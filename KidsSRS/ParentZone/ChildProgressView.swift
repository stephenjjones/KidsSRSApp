import SwiftUI
import KidsSRSCore

/// Read-only per-child progress (Spec §8.4): overview stats, cards-by-state,
/// an accuracy trend, and a "needs practice" list. Reached from the parent
/// dashboard's Progress section.
struct ChildProgressView: View {
    @StateObject private var model: ChildProgressViewModel

    init(model: ChildProgressViewModel) {
        _model = StateObject(wrappedValue: model)
    }

    var body: some View {
        Group {
            if let progress = model.progress {
                if progress.isEmpty {
                    emptyState
                } else {
                    content(progress)
                }
            } else {
                ProgressView()
            }
        }
        .navigationTitle(model.childName.isEmpty ? "Progress" : "\(model.childName)'s progress")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .alert("Something went wrong",
               isPresented: errorPresented,
               presenting: model.errorMessage) { _ in
            Button("OK") { model.errorMessage = nil }
        } message: { Text($0) }
        .task { model.load() }
    }

    // MARK: Sections

    private func content(_ p: ChildProgress) -> some View {
        List {
            Section("Overview") {
                statRow("Accuracy", value: Self.percent(p.totalAccuracy),
                        systemImage: "target")
                statRow("Time studied", value: Self.duration(p.totalStudyTime),
                        systemImage: "clock")
                statRow("Day streak", value: "\(p.streakDays)",
                        systemImage: "flame")
                statRow("Sessions", value: "\(p.sessionCount)",
                        systemImage: "checkmark.circle")
            }

            Section("Cards") {
                statRow("New", value: "\(p.newCount)", systemImage: "sparkles")
                statRow("Learning", value: "\(p.learningCount)", systemImage: "hare")
                statRow("Reviewing", value: "\(p.reviewCount)", systemImage: "checkmark.seal")
            }

            if !p.recentAccuracy.isEmpty {
                Section("Recent accuracy") {
                    ForEach(p.recentAccuracy) { day in
                        ProgressView(value: day.accuracy) {
                            Text(Self.dayLabel(day.day))
                                .font(.subheadline)
                        } currentValueLabel: {
                            Text("\(Self.percent(day.accuracy)) · \(day.correct)/\(day.seen)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("\(Self.dayLabel(day.day)): "
                                            + "\(day.correct) of \(day.seen) correct")
                    }
                }
            }

            Section {
                if p.strugglingCards.isEmpty {
                    Text("No tricky cards yet — nice work!")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(p.strugglingCards) { card in
                        StrugglingRow(card: card)
                    }
                }
            } header: {
                Text("Needs practice")
            } footer: {
                Text("Cards with repeated misses or over-confidence — good ones to re-teach together.")
            }
        }
    }

    private func statRow(_ title: String, value: String, systemImage: String) -> some View {
        LabeledContent {
            Text(value).font(.body.weight(.semibold))
        } label: {
            Label(title, systemImage: systemImage)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(value)")
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No study data yet", systemImage: "chart.bar")
        } description: {
            Text("Progress appears here after \(model.childName) studies their assigned decks.")
        }
    }

    private var errorPresented: Binding<Bool> {
        Binding(get: { model.errorMessage != nil },
                set: { if !$0 { model.errorMessage = nil } })
    }

    // MARK: Formatting

    private static func percent(_ value: Double?) -> String {
        guard let value else { return "—" }
        return "\(Int((value * 100).rounded()))%"
    }

    private static func duration(_ seconds: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = seconds >= 3600 ? [.hour, .minute] : [.minute, .second]
        formatter.unitsStyle = .abbreviated
        formatter.zeroFormattingBehavior = .dropLeading
        return formatter.string(from: max(0, seconds)) ?? "0m"
    }

    private static func dayLabel(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }
}

/// One "needs practice" row — never relies on color alone (Spec §11).
private struct StrugglingRow: View {
    let card: StrugglingCard

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(card.front.isEmpty ? "—" : card.front)
                .font(.headline)
                .lineLimit(2)
            HStack(spacing: 12) {
                if card.lapses > 0 {
                    Label("\(card.lapses) \(card.lapses == 1 ? "miss" : "misses")",
                          systemImage: "arrow.counterclockwise")
                }
                if card.overConfident {
                    Label("Over-confident", systemImage: "exclamationmark.bubble")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        var parts = [card.front.isEmpty ? "Card" : card.front]
        if card.lapses > 0 { parts.append("\(card.lapses) misses") }
        if card.overConfident { parts.append("over-confident") }
        return parts.joined(separator: ", ")
    }
}

/// Drives the per-child progress screen (Spec §8.4). Read-only — fetches a
/// `ChildProgress` value through `DashboardRepository`; no `NSManagedObject`
/// reaches the view (§4.1).
@MainActor
final class ChildProgressViewModel: ObservableObject {
    @Published private(set) var progress: ChildProgress?
    @Published var errorMessage: String?

