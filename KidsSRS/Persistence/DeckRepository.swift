import CoreData
import CryptoKit
import KidsSRSCore

// MARK: - UI-facing value types

/// A lightweight, value-type summary of a deck for list display.
///
/// Spec §4.1 guardrail: views and view models never see `DeckMO` — only these
/// plain values cross the repository boundary. `Identifiable` on the **stable**
/// deck id (Spec §5).
struct DeckSummary: Identifiable, Equatable, Hashable {
    /// Stable, permanent deck identity (Spec §5). Never reassigned on edit.
    let id: UUID
    var title: String
    var cardCount: Int
    /// A bundled starter deck (Spec §9.1): assignable, but not parent-editable.
    var isBundled: Bool = false
}

/// A value-type snapshot of one card, used for both display and editing.
///
/// `Identifiable` on the **stable** card id (Spec §5 / §9.2) — the id survives
/// text edits, which is what lets catalog merge preserve a child's progress.
struct CardDraft: Identifiable, Equatable, Hashable {
    /// Stable, permanent card identity (Spec §5 / §9.2). Survives content edits.
    let id: UUID
    var front: String
    var back: String
    /// Optional hint; an empty string is normalized to `nil` on write.
    var hint: String?
    /// Contiguous, 0-based position within its deck.
    var order: Int
    /// Category names on this card (Spec §14.2), sorted. Used by Game Mode.
    var tags: [String] = []
    /// Optional front/back images (Spec §5), already downsized JPEG data.
    var frontImage: Data?
    var backImage: Data?
}

/// A value-type summary of a category tag (Spec §14.2). `Identifiable` on the
/// stable tag id; card-level and shared across decks.
struct TagSummary: Identifiable, Equatable, Hashable {
    let id: UUID
    var name: String
}

/// One song in a Song Review playlist (Spec §14.3): a video card's display
/// title and its YouTube id, ready for the player. The view never sees `CardMO`.
struct PlaylistSong: Identifiable, Equatable {
    let id: UUID
    var title: String
    var videoRef: String
    var hint: String?
}

/// Errors surfaced by `DeckRepository`.
///
/// Spec §8.3: the editor must surface failures rather than swallow them.
enum DeckRepositoryError: LocalizedError {
    case deckNotFound(UUID)
    case cardNotFound(UUID)
    case childNotFound(UUID)
    case tagNotFound(UUID)
    case invalidVideoReference(String)

    var errorDescription: String? {
        switch self {
        case .deckNotFound: return "That deck could no longer be found."
        case .cardNotFound: return "That card could no longer be found."
        case .childNotFound: return "That child profile could no longer be found."
        case .tagNotFound: return "That category could no longer be found."
        case .invalidVideoReference:
            return "That doesn't look like a YouTube link. Paste a video URL or its ID."
        }
    }
}

// MARK: - Repository

/// The Core Data boundary for parent deck/card authoring (Spec §8.3).
///
/// Spec §4.1 architectural guardrail: SwiftUI views must **never** touch
/// `NSManagedObject`. This repository owns the context and exchanges only the
/// value types above (`DeckSummary`, `CardDraft`) with the view-model layer.
///
/// All writes `save()` immediately and `throw` on failure so callers can
/// surface the error to the parent. Because it is bound to a (main-queue)
/// view context, it is used synchronously from the `@MainActor` view models.
final class DeckRepository {
    /// The parent-authored origin tag (Spec §5 `Deck.origin`).
    static let parentAuthoredOrigin = "parentAuthored"
    /// The bundled starter-deck origin tag (Spec §9.1).
    static let bundledOrigin = "bundled"

    private let context: NSManagedObjectContext

    /// Designated initializer — inject any context (e.g. a preview/in-memory one).
    init(context: NSManagedObjectContext) {
        self.context = context
    }

    /// Convenience: back the repository with a `PersistenceController` (defaults
    /// to the shared store; pass `.preview` for previews/tests).
    convenience init(persistence: PersistenceController = .shared) {
        self.init(context: persistence.container.viewContext)
    }

    /// An in-memory repository for SwiftUI previews and unit tests.
    static var preview: DeckRepository {
        DeckRepository(persistence: .preview)
    }

    // MARK: Decks

