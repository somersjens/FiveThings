//NEW DOC  MoonPhase.swift
import Foundation

enum MoonPhaseKind: String {
    case newMoon
    case waxingCrescent
    case firstQuarter
    case waxingGibbous
    case fullMoon
    case waningGibbous
    case thirdQuarter
    case waningCrescent

    func localizedName(language: AppLanguage) -> String {
        switch (self, language) {
        case (.newMoon, .dutch): return "Nieuwe maan"
        case (.waxingCrescent, .dutch): return "Wassende sikkel"
        case (.firstQuarter, .dutch): return "Eerste kwartier"
        case (.waxingGibbous, .dutch): return "Wassende gibbeus"
        case (.fullMoon, .dutch): return "Volle maan"
        case (.waningGibbous, .dutch): return "Afnemende gibbeus"
        case (.thirdQuarter, .dutch): return "Derde kwartier"
        case (.waningCrescent, .dutch): return "Afnemende sikkel"
        case (.newMoon, .english): return "New Moon"
        case (.waxingCrescent, .english): return "Waxing Crescent"
        case (.firstQuarter, .english): return "First Quarter"
        case (.waxingGibbous, .english): return "Waxing Gibbous"
        case (.fullMoon, .english): return "Full Moon"
        case (.waningGibbous, .english): return "Waning Gibbous"
        case (.thirdQuarter, .english): return "Third Quarter"
        case (.waningCrescent, .english): return "Waning Crescent"
        }
    }

    var sfSymbolName: String {
        switch self {
        case .newMoon: return "moonphase.new.moon"
        case .waxingCrescent: return "moonphase.waxing.crescent"
        case .firstQuarter: return "moonphase.first.quarter"
        case .waxingGibbous: return "moonphase.waxing.gibbous"
        case .fullMoon: return "moonphase.full.moon"
        case .waningGibbous: return "moonphase.waning.gibbous"
        case .thirdQuarter: return "moonphase.last.quarter"
        case .waningCrescent: return "moonphase.waning.crescent"
        }
    }
}

enum MoonPhase {
    /// Simple local approximation (no network).
    static func phase(on date: Date) -> MoonPhaseKind {
        let phase = phaseFraction(on: date)
        switch phase {
        case 0..<0.0625, 0.9375...1.0:
            return .newMoon
        case 0.0625..<0.1875:
            return .waxingCrescent
        case 0.1875..<0.3125:
            return .firstQuarter
        case 0.3125..<0.4375:
            return .waxingGibbous
        case 0.4375..<0.5625:
            return .fullMoon
        case 0.5625..<0.6875:
            return .waningGibbous
        case 0.6875..<0.8125:
            return .thirdQuarter
        default:
            return .waningCrescent
        }
    }

    static func fullMoonDate(near date: Date) -> Date {
        let phase = phaseFraction(on: date)
        var delta = 0.5 - phase
        if delta > 0.5 { delta -= 1.0 }
        if delta < -0.5 { delta += 1.0 }
        return date.addingTimeInterval(delta * synodicMonth * secondsPerDay)
    }

    private static func phaseFraction(on date: Date) -> Double {
        // Known new moon reference: 2000-01-06 18:14 UTC (commonly used approximation anchor)
        // We’ll approximate in UTC to avoid locale drift.
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt

        let refComponents = DateComponents(calendar: calendar, timeZone: calendar.timeZone,
                                           year: 2000, month: 1, day: 6, hour: 18, minute: 14)
        guard let reference = calendar.date(from: refComponents) else { return 0.0 }

        let deltaSeconds = date.timeIntervalSince(reference)
        let deltaDays = deltaSeconds / secondsPerDay

        // phase 0.0..1.0 (0=new, 0.25=first quarter, 0.5=full, 0.75=third)
        let phase = (deltaDays / synodicMonth).truncatingRemainder(dividingBy: 1.0)
        return phase < 0 ? phase + 1.0 : phase
    }

    private static let synodicMonth = 29.530588853
    private static let secondsPerDay = 86400.0
}
