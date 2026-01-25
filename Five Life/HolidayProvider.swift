//NEW DOC  HolidayProvider.swift
import Foundation

struct HolidayItem {
    let date: Date
    let name: String
}

enum HolidayProvider {
    private enum HolidayID: String, CaseIterable {
        case newYearsDay = "new_years_day"
        case independenceDay = "independence_day"
        case veteransDay = "veterans_day"
        case christmasDay = "christmas_day"
        case mlkDay = "mlk_day"
        case presidentsDay = "presidents_day"
        case memorialDay = "memorial_day"
        case laborDay = "labor_day"
        case thanksgiving = "thanksgiving"
        case valentinesDay = "valentines_day"
        case internationalWomensDay = "international_womens_day"
        case earthDay = "earth_day"
        case worldEnvironmentDay = "world_environment_day"
        case internationalDayOfPeace = "international_day_of_peace"
        case halloween = "halloween"
        case liberationDay = "liberation_day"
        case sinterklaas = "sinterklaas"
        case christmasDayOne = "christmas_day_one"
        case christmasDayTwo = "christmas_day_two"
        case kingsDay = "kings_day"
        case goodFriday = "good_friday"
        case easterSunday = "easter_sunday"
        case easterMonday = "easter_monday"
        case ascensionDay = "ascension_day"
        case pentecostSunday = "pentecost_sunday"
        case pentecostMonday = "pentecost_monday"
        case eidAlFitr = "eid_al_fitr"
        case eidAlAdha = "eid_al_adha"
        case roshHashanah = "rosh_hashanah"
        case yomKippur = "yom_kippur"
        case hanukkah = "hanukkah"
        case lunarNewYear = "lunar_new_year"
    }

    private struct HolidayDefinition {
        let id: HolidayID
        let dates: (Int, Calendar) -> [Date]
    }

    private struct HolidayCacheKey: Hashable {
        let year: Int
        let language: AppLanguage
        let calendarIdentifier: Calendar.Identifier
        let timeZoneIdentifier: String
    }

    private static var holidayCache: [HolidayCacheKey: [Date: [String]]] = [:]

    static func holidayNames(on date: Date,
                             language: AppLanguage,
                             calendar: Calendar = .current) -> [String] {
        let year = calendar.component(.year, from: date)
        let key = HolidayCacheKey(year: year,
                                  language: language,
                                  calendarIdentifier: calendar.identifier,
                                  timeZoneIdentifier: calendar.timeZone.identifier)
        let dayKey = calendar.startOfDay(for: date)

        if let cached = holidayCache[key] {
            return cached[dayKey] ?? []
        }

        let holidayMap = buildHolidayMap(for: year, language: language, calendar: calendar)
        holidayCache[key] = holidayMap
        return holidayMap[dayKey] ?? []
    }

    private static func buildHolidayMap(for year: Int,
                                        language: AppLanguage,
                                        calendar: Calendar) -> [Date: [String]] {
        var items: [HolidayItem] = []
        let enabledIDs = enabledHolidayIDs(for: language)
        for definition in holidayDefinitions where enabledIDs.contains(definition.id) {
            let name = holidayName(for: definition.id, language: language)
            for date in definition.dates(year, calendar) {
                items.append(HolidayItem(date: date, name: name))
            }
        }

        var map: [Date: [String]] = [:]
        for item in items {
            let dayKey = calendar.startOfDay(for: item.date)
            var names = map[dayKey] ?? []
            if !names.contains(item.name) {
                names.append(item.name)
                map[dayKey] = names
            }
        }
        return map
    }

