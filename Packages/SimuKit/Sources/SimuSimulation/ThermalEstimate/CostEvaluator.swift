import Foundation
import SimuCore

public enum CostEvaluator {
    public static let maximumRecordBytes = 256*1024
    public static func decimalString(_ x: Decimal) -> String { var value = x; return NSDecimalString(&value, Locale(identifier:"en_US_POSIX")) }
    public static func decimal(_ x: Double) throws -> Decimal {
        try ThermalEstimateValidation.validateCostNumericInput(x)
        guard x.isFinite, let d=Decimal(string:String(x),locale:Locale(identifier:"en_US_POSIX")), !d.isNaN, x == 0 || d != 0 else { throw ProjectDataError.contract("Unrepresentable decimal input") };return d
    }
    public static func evaluate(request: LocalAnalysisRequest, result: LocalAnalysisResult, configuration c: CostEvaluationConfiguration) throws -> CostEvaluationRecord {
        guard request.identity == result.identity, request.method == result.method, request.method.kind == .powerEstimate, result.checks.state == .passed,
              case .powerEstimate(let p)=result.payload, case .powerEstimate(let powerConfig)=request.resolvedInput.configuration.payload else { throw ProjectDataError.contract("Cost requires a fixed complete checked power run") }
        try AnalysisInputResolver().validate(request);try NativeAnalysisCodec().validateResult(result)
        try ThermalEstimateValidation.validateWindows(c.requestedWindows)
        try ThermalEstimateValidation.validateWindows(c.tariffs.map{.init(startMinute:$0.startMinute,endMinute:$0.endMinute)},requireNonempty:false)
        guard c.tariffs.count<=1440,(0...8).contains(c.displayFractionDigits) else { throw ProjectDataError.contract("Unsupported tariff size/display precision") }
        for t in c.tariffs { try ThermalEstimateValidation.validateParameter(t.rate) }
        try ThermalEstimateEvidenceValidation.validate(request:request,result:result)
        var missing:[AnalysisMissingReason]=[]
        if c.currency?.range(of:"^[A-Z]{3}$",options:.regularExpression)==nil { missing.append(.init(code:"currency_required",fieldPath:"currency",reason:"请明确三字母币种；不自动换汇。")) }
        if c.timeBasis != p.timeBasis || c.requestedWindows != p.requestedWindows { missing.append(.init(code:"cost_window_mismatch",fieldPath:"requestedWindows",reason:"费用必须使用父电量的同一完整参考窗口。")) }
        var segments:[CostEvaluationSegment]=[],total=Decimal(0),lower=Decimal(0),upper=Decimal(0)
        for w in c.requestedWindows {
            let boundaries=Set([w.startMinute,w.endMinute]+p.segments.flatMap{[$0.startMinute,$0.endMinute]}+c.tariffs.flatMap{[$0.startMinute,$0.endMinute]}).filter{$0>=w.startMinute && $0<=w.endMinute}.sorted()
            for (start,end) in zip(boundaries,boundaries.dropFirst()) {
                try Task.checkCancellation()
                guard let power=p.segments.first(where:{$0.startMinute<=start && $0.endMinute>=end}) else { missing.append(.init(code:"power_window_missing",fieldPath:"requestedWindows",reason:"父run未覆盖\(start)…\(end)分钟。"));continue }
                guard let tariff=c.tariffs.first(where:{$0.startMinute<=start && $0.endMinute>=end}),case .known(let rate,let source,let rateBounds) = tariff.rate else { missing.append(.init(code:"tariff_missing",fieldPath:"tariffs",reason:"\(start)…\(end)分钟电价未知，不延用上一片价格。"));continue }
                let factor=Decimal(end-start)/Decimal(60000),energy=try decimal(power.powerWatts)*factor,price=try decimal(rate),cost=energy*price
                guard power.powerWatts == 0 || energy != 0, energy == 0 || price == 0 || cost != 0 else { throw ProjectDataError.contract("Decimal underflow is not a zero cost") }
                total += cost
                let original=powerConfig.intervals.first{$0.startMinute<=start && $0.endMinute>=end}!
                var lo=power.powerWatts,hi=power.powerWatts
                if case .known(_,_,let b)=original.power { lo=b?.lower ?? lo;hi=b?.upper ?? hi }
                lower += try decimal(lo)*factor*decimal(rateBounds?.lower ?? rate); upper += try decimal(hi)*factor*decimal(rateBounds?.upper ?? rate)
                guard !cost.isNaN,!total.isNaN,!lower.isNaN,!upper.isNaN else { throw ProjectDataError.contract("Decimal arithmetic overflow") }
                segments.append(.init(startMinute:start,endMinute:end,energyKWhDecimal:decimalString(energy),rateDecimal:decimalString(price),costDecimal:decimalString(cost),source:source))
            }
        }
        let payload=CostEvaluationPayload(segments:segments,totalCostDecimal:missing.isEmpty ? decimalString(total):nil,lowerCostDecimal:missing.isEmpty ? decimalString(lower):nil,upperCostDecimal:missing.isEmpty ? decimalString(upper):nil,missingReasons:missing)
        let hash=try AnalysisHasher().evaluationHash(identity:result.identity,evaluationConfiguration:JSONTreeCoding.encode(c))
        let record=CostEvaluationRecord(projectID:request.resolvedInput.snapshot.projectID,parentIdentity:result.identity,evaluationHash:hash,configuration:c,payload:payload)
        _=try NativeAnalysisCodec().encodeCostEvaluation(record)
        return record
    }
    public static func validate(_ record:CostEvaluationRecord, parent:NativePowerEvidence) throws {
        guard parent.request.identity == record.parentIdentity, parent.request.resolvedInput.snapshot.projectID == record.projectID else { throw ProjectDataError.contract("Cost parent mismatch") }
        let expected=try evaluate(request:parent.request,result:parent.result,configuration:record.configuration)
        guard expected == record else { throw ProjectDataError.contract("Cost hash/payload differs from fixed inputs") }
    }
}
public struct NativePowerEvidence: Equatable, Sendable {
    public let request:LocalAnalysisRequest
    public let result:LocalAnalysisResult
    public init(request:LocalAnalysisRequest,result:LocalAnalysisResult) { self.request=request;self.result=result }
}
