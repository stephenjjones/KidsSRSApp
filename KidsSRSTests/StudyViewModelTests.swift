import XCTest
import KidsSRSCore
@testable import KidsSRS

/// Tests for `StudyViewModel` (Spec §6.2–§6.5): the predict-then-verify flow,
/// write-through to the store, session end, and reward roll-up. Repository
/// behaviour itself is covered by `StudyRepositoryTests`; here we exercise the
/// view model's orchestration over an in-memory store.
@MainActor
final class StudyViewModelTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private struct Fixture {
        let vm: StudyViewModel
        let childID: UUID
    }

    /// Seed an in-memory store with a child + an assigned deck of `cards`.
    private func makeFixture(cards: [(String, String)] = [("2×6", "12"), ("Cap", "Paris"), ("x", "y")],
                             assign: Bool = true) throws -> Fixture {
        let persistence = PersistenceController(inMemory: true)
        let decks = DeckRepository(persistence: persistence)
        let children = ChildRepository(persistence: persistence)
        let study = StudyRepository(persistence: persistence)
        let rewards = RewardRepository(persistence: persistence)

        let child = try children.createChild(name: "Mia")
        let deck = try decks.createDeck(title: "Sample")
        for (front, back) in cards { _ = try decks.addCard(to: deck.id, front: front, back: back, hint: nil) }
        if assign { try decks.setDeck(deck.id, assigned: true, toChild: child.id) }

        let vm = StudyViewModel(childID: child.id, repository: study, rewards: rewards,
                                clock: { [now] in now })
        return Fixture(vm: vm, childID: child.id)
    }

    func testLoadComposesQueueAndStartsAtPredict() throws {
        let f = try makeFixture()
        f.vm.load()
        XCTAssertEqual(f.vm.phase, .predict)
        XCTAssertEqual(f.vm.queue.count, 3)
        XCTAssertEqual(f.vm.index, 0)
        XCTAssertNotNil(f.vm.current)
        XCTAssertNil(f.vm.errorMessage)
    }

    func testNoAssignedDecksFinishesEmpty() throws {
        let f = try makeFixture(assign: false)
        f.vm.load()
        XCTAssertEqual(f.vm.phase, .finished)
        XCTAssertTrue(f.vm.queue.isEmpty)
    }

    func testPredictThenRevealThenGradeAdvancesAndCounts() throws {
        let f = try makeFixture()
        f.vm.load()

        // A prediction is required before the reveal; grading before that is a no-op.
        f.vm.grade(.gotIt)
        XCTAssertEqual(f.vm.phase, .predict, "grade ignored until a prediction is made")

        f.vm.choosePrediction(.knowIt)
        XCTAssertEqual(f.vm.phase, .reveal)

        f.vm.grade(.gotIt)
        XCTAssertEqual(f.vm.correctCount, 1)
        XCTAssertEqual(f.vm.index, 1)
        XCTAssertEqual(f.vm.phase, .predict)
    }

    func testCompletingSessionFinishesAndRecordsCompletedSession() throws {
        let f = try makeFixture()
        f.vm.load()
        let total = f.vm.queue.count

        for _ in 0..<total {
            f.vm.choosePrediction(.knowIt)
            f.vm.grade(.gotIt)
        }

        XCTAssertEqual(f.vm.phase, .finished)
        XCTAssertEqual(f.vm.correctCount, total)
        // recordSession → rewards.recordCompletedSession advanced the ladder.
        XCTAssertEqual(f.vm.rewardSummary?.sessionsCompleted, 1)
    }

    func testGradedStateIsPersisted() throws {
        let persistence = PersistenceController(inMemory: true)
        let decks = DeckRepository(persistence: persistence)
        let children = ChildRepository(persistence: persistence)
        let study = StudyRepository(persistence: persistence)
        let rewards = RewardRepository(persistence: persistence)

        let child = try children.createChild(name: "Leo")
        let deck = try decks.createDeck(title: "Sample")
        _ = try decks.addCard(to: deck.id, front: "only", back: "card", hint: nil)
        try decks.setDeck(deck.id, assigned: true, toChild: child.id)

        let vm = StudyViewModel(childID: child.id, repository: study, rewards: rewards,
                                clock: { [now] in now })
        vm.load()
        vm.choosePrediction(.knowIt)
        vm.grade(.gotIt)
        XCTAssertNil(vm.errorMessage)

        // A fresh view model over the same store sees the advanced state: the
        // single new card is no longer queued as a brand-new card today.
        let reloaded = StudyViewModel(childID: child.id, repository: study, rewards: rewards,
                                      clock: { [now] in now })
        reloaded.load()
        XCTAssertFalse(reloaded.queue.contains { $0.state.status == .new },
                       "the graded card's state should have advanced past .new")
    }

    func testCoachingMapsConfidenceFlag() {
        XCTAssertNil(StudyViewModel.coaching(for: .calibrated))
        XCTAssertNil(StudyViewModel.coaching(for: nil))
        XCTAssertNotNil(StudyViewModel.coaching(for: .overConfident))
        XCTAssertNotNil(StudyViewModel.coaching(for: .underConfident))
    }
}
