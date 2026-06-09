import CoreData
import KidsSRSCore

// MARK: - UI-facing value type

/// A value-type snapshot of a child profile (Spec §5 `Child`, §8.2 per-child
/// settings). Spec §4.1 guardrail: views and view models never see `ChildMO` —
/// only this plain value crosses the repository boundary. `Identifiable` on the
/// **stable** child id (Spec §5).
struct ChildSummary: Identifiable, Equatable, Hashable {
    /// Stable, permanent child identity (Spec §5) — keys this child's
    /// `CardState`, sessions and rewards. Never reassigned on edit.
    let id: UUID
    var displayName: String
    /// Parent-set daily caps (Spec §7.4).
    var dailyNewCardLimit: Int
    var dailyReviewLimit: Int
    /// Pacing preset that expands to scheduler parameters (Spec §7.3).
    var pacingProfile: PacingProfile
    // Per-child accessibility preferences (Spec §11).
    var dyslexiaMode: Bool
    var readAloud: Bool
    var reduceMotion: Bool
    /// The equipped reward avatar's item id (Spec §9.3), or nil for the default
    /// face. Read from `avatarConfig`; set via `setEquippedReward`.
    var equippedItemID: UUID?
    // Optional daily study reminder (Spec §10.4) — off by default.
    var reminderEnabled: Bool = false
    var reminderHour: Int = 16
    var reminderMinute: Int = 0
}

/// Encoded into `Child.avatarConfig` (Spec §5). Codable so further avatar
/// customizations can be added later without breaking stored data.
struct AvatarConfig: Codable, Equatable {
    var equippedItemID: UUID?
}

/// Errors surfaced by `ChildRepository`.
enum ChildRepositoryError: LocalizedError {
    case childNotFound(UUID)

    var errorDescription: String? {
        switch self {
        case .childNotFound: return "That child profile could no longer be found."
        }
    }
}

// MARK: - Repository

/// The Core Data boundary for child profiles (Spec §8.2).
///
/// Mirrors `DeckRepository`: owns a (main-queue) view context, exchanges only
/// the `ChildSummary` value type, and `save()`s + `throw`s on every write so the
/// parent zone can surface failures. All `ChildMO` attributes are optional /
/// scalar-with-default for CloudKit (Spec §5), so reads coalesce defensively.
final class ChildRepository {
    private let context: NSManagedObjectContext

    /// Designated initializer — inject any context (e.g. a preview/in-memory one).
    init(context: NSManagedObjectContext) {
        self.context = context
    }

    /// Convenience: back the repository with a `PersistenceController` (defaults
    /// to the shared store; pass `.preview` for previews/tests).
    convenience init(persistence: PersistenceController = .shared) {
        self.init(context: persistence.container.viewContext)
    }

    /// An in-memory repository for SwiftUI previews and unit tests.
    static var preview: ChildRepository {
        ChildRepository(persistence: .preview)
    }

    // MARK: Reads

    /// All child profiles, sorted by name (case-insensitive).
    func fetchChildren() throws -> [ChildSummary] {
        let request = NSFetchRequest<ChildMO>(entityName: "Child")
        request.sortDescriptors = [
            NSSortDescriptor(key: "displayName", ascending: true,
                             selector: #selector(NSString.localizedCaseInsensitiveCompare(_:)))
        ]
        return try context.fetch(request).map(Self.summary(from:))
    }

    // MARK: Writes

    /// Create a new child profile. Scalar settings take the model's defaults
    /// (Spec §5/§7.3: 5 new/day, 40 reviews/day, normal pacing).
    @discardableResult
    func createChild(name: String) throws -> ChildSummary {
        let child = ChildMO(context: context)
        child.id = UUID()
        child.displayName = name
        try save()
        return Self.summary(from: child)
    }

    /// Rename a child. Identity is preserved (Spec §5).
    func renameChild(id: UUID, name: String) throws {
        let child = try childMO(id: id)
        child.displayName = name
        try save()
    }

    /// Update a child's full settings (Spec §8.2). Identity is preserved.
    func updateChild(_ summary: ChildSummary) throws {
        let child = try childMO(id: summary.id)
        child.displayName = summary.displayName
        child.dailyNewCardLimit = Int16(clamping: summary.dailyNewCardLimit)
        child.dailyReviewLimit = Int16(clamping: summary.dailyReviewLimit)
        child.pacingProfile = summary.pacingProfile.rawValue
        child.dyslexiaMode = summary.dyslexiaMode
        child.readAloud = summary.readAloud
        child.reduceMotion = summary.reduceMotion
        child.reminderEnabled = summary.reminderEnabled
        child.reminderHour = Int16(clamping: summary.reminderHour)
        child.reminderMinute = Int16(clamping: summary.reminderMinute)
        try save()
    }

    /// Delete a child and (by the model's cascade rules) its card states,
    /// sessions and reward progress.
    func deleteChild(id: UUID) throws {
        let child = try childMO(id: id)
        context.delete(child)
        try save()
    }

    // MARK: Reward avatar (Spec §9.3)

    /// Equip (or clear, with nil) a child's reward avatar — writes the item id
    /// into `avatarConfig`. The caller equips only unlocked items.
    func setEquippedReward(itemID: UUID?, forChild childID: UUID) throws {
        let child = try childMO(id: childID)
        child.avatarConfig = try? JSONEncoder().encode(AvatarConfig(equippedItemID: itemID))
        try save()
    }

    /// The child's currently equipped reward item id, or nil.
    func equippedReward(forChild childID: UUID) throws -> UUID? {
        Self.equippedItemID(from: try childMO(id: childID))
    }

    // MARK: - Private helpers

    private func childMO(id: UUID) throws -> ChildMO {
        guard let child = try context.fetchFirst(ChildMO.self, entityName: "Child", id: id) else {
            throw ChildRepositoryError.childNotFound(id)
        }
        return child
    }

    private func save() throws {
        guard context.hasChanges else { return }
        try context.save()
    }

    /// Defensive mapping — all `ChildMO` attributes are optional/scalar-with-
    /// default for CloudKit (Spec §5).
    private static func summary(from child: ChildMO) -> ChildSummary {
        ChildSummary(
            id: child.id ?? UUID(),
            displayName: child.displayName ?? "",
            dailyNewCardLimit: Int(child.dailyNewCardLimit),
            dailyReviewLimit: Int(child.dailyReviewLimit),
            pacingProfile: PacingProfile(rawValue: child.pacingProfile ?? "") ?? .normal,
            dyslexiaMode: child.dyslexiaMode,
            readAloud: child.readAloud,
            reduceMotion: child.reduceMotion,
            equippedItemID: equippedItemID(from: child),
            reminderEnabled: child.reminderEnabled,
            reminderHour: Int(child.reminderHour),
            reminderMinute: Int(child.reminderMinute)
        )
    }

    private static func equippedItemID(from child: ChildMO) -> UUID? {
        guard let data = child.avatarConfig,
              let config = try? JSONDecoder().decode(AvatarConfig.self, from: data) else { return nil }
        return config.equippedItemID
    }
}
