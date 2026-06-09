import Foundation

/// Drives multi-child management in the parent zone (Spec §8.2).
///
/// Mirrors `DeckEditorViewModel`: `@MainActor`, `@Published private(set)` state,
/// a dependency-injected `ChildRepository`, and a `sample()` factory. Exposes
/// only `ChildSummary` value types — no `NSManagedObject` reaches the view (§4.1).
@MainActor
final class ChildrenViewModel: ObservableObject {
    @Published private(set) var children: [ChildSummary] = []
    /// Last error, surfaced to the parent rather than swallowed (Spec §8.3).
    @Published var errorMessage: String?

    private let repository: ChildRepository
    private let reminders: ReminderScheduling
    private var remoteChanges: RemoteChangeObserver?

    init(repository: ChildRepository = ChildRepository(),
         reminders: ReminderScheduling = LocalReminderScheduler()) {
        self.repository = repository
        self.reminders = reminders
        // Refresh when another device's changes sync in (Spec §10.1).
        remoteChanges = RemoteChangeObserver { [weak self] in self?.load() }
    }

    /// (Re)load the child list from the store.
    func load() {
        perform { self.children = try self.repository.fetchChildren() }
    }

    @discardableResult
    func createChild(name: String) -> ChildSummary? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        var created: ChildSummary?
        perform { created = try self.repository.createChild(name: trimmed) }
        load()
        return created
    }

    func renameChild(id: UUID, name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        perform { try self.repository.renameChild(id: id, name: trimmed) }
        load()
    }

    /// Persist edited per-child settings (name, limits, pacing, a11y, reminder).
    func updateChild(_ child: ChildSummary) {
        perform { try self.repository.updateChild(child) }
        load()
        reconcileReminders()
    }

    func deleteChild(id: UUID) {
        perform { try self.repository.deleteChild(id: id) }
        load()
        reconcileReminders()
    }

    /// Re-sync scheduled reminders to the current children (Spec §10.4).
    private func reconcileReminders() {
        let snapshot = children
        Task { await reminders.reconcile(children: snapshot) }
    }

    private func perform(_ action: () throws -> Void) {
        do { try action() }
        catch { errorMessage = error.localizedDescription }
    }

    /// Preview/test factory backed by the in-memory store, pre-seeded.
    static func sample() -> ChildrenViewModel {
        let repository = ChildRepository.preview
        if (try? repository.fetchChildren())?.isEmpty ?? true {
            _ = try? repository.createChild(name: "Mia")
            _ = try? repository.createChild(name: "Leo")
            _ = try? repository.createChild(name: "Ada")
        }
        let model = ChildrenViewModel(repository: repository, reminders: NoopReminderScheduler())
        model.load()
        return model
    }
}
