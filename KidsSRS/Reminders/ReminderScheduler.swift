import Foundation
import UserNotifications

/// A single daily local reminder to schedule (Spec §10.4).
struct PlannedReminder: Equatable {
    let identifier: String
    let childID: UUID
    let hour: Int
    let minute: Int
    let title: String
    let body: String
}

/// Pure planning: turn child settings into the reminders that should exist.
/// Deliberately UI-/system-free so it's fully unit-testable; the side-effecting
/// `UNUserNotificationCenter` work lives in `LocalReminderScheduler`.
enum ReminderPlanner {
    static let identifierPrefix = "study-reminder-"

    static func identifier(for childID: UUID) -> String {
        "\(identifierPrefix)\(childID.uuidString)"
    }

    /// One reminder per child who has reminders enabled (Spec §10.4: off by
    /// default, parent-enabled). Tone is gentle — never guilt-inducing (§1.5).
    static func plannedReminders(for children: [ChildSummary]) -> [PlannedReminder] {
        children
            .filter(\.reminderEnabled)
            .map { child in
                let name = child.displayName.isEmpty ? "you" : child.displayName
                return PlannedReminder(
                    identifier: identifier(for: child.id),
                    childID: child.id,
                    hour: child.reminderHour,
                    minute: child.reminderMinute,
                    title: "Time to study! 🌟",
                    body: "A few cards are ready when \(name) is."
                )
            }
    }
}

/// Applies a reminder plan to the system (Spec §10.4). Abstracted so views/tests
/// can substitute a no-op.
protocol ReminderScheduling {
    /// Reconcile scheduled reminders to match the children's current settings.
    func reconcile(children: [ChildSummary]) async
}

/// No-op scheduler for previews and tests (keeps `UNUserNotificationCenter` out
/// of non-app contexts).
struct NoopReminderScheduler: ReminderScheduling {
    func reconcile(children: [ChildSummary]) async {}
}

/// The real scheduler over `UNUserNotificationCenter`. Local notifications only
/// — no push server (Spec §10.4). This is thin system glue; the decision logic
/// it applies lives in the unit-tested `ReminderPlanner`.
final class LocalReminderScheduler: ReminderScheduling {
    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    func reconcile(children: [ChildSummary]) async {
        let planned = ReminderPlanner.plannedReminders(for: children)

        // Always clear our previously-scheduled reminders so disables/edits take
        // effect; only the still-enabled ones are re-added below.
        let pending = await center.pendingNotificationRequests()
        let ours = pending.map(\.identifier)
            .filter { $0.hasPrefix(ReminderPlanner.identifierPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: ours)

        guard !planned.isEmpty else { return }
        guard await requestAuthorization() else { return }

        for reminder in planned {
            var components = DateComponents()
            components.hour = reminder.hour
            components.minute = reminder.minute

            let content = UNMutableNotificationContent()
            content.title = reminder.title
            content.body = reminder.body
            content.sound = .default

            let request = UNNotificationRequest(
                identifier: reminder.identifier,
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
            )
            try? await center.add(request)
        }
    }

    /// Request alert/sound authorization once; subsequent calls don't re-prompt.
    private func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    }
}
