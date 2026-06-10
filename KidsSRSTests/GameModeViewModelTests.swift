import XCTest
import KidsSRSCore
@testable import KidsSRS

/// Tests for `GameModeViewModel` (Spec §14.5): setup → draw pool → reveal →
/// score/skip → cycle. The draw ranking + scoring live in `GameDrawPlanner` /
/// `StudyRepository` (tested separately); here we cover the view model's
/// two-phase orchestration over an in-memory store.
@MainActor
final class GameModeViewModelTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    /// In-memory store with one child + an assigned, tagged deck of `n` cards.
    private func makeSeeded(n: Int = 3) throws -> GameModeViewModel {
        let persistence = PersistenceController(inMemory: true)
        let decks = DeckRepository(persistence: persistence)
        let children = ChildRepository(persistence: persistence)
        let study = StudyRepository(persistence: persistence)

        let child = try children.createChild(name: "Mia")
        let deck = try decks.createDeck(title: "Math")
        for i in 0..<n {
            let card = try decks.addCard(to: deck.id, front: "q\(i)", back: "a\(i)", hint: nil)
            try decks.setTagNames(["Math"], forCard: card.id)
        }
        try decks.setDeck(deck.id, assigned: true, toChild: child.id)

        return GameModeViewModel(decks: decks, childRepository: children, study: study,
                                 now: { [now] in now })
    }

    func testLoadPopulatesAndDefaultsToFirstChild() throws {
        let vm = try makeSeeded()
        vm.load()
        XCTAssertEqual(vm.children.count, 1)
        XCTAssertEqual(vm.allTags.map(\.name), ["Math"])
        XCTAssertEqual(vm.selectedChildID, vm.children.first?.id)
        XCTAssertTrue(vm.canStart)
    }

    func testCannotStartWithoutAChild() {
        let persistence = PersistenceController(inMemory: true)
        let vm = GameModeViewModel(decks: DeckRepository(persistence: persistence),
                                   childRepository: ChildRepository(persistence: persistence),
                                   study: StudyRepository(persistence: persistence),
                                   now: { [now] in now })
        vm.load()
        XCTAssertTrue(vm.children.isEmpty)
        XCTAssertFalse(vm.canStart)
    }

    func testToggleTag() throws {
        let vm = try makeSeeded()
        vm.load()
        let tagID = try XCTUnwrap(vm.allTags.first?.id)
        vm.toggleTag(tagID)
        XCTAssertTrue(vm.selectedTagIDs.contains(tagID))
        vm.toggleTag(tagID)
        XCTAssertFalse(vm.selectedTagIDs.contains(tagID))
    }

    func testStartBuildsPoolAndEntersPlaying() throws {
        let vm = try makeSeeded()
        vm.load()
        vm.start()
        XCTAssertTrue(vm.isPlaying)
        XCTAssertFalse(vm.pool.isEmpty)
        XCTAssertEqual(vm.index, 0)
        XCTAssertFalse(vm.isRevealed)
        XCTAssertNotNil(vm.current)
        XCTAssertNil(vm.errorMessage)
    }

    func testRevealThenSkipAdvances() throws {
        let vm = try makeSeeded()
        vm.load(); vm.start()
        vm.reveal()
        XCTAssertTrue(vm.isRevealed)
        vm.skip()
        XCTAssertFalse(vm.isRevealed)
        XCTAssertEqual(vm.index, 1)
    }

    func testScoreAdvancesWithoutError() throws {
        let vm = try makeSeeded()
        vm.load(); vm.start()
        vm.reveal()
        vm.score(correct: true)
        XCTAssertEqual(vm.index, 1)
        XCTAssertFalse(vm.isRevealed)
        XCTAssertNil(vm.errorMessage)
    }

    func testAdvancingPastLastCardCyclesToStart() throws {
        let vm = try makeSeeded()
        vm.load(); vm.start()
        let count = vm.pool.count
        for _ in 0..<count { vm.skip() }   // skip past the last card
        XCTAssertEqual(vm.index, 0, "advancing off the end re-ranks and restarts")
        XCTAssertTrue(vm.isPlaying)
    }

    func testEndGameReturnsToSetup() throws {
        let vm = try makeSeeded()
        vm.load(); vm.start()
        vm.endGame()
        XCTAssertFalse(vm.isPlaying)
        XCTAssertTrue(vm.pool.isEmpty)
    }
}
