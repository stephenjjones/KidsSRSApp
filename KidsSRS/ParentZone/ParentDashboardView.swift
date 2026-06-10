import SwiftUI
import KidsSRSCore

/// Parent zone home: child management + per-child progress (Spec §8.2–§8.4),
/// plus entry points for decks, Song Review, Game Mode, and access settings.
struct ParentDashboardView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var children: ChildrenViewModel

    @State private var showingNewChild = false
    @State private var newChildName = ""
    @State private var deleteTarget: ChildSummary?

    /// Observes CloudKit sync health for the status row (Spec §10.1). Nil when
    /// mirroring is off (local-only build / previews) — then no row is shown.
    private let syncMonitor: CloudKitSyncMonitor?

    /// Injected by the caller on the main actor (live store in the app, a
    /// `.sample()` one in previews).
    init(children: ChildrenViewModel,
         syncMonitor: CloudKitSyncMonitor? = PersistenceController.shared.syncMonitor) {
        _children = StateObject(wrappedValue: children)
        self.syncMonitor = syncMonitor
    }

    var body: some View {
        NavigationStack {
            List {
                childrenSection
                progressSection
                Section("Decks") {
                    // Spec §8.3: parent deck/card authoring (text cards this pass).
                    NavigationLink("Author decks") {
                        DeckListView(model: DeckEditorViewModel())
                    }
                }
                Section("Song Review") {
                    // Direct shortcut to the auto-built "what's due" review (§14.3) —
                    // otherwise reached via Song playlists. Consent is still enforced
                    // inside the player (§14.1), so this entry point is safe.
                    NavigationLink {
                        SmartSongReviewView(model: SmartSongReviewViewModel())
                    } label: {
                        Label("Smart review (what's due)", systemImage: "sparkles")
                    }
                    // Spec §14.3: parent-led video playlists.
                    NavigationLink("Song playlists") {
                        SongPlaylistView(model: DeckEditorViewModel())
                    }
                    // Spec §14.1: parental consent required before any video loads.
                    NavigationLink("Video consent") {
                        VideoConsentSettingsView()
                    }
                }
                Section("Game Mode") {
                    // Spec §14.5: board-game card draws, individualized + by category.
                    NavigationLink("Play Game Mode") {
                        GameModeView(model: GameModeViewModel())
                    }
                }
                Section("Pacing") {
                    // Spec §7.3: gentle / normal / fast presets (per-child below).
                    ForEach(PacingProfile.allCases, id: \.self) { profile in
                        let p = SchedulerParameters.defaults(for: profile)
                        LabeledContent(profile.rawValue.capitalized,
                                       value: "\(p.newCardsPerDay) new/day · ≤\(Int(p.maxIntervalDays))d")
                    }
                }
                Section("Parent access") {
                    // Spec §8.1: choose passcode/biometric instead of the math gate.
                    NavigationLink("Lock & passcode") {
                        AdultGateSettingsView()
                    }
                }
                if let syncMonitor {
                    SyncStatusSection(monitor: syncMonitor)
                }
            }
            .navigationTitle("Parents")
            .toolbar {
                Button("Done") { appState.backToProfiles() }
            }
            .alert("Add child", isPresented: $showingNewChild) {
                TextField("Name", text: $newChildName)
                Button("Add") { _ = children.createChild(name: newChildName) }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Add a profile for each child who studies on this device.")
            }
            .confirmationDialog(
                "Remove this profile?",
                isPresented: deletePresented,
                titleVisibility: .visible,
                presenting: deleteTarget
            ) { child in
                Button("Remove “\(child.displayName)”", role: .destructive) {
                    children.deleteChild(id: child.id)
                }
                Button("Cancel", role: .cancel) {}
            } message: { _ in
                Text("This also removes that child's study progress and rewards.")
            }
            .alert("Something went wrong",
                   isPresented: errorPresented,
                   presenting: children.errorMessage) { _ in
                Button("OK") { children.errorMessage = nil }
            } message: { message in
                Text(message)
            }
            .task { children.load() }
        }
    }

    private var childrenSection: some View {
        Section("Children") {
            if children.children.isEmpty {
                Text("No profiles yet. Add your first child below.")
                    .foregroundStyle(.secondary)
            }
            ForEach(children.children) { child in
                NavigationLink {
                    ChildDetailView(child: child, model: children)
                } label: {
                    ChildRow(child: child)
                }
                #if os(iOS)
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) { deleteTarget = child } label: {
                        Label("Remove", systemImage: "trash")
                    }
                }
                #endif
                .contextMenu {
                    Button(role: .destructive) { deleteTarget = child } label: {
                        Label("Remove", systemImage: "trash")
                    }
                }
            }
            Button {
                newChildName = ""
                showingNewChild = true
            } label: {
                Label("Add child", systemImage: "plus")
            }
            .accessibilityLabel("Add child")
        }
    }

    /// Per-child progress insight (Spec §8.4), distinct from management above.
    private var progressSection: some View {
        Section("Progress") {
            if children.children.isEmpty {
                Text("Add a child to see their progress.")
                    .foregroundStyle(.secondary)
            }
            ForEach(children.children) { child in
                NavigationLink {
                    ChildProgressView(
                        model: ChildProgressViewModel(childID: child.id,
                                                      childName: child.displayName)
                    )
                } label: {
                    Label(child.displayName.isEmpty ? "Unnamed" : child.displayName,
                          systemImage: "chart.bar.fill")
                }
            }
        }
    }

    private var deletePresented: Binding<Bool> {
        Binding(get: { deleteTarget != nil },
                set: { if !$0 { deleteTarget = nil } })
    }

    private var errorPresented: Binding<Bool> {
        Binding(get: { children.errorMessage != nil },
                set: { if !$0 { children.errorMessage = nil } })
    }
}