    /// All `parentAuthored` decks, sorted by title (case-insensitive).
    func fetchDecks() throws -> [DeckSummary] {
        let request = NSFetchRequest<DeckMO>(entityName: "Deck")
        request.predicate = NSPredicate(format: "origin == %@", Self.parentAuthoredOrigin)
        request.sortDescriptors = [Self.titleSort]
        return try context.fetch(request).map(Self.summary(from:))
    }

    /// All decks a parent can assign to a child (Spec §8.3 / §9.1): both
    /// `parentAuthored` and `bundled`. (The editor's `fetchDecks` stays
    /// authored-only — bundled decks aren't parent-editable.)
    func fetchAssignableDecks() throws -> [DeckSummary] {
        let request = NSFetchRequest<DeckMO>(entityName: "Deck")
        request.predicate = NSPredicate(format: "origin IN %@",
                                        [Self.parentAuthoredOrigin, Self.bundledOrigin])
        request.sortDescriptors = [Self.titleSort]
        return try context.fetch(request).map(Self.summary(from:))
    }

    /// Idempotently create bundled starter decks from packs (Spec §9.1). A pack
    /// whose deck id already exists is skipped (in-place content merge of an
    /// updated pack is the v2 catalog concern, §9.2). Returns the number created.
    @discardableResult
    func importBundled(_ packs: [DeckPack]) throws -> Int {
        let existing = try existingDeckIDs(in: packs.map(\.id))
        var created = 0
        for pack in packs where !existing.contains(pack.id) {
            let deck = DeckMO(context: context)
            deck.id = pack.id
            deck.title = pack.title
            deck.subjectTag = pack.subjectTag
            deck.origin = Self.bundledOrigin
            deck.version = Int32(pack.version)
            for (index, card) in pack.cards.enumerated() {
                let cardMO = CardMO(context: context)
                cardMO.id = card.id
                cardMO.deck = deck
                cardMO.order = Int32(index)
                apply(front: card.front, back: card.back, hint: card.hint, to: cardMO)
            }
            created += 1
        }
        try save()
        return created
    }

    /// Create a new `parentAuthored` deck (Spec §5: `origin`, `version = 1`).
    @discardableResult
    func createDeck(title: String) throws -> DeckSummary {
        let deck = DeckMO(context: context)
        deck.id = UUID()
        deck.title = title
        deck.origin = Self.parentAuthoredOrigin
        deck.version = 1
        try save()
        return Self.summary(from: deck)
    }

    /// Rename a deck. Identity is preserved (Spec §5).
    func renameDeck(id: UUID, title: String) throws {
        let deck = try deckMO(id: id)
        deck.title = title
        try save()
    }

    /// Delete a deck and (by the model's cascade rule) its cards.
    func deleteDeck(id: UUID) throws {
        let deck = try deckMO(id: id)
        context.delete(deck)
        try save()
    }

    // MARK: Cards

    /// One deck's cards as value types, sorted by `order`.
    func fetchCards(in deckID: UUID) throws -> [CardDraft] {
        let deck = try deckMO(id: deckID)
        return cards(of: deck).map(Self.draft(from:))
    }

    /// Append a new card to a deck. Assigns a fresh **stable** id, the next
    /// contiguous `order`, and a `contentHash` (Spec §5 / §9.2).
    @discardableResult
    func addCard(to deckID: UUID, front: String, back: String, hint: String?) throws -> CardDraft {
        let deck = try deckMO(id: deckID)
        let nextOrder = cards(of: deck).count // count existing BEFORE inserting
        let card = CardMO(context: context)
        card.id = UUID()
        card.deck = deck
        card.order = Int32(nextOrder) // append at end, contiguous
        apply(front: front, back: back, hint: hint, to: card)
        try save()
        return Self.draft(from: card)
    }

    /// Edit a card's content. Spec §5/§9.2: the id is **permanent** — we mutate
    /// text only and recompute `contentHash`, never touching `id` or `order`.
    func updateCard(id: UUID, front: String, back: String, hint: String?) throws {
        let card = try cardMO(id: id)
        apply(front: front, back: back, hint: hint, to: card)
        try save()
    }

    /// Delete a card, then re-pack the deck's `order` so it stays contiguous.
    func deleteCard(id: UUID) throws {
        let card = try cardMO(id: id)
        let deck = card.deck
        context.delete(card)
        if let deck { normalizeOrder(in: deck) }
        try save()
    }

