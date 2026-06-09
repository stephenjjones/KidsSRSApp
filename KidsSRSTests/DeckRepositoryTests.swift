import XCTest
import CoreData
@testable import KidsSRS

/// Unit tests for `DeckRepository` against a fresh in-memory store (Spec §8.3
/// "Definition of done"). Each test gets its own controller so they're isolated.
final class DeckRepositoryTests: XCTestCase {

    private func makeRepository() -> DeckRepository {
        DeckRepository(persistence: PersistenceController(inMemory: true))
    }

    /// A repository plus the context behind it, so tests can also inspect the
    /// stored `CardMO` (e.g. its persisted `contentHash`).
    private func makeRepositoryWithContext() -> (DeckRepository, NSManagedObjectContext) {
        let context = PersistenceController(inMemory: true).container.viewContext
        return (DeckRepository(context: context), context)
    }

    private func storedContentHash(forCardID id: UUID,
                                   in context: NSManagedObjectContext) throws -> String? {
        let request = NSFetchRequest<CardMO>(entityName: "Card")
        request.predicate = NSPredicate(format: "id == %@", id as NSUUID)
        request.fetchLimit = 1
        return try context.fetch(request).first?.contentHash
    }

    // MARK: Decks

    func testCreateDeckIsParentAuthoredAndFetchable() throws {
        let repo = makeRepository()
        let created = try repo.createDeck(title: "Spanish")

        let decks = try repo.fetchDecks()
        XCTAssertEqual(decks.count, 1)
        XCTAssertEqual(decks.first?.id, created.id)
        XCTAssertEqual(decks.first?.title, "Spanish")
        XCTAssertEqual(decks.first?.cardCount, 0)
    }

    func testCreateDeckSetsOriginAndVersion() throws {
        let (repo, context) = makeRepositoryWithContext()
        let created = try repo.createDeck(title: "Spanish")

        let request = NSFetchRequest<DeckMO>(entityName: "Deck")
        request.predicate = NSPredicate(format: "id == %@", created.id as NSUUID)
        let deck = try XCTUnwrap(context.fetch(request).first)
        XCTAssertEqual(deck.origin, "parentAuthored")
        XCTAssertEqual(deck.version, 1)
    }

    func testFetchDecksReturnsOnlyParentAuthored() throws {
        let (repo, context) = makeRepositoryWithContext()
        _ = try repo.createDeck(title: "Authored")

        // A non-parentAuthored deck (e.g. bundled) must be filtered out.
        let bundled = DeckMO(context: context)
        bundled.id = UUID()
        bundled.title = "Bundled"
        bundled.origin = "bundled"
        bundled.version = 1
        try context.save()

        XCTAssertEqual(try repo.fetchDecks().map(\.title), ["Authored"])
    }

    func testFetchDecksSortedByTitleCaseInsensitive() throws {
        let repo = makeRepository()
        _ = try repo.createDeck(title: "banana")
        _ = try repo.createDeck(title: "Apple")
        _ = try repo.createDeck(title: "cherry")

        XCTAssertEqual(try repo.fetchDecks().map(\.title), ["Apple", "banana", "cherry"])
    }

    func testRenameDeckPreservesIdentity() throws {
        let repo = makeRepository()
        let deck = try repo.createDeck(title: "Old")

        try repo.renameDeck(id: deck.id, title: "New")

        let decks = try repo.fetchDecks()
        XCTAssertEqual(decks.count, 1)
        XCTAssertEqual(decks.first?.id, deck.id, "Rename must not reassign the deck id")
        XCTAssertEqual(decks.first?.title, "New")
    }

    func testDeleteDeckRemovesDeckAndCards() throws {
        let repo = makeRepository()
        let deck = try repo.createDeck(title: "Doomed")
        try repo.addCard(to: deck.id, front: "a", back: "b", hint: nil)

        try repo.deleteDeck(id: deck.id)

        XCTAssertTrue(try repo.fetchDecks().isEmpty)
        XCTAssertThrowsError(try repo.fetchCards(in: deck.id))
    }

    func testMutatingMethodsThrowForMissingDeck() {
        let repo = makeRepository()
        XCTAssertThrowsError(try repo.renameDeck(id: UUID(), title: "x"))
        XCTAssertThrowsError(try repo.deleteDeck(id: UUID()))
        XCTAssertThrowsError(try repo.addCard(to: UUID(), front: "a", back: "b", hint: nil))
    }

    // MARK: Cards — identity & content hash

