//NEW DOC  MoonPhase.swift
import Foundation

enum MoonPhaseKind: String {
    case newMoon
    case firstQuarter
    case fullMoon
    case thirdQuarter

    func localizedName(language: AppLanguage) -> String {
        switch (self, language) {
        case (.newMoon, .dutch): return "Nieuwe maan"
        case (.firstQuarter, .dutch): return "Eerste kwartier"
        case (.fullMoon, .dutch): return "Volle maan"
        case (.thirdQuarter, .dutch): return "Derde kwartier"
        case (.newMoon, .english): return "New Moon"
        case (.firstQuarter, .english): return "First Quarter"
        case (.fullMoon, .english): return "Full Moon"
        case (.thirdQuarter, .english): return "Third Quarter"
        }
    }

    var sfSymbolName: String {
        switch self {
        case .newMoon: return "moonphase.new.moon"
        case .firstQuarter: return "moonphase.first.quarter"
        case .fullMoon: return "moonphase.full.moon"
        case .thirdQuarter: return "moonphase.last.quarter"
        }
    }
}

enum MoonPhase {
    /// Simple local approximation (no network).
    /// Returns one of the 4 “named” phases only when the phase is close enough.
    static func namedPhaseIfNear(_ date: Date, threshold: Double = 0.04) -> MoonPhaseKind? {
        // Known new moon reference: 2000-01-06 18:14 UTC (commonly used approximation anchor)
        // We’ll approximate in UTC to avoid locale drift.
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt

        let refComponents = DateComponents(calendar: calendar, timeZone: calendar.timeZone,
                                           year: 2000, month: 1, day: 6, hour: 18, minute: 14)
        guard let reference = calendar.date(from: refComponents) else { return nil }

        let synodicMonth = 29.530588853 // days
        let secondsPerDay = 86400.0

        let deltaSeconds = date.timeIntervalSince(reference)
        let deltaDays = deltaSeconds / secondsPerDay

        // phase 0.0..1.0 (0=new, 0.25=first quarter, 0.5=full, 0.75=third)
        let phase = (deltaDays / synodicMonth).truncatingRemainder(dividingBy: 1.0)
        let p = phase < 0 ? phase + 1.0 : phase

        func near(_ target: Double) -> Bool {
            let d = min(abs(p - target), 1.0 - abs(p - target))
            return d <= threshold
        }

        if near(0.0) { return .newMoon }
        if near(0.25) { return .firstQuarter }
        if near(0.5) { return .fullMoon }
        if near(0.75) { return .thirdQuarter }
        return nil
    }
}
