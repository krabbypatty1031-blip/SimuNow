import Foundation
import SimuCore

public struct ThermalGridStepResult: Sendable {
    public let projection: ProjectionExperimentResult
    public let cellTemperatureDegC: [Double]
    public let fluidMeanTemperatureDegC: Double
    public let maximumTemperatureDegC: Double
    public let minimumTemperatureDegC: Double
}
/// Closed adiabatic 2D Boussinesq experiment, first-order upwind advection and explicit diffusion.
/// No turbulence, HVAC boundaries, humidity or three-dimensional room claims.
public enum ThermalGridExperiment {
    public static func step(columns nx: Int, rows ny: Int, cellWidth dx: Double, timeStep dt: Double,
                            density: Double, horizontalFaceVelocity: [Double], verticalFaceVelocity: [Double],
                            fluidMask: [Bool], temperature: [Double], diffusivitySquareMetersPerSecond alpha: Double,
                            thermalExpansionPerKelvin beta: Double, referenceTemperatureDegC: Double,
                            gravityMetersPerSecondSquared gravity: Double = 9.81) throws -> ThermalGridStepResult {
        guard (2...64).contains(nx), (2...64).contains(ny), temperature.count == nx*ny, fluidMask.count == nx*ny,
              horizontalFaceVelocity.count == (nx+1)*ny, verticalFaceVelocity.count == nx*(ny+1),
              temperature.allSatisfy({ $0.isFinite && $0 >= -273.15 }),
              [dx, dt, alpha, beta, referenceTemperatureDegC, gravity].allSatisfy(\.isFinite),
              dx > 0, dt > 0, alpha >= 0, beta >= 0, gravity >= 0 else { throw ProjectDataError.contract("热网格输入或单位范围无效。") }
        func fluid(_ x: Int, _ y: Int) -> Bool { x >= 0 && x < nx && y >= 0 && y < ny && fluidMask[y*nx+x] }
        var predictedV = verticalFaceVelocity
        for y in 1..<ny { for x in 0..<nx where fluid(x,y-1) && fluid(x,y) {
            predictedV[y*nx+x] += dt * gravity * beta * ((temperature[(y-1)*nx+x] + temperature[y*nx+x])/2 - referenceTemperatureDegC)
        } }
        let projection = try PressureProjectionExperiment.run(columns: nx, rows: ny, cellWidth: dx, timeStep: dt, density: density,
            horizontalFaceVelocity: horizontalFaceVelocity, verticalFaceVelocity: predictedV, fluidMask: fluidMask)
        guard projection.converged else { throw ProjectDataError.contract("压力投影未收敛，热网格步不接受。") }
        let u = projection.horizontalFaceVelocity, v = projection.verticalFaceVelocity
        let cfl = dt/dx * ((u.map(abs).max() ?? 0) + (v.map(abs).max() ?? 0)) + 4*alpha*dt/(dx*dx)
        guard cfl.isFinite, cfl <= 1 else { throw ProjectDataError.contract("显式热网格违反时间步稳定性门槛；请减小时间步。") }
        var next = temperature
        for y in 0..<ny { try Task.checkCancellation(); for x in 0..<nx where fluid(x,y) {
            let index = y*nx+x, t = temperature[index]
            let left = fluid(x-1,y) ? temperature[index-1] : t
            let right = fluid(x+1,y) ? temperature[index+1] : t
            let below = fluid(x,y-1) ? temperature[index-nx] : t
            let above = fluid(x,y+1) ? temperature[index+nx] : t
            let ul = u[y*(nx+1)+x], ur = u[y*(nx+1)+x+1], vb = v[y*nx+x], vt = v[(y+1)*nx+x]
            let fluxLeft = ul * (ul >= 0 ? left : t), fluxRight = ur * (ur >= 0 ? t : right)
            let fluxBelow = vb * (vb >= 0 ? below : t), fluxAbove = vt * (vt >= 0 ? t : above)
            next[index] = t - dt/dx*(fluxRight-fluxLeft+fluxAbove-fluxBelow) + alpha*dt/(dx*dx)*(left+right+below+above-4*t)
        } }
        let valid = next.indices.filter { fluidMask[$0] }.map { next[$0] }
        guard valid.allSatisfy({ $0.isFinite && $0 >= -273.15 }) else { throw ProjectDataError.contract("热网格步越界。") }
        return .init(projection: projection, cellTemperatureDegC: next,
            fluidMeanTemperatureDegC: valid.reduce(0,+)/Double(valid.count), maximumTemperatureDegC: valid.max()!, minimumTemperatureDegC: valid.min()!)
    }
}
