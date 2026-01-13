//NEW DOC  HolidayProvider.swift
import Foundation

struct HolidayItem {
    let date: Date
    let name: String
}

enum HolidayProvider {
    static func holidayNames(on date: Date,
                             language: AppLanguage,
                             calendar: Calendar = .current) -> [String] {
        let year = calendar.component(.year, from: date)
        var items: [HolidayItem] = []

        switch language {
        case .english:
            items.append(contentsOf: englishHolidays(for: year, calendar: calendar))
            items.append(contentsOf: internationalHolidays(for: year, calendar: calendar))
        case .dutch:
            items.append(contentsOf: dutchHolidays(for: year, calendar: calendar))
        }

        items.append(contentsOf: religiousHolidays(for: year, language: language, calendar: calendar))

        var seen = Set<String>()
        var results: [String] = []
        for item in items where calendar.isDate(item.date, inSameDayAs: date) {
            guard !seen.contains(item.name) else { continue }
            seen.insert(item.name)
            results.append(item.name)
        }
        return results
    }

    private static func englishHolidays(for year: Int, calendar: Calendar) -> [HolidayItem] {
        var items: [HolidayItem] = []
        items.append(contentsOf: fixedDateHolidays(year: year, calendar: calendar, names: [
            (1, 1, "New Year's Day"),
            (7, 4, "Independence Day"),
            (11, 11, "Veterans Day"),
            (12, 25, "Christmas Day")
        ]))

        if let mlk = nthWeekday(inMonth: 1, year: year, weekday: 2, occurrence: 3, calendar: calendar) {
            items.append(HolidayItem(date: mlk, name: "Martin Luther King Jr. Day"))
        }
        if let presidents = nthWeekday(inMonth: 2, year: year, weekday: 2, occurrence: 3, calendar: calendar) {
            items.append(HolidayItem(date: presidents, name: "Presidents' Day"))
        }
        if let memorial = lastWeekday(inMonth: 5, year: year, weekday: 2, calendar: calendar) {
            items.append(HolidayItem(date: memorial, name: "Memorial Day"))
        }
        if let labor = nthWeekday(inMonth: 9, year: year, weekday: 2, occurrence: 1, calendar: calendar) {
            items.append(HolidayItem(date: labor, name: "Labor Day"))
        }
        if let thanksgiving = nthWeekday(inMonth: 11, year: year, weekday: 5, occurrence: 4, calendar: calendar) {
            items.append(HolidayItem(date: thanksgiving, name: "Thanksgiving"))
        }

        return items
    }

    private static func internationalHolidays(for year: Int, calendar: Calendar) -> [HolidayItem] {
        fixedDateHolidays(year: year, calendar: calendar, names: [
            (2, 14, "Valentine's Day"),
            (3, 8, "International Women's Day"),
            (4, 22, "Earth Day"),
            (6, 5, "World Environment Day"),
            (9, 21, "International Day of Peace"),
            (10, 31, "Halloween")
        ])
    }

    private static func dutchHolidays(for year: Int, calendar: Calendar) -> [HolidayItem] {
        var items: [HolidayItem] = []
        items.append(contentsOf: fixedDateHolidays(year: year, calendar: calendar, names: [
            (1, 1, "Nieuwjaarsdag"),
            (5, 5, "Bevrijdingsdag"),
            (12, 5, "Sinterklaas"),
            (12, 25, "Eerste kerstdag"),
            (12, 26, "Tweede kerstdag")
        ]))

        if let kingsDay = adjustedKingsDay(for: year, calendar: calendar) {
            items.append(HolidayItem(date: kingsDay, name: "Koningsdag"))
        }

        return items
    }

    private static func religiousHolidays(for year: Int,
                                          language: AppLanguage,
                                          calendar: Calendar) -> [HolidayItem] {
        var items: [HolidayItem] = []

        if let easter = easterSunday(for: year) {
            let names = christianHolidayNames(language: language)
            if let goodFriday = calendar.date(byAdding: .day, value: -2, to: easter) {
                items.append(HolidayItem(date: goodFriday, name: names.goodFriday))
            }
            items.append(HolidayItem(date: easter, name: names.easterSunday))
            if let easterMonday = calendar.date(byAdding: .day, value: 1, to: easter) {
                items.append(HolidayItem(date: easterMonday, name: names.easterMonday))
            }
            if let ascension = calendar.date(byAdding: .day, value: 39, to: easter) {
                items.append(HolidayItem(date: ascension, name: names.ascensionDay))
            }
            if let pentecostSunday = calendar.date(byAdding: .day, value: 49, to: easter) {
                items.append(HolidayItem(date: pentecostSunday, name: names.pentecostSunday))
            }
            if let pentecostMonday = calendar.date(byAdding: .day, value: 50, to: easter) {
                items.append(HolidayItem(date: pentecostMonday, name: names.pentecostMonday))
            }
        }

        items.append(contentsOf: islamicHolidays(for: year, language: language))
        items.append(contentsOf: jewishHolidays(for: year, language: language))
        items.append(contentsOf: lunarNewYear(for: year, language: language))

        return items
    }

