import Foundation

/// Drives the parent deck list (Spec §8.3).
///
/// Mirrors `StudyViewModel`'s style: `@MainActor`, `@Published private(set)`
/// state, a dependency-injected repository, and a `sample()` factory for
/// previews. Talks only to `DeckRepository` and exposes value types — no
/// `NSManagedObject` ever reaches the view (Spec §4.1).
@MainActor
final class DeckEditorViewModel: ObservableObject {
    @Published private(set) var decks: [DeckSummary] = []
    /// Last error, surfaced to the parent rather than swallowed (Spec §8.3).
    @Published var errorMessage: String?

    private let repository: DeckRepository
    private var remoteChanges: RemoteChangeObserver?

    init(repository: DeckRepository = DeckRepository()) {
        self.repository = repository
        // Refresh when another device's changes sync in (Spec §10.1).
        remoteChanges = RemoteChangeObserver { [weak self] in self?.load() }
    }

    /// (Re)load the deck list from the store.
    func load() {
        perform { self.decks = try self.repository.fetchDecks() }
    }

    @discardableResult
    func createDeck(title: String) -> DeckSummary? {
        let trimmed = title.trimmed
        guard !trimmed.isEmpty else { return nil }
        var created: DeckSummary?
        perform { created = try self.repository.createDeck(title: trimmed) }
        load()
        return created
    }

    func renameDeck(id: UUID, title: String) {
        let trimmed = title.trimmed
        guard !trimmed.isEmpty else { return }
        perform { try self.repository.renameDeck(id: id, title: trimmed) }
        load()
    }

    func deleteDeck(id: UUID) {
        perform { try self.repository.deleteDeck(id: id) }
        load()
    }

    /// A card-list view model for `deck`, sharing this repository so previews and
    /// the live store stay consistent.
    func makeDetailViewModel(for deck: DeckSummary) -> DeckDetailViewModel {
        DeckDetailViewModel(deck: deck, repository: repository)
    }

    /// A song-list view model for `deck` (Spec §14.3), sharing this repository.
    func makeSongDeckViewModel(for deck: DeckSummary) -> SongDeckViewModel {
        SongDeckViewModel(deck: deck, repository: repository)
    }

    /// Run a throwing repository call, surfacing any error to the parent.
    private func perform(_ action: () throws -> Void) {
        do { try action() }
        catch { errorMessage = error.localizedDescription }
    }

    /// Preview/test factory backed by the in-memory store, pre-seeded with decks.
    static func sample() -> DeckEditorViewModel {
        let repository = DeckRepository.preview
        if (try? repository.fetchDecks())?.isEmpty ?? true {
            if let spanish = try? repository.createDeck(title: "Spanish — Animals") {
                _ = try? repository.addCard(to: spanish.id, front: "el perro", back: "the dog", hint: nil)
                _ = try? repository.addCard(to: spanish.id, front: "el gato", back: "the cat", hint: "a feline")
                _ = try? repository.addCard(to: spanish.id, front: "el pájaro", back: "the bird", hint: nil)
            }
            _ = try? repository.createDeck(title: "Multiplication × 7")
        }
        let model = DeckEditorViewModel(repository: repository)
        model.load()
        return model
    }
}

/// Drives one deck's card list + editing (Spec §8.3).
///
/// A companion to `DeckEditorViewModel`: keeping per-deck card state in its own
/// `@MainActor` object avoids a single shared mutable `cards` array aliasing
/// across pushed detail screens. Both view models share one `DeckRepository`.
@MainActor
final class DeckDetailViewModel: ObservableObject {
    @Published private(set) var deck: DeckSummary
    @Published private(set) var cards: [CardDraft] = []
    /// All category tags in the store, for the card editor's picker (Spec §14.2).
    @Published private(set) var allTags: [TagSummary] = []
    @Published var errorMessage: String?

    private let repository: DeckRepository
    private var remoteChanges: RemoteChangeObserver?

    init(deck: DeckSummary, repository: DeckRepository = DeckRepository()) {
        self.deck = deck
        self.repository = repository
        // Refresh this deck's cards when another device's changes sync in (§10.1).
        remoteChanges = RemoteChangeObserver { [weak self] in self?.load() }
    }

    /// Category names offered by the card editor's picker.
    var allTagNames: [String] { allTags.map(\.name) }

    /// (Re)load this deck's cards (and the tag vocabulary) from the store.
    func load() {
        perform {
            self.cards = try self.repository.fetchCards(in: self.deck.id)
            self.allTags = try self.repository.fetchTags()
        }
    }

    func addCard(_ edits: CardEdits) {
        perform {
            let card = try self.repository.addCard(to: self.deck.id,
                                                   front: edits.front.trimmed,
                                                   back: edits.back.trimmed,
                                                   hint: edits.hint.trimmedOrNil)
            try self.repository.setTagNames(edits.tags, forCard: card.id)
            try self.repository.setImages(front: edits.frontImage, back: edits.backImage,
                                          forCard: card.id)
        }
        load()
    }

    /// Edit a card's content, categories and images. Its stable id is preserved.
    func updateCard(id: UUID, _ edits: CardEdits) {
        perform {
            try self.repository.updateCard(id: id,
                                           front: edits.front.trimmed,
                                           back: edits.back.trimmed,
                                           hint: edits.hint.trimmedOrNil)
            try self.repository.setTagNames(edits.tags, forCard: id)
            try self.repository.setImages(front: edits.frontImage, back: edits.backImage,
                                          forCard: id)
        }
        load()
    }

    /// Delete the cards at the given list offsets (from `.onDelete` / a menu).
    func deleteCards(at offsets: IndexSet) {
        let ids = offsets.map { cards[$0].id }
        perform { for id in ids { try self.repository.deleteCard(id: id) } }
        load()
    }

    func deleteCard(id: UUID) {
        perform { try self.repository.deleteCard(id: id) }
        load()
    }

    /// Reorder via `.onMove`: apply optimistically, then persist the new order.
    func moveCards(from source: IndexSet, to destination: Int) {
        var reordered = cards
        reordered.move(fromOffsets: source, toOffset: destination)
        cards = reordered
        perform { try self.repository.reorderCards(in: self.deck.id, to: reordered.map(\.id)) }
        load()
    }

    private func perform(_ action: () throws -> Void) {
        do { try action() }
        catch { errorMessage = error.localizedDescription }
    }

    /// Preview/test factory backed by the in-memory store (reuses the seeded
    /// `DeckEditorViewModel.sample()` decks, picking one that has cards).
    static func sample() -> DeckDetailViewModel {
        let editor = DeckEditorViewModel.sample()
        let deck = editor.decks.first(where: { $0.cardCount > 0 })
            ?? editor.decks.first
            ?? DeckSummary(id: UUID(), title: "Sample deck", cardCount: 0)
        let model = editor.makeDetailViewModel(for: deck)
        model.load()
        return model
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
    var trimmedOrNil: String? {
        let value = trimmed
        return value.isEmpty ? nil : value
    }
}
