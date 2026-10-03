import Foundation
import SimuCore

public enum RoomDynamicsExperiment {
    public static let method = "simunow.experimental.roomMeanRCAndCO2.v1"
    /// Exact integration of piecewise constant sources. Recirculation is excluded from outdoor exchange.
    public static func run(_ c: RoomDynamicsConfiguration, intervals: [RoomDynamicsInterval], outputStepSeconds: Double) throws -> [RoomDynamicsSample] {
        let parameters = [c.roomVolumeCubicMeters, c.heatCapacityJoulesPerKelvin, c.envelopeConductanceWattsPerKelvin,
                          c.outdoorExchangeCubicMetersPerSecond, c.airVolumetricHeatCapacityJoulesPerCubicMeterKelvin,
                          c.initialTemperatureDegC, c.initialCO2PPM, outputStepSeconds]
        guard parameters.allSatisfy(\.isFinite), c.roomVolumeCubicMeters > 0, c.heatCapacityJoulesPerKelvin > 0,
              c.envelopeConductanceWattsPerKelvin >= 0, c.outdoorExchangeCubicMetersPerSecond >= 0,
              c.airVolumetricHeatCapacityJoulesPerCubicMeterKelvin > 0, c.initialTemperatureDegC >= -273.15,
              c.initialCO2PPM >= 0, outputStepSeconds >= 0.1, intervals.count <= 1000, !intervals.isEmpty else {
            throw ProjectDataError.contract("动态平均模型需要完整的热容量、体积、外界交换、初态与有限时间步。")
        }
        var sampleBudget = 1
        for interval in intervals {
            guard [interval.durationSeconds, interval.outdoorTemperatureDegC, interval.internalSensibleWatts,
                   interval.deliveredSensibleCoolingWatts, interval.outdoorCO2PPM, interval.co2SourceCubicMetersPerSecond].allSatisfy(\.isFinite),
                  interval.durationSeconds > 0, interval.durationSeconds <= 7 * 86400, interval.outdoorTemperatureDegC >= -273.15,
                  interval.internalSensibleWatts >= 0, interval.deliveredSensibleCoolingWatts >= 0,
                  interval.outdoorCO2PPM >= 0, interval.co2SourceCubicMetersPerSecond >= 0,
                  ceil(interval.durationSeconds / outputStepSeconds) <= 10_000 else { throw ProjectDataError.contract("动态工况或时间步超出范围。") }
            sampleBudget += Int(ceil(interval.durationSeconds / outputStepSeconds))
            guard sampleBudget <= 10_001 else { throw ProjectDataError.contract("动态输出最多 10000 步。") }
        }
        var time = 0.0, temperature = c.initialTemperatureDegC, co2 = c.initialCO2PPM
        var output: [RoomDynamicsSample] = [.init(timeSeconds: 0, roomMeanTemperatureDegC: temperature, roomMeanCO2PPM: co2)]
        let conductance = c.envelopeConductanceWattsPerKelvin + c.outdoorExchangeCubicMetersPerSecond * c.airVolumetricHeatCapacityJoulesPerCubicMeterKelvin
        for interval in intervals {
            let steps = Int(ceil(interval.durationSeconds / outputStepSeconds))
            for step in 0..<steps {
                try Task.checkCancellation()
                let dt = min(outputStepSeconds, interval.durationSeconds - Double(step) * outputStepSeconds)
                let thermalSource = interval.internalSensibleWatts - interval.deliveredSensibleCoolingWatts
                let thermalRate = conductance / c.heatCapacityJoulesPerKelvin
                temperature = advance(initial: temperature, equilibrium: interval.outdoorTemperatureDegC,
                                      sourceRate: thermalSource / c.heatCapacityJoulesPerKelvin, exchangeRate: thermalRate, seconds: dt)
                co2 = advance(initial: co2, equilibrium: interval.outdoorCO2PPM,
                              sourceRate: interval.co2SourceCubicMetersPerSecond / c.roomVolumeCubicMeters * 1e6,
                              exchangeRate: c.outdoorExchangeCubicMetersPerSecond / c.roomVolumeCubicMeters, seconds: dt)
                guard temperature.isFinite, temperature >= -273.15, co2.isFinite, co2 >= 0 else { throw ProjectDataError.contract("动态模型越界，不能作为有效预测。") }
                time += dt; output.append(.init(timeSeconds: time, roomMeanTemperatureDegC: temperature, roomMeanCO2PPM: co2))
            }
        }
        return output
    }
    private static func advance(initial: Double, equilibrium: Double, sourceRate: Double, exchangeRate: Double, seconds: Double) -> Double {
        if exchangeRate == 0 { return initial + sourceRate * seconds }
        // expm1 avoids cancellation for very small ventilation/conductance and short steps.
        let exchangedFraction = -expm1(-exchangeRate * seconds)
        return initial + (equilibrium - initial) * exchangedFraction + sourceRate * (exchangedFraction / exchangeRate)
    }
}
