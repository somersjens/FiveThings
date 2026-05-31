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
        DayIdentity.canonicalDate(for: DayIdentity.identifier(for: date))
    }

    @discardableResult
    func ensureTodayEntry(modelContext: ModelContext, settings: SettingsStore) -> Bool {
        settings.clampDailyCount()

        let todayIdentifier = DayIdentity.todayIdentifier()

        let allEntriesDescriptor = FetchDescriptor<DayEntry>()
        let allEntries = (try? modelContext.fetch(allEntriesDescriptor)) ?? []
        let didNormalizeEntries = normalizeAndMergeDuplicateEntries(allEntries, modelContext: modelContext)
        let activeEntries = (try? modelContext.fetch(allEntriesDescriptor)) ?? allEntries
        let existingDayIdentifiers = Set(activeEntries.map(\.normalizedDayIdentifier))
        let hasHistoryBeforeToday = activeEntries.contains { $0.normalizedDayIdentifier < todayIdentifier }

        var didCreateEntry = false
        var didResizeToday = false

        if let existingToday = activeEntries.first(where: { $0.normalizedDayIdentifier == todayIdentifier }), !existingToday.isLocked {
            let oldItemCount = existingToday.itemCount
            let oldItems = existingToday.items
            existingToday.resizeItemsIfNeeded(to: settings.dailyItemCount)
            didResizeToday = oldItemCount != existingToday.itemCount || oldItems != existingToday.items
        }

        let recentDayIdentifiers = (0..<3)
            .compactMap { DayIdentity.addingDays(-$0, to: todayIdentifier) }
            .reversed()

        for dayIdentifier in recentDayIdentifiers {
            if existingDayIdentifiers.contains(dayIdentifier) {
                continue
            }
            if dayIdentifier != todayIdentifier && !hasHistoryBeforeToday {
                continue
            }

            let entry = DayEntry(dayIdentifier: dayIdentifier, itemCount: settings.dailyItemCount)
            modelContext.insert(entry)
            didCreateEntry = true
        }

        if didCreateEntry || didResizeToday || didNormalizeEntries {
            try? modelContext.save()
        }

        return didCreateEntry
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

        let nextReminderIdentifier = DayIdentity.identifier(for: nextReminder, calendar: calendar)
        guard let targetDayIdentifier = DayIdentity.addingDays(-1, to: nextReminderIdentifier) else {
            return nil
        }

        if let entry = allEntries.first(where: { $0.normalizedDayIdentifier == targetDayIdentifier }) {
            return entry.isLocked ? nil : nextReminder
        }

        return nextReminder
    }

    func dailyReminderDate(allEntries: [DayEntry], reminderTime: ReminderTime?, now: Date = Date()) -> Date? {
        guard let reminderTime else { return nil }
        let calendar = Calendar.current
        guard var nextReminder = calendar.nextDate(after: now,
                                                   matching: reminderTime.asDateComponents(),
                                                   matchingPolicy: .nextTimePreservingSmallerComponents) else {
            return nil
        }

        for _ in 0..<370 {
            let reminderDayIdentifier = DayIdentity.identifier(for: nextReminder, calendar: calendar)
            if let entry = allEntries.first(where: { $0.normalizedDayIdentifier == reminderDayIdentifier }), entry.isLocked {
                guard let shifted = calendar.date(byAdding: .day, value: 1, to: nextReminder) else {
                    return nil
                }
                nextReminder = shifted
                continue
            }
            return nextReminder
        }

        return nil
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

    private func normalizeAndMergeDuplicateEntries(_ entries: [DayEntry], modelContext: ModelContext) -> Bool {
        var didChange = false
        var entriesByIdentifier: [String: DayEntry] = [:]

        for entry in entries {
            didChange = entry.normalizeDayIdentity() || didChange
            let identifier = entry.normalizedDayIdentifier
            guard let existing = entriesByIdentifier[identifier] else {
                entriesByIdentifier[identifier] = entry
                continue
            }

            let keeper = preferredEntry(existing, entry)
            let duplicate = keeper === existing ? entry : existing
            merge(duplicate, into: keeper)
            modelContext.delete(duplicate)
            entriesByIdentifier[identifier] = keeper
            didChange = true
        }

        return didChange
    }

    private func preferredEntry(_ lhs: DayEntry, _ rhs: DayEntry) -> DayEntry {
        let lhsMeaningful = isMeaningful(lhs)
        let rhsMeaningful = isMeaningful(rhs)
        if lhsMeaningful != rhsMeaningful {
            return lhsMeaningful ? lhs : rhs
        }
        return lhs.updatedAt >= rhs.updatedAt ? lhs : rhs
    }

    private func isMeaningful(_ entry: DayEntry) -> Bool {
        if entry.isLocked || entry.wasCompleted || entry.score != nil { return true }
        return entry.items.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private func merge(_ duplicate: DayEntry, into keeper: DayEntry) {
        guard duplicate !== keeper else { return }
        if !isMeaningful(keeper), isMeaningful(duplicate) {
            keeper.itemCount = duplicate.itemCount
            keeper.items = duplicate.items
            keeper.isLocked = duplicate.isLocked
            keeper.wasCompleted = duplicate.wasCompleted
            keeper.score = duplicate.score
        } else {
            keeper.itemCount = max(keeper.itemCount, duplicate.itemCount)
            keeper.ensureItemsCount(atLeast: keeper.itemCount)
            for (index, item) in duplicate.items.enumerated() where index < keeper.items.count {
                if keeper.items[index].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                   !item.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    keeper.items[index] = item
                }
            }
            keeper.isLocked = keeper.isLocked || duplicate.isLocked
            keeper.wasCompleted = keeper.wasCompleted || duplicate.wasCompleted
            keeper.score = keeper.score ?? duplicate.score
        }
        keeper.createdAt = min(keeper.createdAt, duplicate.createdAt)
        keeper.updatedAt = max(keeper.updatedAt, duplicate.updatedAt)
        _ = duplicate.items.count
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
