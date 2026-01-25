//NEW DOC  NotificationManager.swift
import Combine
import Foundation
import UserNotifications

enum NotificationIDs {
    static let daily = "daily_positive_things"
    static let nextDay = "next_day_if_needed"
}

private enum NotificationVariant: String {
    case daily
    case nextDay
}

@MainActor
final class NotificationManager: ObservableObject {
    static let shared = NotificationManager()

    @Published var authorizationStatus: UNAuthorizationStatus = .notDetermined
    private let notificationSound = UNNotificationSound(named: UNNotificationSoundName("Pling.wav"))
    private let notificationVariantCount = 10

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

        let variantIndex = nextVariantIndex(for: .daily, language: language)
        let content = UNMutableNotificationContent()
        content.title = L10n.string("notifications.daily.\(variantIndex).title", language: language)
        let timeString = reminderTimeString(for: time)
        let clampedCount = max(1, dailyCount)
        content.body = L10n.string("notifications.daily.\(variantIndex).body",
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

    /// Schedules a reminder for “next day if needed” (we refresh this from the app when state changes).
    func scheduleNextDayIfNeeded(time: ReminderTime?, reminderDate: Date?, language: AppLanguage) async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [NotificationIDs.nextDay])

        guard let time, let reminderDate else { return }
        let allowed = await requestAuthorizationIfNeeded()
        guard allowed else { return }

        let variantIndex = nextVariantIndex(for: .nextDay, language: language)
        let content = UNMutableNotificationContent()
        content.title = L10n.string("notifications.next.\(variantIndex).title", language: language)
        let timeString = reminderTimeString(for: time)
        content.body = L10n.string("notifications.next.\(variantIndex).body", language: language, timeString)
        content.sound = notificationSound

        var triggerComps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: reminderDate)
        triggerComps.calendar = .current
        let trigger = UNCalendarNotificationTrigger(dateMatching: triggerComps, repeats: false)

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

    private func nextVariantIndex(for variant: NotificationVariant, language: AppLanguage) -> Int {
        let defaults = UserDefaults.standard
        let key = "notificationVariants.\(variant.rawValue).\(language.rawValue)"
        var remaining = defaults.array(forKey: key) as? [Int] ?? []
        if remaining.isEmpty {
            remaining = Array(1...notificationVariantCount).shuffled()
        }
        let next = remaining.removeFirst()
        defaults.set(remaining, forKey: key)
        return next
    }
}
