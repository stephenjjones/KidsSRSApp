import SwiftUI

/// Parent-zone settings for the adult gate (Spec §8.1): choose a passcode
/// instead of the math problem, and optionally enable biometric unlock. Reached
/// from `ParentDashboardView` (already inside the gate).
struct AdultGateSettingsView: View {
    @StateObject private var store: AdultGateStore
    private let authenticator: BiometricAuthenticating

    @State private var showingPasscodeSheet = false

    init(store: AdultGateStore = AdultGateStore(),
         authenticator: BiometricAuthenticating = SystemBiometricAuthenticator()) {
        _store = StateObject(wrappedValue: store)
        self.authenticator = authenticator
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("Current",
                               value: store.hasPasscode ? "Passcode" : "Math problem")
                Button(store.hasPasscode ? "Change passcode" : "Set a passcode") {
                    showingPasscodeSheet = true
                }
                if store.hasPasscode {
                    Button("Remove passcode", role: .destructive) {
                        store.removePasscode()
                    }
                }
            } header: {
                Text("Unlock method")
            } footer: {
                Text("A passcode is quicker than the math problem, and only you know it — a good fit for a shared device.")
            }

            if authenticator.biometryType.isAvailable {
                Section {
                    Toggle("Unlock with \(authenticator.biometryType.label)",
                           isOn: $store.biometricEnabled)
                } header: {
                    Text("Biometrics")
                } footer: {
                    Text("On a shared device, \(authenticator.biometryType.label) only keeps kids out if they aren't enrolled in it. The \(store.hasPasscode ? "passcode" : "math problem") is always available as a fallback.")
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Lock & passcode")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .sheet(isPresented: $showingPasscodeSheet) {
            PasscodeSetupView { code in store.setPasscode(code) }
        }
    }
}

/// Set or change the parent passcode (enter + confirm). Numeric, 4+ digits.
private struct PasscodeSetupView: View {
    let onSet: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var code = ""
    @State private var confirm = ""

    private var isNumeric: Bool { !code.isEmpty && code.allSatisfy(\.isNumber) }
    private var isValid: Bool { code.count >= 4 && isNumeric && code == confirm }
    private var mismatch: Bool { !confirm.isEmpty && code != confirm }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Group {
                        SecureField("Passcode", text: $code)
                            .accessibilityLabel("New passcode")
                        SecureField("Confirm passcode", text: $confirm)
                            .accessibilityLabel("Confirm passcode")
                    }
                    #if os(iOS)
                    .keyboardType(.numberPad)
                    #endif
                } footer: {
                    if mismatch {
                        Text("Passcodes don't match.").foregroundStyle(.red)
                    } else {
                        Text("At least 4 digits. Choose something your child won't guess.")
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Set passcode")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSet(code)
                        dismiss()
                    }
                    .disabled(!isValid)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 360, minHeight: 240)
        #endif
    }
}

#Preview("Math default") {
    NavigationStack {
        AdultGateSettingsView(
            store: AdultGateStore(defaults: UserDefaults(suiteName: "preview-settings")!),
            authenticator: UnavailableBiometricAuthenticator()
        )
    }
}