    // MARK: Songs / video cards (Spec §14.2 / §14.3)

    /// Append a video (song) card to a deck. `youTube` may be a full URL or a
    /// bare id; it is normalized to an 11-char video id (Spec §14.2) and rejected
    /// if unparseable. Sets `kind = "video"` and stores the title as `frontText`.
    @discardableResult
    func addVideoCard(to deckID: UUID, title: String, youTube: String, hint: String?) throws -> CardDraft {
        guard let videoID = YouTubeVideoID.extract(from: youTube) else {
            throw DeckRepositoryError.invalidVideoReference(youTube)
        }
        let deck = try deckMO(id: deckID)
        let normalizedHint = (hint?.isEmpty ?? true) ? nil : hint
        let card = CardMO(context: context)
        card.id = UUID()
        card.deck = deck
        card.order = Int32(cards(of: deck).count) // append, contiguous
        card.kind = "video"
        card.videoRef = videoID
        card.frontText = title
        card.backText = nil
        card.hint = normalizedHint
        // A song has no "back"; fold the video id into the hash so content edits
        // (title / id / hint) still change `contentHash` for §9.2 merge.
        card.contentHash = Self.contentHash(front: title, back: videoID, hint: normalizedHint)
        try save()
        return Self.draft(from: card)
    }

    /// A deck's video (song) cards as playlist entries, in `order`. Text/image
    /// cards in the same deck are excluded — those study via the card flow.
    func fetchSongs(in deckID: UUID) throws -> [PlaylistSong] {
        let deck = try deckMO(id: deckID)
        return cards(of: deck)
            .filter { $0.kind == "video" }
            .map { PlaylistSong(id: $0.id ?? UUID(),
                                title: $0.frontText ?? "",
                                videoRef: $0.videoRef ?? "",
                                hint: $0.hint) }
    }

    /// Create a parent-authored **song deck** from imported videos (Spec §14.3):
    /// the deck title + one `video` card per song, in playlist order, in one save.
    @discardableResult
    func createSongDeck(title: String, songs: [(videoID: String, title: String)]) throws -> DeckSummary {
        let deck = DeckMO(context: context)
        deck.id = UUID()
        deck.title = title
        deck.origin = Self.parentAuthoredOrigin
        deck.version = 1
        for (index, song) in songs.enumerated() {
            let card = CardMO(context: context)
            card.id = UUID()
            card.deck = deck
            card.order = Int32(index)
            card.kind = "video"
            card.videoRef = song.videoID
            card.frontText = song.title
            card.contentHash = Self.contentHash(front: song.title, back: song.videoID, hint: nil)
        }
        try save()
        return Self.summary(from: deck)
    }

    // MARK: Assignment (Spec §8.2 / §8.3 — decks assignable to children)

    /// The ids of decks currently assigned to a child.
    func assignedDeckIDs(forChild childID: UUID) throws -> Set<UUID> {
        let child = try childMO(id: childID)
        let decks = (child.assignedDecks as? Set<DeckMO>) ?? []
        return Set(decks.compactMap(\.id))
    }

    /// Assign or unassign a deck to/from a child (many-to-many, Spec §8.3).
    /// Idempotent — assigning an already-assigned deck is a no-op.
    func setDeck(_ deckID: UUID, assigned: Bool, toChild childID: UUID) throws {
        let deck = try deckMO(id: deckID)
        let child = try childMO(id: childID)
        // KVC-based mutation avoids depending on generated accessor names.
        let assignedDecks = child.mutableSetValue(forKey: "assignedDecks")
        if assigned {
            assignedDecks.add(deck)
        } else {
            assignedDecks.remove(deck)
        }
        try save()
    }

    /// Persist a new card order. `orderedIDs` is the full desired sequence; any
    /// card not named keeps its relative position after the named set. Resulting
    /// `order` values are contiguous and 0-based.
    func reorderCards(in deckID: UUID, to orderedIDs: [UUID]) throws {
        let deck = try deckMO(id: deckID)
        var byID: [UUID: CardMO] = [:]
        for card in cards(of: deck) where card.id != nil {
            byID[card.id!] = card
        }
        var next = 0
        for cardID in orderedIDs {
            guard let card = byID.removeValue(forKey: cardID) else { continue }
            card.order = Int32(next)
            next += 1
        }
        // Anything not referenced keeps its prior relative order, appended after.
        for card in byID.values.sorted(by: { $0.order < $1.order }) {
            card.order = Int32(next)
            next += 1
        }
        try save()
    }

