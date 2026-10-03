import SwiftUI
import SimuCore
import SimuSimulation

@MainActor public struct ThermalEstimatePanelView:View {
    let store:WorkspaceStore
    let entries:[String:ProjectPackageEntry]
    let input:EstimateWorkspaceInput
    @State private var powerDraft:PowerEstimateDraft?
    @State private var heatDraft:HeatBalanceDraft?
    @State private var tariffDraft:TariffDraft?
    @State private var loadingCost=false
    @State private var costLoadTask:Task<Void,Never>?
    @State private var costLoadID=UUID()
    public init(store:WorkspaceStore,entries:[String:ProjectPackageEntry],input:EstimateWorkspaceInput) { self.store=store;self.entries=entries;self.input=input }
    public var body:some View {
        VStack(alignment:.leading,spacing:12) {
            Text("透明情景估算").font(.headline)
            Text("参考日功率积分与指定工况显热账目。采用配置是冻结值：高级人员/环境/设备条件改变后需要重新导入并采用，不会自动进入本结果。不推算实际账单、逐点室温、PMV或全年节约。").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
            methodCard(.powerEstimate,title:"电量与参考日电费")
            methodCard(.steadyHeatBalance,title:"限定稳态显热")
            if let error=store.estimates.error { Text(error).font(.caption).foregroundStyle(.orange) }
        }
        .onDisappear { costLoadID=UUID();costLoadTask?.cancel();costLoadTask=nil;loadingCost=false }
        .onChange(of:input){_,_ in costLoadID=UUID();costLoadTask?.cancel();costLoadTask=nil;loadingCost=false }
        .sheet(item:$powerDraft){draft in PowerEstimateEditor(draft:draft,registry:store.modelRegistry){edited in
            let configs=try edited.applying(currentProject:store.project,currentScenarioID:store.selectedScenarioID,currentStore:store.analysisConfiguration)
            try store.updateAnalysisConfiguration(configs,actionName:"采用功率情景")
        }}
        .sheet(item:$heatDraft){draft in HeatBalanceEditor(draft:draft){edited in
            let configs=try edited.applying(currentProject:store.project,currentScenarioID:store.selectedScenarioID,currentStore:store.analysisConfiguration)
            try store.updateAnalysisConfiguration(configs,actionName:"采用显热情景")
        }}
        .sheet(item:$tariffDraft){draft in TariffEditor(draft:draft){edited in
            let project=try edited.applying(currentProject:store.project,currentScenarioID:store.selectedScenarioID)
            try store.replaceProject(project,actionName:"修改参考日电价")
        }}
    }
    @ViewBuilder private func methodCard(_ kind:AnalysisKind,title:String)->some View {
        let coordinator=store.estimates.coordinator(kind)
        VStack(alignment:.leading,spacing:6) {
            Text(title).font(.subheadline.bold())
            ViewThatFits(in:.horizontal) {
                HStack { controls(kind) }
                VStack(alignment:.leading) { controls(kind) }
            }
            if store.estimates.validating { Text("正在后台核对当前输入…").font(.caption) }
            if let readiness=store.estimates.readiness[kind],!readiness.blockers.isEmpty {
                DisclosureGroup("待补充 / 不可计算：\(readiness.blockers.count)项") {
                    ForEach(Array(readiness.blockers.enumerated()),id:\.offset){_,issue in Text(issue.message).font(.caption).fixedSize(horizontal:false,vertical:true)}
                }
            }
            if kind == .powerEstimate,let draft=store.estimates.draftSubtotal,!draft.complete {
                Text("草稿已知时段小计 \(draft.payload.knownSubtotalKWh.formatted()) kWh；覆盖 \(draft.coveredMinutes)/\(draft.requestedMinutes) 分钟。完整电量不可用，不能据此报告收益。").font(.caption).foregroundStyle(.secondary)
            }
            if let request=store.estimates.prepared[kind],coordinator.activeIdentity?.inputHash==request.identity.inputHash,let stage=coordinator.stage { Text("任务：\(stageTitle(stage))").font(.caption) }
            if let result=store.estimates.currentResult(kind) {
                Text("方法检查：\(result.checks.state == .passed ? "通过" : "未通过") · 依据：简化情景估算 · 当前输入").font(.caption)
                Text(persistence(coordinator.persistence[result.identity.runID] ?? .notSaved)).font(.caption).foregroundStyle(.secondary)
                switch result.payload {
                case .powerEstimate(let p):
                    Text("请求参考窗口电量：\(p.totalEnergyKWh?.formatted() ?? "待补充") kWh").font(.headline)
                    if let lo=p.lowerEnergyKWh,let hi=p.upperEnergyKWh,lo != hi { Text("已声明情景范围：\(lo.formatted())…\(hi.formatted()) kWh；无概率。").font(.caption) }
                    Text("固定24小时参考口径，分钟区间[start,end)；不是夏令时实际账单日。").font(.caption)
                    HStack {
                        Button("参考日电价"){openTariff(result:result)}
                        Button("评价当前电价"){evaluateCurrentTariff(result:result)}.disabled(loadingCost || store.estimates.evaluatingCost || coordinator.persistence[result.identity.runID] != .saved)
                    }
                    if loadingCost || store.estimates.evaluatingCost { ProgressView("后台费用评价…") }
                    costCard(parent:result)
                case .steadyHeatBalance(let p):
                    Text("带符号显热收支：\(p.totalSignedWatts?.formatted() ?? "待补充") W").font(.headline)
                    Text("正制冷显负荷：\(p.coolingSensibleWatts?.formatted() ?? "待补充") W · \(p.completeness == .declaredSubset ? "指定项子集" : "完整已声明工况")").font(.caption)
                    if let lo=p.lowerCoolingSensibleWatts,let hi=p.upperCoolingSensibleWatts,lo != hi { Text("端点情景包络：\(lo.formatted())…\(hi.formatted()) W；不含概率。").font(.caption) }
                    Text(capacityTitle(p.capacityScreen)).font(.caption)
                    ForEach(p.terms,id:\.id){term in Text("\(term.description)：\(term.signedWatts.formatted()) W").font(.caption)}
                    ForEach(p.notes ?? [],id:\.self){Text($0).font(.caption).foregroundStyle(.secondary)}
                default: EmptyView()
                }
                DisclosureGroup("采用输入、来源与固定Run") {
                    if let configuration=input.configuration?.configuration(scenarioID:result.identity.scenarioID,kind:kind) { adoptedValues(configuration) }
                    Text("Run \(result.identity.runID.uuidString) · inputHash \(result.identity.inputHash)").font(.caption2).textSelection(.enabled)
                }
            } else if coordinator.results.values.contains(where:{$0.identity.scenarioID==input.scenarioID}) {
                Text("旧结果已过期或当前输入待补充；保留历史，不贴到当前方案。请核对配置后重新计算。").font(.caption).foregroundStyle(.secondary)
            }
            if let failure=coordinator.failure,coordinator.activeIdentity?.inputHash==store.estimates.prepared[kind]?.identity.inputHash { Text(failure.reason).font(.caption).foregroundStyle(.orange) }
        }.padding(10).background(.quaternary,in:RoundedRectangle(cornerRadius:10))
    }
    @ViewBuilder private func controls(_ kind:AnalysisKind)->some View {
        Button(kind == .powerEstimate ? "功率与时段" : "显热输入"){open(kind)}
        Button("计算当前情景") { store.estimates.run(kind,persist:persistRun) }.disabled(store.estimates.prepared[kind]==nil || store.estimates.validating)
        Button("取消"){store.estimates.coordinator(kind).stop()}.disabled(store.estimates.coordinator(kind).activeIdentity==nil || store.estimates.coordinator(kind).stage?.isTerminal==true)
    }
    @ViewBuilder private func costCard(parent:LocalAnalysisResult)->some View {
        if let cost=store.estimates.cost,cost.parentIdentity == parent.identity {
            let live=try? currentCostConfiguration(parent:parent)
            let current=live==cost.configuration
            if !current { Text("费用评价已过期；费率/币种已改变，父电量仍可用。").font(.caption).foregroundStyle(.secondary) }
            if current,let amount=cost.payload.totalCostDecimal { Text("参考日窗口费用：\(displayDecimal(amount,digits:cost.configuration.displayFractionDigits)) \(cost.configuration.currency ?? "待补充")；情景估算").font(.headline) }
            else if current { Text("费用待补充；电量仍可用。").font(.caption) }
            if current {
                if let lo=cost.payload.lowerCostDecimal,let hi=cost.payload.upperCostDecimal,lo != hi { Text("已声明费用情景范围：\(displayDecimal(lo,digits:cost.configuration.displayFractionDigits))…\(displayDecimal(hi,digits:cost.configuration.displayFractionDigits)) \(cost.configuration.currency ?? "币种")；无概率。").font(.caption) }
                ForEach(Array(cost.payload.missingReasons.enumerated()),id:\.offset){_,m in Text(m.reason).font(.caption)}
                Text(persistence(store.estimates.costPersistence)).font(.caption).foregroundStyle(.secondary)
            }
            DisclosureGroup("固定费用片段与来源") {
                ForEach(Array(cost.payload.segments.enumerated()),id:\.offset){_,s in
                    Text("\(s.startMinute)…\(s.endMinute) min · \(s.energyKWhDecimal) kWh × \(s.rateDecimal) \(cost.configuration.currency ?? "币种")/kWh = \(s.costDecimal)").font(.caption)
                    Text(source(s.source)).font(.caption2).textSelection(.enabled)
                }
                Text("排除：\(cost.configuration.excludedCosts.joined(separator:"、"))；不另加未知税费，不外推年度收益。").font(.caption)
                Text("固定未格式化总额：\(cost.payload.totalCostDecimal ?? "待补充") · 只最终显示舍入，非账单结算规则。").font(.caption2)
                Text(cost.payload.decimalPolicy).font(.caption2)
                Text("父Run \(cost.parentIdentity.runID.uuidString) · evaluationHash \(cost.evaluationHash)").font(.caption2)
            }
        } else { Text("费用未评价；请明确电价/币种。未知费用不显示为0。").font(.caption).foregroundStyle(.secondary) }
    }
    private func displayDecimal(_ text:String,digits:Int)->String {
        guard let value=Decimal(string:text,locale:Locale(identifier:"en_US_POSIX")) else { return "待补充" }
        let formatter=NumberFormatter();formatter.numberStyle = .decimal;formatter.minimumFractionDigits=digits;formatter.maximumFractionDigits=digits;formatter.roundingMode = .halfEven
        return formatter.string(from:NSDecimalNumber(decimal:value)) ?? text
    }
    private func source(_ s:SourceRecord)->String { "来源 \(InputDisplay.source(s.kind)) · \(s.reference ?? "用户录入") · \(s.note ?? "")" }
    @ViewBuilder private func adoptedValues(_ config:AnalysisConfiguration)->some View {
        switch config.payload {
        case .powerEstimate(let p):
            ForEach(Array(p.intervals.enumerated()),id:\.offset){_,i in
                Text("\(InputDisplay.clock(String(i.startMinute)))–\(InputDisplay.clock(String(i.endMinute))) · \(i.power.value?.formatted() ?? "未知") W · \(InputDisplay.powerBasis(i.basis))").font(.caption)
                if case .known(_,let s,_)=i.power { Text(source(s)).font(.caption2).textSelection(.enabled) }
                if let period=i.measurementPeriod { Text("测量时段："+period).font(.caption) }
            }
            if let scope=p.aggregateCoverageNote { Text("合计覆盖："+scope).font(.caption) }
        case .steadyHeatBalance(let p):
            Text("代表时刻\(InputDisplay.clock(String(p.conditionMinute))) · UA：\(p.coverage?.conductanceScope ?? "待声明") · 内部：\(p.coverage?.internalSensibleScope ?? "待声明") · 空气条件：\(p.coverage?.airPropertyConditions ?? "待声明")").font(.caption)
            ForEach(ThermalEstimateValidation.heatTerms+["indoorTemperature","outdoorTemperature","density","specificHeat"],id:\.self){f in
                if let v=ThermalEstimateValidation.heatParameter(p,field:f) { Text("\(heatFieldTitle(f))：\(v.value?.formatted() ?? "未知") \(v.unit)").font(.caption);if let s=v.source { Text(source(s)).font(.caption2).textSelection(.enabled) } }
            }
            ForEach(p.internalSources ?? [],id:\.entityID){entry in
                Text("冻结内部源 \(entry.entityID.uuidString) · \(entry.description)").font(.caption)
                parameterEvidence("源总显热",entry.sensible);parameterEvidence("代表时段有效比例",entry.effectiveFraction)
            }
            if let capacity=p.sensibleCoolingCapacity { parameterEvidence("直接显热能力",capacity) }
            if let capacity=p.totalCoolingCapacity { parameterEvidence("总制冷能力",capacity) }
            if let shr=p.sensibleHeatRatio { parameterEvidence("SHR",shr) }
            if let result=store.estimates.currentResult(.steadyHeatBalance),case .steadyHeatBalance(let value)=result.payload {
                ForEach(value.scenarios ?? [],id:\.id){scenario in
                    Text("情景\(scenario.id)：Q_signed \(scenario.totalSignedWatts.formatted()) W · Q_cooling \(scenario.coolingSensibleWatts.formatted()) W").font(.caption)
                    ForEach(scenario.adoptedValues,id:\.field){v in Text("采用\(v.field)=\(v.value.formatted()) \(v.unit) · \(source(v.source))").font(.caption2)}
                }
            }
            ForEach(p.exclusions ?? [],id:\.term){Text("明确排除\($0.term)：\($0.reason)").font(.caption)}
        default: EmptyView()
        }
    }
    @ViewBuilder private func parameterEvidence<Q>(_ title:String,_ p:PhysicalParameter<Q>)->some View {
        Text("\(title)：\(p.value?.formatted() ?? "未知") \(Q.unit)").font(.caption)
        if case .known(_,let s,let bounds)=p { Text(source(s)).font(.caption2).textSelection(.enabled);if let b=bounds {Text("采用范围\(b.lower.formatted())…\(b.upper.formatted()) \(Q.unit) · \(b.meaning)").font(.caption)} }
    }
    private func capacityTitle(_ c:SensibleCapacityScreen)->String { switch c { case .sufficientForDeclaredSensibleCase:"已声明代表工况显热容量账面覆盖；不代表全制冷选型或舒适通过。";case .insufficientForDeclaredSensibleCase:"已声明代表工况显热容量账面不足。";case .cannotEvaluate:"容量不可筛查：缺显热/SHR依据、负荷/能力范围重叠或存在排除项。" } }
    private func stageTitle(_ stage:LocalAnalysisStage)->String {
        switch stage {
        case .accepted:"已接受"
        case .validating:"验证输入"
        case .running,.progress:"计算情景"
        case .checking:"方法检查"
        case .completed:"计算完成"
        case .failed:"失败"
        case .cancelled:"已取消"
        }
    }
    private func persistence(_ p:AnalysisPersistenceState)->String { switch p { case .saved:"已加入项目；写盘由文档保存负责。";case .notSaved:"尚未加入项目。";case .failed(let reason):"结果未保存："+reason } }
    private func open(_ kind:AnalysisKind) { guard let project=store.project,let id=store.selectedScenarioID else{return};if kind == .powerEstimate { powerDraft = .init(project:project,scenarioID:id,store:store.analysisConfiguration) } else { heatDraft = .init(project:project,scenarioID:id,store:store.analysisConfiguration) } }
    private func persistRun(_ a:NativeAnalysisArtifact)throws { guard let write=store.persistNativeAnalysis else{throw NativeArtifactError.unsupportedRecord};try write(a) }
    private func persistCost(_ a:NativeCostEvaluationArtifact)throws { guard let write=store.persistCostEvaluation else{throw NativeArtifactError.unsupportedRecord};try write(a) }
    private func currentCostConfiguration(parent:LocalAnalysisResult)throws -> CostEvaluationConfiguration {
        guard let project=store.project,let id=store.selectedScenarioID,
              id==parent.identity.scenarioID,let scenario=project.scenarios.first(where:{$0.id==id}),case .powerEstimate(let p)=parent.payload else { throw WorkspaceEditingError.noScenario }
        let cost=scenario.evaluation.cost
        return .init(requestedWindows:p.requestedWindows,currency:cost.currency,tariffs:cost.tariffs.map{.init(startMinute:$0.startMinute,endMinute:$0.endMinute,rate:$0.rate)})
    }
    private func openTariff(result:LocalAnalysisResult) {
        guard let project=store.project,let id=store.selectedScenarioID,let request=store.estimates.prepared[.powerEstimate] else{return}
        // Only input/configuration is used by the editor; cost calculation loads the actual parent run separately.
        tariffDraft = .init(project:project,scenarioID:id,parent:request)
    }
    private func evaluateCurrentTariff(result:LocalAnalysisResult) {
        guard let project=store.project,let config=try? currentCostConfiguration(parent:result) else{return}
        let entries=entries;loadingCost=true
        costLoadTask?.cancel();costLoadID=UUID();let token=costLoadID
        let instance=store.documentInstanceID,revision=store.nativeSidefileRevision
        costLoadTask=Task {
            defer {if costLoadID==token{loadingCost=false;costLoadTask=nil}}
            do {
                let worker=Task.detached{try NativeArtifactCodec().load(runID:result.identity.runID,entries:entries,projectID:project.id)}
                let parent=try await withTaskCancellationHandler(operation:{try await worker.value},onCancel:{worker.cancel()})
                guard !Task.isCancelled,costLoadID==token,store.project==project,store.estimates.currentResult(.powerEstimate)?.identity==result.identity else{return}
                try store.validateNativeDocumentContext(instanceID:instance,sidefileRevision:revision)
                store.estimates.evaluateCost(configuration:config,parent:parent,entries:entries,persist:persistCost)
            } catch { if !Task.isCancelled,costLoadID==token {store.presentedError=error.localizedDescription} }
        }
    }
}
private struct PowerEstimateEditor:View {
    @State var draft:PowerEstimateDraft
    let registry:ModelRegistry
    let apply:@MainActor (PowerEstimateDraft)throws->Void
    @State private var error:String?
    @SwiftUI.Environment(\.dismiss) private var dismiss
    var body:some View { NavigationStack { EditorForm {
        Text("单位W为电输入功率；制冷量/COP不采用。未覆盖或未知不是停机。跨午夜输入会拆成两段半开窗口；固定24h参考，不是实际账单日。")
        EditorSection("请求窗口 · 参考日时钟") {
            ForEach($draft.windows){$w in HStack{ClockMinuteField(title:"开始",text:$w.startText);ClockMinuteField(title:"结束",text:$w.endText);Button("删除窗口"){draft.windows.removeAll{$0.id==w.id}}}}
            Button("增加请求窗口"){draft.windows.append(.init())}
        }
        EditorSection("功率片段；停机需明确0 W") {
            ForEach($draft.intervals){$i in VStack(alignment:.leading){
                HStack{ClockMinuteField(title:"开始",text:$i.startText);ClockMinuteField(title:"结束",text:$i.endText)}
                PhysicalParameterEditor("电输入功率",draft:$i.parameter,quantity:ElectricalPowerTag.self,range:.nonnegative)
                Picker("功率依据",selection:$i.basis){Text("请选择口径").tag(Optional<ElectricalPowerBasis>.none);ForEach(ElectricalPowerBasis.allCases,id:\.self){Text(InputDisplay.powerBasis($0)).tag(Optional($0))}}
                TextField("实测日期/采样时段/适用范围",text:$i.measurementPeriod,axis:.vertical)
                Button("删除功率片段"){draft.intervals.removeAll{$0.id==i.id}}
            }}
            Button("增加功率片段"){draft.intervals.append(.init())}
            Button("从设备电功率导入草稿"){do{try draft.importElectricalPower(registry:registry)}catch{self.error=error.localizedDescription}}
            Toggle("明确采用额定输入功率连续运行情景",isOn:$draft.ratedConfirmed)
            Toggle("明确合计电功率覆盖当前全部设备",isOn:$draft.aggregateCoverageConfirmed)
            if draft.aggregateCoverageConfirmed {TextField("合计覆盖与来源说明",text:$draft.aggregateNote,axis:.vertical)}
        }
        if let error {Text(error).foregroundStyle(.red)}
    }.navigationTitle("功率与时段").toolbar{ToolbarItem(placement:.cancellationAction){Button("取消"){dismiss()}};ToolbarItem(placement:.confirmationAction){Button("采用配置"){do{try apply(draft);dismiss()}catch{self.error=error.localizedDescription}}}}
    .modifier(EditorSheetSize())
    } }
}
private struct HeatBalanceEditor:View {
    @State var draft:HeatBalanceDraft
    let apply:@MainActor (HeatBalanceDraft)throws->Void
    @State private var error:String?
    @SwiftUI.Environment(\.dismiss) private var dismiss
    var body:some View { NavigationStack { EditorForm {
        Text("采用有明确依据的合计热导（UA）；不会由未齐备的围护参数推测。室内温度为所采用的情景；排除室内循环风与潜热，各显热源只计一次。")
        ClockMinuteField(title:"代表时刻",text:$draft.conditionMinuteText)
        Toggle("明确采用室内温度为估算条件，未声称已达室温",isOn:$draft.indoorConfirmed)
        TextField("UA覆盖范围",text:$draft.conductanceScope,axis:.vertical)
        TextField("内部显热覆盖清单/合计范围",text:$draft.internalScope,axis:.vertical)
        TextField("空气密度/比热的适用温度条件",text:$draft.airConditions,axis:.vertical)
        TextField("覆盖来源/说明",text:$draft.scopeReference,axis:.vertical)
        parameter("conductance","合计UA",HeatConductanceTag.self,.nonnegative)
        parameter("indoorTemperature","室内情景Tin",TemperatureTag.self,.init(minimum:-100,maximum:100))
        parameter("outdoorTemperature","室外Tout",TemperatureTag.self,.init(minimum:-100,maximum:100))
        parameter("outdoorAir","独立室外新风",VolumeFlowTag.self,.nonnegative)
        parameter("infiltration","独立渗风",VolumeFlowTag.self,.nonnegative)
        parameter("density","空气密度ρ",DensityTag.self,.positive)
        parameter("specificHeat","空气比热cp",SpecificHeatTag.self,.positive)
        parameter("internalSensibleHeat","内部总显热",ThermalPowerTag.self,.nonnegative)
        Button("明确冻结当前人员/设备显热与有效比例清单"){do{try draft.importInternalSources()}catch{self.error=error.localizedDescription}}
        if let sources=draft.internalSources {Text("已冻结\(sources.count)项内部总显热；修改合计需与清单一致。");Button("改用显式合计口径，清除清单"){draft.internalSources=nil}}
        parameter("solarSensibleHeat","太阳显热",ThermalPowerTag.self,.nonnegative)
        EditorSection("明确排除项；子集不能作完整容量筛查") { ForEach(ThermalEstimateValidation.heatTerms,id:\.self){field in
            Toggle("排除 \(field)",isOn:Binding(get:{draft.exclusions[field] != nil},set:{if $0{draft.exclusions[field]=""}else{draft.exclusions.removeValue(forKey:field)}}))
            if draft.exclusions[field] != nil {TextField("排除理由",text:Binding(get:{draft.exclusions[field] ?? ""},set:{draft.exclusions[field]=$0}),axis:.vertical)}
        }}
        EditorSection("显热能力或有依据总能力×SHR，可保持未知") {
            parameter("sensibleCoolingCapacity","直接显热能力",ThermalPowerTag.self,.nonnegative)
            parameter("totalCoolingCapacity","总制冷能力",ThermalPowerTag.self,.nonnegative)
            parameter("sensibleHeatRatio","SHR（未知不能取1）",RatioTag.self,.fraction)
        }
        EditorSection("范围：最多2个采用输入、4个端点+名义") {
            Picker("区间关系",selection:$draft.sensitivityRelationship){Text("相关性未知，端点情景包络").tag("unknownDependenceEnvelope");Text("有依据的独立端点情景").tag("independentEndpointScenarios")}
            TextField("区间关系/端点范围来源与局限",text:$draft.sensitivityExplanation,axis:.vertical)
        }
        if let error {Text(error).foregroundStyle(.red)}
    }.navigationTitle("显热情景输入").toolbar{ToolbarItem(placement:.cancellationAction){Button("取消"){dismiss()}};ToolbarItem(placement:.confirmationAction){Button("采用配置"){do{try apply(draft);dismiss()}catch{self.error=error.localizedDescription}}}}
    .modifier(EditorSheetSize())
    } }
    private func parameter<Q:QuantityTag>(_ field:String,_ title:String,_ tag:Q.Type,_ range:ParameterValueRange)->some View { PhysicalParameterEditor(title,draft:Binding(get:{draft.parameters[field] ?? .init()},set:{draft.parameters[field]=$0}),quantity:tag,range:range) }
}
private struct TariffEditor:View {
    @State var draft:TariffDraft
    let apply:@MainActor (TariffDraft)throws->Void
    @State private var error:String?
    @SwiftUI.Environment(\.dismiss) private var dismiss
    var body:some View { NavigationStack { EditorForm {
        Text("费用评价固定电量run。币种或费率未知时不生成费用数值；不换汇，不补税费、设备报价或年度收益。")
        EditorTextField(title:"币种代码，例如 EUR / CNY",text:$draft.currency)
        ForEach($draft.tariffs){$i in VStack{
            HStack{ClockMinuteField(title:"开始",text:$i.startText);ClockMinuteField(title:"结束",text:$i.endText)}
            PhysicalParameterEditor("费率（币种/kWh）",draft:$i.parameter,quantity:EnergyRateTag.self,range:.nonnegative)
            Button("删除费率片段"){draft.tariffs.removeAll{$0.id==i.id}}
        }}
        Button("增加费率片段"){draft.tariffs.append(.init())}
        Text("费用仅作单位消费费率情景；订阅、设备和安装费用不在合计内。来源若已含税，不额外加假税。")
        if let error {Text(error).foregroundStyle(.red)}
    }.navigationTitle("参考日电价").toolbar{ToolbarItem(placement:.cancellationAction){Button("取消"){dismiss()}};ToolbarItem(placement:.confirmationAction){Button("应用费率"){do{try apply(draft);dismiss()}catch{self.error=error.localizedDescription}}}}
    .modifier(EditorSheetSize())
    } }
}
