//NEW DOC  SettingsStore.swift
import Combine
import Foundation
import SwiftUI

enum AppLanguage: String, CaseIterable, Identifiable, Codable {
    case english
    case dutch

    var id: String { rawValue }

    var localeIdentifier: String {
        switch self {
        case .english: return "en_US"
        case .dutch: return "nl_NL"
        }
    }

    var displayName: String {
        switch self {
        case .english: return "English"
        case .dutch: return "Nederlands"
        }
    }
}

struct ReminderTime: Codable, Equatable {
    var hour: Int
    var minute: Int

    static func from(date: Date, calendar: Calendar = .current) -> ReminderTime {
        let comps = calendar.dateComponents([.hour, .minute], from: date)
        return ReminderTime(hour: comps.hour ?? 9, minute: comps.minute ?? 0)
    }

    func asDateComponents() -> DateComponents {
        var c = DateComponents()
        c.hour = hour
        c.minute = minute
        return c
    }

    func displayString(locale: Locale) -> String {
        var comps = DateComponents()
        comps.hour = hour
        comps.minute = minute
        let cal = Calendar.current
        let date = cal.date(from: comps) ?? Date()
        let f = DateFormatter()
        f.locale = locale
        f.timeStyle = .short
        f.dateStyle = .none
        return f.string(from: date)
    }
}

@MainActor
final class SettingsStore: ObservableObject {
    @AppStorage("dailyItemCount") var dailyItemCount: Int = 5

    @AppStorage("languageRaw") private var languageRaw: String = AppLanguage.dutch.rawValue
    var language: AppLanguage {
        get { AppLanguage(rawValue: languageRaw) ?? .dutch }
        set { languageRaw = newValue.rawValue; objectWillChange.send() }
    }

    @AppStorage("moonEnabled") var moonEnabled: Bool = false

    // Optional reminders stored as JSON Data in AppStorage
    @AppStorage("dailyReminderData") private var dailyReminderData: Data = Data()
    @AppStorage("nextDayReminderData") private var nextDayReminderData: Data = Data()

    var dailyReminderTime: ReminderTime? {
        get { decode(ReminderTime.self, from: dailyReminderData) }
        set { dailyReminderData = encode(newValue); objectWillChange.send() }
    }

    var nextDayReminderTime: ReminderTime? {
        get { decode(ReminderTime.self, from: nextDayReminderData) }
        set { nextDayReminderData = encode(newValue); objectWillChange.send() }
    }

    var locale: Locale { Locale(identifier: language.localeIdentifier) }

    func clampDailyCount() {
        dailyItemCount = max(3, min(10, dailyItemCount))
    }

    private func encode<T: Encodable>(_ value: T?) -> Data {
        guard let value else { return Data() }
        do { return try JSONEncoder().encode(value) } catch { return Data() }
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) -> T? {
        guard !data.isEmpty else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}
