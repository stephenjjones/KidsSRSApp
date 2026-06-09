import Foundation
import Combine

/// Lightweight app-wide navigation/state. Spec §6.1 routes.
@MainActor
final class AppState: ObservableObject {
    enum Route: Equatable {
        case profilePicker
        case studying(childID: UUID)
        case parentZone
    }

    @Published var route: Route = .profilePicker

    func startStudying(childID: UUID) { route = .studying(childID: childID) }
    func backToProfiles() { route = .profilePicker }
    func enterParentZone() { route = .parentZone }
}