    func testAddCardAssignsStableIdContiguousOrderAndContentHash() throws {
        let (repo, context) = makeRepositoryWithContext()
        let deck = try repo.createDeck(title: "Deck")

        let first = try repo.addCard(to: deck.id, front: "el perro", back: "the dog", hint: nil)
        let second = try repo.addCard(to: deck.id, front: "el gato", back: "the cat", hint: "feline")

        XCTAssertEqual(first.order, 0)
        XCTAssertEqual(second.order, 1)
        XCTAssertNotEqual(first.id, second.id)
        XCTAssertEqual(try storedContentHash(forCardID: first.id, in: context),
                       DeckRepository.contentHash(front: "el perro", back: "the dog", hint: nil))
        XCTAssertEqual(try storedContentHash(forCardID: second.id, in: context),
                       DeckRepository.contentHash(front: "el gato", back: "the cat", hint: "feline"))
    }

    func testUpdateCardPreservesIdAndUpdatesContentHash() throws {
        let (repo, context) = makeRepositoryWithContext()
        let deck = try repo.createDeck(title: "Deck")
        let card = try repo.addCard(to: deck.id, front: "cat", back: "gato", hint: nil)
        let originalHash = try storedContentHash(forCardID: card.id, in: context)

        try repo.updateCard(id: card.id, front: "cat", back: "el gato", hint: "feline")

        let cards = try repo.fetchCards(in: deck.id)
        XCTAssertEqual(cards.count, 1)
        XCTAssertEqual(cards.first?.id, card.id, "Editing a card must not reassign its id")
        XCTAssertEqual(cards.first?.back, "el gato")
        XCTAssertEqual(cards.first?.hint, "feline")

        let newHash = try storedContentHash(forCardID: card.id, in: context)
        XCTAssertNotEqual(newHash, originalHash, "contentHash must change when content changes")
        XCTAssertEqual(newHash,
                       DeckRepository.contentHash(front: "cat", back: "el gato", hint: "feline"))
    }

    func testEmptyHintIsNormalizedToNilAndHashedAsNil() throws {
        let (repo, context) = makeRepositoryWithContext()
        let deck = try repo.createDeck(title: "Deck")
        let card = try repo.addCard(to: deck.id, front: "a", back: "b", hint: "")

        let stored = try XCTUnwrap(try repo.fetchCards(in: deck.id).first)
        XCTAssertNil(stored.hint)
        // Empty hint and nil hint must hash identically.
        XCTAssertEqual(try storedContentHash(forCardID: card.id, in: context),
                       DeckRepository.contentHash(front: "a", back: "b", hint: nil))
    }

    // MARK: Cards — order maintenance

    func testDeleteCardKeepsOrderContiguous() throws {
        let repo = makeRepository()
        let deck = try repo.createDeck(title: "Deck")
        let a = try repo.addCard(to: deck.id, front: "a", back: "1", hint: nil)
        let b = try repo.addCard(to: deck.id, front: "b", back: "2", hint: nil)
        let c = try repo.addCard(to: deck.id, front: "c", back: "3", hint: nil)

        try repo.deleteCard(id: b.id) // remove the middle card

        let cards = try repo.fetchCards(in: deck.id)
        XCTAssertEqual(cards.map(\.front), ["a", "c"])
        XCTAssertEqual(cards.map(\.order), [0, 1], "Order must stay contiguous after delete")
        XCTAssertEqual(cards.map(\.id), [a.id, c.id])
    }

    func testReorderCardsPersistsContiguousOrder() throws {
        let repo = makeRepository()
        let deck = try repo.createDeck(title: "Deck")
        let a = try repo.addCard(to: deck.id, front: "a", back: "1", hint: nil)
        let b = try repo.addCard(to: deck.id, front: "b", back: "2", hint: nil)
        let c = try repo.addCard(to: deck.id, front: "c", back: "3", hint: nil)

        // New order: c, a, b
        try repo.reorderCards(in: deck.id, to: [c.id, a.id, b.id])

        let cards = try repo.fetchCards(in: deck.id)
        XCTAssertEqual(cards.map(\.front), ["c", "a", "b"])
        XCTAssertEqual(cards.map(\.order), [0, 1, 2])
        XCTAssertEqual(Set(cards.map(\.id)), Set([a.id, b.id, c.id]))
    }

    func testReorderWithSubsetAppendsRemainderContiguously() throws {
        let repo = makeRepository()
        let deck = try repo.createDeck(title: "Deck")
        let a = try repo.addCard(to: deck.id, front: "a", back: "1", hint: nil)
        let b = try repo.addCard(to: deck.id, front: "b", back: "2", hint: nil)
        let c = try repo.addCard(to: deck.id, front: "c", back: "3", hint: nil)

        // Only name the last card; the rest keep their relative order after it.
        try repo.reorderCards(in: deck.id, to: [c.id])

        let cards = try repo.fetchCards(in: deck.id)
        XCTAssertEqual(cards.map(\.order), [0, 1, 2])
        XCTAssertEqual(cards.map(\.id), [c.id, a.id, b.id])
    }

