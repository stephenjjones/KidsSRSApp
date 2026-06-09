import Foundation

/// Selects songs for a cross-playlist, spaced-repetition Song Review (Spec §14.3)
/// over a chosen set of children. Pure & testable; the repository supplies, per
/// candidate song, each selected child's scheduler state (nil = never scored).
///
/// A song is included when **at least one** selected child needs it — due for
/// review, or new to them — and excluded when every selected child already knows
/// it (scheduled for later). Due songs come first (earliest due, then the most
/// kids needing it); new songs follow, capped so a first session isn't enormous.
public struct SongReviewPlanner: Sendable {

    public struct Candidate<ID: Hashable & Sendable>: Sendable {
        public let id: ID
        /// Per selected child: their state, or nil if never scored (new to them).
        public let childStates: [SchedulerState?]
        public init(id: ID, childStates: [SchedulerState?]) {
            self.id = id
            self.childStates = childStates
        }
    }

    public init() {}

    /// - Parameters:
    ///   - candidates: every song, with the selected children's states.
    ///   - now: a song is "due" when a child's `dueDate <= now`.
    ///   - newLimit: cap on never-scored songs added after the due ones.
    public func plan<ID: Hashable & Sendable>(
        candidates: [Candidate<ID>],
        now: Date,
        newLimit: Int = 10
    ) -> [ID] {
        var dueSongs: [(id: ID, earliest: Date, needyCount: Int)] = []
        var newSongs: [ID] = []

        for candidate in candidates {
            var dueDates: [Date] = []
            var anyNew = false
            for state in candidate.childStates {
                if let state {
                    if (state.status == .review || state.status == .learning), state.dueDate <= now {
                        dueDates.append(state.dueDate)
                    }
                } else {
                    anyNew = true // never scored by this child
                }
            }
            if !dueDates.isEmpty {
                dueSongs.append((candidate.id, dueDates.min()!, dueDates.count))
            } else if anyNew {
                newSongs.append(candidate.id)
            }
            // else: every selected child has it and none are due → known, skip.
        }

        let dueOrdered = dueSongs.sorted {
            $0.earliest != $1.earliest ? $0.earliest < $1.earliest : $0.needyCount > $1.needyCount
        }.map(\.id)

        return dueOrdered + Array(newSongs.prefix(max(0, newLimit)))
    }
}
