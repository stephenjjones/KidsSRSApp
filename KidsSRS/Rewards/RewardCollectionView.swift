import SwiftUI
import KidsSRSCore

/// Renders a reward item as an avatar visual. **This + `RewardCatalog` are the
/// only places to change when the real themed collectibles replace the current
/// SF-Symbol placeholders** (Spec §9.3) — everything else references items by id.
struct RewardItemAvatar: View {
    let item: RewardItem
    var size: CGFloat = 56

    var body: some View {
        Image(systemName: item.symbol)
            .font(.system(size: size * 0.42))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Color.accentColor.gradient, in: Circle())
    }
}

/// A child's avatar: their equipped reward item if any, else the default face.
struct ChildAvatar: View {
    let child: ChildSummary
    var size: CGFloat = 120

    var body: some View {
        if let id = child.equippedItemID, let item = RewardCatalog.item(id: id) {
            RewardItemAvatar(item: item, size: size)
        } else {
            let face = ProfileFace(id: child.id)
            Image(systemName: face.symbol)
                .font(.system(size: size * 0.4))
                .foregroundStyle(.white)
                .frame(width: size, height: size)
                .background(face.color, in: Circle())
        }
    }
}

/// Drives the reward collection screen (Spec §9.3): which items are unlocked,
/// which is equipped, and equipping. Items come from `RewardCatalog` by id.
@MainActor
final class RewardCollectionViewModel: ObservableObject {
    let childID: UUID
    let childName: String
    /// The shipped ladder — swap in `RewardCatalog` when the real theme lands.
    let milestones = RewardCatalog.milestones

    @Published private(set) var unlockedIDs: Set<UUID> = []
    @Published private(set) var equippedID: UUID?
    @Published private(set) var sessionsCompleted = 0
    @Published var errorMessage: String?

    private let rewards: RewardRepository
    private let children: ChildRepository

    init(childID: UUID, childName: String,
         rewards: RewardRepository = RewardRepository(),
         children: ChildRepository = ChildRepository()) {
        self.childID = childID
        self.childName = childName
        self.rewards = rewards
        self.children = children
    }

    func load() {
        do {
            let summary = try rewards.summary(forChild: childID)
            unlockedIDs = Set(summary.unlockedItems.map(\.id))
            sessionsCompleted = summary.sessionsCompleted
            equippedID = try children.equippedReward(forChild: childID)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func isUnlocked(_ item: RewardItem) -> Bool { unlockedIDs.contains(item.id) }
    func isEquipped(_ item: RewardItem) -> Bool { equippedID == item.id }
    func sessionsUntil(_ milestone: RewardMilestone) -> Int {
        max(0, milestone.requiredSessions - sessionsCompleted)
    }

    /// Tap an unlocked item: equip it, or un-equip if it's already worn.
    func toggleEquip(_ item: RewardItem) {
        guard isUnlocked(item) else { return }
        let newValue: UUID? = isEquipped(item) ? nil : item.id
        do {
            try children.setEquippedReward(itemID: newValue, forChild: childID)
            equippedID = newValue
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    static func sample() -> RewardCollectionViewModel {
        let persistence = PersistenceController(inMemory: true)
        let children = ChildRepository(persistence: persistence)
        let rewards = RewardRepository(persistence: persistence)
        let id = (try? children.createChild(name: "Mia"))?.id ?? UUID()
        for _ in 0..<3 { _ = try? rewards.recordCompletedSession(forChild: id) } // unlock first two
        let model = RewardCollectionViewModel(childID: id, childName: "Mia",
                                              rewards: rewards, children: children)
        model.load()
        return model
    }
}

struct RewardCollectionView: View {
    @StateObject private var model: RewardCollectionViewModel
    @Environment(\.dismiss) private var dismiss
    private let columns = [GridItem(.adaptive(minimum: 110), spacing: 16)]

    init(model: RewardCollectionViewModel) {
        _model = StateObject(wrappedValue: model)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(model.milestones) { milestone in
                        cell(milestone)
                    }
                }
                .padding()
            }
            .navigationTitle("\(model.childName)'s rewards")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("Something went wrong",
                   isPresented: errorPresented,
                   presenting: model.errorMessage) { _ in
                Button("OK") { model.errorMessage = nil }
            } message: { message in
                Text(message)
            }
            .task { model.load() }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 460)
        #endif
    }

    @ViewBuilder
    private func cell(_ milestone: RewardMilestone) -> some View {
        let item = milestone.item
        let unlocked = model.isUnlocked(item)
        let equipped = model.isEquipped(item)
        Button {
            model.toggleEquip(item)
        } label: {
            VStack(spacing: 6) {
                RewardItemAvatar(item: item, size: 72)
                    .opacity(unlocked ? 1 : 0.25)
                    .overlay {
                        if !unlocked {
                            Image(systemName: "lock.fill")
                                .font(.title3)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .overlay(alignment: .topTrailing) {
                        if equipped {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .background(Color.white, in: Circle())
                        }
                    }
                Text(item.name)
                    .font(.caption)
                    .lineLimit(1)
                if !unlocked {
                    Text("Study \(model.sessionsUntil(milestone)) more")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    Text(equipped ? "Equipped" : "Tap to wear")
                        .font(.caption2)
                        .foregroundStyle(equipped ? .green : .secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
        .disabled(!unlocked)
        .accessibilityLabel(accessibility(item, milestone, unlocked: unlocked, equipped: equipped))
    }

    private func accessibility(_ item: RewardItem, _ milestone: RewardMilestone,
                               unlocked: Bool, equipped: Bool) -> String {
        if !unlocked { return "\(item.name), locked, study \(model.sessionsUntil(milestone)) more sessions" }
        return "\(item.name), \(equipped ? "equipped" : "unlocked, tap to wear")"
    }

    private var errorPresented: Binding<Bool> {
        Binding(get: { model.errorMessage != nil },
                set: { if !$0 { model.errorMessage = nil } })
    }
}

#Preview {
    RewardCollectionView(model: .sample())
}
