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
    private struct PhaseCacheKey: Hashable {
        let day: Date
        let timeZoneIdentifier: String
    }

    private static var phaseCache: [PhaseCacheKey: MoonPhaseKind] = [:]

    /// Simple local approximation (no network).
    static func phase(on date: Date, timeZone: TimeZone) -> MoonPhaseKind {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let dayStart = calendar.startOfDay(for: date)
        let midday = calendar.date(byAdding: .hour, value: 12, to: dayStart) ?? date

        let dayKey = cacheDayKey(for: dayStart, timeZone: timeZone)
        if let cached = phaseCache[dayKey] {
            return cached
        }

        let phaseValue = phaseFraction(on: midday)
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

    static func description(on date: Date, language: AppLanguage, locale: Locale, timeZone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
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
            formatter.timeZone = timeZone
            let timeText = formatter.string(from: principal.date)
            let phaseName = principal.kind.localizedName(language: language)
            return L10n.string("moonphase.principal.format", language: language, phaseName, timeText, "\(principal.approxPercent)")
        }

        let range = illuminationRange(in: dayStart..<dayEnd)
        let direction = waxingOrWaning(on: midday, language: language)
        return L10n.string("moonphase.illumination.range", language: language,
                           "\(range.min)", "\(range.max)%", direction)
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
        let phaseType = PrincipalPhaseType(targetPhase: targetPhase)
        let k = approximateK(for: date, targetPhase: targetPhase)
        let candidates = [k - 1.0, k, k + 1.0].map { truePhaseDate(for: $0, phaseType: phaseType) }
        guard let closest = candidates.min(by: { abs($0.timeIntervalSince(date)) < abs($1.timeIntervalSince(date)) }) else {
            return date
        }
        return closest
    }

    private enum PrincipalPhaseType {
        case newMoon
        case firstQuarter
        case fullMoon
        case thirdQuarter

        init(targetPhase: Double) {
            switch targetPhase {
            case 0.25: self = .firstQuarter
            case 0.5: self = .fullMoon
            case 0.75: self = .thirdQuarter
            default: self = .newMoon
            }
        }

        var kOffset: Double {
            switch self {
            case .newMoon: return 0.0
            case .firstQuarter: return 0.25
            case .fullMoon: return 0.5
            case .thirdQuarter: return 0.75
            }
        }

        var fraction: Double {
            kOffset
        }
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
        let minRounded = max(0, Int(minValue.rounded()))
        let maxRounded = min(100, Int(maxValue.rounded()))
        return (minRounded, maxRounded)
    }

    private static func illuminationPercentage(for phase: Double) -> Double {
        (1.0 - cos(2.0 * Double.pi * phase)) / 2.0 * 100.0
    }

    private static func cacheDayKey(for date: Date, timeZone: TimeZone) -> PhaseCacheKey {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let dayStart = calendar.startOfDay(for: date)
        return PhaseCacheKey(day: dayStart, timeZoneIdentifier: timeZone.identifier)
    }

    private static func phaseFraction(on date: Date) -> Double {
        let phaseTypes: [PrincipalPhaseType] = [.newMoon, .firstQuarter, .fullMoon, .thirdQuarter]
        var events: [(date: Date, fraction: Double)] = []
        for phaseType in phaseTypes {
            let k = approximateK(for: date, targetPhase: phaseType.kOffset)
            for candidate in [k - 1.0, k, k + 1.0] {
                let eventDate = truePhaseDate(for: candidate, phaseType: phaseType)
                events.append((eventDate, phaseType.fraction))
            }
        }

        let sorted = events.sorted { $0.date < $1.date }
        guard let nextIndex = sorted.firstIndex(where: { $0.date > date }) else {
            return sorted.last?.fraction ?? 0.0
        }

        let next = sorted[nextIndex]
        let last = nextIndex > 0 ? sorted[nextIndex - 1] : sorted.last ?? next
        let span = next.date.timeIntervalSince(last.date)
        guard span > 0 else { return last.fraction }
        let elapsed = date.timeIntervalSince(last.date)
        var startFraction = last.fraction
        var endFraction = next.fraction
        if endFraction <= startFraction {
            endFraction += 1.0
        }
        let fraction = startFraction + (elapsed / span) * (endFraction - startFraction)
        let normalized = fraction.truncatingRemainder(dividingBy: 1.0)
        return normalized < 0 ? normalized + 1.0 : normalized
    }

    private static let synodicMonth = 29.530588853
    private static let secondsPerDay = 86400.0

    private static func approximateK(for date: Date, targetPhase: Double) -> Double {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        let year = Double(components.year ?? 2000)
        let month = Double((components.month ?? 1) - 1)
        let day = Double((components.day ?? 1) - 1)
        let yearFraction = year + (month + day / 30.0) / 12.0
        let k = (yearFraction - 2000.0) * 12.3685
        return (k - targetPhase).rounded() + targetPhase
    }

    private static func truePhaseDate(for k: Double, phaseType: PrincipalPhaseType) -> Date {
        let jd = truePhaseJulianDay(for: k, phaseType: phaseType)
        return date(fromJulianDay: jd)
    }

    private static func truePhaseJulianDay(for k: Double, phaseType: PrincipalPhaseType) -> Double {
        let t = k / 1236.85
        let t2 = t * t
        let t3 = t2 * t
        let t4 = t3 * t
        let jdMean = 2451550.09765
            + 29.530588853 * k
            + 0.0001337 * t2
            - 0.000000150 * t3
            + 0.00000000073 * t4

        let e = 1.0 - 0.002516 * t - 0.0000074 * t2
        let m = degreesToRadians(2.5534 + 29.10535670 * k - 0.0000014 * t2 - 0.00000011 * t3)
        let mPrime = degreesToRadians(201.5643 + 385.81693528 * k + 0.0107582 * t2 + 0.00001238 * t3 - 0.000000058 * t4)
        let f = degreesToRadians(160.7108 + 390.67050284 * k - 0.0016118 * t2 - 0.00000227 * t3 + 0.000000011 * t4)
        let omega = degreesToRadians(124.7746 - 1.56375580 * k + 0.0020691 * t2 + 0.00000215 * t3)

        let correction: Double
        switch phaseType {
        case .newMoon:
            correction = newOrFullCorrection(m: m, mPrime: mPrime, f: f, omega: omega, e: e, isFullMoon: false)
        case .fullMoon:
            correction = newOrFullCorrection(m: m, mPrime: mPrime, f: f, omega: omega, e: e, isFullMoon: true)
        case .firstQuarter, .thirdQuarter:
            correction = quarterCorrection(m: m, mPrime: mPrime, f: f, omega: omega, e: e, isFirstQuarter: phaseType == .firstQuarter)
        }

        let additional = planetaryCorrection(for: k, t: t)
        return jdMean + correction + additional
    }

    private static func newOrFullCorrection(m: Double,
                                           mPrime: Double,
                                           f: Double,
                                           omega: Double,
                                           e: Double,
                                           isFullMoon: Bool) -> Double {
        let sinM = sin(m)
        let sinMPrime = sin(mPrime)
        let sin2MPrime = sin(2.0 * mPrime)
        let sin2F = sin(2.0 * f)
        let sinMPrimeMinusM = sin(mPrime - m)
        let sinMPrimePlusM = sin(mPrime + m)
        let sin2M = sin(2.0 * m)
        let sinMPrimeMinus2F = sin(mPrime - 2.0 * f)
        let sinMPrimePlus2F = sin(mPrime + 2.0 * f)
        let sin2MPrimePlusM = sin(2.0 * mPrime + m)
        let sin3MPrime = sin(3.0 * mPrime)
        let sinMPlus2F = sin(m + 2.0 * f)
        let sinMMinus2F = sin(m - 2.0 * f)
        let sin2MPrimeMinusM = sin(2.0 * mPrime - m)
        let sinOmega = sin(omega)
        let sinMPrimePlus2M = sin(mPrime + 2.0 * m)
        let sin2MPrimeMinus2F = sin(2.0 * mPrime - 2.0 * f)
        let sin3M = sin(3.0 * m)
        let sinMPrimePlusMMinus2F = sin(mPrime + m - 2.0 * f)
        let sin2MPrimePlus2F = sin(2.0 * mPrime + 2.0 * f)
        let sinMPrimePlusMPlus2F = sin(mPrime + m + 2.0 * f)
        let sinMPrimeMinusMPlus2F = sin(mPrime - m + 2.0 * f)
        let sinMPrimeMinusMMinus2F = sin(mPrime - m - 2.0 * f)
        let sin3MPrimePlusM = sin(3.0 * mPrime + m)
        let sin4MPrime = sin(4.0 * mPrime)

        let coefficients = isFullMoon
            ? (-0.40614, 0.17302, 0.01614, 0.01043, 0.00734, -0.00515, 0.00209)
            : (-0.40720, 0.17241, 0.01608, 0.01039, 0.00739, -0.00514, 0.00208)

        let (c1, c2, c3, c4, c5, c6, c7) = coefficients
        return c1 * sinMPrime
            + c2 * e * sinM
            + c3 * sin2MPrime
            + c4 * sin2F
            + c5 * e * sinMPrimeMinusM
            + c6 * e * sinMPrimePlusM
            + c7 * e * e * sin2M
            - 0.00111 * sinMPrimeMinus2F
            - 0.00057 * sinMPrimePlus2F
            + 0.00056 * e * sin2MPrimePlusM
            - 0.00042 * sin3MPrime
            + 0.00042 * e * sinMPlus2F
            + 0.00038 * e * sinMMinus2F
            - 0.00024 * e * sin2MPrimeMinusM
            - 0.00017 * sinOmega
            - 0.00007 * sinMPrimePlus2M
            + 0.00004 * sin2MPrimeMinus2F
            + 0.00004 * sin3M
            + 0.00003 * sinMPrimePlusMMinus2F
            + 0.00003 * sin2MPrimePlus2F
            - 0.00003 * sinMPrimePlusMPlus2F
            + 0.00003 * sinMPrimeMinusMPlus2F
            - 0.00002 * sinMPrimeMinusMMinus2F
            - 0.00002 * sin3MPrimePlusM
            + 0.00002 * sin4MPrime
    }

    private static func quarterCorrection(m: Double,
                                          mPrime: Double,
                                          f: Double,
                                          omega: Double,
                                          e: Double,
                                          isFirstQuarter: Bool) -> Double {
        let sinMPrime = sin(mPrime)
        let sinM = sin(m)
        let sinMPrimePlusM = sin(mPrime + m)
        let sin2MPrime = sin(2.0 * mPrime)
        let sin2F = sin(2.0 * f)
        let sinMPrimeMinusM = sin(mPrime - m)
        let sin2M = sin(2.0 * m)
        let sinMPrimeMinus2F = sin(mPrime - 2.0 * f)
        let sinMPrimePlus2F = sin(mPrime + 2.0 * f)
        let sin3MPrime = sin(3.0 * mPrime)
        let sin2MPrimeMinusM = sin(2.0 * mPrime - m)
        let sinMPlus2F = sin(m + 2.0 * f)
        let sinMMinus2F = sin(m - 2.0 * f)
        let sinMPrimePlus2M = sin(mPrime + 2.0 * m)
        let sin2MPrimePlusM = sin(2.0 * mPrime + m)
        let sinOmega = sin(omega)

        var correction = -0.62801 * sinMPrime
            + 0.17172 * e * sinM
            - 0.01183 * e * sinMPrimePlusM
            + 0.00862 * sin2MPrime
            + 0.00804 * sin2F
            + 0.00454 * e * sinMPrimeMinusM
            + 0.00204 * e * e * sin2M
            - 0.00180 * sinMPrimeMinus2F
            - 0.00070 * sinMPrimePlus2F
            - 0.00040 * sin3MPrime
            - 0.00034 * e * sin2MPrimeMinusM
            + 0.00032 * e * sinMPlus2F
            + 0.00032 * e * sinMMinus2F
            - 0.00028 * e * e * sinMPrimePlus2M
            + 0.00027 * e * sin2MPrimePlusM
            - 0.00017 * sinOmega

        let w = 0.00306
            - 0.00038 * e * cos(m)
            + 0.00026 * cos(mPrime)
            - 0.00002 * cos(mPrime - m)
            + 0.00002 * cos(mPrime + m)
            + 0.00002 * cos(2.0 * f)
        correction += isFirstQuarter ? w : -w
        return correction
    }

    private static func planetaryCorrection(for k: Double, t: Double) -> Double {
        let a1 = degreesToRadians(299.77 + 0.107408 * k - 0.009173 * t * t)
        let a2 = degreesToRadians(251.88 + 0.016321 * k)
        let a3 = degreesToRadians(251.83 + 26.651886 * k)
        let a4 = degreesToRadians(349.42 + 36.412478 * k)
        let a5 = degreesToRadians(84.66 + 18.206239 * k)
        let a6 = degreesToRadians(141.74 + 53.303771 * k)
        let a7 = degreesToRadians(207.14 + 2.453732 * k)
        let a8 = degreesToRadians(154.84 + 7.306860 * k)
        let a9 = degreesToRadians(34.52 + 27.261239 * k)
        let a10 = degreesToRadians(207.19 + 0.121824 * k)
        let a11 = degreesToRadians(291.34 + 1.844379 * k)
        let a12 = degreesToRadians(161.72 + 24.198154 * k)
        let a13 = degreesToRadians(239.56 + 25.513099 * k)
        let a14 = degreesToRadians(331.55 + 3.592518 * k)

        return 0.000325 * sin(a1)
            + 0.000165 * sin(a2)
            + 0.000164 * sin(a3)
            + 0.000126 * sin(a4)
            + 0.000110 * sin(a5)
            + 0.000062 * sin(a6)
            + 0.000060 * sin(a7)
            + 0.000056 * sin(a8)
            + 0.000047 * sin(a9)
            + 0.000042 * sin(a10)
            + 0.000040 * sin(a11)
            + 0.000037 * sin(a12)
            + 0.000035 * sin(a13)
            + 0.000023 * sin(a14)
    }

    private static func date(fromJulianDay jd: Double) -> Date {
        Date(timeIntervalSince1970: (jd - 2440587.5) * secondsPerDay)
    }

    private static func degreesToRadians(_ degrees: Double) -> Double {
        degrees * Double.pi / 180.0
    }
}
