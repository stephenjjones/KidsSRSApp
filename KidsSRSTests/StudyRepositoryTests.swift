import XCTest
import CoreData
import KidsSRSCore
@testable import KidsSRS

/// Unit tests for `StudyRepository`: session composition (assigned-only,
/// reviews-first, caps) and `CardState` persistence/round-trip. In-memory store.
final class StudyRepositoryTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    /// All three repositories plus the context they share.
    private func makeRepositories()
        -> (study: StudyRepository, decks: DeckRepository,
            children: ChildRepository, context: NSManagedObjectContext) {
        let context = PersistenceController(inMemory: true).container.viewContext
        return (StudyRepository(context: context),
                DeckRepository(context: context),
                ChildRepository(context: context),
                context)
    }

    // MARK: Composition

    func testEmptySessionWhenNothingAssigned() throws {
        let r = makeRepositories()
        let child = try r.children.createChild(name: "Mia")
        let deck = try r.decks.createDeck(title: "Math")
        _ = try r.decks.addCard(to: deck.id, front: "1+1", back: "2", hint: nil)
        // Deck exists but is NOT assigned to the child.

        let plan = try r.study.loadSession(forChild: child.id, now: now)
        XCTAssertTrue(plan.cards.isEmpty)
        XCTAssertEqual(plan.pacingProfile, .normal)
    }

    func testSessionIncludesOnlyAssignedDecks() throws {
        let r = makeRepositories()
        let child = try r.children.createChild(name: "Mia")

        let assigned = try r.decks.createDeck(title: "Assigned")
        let a1 = try r.decks.addCard(to: assigned.id, front: "a1", back: "x", hint: nil)
        let a2 = try r.decks.addCard(to: assigned.id, front: "a2", back: "x", hint: nil)

        let other = try r.decks.createDeck(title: "Other")
        _ = try r.decks.addCard(to: other.id, front: "o1", back: "x", hint: nil)

        try r.decks.setDeck(assigned.id, assigned: true, toChild: child.id)

        let plan = try r.study.loadSession(forChild: child.id, now: now)
        // Deterministic order: deck title then card order.
        XCTAssertEqual(plan.cards.map(\.id), [a1.id, a2.id])
        XCTAssertTrue(plan.cards.allSatisfy { $0.state.status == .new })
    }

    func testNewCardCapIsRespected() throws {
        let r = makeRepositories()
        let child = try r.children.createChild(name: "Mia") // default 5 new/day (§7.3)
        let deck = try r.decks.createDeck(title: "Deck")
        for i in 0..<10 { _ = try r.decks.addCard(to: deck.id, front: "c\(i)", back: "x", hint: nil) }
        try r.decks.setDeck(deck.id, assigned: true, toChild: child.id)

        let plan = try r.study.loadSession(forChild: child.id, now: now)
        XCTAssertEqual(plan.cards.count, 5, "New cards capped at the child's dailyNewCardLimit")
    }

    func testReviewsComeBeforeNewCards() throws {
        let r = makeRepositories()
        let child = try r.children.createChild(name: "Mia")
        let deck = try r.decks.createDeck(title: "Deck")
        let due = try r.decks.addCard(to: deck.id, front: "due", back: "x", hint: nil)
        let fresh = try r.decks.addCard(to: deck.id, front: "fresh", back: "x", hint: nil)
        try r.decks.setDeck(deck.id, assigned: true, toChild: child.id)

        // Make `due` a review card already due.
        let reviewState = SchedulerState(status: .review, easeFactor: 2.3, intervalDays: 1,
                                         repetitions: 1, dueDate: now.addingTimeInterval(-60))
        try r.study.saveState(forChild: child.id, cardID: due.id, state: reviewState)

        let plan = try r.study.loadSession(forChild: child.id, now: now)
        XCTAssertEqual(plan.cards.map(\.id), [due.id, fresh.id], "Due review precedes the new card")
        XCTAssertEqual(plan.cards.first?.state.status, .review)
    }

    // MARK: CardState persistence

    func testGradeLazilyCreatesAndPersistsCardState() throws {
        let r = makeRepositories()
        let child = try r.children.createChild(name: "Mia")
        let deck = try r.decks.createDeck(title: "Deck")
        let card = try r.decks.addCard(to: deck.id, front: "2x6", back: "12", hint: nil)
        try r.decks.setDeck(deck.id, assigned: true, toChild: child.id)

        XCTAssertEqual(try cardStateCount(in: r.context), 0, "No CardState before any review")

        // Simulate the view model: apply the scheduler, persist the result.
        let newState = Scheduler(profile: .normal).apply(
            ReviewInput(grade: .gotIt, prediction: .knowIt, reviewedAt: now), to: .makeNew())
        try r.study.saveState(forChild: child.id, cardID: card.id, state: newState)

        XCTAssertEqual(try cardStateCount(in: r.context), 1, "Exactly one CardState materialized")
        // A "Got it" on a new card enters learning (Spec §7.2) with a future due
        // date, so it's no longer offered this instant.
        XCTAssertTrue(try r.study.loadSession(forChild: child.id, now: now).cards.isEmpty)
    }

    func testGradedProgressSurvivesReloadAndAdvancesOthers() throws {
        let r = makeRepositories()
        let child = try r.children.createChild(name: "Mia")
        let deck = try r.decks.createDeck(title: "Deck")
        let c0 = try r.decks.addCard(to: deck.id, front: "c0", back: "x", hint: nil)
        let c1 = try r.decks.addCard(to: deck.id, front: "c1", back: "x", hint: nil)
        let c2 = try r.decks.addCard(to: deck.id, front: "c2", back: "x", hint: nil)
        try r.decks.setDeck(deck.id, assigned: true, toChild: child.id)

        XCTAssertEqual(try r.study.loadSession(forChild: child.id, now: now).cards.map(\.id),
                       [c0.id, c1.id, c2.id])

        let state = Scheduler(profile: .normal).apply(
            ReviewInput(grade: .gotIt, prediction: .knowIt, reviewedAt: now), to: .makeNew())
        try r.study.saveState(forChild: child.id, cardID: c0.id, state: state)

        // Reload via a FRESH repository on the same context: progress persisted,
        // c0 dropped (future learning step), the rest still queued.
        let reloaded = StudyRepository(context: r.context)
        XCTAssertEqual(try reloaded.loadSession(forChild: child.id, now: now).cards.map(\.id),
                       [c1.id, c2.id])
    }

    func testSaveStateRoundTripsAllFields() throws {
        let r = makeRepositories()
        let child = try r.children.createChild(name: "Mia")
        let deck = try r.decks.createDeck(title: "Deck")
        let card = try r.decks.addCard(to: deck.id, front: "q", back: "a", hint: nil)
        try r.decks.setDeck(deck.id, assigned: true, toChild: child.id)

        let state = SchedulerState(status: .review, easeFactor: 2.18, intervalDays: 6,
                                   repetitions: 2, lapses: 1, learningStepIndex: nil,
                                   dueDate: now.addingTimeInterval(6 * 86_400),
                                   lastReviewedAt: now,
                                   lastConfidenceFlag: .underConfident)
        try r.study.saveState(forChild: child.id, cardID: card.id, state: state)

        // Look far enough ahead that the card is due again, then compare fields.
        let plan = try r.study.loadSession(forChild: child.id, now: now.addingTimeInterval(7 * 86_400))
        let stored = try XCTUnwrap(plan.cards.first(where: { $0.id == card.id })?.state)
        XCTAssertEqual(stored.status, .review)
        XCTAssertEqual(stored.easeFactor, 2.18, accuracy: 0.0001)
        XCTAssertEqual(stored.intervalDays, 6, accuracy: 0.0001)
        XCTAssertEqual(stored.repetitions, 2)
        XCTAssertEqual(stored.lapses, 1)
        XCTAssertEqual(stored.dueDate, now.addingTimeInterval(6 * 86_400))
        XCTAssertEqual(stored.lastConfidenceFlag, .underConfident)
    }

    func testSaveStateThrowsForMissingCard() throws {
        let r = makeRepositories()
        let child = try r.children.createChild(name: "Mia")
        XCTAssertThrowsError(
            try r.study.saveState(forChild: child.id, cardID: UUID(), state: .makeNew()))
    }

    // MARK: Accessibility preferences (Spec §11)

    func testLoadSessionSurfacesChildAccessibilityPreferences() throws {
        let r = makeRepositories()
        var child = try r.children.createChild(name: "Mia")
        XCTAssertEqual(try r.study.loadSession(forChild: child.id, now: now).preferences,
                       .default)

        child.dyslexiaMode = true
        child.readAloud = true
        child.reduceMotion = true
        try r.children.updateChild(child)

        let prefs = try r.study.loadSession(forChild: child.id, now: now).preferences
        XCTAssertTrue(prefs.dyslexiaMode)
        XCTAssertTrue(prefs.readAloud)
        XCTAssertTrue(prefs.reduceMotion)
    }

    // MARK: Game Mode draw (Spec §14.5)

    func testGameDrawFiltersByAssignedDeckAndCategory() throws {
        let r = makeRepositories()
        let child = try r.children.createChild(name: "Mia")

        let math = try r.decks.createDeck(title: "Math")
        let tagged = try r.decks.addCard(to: math.id, front: "2x3", back: "6", hint: nil)
        let untagged = try r.decks.addCard(to: math.id, front: "9-4", back: "5", hint: nil)

        let other = try r.decks.createDeck(title: "Other")
        let elsewhere = try r.decks.addCard(to: other.id, front: "x", back: "y", hint: nil)

        try r.decks.setDeck(math.id, assigned: true, toChild: child.id)
        // `other` is deliberately NOT assigned to the child.

        let tag = try r.decks.findOrCreateTag(name: "Multiplication")
        try r.decks.setTags([tag.id], forCard: tagged.id)
        try r.decks.setTags([tag.id], forCard: elsewhere.id) // tagged but unassigned deck

        let draw = try r.study.loadGameDraw(forChild: child.id, tagIDs: [tag.id], now: now)
        XCTAssertEqual(draw.map(\.id), [tagged.id],
                       "only tagged cards inside the child's assigned decks are drawn")
        _ = untagged // present in an assigned deck but untagged → excluded by the category
    }

    func testGameDrawWithoutCategoriesReturnsAllAssignedCards() throws {
        let r = makeRepositories()
        let child = try r.children.createChild(name: "Mia")
        let deck = try r.decks.createDeck(title: "Deck")
        let a = try r.decks.addCard(to: deck.id, front: "a", back: "x", hint: nil)
        let b = try r.decks.addCard(to: deck.id, front: "b", back: "x", hint: nil)
        try r.decks.setDeck(deck.id, assigned: true, toChild: child.id)

        let draw = try r.study.loadGameDraw(forChild: child.id, tagIDs: [], now: now)
        XCTAssertEqual(Set(draw.map(\.id)), [a.id, b.id], "no category filter ⇒ all assigned cards")
    }

    func testGameDrawRanksDueThenNewThenKnown() throws {
        let r = makeRepositories()
        let child = try r.children.createChild(name: "Mia")
        let deck = try r.decks.createDeck(title: "Deck")
        let dueCard = try r.decks.addCard(to: deck.id, front: "due", back: "x", hint: nil)
        let newCard = try r.decks.addCard(to: deck.id, front: "new", back: "x", hint: nil)
        let knownCard = try r.decks.addCard(to: deck.id, front: "known", back: "x", hint: nil)
        try r.decks.setDeck(deck.id, assigned: true, toChild: child.id)

        // dueCard: a review already due → needs practice now (top tier).
        try r.study.saveState(forChild: child.id, cardID: dueCard.id,
                              state: SchedulerState(status: .review, easeFactor: 2.3, intervalDays: 1,
                                                    repetitions: 1, dueDate: now.addingTimeInterval(-60)))
        // knownCard: a review due far in the future → known well (lowest tier).
        try r.study.saveState(forChild: child.id, cardID: knownCard.id,
                              state: SchedulerState(status: .review, easeFactor: 2.3, intervalDays: 30,
                                                    repetitions: 4,
                                                    dueDate: now.addingTimeInterval(30 * 86_400)))
        // newCard: left untouched → status `new` (middle tier).

        let draw = try r.study.loadGameDraw(forChild: child.id, tagIDs: [], now: now)
        XCTAssertEqual(draw.map(\.id), [dueCard.id, newCard.id, knownCard.id])
    }

    func testGameDrawThrowsForMissingChild() throws {
        let r = makeRepositories()
        XCTAssertThrowsError(try r.study.loadGameDraw(forChild: UUID(), tagIDs: [], now: now))
    }

    func testGameDrawExcludesVideoSongCards() throws {
        let r = makeRepositories()
        let child = try r.children.createChild(name: "Mia")
        let deck = try r.decks.createDeck(title: "Mixed")
        let text = try r.decks.addCard(to: deck.id, front: "q", back: "a", hint: nil)
        _ = try r.decks.addVideoCard(to: deck.id, title: "song",
                                     youTube: "youtu.be/abcdefghijk", hint: nil)
        try r.decks.setDeck(deck.id, assigned: true, toChild: child.id)

        let draw = try r.study.loadGameDraw(forChild: child.id, tagIDs: [], now: now)
        XCTAssertEqual(draw.map(\.id), [text.id], "video songs are for Song Review, not Game Mode")
    }

    func testScoreGameDrawAdvancesOnCorrectAndLapsesOnIncorrect() throws {
        let r = makeRepositories()
        let child = try r.children.createChild(name: "Mia")
        let deck = try r.decks.createDeck(title: "Deck")
        let card = try r.decks.addCard(to: deck.id, front: "2x3", back: "6", hint: nil)
        try r.decks.setDeck(deck.id, assigned: true, toChild: child.id)

        // Correct on a new card behaves like "Got it" → enters learning step 1.
        try r.study.scoreGameDraw(forChild: child.id, cardID: card.id, correct: true, now: now)
        let s1 = try XCTUnwrap(storedState(childID: child.id, cardID: card.id, in: r.context))
        XCTAssertEqual(s1.status, .learning)
        XCTAssertEqual(s1.learningStepIndex, 1)

        // Incorrect then resets to learning step 0 (lapse-like), and never a flag.
        try r.study.scoreGameDraw(forChild: child.id, cardID: card.id, correct: false, now: now)
        let s2 = try XCTUnwrap(storedState(childID: child.id, cardID: card.id, in: r.context))
        XCTAssertEqual(s2.learningStepIndex, 0)
        XCTAssertNil(s2.lastConfidenceFlag)
    }

    // MARK: Song scoring (Spec §14.3 / §14.4)

    func testStudySessionExcludesVideoSongCards() throws {
        let r = makeRepositories()
        let child = try r.children.createChild(name: "Mia")
        let deck = try r.decks.createDeck(title: "Mixed")
        let text = try r.decks.addCard(to: deck.id, front: "2+2", back: "4", hint: nil)
        _ = try r.decks.addVideoCard(to: deck.id, title: "Counting song",
                                     youTube: "https://youtu.be/abcdefghijk", hint: nil)
        try r.decks.setDeck(deck.id, assigned: true, toChild: child.id)

        let plan = try r.study.loadSession(forChild: child.id, now: now)
        XCTAssertEqual(plan.cards.map(\.id), [text.id],
                       "songs review in Song Review, not the flashcard flow")
    }

    func testScoreSongPersistsParentGrade() throws {
        let r = makeRepositories()
        let child = try r.children.createChild(name: "Mia")
        let deck = try r.decks.createDeck(title: "Songs")
        let song = try r.decks.addVideoCard(to: deck.id, title: "Sevens",
                                            youTube: "https://youtu.be/abcdefghijk", hint: nil)
        try r.decks.setDeck(deck.id, assigned: true, toChild: child.id)

        try r.study.scoreSong(forChild: child.id, cardID: song.id, grade: .knowsIt, now: now)

        // "Knows it" on a never-scored song behaves like "Got it" → learning (§14.4).
        let state = try XCTUnwrap(storedState(childID: child.id, cardID: song.id, in: r.context))
        XCTAssertEqual(state.status, .learning)
        XCTAssertEqual(state.learningStepIndex, 1)
        XCTAssertEqual(state.lastReviewedAt, now)
    }

    func testScoreSongThrowsForMissingChild() throws {
        let r = makeRepositories()
        let deck = try r.decks.createDeck(title: "Songs")
        let song = try r.decks.addVideoCard(to: deck.id, title: "x",
                                            youTube: "youtu.be/abcdefghijk", hint: nil)
        XCTAssertThrowsError(
            try r.study.scoreSong(forChild: UUID(), cardID: song.id, grade: .knowsIt, now: now))
    }

    // MARK: Smart Song Review (Spec §14.3)

    func testGenerateSongReviewSurfacesDueAndNewExcludesKnown() throws {
        let r = makeRepositories()
        let child = try r.children.createChild(name: "Mia")
        let deckA = try r.decks.createDeck(title: "A")
        let due = try r.decks.addVideoCard(to: deckA.id, title: "Due Song",
                                           youTube: "youtu.be/aaaaaaaaaaa", hint: nil)
        let fresh = try r.decks.addVideoCard(to: deckA.id, title: "New Song",
                                             youTube: "youtu.be/bbbbbbbbbbb", hint: nil)
        let deckB = try r.decks.createDeck(title: "B")
        let known = try r.decks.addVideoCard(to: deckB.id, title: "Known Song",
                                             youTube: "youtu.be/ccccccccccc", hint: nil)

        // `due`: a review already due. `known`: scheduled far out. `fresh`: never scored.
        try r.study.saveState(forChild: child.id, cardID: due.id,
                              state: SchedulerState(status: .review, easeFactor: 2.3, intervalDays: 1,
                                                    repetitions: 1, dueDate: now.addingTimeInterval(-60)))
        try r.study.saveState(forChild: child.id, cardID: known.id,
                              state: SchedulerState(status: .review, easeFactor: 2.3, intervalDays: 30,
                                                    repetitions: 4,
                                                    dueDate: now.addingTimeInterval(30 * 86_400)))

        let review = try r.study.generateSongReview(forChildren: [child.id], now: now)
        XCTAssertEqual(review.map(\.id), [due.id, fresh.id],
                       "due first, then new; the known song is excluded")
    }

    func testGenerateSongReviewEmptyForEmptySelection() throws {
        let r = makeRepositories()
        XCTAssertTrue(try r.study.generateSongReview(forChildren: [], now: now).isEmpty)
    }

    // MARK: Helpers

    private func cardStateCount(in context: NSManagedObjectContext) throws -> Int {
        try context.count(for: NSFetchRequest<CardStateMO>(entityName: "CardState"))
    }

    private func storedState(childID: UUID, cardID: UUID,
                             in context: NSManagedObjectContext) throws -> SchedulerState? {
        let request = NSFetchRequest<CardStateMO>(entityName: "CardState")
        request.predicate = NSPredicate(format: "child.id == %@ AND card.id == %@",
                                        childID as NSUUID, cardID as NSUUID)
        request.fetchLimit = 1
        return try context.fetch(request).first.map(StudyRepository.schedulerState(from:))
    }
}
