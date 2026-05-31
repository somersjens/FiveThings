//NEW DOC  Models.swift
import Foundation
import SwiftData

enum DayIdentity {
    private static let utcCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar
    }()

    private static let identifierFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = utcCalendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static func identifier(for date: Date, calendar sourceCalendar: Calendar = .current) -> String {
        let components = sourceCalendar.dateComponents([.year, .month, .day], from: date)
        return identifier(year: components.year ?? 1, month: components.month ?? 1, day: components.day ?? 1)
    }

    static func identifier(year: Int, month: Int, day: Int) -> String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    static func todayIdentifier(calendar: Calendar = .current, now: Date = Date()) -> String {
        identifier(for: now, calendar: calendar)
    }

    static func canonicalIdentifier(for date: Date) -> String {
        identifierFormatter.string(from: date)
    }

    static func canonicalDate(for identifier: String) -> Date {
        dateComponents(for: identifier).flatMap { components in
            var dateComponents = DateComponents()
            dateComponents.calendar = utcCalendar
            dateComponents.timeZone = TimeZone(secondsFromGMT: 0)
            dateComponents.year = components.year
            dateComponents.month = components.month
            dateComponents.day = components.day
            return utcCalendar.date(from: dateComponents)
        } ?? Date(timeIntervalSince1970: 0)
    }

    static func addingDays(_ days: Int, to identifier: String) -> String? {
        let date = canonicalDate(for: identifier)
        return utcCalendar.date(byAdding: .day, value: days, to: date).map { identifierFormatter.string(from: $0) }
    }

    static func dateComponents(for identifier: String) -> (year: Int, month: Int, day: Int)? {
        let parts = identifier.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return (parts[0], parts[1], parts[2])
    }
}

@Model
final class DayEntry {
    var id: UUID
    /// Stable civil-day key (yyyy-MM-dd) used for identity across time zone changes.
    var dayIdentifier: String = ""
    /// Canonical UTC date for the civil day; derive identity from dayIdentifier, not from device time zone.
    var day: Date
    /// How many items this day expects (1...10)
    var itemCount: Int
    /// Stored as an attribute so we can keep it simple and local.
    @Attribute var items: [String]
    var isLocked: Bool
    var wasCompleted: Bool
    var score: Int?
    var createdAt: Date
    var updatedAt: Date

    init(day: Date, itemCount: Int) {
        let identifier = DayIdentity.identifier(for: day)
        self.id = UUID()
        self.dayIdentifier = identifier
        self.day = DayIdentity.canonicalDate(for: identifier)
        self.itemCount = itemCount
        self.items = Array(repeating: "", count: max(1, min(10, itemCount)))
        self.isLocked = false
        self.wasCompleted = false
        self.score = nil
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    convenience init(dayIdentifier: String, itemCount: Int) {
        self.init(day: DayIdentity.canonicalDate(for: dayIdentifier), itemCount: itemCount)
        self.dayIdentifier = dayIdentifier
        self.day = DayIdentity.canonicalDate(for: dayIdentifier)
    }

    var isComplete: Bool {
        isComplete(requiredCount: itemCount)
    }

    var filledItemCount: Int {
        items.reduce(0) { count, item in
            let trimmed = item.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? count : count + 1
        }
    }

    func isComplete(requiredCount: Int) -> Bool {
        let clamped = max(1, min(10, requiredCount))
        guard items.count >= clamped else { return false }
        return items.prefix(clamped).allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    var normalizedDayIdentifier: String {
        if dayIdentifier.isEmpty {
            return DayIdentity.identifier(for: day)
        }
        return dayIdentifier
    }

    @discardableResult
    func normalizeDayIdentity() -> Bool {
        let identifier = normalizedDayIdentifier
        let canonicalDay = DayIdentity.canonicalDate(for: identifier)
        var didChange = false
        if dayIdentifier != identifier {
            dayIdentifier = identifier
            didChange = true
        }
        if day != canonicalDay {
            day = canonicalDay
            didChange = true
        }
        return didChange
    }

    func resizeItemsIfNeeded(to newCount: Int) {
        let clamped = max(1, min(10, newCount))
        var didChange = false
        if clamped != itemCount {
            itemCount = clamped
            didChange = true
        }

        if items.count < clamped {
            items.append(contentsOf: Array(repeating: "", count: clamped - items.count))
            didChange = true
        } else if items.count > clamped {
            let beforeCount = items.count
            while items.count > clamped,
                  let last = items.last,
                  last.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                items.removeLast()
            }
            didChange = didChange || items.count != beforeCount
        }
        if didChange {
            updatedAt = Date()
        }
    }

    func updateItemCountPreservingItems(to newCount: Int) {
        let clamped = max(1, min(10, newCount))
        var didChange = false
        if clamped != itemCount {
            itemCount = clamped
            didChange = true
        }
        if items.count < clamped {
            items.append(contentsOf: Array(repeating: "", count: clamped - items.count))
            didChange = true
        }
        if didChange {
            updatedAt = Date()
        }
    }

    func ensureItemsCount(atLeast count: Int) {
        let clamped = max(1, min(10, count))
        guard items.count < clamped else { return }
        items.append(contentsOf: Array(repeating: "", count: clamped - items.count))
        updatedAt = Date()
    }

    func pruneEmptyOptionalItems(keepingAtLeast count: Int) {
        let clamped = max(1, min(10, count))
        var didTrim = false
        while items.count > clamped,
              let last = items.last,
              last.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            items.removeLast()
            didTrim = true
        }
        if didTrim {
            updatedAt = Date()
        }
    }

    func removeItem(at index: Int) {
        guard index >= 0, index < items.count else { return }
        items.remove(at: index)
        updatedAt = Date()
    }
}
