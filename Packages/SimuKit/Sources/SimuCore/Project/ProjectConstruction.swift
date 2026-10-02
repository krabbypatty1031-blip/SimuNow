import Foundation

public extension ProjectDocument {
    static func unfinished(id: UUID = UUID(), name: String, spaceType: SpaceType = .office) -> ProjectDocument {
        .init(id:id,name:name,spaceType:spaceType,geometry:.init())
    }
}
public extension Scenario {
    static func unfinished(id: UUID = UUID(), name: String) -> Scenario {
        .init(id:id,name:name,inputs:.init(usage:.init(),envelope:.init(),environment:.init(outdoorTemperature:.unknown(reason:"Not supplied"),outdoorHumidity:.unknown(reason:"Not supplied"),indoorHumidity:.unknown(reason:"Not supplied"))),evaluation:.init(cost:.init()))
    }
}
public extension HeatGain {
    var convectivePowerWatts: Double? {
        guard let total = sensible.value, let fraction = convectiveFraction.value else { return nil }
        return total * fraction
    }
    var radiativePowerWatts: Double? {
        guard let total = sensible.value, let fraction = convectiveFraction.value else { return nil }
        return total * (1 - fraction)
    }
}
