//NEW DOC  ContentViewModel.swift
import Combine
import Foundation
import SwiftData

@MainActor
final class ContentViewModel: ObservableObject {
    @Published var searchText: String = ""
    @Published var newestFirst: Bool = true

    func startOfDay(_ date: Date) -> Date {
        Calendar.current.startOfDay(for: date)
    }

    func ensureTodayEntry(modelContext: ModelContext, settings: SettingsStore) {
        settings.clampDailyCount()

        let today = startOfDay(Date())
        let descriptor = FetchDescriptor<DayEntry>(
            predicate: #Predicate { $0.day == today }
        )

        if let existing = try? modelContext.fetch(descriptor).first {
            // If settings changed, resize today only when it's unlocked
            if !existing.isLocked {
                existing.resizeItemsIfNeeded(to: settings.dailyItemCount)
            }
            return
        }

        let entry = DayEntry(day: today, itemCount: settings.dailyItemCount)
        modelContext.insert(entry)
        try? modelContext.save()
    }

    func lock(_ entry: DayEntry, requiredCount: Int, modelContext: ModelContext) {
        entry.resizeItemsIfNeeded(to: requiredCount)
        entry.isLocked = true
        entry.updatedAt = Date()
        try? modelContext.save()
    }

    func unlock(_ entry: DayEntry, settings: SettingsStore, modelContext: ModelContext) {
        entry.isLocked = false
        if settings.dailyItemCount > entry.itemCount {
            entry.ensureItemsCount(atLeast: settings.dailyItemCount)
        } else {
            entry.ensureItemsCount(atLeast: entry.itemCount)
        }
        entry.updatedAt = Date()
        try? modelContext.save()
    }

    func updateItem(_ entry: DayEntry, index: Int, text: String, modelContext: ModelContext) {
        guard index >= 0, index < entry.items.count else { return }
        entry.items[index] = text
        entry.updatedAt = Date()
        try? modelContext.save()
    }

    func removeItem(_ entry: DayEntry, index: Int, modelContext: ModelContext) {
        guard index >= 0, index < entry.items.count else { return }
        entry.removeItem(at: index)
        try? modelContext.save()
    }

    func moveItem(_ entry: DayEntry, from source: Int, to destination: Int, modelContext: ModelContext) {
        guard source != destination,
              source >= 0,
              destination >= 0,
              source < entry.items.count,
              destination < entry.items.count else { return }
        let item = entry.items.remove(at: source)
        entry.items.insert(item, at: destination)
        entry.updatedAt = Date()
        try? modelContext.save()
    }

    func shouldScheduleNextDayReminder(allEntries: [DayEntry]) -> Bool {
        // “If needed”: schedule if there exists any unlocked (unfinished) entry for *today* OR any prior day.
        // This is a practical interpretation given iOS notification constraints.
        allEntries.contains { !$0.isLocked }
    }
}
