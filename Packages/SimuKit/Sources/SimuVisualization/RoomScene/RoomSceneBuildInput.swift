import Foundation
import SimuCore

/// Full immutable source associated with an asynchronous descriptor build.
/// A previous picture may remain visible while rebuilding, but it cannot select/edit newer inputs.
public struct RoomSceneBuildInput: Equatable, Sendable {
    public let project: ProjectDocument
    public let scenarioID: UUID
    public init(project: ProjectDocument, scenarioID: UUID) { self.project = project; self.scenarioID = scenarioID }
    public func permitsSelection(currentProject: ProjectDocument, scenarioID: UUID) -> Bool { self.scenarioID == scenarioID && project == currentProject }
}
