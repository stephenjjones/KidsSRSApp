import Foundation
import KidsSRSCore

/// Seeds the bundled starter decks (Spec §9.1) so first launch isn't empty.
///
/// Loads `StarterDecks.json` (the shared `DeckPack` format, §9.2) from the app
/// bundle and imports it idempotently via `DeckRepository` — safe to call on
/// every launch; existing decks are skipped.
struct StarterDeckImporter {
    static let resourceName = "StarterDecks"

    private let repository: DeckRepository
    private let bundle: Bundle

    init(repository: DeckRepository = DeckRepository(), bundle: Bundle = .main) {
        self.repository = repository
        self.bundle = bundle
    }

    /// Import any not-yet-present starter decks. Returns the number created.
    @discardableResult
    func importIfNeeded() throws -> Int {
        guard let url = bundle.url(forResource: Self.resourceName, withExtension: "json") else {
            return 0 // No bundled content — nothing to seed.
        }
        let data = try Data(contentsOf: url)
        let packs = try JSONDecoder().decode([DeckPack].self, from: data)
        return try repository.importBundled(packs)
    }
}
