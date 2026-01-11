//NEW DOC  ContentViewModel.swift
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

    func lock(_ entry: DayEntry, modelContext: ModelContext) {
        entry.isLocked = true
        entry.updatedAt = Date()
        try? modelContext.save()
    }

    func unlock(_ entry: DayEntry, modelContext: ModelContext) {
        entry.isLocked = false
        entry.updatedAt = Date()
        try? modelContext.save()
    }

    func updateItem(_ entry: DayEntry, index: Int, text: String, modelContext: ModelContext) {
        guard index >= 0, index < entry.items.count else { return }
        entry.items[index] = text
        entry.updatedAt = Date()
        try? modelContext.save()
    }

    func shouldScheduleNextDayReminder(allEntries: [DayEntry]) -> Bool {
        // “If needed”: schedule if there exists any unlocked (unfinished) entry for *today* OR any prior day.
        // This is a practical interpretation given iOS notification constraints.
        allEntries.contains { !$0.isLocked }
    }
}
