import XCTest
import KidsSRSCore
@testable import KidsSRS

/// Tests for the pure `ReminderPlanner` (Spec §10.4): only enabled children get
/// reminders, with stable identifiers and their chosen times.
final class ReminderPlannerTests: XCTestCase {

    private func child(_ name: String, enabled: Bool, hour: Int = 16, minute: Int = 0) -> ChildSummary {
        ChildSummary(id: UUID(), displayName: name,
                     dailyNewCardLimit: 5, dailyReviewLimit: 40, pacingProfile: .normal,
                     dyslexiaMode: false, readAloud: false, reduceMotion: false,
                     reminderEnabled: enabled, reminderHour: hour, reminderMinute: minute)
    }

    func testOnlyEnabledChildrenGetReminders() {
        let mia = child("Mia", enabled: true, hour: 17, minute: 30)
        let leo = child("Leo", enabled: false)

        let planned = ReminderPlanner.plannedReminders(for: [mia, leo])
        XCTAssertEqual(planned.count, 1)
        let reminder = try? XCTUnwrap(planned.first)
        XCTAssertEqual(reminder?.childID, mia.id)
        XCTAssertEqual(reminder?.hour, 17)
        XCTAssertEqual(reminder?.minute, 30)
        XCTAssertEqual(reminder?.identifier, ReminderPlanner.identifier(for: mia.id))
        XCTAssertTrue(reminder?.identifier.hasPrefix(ReminderPlanner.identifierPrefix) ?? false)
    }

    func testNoRemindersWhenAllDisabled() {
        let planned = ReminderPlanner.plannedReminders(for: [
            child("Mia", enabled: false),
            child("Leo", enabled: false),
        ])
        XCTAssertTrue(planned.isEmpty)
    }

    func testIdentifierIsStablePerChild() {
        let id = UUID()
        XCTAssertEqual(ReminderPlanner.identifier(for: id), ReminderPlanner.identifier(for: id))
        XCTAssertNotEqual(ReminderPlanner.identifier(for: id),
                          ReminderPlanner.identifier(for: UUID()))
    }

    func testBodyIsGentleAndNamePersonalized() {
        let planned = ReminderPlanner.plannedReminders(for: [child("Mia", enabled: true)])
        let reminder = planned.first
        XCTAssertEqual(reminder?.title, "Time to study! 🌟")
        XCTAssertTrue(reminder?.body.contains("Mia") ?? false)
        // No guilt / streak-loss language (Spec §1.5 / §10.4).
        let body = reminder?.body.lowercased() ?? ""
        XCTAssertFalse(body.contains("don't lose"))
        XCTAssertFalse(body.contains("streak"))
    }
}
