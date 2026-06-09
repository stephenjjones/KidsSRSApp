import Foundation

/// Where the family stands on video consent (Spec §14.1).
enum VideoConsentStatus: Equatable {
    case notRequested
    case granted(Date)
    case revoked
}

/// Records whether a parent has consented to loading YouTube video (Spec §14.1).
///
/// COPPA requires **verifiable parental consent (VPC) before any video loads** —
/// and the §8.1 adult gate is explicitly *not* VPC. This store is the single
/// source of truth the video chokepoint (`SongReviewView`) checks; it persists
/// the decision (with a timestamp) and supports revocation.
///
/// > ⚠️ LEGAL: the *act* of granting (see `VideoConsentView`) is an interim
/// > informed-acknowledgment, **not** a legally-sufficient VPC mechanism. The
/// > enforcement here is real; the verification method must be replaced with a
/// > legally-approved one (and signed off) before release.
final class VideoConsentStore: ObservableObject {
    @Published private(set) var status: VideoConsentStatus

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if defaults.bool(forKey: Key.granted),
           let date = defaults.object(forKey: Key.grantedAt) as? Date {
            status = .granted(date)
        } else if defaults.bool(forKey: Key.revoked) {
            status = .revoked
        } else {
            status = .notRequested
        }
    }

    /// The one check the video chokepoint relies on.
    var isGranted: Bool {
        if case .granted = status { return true }
        return false
    }

    var grantedAt: Date? {
        if case .granted(let date) = status { return date }
        return nil
    }

    /// Record consent. See the type-level LEGAL note — the verification rigor
    /// behind this call is what must be upgraded before launch, not the storage.
    func grant() {
        let now = Date()
        defaults.set(true, forKey: Key.granted)
        defaults.set(now, forKey: Key.grantedAt)
        defaults.set(false, forKey: Key.revoked)
        status = .granted(now)
    }

    /// Withdraw consent. Video is blocked again until re-granted (§14.1).
    func revoke() {
        defaults.set(false, forKey: Key.granted)
        defaults.removeObject(forKey: Key.grantedAt)
        defaults.set(true, forKey: Key.revoked)
        status = .revoked
    }

    private enum Key {
        static let granted = "videoConsent.granted"
        static let grantedAt = "videoConsent.grantedAt"
        static let revoked = "videoConsent.revoked"
    }
}
