import Foundation

/// Conversation data for the in-app consult assistant (ADR-022).
/// Pure record: the role and the text. Sensitive rendering (bubbles,
/// colours) lives in the workspace layer.
public struct ChatTurn: Codable, Equatable, Identifiable, Sendable, Hashable {
    /// Who spoke. The system role never leaves the client; history only
    /// carries what the user saw.
    public enum Role: String, Codable, Sendable {
        case user
        case assistant
    }

    public var id: UUID
    public var role: Role
    public var text: String
    public var sentAt: Date

    public init(id: UUID = UUID(), role: Role, text: String, sentAt: Date = Date()) {
        self.id = id
        self.role = role
        self.text = text
        self.sentAt = sentAt
    }
}
