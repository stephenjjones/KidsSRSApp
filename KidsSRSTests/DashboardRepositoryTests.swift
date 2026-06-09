import XCTest
import CoreData
import KidsSRSCore
@testable import KidsSRS

/// Tests for `DashboardRepository` (Spec §8.4): card-state breakdown, accuracy,
/// study time, streak, and the struggling-cards list. Uses a fixed UTC calendar
/// so day-boundary logic is deterministic.
final class DashboardRepositoryTests: XCTestCase {

    private let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()
    /// Midday so ±minutes never crosses a day boundary.
    private let now = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c.date(from: DateComponents(year: 2023, month: 11, day: 15, hour: 12))!
    }()

    private func day(_ offset: Int) -> Date {
        calendar.date(byAdding: .day, value: offset, to: now)!
    }
    private func startOfDay(_ offset: Int) -> Date {
        calendar.startOfDay(for: day(offset))
    }

    private func makeRepositories()
        -> (dashboard: DashboardRepository, study: StudyRepository,
            decks: DeckRepository, children: ChildRepository) {
        let context = PersistenceController(inMemory: true).container.viewContext
        return (DashboardRepository(context: context, calendar: calendar),
                StudyRepository(context: context),
                DeckRepository(context: context),
                ChildRepository(context: context))
    }

    // MARK: Pure streak logic

    func testStreakCountsConsecutiveDaysEndingToday() {
        let days = Set([startOfDay(0), startOfDay(-1), startOfDay(-2)])
        XCTAssertEqual(
            DashboardRepository.streakDays(studyDays: days, calendar: calendar, now: now), 3)
    }

    func testStreakEndsYesterdayWhenNotStudiedToday() {
        let days = Set([startOfDay(-1), startOfDay(-2)])
        XCTAssertEqual(
            DashboardRepository.streakDays(studyDays: days, calendar: calendar, now: now), 2)
    }

    func testStreakIsZeroWithAGap() {
        let days = Set([startOfDay(-2), startOfDay(-3)])
        XCTAssertEqual(
            DashboardRepository.streakDays(studyDays: days, calendar: calendar, now: now), 0)
        XCTAssertEqual(
            DashboardRepository.streakDays(studyDays: [], calendar: calendar, now: now), 0)
    }

    // MARK: Integration

    func testProgressAggregatesStatesSessionsAndStruggling() throws {
        let r = makeRepositories()
        let child = try r.children.createChild(name: "Mia")
        let deck = try r.decks.createDeck(title: "Deck")
        let c0 = try r.decks.addCard(to: deck.id, front: "c0", back: "x", hint: nil)
        let c1 = try r.decks.addCard(to: deck.id, front: "c1", back: "x", hint: nil)
        let c2 = try r.decks.addCard(to: deck.id, front: "tricky", back: "x", hint: nil)
        _ = try r.decks.addCard(to: deck.id, front: "c3", back: "x", hint: nil) // never studied
        try r.decks.setDeck(deck.id, assigned: true, toChild: child.id)

        // c0 → review, c1 → learning, c2 → review but struggling (lapses + over-confident).
        try r.study.saveState(forChild: child.id, cardID: c0.id,
                              state: SchedulerState(status: .review, intervalDays: 6,
                                                    repetitions: 2, dueDate: day(6)))
        try r.study.saveState(forChild: child.id, cardID: c1.id,
                              state: SchedulerState(status: .learning, learningStepIndex: 1,
                                                    dueDate: day(0)))
        try r.study.saveState(forChild: child.id, cardID: c2.id,
                              state: SchedulerState(status: .review, intervalDays: 1,
                                                    repetitions: 1, lapses: 3, dueDate: day(1),
                                                    lastConfidenceFlag: .overConfident))

        // Two sessions: today (2/3) and yesterday (2/2).
        try r.study.recordSession(forChild: child.id, startedAt: day(0),
                                  endedAt: day(0).addingTimeInterval(300),
                                  cardsSeen: 3, cardsCorrect: 2, newIntroduced: 3)
        try r.study.recordSession(forChild: child.id, startedAt: day(-1),
                                  endedAt: day(-1).addingTimeInterval(300),
                                  cardsSeen: 2, cardsCorrect: 2, newIntroduced: 0)

        let p = try r.dashboard.progress(forChild: child.id, now: now)

        XCTAssertFalse(p.isEmpty)
        // State breakdown: 4 assigned, 3 studied → 1 new; 1 learning; 2 review.
        XCTAssertEqual(p.newCount, 1)
        XCTAssertEqual(p.learningCount, 1)
        XCTAssertEqual(p.reviewCount, 2)
        // Accuracy 4/5, both sessions, two-day streak, 10 minutes studied.
        XCTAssertEqual(try XCTUnwrap(p.totalAccuracy), 0.8, accuracy: 0.0001)
        XCTAssertEqual(p.sessionCount, 2)
        XCTAssertEqual(p.streakDays, 2)
        XCTAssertEqual(p.totalStudyTime, 600, accuracy: 0.5)
        XCTAssertEqual(p.recentAccuracy.count, 2)
        XCTAssertEqual(p.recentAccuracy.map(\.day), [startOfDay(-1), startOfDay(0)]) // oldest→newest
        // Only the tricky card is flagged.
        XCTAssertEqual(p.strugglingCards.map(\.front), ["tricky"])
        XCTAssertEqual(p.strugglingCards.first?.lapses, 3)
        XCTAssertTrue(p.strugglingCards.first?.overConfident ?? false)
    }

    func testEmptyProgressForUnstudiedChild() throws {
        let r = makeRepositories()
        let child = try r.children.createChild(name: "Mia")

        let p = try r.dashboard.progress(forChild: child.id, now: now)
        XCTAssertTrue(p.isEmpty)
        XCTAssertNil(p.totalAccuracy)
        XCTAssertEqual(p.streakDays, 0)
        XCTAssertTrue(p.strugglingCards.isEmpty)
    }
}
