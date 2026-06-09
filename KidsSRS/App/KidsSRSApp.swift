import SwiftUI

/// App entry point. SwiftUI multiplatform (iOS + macOS) — Spec §4.
@main
struct KidsSRSApp: App {
    @StateObject private var persistence = PersistenceController.shared
    @StateObject private var appState = AppState()

    init() {
        // Register the bundled OpenDyslexic font for dyslexia mode (Spec §11).
        DyslexiaFontProvider.registerBundledFonts()

        // Seed bundled starter decks on first launch (idempotent) so a fresh
        // install has something to study right away (Spec §9.1).
        try? StarterDeckImporter().importIfNeeded()

        // Serve the Song Review player from a real localhost origin so YouTube
        // embeds play (Spec §14.3 / LocalPlayerServer). Idempotent.
        LocalPlayerServer.shared.startIfNeeded()

        // Re-sync any parent-enabled study reminders to the OS (Spec §10.4).
        Task { @MainActor in
            let children = (try? ChildRepository().fetchChildren()) ?? []
            await LocalReminderScheduler().reconcile(children: children)
        }
    }

    var body: some Scene {
        WindowGroup {
            if persistence.loadError != nil {
                // Spec §4: degrade gracefully instead of crashing on a store that
                // can't be opened (e.g. a migration that can't be inferred).
                StoreUnavailableView()
            } else {
                RootView()
                    .environment(\.managedObjectContext, persistence.container.viewContext)
                    .environmentObject(appState)
            }
        }
        #if os(macOS)
        .defaultSize(width: 900, height: 680)
        #endif
    }
}

/// Shown when the persistent store can't be opened (Spec §4). Informative, not a
/// crash; deliberately offers no destructive "reset" (that would erase the only
/// copy of local data — a future version with sync on could recover from iCloud).
struct StoreUnavailableView: View {
    var body: some View {
        ContentUnavailableView {
            Label("Couldn't open your data", systemImage: "externaldrive.badge.exclamationmark")
        } description: {
            Text("Something went wrong loading your saved progress. Please close and reopen the app. If it keeps happening, restarting your device may help.")
        }
        .padding()
    }
}

/// Top-level navigation gate: profile picker → study, with a gated parent zone.
struct RootView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        switch appState.route {
        case .profilePicker:
            ProfilePickerView(model: ProfilePickerViewModel())
        case .studying(let childID):
            StudySessionView(model: StudyViewModel(childID: childID))
        case .parentZone:
            ParentDashboardView(children: ChildrenViewModel())
        }
    }
}
