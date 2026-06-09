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

    /// Injected by the caller on the main actor (live store in the app, a
    /// `.sample()` one in previews).
    init(children: ChildrenViewModel) {
        _children = StateObject(wrappedValue: children)
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

#Preview {
    ParentDashboardView(children: .sample())
        .environmentObject(AppState())
}
