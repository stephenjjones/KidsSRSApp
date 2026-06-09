import Foundation

/// Builds a single day's bounded study session. Spec §6.2 / §7.4.
///
/// Rules:
///  - **Reviews come first**, capped at `dailyReviewLimit`.
///  - **New cards** fill the remaining headroom, capped at `newCardsPerDay`.
///  - Anything over the caps is simply left out (the app reschedules it
///    silently — the child is *never* shown an overdue pile).
public struct SessionPlanner: Sendable {

    public struct Limits: Sendable, Equatable {
        public var dailyReviewLimit: Int
        public var newCardsPerDay: Int
        public init(dailyReviewLimit: Int, newCardsPerDay: Int) {
            self.dailyReviewLimit = dailyReviewLimit
            self.newCardsPerDay = newCardsPerDay
        }
    }

    /// A card reference + its scheduling state. Generic over the app's own ID type.
    public struct Item<ID: Hashable & Sendable>: Sendable {
        public var id: ID
        public var state: SchedulerState
        public init(id: ID, state: SchedulerState) {
            self.id = id
            self.state = state
        }
    }

    public init() {}

    /// Returns the ordered set of card IDs to study today.
    ///
    /// - Parameters:
    ///   - candidates: all cards assigned to the child.
    ///   - limits: the parent-set daily caps.
    ///   - now: "today" reference instant; a card is due when `dueDate <= now`.
    public func plan<ID: Hashable & Sendable>(
        candidates: [Item<ID>],
        limits: Limits,
        now: Date
    ) -> [ID] {
        // Due reviews: status .review or .learning whose dueDate has arrived.
        let dueReviews = candidates
            .filter { ($0.state.status == .review || $0.state.status == .learning)
                && $0.state.dueDate <= now }
            .sorted { $0.state.dueDate < $1.state.dueDate }
            .prefix(max(0, limits.dailyReviewLimit))
            .map(\.id)

        // New cards fill remaining headroom, capped independently.
        let newCards = candidates
            .filter { $0.state.status == .new }
            .prefix(max(0, limits.newCardsPerDay))
            .map(\.id)

        // Reviews first, then new cards (Spec §6.2).
        return Array(dueReviews) + Array(newCards)
    }
}
