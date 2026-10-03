import Foundation

/// ADR-014 demo electricity price. Editable, and always carries a source.
/// A nil price is a missing tariff, not a free one, and must not become 0.
public struct CostAssumptions: Codable, Equatable, Sendable {
    public var pricePerKWh: Double?
    public var currency: String
    public var source: ParameterSource
    public var reference: String?

    public init(
        pricePerKWh: Double?,
        currency: String,
        source: ParameterSource,
        reference: String? = nil
    ) {
        self.pricePerKWh = pricePerKWh
        self.currency = currency
        self.source = source
        self.reference = reference
    }

    /// 1.2 HKD/kWh competition placeholder. Not a utility tariff and not a quote.
    public static let demo = CostAssumptions(
        pricePerKWh: 1.2,
        currency: "HKD",
        source: .assumed,
        reference: "比赛演示假设，非真实电价"
    )

    /// A usable price needs a non-negative number and a currency code.
    public var hasPrice: Bool {
        guard let pricePerKWh, pricePerKWh >= 0 else { return false }
        return !currency.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// Frozen representative-day energy and cost. Nil means omitted, never a sentinel 0.
/// L1 results still omit `annual_kwh`. Report-layer yearly totals live on
/// `EvidenceRun` as `annualEnergyKWh` / `annualCost` (day × occupied days).
public struct RepresentativeDayCost: Codable, Equatable, Sendable {
    public var electricPowerW: Double?
    public var occupiedHours: Double?
    public var energyKWh: Double?
    public var cost: Double?
    public var currency: String?
    /// Unit price frozen with this snapshot. Tariff sits outside the physics hash,
    /// so a later price edit must not be read as a change in L1 watts.
    public var pricePerKWh: Double?
    public var energyOmitted: Bool
    public var costOmitted: Bool
    public var reason: String?
    /// No retrofit or equipment quote exists in this phase.
    public var retrofitQuote: String

    public init(
        electricPowerW: Double?,
        occupiedHours: Double?,
        energyKWh: Double?,
        cost: Double?,
        currency: String?,
        pricePerKWh: Double? = nil,
        energyOmitted: Bool,
        costOmitted: Bool,
        reason: String? = nil,
        retrofitQuote: String = "待报价"
    ) {
        self.electricPowerW = electricPowerW
        self.occupiedHours = occupiedHours
        self.energyKWh = energyKWh
        self.cost = cost
        self.currency = currency
        self.pricePerKWh = pricePerKWh
        self.energyOmitted = energyOmitted
        self.costOmitted = costOmitted
        self.reason = reason
        self.retrofitQuote = retrofitQuote
    }

    public static func omitted(reason: String) -> RepresentativeDayCost {
        RepresentativeDayCost(
            electricPowerW: nil,
            occupiedHours: nil,
            energyKWh: nil,
            cost: nil,
            currency: nil,
            pricePerKWh: nil,
            energyOmitted: true,
            costOmitted: true,
            reason: reason
        )
    }

    public var energyText: String {
        guard let energyKWh, !energyOmitted else { return "未知" }
        return UserFacingCopy.displayQuantity(energyKWh, unit: "kWh")
    }

    public var costText: String {
        guard let cost, let currency, !costOmitted else { return "未知" }
        return UserFacingCopy.displayQuantity(cost, unit: currency)
    }

    public var powerText: String {
        guard let electricPowerW else { return "未知" }
        return UserFacingCopy.displayQuantity(electricPowerW, unit: "W")
    }
}

/// Representative-day costing only. Does not multiply by 365 or invent a payback.
public enum CostAccounting {
    /// Clock window in hours. `08:00`–`18:00` is 10 h, not 24 h and not 365 days.
    public static func occupiedHours(start: String?, end: String?) -> Double? {
        guard let start, let end,
              let startMinutes = OccupiedHours.minutes(from: start),
              let endMinutes = OccupiedHours.minutes(from: end),
              endMinutes > startMinutes else {
            return nil
        }
        return Double(endMinutes - startMinutes) / 60
    }

    /// Energy is `p_elec_w / 1000 × occupiedHours`, rounded half-up to 0.00001 kWh.
    /// Cost is that energy times the tariff, rounded half-up to currency millis (0.001).
    /// 1033.112 W × 10 h × 1.2 HKD/kWh therefore locks at 10.33112 kWh and 12.397 HKD.
    /// Missing power or hours omits both figures. A missing tariff omits only the cost.
    public static func representativeDay(
        electricPowerW: Double?,
        occupiedStart: String?,
        occupiedEnd: String?,
        tariff: CostAssumptions?
    ) -> RepresentativeDayCost {
        let hours = occupiedHours(start: occupiedStart, end: occupiedEnd)
        let priced = tariff?.hasPrice == true
        var energy: Double?
        var cost: Double?
        var currency: String?
        if let electricPowerW, let hours {
            let energyDecimal = roundHalfUp(
                decimal(electricPowerW) / Decimal(1000) * decimal(hours),
                scale: 5
            )
            energy = double(energyDecimal)
            if priced, let tariff, let price = tariff.pricePerKWh {
                cost = double(roundHalfUp(energyDecimal * decimal(price), scale: 3))
                currency = tariff.currency
            }
        }
        return RepresentativeDayCost(
            electricPowerW: electricPowerW,
            occupiedHours: hours,
            energyKWh: energy,
            cost: cost,
            currency: currency,
            pricePerKWh: priced ? tariff?.pricePerKWh : nil,
            energyOmitted: energy == nil,
            costOmitted: cost == nil,
            reason: omissionReason(
                electricPowerW: electricPowerW,
                hours: hours,
                priced: priced
            )
        )
    }

    /// Occupied days used to scale a representative day into a yearly total.
    public static let occupiedDaysPerYear: Double = 365

    /// `dayEnergyKWh × occupiedDaysPerYear`, half-up to 0.00001 kWh.
    public static func annualEnergyKWh(from dayEnergyKWh: Double?) -> Double? {
        guard let dayEnergyKWh else { return nil }
        return double(roundHalfUp(decimal(dayEnergyKWh) * decimal(occupiedDaysPerYear), scale: 5))
    }

    /// `dayCost × occupiedDaysPerYear`, half-up to currency millis.
    public static func annualCost(from dayCost: Double?) -> Double? {
        guard let dayCost else { return nil }
        return double(roundHalfUp(decimal(dayCost) * decimal(occupiedDaysPerYear), scale: 3))
    }

    /// Difference of two L1 day costs that share currency, tariff and occupied hours.
    /// A basis mismatch, a tariff change or a currency change hides the figure.
    /// The result is the two `p_elec_w` values at that shared price, not a tariff delta
    /// and not one power times a coefficient.
    public static func savingsHKD(
        _ high: RepresentativeDayCost,
        _ low: RepresentativeDayCost,
        basisMismatch: String?
    ) -> Double? {
        guard basisMismatch == nil else { return nil }
        guard let highCost = high.cost, let lowCost = low.cost,
              high.electricPowerW != nil, low.electricPowerW != nil,
              let highHours = high.occupiedHours, let lowHours = low.occupiedHours,
              decimal(highHours) == decimal(lowHours),
              let highPrice = high.pricePerKWh, let lowPrice = low.pricePerKWh,
              decimal(highPrice) == decimal(lowPrice),
              let highCurrency = high.currency, let lowCurrency = low.currency,
              highCurrency == lowCurrency else {
            return nil
        }
        return double(roundHalfUp(decimal(highCost) - decimal(lowCost), scale: 3))
    }

    private static func omissionReason(
        electricPowerW: Double?,
        hours: Double?,
        priced: Bool
    ) -> String? {
        if electricPowerW == nil {
            return "无 L1 电功率，代表日电量与电费省略"
        }
        if hours == nil {
            return "无占用时段，代表日电量与电费省略"
        }
        if !priced {
            return "无电价，代表日电费省略"
        }
        return nil
    }

    /// Shortest decimal spelling, so 1033.112 and 1.2 stay exact under Decimal.
    private static func decimal(_ value: Double) -> Decimal {
        Decimal(string: String(value), locale: Locale(identifier: "en_US_POSIX")) ?? Decimal(value)
    }

    private static func roundHalfUp(_ value: Decimal, scale: Int) -> Decimal {
        var input = value
        var output = Decimal()
        NSDecimalRound(&output, &input, scale, .plain)
        return output
    }

    private static func double(_ value: Decimal) -> Double {
        (value as NSDecimalNumber).doubleValue
    }
}
