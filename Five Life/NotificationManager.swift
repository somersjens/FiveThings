//NEW DOC  NotificationManager.swift
import Combine
import Foundation
import UserNotifications

enum NotificationIDs {
    static let daily = "daily_positive_things"
    static let nextDay = "next_day_if_needed"
}

@MainActor
final class NotificationManager: ObservableObject {
    static let shared = NotificationManager()

    @Published var authorizationStatus: UNAuthorizationStatus = .notDetermined
    private let notificationSound = UNNotificationSound(named: UNNotificationSoundName("Pling.wav"))

    private init() { }

    func refreshAuthorizationStatus() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        authorizationStatus = settings.authorizationStatus
    }

    func requestAuthorizationIfNeeded() async -> Bool {
        await refreshAuthorizationStatus()
        switch authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            return false
        case .notDetermined:
            do {
                let ok = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
                await refreshAuthorizationStatus()
                return ok
            } catch {
                await refreshAuthorizationStatus()
                return false
            }
        @unknown default:
            return false
        }
    }

    func scheduleDailyReminder(time: ReminderTime?, language: AppLanguage, dailyCount: Int) async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [NotificationIDs.daily])

        guard let time else { return }
        let allowed = await requestAuthorizationIfNeeded()
        guard allowed else { return }

        let content = UNMutableNotificationContent()
        content.title = L10n.string("notifications.daily.title", language: language)
        let timeString = reminderTimeString(for: time)
        let clampedCount = max(1, dailyCount)
        content.body = L10n.string("notifications.daily.body",
                                   language: language,
                                   timeString,
                                   clampedCount)
        content.sound = notificationSound

        var triggerComps = time.asDateComponents()
        triggerComps.calendar = .current
        let trigger = UNCalendarNotificationTrigger(dateMatching: triggerComps, repeats: true)

        let req = UNNotificationRequest(identifier: NotificationIDs.daily, content: content, trigger: trigger)
        try? await center.add(req)
    }

    /// Schedules a daily reminder for “next day if needed” (we refresh this from the app when state changes).
    func scheduleNextDayIfNeeded(time: ReminderTime?, shouldSchedule: Bool, language: AppLanguage) async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [NotificationIDs.nextDay])

        guard let time, shouldSchedule else { return }
        let allowed = await requestAuthorizationIfNeeded()
        guard allowed else { return }

        let content = UNMutableNotificationContent()
        content.title = L10n.string("notifications.next.title", language: language)
        let timeString = reminderTimeString(for: time)
        content.body = L10n.string("notifications.next.body", language: language, timeString)
        content.sound = notificationSound

        var triggerComps = time.asDateComponents()
        triggerComps.calendar = .current
        let trigger = UNCalendarNotificationTrigger(dateMatching: triggerComps, repeats: true)

        let req = UNNotificationRequest(identifier: NotificationIDs.nextDay, content: content, trigger: trigger)
        try? await center.add(req)
    }

    private func reminderTimeString(for time: ReminderTime) -> String {
        var comps = DateComponents()
        comps.hour = time.hour
        comps.minute = time.minute
        let calendar = Calendar.current
        let date = calendar.date(from: comps) ?? Date()
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "H:mm"
        return formatter.string(from: date)
    }
}
