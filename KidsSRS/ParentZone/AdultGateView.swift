import SwiftUI

/// Friction gate that keeps kids out of the parent zone (Spec §8.1).
///
/// Tries biometric unlock first when the parent has enabled it, then falls back
/// to the configured manual challenge — a parent-set passcode if there is one,
/// otherwise a generated arithmetic problem. This is a keep-kids-out gate, NOT a
/// security boundary.
struct AdultGateView: View {
    let onPass: () -> Void
    private let store: AdultGateStore
    private let authenticator: BiometricAuthenticating

    @State private var entry = ""
    @State private var wrong = false
    @State private var a = Int.random(in: 3...9)
    @State private var b = Int.random(in: 3...9)
    @State private var didAttemptBiometric = false

    init(onPass: @escaping () -> Void,
         store: AdultGateStore = AdultGateStore(),
         authenticator: BiometricAuthenticating = SystemBiometricAuthenticator()) {
        self.onPass = onPass
        self.store = store
        self.authenticator = authenticator
    }

    private var showBiometric: Bool {
        store.biometricEnabled && authenticator.biometryType.isAvailable
    }
    private var usePasscode: Bool {
        store.method == .passcode && store.hasPasscode
    }

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "lock.fill").font(.largeTitle)
            Text("Ask a grown-up").font(.title2.bold())

            if showBiometric {
                Button { attemptBiometric() } label: {
                    Label("Use \(authenticator.biometryType.label)",
                          systemImage: authenticator.biometryType.systemImage)
                }
                .buttonStyle(.borderedProminent)
                Text("or").font(.footnote).foregroundStyle(.secondary)
            }

            Text(usePasscode ? "Enter the parent passcode" : "What is \(a) × \(b)?")
                .font(.title3)

            challengeField

            if wrong {
                Text("Try again").foregroundStyle(.red).font(.footnote)
            }

            Button("Enter") { check() }
                .buttonStyle(.bordered)
        }
        .padding()
        .task {
            // Auto-prompt biometrics once when entering (standard lock-screen UX).
            guard showBiometric, !didAttemptBiometric else { return }
            didAttemptBiometric = true
            attemptBiometric()
        }
    }

    @ViewBuilder
    private var challengeField: some View {
        Group {
            if usePasscode {
                SecureField("Passcode", text: $entry)
                    .accessibilityLabel("Parent passcode")
            } else {
                TextField("Answer", text: $entry)
                    .accessibilityLabel("Answer")
            }
        }
        #if os(iOS)
        .keyboardType(.numberPad)
        #endif
        .textFieldStyle(.roundedBorder)
        .frame(width: 200)
        .multilineTextAlignment(.center)
        .onSubmit { check() }
    }

    private func attemptBiometric() {
        Task {
            if await authenticator.authenticate(reason: "Unlock the parent area") {
                onPass()
            }
        }
    }

    private func check() {
        let ok = usePasscode ? store.verifyPasscode(entry) : (Int(entry) == a * b)
        if ok {
            onPass()
        } else {
            wrong = true
            entry = ""
            if !usePasscode {
                a = Int.random(in: 3...9)
                b = Int.random(in: 3...9)
            }
        }
    }
}

#Preview("Math") {
    AdultGateView(onPass: {},
                  store: AdultGateStore(defaults: UserDefaults(suiteName: "preview-math")!),
                  authenticator: UnavailableBiometricAuthenticator())
}