    private static func islamicHolidays(for year: Int, language: AppLanguage) -> [HolidayItem] {
        let calendar = Calendar(identifier: .islamicUmmAlQura)
        let names = islamicHolidayNames(language: language)
        var items: [HolidayItem] = []

        let matches = datesMatching(calendar: calendar, year: year) { comps in
            guard let month = comps.month, let day = comps.day else { return false }
            return (month == 10 && day == 1) || (month == 12 && day == 10)
        }

        for date in matches {
            let comps = calendar.dateComponents([.month, .day], from: date)
            if comps.month == 10 && comps.day == 1 {
                items.append(HolidayItem(date: date, name: names.eidAlFitr))
            }
            if comps.month == 12 && comps.day == 10 {
                items.append(HolidayItem(date: date, name: names.eidAlAdha))
            }
        }

        return items
    }

    private static func jewishHolidays(for year: Int, language: AppLanguage) -> [HolidayItem] {
        let calendar = Calendar(identifier: .hebrew)
        let names = jewishHolidayNames(language: language)
        var items: [HolidayItem] = []

        let matches = datesMatching(calendar: calendar, year: year) { comps in
            guard let month = comps.month, let day = comps.day else { return false }
            return (month == 1 && day == 1)
                || (month == 1 && day == 10)
                || (month == 3 && day == 25)
        }

        for date in matches {
            let comps = calendar.dateComponents([.month, .day], from: date)
            if comps.month == 1 && comps.day == 1 {
                items.append(HolidayItem(date: date, name: names.roshHashanah))
            }
            if comps.month == 1 && comps.day == 10 {
                items.append(HolidayItem(date: date, name: names.yomKippur))
            }
            if comps.month == 3 && comps.day == 25 {
                items.append(HolidayItem(date: date, name: names.hanukkah))
            }
        }

        return items
    }

    private static func lunarNewYear(for year: Int, language: AppLanguage) -> [HolidayItem] {
        let calendar = Calendar(identifier: .chinese)
        let name = language == .dutch ? "Chinees Nieuwjaar" : "Lunar New Year"
        let matches = datesMatching(calendar: calendar, year: year) { comps in
            guard let month = comps.month, let day = comps.day else { return false }
            return month == 1 && day == 1
        }
        return matches.map { HolidayItem(date: $0, name: name) }
    }

    private static func christianHolidayNames(language: AppLanguage) -> (goodFriday: String,
                                                                        easterSunday: String,
                                                                        easterMonday: String,
                                                                        ascensionDay: String,
                                                                        pentecostSunday: String,
                                                                        pentecostMonday: String) {
        switch language {
        case .dutch:
            return ("Goede Vrijdag", "Eerste paasdag", "Tweede paasdag", "Hemelvaart", "Eerste pinksterdag", "Tweede pinksterdag")
        case .english:
            return ("Good Friday", "Easter Sunday", "Easter Monday", "Ascension Day", "Pentecost Sunday", "Pentecost Monday")
        }
    }

    private static func islamicHolidayNames(language: AppLanguage) -> (eidAlFitr: String, eidAlAdha: String) {
        switch language {
        case .dutch:
            return ("Suikerfeest", "Offerfeest")
        case .english:
            return ("Eid al-Fitr", "Eid al-Adha")
        }
    }

    private static func jewishHolidayNames(language: AppLanguage) -> (roshHashanah: String, yomKippur: String, hanukkah: String) {
        switch language {
        case .dutch:
            return ("Rosj Hasjana", "Jom Kipoer", "Chanoeka")
        case .english:
            return ("Rosh Hashanah", "Yom Kippur", "Hanukkah")
        }
    }

    private static func fixedDateHolidays(year: Int, calendar: Calendar, names: [(Int, Int, String)]) -> [HolidayItem] {
        names.compactMap { month, day, name in
            guard let date = calendar.date(from: DateComponents(year: year, month: month, day: day)) else { return nil }
            return HolidayItem(date: date, name: name)
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