    private static var holidayDefinitions: [HolidayDefinition] {
        [
            HolidayDefinition(id: .newYearsDay, dates: fixedDate(month: 1, day: 1)),
            HolidayDefinition(id: .independenceDay, dates: fixedDate(month: 7, day: 4)),
            HolidayDefinition(id: .veteransDay, dates: fixedDate(month: 11, day: 11)),
            HolidayDefinition(id: .christmasDay, dates: fixedDate(month: 12, day: 25)),
            HolidayDefinition(id: .mlkDay, dates: nthWeekdayDate(month: 1, weekday: 2, occurrence: 3)),
            HolidayDefinition(id: .presidentsDay, dates: nthWeekdayDate(month: 2, weekday: 2, occurrence: 3)),
            HolidayDefinition(id: .memorialDay, dates: lastWeekdayDate(month: 5, weekday: 2)),
            HolidayDefinition(id: .laborDay, dates: nthWeekdayDate(month: 9, weekday: 2, occurrence: 1)),
            HolidayDefinition(id: .thanksgiving, dates: nthWeekdayDate(month: 11, weekday: 5, occurrence: 4)),
            HolidayDefinition(id: .valentinesDay, dates: fixedDate(month: 2, day: 14)),
            HolidayDefinition(id: .internationalWomensDay, dates: fixedDate(month: 3, day: 8)),
            HolidayDefinition(id: .earthDay, dates: fixedDate(month: 4, day: 22)),
            HolidayDefinition(id: .worldEnvironmentDay, dates: fixedDate(month: 6, day: 5)),
            HolidayDefinition(id: .internationalDayOfPeace, dates: fixedDate(month: 9, day: 21)),
            HolidayDefinition(id: .halloween, dates: fixedDate(month: 10, day: 31)),
            HolidayDefinition(id: .liberationDay, dates: fixedDate(month: 5, day: 5)),
            HolidayDefinition(id: .sinterklaas, dates: fixedDate(month: 12, day: 5)),
            HolidayDefinition(id: .christmasDayOne, dates: fixedDate(month: 12, day: 25)),
            HolidayDefinition(id: .christmasDayTwo, dates: fixedDate(month: 12, day: 26)),
            HolidayDefinition(id: .kingsDay, dates: adjustedKingsDayDate()),
            HolidayDefinition(id: .goodFriday, dates: easterRelativeDates(offset: -2)),
            HolidayDefinition(id: .easterSunday, dates: easterRelativeDates(offset: 0)),
            HolidayDefinition(id: .easterMonday, dates: easterRelativeDates(offset: 1)),
            HolidayDefinition(id: .ascensionDay, dates: easterRelativeDates(offset: 39)),
            HolidayDefinition(id: .pentecostSunday, dates: easterRelativeDates(offset: 49)),
            HolidayDefinition(id: .pentecostMonday, dates: easterRelativeDates(offset: 50)),
            HolidayDefinition(id: .eidAlFitr, dates: islamicDate(month: 10, day: 1)),
            HolidayDefinition(id: .eidAlAdha, dates: islamicDate(month: 12, day: 10)),
            HolidayDefinition(id: .roshHashanah, dates: hebrewDate(month: 1, day: 1)),
            HolidayDefinition(id: .yomKippur, dates: hebrewDate(month: 1, day: 10)),
            HolidayDefinition(id: .hanukkah, dates: hebrewDate(month: 3, day: 25)),
            HolidayDefinition(id: .lunarNewYear, dates: chineseDate(month: 1, day: 1))
        ]
    }

    private static let englishHolidayIDs: [HolidayID] = [
        .newYearsDay,
        .independenceDay,
        .veteransDay,
        .christmasDay,
        .mlkDay,
        .presidentsDay,
        .memorialDay,
        .laborDay,
        .thanksgiving
    ]

    private static let internationalHolidayIDs: [HolidayID] = [
        .valentinesDay,
        .internationalWomensDay,
        .earthDay,
        .worldEnvironmentDay,
        .internationalDayOfPeace,
        .halloween
    ]

    private static let dutchHolidayIDs: [HolidayID] = [
        .newYearsDay,
        .liberationDay,
        .sinterklaas,
        .christmasDayOne,
        .christmasDayTwo,
        .kingsDay
    ]

    private static let religiousHolidayIDs: [HolidayID] = [
        .goodFriday,
        .easterSunday,
        .easterMonday,
        .ascensionDay,
        .pentecostSunday,
        .pentecostMonday,
        .eidAlFitr,
        .eidAlAdha,
        .roshHashanah,
        .yomKippur,
        .hanukkah,
        .lunarNewYear
    ]

    private static func holidayName(for id: HolidayID, language: AppLanguage) -> String {
        L10n.string("holiday.\(id.rawValue)", language: language)
    }

    private static func enabledHolidayIDs(for language: AppLanguage) -> Set<HolidayID> {
        let list = L10n.string("holiday.enabled_list", language: language)
        let ids = list
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .compactMap { HolidayID(rawValue: String($0)) }
        if list == "holiday.enabled_list" || ids.isEmpty {
            return defaultHolidayIDs(for: language)
        }
        return Set(ids)
    }

    private static func defaultHolidayIDs(for language: AppLanguage) -> Set<HolidayID> {
        switch language {
        case .english, .englishUK:
            return Set(englishHolidayIDs + internationalHolidayIDs + religiousHolidayIDs)
        case .dutch:
            return Set(dutchHolidayIDs + religiousHolidayIDs)
        default:
            return Set(internationalHolidayIDs + religiousHolidayIDs)
        }
    }

    private static func fixedDate(month: Int, day: Int) -> (Int, Calendar) -> [Date] {
        { year, calendar in
            guard let date = calendar.date(from: DateComponents(year: year, month: month, day: day)) else {
                return []
            }
            return [date]
        }
    }

