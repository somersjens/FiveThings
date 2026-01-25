//NEW DOC  ContentViewModel.swift
import Combine
import Foundation
import SwiftData

@MainActor
final class ContentViewModel: ObservableObject {
    private enum SaveConstants {
        static let debounceNanoseconds: UInt64 = 300_000_000
    }

    private var pendingSaveTasks: [UUID: Task<Void, Never>] = [:]
    enum FinishedCardsLimit: Int, CaseIterable {
        case fourteen = 14
        case thirty = 30
        case ninety = 90
        case oneEighty = 180
        case threeSixtyFive = 365
        case all = 0

        func displayText(language: AppLanguage) -> String {
            switch self {
            case .all:
                return L10n.string("filters.all", language: language)
            default:
                return "\(rawValue)"
            }
        }

        func next() -> FinishedCardsLimit {
            let order: [FinishedCardsLimit] = [.fourteen, .thirty, .ninety, .oneEighty, .threeSixtyFive, .all]
            guard let index = order.firstIndex(of: self) else {
                return .fourteen
            }
            let nextIndex = order.index(after: index)
            return nextIndex < order.endIndex ? order[nextIndex] : .fourteen
        }
    }

    @Published var searchText: String = ""
    @Published var newestFirst: Bool = true
    @Published var finishedLimit: FinishedCardsLimit = .thirty
    @Published private(set) var searchSnapshots: [UUID: DayEntrySnapshot] = [:]

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

    func lock(_ entry: DayEntry, requiredCount: Int, settings: SettingsStore, modelContext: ModelContext) {
        entry.pruneEmptyOptionalItems(keepingAtLeast: requiredCount)
        entry.updateItemCountPreservingItems(to: requiredCount)
        entry.isLocked = true
        entry.wasCompleted = true
        entry.updatedAt = Date()
        try? modelContext.save()
        searchSnapshots[entry.id] = nil
        AppleSyncManager.shared.captureSnapshotOnLockIfNeeded(
            entry: entry,
            modelContext: modelContext,
            settings: settings,
            isConnected: settings.appleIdConnected
        )
    }

    func unlock(_ entry: DayEntry, settings: SettingsStore, modelContext: ModelContext) {
        if entry.isLocked {
            searchSnapshots[entry.id] = DayEntrySnapshot(from: entry)
            entry.wasCompleted = true
        }
        entry.isLocked = false
        if settings.dailyItemCount > entry.itemCount {
            entry.ensureItemsCount(atLeast: settings.dailyItemCount)
        } else {
            entry.ensureItemsCount(atLeast: entry.itemCount)
        }
        entry.updatedAt = Date()
        try? modelContext.save()
    }

    func searchSnapshot(for entry: DayEntry) -> DayEntrySnapshot? {
        guard !entry.isLocked else { return nil }
        return searchSnapshots[entry.id]
    }

    func updateItem(_ entry: DayEntry, index: Int, text: String, modelContext: ModelContext) {
        guard index >= 0, index < entry.items.count else { return }
        guard entry.items[index] != text else { return }
        entry.items[index] = text
        entry.updatedAt = Date()
        scheduleSave(for: entry, modelContext: modelContext)
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

    func flushPendingSaves(modelContext: ModelContext) {
        pendingSaveTasks.values.forEach { $0.cancel() }
        pendingSaveTasks.removeAll()
        try? modelContext.save()
    }

    func nextDayReminderDate(allEntries: [DayEntry], reminderTime: ReminderTime?, now: Date = Date()) -> Date? {
        guard let reminderTime else { return nil }
        let calendar = Calendar.current
        guard let nextReminder = calendar.nextDate(after: now,
                                                   matching: reminderTime.asDateComponents(),
                                                   matchingPolicy: .nextTimePreservingSmallerComponents) else {
            return nil
        }

        let nextReminderStart = startOfDay(nextReminder)
        guard let targetDay = calendar.date(byAdding: .day, value: -1, to: nextReminderStart) else {
            return nil
        }

        if let entry = allEntries.first(where: { $0.day == targetDay }) {
            return entry.isLocked ? nil : nextReminder
        }

        return nextReminder
    }

    func limitedFinishedEntries(from entries: [DayEntry]) -> [DayEntry] {
        let sortedByNewest = entries.sorted { $0.day > $1.day }
        switch finishedLimit {
        case .all:
            return sortedByNewest
        default:
            return Array(sortedByNewest.prefix(finishedLimit.rawValue))
        }
    }

    private func scheduleSave(for entry: DayEntry, modelContext: ModelContext) {
        let entryID = entry.id
        pendingSaveTasks[entryID]?.cancel()
        pendingSaveTasks[entryID] = Task { [weak self] in
            try? await Task.sleep(nanoseconds: SaveConstants.debounceNanoseconds)
            await MainActor.run {
                try? modelContext.save()
                self?.pendingSaveTasks[entryID] = nil
            }
        }
    }
}