    // MARK: Deck↔Child assignment (Spec §8.2 / §8.3)

    /// Deck + Child repositories sharing one context, so assignment can be
    /// exercised across both entities.
    private func makeDeckAndChildRepositories() -> (DeckRepository, ChildRepository) {
        let context = PersistenceController(inMemory: true).container.viewContext
        return (DeckRepository(context: context), ChildRepository(context: context))
    }

    func testAssignDeckToChildRoundTrips() throws {
        let (decks, children) = makeDeckAndChildRepositories()
        let deck = try decks.createDeck(title: "Spanish")
        let child = try children.createChild(name: "Mia")

        XCTAssertTrue(try decks.assignedDeckIDs(forChild: child.id).isEmpty)

        try decks.setDeck(deck.id, assigned: true, toChild: child.id)
        XCTAssertEqual(try decks.assignedDeckIDs(forChild: child.id), [deck.id])

        // Idempotent.
        try decks.setDeck(deck.id, assigned: true, toChild: child.id)
        XCTAssertEqual(try decks.assignedDeckIDs(forChild: child.id), [deck.id])

        try decks.setDeck(deck.id, assigned: false, toChild: child.id)
        XCTAssertTrue(try decks.assignedDeckIDs(forChild: child.id).isEmpty)
    }

    func testAssignmentIsManyToMany() throws {
        let (decks, children) = makeDeckAndChildRepositories()
        let math = try decks.createDeck(title: "Math")
        let spanish = try decks.createDeck(title: "Spanish")
        let mia = try children.createChild(name: "Mia")
        let leo = try children.createChild(name: "Leo")

        // One deck to two children; one child to two decks.
        try decks.setDeck(math.id, assigned: true, toChild: mia.id)
        try decks.setDeck(math.id, assigned: true, toChild: leo.id)
        try decks.setDeck(spanish.id, assigned: true, toChild: mia.id)

        XCTAssertEqual(try decks.assignedDeckIDs(forChild: mia.id), [math.id, spanish.id])
        XCTAssertEqual(try decks.assignedDeckIDs(forChild: leo.id), [math.id])
    }

    func testDeletingDeckRemovesAssignmentButKeepsChild() throws {
        let (decks, children) = makeDeckAndChildRepositories()
        let deck = try decks.createDeck(title: "Spanish")
        let child = try children.createChild(name: "Mia")
        try decks.setDeck(deck.id, assigned: true, toChild: child.id)

        try decks.deleteDeck(id: deck.id)

        // Nullify: the child survives, with no dangling assignment.
        XCTAssertEqual(try children.fetchChildren().map(\.id), [child.id])
        XCTAssertTrue(try decks.assignedDeckIDs(forChild: child.id).isEmpty)
    }

    func testDeletingChildKeepsDeck() throws {
        let (decks, children) = makeDeckAndChildRepositories()
        let deck = try decks.createDeck(title: "Spanish")
        let child = try children.createChild(name: "Mia")
        try decks.setDeck(deck.id, assigned: true, toChild: child.id)

        try children.deleteChild(id: child.id)

        // Nullify: the deck survives.
        XCTAssertEqual(try decks.fetchDecks().map(\.id), [deck.id])
    }

    func testAssignmentThrowsForMissingChildOrDeck() throws {
        let (decks, children) = makeDeckAndChildRepositories()
        let deck = try decks.createDeck(title: "Spanish")
        let child = try children.createChild(name: "Mia")

        XCTAssertThrowsError(try decks.setDeck(deck.id, assigned: true, toChild: UUID()))
        XCTAssertThrowsError(try decks.setDeck(UUID(), assigned: true, toChild: child.id))
        XCTAssertThrowsError(try decks.assignedDeckIDs(forChild: UUID()))
    }

    // MARK: Tags / categories (Spec §14.2)

    func testFindOrCreateTagDeDupesByCaseInsensitiveName() throws {
        let repo = makeRepository()
        let first = try repo.findOrCreateTag(name: "Multiplication")
        let again = try repo.findOrCreateTag(name: "  multiplication ")
        XCTAssertEqual(first.id, again.id, "same name (case/space-insensitive) reuses the tag")
        XCTAssertEqual(try repo.fetchTags().count, 1)
        XCTAssertEqual(try repo.fetchTags().first?.name, "Multiplication")
    }

