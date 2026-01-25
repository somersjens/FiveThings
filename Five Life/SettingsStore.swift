//NEW DOC  SettingsStore.swift
import Combine
import Foundation
import SwiftUI

enum AppLanguage: String, CaseIterable, Identifiable, Codable {
    case english
    case englishUK
    case arabic
    case bengali
    case chineseSimplified
    case chineseTraditional
    case croatian
    case czech
    case danish
    case dutch
    case filipino
    case finnish
    case french
    case german
    case greek
    case hebrew
    case hindi
    case hungarian
    case indonesian
    case italian
    case japanese
    case korean
    case malay
    case norwegian
    case polish
    case portugueseBrazil
    case portuguesePortugal
    case romanian
    case russian
    case serbian
    case slovak
    case slovenian
    case spanishMexico
    case spanishSpain
    case swedish
    case tamil
    case thai
    case turkish
    case ukrainian
    case vietnamese

    var id: String { rawValue }

    var localeIdentifier: String {
        switch self {
        case .english: return "en_US"
        case .englishUK: return "en_GB"
        case .arabic: return "ar_SA"
        case .bengali: return "bn_BD"
        case .chineseSimplified: return "zh_Hans_CN"
        case .chineseTraditional: return "zh_Hant_TW"
        case .croatian: return "hr_HR"
        case .czech: return "cs_CZ"
        case .danish: return "da_DK"
        case .dutch: return "nl_NL"
        case .filipino: return "fil_PH"
        case .finnish: return "fi_FI"
        case .french: return "fr_FR"
        case .german: return "de_DE"
        case .greek: return "el_GR"
        case .hebrew: return "he_IL"
        case .hindi: return "hi_IN"
        case .hungarian: return "hu_HU"
        case .indonesian: return "id_ID"
        case .italian: return "it_IT"
        case .japanese: return "ja_JP"
        case .korean: return "ko_KR"
        case .malay: return "ms_MY"
        case .norwegian: return "nb_NO"
        case .polish: return "pl_PL"
        case .portugueseBrazil: return "pt_BR"
        case .portuguesePortugal: return "pt_PT"
        case .romanian: return "ro_RO"
        case .russian: return "ru_RU"
        case .serbian: return "sr_RS"
        case .slovak: return "sk_SK"
        case .slovenian: return "sl_SI"
        case .spanishMexico: return "es_MX"
        case .spanishSpain: return "es_ES"
        case .swedish: return "sv_SE"
        case .tamil: return "ta_IN"
        case .thai: return "th_TH"
        case .turkish: return "tr_TR"
        case .ukrainian: return "uk_UA"
        case .vietnamese: return "vi_VN"
        }
    }

    var numberingSystemOverride: String? {
        switch self {
        case .arabic: return "arab"
        case .bengali: return "beng"
        case .chineseSimplified, .chineseTraditional: return "hanidec"
        case .hindi: return "deva"
        case .japanese: return "hanidec"
        case .thai: return "thai"
        default: return nil
        }
    }

    var isRightToLeft: Bool {
        switch self {
        case .arabic:
            return true
        default:
            return false
        }
    }

    var countryName: String {
        switch self {
        case .english: return "United States"
        case .englishUK: return "United Kingdom"
        case .arabic: return "Saudi Arabia"
        case .bengali: return "Bangladesh"
        case .chineseSimplified: return "China"
        case .chineseTraditional: return "Taiwan"
        case .croatian: return "Croatia"
        case .czech: return "Czech Republic"
        case .danish: return "Denmark"
        case .dutch: return "Netherlands"
        case .filipino: return "Philippines"
        case .finnish: return "Finland"
        case .french: return "France"
        case .german: return "Germany"
        case .greek: return "Greece"
        case .hebrew: return "Israel"
        case .hindi: return "India"
        case .hungarian: return "Hungary"
        case .indonesian: return "Indonesia"
        case .italian: return "Italy"
        case .japanese: return "Japan"
        case .korean: return "South Korea"
        case .malay: return "Malaysia"
        case .norwegian: return "Norway"
        case .polish: return "Poland"
        case .portugueseBrazil: return "Brazil"
        case .portuguesePortugal: return "Portugal"
        case .romanian: return "Romania"
        case .russian: return "Russia"
        case .serbian: return "Serbia"
        case .slovak: return "Slovakia"
        case .slovenian: return "Slovenia"
        case .spanishMexico: return "Mexico"
        case .spanishSpain: return "Spain"
        case .swedish: return "Sweden"
        case .tamil: return "India"
        case .thai: return "Thailand"
        case .turkish: return "Turkey"
        case .ukrainian: return "Ukraine"
        case .vietnamese: return "Vietnam"
        }
    }

