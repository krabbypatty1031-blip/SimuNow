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
    /// True when the guard appended the caution note for this reply (ADR-022).
    /// The note is display metadata only: `text` keeps the model's own words,
    /// so the note never enters the history the next round's model sees.
    public var hasCautionNote: Bool

    public init(id: UUID = UUID(), role: Role, text: String, sentAt: Date = Date(), hasCautionNote: Bool = false) {
        self.id = id
        self.role = role
        self.text = text
        self.sentAt = sentAt
        self.hasCautionNote = hasCautionNote
    }

    /// Tolerant decode: turns persisted before the flag existed (or decoded
    /// from test fixtures) carry no key; a missing flag reads as "no note".
    private enum CodingKeys: String, CodingKey {
        case id, role, text, sentAt, hasCautionNote
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        role = try container.decode(Role.self, forKey: .role)
        text = try container.decode(String.self, forKey: .text)
        sentAt = try container.decode(Date.self, forKey: .sentAt)
        hasCautionNote = try container.decodeIfPresent(Bool.self, forKey: .hasCautionNote) ?? false
    }
}
