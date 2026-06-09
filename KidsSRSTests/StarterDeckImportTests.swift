import XCTest
import CoreData
import KidsSRSCore
@testable import KidsSRS

/// Tests for bundled starter-deck import (Spec §9.1): idempotency, `bundled`
/// origin, editor exclusion, and assignability.
final class StarterDeckImportTests: XCTestCase {

    private func makeRepository() -> DeckRepository {
        DeckRepository(persistence: PersistenceController(inMemory: true))
    }

    private func samplePacks() -> [DeckPack] {
        [
            DeckPack(id: UUID(uuidString: "DECC0001-0000-0000-0000-000000000001")!,
                     title: "Spanish — Animals", subjectTag: "spanish", version: 1,
                     cards: [
                        CardPack(id: UUID(uuidString: "CA8D0001-0000-0000-0000-000000000001")!,
                                 front: "el gato", back: "the cat", hint: "a feline"),
                        CardPack(id: UUID(uuidString: "CA8D0001-0000-0000-0000-000000000002")!,
                                 front: "el perro", back: "the dog", hint: nil),
                     ]),
            DeckPack(id: UUID(uuidString: "DECC0002-0000-0000-0000-000000000002")!,
                     title: "Multiplication ×3", subjectTag: "math", version: 1,
                     cards: [
                        CardPack(id: UUID(uuidString: "CA8D0002-0000-0000-0000-000000000001")!,
                                 front: "3 × 1", back: "3", hint: nil),
                     ]),
        ]
    }

    func testImportCreatesBundledDecksWithStableCardIDs() throws {
        let repo = makeRepository()
        let packs = samplePacks()

        let created = try repo.importBundled(packs)
        XCTAssertEqual(created, 2)

        let assignable = try repo.fetchAssignableDecks()
        XCTAssertEqual(assignable.map(\.title), ["Multiplication ×3", "Spanish — Animals"])
        XCTAssertTrue(assignable.allSatisfy(\.isBundled))

        // Cards keep their pack ids and order.
        let spanish = try XCTUnwrap(assignable.first(where: { $0.title == "Spanish — Animals" }))
        let cards = try repo.fetchCards(in: spanish.id)
        XCTAssertEqual(cards.map(\.front), ["el gato", "el perro"])
        XCTAssertEqual(cards.map(\.order), [0, 1])
        XCTAssertEqual(cards.first?.id, UUID(uuidString: "CA8D0001-0000-0000-0000-000000000001"))
        XCTAssertEqual(cards.first?.hint, "a feline")
    }

    func testImportIsIdempotent() throws {
        let repo = makeRepository()
        let packs = samplePacks()

        XCTAssertEqual(try repo.importBundled(packs), 2)
        XCTAssertEqual(try repo.importBundled(packs), 0, "Re-import creates nothing")
        XCTAssertEqual(try repo.fetchAssignableDecks().count, 2, "No duplicates")
    }

    func testImportAddsOnlyNewPacks() throws {
        let repo = makeRepository()
        var packs = samplePacks()
        XCTAssertEqual(try repo.importBundled(packs), 2)

        // A later app update adds a third starter deck.
        packs.append(DeckPack(id: UUID(uuidString: "DECC0003-0000-0000-0000-000000000003")!,
                              title: "Sight Words", subjectTag: "reading", version: 1,
                              cards: [CardPack(id: UUID(), front: "the", back: "the", hint: nil)]))
        XCTAssertEqual(try repo.importBundled(packs), 1, "Only the new deck is created")
        XCTAssertEqual(try repo.fetchAssignableDecks().count, 3)
    }

    func testBundledDecksAreNotShownInTheEditor() throws {
        let repo = makeRepository()
        _ = try repo.importBundled(samplePacks())
        _ = try repo.createDeck(title: "My Authored Deck")

        // The editor lists only parentAuthored decks.
        XCTAssertEqual(try repo.fetchDecks().map(\.title), ["My Authored Deck"])
        XCTAssertFalse(try repo.fetchDecks().contains(where: \.isBundled))
        // But all three are assignable.
        XCTAssertEqual(try repo.fetchAssignableDecks().count, 3)
    }

    /// Loads the real shipped `StarterDecks.json` from the app bundle to catch a
    /// missing resource or malformed JSON.
    func testShippedStarterDecksResourceImports() throws {
        let repo = DeckRepository(persistence: PersistenceController(inMemory: true))
        let created = try StarterDeckImporter(repository: repo, bundle: .main).importIfNeeded()
        XCTAssertGreaterThanOrEqual(created, 1, "StarterDecks.json should ship at least one deck")

        let decks = try repo.fetchAssignableDecks()
        XCTAssertFalse(decks.isEmpty)
        XCTAssertTrue(decks.allSatisfy(\.isBundled))
        XCTAssertTrue(decks.allSatisfy { $0.cardCount > 0 }, "Every starter deck has cards")
    }

    func testBundledDeckIsAssignableAndStudyable() throws {
        let controller = PersistenceController(inMemory: true)
        let context = controller.container.viewContext
        let decks = DeckRepository(context: context)
        let children = ChildRepository(context: context)
        let study = StudyRepository(context: context)

        _ = try decks.importBundled(samplePacks())
        let child = try children.createChild(name: "Mia")
        let spanish = try XCTUnwrap(
            try decks.fetchAssignableDecks().first(where: { $0.title == "Spanish — Animals" }))

        try decks.setDeck(spanish.id, assigned: true, toChild: child.id)

        // The bundled deck's cards now appear in the child's session.
        let plan = try study.loadSession(forChild: child.id, now: Date())
        XCTAssertEqual(Set(plan.cards.map(\.front)), ["el gato", "el perro"])
    }
}
