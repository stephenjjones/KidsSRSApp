import Foundation

/// Selects and ranks cards for **Game Mode** draws (Spec §14.5).
///
/// Game Mode replaces a board game's question cards: the app draws a card on
/// demand, individualized to the child. This is the pure, persistence-free
/// ranking — the repository supplies the candidate cards (already filtered to a
/// child's assigned decks and chosen categories) plus each card's scheduling
/// state, and this orders them so the cards the child knows *least* well come
/// first. The Game Mode UI can take from the top or sample by rank.
///
/// Ranking, highest priority first:
///  1. **Due** learning/review cards — actively need practice *now*.
///  2. **New** cards — not yet introduced.
///  3. Not-yet-due learning/review cards — already known well enough to be
///     scheduled for later, so least worth drawing.
///
/// Within a tier, cards with **more lapses** rank first (struggling content),
/// then the **earliest due** date. `retired` cards are never drawn.
public struct GameDrawPlanner: Sendable {

    public init() {}

    /// Rank drawable cards, most worth practicing first (Spec §14.5).
    ///
    /// - Parameters:
    ///   - candidates: cards already scoped to the child's assigned decks and
    ///     the chosen categories, each paired with its scheduling state. Reuses
    ///     `SessionPlanner.Item` (an `id` + `SchedulerState` pair).
    ///   - now: reference instant; a card is "due" when `dueDate <= now`.
    public func ranked<ID: Hashable & Sendable>(
        candidates: [SessionPlanner.Item<ID>],
        now: Date
    ) -> [ID] {
        candidates
            .filter { $0.state.status != .retired }
            .sorted { Self.sortsBefore($0.state, $1.state, now: now) }
            .map(\.id)
    }

    /// Strict-weak ordering used by `ranked`: higher tier first, then more
    /// lapses, then earlier due date. Kept `static` and deterministic so it can
    /// be unit-tested directly.
    static func sortsBefore(_ a: SchedulerState, _ b: SchedulerState, now: Date) -> Bool {
        let ta = tier(a, now: now), tb = tier(b, now: now)
        if ta != tb { return ta > tb }
        if a.lapses != b.lapses { return a.lapses > b.lapses }
        return a.dueDate < b.dueDate
    }

    /// 2 = due & active (most needed), 1 = new, 0 = not-yet-due (least needed).
    private static func tier(_ s: SchedulerState, now: Date) -> Int {
        switch s.status {
        case .review, .learning: return s.dueDate <= now ? 2 : 0
        case .new:               return 1
        case .retired:           return -1
        }
    }
}
