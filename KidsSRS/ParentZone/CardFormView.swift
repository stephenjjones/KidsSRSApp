import SwiftUI
import PhotosUI
import KidsSRSCore

/// What the card form is editing: a brand-new card or an existing one.
/// `Identifiable` so it can drive a `.sheet(item:)`.
enum CardEditTarget: Identifiable {
    case new
    case existing(CardDraft)

    var id: String {
        switch self {
        case .new: return "new"
        case .existing(let card): return card.id.uuidString
        }
    }
}

/// The values produced when the parent saves a card (Spec §8.3 / §5 / §14.2).
struct CardEdits {
    var front: String
    var back: String
    var hint: String
    var tags: [String]
    var frontImage: Data?
    var backImage: Data?
}

/// The add/edit card form (Spec §8.3). Each side can carry **text and/or an
/// image** (Spec §6.3 / §5); Save is enabled once each side has text or an image.
/// Imported images are downsized (`ImageDownsizer`, §5). Presented as a sheet.
struct CardFormView: View {
    let target: CardEditTarget
    /// All existing category names, shown as toggleable chips.
    let allTags: [String]
    /// Called with the entered values when the parent taps Save.
    let onSave: (CardEdits) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var front: String
    @State private var back: String
    @State private var hint: String
    @State private var selectedTags: Set<String>
    @State private var newTag: String = ""
    @State private var frontImage: Data?
    @State private var backImage: Data?
    @State private var frontPickerItem: PhotosPickerItem?
    @State private var backPickerItem: PhotosPickerItem?

    init(target: CardEditTarget,
         allTags: [String] = [],
         onSave: @escaping (CardEdits) -> Void) {
        self.target = target
        self.allTags = allTags
        self.onSave = onSave
        switch target {
        case .new:
            _front = State(initialValue: "")
            _back = State(initialValue: "")
            _hint = State(initialValue: "")
            _selectedTags = State(initialValue: [])
            _frontImage = State(initialValue: nil)
            _backImage = State(initialValue: nil)
        case .existing(let card):
            _front = State(initialValue: card.front)
            _back = State(initialValue: card.back)
            _hint = State(initialValue: card.hint ?? "")
            _selectedTags = State(initialValue: Set(card.tags))
            _frontImage = State(initialValue: card.frontImage)
            _backImage = State(initialValue: card.backImage)
        }
    }

    private var isValid: Bool {
        let frontText = front.trimmingCharacters(in: .whitespacesAndNewlines)
        let backText = back.trimmingCharacters(in: .whitespacesAndNewlines)
        return (!frontText.isEmpty || frontImage != nil)
            && (!backText.isEmpty || backImage != nil)
    }

    private var navigationTitleText: String {
        switch target {
        case .new: return "Add card"
        case .existing: return "Edit card"
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Question or prompt", text: $front, axis: .vertical)
                        .lineLimit(1...4)
                        .accessibilityLabel("Front text")
                    imageRow(image: $frontImage, item: $frontPickerItem, side: "Front")
                } header: {
                    Text("Front")
                } footer: {
                    Text("Add text, an image, or both.")
                }

                Section {
                    TextField("Answer", text: $back, axis: .vertical)
                        .lineLimit(1...4)
                        .accessibilityLabel("Back text")
                    imageRow(image: $backImage, item: $backPickerItem, side: "Back")
                } header: {
                    Text("Back")
                } footer: {
                    Text("Add text, an image, or both.")
                }

                Section {
                    TextField("Optional hint", text: $hint, axis: .vertical)
                        .lineLimit(1...3)
                        .accessibilityLabel("Hint, optional")
                } header: {
                    Text("Hint")
                } footer: {
                    Text("Shown to your child if they get stuck. Optional.")
                }

                categoriesSection
            }
            .formStyle(.grouped)
            .navigationTitle(navigationTitleText)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(CardEdits(front: front, back: back, hint: hint,
                                         tags: Array(selectedTags),
                                         frontImage: frontImage, backImage: backImage))
                        dismiss()
                    }
                    .disabled(!isValid)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 420)
        #endif
    }

    // MARK: Images (Spec §5)

    @ViewBuilder
    private func imageRow(image: Binding<Data?>, item: Binding<PhotosPickerItem?>, side: String) -> some View {
        if let data = image.wrappedValue, let preview = Image(cardImageData: data) {
            preview
                .resizable()
                .scaledToFit()
                .frame(maxHeight: 160)
                .frame(maxWidth: .infinity)
                .accessibilityLabel("\(side) image")
        }
        HStack {
            PhotosPicker(selection: item, matching: .images) {
                Label(image.wrappedValue == nil ? "Add image" : "Change image", systemImage: "photo")
            }
            if image.wrappedValue != nil {
                Spacer()
                Button("Remove", role: .destructive) {
                    image.wrappedValue = nil
                    item.wrappedValue = nil
                }
            }
        }
        .onChange(of: item.wrappedValue) { _, newItem in
            loadImage(newItem, into: image)
        }
    }

    /// Load the picked image, downsize it (Spec §5), and store the JPEG data.
    private func loadImage(_ item: PhotosPickerItem?, into binding: Binding<Data?>) {
        guard let item else { return }
        Task {
            guard let raw = try? await item.loadTransferable(type: Data.self),
                  let small = ImageDownsizer.downsized(raw) else { return }
            await MainActor.run { binding.wrappedValue = small }
        }
    }

    // MARK: Categories (Spec §14.2)

    /// Chips to show: existing tags ∪ currently selected (incl. just-added).
    private var displayedTags: [String] {
        Set(allTags).union(selectedTags)
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private var trimmedNewTag: String {
        newTag.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @ViewBuilder private var categoriesSection: some View {
        Section {
            if !displayedTags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(displayedTags, id: \.self) { tag in
                            let isOn = selectedTags.contains(tag)
                            Button { toggle(tag) } label: {
                                Label(tag, systemImage: isOn ? "checkmark.circle.fill" : "circle")
                            }
                            .buttonStyle(.bordered)
                            .tint(isOn ? .accentColor : .secondary)
                            .accessibilityLabel("\(tag), \(isOn ? "selected" : "not selected")")
                            .accessibilityAddTraits(isOn ? [.isSelected] : [])
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
            HStack {
                TextField("New category", text: $newTag)
                    #if os(iOS)
                    .textInputAutocapitalization(.words)
                    #endif
                    .onSubmit(addNewTag)
                Button("Add", action: addNewTag)
                    .disabled(trimmedNewTag.isEmpty)
            }
        } header: {
            Text("Categories")
        } footer: {
            Text("Used by Game Mode to draw cards by category. Optional.")
        }
    }

    private func toggle(_ tag: String) {
        if selectedTags.contains(tag) {
            selectedTags.remove(tag)
        } else {
            selectedTags.insert(tag)
        }
    }

    private func addNewTag() {
        let trimmed = trimmedNewTag
        guard !trimmed.isEmpty else { return }
        // Reuse existing casing if the name already exists case-insensitively.
        let canonical = displayedTags.first { $0.caseInsensitiveCompare(trimmed) == .orderedSame } ?? trimmed
        selectedTags.insert(canonical)
        newTag = ""
    }
}

#Preview("Add") {
    CardFormView(target: .new, allTags: ["Spanish", "Animals", "Food"]) { _ in }
}

#Preview("Edit") {
    CardFormView(
        target: .existing(
            CardDraft(id: UUID(), front: "el gato", back: "the cat", hint: "a feline",
                      order: 0, tags: ["Spanish", "Animals"])
        ),
        allTags: ["Spanish", "Animals", "Food"]
    ) { _ in }
}
