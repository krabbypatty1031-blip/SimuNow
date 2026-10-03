import SwiftUI
import RealityKit
#if os(macOS)
import AppKit
private typealias RoomColor = NSColor
#else
import UIKit
private typealias RoomColor = UIColor
#endif

@available(macOS 15, iOS 18, *)
@MainActor
final class RoomMaterialPalette {
    private var materials: [String: SimpleMaterial] = [:]
    var count: Int { materials.count }
    func material(_ role: RoomSceneMaterial, dark: Bool, selected: Bool = false) -> SimpleMaterial {
        let key = role.rawValue + (dark ? "/dark" : "/light") + (selected ? "/selected" : "")
        if let cached = materials[key] { return cached }
        let color: RoomColor
        if selected { color = .systemYellow }
        else {
            switch role {
            case .wall: color = dark ? RoomColor(white: 0.42, alpha: 1) : RoomColor(white: 0.77, alpha: 1)
            case .floor: color = dark ? RoomColor(white: 0.24, alpha: 1) : RoomColor(white: 0.62, alpha: 1)
            case .door: color = .systemBrown
            case .window, .sample: color = .systemBlue
            case .furniture: color = dark ? .systemGray : .systemBrown
            case .seat: color = .systemIndigo
            case .occupant: color = .systemPurple
            case .equipment: color = .systemOrange
            case .hvac, .returnPort: color = .systemTeal
            case .supply, .preview: color = .systemCyan
            case .control: color = .systemPink
            case .north: color = .systemRed
            case .blocked: color = .systemOrange
            }
        }
        let value = SimpleMaterial(color: color, roughness: 0.85, isMetallic: false)
        materials[key] = value; return value
    }
    func clear() { materials.removeAll() }
}