    var languageName: String {
        switch self {
        case .english: return "English (US)"
        case .englishUK: return "English (UK)"
        case .arabic: return "Arabic"
        case .bengali: return "Bengali"
        case .chineseSimplified: return "Chinese (Simplified)"
        case .chineseTraditional: return "Chinese (Traditional)"
        case .croatian: return "Croatian"
        case .czech: return "Czech"
        case .danish: return "Danish"
        case .dutch: return "Dutch"
        case .filipino: return "Filipino"
        case .finnish: return "Finnish"
        case .french: return "French"
        case .german: return "German"
        case .greek: return "Greek"
        case .hebrew: return "Hebrew"
        case .hindi: return "Hindi"
        case .hungarian: return "Hungarian"
        case .indonesian: return "Indonesian"
        case .italian: return "Italian"
        case .japanese: return "Japanese"
        case .korean: return "Korean"
        case .malay: return "Malay"
        case .norwegian: return "Norwegian"
        case .polish: return "Polish"
        case .portugueseBrazil: return "Portuguese (Brazil)"
        case .portuguesePortugal: return "Portuguese (Portugal)"
        case .romanian: return "Romanian"
        case .russian: return "Russian"
        case .serbian: return "Serbian"
        case .slovak: return "Slovak"
        case .slovenian: return "Slovenian"
        case .spanishMexico: return "Spanish (Mexico)"
        case .spanishSpain: return "Spanish (Spain)"
        case .swedish: return "Swedish"
        case .tamil: return "Tamil"
        case .thai: return "Thai"
        case .turkish: return "Turkish"
        case .ukrainian: return "Ukrainian"
        case .vietnamese: return "Vietnamese"
        }
    }

    var displayName: String {
        "\(localizedLanguageName) (\(localizedCountryName))"
    }

    var shortDisplayName: String {
        localizedLanguageName
    }

    var localizedCountryName: String {
        let locale = Locale(identifier: localeIdentifier)
        if let regionCode = locale.region?.identifier,
           let localized = locale.localizedString(forRegionCode: regionCode) {
            return localized
        }
        return countryName
    }

    var localizedLanguageName: String {
        let locale = Locale(identifier: localeIdentifier)
        if let languageCode = locale.language.languageCode?.identifier,
           let localized = locale.localizedString(forLanguageCode: languageCode) {
            return capitalizedFirstLetter(localized, locale: locale)
        }
        return capitalizedFirstLetter(languageName, locale: locale)
    }

    private func capitalizedFirstLetter(_ value: String, locale: Locale) -> String {
        guard let first = value.first else { return value }
        return String(first).uppercased(with: locale) + value.dropFirst()
    }