    func testSetTagsReplacesACardsTagSet() throws {
        let repo = makeRepository()
        let deck = try repo.createDeck(title: "Deck")
        let card = try repo.addCard(to: deck.id, front: "q", back: "a", hint: nil)
        let t1 = try repo.findOrCreateTag(name: "A")
        let t2 = try repo.findOrCreateTag(name: "B")
        let t3 = try repo.findOrCreateTag(name: "C")

        try repo.setTags([t1.id, t2.id], forCard: card.id)
        XCTAssertEqual(try repo.tagIDs(forCard: card.id), [t1.id, t2.id])

        try repo.setTags([t3.id], forCard: card.id) // replace, not merge
        XCTAssertEqual(try repo.tagIDs(forCard: card.id), [t3.id])
    }

    func testDeleteTagUnlinksItFromCards() throws {
        let repo = makeRepository()
        let deck = try repo.createDeck(title: "Deck")
        let card = try repo.addCard(to: deck.id, front: "q", back: "a", hint: nil)
        let tag = try repo.findOrCreateTag(name: "Temp")
        try repo.setTags([tag.id], forCard: card.id)

        try repo.deleteTag(id: tag.id)
        XCTAssertTrue(try repo.fetchTags().isEmpty)
        XCTAssertTrue(try repo.tagIDs(forCard: card.id).isEmpty, "Nullify drops the card link")
    }

    func testSetTagNamesCreatesReusesDeDupesAndSurfacesOnDraft() throws {
        let repo = makeRepository()
        let deck = try repo.createDeck(title: "Deck")
        let card = try repo.addCard(to: deck.id, front: "q", back: "a", hint: nil)
        _ = try repo.findOrCreateTag(name: "Math") // pre-existing

        // "Math" reused, "multiplication" created, "math" is a case-dupe → ignored.
        try repo.setTagNames(["Math", "  multiplication ", "math"], forCard: card.id)
        XCTAssertEqual(try repo.fetchTags().map(\.name).sorted(), ["Math", "multiplication"])

        // The card editor reads tags back off the draft, sorted.
        let draft = try XCTUnwrap(repo.fetchCards(in: deck.id).first)
        XCTAssertEqual(draft.tags, ["Math", "multiplication"])

        // Setting names replaces the whole set.
        try repo.setTagNames(["Geography"], forCard: card.id)
        XCTAssertEqual(try XCTUnwrap(repo.fetchCards(in: deck.id).first).tags, ["Geography"])
    }

    // MARK: Images (Spec §5)

    func testSetImagesPersistsAndClearsOnDraft() throws {
        let repo = makeRepository()
        let deck = try repo.createDeck(title: "Deck")
        // Image-only front is allowed (text optional when an image is present).
        let card = try repo.addCard(to: deck.id, front: "", back: "answer", hint: nil)
        let front = Data([0x01, 0x02, 0x03])
        let back = Data([0x09, 0x08])

        try repo.setImages(front: front, back: back, forCard: card.id)
        var draft = try XCTUnwrap(repo.fetchCards(in: deck.id).first)
        XCTAssertEqual(draft.frontImage, front)
        XCTAssertEqual(draft.backImage, back)

        // Passing nil clears that side.
        try repo.setImages(front: nil, back: back, forCard: card.id)
        draft = try XCTUnwrap(repo.fetchCards(in: deck.id).first)
        XCTAssertNil(draft.frontImage)
        XCTAssertEqual(draft.backImage, back)
    }

    // MARK: Songs / video cards (Spec §14.2 / §14.3)

    func testAddVideoCardNormalizesURLAndFetchSongsReturnsOnlyVideos() throws {
        let repo = makeRepository()
        let deck = try repo.createDeck(title: "Songs")
        _ = try repo.addCard(to: deck.id, front: "plain", back: "x", hint: nil) // not a song
        let s1 = try repo.addVideoCard(
            to: deck.id, title: "Sevens",
            youTube: "https://www.youtube.com/watch?v=abcdefghijk&list=zzz", hint: nil)
        let s2 = try repo.addVideoCard(
            to: deck.id, title: "States", youTube: "youtu.be/ABCDEFGHIJK", hint: "geography")

        let songs = try repo.fetchSongs(in: deck.id)
        XCTAssertEqual(songs.map(\.id), [s1.id, s2.id], "only video cards, in deck order")
        XCTAssertEqual(songs.first?.videoRef, "abcdefghijk")
        XCTAssertEqual(songs.first?.title, "Sevens")
        XCTAssertEqual(songs.last?.videoRef, "ABCDEFGHIJK")
        XCTAssertEqual(songs.last?.hint, "geography")
    }

    func testAddVideoCardRejectsUnparseableReference() throws {
        let repo = makeRepository()
        let deck = try repo.createDeck(title: "Songs")
        XCTAssertThrowsError(
            try repo.addVideoCard(to: deck.id, title: "bad", youTube: "https://example.com/nope", hint: nil))
    }
}
