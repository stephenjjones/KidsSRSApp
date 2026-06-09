import Foundation
import CryptoKit
import LocalAuthentication

// MARK: - Configuration store

/// Stores the parent-zone gate configuration (Spec §8.1): which manual
/// challenge to use (math problem or a parent-set passcode) and whether to also
/// offer biometric unlock.
///
/// This is a **friction gate, not a security boundary** (§8.1), so the passcode
/// is kept as a salted SHA-256 hash in `UserDefaults` (a kid can't read it) —
/// proportionate to the threat, and avoids Keychain/entitlement friction across
/// iOS + macOS. It is never used to protect sensitive data.
final class AdultGateStore: ObservableObject {
    /// The manual fallback challenge.
    enum Method: String {
        case math      // generated arithmetic (the default)
        case passcode  // a parent-set numeric passcode
    }

    @Published private(set) var method: Method
    /// Whether to attempt Face ID / Touch ID before the manual challenge.
    @Published var biometricEnabled: Bool {
        didSet { defaults.set(biometricEnabled, forKey: Key.biometricEnabled) }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.method = Method(rawValue: defaults.string(forKey: Key.method) ?? "") ?? .math
        self.biometricEnabled = defaults.bool(forKey: Key.biometricEnabled)
    }

    /// A passcode is configured and in use.
    var hasPasscode: Bool {
        method == .passcode && defaults.string(forKey: Key.passcodeHash) != nil
    }

    /// Set (or change) the parent passcode and switch the gate to it.
    func setPasscode(_ code: String) {
        defaults.set(hash(code), forKey: Key.passcodeHash)
        defaults.set(Method.passcode.rawValue, forKey: Key.method)
        method = .passcode
    }

    /// Verify an entered passcode against the stored hash.
    func verifyPasscode(_ code: String) -> Bool {
        guard let stored = defaults.string(forKey: Key.passcodeHash) else { return false }
        return hash(code) == stored
    }

    /// Remove the passcode and fall back to the math challenge.
    func removePasscode() {
        defaults.removeObject(forKey: Key.passcodeHash)
        defaults.set(Method.math.rawValue, forKey: Key.method)
        method = .math
    }

    // MARK: Hashing

    private func hash(_ code: String) -> String {
        let digest = SHA256.hash(data: Data((salt + code).utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// A per-install random salt, generated once and reused.
    private var salt: String {
        if let existing = defaults.string(forKey: Key.salt) { return existing }
        let new = UUID().uuidString
        defaults.set(new, forKey: Key.salt)
        return new
    }

    private enum Key {
        static let method = "adultGate.method"
        static let biometricEnabled = "adultGate.biometricEnabled"
        static let passcodeHash = "adultGate.passcodeHash"
        static let salt = "adultGate.salt"
    }
}

// MARK: - Biometrics

/// The kind of biometric available, so the UI can label it correctly.
enum BiometryKind: Equatable {
    case none, faceID, touchID

    var label: String {
        switch self {
        case .none:    return "Biometrics"
        case .faceID:  return "Face ID"
        case .touchID: return "Touch ID"
        }
    }

    var systemImage: String {
        switch self {
        case .none:    return "lock.fill"
        case .faceID:  return "faceid"
        case .touchID: return "touchid"
        }
    }

    var isAvailable: Bool { self != .none }
}

/// Abstracts biometric unlock so views/tests can substitute a stub (the real
/// `LAContext` work isn't unit-testable here).
protocol BiometricAuthenticating {
    var biometryType: BiometryKind { get }
    func authenticate(reason: String) async -> Bool
}

/// The real authenticator over `LocalAuthentication` (Face ID / Touch ID).
/// Biometric-only policy — never falls back to the device passcode, which a
/// child on a shared device may know (Spec §8.1 keep-kids-out intent).
struct SystemBiometricAuthenticator: BiometricAuthenticating {
    var biometryType: BiometryKind {
        let context = LAContext()
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics,
                                        error: nil) else { return .none }
        switch context.biometryType {
        case .faceID:  return .faceID
        case .touchID: return .touchID
        default:       return .none
        }
    }

    func authenticate(reason: String) async -> Bool {
        let context = LAContext()
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics,
                                        error: nil) else { return false }
        return (try? await context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics,
                                                  localizedReason: reason)) ?? false
    }
}

/// No biometrics — for previews/tests.
struct UnavailableBiometricAuthenticator: BiometricAuthenticating {
    var biometryType: BiometryKind { .none }
    func authenticate(reason: String) async -> Bool { false }
}
