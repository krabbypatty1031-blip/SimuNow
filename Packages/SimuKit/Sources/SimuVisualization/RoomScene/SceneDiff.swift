import Foundation

public struct SceneDiff: Equatable, Sendable {
    public let added: [SceneNodeKey]
    public let removed: [SceneNodeKey]
    public let geometry: [SceneNodeKey]
    public let transform: [SceneNodeKey]
    public let material: [SceneNodeKey]
    public let selection: [SceneNodeKey]
    public init(old: SceneDescriptor?, new: SceneDescriptor) {
        let before = Dictionary((old?.nodes ?? []).map { ($0.key,$0) }, uniquingKeysWith: { first,_ in first })
        let after = Dictionary(new.nodes.map { ($0.key,$0) }, uniquingKeysWith: { first,_ in first })
        added = new.nodes.filter { before[$0.key] == nil }.map(\.key)
        removed = (old?.nodes ?? []).filter { after[$0.key] == nil }.map(\.key)
        let pairs = new.nodes.compactMap { node in before[node.key].map { ($0,node) } }
        geometry = pairs.filter { $0.0.geometry != $0.1.geometry }.map { $0.1.key }
        transform = pairs.filter { $0.0.position != $0.1.position }.map { $0.1.key }
        material = pairs.filter { $0.0.material != $0.1.material }.map { $0.1.key }
        selection = pairs.filter { $0.0.selectable != $0.1.selectable }.map { $0.1.key }
    }
    public var isEmpty: Bool { added.isEmpty && removed.isEmpty && geometry.isEmpty && transform.isEmpty && material.isEmpty && selection.isEmpty }
}