    var flagEmoji: String {
        switch self {
        case .english: return "🇺🇸"
        case .englishUK: return "🇬🇧"
        case .arabic: return "🇸🇦"
        case .bengali: return "🇧🇩"
        case .chineseSimplified: return "🇨🇳"
        case .chineseTraditional: return "🇹🇼"
        case .croatian: return "🇭🇷"
        case .czech: return "🇨🇿"
        case .danish: return "🇩🇰"
        case .dutch: return "🇳🇱"
        case .filipino: return "🇵🇭"
        case .finnish: return "🇫🇮"
        case .french: return "🇫🇷"
        case .german: return "🇩🇪"
        case .greek: return "🇬🇷"
        case .hebrew: return "🇮🇱"
        case .hindi: return "🇮🇳"
        case .hungarian: return "🇭🇺"
        case .indonesian: return "🇮🇩"
        case .italian: return "🇮🇹"
        case .japanese: return "🇯🇵"
        case .korean: return "🇰🇷"
        case .malay: return "🇲🇾"
        case .norwegian: return "🇳🇴"
        case .polish: return "🇵🇱"
        case .portugueseBrazil: return "🇧🇷"
        case .portuguesePortugal: return "🇵🇹"
        case .romanian: return "🇷🇴"
        case .russian: return "🇷🇺"
        case .serbian: return "🇷🇸"
        case .slovak: return "🇸🇰"
        case .slovenian: return "🇸🇮"
        case .spanishMexico: return "🇲🇽"
        case .spanishSpain: return "🇪🇸"
        case .swedish: return "🇸🇪"
        case .tamil: return "🇮🇳"
        case .thai: return "🇹🇭"
        case .turkish: return "🇹🇷"
        case .ukrainian: return "🇺🇦"
        case .vietnamese: return "🇻🇳"
        }
    }

    var localizationCode: String {
        switch self {
        case .english, .englishUK: return "en"
        case .arabic: return "ar"
        case .bengali: return "bn"
        case .chineseSimplified: return "zh-Hans"
        case .chineseTraditional: return "zh-Hant"
        case .croatian: return "hr"
        case .czech: return "cs"
        case .danish: return "da"
        case .dutch: return "nl"
        case .filipino: return "fil"
        case .finnish: return "fi"
        case .french: return "fr"
        case .german: return "de"
        case .greek: return "el"
        case .hebrew: return "he"
        case .hindi: return "hi"
        case .hungarian: return "hu"
        case .indonesian: return "id"
        case .italian: return "it"
        case .japanese: return "ja"
        case .korean: return "ko"
        case .malay: return "ms"
        case .norwegian: return "nb"
        case .polish: return "pl"
        case .portugueseBrazil: return "pt-BR"
        case .portuguesePortugal: return "pt-PT"
        case .romanian: return "ro"
        case .russian: return "ru"
        case .serbian: return "sr"
        case .slovak: return "sk"
        case .slovenian: return "sl"
        case .spanishMexico, .spanishSpain: return "es"
        case .swedish: return "sv"
        case .tamil: return "ta"
        case .thai: return "th"
        case .turkish: return "tr"
        case .ukrainian: return "uk"
        case .vietnamese: return "vi"
        }
    }

    static var orderedByLanguageName: [AppLanguage] {
        allCases.sorted {
            let comparison = $0.displayName.localizedCaseInsensitiveCompare($1.displayName)
            if comparison == .orderedSame {
                return $0.countryName.localizedCaseInsensitiveCompare($1.countryName) == .orderedAscending
            }
            return comparison == .orderedAscending
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

    @AppStorage("moonEnabled") var moonEnabled: Bool = true
    @AppStorage("holidaysEnabled") var holidaysEnabled: Bool = false
    @AppStorage("faceIdLockEnabled") var faceIdLockEnabled: Bool = false
    @AppStorage("statisticsEnabled") var statisticsEnabled: Bool = true
    @AppStorage("scoreEnabled") var scoreEnabled: Bool = false
    @AppStorage("appleIdConnected") var appleIdConnected: Bool = false
    @AppStorage("appleUserIdentifier") var appleUserIdentifier: String = ""
    @AppStorage("donationPaid") var donationPaid: Bool = false
    @AppStorage("appleLastSnapshotAt") private var appleLastSnapshotAtInterval: Double = 0
    @AppStorage("appleSnapshotDeletionPending") var appleSnapshotDeletionPending: Bool = false
    var appleLastSnapshotAt: Date {
        get { Date(timeIntervalSince1970: appleLastSnapshotAtInterval) }
        set { appleLastSnapshotAtInterval = newValue.timeIntervalSince1970; objectWillChange.send() }
    }

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
        dailyItemCount = max(1, min(10, dailyItemCount))
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
