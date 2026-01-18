//NEW DOC  Models.swift
import Foundation
import SwiftData

@Model
final class DayEntry {
    var id: UUID
    /// Normalized start-of-day date (local calendar)
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
        self.id = UUID()
        self.day = day
        self.itemCount = itemCount
        self.items = Array(repeating: "", count: max(1, min(10, itemCount)))
        self.isLocked = false
        self.wasCompleted = false
        self.score = nil
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    var isComplete: Bool {
        isComplete(requiredCount: itemCount)
    }

    func isComplete(requiredCount: Int) -> Bool {
        let clamped = max(1, min(10, requiredCount))
        guard items.count >= clamped else { return false }
        return items.prefix(clamped).allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
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
