import Foundation

// MARK: - Domain types

/// A collectible cosmetic reward — an avatar/customization (Spec §9.3). The
/// `symbol` is a presentation hint (an SF Symbol name); the domain stays UI-free.
public struct RewardItem: Identifiable, Equatable, Sendable {
    /// Stable, permanent identity — persisted in the child's unlocked set.
    public let id: UUID
    public let name: String
    public let symbol: String

    public init(id: UUID, name: String, symbol: String) {
        self.id = id
        self.name = name
        self.symbol = symbol
    }
}

/// A deterministic "study X → earn Y" milestone (Spec §9.3). No randomness, no
/// loot boxes: reaching `requiredSessions` completed sessions unlocks `item`.
public struct RewardMilestone: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let requiredSessions: Int
    public let item: RewardItem

    public init(id: UUID, requiredSessions: Int, item: RewardItem) {
        self.id = id
        self.requiredSessions = requiredSessions
        self.item = item
    }
}

// MARK: - Engine

/// Pure, deterministic reward evaluation (Spec §9.3). Mirrors the Scheduler's
/// design: no persistence, no UI, no randomness — so it's fully unit-testable
/// and provably non-loot-box for Kids-Category compliance.
public struct RewardEngine: Sendable {
    /// Milestones in ascending requirement order.
    public let milestones: [RewardMilestone]

    public init(milestones: [RewardMilestone]) {
        self.milestones = milestones.sorted { $0.requiredSessions < $1.requiredSessions }
    }

    /// The next milestone not yet reached, or `nil` if everything is unlocked.
    public func nextMilestone(completedSessions: Int) -> RewardMilestone? {
        milestones.first { $0.requiredSessions > completedSessions }
    }

    /// Milestones whose threshold was crossed moving `previous → now`.
    public func newlyUnlocked(previous: Int, now: Int) -> [RewardMilestone] {
        milestones.filter { $0.requiredSessions > previous && $0.requiredSessions <= now }
    }

    /// All milestones unlocked at `completedSessions`.
    public func unlockedMilestones(completedSessions: Int) -> [RewardMilestone] {
        milestones.filter { $0.requiredSessions <= completedSessions }
    }

    /// Progress in `0...1` from the previous milestone toward the next one.
    /// Returns `1` once every milestone is unlocked.
    public func progressToNext(completedSessions: Int) -> Double {
        guard let next = nextMilestone(completedSessions: completedSessions) else { return 1 }
        let previousRequirement = milestones
            .last { $0.requiredSessions <= completedSessions }?.requiredSessions ?? 0
        let span = next.requiredSessions - previousRequirement
        guard span > 0 else { return 0 }
        let done = completedSessions - previousRequirement
        return min(1, max(0, Double(done) / Double(span)))
    }
}

// MARK: - Bundled catalog

/// The shipped, fixed reward ladder (Spec §9.3). IDs are **permanent constants**
/// so a child's unlocked set stays valid across launches and app updates.
public enum RewardCatalog {
    public static let milestones: [RewardMilestone] = [
        RewardMilestone(
            id: UUID(uuidString: "0E000000-0000-0000-0000-000000000001")!,
            requiredSessions: 1,
            item: RewardItem(id: UUID(uuidString: "17E11000-0000-0000-0000-000000000001")!,
                             name: "Starter Star", symbol: "star.fill")),
        RewardMilestone(
            id: UUID(uuidString: "0E000000-0000-0000-0000-000000000002")!,
            requiredSessions: 3,
            item: RewardItem(id: UUID(uuidString: "17E11000-0000-0000-0000-000000000002")!,
                             name: "Brave Fox", symbol: "pawprint.fill")),
        RewardMilestone(
            id: UUID(uuidString: "0E000000-0000-0000-0000-000000000003")!,
            requiredSessions: 7,
            item: RewardItem(id: UUID(uuidString: "17E11000-0000-0000-0000-000000000003")!,
                             name: "Clever Owl", symbol: "bird.fill")),
        RewardMilestone(
            id: UUID(uuidString: "0E000000-0000-0000-0000-000000000004")!,
            requiredSessions: 14,
            item: RewardItem(id: UUID(uuidString: "17E11000-0000-0000-0000-000000000004")!,
                             name: "Mighty Dragon", symbol: "lizard.fill")),
        RewardMilestone(
            id: UUID(uuidString: "0E000000-0000-0000-0000-000000000005")!,
            requiredSessions: 30,
            item: RewardItem(id: UUID(uuidString: "17E11000-0000-0000-0000-000000000005")!,
                             name: "Champion Crown", symbol: "crown.fill")),
    ]

    /// An engine over the bundled ladder.
    public static var engine: RewardEngine { RewardEngine(milestones: milestones) }

    /// Look up an item by its stable id — used to render a child's equipped
    /// avatar from the id persisted in `avatarConfig`.
    public static func item(id: UUID) -> RewardItem? {
        milestones.first { $0.item.id == id }?.item
    }
}
