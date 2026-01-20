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
        L10n.string(localizationKey, language: language)
    }

    private var localizationKey: String {
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
    private static var phaseCache: [Date: MoonPhaseKind] = [:]

    /// Simple local approximation (no network).
    static func phase(on date: Date) -> MoonPhaseKind {
        let dayKey = cacheDayKey(for: date)
        if let cached = phaseCache[dayKey] {
            return cached
        }

        let phaseValue = phaseFraction(on: date)
        let phase: MoonPhaseKind
        switch phaseValue {
        case 0..<0.0625, 0.9375...1.0:
            phase = .newMoon
        case 0.0625..<0.1875:
            phase = .waxingCrescent
        case 0.1875..<0.3125:
            phase = .firstQuarter
        case 0.3125..<0.4375:
            phase = .waxingGibbous
        case 0.4375..<0.5625:
            phase = .fullMoon
        case 0.5625..<0.6875:
            phase = .waningGibbous
        case 0.6875..<0.8125:
            phase = .thirdQuarter
        default:
            phase = .waningCrescent
        }
        phaseCache[dayKey] = phase
        return phase
    }

    static func description(on date: Date, language: AppLanguage, locale: Locale) -> String {
        var calendar = Calendar.current
        calendar.timeZone = TimeZone.current
        let dayStart = calendar.startOfDay(for: date)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart),
              let midday = calendar.date(byAdding: .hour, value: 12, to: dayStart) else {
            return ""
        }

        if let principal = principalPhaseEvent(on: midday, within: dayStart..<dayEnd) {
            let formatter = DateFormatter()
            formatter.dateStyle = .none
            formatter.timeStyle = .short
            formatter.locale = locale
            formatter.timeZone = calendar.timeZone
            let timeText = formatter.string(from: principal.date)
            let phaseName = principal.kind.localizedName(language: language)
            return L10n.string("moonphase.principal.format", language: language, phaseName, timeText, "\(principal.approxPercent)")
        }

        let range = illuminationRange(in: dayStart..<dayEnd)
        let direction = waxingOrWaning(on: midday, language: language)
        return L10n.string("moonphase.illumination.range", language: language,
                           "\(range.min)%", "\(range.max)%", direction)
    }

    private static func waxingOrWaning(on date: Date, language: AppLanguage) -> String {
        let phaseValue = phaseFraction(on: date)
        let key = phaseValue < 0.5 ? "moonphase.waxing" : "moonphase.waning"
        return L10n.string(key, language: language)
    }

    private static func principalPhaseEvent(on date: Date,
                                           within range: Range<Date>) -> (kind: MoonPhaseKind, approxPercent: Int, date: Date)? {
        let candidates: [(MoonPhaseKind, Double, Int)] = [
            (.newMoon, 0.0, 0),
            (.firstQuarter, 0.25, 50),
            (.fullMoon, 0.5, 100),
            (.thirdQuarter, 0.75, 50)
        ]
        for (kind, targetPhase, percent) in candidates {
            let eventDate = principalPhaseDate(near: date, targetPhase: targetPhase)
            if range.contains(eventDate) {
                return (kind, percent, eventDate)
            }
        }
        return nil
    }

    private static func principalPhaseDate(near date: Date, targetPhase: Double) -> Date {
        let phase = phaseFraction(on: date)
        var delta = targetPhase - phase
        if delta > 0.5 { delta -= 1.0 }
        if delta < -0.5 { delta += 1.0 }
        return date.addingTimeInterval(delta * synodicMonth * secondsPerDay)
    }

    private static func illuminationRange(in range: Range<Date>) -> (min: Int, max: Int) {
        let samples = 24
        let span = range.upperBound.timeIntervalSince(range.lowerBound)
        var minValue = 100.0
        var maxValue = 0.0
        for index in 0...samples {
            let fraction = Double(index) / Double(samples)
            let sampleDate = range.lowerBound.addingTimeInterval(span * fraction)
            let illum = illuminationPercentage(for: phaseFraction(on: sampleDate))
            minValue = min(minValue, illum)
            maxValue = max(maxValue, illum)
        }
        let minRounded = max(0, Int(floor(minValue)))
        let maxRounded = min(100, Int(ceil(maxValue)))
        return (minRounded, maxRounded)
    }

    private static func illuminationPercentage(for phase: Double) -> Double {
        (1.0 - cos(2.0 * Double.pi * phase)) / 2.0 * 100.0
    }

    private static func cacheDayKey(for date: Date) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar.startOfDay(for: date)
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