/// One row in the Children list: name + a short settings summary.
private struct ChildRow: View {
    let child: ChildSummary

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: ProfileFace(id: child.id).symbol)
                .foregroundStyle(.tint)
                .imageScale(.large)
            VStack(alignment: .leading, spacing: 2) {
                Text(child.displayName.isEmpty ? "Unnamed" : child.displayName)
                    .font(.headline)
                Text("\(child.pacingProfile.rawValue.capitalized) · "
                     + "\(child.dailyNewCardLimit) new/day · \(child.dailyReviewLimit) reviews/day")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(child.displayName), \(child.pacingProfile.rawValue) pacing, "
                            + "\(child.dailyNewCardLimit) new cards per day, "
                            + "\(child.dailyReviewLimit) reviews per day")
    }
}

/// Compact iCloud-sync health row (Spec §10.1) so a parent can see — and a
/// stalled/failed sync isn't invisible. Color is paired with an icon **and**
/// text, never on its own (Spec §11).
private struct SyncStatusSection: View {
    @ObservedObject var monitor: CloudKitSyncMonitor

    var body: some View {
        let summary = monitor.summary
        Section("iCloud Sync") {
            HStack(spacing: 12) {
                Image(systemName: icon(summary.state))
                    .foregroundStyle(tint(summary.state))
                    .imageScale(.large)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title(summary.state)).font(.headline)
                    subtitle(summary)
                }
            }
            .padding(.vertical, 2)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibilityText(summary))
        }
    }

    @ViewBuilder
    private func subtitle(_ s: CloudKitSyncMonitor.Summary) -> some View {
        if let detail = s.errorDetail {
            Text(detail).font(.caption).foregroundStyle(.secondary)
        } else if let date = s.lastSyncedAt {
            Text("Last synced \(date.formatted(.relative(presentation: .named)))")
                .font(.subheadline).foregroundStyle(.secondary)
        } else if s.state == .healthy || s.state == .syncing {
            Text("Your family's devices stay in sync over iCloud.")
                .font(.subheadline).foregroundStyle(.secondary)
        }
    }

    private func icon(_ s: CloudKitSyncMonitor.Summary.State) -> String {
        switch s {
        case .idle:    return "icloud"
        case .syncing: return "arrow.triangle.2.circlepath"
        case .healthy: return "checkmark.icloud.fill"
        case .failing: return "exclamationmark.icloud.fill"
        }
    }
    private func tint(_ s: CloudKitSyncMonitor.Summary.State) -> Color {
        switch s {
        case .idle:    return .secondary
        case .syncing: return .accentColor
        case .healthy: return .green
        case .failing: return .orange
        }
    }
    private func title(_ s: CloudKitSyncMonitor.Summary.State) -> String {
        switch s {
        case .idle:    return "Waiting to sync"
        case .syncing: return "Syncing…"
        case .healthy: return "Sync on"
        case .failing: return "Sync problem"
        }
    }
    private func accessibilityText(_ s: CloudKitSyncMonitor.Summary) -> String {
        var parts = ["iCloud sync", title(s.state)]
        if let detail = s.errorDetail {
            parts.append(detail)
        } else if let date = s.lastSyncedAt {
            parts.append("last synced \(date.formatted(.relative(presentation: .named)))")
        }
        return parts.joined(separator: ", ")
    }
}

#Preview {
    ParentDashboardView(children: .sample(), syncMonitor: nil)
        .environmentObject(AppState())
}
