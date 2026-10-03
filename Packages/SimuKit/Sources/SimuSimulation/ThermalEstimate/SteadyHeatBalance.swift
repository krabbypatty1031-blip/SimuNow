import Foundation
import SimuCore

public enum SteadyHeatBalance {
    public static func calculate(_ config: SteadyHeatBalanceConfiguration) throws -> SteadyHeatBalancePayload {
        try ThermalEstimateValidation.validateHeat(config)
        let missing = ThermalEstimateValidation.heatMissing(config)
        guard missing.isEmpty else { throw ProjectDataError.contract("Incomplete explicit heat case: \(missing.map(\.code))") }
        let nominal = try evaluate(config, overrides: [:])
        var scenarios: [HeatSensitivityScenario] = [.init(id: "nominal", adoptedValues: [], totalSignedWatts: nominal.total, coolingSensibleWatts: max(0,nominal.total))]
        if let sensitivity = config.sensitivity, !sensitivity.fields.isEmpty {
            let n = sensitivity.fields.count
            for mask in 0..<(1 << n) {
                try Task.checkCancellation()
                var overrides: [String:Double] = [:], values: [HeatSensitivityValue] = []
                for (index, field) in sensitivity.fields.enumerated() {
                    guard let p = ThermalEstimateValidation.heatParameter(config,field:field), let bounds = p.bounds, let source = p.source else { throw ProjectDataError.contract("Missing sensitivity source/bounds") }
                    let v = (mask & (1 << index)) == 0 ? bounds.lower : bounds.upper
                    overrides[field] = v; values.append(.init(field:field,value:v,unit:p.unit,source:source))
                }
                let s = try evaluate(config,overrides:overrides)
                scenarios.append(.init(id:"endpoint-\(mask)",adoptedValues:values,totalSignedWatts:s.total,coolingSensibleWatts:max(0,s.total)))
            }
        }
        let minimum = scenarios.map(\.coolingSensibleWatts).min()!, maximum = scenarios.map(\.coolingSensibleWatts).max()!
        func range<Q>(_ p: PhysicalParameter<Q>?) -> (Double,Double,Double)? {
            guard case .known(let value,_,let bounds) = p else { return nil }
            return (value,bounds?.lower ?? value,bounds?.upper ?? value)
        }
        let capacityRange: (Double,Double,Double)?
        if let direct = range(config.sensibleCoolingCapacity) { capacityRange = direct }
        else if let total = range(config.totalCoolingCapacity), let shr = range(config.sensibleHeatRatio) { capacityRange = (total.0*shr.0,total.1*shr.1,total.2*shr.2) }
        else { capacityRange = nil }
        let capacity = capacityRange?.0
        let screen: SensibleCapacityScreen
        if !config.excludedTerms.isEmpty || capacityRange == nil { screen = .cannotEvaluate }
        else if capacityRange!.1 >= maximum { screen = .sufficientForDeclaredSensibleCase }
        else if capacityRange!.2 < minimum { screen = .insufficientForDeclaredSensibleCase }
        else { screen = .cannotEvaluate }
        return .init(terms: nominal.terms,totalSignedWatts:nominal.total,coolingSensibleWatts:max(0,nominal.total),excludedTerms:config.excludedTerms,capacityScreen:screen,
                     completeness:config.excludedTerms.isEmpty ? .completeDeclaredCase : .declaredSubset,lowerCoolingSensibleWatts:minimum,upperCoolingSensibleWatts:maximum,scenarios:scenarios,adoptedSensibleCapacityWatts:capacity,
                     notes:["Tin是已采用情景条件，不代表已达到室温。", "循环送回风、潜热、空间温度、PMV、动态降温与用电反推不在方法内。", "端点情景包络不含概率或置信区间；相关性未知时组合可能不同时发生。", "容量筛查仅适用于完整已声明显热代表工况；不代表全制冷选型或舒适通过。"])
    }
    private static func evaluate(_ c: SteadyHeatBalanceConfiguration, overrides: [String:Double]) throws -> (terms:[HeatBalanceTerm],total:Double) {
        func v(_ field:String) throws -> Double {
            if c.excludedTerms.contains(field) { return 0 }
            guard let x = overrides[field] ?? ThermalEstimateValidation.heatParameter(c,field:field)?.value else { throw ProjectDataError.contract("Unknown heat term \(field)") }; return x
        }
        let delta = try v("outdoorTemperature") - v("indoorTemperature")
        let conductance = try v("conductance") * delta
        let factor = try v("density") * v("specificHeat") * delta
        let outdoor = try factor * v("outdoorAir"), infiltration = try factor * v("infiltration")
        let internalHeat = try v("internalSensibleHeat"), solar = try v("solarSensibleHeat")
        let raw = [("conductance",conductance,"UA × (Tout−Tin)"),("outdoorAir",outdoor,"ρ cp 室外新风 × ΔT；循环风排除"),("infiltration",infiltration,"ρ cp 渗风 × ΔT"),("internalSensibleHeat",internalHeat,"内部总显热只计一次"),("solarSensibleHeat",solar,"显式太阳显热")]
        let total = raw.reduce(0){$0+$1.1}
        guard raw.allSatisfy({$0.1.isFinite}),total.isFinite else { throw ProjectDataError.contract("Heat balance overflow") }
        let terms = raw.filter{!c.excludedTerms.contains($0.0)}.map{HeatBalanceTerm(id:$0.0,signedWatts:$0.1,description:$0.2)}
        return (terms,total)
    }
}
public struct SteadyHeatBalanceExecutor: LocalAnalysisExecutor {
    public let method = AnalysisMethod(kind:.steadyHeatBalance)
    public init() {}
    public func execute(_ request: LocalAnalysisRequest, progress:@escaping @Sendable(Double) async -> Void) async throws -> LocalAnalysisExecution {
        guard case .steadyHeatBalance(let c)=request.resolvedInput.configuration.payload else { throw ProjectDataError.contract("Wrong heat executor input") }
        await progress(0.1);let payload=try SteadyHeatBalance.calculate(c);try Task.checkCancellation();await progress(1)
        return .init(payload:.steadyHeatBalance(payload),checks:.init(state:.passed))
    }
}
