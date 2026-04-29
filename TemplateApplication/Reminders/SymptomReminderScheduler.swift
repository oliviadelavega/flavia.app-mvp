//
// Flavia study app
//
// Local-notification scheduler for the daily symptom check-in nudge. iOS has
// no built-in "fire only if X hasn't happened" trigger, so we approximate it
// the way most habit-tracking apps do:
//
//   - schedule one non-repeating reminder per day at a fixed local time
//     (`reminderHour`) for the next `rollingWindowDays` days;
//   - on every relevant lifecycle event (app foregrounding, after granting
//     notification permission), top the window back up;
//   - when the user saves today's symptom log, cancel today's pending
//     reminder so they aren't pinged for work they already did.
//
// We use one identifier per calendar day (`symptom-reminder-YYYY-MM-DD`) so
// individual days can be cancelled without affecting future ones — a single
// repeating trigger wouldn't allow that. iOS caps pending notifications at
// 64 per app, so a 7-day window is comfortably within budget.
//
// This is a single-device approximation: a reminder scheduled on iPhone
// won't be cancelled by a check-in saved on iPad. If multi-device usage
// ever becomes a study requirement, swap this for server-driven push.
//

import Foundation
import OSLog
import Spezi
import UserNotifications


@MainActor
@Observable
final class SymptomReminderScheduler: Module, EnvironmentAccessible, DefaultInitializable {
    /// Local hour-of-day at which the reminder fires. 20 = 8 PM.
    static let reminderHour = 20
    /// How many days ahead we keep scheduled at any time.
    static let rollingWindowDays = 7
    /// Identifier prefix — one notification per `YYYY-MM-DD`.
    static let identifierPrefix = "symptom-reminder-"

    @ObservationIgnored private let logger = Logger(subsystem: "com.flavia.app", category: "SymptomReminder")
    @ObservationIgnored private let center = UNUserNotificationCenter.current()

    nonisolated init() {}

    static func reminderIdentifier(for date: Date) -> String {
        identifierPrefix + SymptomLogDate.documentID(for: date)
    }

    /// Schedules a reminder for each of the next `rollingWindowDays` days that doesn't
    /// already have one pending. Skips today if it's already past the reminder time.
    /// Safe to call repeatedly — it's a no-op for days that are already scheduled.
    func ensureRollingWindow() async {
        guard await isAuthorized() else {
            return
        }

        let pending = await center.pendingNotificationRequests()
        let pendingIDs = Set(pending.map(\.identifier))
        let calendar = Calendar.current
        let now = Date()

        for offset in 0..<Self.rollingWindowDays {
            guard let day = calendar.date(byAdding: .day, value: offset, to: now) else {
                continue
            }
            let identifier = Self.reminderIdentifier(for: day)
            if pendingIDs.contains(identifier) {
                continue
            }
            guard let fireDate = scheduledFireDate(for: day, calendar: calendar), fireDate > now else {
                continue
            }
            await schedule(identifier: identifier, fireDate: fireDate, calendar: calendar)
        }
    }

    /// Cancels today's pending reminder. Call after the user saves a symptom check-in.
    func cancelToday() {
        let identifier = Self.reminderIdentifier(for: Date())
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
    }

    /// Removes every reminder this module owns. Useful if the user revokes notification
    /// permission or wants to reset the schedule.
    func cancelAll() async {
        let pending = await center.pendingNotificationRequests()
        let ids = pending
            .map(\.identifier)
            .filter { $0.hasPrefix(Self.identifierPrefix) }
        if !ids.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: ids)
        }
    }

    private func scheduledFireDate(for date: Date, calendar: Calendar) -> Date? {
        var components = calendar.dateComponents([.year, .month, .day], from: date)
        components.hour = Self.reminderHour
        components.minute = 0
        return calendar.date(from: components)
    }

    private func schedule(identifier: String, fireDate: Date, calendar: Calendar) async {
        let content = UNMutableNotificationContent()
        content.title = String(localized: "Daily check-in")
        content.body = String(localized: "How was today? Tap to log your symptoms.")
        content.sound = .default

        let triggerComponents = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: triggerComponents, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

        do {
            try await center.add(request)
        } catch {
            logger.error("Failed to schedule \(identifier): \(error.localizedDescription)")
        }
    }

    private func isAuthorized() async -> Bool {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied, .notDetermined:
            return false
        @unknown default:
            return false
        }
    }
}
