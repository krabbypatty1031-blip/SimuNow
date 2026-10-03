import Foundation
import Observation
import SimuCore
import SimuSimulation

public struct EstimateWorkspaceInput: Equatable, Sendable {
    public let project:ProjectDocument?
    public let scenarioID:UUID?
    public let configuration:AnalysisConfigurationStore?
    public let additionalIssues:[ValidationIssue]
    public init(project:ProjectDocument?,scenarioID:UUID?,configuration:AnalysisConfigurationStore?,additionalIssues:[ValidationIssue]=[]) { self.project=project;self.scenarioID=scenarioID;self.configuration=configuration;self.additionalIssues=additionalIssues }
}
@MainActor @Observable
public final class ThermalEstimateCoordinator {
    public let power:AnalysisCoordinator
    public let heat:AnalysisCoordinator
    public private(set) var prepared:[AnalysisKind:LocalAnalysisRequest]=[:]
    public private(set) var readiness:[AnalysisKind:AnalysisReadiness]=[:]
    public private(set) var draftSubtotal:PowerDraftSubtotal?
    public private(set) var validating=false
    public private(set) var cost:CostEvaluationRecord?
    public private(set) var costPersistence:AnalysisPersistenceState = .notSaved
    public private(set) var evaluatingCost=false
    public private(set) var error:String?
    @ObservationIgnored private var validationTask:Task<Void,Never>?
    @ObservationIgnored private var costTask:Task<Void,Never>?
    @ObservationIgnored private var input:EstimateWorkspaceInput?
    @ObservationIgnored private var generation=UUID()
    public init(client:any LocalAnalysisSubmitting) { power=AnalysisCoordinator(client:client);heat=AnalysisCoordinator(client:client) }
    deinit { validationTask?.cancel();costTask?.cancel() }
    public func coordinator(_ kind:AnalysisKind)->AnalysisCoordinator { kind == .steadyHeatBalance ? heat:power }
    public func restoreFixedCost(_ record: CostEvaluationRecord) {
        guard !evaluatingCost else { return }
        cost = record; costPersistence = .saved
    }
    public func currentResult(_ kind:AnalysisKind)->LocalAnalysisResult? {
        guard !validating,let request=prepared[kind] else { return nil }
        return coordinator(kind).result(scenarioID:request.identity.scenarioID,inputHash:request.identity.inputHash)
    }
    public func update(_ next:EstimateWorkspaceInput,registry:ModelRegistry) {
        guard input != next else { return }
        input=next;generation=UUID();let token=generation
        validationTask?.cancel();costTask?.cancel();evaluatingCost=false
        power.stop();heat.stop();prepared=[:];readiness=[:];draftSubtotal=nil;validating=true;error=nil
        let worker=Task.detached { () -> ([AnalysisKind:LocalAnalysisRequest],[AnalysisKind:AnalysisReadiness],PowerDraftSubtotal?) in
            guard let project=next.project,let id=next.scenarioID else { return ([:],[:],nil) }
            var requests:[AnalysisKind:LocalAnalysisRequest]=[:],reports:[AnalysisKind:AnalysisReadiness]=[:],subtotal:PowerDraftSubtotal?
            for kind in [AnalysisKind.powerEstimate,.steadyHeatBalance] {
                if Task.isCancelled { return ([:],[:],nil) }
                let config=next.configuration?.configuration(scenarioID:id,kind:kind)
                let report=AnalysisReadinessEvaluator(registry:registry).evaluate(project:project,scenarioID:id,capability:AnalysisCapability(rawValue:kind.rawValue)!,configuration:config,additionalIssues:next.additionalIssues)
                reports[kind]=report
                if report.eligible,let config { requests[kind]=try? AnalysisInputResolver(registry:registry).request(project:project,scenarioID:id,method:.init(kind:kind),configuration:config,additionalIssues:next.additionalIssues) }
                if case .powerEstimate(let c)=config?.payload { subtotal=try? PowerIntegrator.draft(c,deviceIDs:project.scenarios.first{$0.id==id}?.inputs.hvac.map(\.id) ?? []) }
            }
            return (requests,reports,subtotal)
        }
        validationTask=Task { [weak self] in
            let values=await withTaskCancellationHandler(operation:{await worker.value},onCancel:{worker.cancel()})
            guard let self,!Task.isCancelled,self.generation==token else { return }
            self.prepared=values.0;self.readiness=values.1;self.draftSubtotal=values.2;self.validating=false
        }
    }
    public func run(_ kind:AnalysisKind,persist:@escaping @MainActor @Sendable (NativeAnalysisArtifact)throws->Void) {
        guard let request=prepared[kind],!validating else { return }
        let fresh=LocalAnalysisRequest(identity:.init(runID:UUID(),scenarioID:request.identity.scenarioID,inputHash:request.identity.inputHash),method:request.method,resolvedInput:request.resolvedInput,snapshotHash:request.snapshotHash,computationHash:request.computationHash,limits:request.limits)
        prepared[kind]=fresh
        coordinator(kind).start(fresh,persist:persist)
    }
    public func evaluateCost(configuration:CostEvaluationConfiguration,parent:NativeAnalysisArtifact,entries:[String:ProjectPackageEntry] = [:],persist:@escaping @MainActor @Sendable (NativeCostEvaluationArtifact)throws->Void) {
        costTask?.cancel();let token=generation;evaluatingCost=true;error=nil;costPersistence = .notSaved
        let worker=Task.detached { () throws -> (CostEvaluationRecord,NativeCostEvaluationArtifact?,String?) in
            try Task.checkCancellation()
            let record=try CostEvaluator.evaluate(request:parent.request,result:parent.result,configuration:configuration)
            try Task.checkCancellation()
            do { return (record,try NativeCostEvaluationCodec.make(record,parent:parent,entries:entries),nil) }
            catch { return (record,nil,String(describing:error)) }
        }
        costTask=Task { [weak self] in
            do {
                let value=try await withTaskCancellationHandler(operation:{try await worker.value},onCancel:{worker.cancel()})
                guard let self,!Task.isCancelled,self.generation==token else { return }
                self.cost=value.0
                if let artifact=value.1 { do { try persist(artifact);self.costPersistence = .saved } catch { self.costPersistence = .failed(String(describing:error)) } }
                else { self.costPersistence = .failed(value.2 ?? "费用记录超出保存支持范围") }
            } catch { if !Task.isCancelled,self?.generation==token { self?.error=String(describing:error) } }
            if self?.generation==token { self?.evaluatingCost=false }
        }
    }
    public func stop() { generation=UUID();validationTask?.cancel();costTask?.cancel();validationTask=nil;costTask=nil;validating=false;evaluatingCost=false;power.stop();heat.stop();input=nil;prepared=[:] }
    public func resetSession() {
        stop()
        power.resetSession();heat.resetSession()
        readiness=[:];draftSubtotal=nil;cost=nil;costPersistence = .notSaved;error=nil
    }
}
