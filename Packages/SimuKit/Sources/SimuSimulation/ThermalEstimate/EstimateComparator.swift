import Foundation
import SimuCore

public struct FixedEstimateEvidence: Equatable, Sendable {
    public let request: LocalAnalysisRequest
    public let result: LocalAnalysisResult
    public let currentInputHash: String?
    public let cost: CostEvaluationRecord?
    public init(request: LocalAnalysisRequest, result: LocalAnalysisResult, currentInputHash: String?, cost: CostEvaluationRecord? = nil) {
        self.request=request;self.result=result;self.currentInputHash=currentInputHash;self.cost=cost
    }
}
public enum EstimateComparator {
    /// Pure fixed evidence. A missing current hash is explicitly stale/unverifiable.
    public static func compare(baseline b:FixedEstimateEvidence,candidate c:FixedEstimateEvidence,decisionVariables:[String],comparisonID:UUID=UUID()) throws -> ComparisonSnapshot {
        var reasons:[AnalysisMissingReason]=[]
        func reject(_ code:String,_ message:String) { reasons.append(.init(code:code,fieldPath:"comparison",reason:message)) }
        let knownVariables=Set(["powerIntervals","direction","conductance","indoorTemperature","outdoorTemperature","outdoorAir","infiltration","internalSensibleHeat","solarSensibleHeat"])
        guard Set(decisionVariables).count == decisionVariables.count,Set(decisionVariables).isSubset(of:knownVariables) else { throw ProjectDataError.contract("Unsupported comparison decision variable") }
        for e in [b,c] {
            try AnalysisInputResolver().validate(e.request);try NativeAnalysisCodec().validateResult(e.result)
            guard e.request.identity == e.result.identity,e.request.method == e.result.method else { throw ProjectDataError.contract("Fixed comparison identity mismatch") }
            try ThermalEstimateEvidenceValidation.validate(request:e.request,result:e.result)
            if e.result.checks.state != .passed || !e.result.missingReasons.isEmpty { reject("checks_missing","方法检查未通过或结果缺项，不能比较改善。") }
            if e.currentInputHash != e.request.identity.inputHash { reject("stale_run","固定run相对当前输入过期或新鲜度未验证。") }
            if let cost=e.cost { try CostEvaluator.validate(cost,parent:.init(request:e.request,result:e.result)) }
        }
        if b.request.resolvedInput.snapshot.projectID != c.request.resolvedInput.snapshot.projectID { reject("project_mismatch","项目身份不同。") }
        if b.request.method != c.request.method { reject("method_mismatch","方法或版本不同，不能同口径比较。") }
        var metrics:[EstimateComparisonMetric]=[]
        func metric(_ name:String,_ unit:String,_ bv:Double?,_ cv:Double?,_ blo:Double?,_ bhi:Double?,_ clo:Double?,_ chi:Double?) {
            var text=reasons.map(\.reason)
            if bv==nil || cv==nil { text.append("完整值缺失，不能给出改善差。") }
            let ranking:String
            if !reasons.isEmpty { ranking="cannotRank" }
            else if let bv,let cv,let blo,let bhi,let clo,let chi {
                if bv==cv && blo==clo && bhi==chi { ranking="sameDeclaredEstimate" }
                else if blo<=chi && clo<=bhi { ranking="overlapNoStableRanking";text.append("端点情景范围重叠或排序可能翻转，无法稳定排序。") }
                else { ranking="disjointDeclaredEnvelopes" }
            } else { ranking="cannotRank" }
            let difference=(text.isEmpty && bv != nil && cv != nil) ? cv!-bv!:nil
            let percent=(difference != nil && bv != 0) ? difference!/abs(bv!)*100:nil
            if bv==0 { text.append("零基准的百分比不可定义。") }
            metrics.append(.init(metric:name,unit:unit,baseline:bv,candidate:cv,absoluteDifference:difference,percentDifference:percent,reasons:text,ranking:ranking))
        }
        switch (b.result.payload,c.result.payload,b.request.resolvedInput.configuration.payload,c.request.resolvedInput.configuration.payload) {
        case (.powerEstimate(let bp),.powerEstimate(let cp),.powerEstimate(let bc),.powerEstimate(let cc)):
            if bp.timeBasis != cp.timeBasis || bp.requestedWindows != cp.requestedWindows { reject("window_mismatch","参考时间口径或请求窗口不同。") }
            let boundaries=Set(bp.requestedWindows.flatMap{[$0.startMinute,$0.endMinute]}+bc.intervals.flatMap{[$0.startMinute,$0.endMinute]}+cc.intervals.flatMap{[$0.startMinute,$0.endMinute]}).sorted()
            for (start,end) in zip(boundaries,boundaries.dropFirst()) where bp.requestedWindows.contains(where:{$0.startMinute<=start && $0.endMinute>=end}) {
                let bi=bc.intervals.first{$0.startMinute<=start && $0.endMinute>=end},ci=cc.intervals.first{$0.startMinute<=start && $0.endMinute>=end}
                if bi?.basis != ci?.basis { reject("basis_mismatch","采用时段功率basis不同，不表示同口径实测改善。") }
                if bi?.power != ci?.power && !decisionVariables.contains("powerIntervals") { reject("undeclared_power_change","功率值/范围/来源改变但未声明powerIntervals决策变量。") }
            }
            if Set(b.request.resolvedInput.snapshot.inputs.hvac.map(\.id)) != Set(c.request.resolvedInput.snapshot.inputs.hvac.map(\.id)) { reject("power_devices_mismatch","被覆盖设备不同。") }
            if Set(bc.aggregateDeviceIDs ?? []) != Set(cc.aggregateDeviceIDs ?? []) || bc.aggregateCoverageNote != cc.aggregateCoverageNote { reject("power_scope_mismatch","合计设备覆盖口径不同。") }
            metric("energy","kWh",bp.totalEnergyKWh,cp.totalEnergyKWh,bp.lowerEnergyKWh,bp.upperEnergyKWh,cp.lowerEnergyKWh,cp.upperEnergyKWh)
            if let bc=b.cost,let cc=c.cost {
                if bc.configuration != cc.configuration { reject("tariff_mismatch","币种、费率、窗口、来源或费用排除口径不同。") }
                func number(_ s:String?) -> Double? { s.flatMap{Double($0)} }
                metric("referenceCost",bc.configuration.currency ?? "missing",number(bc.payload.totalCostDecimal),number(cc.payload.totalCostDecimal),number(bc.payload.lowerCostDecimal),number(bc.payload.upperCostDecimal),number(cc.payload.lowerCostDecimal),number(cc.payload.upperCostDecimal))
            }
        case (.steadyHeatBalance(let bp),.steadyHeatBalance(let cp),.steadyHeatBalance(let bc),.steadyHeatBalance(let cc)):
            if bc.conditionMinute != cc.conditionMinute || bc.coverage != cc.coverage || bc.excludedTerms != cc.excludedTerms || bc.exclusions != cc.exclusions || bc.sensitivity?.relationship != cc.sensitivity?.relationship { reject("heat_context_mismatch","代表分钟、覆盖/排除或区间关系依据不同。") }
            for f in ThermalEstimateValidation.heatTerms+["indoorTemperature","outdoorTemperature","density","specificHeat"] where !decisionVariables.contains(f) {
                let a=ThermalEstimateValidation.heatParameter(bc,field:f),d=ThermalEstimateValidation.heatParameter(cc,field:f)
                if a?.value != d?.value || a?.bounds != d?.bounds || a?.source != d?.source { reject("heat_background_mismatch","背景条件\(f)不同且未声明为决策变量。") }
            }
            if bp.completeness != .completeDeclaredCase || cp.completeness != .completeDeclaredCase { reject("heat_subset","指定项子集不能作完整房间负荷收益比较。") }
            metric("coolingSensible","W",bp.coolingSensibleWatts,cp.coolingSensibleWatts,bp.lowerCoolingSensibleWatts,bp.upperCoolingSensibleWatts,cp.lowerCoolingSensibleWatts,cp.upperCoolingSensibleWatts)
        case (.airflowPreview(let bp),.airflowPreview(let cp),.airflowPreview(let bc),.airflowPreview(let cc)):
            if bc.profileID != cc.profileID || bc.profileVersion != cc.profileVersion || bc.baseRadiusMeters != cc.baseRadiusMeters || bc.halfAngleDegrees != cc.halfAngleDegrees || bc.lengthMeters != cc.lengthMeters { reject("preview_profile_mismatch","预览规则档案或扩散条件不同。") }
            func geometry(_ e:FixedEstimateEvidence) throws -> JSONValue {
                var value=try JSONTreeCoding.encode(e.request.resolvedInput.snapshot.geometry).fields!
                for key in ["rooms","obstacles"] { value[key] = .array((value[key]?.items ?? []).map { node in var fields=node.fields!;fields.removeValue(forKey:"name");if key=="rooms"{fields.removeValue(forKey:"northAngle")};return .object(fields) }) }
                return .object(value)
            }
            if try geometry(b) != geometry(c) { reject("preview_background_mismatch","房间/家具采用背景不同。") }
            let bInputs=b.request.resolvedInput.snapshot.inputs,cInputs=c.request.resolvedInput.snapshot.inputs
            func targets(_ input:ScenarioInputs) -> [JSONValue] {
                input.usage.seats.map { seat in .object(["id":.string(seat.id.uuidString.lowercased()),"roomID":.string(seat.roomID.uuidString.lowercased()),"position":(try? JSONTreeCoding.encode(seat.position)) ?? .null,"samples":(try? JSONTreeCoding.encode(seat.samples)) ?? .null]) }
            }
            if targets(bInputs) != targets(cInputs) || bInputs.hvac.map(\.id) != cInputs.hvac.map(\.id) || bInputs.hvac.flatMap({$0.ports.filter{$0.role == .supply}.map(\.position)}) != cInputs.hvac.flatMap({$0.ports.filter{$0.role == .supply}.map(\.position)}) { reject("preview_target_scope_mismatch","关注点、设备或源位置背景不同。") }
            if bInputs.hvac.flatMap({$0.ports.filter{$0.role == .supply}.map(\.direction)}) != cInputs.hvac.flatMap({$0.ports.filter{$0.role == .supply}.map(\.direction)}), !decisionVariables.contains("direction") { reject("undeclared_direction_change","方向改变但未明确direction决策变量。") }
            if !bp.relations.contains(where:{$0.state != .notEvaluated}) || !cp.relations.contains(where:{$0.state != .notEvaluated}) { reject("preview_targets_missing","无可评价关注点，不能比较点位建议。") }
            metrics.append(.init(metric:"qualitativePathRelations",unit:"1",baseline:nil,candidate:nil,absoluteDifference:nil,percentDifference:nil,reasons:reasons.map(\.reason)+["方向候选仅比较几何关系，不给舒适或节电差。"],ranking:"qualitativeOnly"))
        default: reject("payload_mismatch","载荷方法不同。")
        }
        let refs=[b,c].map{ComparisonRunReference(runID:$0.result.identity.runID,scenarioID:$0.result.identity.scenarioID,inputHash:$0.result.identity.inputHash,method:$0.result.method,evaluationHash:$0.cost?.evaluationHash)}
        let context:JSONValue = .object(["runs":try JSONTreeCoding.encode(refs),"decisionVariables":try JSONTreeCoding.encode(decisionVariables),"baselineConfiguration":try JSONTreeCoding.encode(b.request.resolvedInput.configuration),"candidateConfiguration":try JSONTreeCoding.encode(c.request.resolvedInput.configuration),"metrics":try JSONTreeCoding.encode(metrics),"reasons":try JSONTreeCoding.encode(reasons)])
        let hash=AnalysisHasher.sha256(try AnalysisCanonicalizer.bytes(AnalysisCanonicalizer.value(context,schema:nil,root:.object([:]))))
        let snapshot=ComparisonSnapshot(comparisonID:comparisonID,projectID:b.request.resolvedInput.snapshot.projectID,runs:refs,comparisonContextHash:hash,comparableItems:metrics.filter{$0.absoluteDifference != nil || $0.ranking == "qualitativeOnly" && reasons.isEmpty}.map(\.metric),incomparableReasons:reasons,decisionVariables:decisionVariables,metrics:metrics)
        _=try NativeAnalysisCodec().encodeComparisonSnapshot(snapshot);return snapshot
    }
}
