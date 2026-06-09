import Foundation

/// The on-device deck content format (Spec §9.1). v1 ships a **bundled** subset
/// using this exact shape so the v2 catalog (CDN deck packs, §9.2) can decode
/// the same format — only the source (app bundle vs. network) differs.
///
/// IDs are **permanent** (Spec §5 / §9.2): they key a child's `CardState`, so a
/// content edit updates text in place without resetting progress.
public struct DeckPack: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let title: String
    public let subjectTag: String?
    public let version: Int
    public let cards: [CardPack]

    public init(id: UUID, title: String, subjectTag: String?, version: Int, cards: [CardPack]) {
        self.id = id
        self.title = title
        self.subjectTag = subjectTag
        self.version = version
        self.cards = cards
    }
}

/// One text card within a `DeckPack`.
public struct CardPack: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let front: String
    public let back: String
    public let hint: String?

    public init(id: UUID, front: String, back: String, hint: String?) {
        self.id = id
        self.front = front
        self.back = back
        self.hint = hint
    }
}