    // MARK: Tags / categories (Spec §14.2 — card-level, cross-deck)

    /// All category tags, sorted by name (case-insensitive).
    func fetchTags() throws -> [TagSummary] {
        let request = NSFetchRequest<TagMO>(entityName: "Tag")
        request.sortDescriptors = [Self.nameSort]
        return try context.fetch(request).map(Self.tagSummary(from:))
    }

    /// Find an existing tag by trimmed, case-insensitive name, or create one.
    /// Tags carry no CloudKit unique constraint (Spec §4.1), so de-duping by name
    /// is enforced here rather than by the store.
    @discardableResult
    func findOrCreateTag(name: String) throws -> TagSummary {
        let tag = try findOrCreateTagMO(name: name)
        try save()
        return Self.tagSummary(from: tag)
    }

    /// Find-or-create returning the managed object; the caller saves. Trims and
    /// de-dupes by case-insensitive name (Spec §14.2).
    private func findOrCreateTagMO(name: String) throws -> TagMO {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let request = NSFetchRequest<TagMO>(entityName: "Tag")
        request.predicate = NSPredicate(format: "name ==[c] %@", trimmed)
        request.fetchLimit = 1
        if let existing = try context.fetch(request).first { return existing }
        let tag = TagMO(context: context)
        tag.id = UUID()
        tag.name = trimmed
        return tag
    }

    /// Delete a tag; its links to cards drop via the model's Nullify rule.
    func deleteTag(id: UUID) throws {
        let tag = try tagMO(id: id)
        context.delete(tag)
        try save()
    }

    /// The ids of tags currently on a card.
    func tagIDs(forCard cardID: UUID) throws -> Set<UUID> {
        let card = try cardMO(id: cardID)
        let tags = (card.tags as? Set<TagMO>) ?? []
        return Set(tags.compactMap(\.id))
    }

    /// Replace a card's full tag set (Spec §14.2). Idempotent. KVC mutation
    /// avoids depending on the generated to-many accessor name.
    func setTags(_ tagIDs: Set<UUID>, forCard cardID: UUID) throws {
        let card = try cardMO(id: cardID)
        let desired = try tagMOs(ids: tagIDs)
        let tags = card.mutableSetValue(forKey: "tags")
        tags.removeAllObjects()
        for tag in desired { tags.add(tag) }
        try save()
    }

    /// Replace a card's tags by **name** (Spec §14.2): existing names reuse their
    /// tag, new names are created, blanks/case-dupes are ignored. The card editor
    /// uses this so parents work in category names, not ids.
    func setTagNames(_ names: [String], forCard cardID: UUID) throws {
        let card = try cardMO(id: cardID)
        var resolved: [TagMO] = []
        var seen = Set<String>()
        for raw in names {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seen.insert(trimmed.lowercased()).inserted else { continue }
            resolved.append(try findOrCreateTagMO(name: trimmed))
        }
        let tags = card.mutableSetValue(forKey: "tags")
        tags.removeAllObjects()
        for tag in resolved { tags.add(tag) }
        try save()
    }

    // MARK: Images (Spec §5)

    /// Set/clear a card's front and back images. Pass `nil` to remove a side's
    /// image. Callers pass already-downsized data (`ImageDownsizer`, Spec §5).
    func setImages(front: Data?, back: Data?, forCard cardID: UUID) throws {
        let card = try cardMO(id: cardID)
        card.frontImage = front
        card.backImage = back
        try save()
    }

    // MARK: Content hashing (Spec §9.2)

