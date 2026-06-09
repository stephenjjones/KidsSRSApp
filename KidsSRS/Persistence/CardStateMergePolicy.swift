import CoreData

/// Conflict resolution for cross-device sync (Spec §10.3).
///
/// Last-writer-wins is acceptable for most fields, but for `CardState` — the
/// scheduler's per-child progress — naïve LWW can **drop a completed review**:
/// whichever device happens to sync last wins, even if its review is older. This
/// policy resolves `CardState` conflicts in favor of the record with the most
/// recent `lastReviewedAt`, so a finished review on one family device is never
/// clobbered by a staler record from another. Every other entity falls back to
/// ordinary property-level trump.
///
/// Installed on the view context, this governs both local save conflicts and the
/// merge of CloudKit-imported changes.
final class CardStateMergePolicy: NSMergePolicy {

    init() {
        super.init(merge: .mergeByPropertyObjectTrumpMergePolicyType)
    }

    override func resolve(optimisticLockingConflicts conflicts: [NSMergeConflict]) throws {
        for conflict in conflicts {
            // The store's current values live in `persistedSnapshot` for a
            // store-vs-context conflict, or `cachedSnapshot` when the conflict is
            // against the coordinator's row cache (e.g. another context saved
            // first). Consult whichever is present.
            guard conflict.sourceObject.entity.name == "CardState",
                  let persisted = conflict.persistedSnapshot ?? conflict.cachedSnapshot
            else { continue }

            let source = conflict.sourceObject
            let sourceDate = source.value(forKey: "lastReviewedAt") as? Date
            let persistedDate = persisted["lastReviewedAt"] as? Date

            if Self.prefersPersisted(sourceLastReviewedAt: sourceDate,
                                     persistedLastReviewedAt: persistedDate) {
                // The store's review is newer — keep it. Overwrite our stale
                // attribute changes with the persisted values so the upcoming
                // property-trump merge writes the store's record back unchanged.
                for name in source.entity.attributesByName.keys {
                    let value = persisted[name]
                    source.setValue(value is NSNull ? nil : value, forKey: name)
                }
            }
            // Otherwise our record is newer-or-equal → property-trump keeps it.
        }
        try super.resolve(optimisticLockingConflicts: conflicts)
    }

    /// The core decision (Spec §10.3), factored out so it can be tested directly:
    /// prefer the persisted (store) record only when its review is strictly newer.
    /// A missing timestamp is treated as the distant past, so any real review wins.
    static func prefersPersisted(sourceLastReviewedAt source: Date?,
                                 persistedLastReviewedAt persisted: Date?) -> Bool {
        (persisted ?? .distantPast) > (source ?? .distantPast)
    }
}
