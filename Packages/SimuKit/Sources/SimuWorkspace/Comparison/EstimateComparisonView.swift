import SwiftUI
import SimuCore
import SimuSimulation

public struct EstimateComparisonBuildInput:Equatable,Sendable {
    public let project:ProjectDocument?
    public let configuration:AnalysisConfigurationStore?
    public let entries:[String:ProjectPackageEntry]
    public let revision:UUID
    public let baselineID:UUID?
    public let candidateID:UUID?
    public let kind:AnalysisKind
    public let decisionVariables:[String]
    public let additionalIssues:[ValidationIssue]
}
public enum EstimateComparisonBuilder {
    public static func build(_ input:EstimateComparisonBuildInput,registry:ModelRegistry = .builtIn) throws -> ComparisonSnapshot {
        guard let project=input.project,let b=input.baselineID,let c=input.candidateID,b != c else { throw ProjectDataError.contract("选择不同的基准与候选。") }
        let index=NativeArtifactCodec(registry:registry).index(entries:input.entries,projectID:project.id)
        func evidence(_ id:UUID)throws -> FixedEstimateEvidence {
            guard let config=input.configuration?.configuration(scenarioID:id,kind:input.kind) else { throw ProjectDataError.contract("方案缺少此方法配置。") }
            let current=try AnalysisInputResolver(registry:registry).request(project:project,scenarioID:id,method:.init(kind:input.kind),configuration:config,additionalIssues:input.additionalIssues)
            var parent:NativeAnalysisArtifact?
            for file in index.filter({$0.scenarioID==id}) {
                try Task.checkCancellation()
                guard let run=try? NativeArtifactCodec(registry:registry).load(runID:file.id,entries:input.entries,projectID:project.id),run.request.method.kind==input.kind,run.request.identity.inputHash==current.identity.inputHash,run.result.checks.state == .passed else { continue }
                // Stable order, not completion-time inference; all matching runs compute the same current input.
                parent=run;break
            }
            guard let parent else { throw ProjectDataError.contract("无已保存、当前输入匹配的方法run；先切换此方案计算并保存。") }
            var cost:CostEvaluationRecord?
            if input.kind == .powerEstimate,case .powerEstimate(let p)=parent.result.payload,let scenario=project.scenarios.first(where:{$0.id==id}) {
                let configuration=CostEvaluationConfiguration(requestedWindows:p.requestedWindows,currency:scenario.evaluation.cost.currency,tariffs:scenario.evaluation.cost.tariffs.map{.init(startMinute:$0.startMinute,endMinute:$0.endMinute,rate:$0.rate)})
                let hash=try AnalysisHasher(registry:registry).evaluationHash(identity:parent.result.identity,evaluationConfiguration:JSONTreeCoding.encode(configuration))
                cost=try? NativeCostEvaluationCodec.load(hash:hash,parent:parent,entries:input.entries)
            }
            return .init(request:parent.request,result:parent.result,currentInputHash:current.identity.inputHash,cost:cost)
        }
        return try EstimateComparator.compare(baseline:evidence(b),candidate:evidence(c),decisionVariables:input.decisionVariables)
    }
}
@MainActor public struct EstimateComparisonView:View {
    let store:WorkspaceStore
    let entries:[String:ProjectPackageEntry]
    let revision:UUID
    let additionalIssues:[ValidationIssue]
    @State private var baselineID:UUID?
    @State private var candidateID:UUID?
    @State private var kind:AnalysisKind = .powerEstimate
    @State private var decisions:Set<String>=["powerIntervals"]
    @State private var snapshot:ComparisonSnapshot?
    @State private var saved = false
    @State private var error:String?
    @State private var busy=false
    @State private var buildTask:Task<Void,Never>?
    @State private var buildID=UUID()
    public init(store:WorkspaceStore,entries:[String:ProjectPackageEntry],revision:UUID,additionalIssues:[ValidationIssue]=[]) { self.store=store;self.entries=entries;self.revision=revision;self.additionalIssues=additionalIssues }
    private var input:EstimateComparisonBuildInput { .init(project:store.project,configuration:store.analysisConfiguration,entries:entries,revision:revision,baselineID:baselineID ?? store.baselineScenarioID,candidateID:candidateID ?? store.selectedScenarioID,kind:kind,decisionVariables:decisions.sorted(),additionalIssues:additionalIssues) }
    public var body:some View {
        VStack(alignment:.leading,spacing:8) {
            Text("固定情景估算比较").font(.headline)
            Text("从项目保存的固定run读取证据，检查当前hash与口径。范围重叠不标最佳；零基准百分比不可定义。角度本身不给节电差。").font(.caption).foregroundStyle(.secondary)
            Picker("方法",selection:$kind){Text("电量 / 已保存费用").tag(AnalysisKind.powerEstimate);Text("显热").tag(AnalysisKind.steadyHeatBalance)}
            DisclosureGroup("明确比较决策变量：\(decisions.sorted().joined(separator:"、"))") {
                ForEach(kind == .powerEstimate ? ["powerIntervals"] : ["conductance","indoorTemperature","outdoorTemperature","outdoorAir","infiltration","internalSensibleHeat","solarSensibleHeat"],id:\.self){field in
                    Toggle("明确改变\(field == "powerIntervals" ? "电功率与时段" : heatFieldTitle(field))",isOn:Binding(get:{decisions.contains(field)},set:{if $0{decisions.insert(field)}else{decisions.remove(field)}}))
                }
                Text("未选字段作为背景，差异会阻断改善比较；这里是情景声明，不保证实际收益。").font(.caption)
            }
            if let project=store.project {
                Picker("基准",selection:Binding(get:{baselineID ?? store.baselineScenarioID},set:{baselineID=$0})){ForEach(project.scenarios,id:\.id){Text($0.name).tag(Optional($0.id))}}
                Picker("候选",selection:Binding(get:{candidateID ?? store.selectedScenarioID},set:{candidateID=$0})){ForEach(project.scenarios,id:\.id){Text($0.name).tag(Optional($0.id))}}
            }
            Button("冻结、比较并保存到项目"){build()}.disabled(busy || input.baselineID==input.candidateID)
            if busy {ProgressView("后台核对固定run…")}
            if let error {Text(error).font(.caption).foregroundStyle(.orange)}
            if let snapshot {
                ForEach(snapshot.metrics ?? [],id:\.metric){m in VStack(alignment:.leading){
                    Text("\(metricTitle(m.metric))：基准 \(m.baseline?.formatted() ?? "未知") / 候选 \(m.candidate?.formatted() ?? "未知") \(m.unit)").font(.caption)
                    if let delta=m.absoluteDifference {Text("名义绝对差（候选−基准）：\(delta.formatted()) \(m.unit)").font(.caption)}
                    if let percent=m.percentDifference {Text("同口径名义差：\(percent.formatted()) %；不是保证收益。").font(.caption)}
                    Text("排序依据："+comparisonRankingTitle(m.ranking)).font(.caption)
                    ForEach(m.reasons,id:\.self){Text($0).font(.caption).foregroundStyle(.secondary)}
                }}
                ForEach(Array(snapshot.incomparableReasons.enumerated()),id:\.offset){_,reason in Text(reason.reason).font(.caption).foregroundStyle(.secondary)}
                Text("Comparison \(snapshot.comparisonID.uuidString) · \(saved ? "固定比较已保存到项目" : "当前仅在会话中，尚未保存")").font(.caption2)
            }
        }.onChange(of:kind){_,value in decisions = value == .powerEstimate ? ["powerIntervals"]:[] }
        .onDisappear {buildTask?.cancel();buildID=UUID();busy=false}
        .onChange(of:input){_,_ in buildTask?.cancel();buildID=UUID();busy=false;if snapshot != nil {error="项目已更新；下方仍为原固定比较。重新冻结可比较当前输入。"}}
    }
    private func build() {
        let frozen=input,registry=store.modelRegistry,instance=store.documentInstanceID;busy=true;error=nil;saved=false
        buildTask?.cancel();buildID=UUID();let token=buildID
        buildTask=Task { defer{if buildID==token{busy=false}};do {
            let worker=Task.detached{
                let snapshot = try EstimateComparisonBuilder.build(frozen,registry:registry)
                return try FixedComparisonArtifacts.make(snapshot, entries: frozen.entries)
            }
            let value=try await withTaskCancellationHandler(operation:{try await worker.value},onCancel:{worker.cancel()})
            guard !Task.isCancelled,buildID==token,input==frozen else{return}
            try store.validateNativeDocumentContext(instanceID:instance,sidefileRevision:frozen.revision)
            snapshot=value.record.snapshot
            guard let persist = store.persistComparison else { throw NativeArtifactError.unsupportedRecord }
            try persist(value); saved=true
        }catch{if !Task.isCancelled,buildID==token{self.error=error.localizedDescription}} }
    }
    private func metricTitle(_ key: String) -> String {
        switch key { case "energy": "声明时段电量"; case "referenceCost": "声明时段费用"; case "coolingSensible": "工况显热需求"; default: key }
    }
}
