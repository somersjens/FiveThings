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

    func scheduleDailyReminder(time: ReminderTime?, language: AppLanguage) async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [NotificationIDs.daily])

        guard let time else { return }
        let allowed = await requestAuthorizationIfNeeded()
        guard allowed else { return }

        let content = UNMutableNotificationContent()
        content.title = (language == .dutch) ? "Dagelijkse reminder" : "Daily reminder"
        content.body = (language == .dutch) ? "Schrijf je positieve dingen van vandaag." : "Write your positive things for today."
        content.sound = .default

        var triggerComps = time.asDateComponents()
        triggerComps.calendar = .current
        let trigger = UNCalendarNotificationTrigger(dateMatching: triggerComps, repeats: true)

        let req = UNNotificationRequest(identifier: NotificationIDs.daily, content: content, trigger: trigger)
        try? await center.add(req)
    }

    /// Schedules a *one-off* reminder for “next day if needed” (we refresh this from the app when state changes).
    func scheduleNextDayIfNeeded(time: ReminderTime?, shouldSchedule: Bool, language: AppLanguage) async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [NotificationIDs.nextDay])

        guard let time, shouldSchedule else { return }
        let allowed = await requestAuthorizationIfNeeded()
        guard allowed else { return }

        let content = UNMutableNotificationContent()
        content.title = (language == .dutch) ? "Niet vergeten" : "Don’t forget"
        content.body = (language == .dutch)
            ? "Je hebt nog een onvoltooide dagkaart. Werk ’m af."
            : "You still have an unfinished day card. Finish it."
        content.sound = .default

        // Schedule for *tomorrow* at the chosen time
        let calendar = Calendar.current
        let now = Date()
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) else { return }
        let hm = DateComponents(hour: time.hour, minute: time.minute)
        let date = calendar.nextDate(after: tomorrow,
                                     matching: hm,
                                     matchingPolicy: .nextTimePreservingSmallerComponents) ?? tomorrow

        let comps = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)

        let req = UNNotificationRequest(identifier: NotificationIDs.nextDay, content: content, trigger: trigger)
        try? await center.add(req)
    }
}
