import CoreData

// MARK: - UI-facing value types (Spec §8.4)

/// Per-child progress insight for the parent dashboard (Spec §8.4). All
/// read-only; computed from `CardState` + `SessionLog` + the child's assigned
/// cards. Spec §4.1: the view never sees `NSManagedObject`.
struct ChildProgress: Equatable {
    /// Cards in each scheduler state (Spec §7). `new` = assigned but not yet
    /// studied; `learning`/`review` come from persisted `CardState`.
    var newCount: Int
    var learningCount: Int
    var reviewCount: Int

    /// Overall accuracy across all logged sessions; `nil` if nothing studied yet.
    var totalAccuracy: Double?
    var totalStudyTime: TimeInterval
    var sessionCount: Int
    /// Consecutive study days ending today/yesterday (informational, §8.4).
    var streakDays: Int
    var lastStudied: Date?

    /// Up to the last 7 study days, oldest → newest (for the accuracy trend).
    var recentAccuracy: [DayAccuracy]
    /// Cards the child finds hard: high lapses or repeated over-confidence (§6.4).
    var strugglingCards: [StrugglingCard]

    /// Nothing to show yet — no sessions and no scheduler progress.
    var isEmpty: Bool {
        sessionCount == 0 && learningCount == 0 && reviewCount == 0
    }
}

/// One day's accuracy for the trend.
struct DayAccuracy: Equatable, Identifiable {
    var day: Date
    var seen: Int
    var correct: Int
    var id: Date { day }
    var accuracy: Double { seen == 0 ? 0 : Double(correct) / Double(seen) }
}

/// A card flagged for the parent to re-teach (Spec §8.4).
struct StrugglingCard: Equatable, Identifiable {
    let id: UUID
    var front: String
    var lapses: Int
    var overConfident: Bool
}

// MARK: - Repository

/// Read-only analytics for the parent dashboard (Spec §8.4).
final class DashboardRepository {
    /// A card counts as "struggling" at or above this lapse count.
    static let strugglingLapseThreshold = 2

    private let context: NSManagedObjectContext
    private let calendar: Calendar

    init(context: NSManagedObjectContext, calendar: Calendar = .current) {
        self.context = context
        self.calendar = calendar
    }

    convenience init(persistence: PersistenceController = .shared, calendar: Calendar = .current) {
        self.init(context: persistence.container.viewContext, calendar: calendar)
    }

    static var preview: DashboardRepository {
        DashboardRepository(persistence: .preview)
    }

    func progress(forChild childID: UUID, now: Date) throws -> ChildProgress {
        let child = try childMO(id: childID)
        let states = try cardStates(forChild: childID)
        let logs = try sessionLogs(forChild: childID)

        // Card-state breakdown.
        let learning = states.filter { $0.status == "learning" }.count
        let review = states.filter { $0.status == "review" }.count
        let studiedCardIDs = Set(states.compactMap { $0.card?.id })
        let assignedCards = ((child.assignedDecks as? Set<DeckMO>) ?? [])
            .flatMap { ($0.cards as? Set<CardMO>) ?? [] }
            .filter { !$0.isDeleted }
        let newCount = max(0, assignedCards.count - studiedCardIDs.count)

        // Struggling cards (Spec §6.4 / §8.4).
        let struggling = states.compactMap { Self.strugglingCard(from: $0) }
            .sorted { ($0.lapses, $1.front) > ($1.lapses, $0.front) }

        // Session-derived stats.
        let totalSeen = logs.reduce(0) { $0 + Int($1.cardsSeen) }
        let totalCorrect = logs.reduce(0) { $0 + Int($1.cardsCorrect) }
        let totalTime = logs.reduce(0.0) { acc, log in
            guard let start = log.startedAt, let end = log.endedAt, end > start else { return acc }
            return acc + end.timeIntervalSince(start)
        }
        let byDay = Self.accuracyByDay(logs: logs, calendar: calendar)

        return ChildProgress(
            newCount: newCount,
            learningCount: learning,
            reviewCount: review,
            totalAccuracy: totalSeen == 0 ? nil : Double(totalCorrect) / Double(totalSeen),
            totalStudyTime: totalTime,
            sessionCount: logs.count,
            streakDays: Self.streakDays(studyDays: Set(byDay.keys), calendar: calendar, now: now),
            lastStudied: logs.compactMap { $0.startedAt }.max(),
            recentAccuracy: Self.recentAccuracy(byDay: byDay, days: 7),
            strugglingCards: struggling
        )
    }

    // MARK: - Pure helpers (date logic, unit-tested directly)

    /// Aggregate sessions into per-(start-of-)day accuracy buckets.
    static func accuracyByDay(logs: [SessionLogMO],
                             calendar: Calendar) -> [Date: (seen: Int, correct: Int)] {
        var byDay: [Date: (seen: Int, correct: Int)] = [:]
        for log in logs {
            guard let started = log.startedAt else { continue }
            let day = calendar.startOfDay(for: started)
            var bucket = byDay[day] ?? (0, 0)
            bucket.seen += Int(log.cardsSeen)
            bucket.correct += Int(log.cardsCorrect)
            byDay[day] = bucket
        }
        return byDay
    }

    static func recentAccuracy(byDay: [Date: (seen: Int, correct: Int)], days: Int) -> [DayAccuracy] {
        byDay.keys.sorted().suffix(days).map { day in
            let bucket = byDay[day] ?? (0, 0)
            return DayAccuracy(day: day, seen: bucket.seen, correct: bucket.correct)
        }
    }

    /// Consecutive study days ending today (or yesterday, if not yet studied
    /// today). Informational only — never weaponized (Spec §8.4).
    static func streakDays(studyDays: Set<Date>, calendar: Calendar, now: Date) -> Int {
        let today = calendar.startOfDay(for: now)
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: today) else { return 0 }

        var cursor: Date
        if studyDays.contains(today) { cursor = today }
        else if studyDays.contains(yesterday) { cursor = yesterday }
        else { return 0 }

        var count = 0
        while studyDays.contains(cursor) {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return count
    }

    private static func strugglingCard(from state: CardStateMO) -> StrugglingCard? {
        let lapses = Int(state.lapses)
        let overConfident = state.lastConfidenceFlag == "overConfident"
        guard lapses >= strugglingLapseThreshold || overConfident,
              let card = state.card, let id = card.id else { return nil }
        return StrugglingCard(id: id, front: card.frontText ?? "",
                              lapses: lapses, overConfident: overConfident)
    }

    // MARK: - Fetching

    private func childMO(id: UUID) throws -> ChildMO {
        guard let child = try context.fetchFirst(ChildMO.self, entityName: "Child", id: id) else {
            throw StudyRepositoryError.childNotFound(id)
        }
        return child
    }

    private func cardStates(forChild childID: UUID) throws -> [CardStateMO] {
        let request = NSFetchRequest<CardStateMO>(entityName: "CardState")
        request.predicate = NSPredicate(format: "child.id == %@", childID as NSUUID)
        return try context.fetch(request)
    }

    private func sessionLogs(forChild childID: UUID) throws -> [SessionLogMO] {
        let request = NSFetchRequest<SessionLogMO>(entityName: "SessionLog")
        request.predicate = NSPredicate(format: "child.id == %@", childID as NSUUID)
        return try context.fetch(request)
    }
}
