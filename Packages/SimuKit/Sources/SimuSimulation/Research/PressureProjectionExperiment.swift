import Foundation
import SimuCore

public struct ProjectionExperimentResult: Sendable {
    public let columns: Int
    public let rows: Int
    public let horizontalFaceVelocity: [Double]
    public let verticalFaceVelocity: [Double]
    public let pressure: [Double]
    public let fluidMask: [Bool]
    public let initialMaximumDivergence: Double
    public let finalMaximumDivergence: Double
    public let iterations: Int
    public let elapsedSeconds: Double
    public let estimatedArrayBytes: Int
    public let converged: Bool
}
/// Two-dimensional, closed-box, constant-density CPU MAC-grid experiment.
/// This is an incompressibility benchmark, not a room airflow/temperature solver.
public enum PressureProjectionExperiment {
    public static let method = "simunow.experimental.closedBoxProjection2D.v1"
    public static func run(columns nx: Int, rows ny: Int, cellWidth dx: Double, timeStep dt: Double,
                           density: Double, horizontalFaceVelocity inputU: [Double], verticalFaceVelocity inputV: [Double],
                           fluidMask: [Bool], maximumIterations: Int = 2000, tolerance: Double = 1e-6) throws -> ProjectionExperimentResult {
        guard (2...64).contains(nx), (2...64).contains(ny), (1...5000).contains(maximumIterations),
              [dx, dt, density, tolerance].allSatisfy(\.isFinite), dx > 0, dt > 0, density > 0, tolerance > 0,
              inputU.count == (nx + 1)*ny, inputV.count == nx*(ny + 1), fluidMask.count == nx*ny,
              inputU.allSatisfy(\.isFinite), inputV.allSatisfy(\.isFinite), fluidMask.contains(true) else { throw ProjectDataError.contract("投影实验网格、边界、数组或预算无效。") }
        let start = ContinuousClock.now
        var u = inputU, v = inputV, pressure = Array(repeating: 0.0, count: nx*ny)
        func fluid(_ x: Int, _ y: Int) -> Bool { x >= 0 && x < nx && y >= 0 && y < ny && fluidMask[y*nx+x] }
        // Impermeable outer walls and obstacle faces. Invalid cells never participate in statistics.
        for y in 0..<ny { for x in 0...nx where !fluid(x-1,y) || !fluid(x,y) { u[y*(nx+1)+x] = 0 } }
        for y in 0...ny { for x in 0..<nx where !fluid(x,y-1) || !fluid(x,y) { v[y*nx+x] = 0 } }
        func divergence(_ a: [Double], _ b: [Double]) -> [Double] {
            (0..<nx*ny).map { index in
                guard fluidMask[index] else { return 0 }
                let x = index % nx, y = index / nx
                return (a[y*(nx+1)+x+1]-a[y*(nx+1)+x] + b[(y+1)*nx+x]-b[y*nx+x]) / dx
            }
        }
        let initial = divergence(u,v), maximumInitial = initial.map(abs).max() ?? 0
        let rhs = initial.map { $0 * density / dt }
        var iterations = 0
        // Neumann Poisson system solved with Gauss-Seidel. Each closed connected fluid region
        // has a pressure gauge; face gradients are independent of that constant.
        for iteration in 0..<maximumIterations {
            try Task.checkCancellation()
            for y in 0..<ny { for x in 0..<nx where fluid(x,y) {
                var sum = 0.0, count = 0.0
                for (xx, yy) in [(x-1,y),(x+1,y),(x,y-1),(x,y+1)] where fluid(xx,yy) { sum += pressure[yy*nx+xx]; count += 1 }
                if count > 0 { pressure[y*nx+x] = (sum - rhs[y*nx+x]*dx*dx) / count }
            } }
            iterations = iteration + 1
            if iteration % 10 == 0 {
                var residual = 0.0
                for y in 0..<ny { for x in 0..<nx where fluid(x,y) {
                    var laplacian = 0.0
                    for (xx,yy) in [(x-1,y),(x+1,y),(x,y-1),(x,y+1)] where fluid(xx,yy) { laplacian += pressure[yy*nx+xx] - pressure[y*nx+x] }
                    residual = max(residual, abs(laplacian / (dx*dx) - rhs[y*nx+x]) * dt / density)
                } }
                if residual <= tolerance { break }
            }
        }
        for y in 0..<ny { for x in 1..<nx where fluid(x-1,y) && fluid(x,y) { u[y*(nx+1)+x] -= dt/density*(pressure[y*nx+x]-pressure[y*nx+x-1])/dx } }
        for y in 1..<ny { for x in 0..<nx where fluid(x,y-1) && fluid(x,y) { v[y*nx+x] -= dt/density*(pressure[y*nx+x]-pressure[(y-1)*nx+x])/dx } }
        let maximumFinal = divergence(u,v).map(abs).max() ?? 0
        guard u.allSatisfy(\.isFinite), v.allSatisfy(\.isFinite), pressure.allSatisfy(\.isFinite) else { throw ProjectDataError.contract("投影数值发散。") }
        let elapsed = start.duration(to: .now).components
        return .init(columns: nx, rows: ny, horizontalFaceVelocity: u, verticalFaceVelocity: v, pressure: pressure,
            fluidMask: fluidMask, initialMaximumDivergence: maximumInitial, finalMaximumDivergence: maximumFinal,
            iterations: iterations, elapsedSeconds: Double(elapsed.seconds)+Double(elapsed.attoseconds)/1e18,
            estimatedArrayBytes: (u.count+v.count+pressure.count+rhs.count+initial.count)*8+fluidMask.count,
            converged: maximumFinal <= tolerance)
    }
}