    let childName: String
    private let childID: UUID
    private let repository: DashboardRepository
    private let clock: () -> Date

    init(childID: UUID, childName: String,
         repository: DashboardRepository = DashboardRepository(),
         clock: @escaping () -> Date = Date.init) {
        self.childID = childID
        self.childName = childName
        self.repository = repository
        self.clock = clock
    }

    func load() {
        do { progress = try repository.progress(forChild: childID, now: clock()) }
        catch { errorMessage = error.localizedDescription }
    }

    /// Preview factory: an in-memory store seeded with sessions + card states.
    static func sample() -> ChildProgressViewModel {
        let context = PersistenceController(inMemory: true).container.viewContext
        let children = ChildRepository(context: context)
        let decks = DeckRepository(context: context)
        let study = StudyRepository(context: context)
        let now = Date()

        guard let child = try? children.createChild(name: "Mia"),
              let deck = try? decks.createDeck(title: "Spanish — Animals") else {
            return ChildProgressViewModel(childID: UUID(), childName: "Mia",
                                          repository: DashboardRepository(context: context))
        }

        let cat = try? decks.addCard(to: deck.id, front: "el gato", back: "the cat", hint: nil)
        let dog = try? decks.addCard(to: deck.id, front: "el perro", back: "the dog", hint: nil)
        let bird = try? decks.addCard(to: deck.id, front: "el pájaro", back: "the bird", hint: nil)
        _ = try? decks.addCard(to: deck.id, front: "el ratón", back: "the mouse", hint: nil)
        try? decks.setDeck(deck.id, assigned: true, toChild: child.id)

        if let cat {
            try? study.saveState(forChild: child.id, cardID: cat.id,
                                 state: SchedulerState(status: .review, intervalDays: 6,
                                                       repetitions: 2,
                                                       dueDate: now.addingTimeInterval(6 * 86_400),
                                                       lastReviewedAt: now))
        }
        if let dog {
            try? study.saveState(forChild: child.id, cardID: dog.id,
                                 state: SchedulerState(status: .learning, learningStepIndex: 1,
                                                       dueDate: now, lastReviewedAt: now))
        }
        if let bird {
            try? study.saveState(forChild: child.id, cardID: bird.id,
                                 state: SchedulerState(status: .review, intervalDays: 1,
                                                       repetitions: 1, lapses: 3, dueDate: now,
                                                       lastReviewedAt: now,
                                                       lastConfidenceFlag: .overConfident))
        }

        let yesterday = now.addingTimeInterval(-86_400)
        try? study.recordSession(forChild: child.id, startedAt: now.addingTimeInterval(-300),
                                 endedAt: now, cardsSeen: 3, cardsCorrect: 2, newIntroduced: 3)
        try? study.recordSession(forChild: child.id, startedAt: yesterday,
                                 endedAt: yesterday.addingTimeInterval(360),
                                 cardsSeen: 4, cardsCorrect: 4, newIntroduced: 0)

        let model = ChildProgressViewModel(childID: child.id, childName: "Mia",
                                           repository: DashboardRepository(context: context))
        model.load()
        return model
    }
}

#Preview("With data") {
    NavigationStack {
        ChildProgressView(model: .sample())
    }
}

#Preview("Empty") {
    NavigationStack {
        ChildProgressView(
            model: ChildProgressViewModel(
                childID: UUID(), childName: "Mia",
                repository: DashboardRepository(persistence: PersistenceController(inMemory: true))
            )
        )
    }
}
