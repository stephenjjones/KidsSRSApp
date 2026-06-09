import CoreData
import KidsSRSCore

/// A snapshot of a child's reward state for display (Spec §9.3). Spec §4.1: the
/// view never sees `RewardProgressMO`.
struct RewardSummary: Equatable {
    /// Completed study sessions counted toward milestones.
    var sessionsCompleted: Int
    /// Items unlocked *by this update* — drives the session-end celebration.
    var newlyUnlocked: [RewardItem]
    /// The full collection earned so far (for the trophy strip).
    var unlockedItems: [RewardItem]
    /// The next thing to earn; `nil` once everything is unlocked.
    var nextMilestone: RewardMilestone?
    /// Progress `0...1` toward `nextMilestone` (always-visible, Spec §9.3).
    var progressToNext: Double

    /// Sessions still needed for the next unlock (0 if none / already unlocked).
    var sessionsUntilNext: Int {
        guard let next = nextMilestone else { return 0 }
        return max(0, next.requiredSessions - sessionsCompleted)
    }
}

/// The Core Data boundary for the deterministic reward economy (Spec §9.3).
///
/// Reward progress is per child (`RewardProgress`); unlocking is driven entirely
/// by the pure `RewardEngine` (no randomness, no loot boxes — Kids-Category
/// compliant). `points` stores cumulative completed sessions.
final class RewardRepository {
    private let context: NSManagedObjectContext
    private let engine: RewardEngine

    init(context: NSManagedObjectContext, engine: RewardEngine = RewardCatalog.engine) {
        self.context = context
        self.engine = engine
    }

    convenience init(persistence: PersistenceController = .shared,
                     engine: RewardEngine = RewardCatalog.engine) {
        self.init(context: persistence.container.viewContext, engine: engine)
    }

    static var preview: RewardRepository {
        RewardRepository(persistence: .preview)
    }

    /// Read-only current state (no mutation) — used to show the collection even
    /// when there's nothing new to celebrate.
    func summary(forChild childID: UUID) throws -> RewardSummary {
        let progress = try existingProgress(forChild: childID)
        let sessions = Int(progress?.points ?? 0)
        let unlocked = unlockedIDs(progress)
        return makeSummary(sessions: sessions, unlockedIDs: unlocked, newly: [])
    }

    /// Advance one completed session and return what (if anything) was unlocked.
    @discardableResult
    func recordCompletedSession(forChild childID: UUID) throws -> RewardSummary {
        let progress = try findOrCreateProgress(forChild: childID)
        let previous = Int(progress.points)
        let now = previous + 1

        let newly = engine.newlyUnlocked(previous: previous, now: now)
        var unlocked = unlockedIDs(progress)
        for milestone in newly { unlocked.insert(milestone.item.id) }

        progress.points = Int32(now)
        progress.unlockedItemIDs = unlocked.map { $0 as NSUUID }
        progress.currentMilestoneID = engine.nextMilestone(completedSessions: now)?.id
        try save()

        return makeSummary(sessions: now, unlockedIDs: unlocked, newly: newly.map(\.item))
    }

    // MARK: - Helpers

    private func makeSummary(sessions: Int, unlockedIDs: Set<UUID>,
                             newly: [RewardItem]) -> RewardSummary {
        // The persisted set is the source of truth for the collection; the next
        // milestone / progress are derived deterministically from the count.
        let unlockedItems = engine.milestones
            .filter { unlockedIDs.contains($0.item.id) }
            .map(\.item)
        return RewardSummary(
            sessionsCompleted: sessions,
            newlyUnlocked: newly,
            unlockedItems: unlockedItems,
            nextMilestone: engine.nextMilestone(completedSessions: sessions),
            progressToNext: engine.progressToNext(completedSessions: sessions)
        )
    }

    private func unlockedIDs(_ progress: RewardProgressMO?) -> Set<UUID> {
        Set((progress?.unlockedItemIDs ?? []).map { $0 as UUID })
    }

    private func existingProgress(forChild childID: UUID) throws -> RewardProgressMO? {
        let request = NSFetchRequest<RewardProgressMO>(entityName: "RewardProgress")
        request.predicate = NSPredicate(format: "child.id == %@", childID as NSUUID)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    private func findOrCreateProgress(forChild childID: UUID) throws -> RewardProgressMO {
        if let existing = try existingProgress(forChild: childID) { return existing }
        guard let child = try context.fetchFirst(ChildMO.self, entityName: "Child", id: childID) else {
            throw StudyRepositoryError.childNotFound(childID)
        }
        let progress = RewardProgressMO(context: context)
        progress.child = child
        progress.points = 0
        return progress
    }

    private func save() throws {
        guard context.hasChanges else { return }
        try context.save()
    }
}
