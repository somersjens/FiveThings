//NEW DOC  Models.swift
import Foundation
import SwiftData

@Model
final class DayEntry {
    var id: UUID
    /// Normalized start-of-day date (local calendar)
    var day: Date
    /// How many items this day expects (3...10)
    var itemCount: Int
    /// Stored as an attribute so we can keep it simple and local.
    @Attribute var items: [String]
    var isLocked: Bool
    var createdAt: Date
    var updatedAt: Date

    init(day: Date, itemCount: Int) {
        self.id = UUID()
        self.day = day
        self.itemCount = itemCount
        self.items = Array(repeating: "", count: max(3, min(10, itemCount)))
        self.isLocked = false
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    var isComplete: Bool {
        items.count == itemCount && items.allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    func resizeItemsIfNeeded(to newCount: Int) {
        let clamped = max(3, min(10, newCount))
        if clamped == itemCount { return }
        itemCount = clamped

        if items.count < clamped {
            items.append(contentsOf: Array(repeating: "", count: clamped - items.count))
        } else if items.count > clamped {
            items = Array(items.prefix(clamped))
        }
        updatedAt = Date()
    }
}
