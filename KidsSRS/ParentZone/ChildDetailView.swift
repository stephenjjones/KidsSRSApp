import SwiftUI
import KidsSRSCore

/// Per-child settings (Spec §8.2): name, parent-set daily caps (§7.4), pacing
/// preset (§7.3), and per-child accessibility preferences (§11). Pushed from the
/// parent dashboard's Children section. Edits are applied live through the
/// shared `ChildrenViewModel`.
struct ChildDetailView: View {
    @ObservedObject var model: ChildrenViewModel
    @State private var child: ChildSummary

    init(child: ChildSummary, model: ChildrenViewModel) {
        self.model = model
        _child = State(initialValue: child)
    }

    /// Bridges the stored hour/minute to a `DatePicker` time.
    private var reminderTime: Binding<Date> {
        Binding(
            get: {
                var components = DateComponents()
                components.hour = child.reminderHour
                components.minute = child.reminderMinute
                return Calendar.current.date(from: components) ?? Date()
            },
            set: { newValue in
                let components = Calendar.current.dateComponents([.hour, .minute], from: newValue)
                child.reminderHour = components.hour ?? 16
                child.reminderMinute = components.minute ?? 0
            }
        )
    }

    var body: some View {
        Form {
            Section("Name") {
                TextField("Child's name", text: $child.displayName)
                    .accessibilityLabel("Child's name")
            }

            Section {
                Stepper(value: $child.dailyNewCardLimit, in: 0...50) {
                    LabeledContent("New cards / day", value: "\(child.dailyNewCardLimit)")
                }
                .accessibilityLabel("New cards per day")
                .accessibilityValue("\(child.dailyNewCardLimit)")

                Stepper(value: $child.dailyReviewLimit, in: 0...200, step: 5) {
                    LabeledContent("Reviews / day", value: "\(child.dailyReviewLimit)")
                }
                .accessibilityLabel("Reviews per day")
                .accessibilityValue("\(child.dailyReviewLimit)")
            } header: {
                Text("Daily limits")
            } footer: {
                Text("Caps the daily session so there's never a backlog. Reviews come first, then new cards.")
            }

            Section("Decks") {
                NavigationLink {
                    AssignDecksView(
                        model: AssignDecksViewModel(childID: child.id,
                                                    childName: child.displayName)
                    )
                } label: {
                    Label("Assigned decks", systemImage: "rectangle.stack")
                }
            }

            Section {
                Picker("Pacing", selection: $child.pacingProfile) {
                    ForEach(PacingProfile.allCases, id: \.self) { profile in
                        Text(profile.rawValue.capitalized).tag(profile)
                    }
                }
                let params = SchedulerParameters.defaults(for: child.pacingProfile)
                LabeledContent("Preset",
                               value: "\(params.newCardsPerDay) new/day · ≤\(Int(params.maxIntervalDays))d")
                    .foregroundStyle(.secondary)
                    .font(.footnote)
            } header: {
                Text("Pacing")
            } footer: {
                Text("Gentle, normal or fast tunes how quickly cards space out.")
            }

            Section {
                Toggle("Dyslexia-friendly text", isOn: $child.dyslexiaMode)
                Toggle("Read aloud", isOn: $child.readAloud)
                Toggle("Reduce motion", isOn: $child.reduceMotion)
            } header: {
                Text("Accessibility")
            } footer: {
                Text("Per-child supports for struggling readers and motion sensitivity.")
            }

            Section {
                Toggle("Daily study reminder", isOn: $child.reminderEnabled)
                if child.reminderEnabled {
                    DatePicker("Time", selection: reminderTime, displayedComponents: .hourAndMinute)
                }
            } header: {
                Text("Reminders")
            } footer: {
                Text("Off by default. A gentle daily nudge on this device — no streaks, no pressure.")
            }
        }
        .formStyle(.grouped)
        .navigationTitle(child.displayName.isEmpty ? "Child" : child.displayName)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        // Persist any change live. `ChildSummary` is Equatable, so this fires on
        // every edited field.
        .onChange(of: child) { _, updated in
            model.updateChild(updated)
        }
    }
}

#Preview {
    let model = ChildrenViewModel.sample()
    return NavigationStack {
        ChildDetailView(child: model.children.first
                        ?? ChildSummary(id: UUID(), displayName: "Mia",
                                        dailyNewCardLimit: 5, dailyReviewLimit: 40,
                                        pacingProfile: .normal,
                                        dyslexiaMode: false, readAloud: false, reduceMotion: false),
                        model: model)
    }
}
