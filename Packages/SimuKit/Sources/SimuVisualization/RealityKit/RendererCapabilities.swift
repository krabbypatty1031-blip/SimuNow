import Foundation

public struct RendererCapabilities: Equatable, Sendable {
    public let supportsNonAR3D: Bool
    public let explanation: String
    public init(supportsNonAR3D: Bool, explanation: String) { self.supportsNonAR3D = supportsNonAR3D; self.explanation = explanation }
    public static var current: Self {
        if #available(macOS 15, iOS 18, *) { return .init(supportsNonAR3D: true, explanation: "RealityKit non-AR room view") }
        return .init(supportsNonAR3D: false, explanation: "此系统使用完整二维房间编辑；三维查看需要 macOS 15 / iOS 18。")
    }
}
