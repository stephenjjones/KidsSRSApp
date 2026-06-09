import Foundation

/// Read-only view model for the "pick your face" launch screen (Spec §6.1).
///
/// The child zone is never gated (§8.1) and must not mutate profiles, so this is
/// deliberately separate from the parent zone's `ChildrenViewModel` — it only
/// fetches `ChildSummary` values through the repository (§4.1).
@MainActor
final class ProfilePickerViewModel: ObservableObject {
    @Published private(set) var children: [ChildSummary] = []
    @Published var errorMessage: String?

    private let repository: ChildRepository
    private var remoteChanges: RemoteChangeObserver?

    init(repository: ChildRepository = ChildRepository()) {
        self.repository = repository
        // Refresh the profile list when another device's changes sync in (§10.1).
        remoteChanges = RemoteChangeObserver { [weak self] in self?.load() }
    }

    func load() {
        do { children = try repository.fetchChildren() }
        catch { errorMessage = error.localizedDescription }
    }

    /// Preview factory backed by the in-memory store (reuses the seeded profiles).
    static func sample() -> ProfilePickerViewModel {
        let editor = ChildrenViewModel.sample() // seeds the shared preview store
        let model = ProfilePickerViewModel(repository: .preview)
        model.children = editor.children
        return model
    }
}