    /// SHA-256 of `front \0 back \0 hint`, hex-encoded. Spec §9.2 uses this to
    /// detect content changes during catalog merge.
    static func contentHash(front: String, back: String, hint: String?) -> String {
        let payload = "\(front)\u{0}\(back)\u{0}\(hint ?? "")"
        let digest = SHA256.hash(data: Data(payload.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Private helpers

    /// Set a card's text + content hash, normalizing an empty hint to `nil`.
    private func apply(front: String, back: String, hint: String?, to card: CardMO) {
        let normalizedHint = (hint?.isEmpty ?? true) ? nil : hint
        card.frontText = front
        card.backText = back
        card.hint = normalizedHint
        card.contentHash = Self.contentHash(front: front, back: back, hint: normalizedHint)
    }

    /// Re-pack a deck's card `order` into a contiguous 0-based sequence,
    /// preserving relative order. Keeps ordering consistent after a delete.
    private func normalizeOrder(in deck: DeckMO) {
        for (index, card) in cards(of: deck).enumerated() {
            card.order = Int32(index)
        }
    }

    /// The deck's live (non-deleted) cards, sorted by `order`.
    private func cards(of deck: DeckMO) -> [CardMO] {
        let set = (deck.cards as? Set<CardMO>) ?? []
        return set.filter { !$0.isDeleted }.sorted { $0.order < $1.order }
    }

    private func deckMO(id: UUID) throws -> DeckMO {
        guard let deck = try context.fetchFirst(DeckMO.self, entityName: "Deck", id: id) else {
            throw DeckRepositoryError.deckNotFound(id)
        }
        return deck
    }

    private func cardMO(id: UUID) throws -> CardMO {
        guard let card = try context.fetchFirst(CardMO.self, entityName: "Card", id: id) else {
            throw DeckRepositoryError.cardNotFound(id)
        }
        return card
    }

    private func tagMO(id: UUID) throws -> TagMO {
        guard let tag = try context.fetchFirst(TagMO.self, entityName: "Tag", id: id) else {
            throw DeckRepositoryError.tagNotFound(id)
        }
        return tag
    }

    /// The `TagMO`s for a set of ids (order unspecified).
    private func tagMOs(ids: Set<UUID>) throws -> [TagMO] {
        guard !ids.isEmpty else { return [] }
        let request = NSFetchRequest<TagMO>(entityName: "Tag")
        request.predicate = NSPredicate(format: "id IN %@", ids.map { $0 as NSUUID })
        return try context.fetch(request)
    }

    private func childMO(id: UUID) throws -> ChildMO {
        guard let child = try context.fetchFirst(ChildMO.self, entityName: "Child", id: id) else {
            throw DeckRepositoryError.childNotFound(id)
        }
        return child
    }

    private func save() throws {
        guard context.hasChanges else { return }
        try context.save()
    }

    /// Which of `ids` already exist as decks (for idempotent bundled import).
    private func existingDeckIDs(in ids: [UUID]) throws -> Set<UUID> {
        guard !ids.isEmpty else { return [] }
        let request = NSFetchRequest<DeckMO>(entityName: "Deck")
        request.predicate = NSPredicate(format: "id IN %@", ids.map { $0 as NSUUID })
        return Set(try context.fetch(request).compactMap(\.id))
    }

    /// Shared case-insensitive title sort.
    private static let titleSort = NSSortDescriptor(
        key: "title", ascending: true,
        selector: #selector(NSString.localizedCaseInsensitiveCompare(_:)))

    /// Shared case-insensitive name sort (tags).
    private static let nameSort = NSSortDescriptor(
        key: "name", ascending: true,
        selector: #selector(NSString.localizedCaseInsensitiveCompare(_:)))

    // MARK: Mapping (defensive — all MO attributes are optional, Spec §5)

    private static func summary(from deck: DeckMO) -> DeckSummary {
        let liveCards = (deck.cards as? Set<CardMO>)?.filter { !$0.isDeleted } ?? []
        return DeckSummary(
            id: deck.id ?? UUID(),
            title: deck.title ?? "",
            cardCount: liveCards.count,
            isBundled: deck.origin == bundledOrigin
        )
    }

    private static func draft(from card: CardMO) -> CardDraft {
        let tagNames = ((card.tags as? Set<TagMO>) ?? [])
            .compactMap(\.name)
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        return CardDraft(
            id: card.id ?? UUID(),
            front: card.frontText ?? "",
            back: card.backText ?? "",
            hint: card.hint,
            order: Int(card.order),
            tags: tagNames,
            frontImage: card.frontImage,
            backImage: card.backImage
        )
    }

    private static func tagSummary(from tag: TagMO) -> TagSummary {
        TagSummary(id: tag.id ?? UUID(), name: tag.name ?? "")
    }
}
