import Foundation

/// Separate research inputs with explicit SI units. No humidity, comfort or point-temperature inference.
public struct RoomDynamicsConfiguration: Codable, Equatable, Sendable {
    public let roomVolumeCubicMeters: Double
    public let heatCapacityJoulesPerKelvin: Double
    public let envelopeConductanceWattsPerKelvin: Double
    public let outdoorExchangeCubicMetersPerSecond: Double
    public let airVolumetricHeatCapacityJoulesPerCubicMeterKelvin: Double
    public let initialTemperatureDegC: Double
    public let initialCO2PPM: Double
    public init(roomVolumeCubicMeters: Double, heatCapacityJoulesPerKelvin: Double,
                envelopeConductanceWattsPerKelvin: Double, outdoorExchangeCubicMetersPerSecond: Double,
                airVolumetricHeatCapacityJoulesPerCubicMeterKelvin: Double, initialTemperatureDegC: Double, initialCO2PPM: Double) {
        self.roomVolumeCubicMeters = roomVolumeCubicMeters; self.heatCapacityJoulesPerKelvin = heatCapacityJoulesPerKelvin
        self.envelopeConductanceWattsPerKelvin = envelopeConductanceWattsPerKelvin
        self.outdoorExchangeCubicMetersPerSecond = outdoorExchangeCubicMetersPerSecond
        self.airVolumetricHeatCapacityJoulesPerCubicMeterKelvin = airVolumetricHeatCapacityJoulesPerCubicMeterKelvin
        self.initialTemperatureDegC = initialTemperatureDegC; self.initialCO2PPM = initialCO2PPM
    }
}
public struct RoomDynamicsInterval: Codable, Equatable, Sendable {
    public let durationSeconds: Double
    public let outdoorTemperatureDegC: Double
    public let internalSensibleWatts: Double
    public let deliveredSensibleCoolingWatts: Double
    public let outdoorCO2PPM: Double
    public let co2SourceCubicMetersPerSecond: Double
    public init(durationSeconds: Double, outdoorTemperatureDegC: Double, internalSensibleWatts: Double,
                deliveredSensibleCoolingWatts: Double, outdoorCO2PPM: Double, co2SourceCubicMetersPerSecond: Double) {
        self.durationSeconds = durationSeconds; self.outdoorTemperatureDegC = outdoorTemperatureDegC
        self.internalSensibleWatts = internalSensibleWatts; self.deliveredSensibleCoolingWatts = deliveredSensibleCoolingWatts
        self.outdoorCO2PPM = outdoorCO2PPM; self.co2SourceCubicMetersPerSecond = co2SourceCubicMetersPerSecond
    }
}
public struct RoomDynamicsSample: Codable, Equatable, Sendable {
    public let timeSeconds: Double
    public let roomMeanTemperatureDegC: Double
    public let roomMeanCO2PPM: Double
    public init(timeSeconds: Double, roomMeanTemperatureDegC: Double, roomMeanCO2PPM: Double) {
        self.timeSeconds = timeSeconds; self.roomMeanTemperatureDegC = roomMeanTemperatureDegC; self.roomMeanCO2PPM = roomMeanCO2PPM
    }
}