    private static func nthWeekdayDate(month: Int, weekday: Int, occurrence: Int) -> (Int, Calendar) -> [Date] {
        { year, calendar in
            guard let date = nthWeekday(inMonth: month, year: year, weekday: weekday, occurrence: occurrence, calendar: calendar) else {
                return []
            }
            return [date]
        }
    }

    private static func lastWeekdayDate(month: Int, weekday: Int) -> (Int, Calendar) -> [Date] {
        { year, calendar in
            guard let date = lastWeekday(inMonth: month, year: year, weekday: weekday, calendar: calendar) else {
                return []
            }
            return [date]
        }
    }

    private static func adjustedKingsDayDate() -> (Int, Calendar) -> [Date] {
        { year, calendar in
            guard let date = adjustedKingsDay(for: year, calendar: calendar) else { return [] }
            return [date]
        }
    }

    private static func easterRelativeDates(offset: Int) -> (Int, Calendar) -> [Date] {
        { year, calendar in
            guard let easter = easterSunday(for: year),
                  let date = calendar.date(byAdding: .day, value: offset, to: easter) else {
                return []
            }
            return [date]
        }
    }

    private static func islamicDate(month: Int, day: Int) -> (Int, Calendar) -> [Date] {
        { year, _ in
            let calendar = Calendar(identifier: .islamicUmmAlQura)
            return datesMatching(calendar: calendar, year: year) { comps in
                guard let compsMonth = comps.month, let compsDay = comps.day else { return false }
                return compsMonth == month && compsDay == day
            }
        }
    }

    private static func hebrewDate(month: Int, day: Int) -> (Int, Calendar) -> [Date] {
        { year, _ in
            let calendar = Calendar(identifier: .hebrew)
            return datesMatching(calendar: calendar, year: year) { comps in
                guard let compsMonth = comps.month, let compsDay = comps.day else { return false }
                return compsMonth == month && compsDay == day
            }
        }
    }

    private static func chineseDate(month: Int, day: Int) -> (Int, Calendar) -> [Date] {
        { year, _ in
            let calendar = Calendar(identifier: .chinese)
            return datesMatching(calendar: calendar, year: year) { comps in
                guard let compsMonth = comps.month, let compsDay = comps.day else { return false }
                return compsMonth == month && compsDay == day
            }
        }
    }

    private static func nthWeekday(inMonth month: Int,
                                   year: Int,
                                   weekday: Int,
                                   occurrence: Int,
                                   calendar: Calendar) -> Date? {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.weekday = weekday
        components.weekdayOrdinal = occurrence
        return calendar.date(from: components)
    }

    private static func lastWeekday(inMonth month: Int,
                                    year: Int,
                                    weekday: Int,
                                    calendar: Calendar) -> Date? {
        var components = DateComponents()
        components.year = year
        components.month = month + 1
        components.day = 0
        guard let lastDay = calendar.date(from: components) else { return nil }
        let weekdayOfLast = calendar.component(.weekday, from: lastDay)
        let diff = (weekdayOfLast - weekday + 7) % 7
        return calendar.date(byAdding: .day, value: -diff, to: lastDay)
    }

    private static func adjustedKingsDay(for year: Int, calendar: Calendar) -> Date? {
        guard let april27 = calendar.date(from: DateComponents(year: year, month: 4, day: 27)) else {
            return nil
        }
        let weekday = calendar.component(.weekday, from: april27)
        if weekday == 1 {
            return calendar.date(byAdding: .day, value: -1, to: april27)
        }
        return april27
    }

    private static func easterSunday(for year: Int) -> Date? {
        // Meeus/Jones/Butcher algorithm for Gregorian calendar
        let a = year % 19
        let b = year / 100
        let c = year % 100
        let d = b / 4
        let e = b % 4
        let f = (b + 8) / 25
        let g = (b - f + 1) / 3
        let h = (19 * a + b - d - g + 15) % 30
        let i = c / 4
        let k = c % 4
        let l = (32 + 2 * e + 2 * i - h - k) % 7
        let m = (a + 11 * h + 22 * l) / 451
        let month = (h + l - 7 * m + 114) / 31
        let day = ((h + l - 7 * m + 114) % 31) + 1
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar.date(from: DateComponents(year: year, month: month, day: day))
    }

    private static func datesMatching(calendar: Calendar,
                                      year: Int,
                                      matching: (DateComponents) -> Bool) -> [Date] {
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = .current
        guard let start = gregorian.date(from: DateComponents(year: year, month: 1, day: 1)),
              let end = gregorian.date(from: DateComponents(year: year + 1, month: 1, day: 1)) else {
            return []
        }

        var dates: [Date] = []
        var current = start
        while current < end {
            let comps = calendar.dateComponents([.month, .day], from: current)
            if matching(comps) {
                dates.append(current)
            }
            guard let next = gregorian.date(byAdding: .day, value: 1, to: current) else { break }
            current = next
        }
        return dates
    }
}
