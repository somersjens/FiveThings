//NEW DOC  AppleSyncManager.swift
import Foundation
import SwiftData

struct DayEntrySnapshot: Codable {
    var id: UUID
    var day: Date
    var itemCount: Int
    var items: [String]
    var isLocked: Bool
    var wasCompleted: Bool
    var score: Int?
    var createdAt: Date
    var updatedAt: Date

    init(from entry: DayEntry) {
        id = entry.id
        day = entry.day
        itemCount = entry.itemCount
        items = entry.items
        isLocked = entry.isLocked
        wasCompleted = entry.wasCompleted
        score = entry.score
        createdAt = entry.createdAt
        updatedAt = entry.updatedAt
    }
}

struct AppleSnapshot: Codable {
    var entries: [DayEntrySnapshot]
    var savedAt: Date
}

@MainActor
final class AppleSyncManager {
    enum SignInContext {
        case initialConnect
        case deferredConnect
    }

    static let shared = AppleSyncManager()

    private let store = NSUbiquitousKeyValueStore.default
    private let snapshotKey = "appleSnapshotData"

    private init() {}

    func reconcileAfterSignIn(modelContext: ModelContext,
                              settings: SettingsStore,
                              context: SignInContext) {
        let localEntries = fetchEntries(modelContext: modelContext)
        if let snapshot = loadSnapshot(), !snapshot.entries.isEmpty {
            replaceLocalEntries(with: snapshot.entries, modelContext: modelContext)
            ensureTodayEntry(modelContext: modelContext, settings: settings)
            return
        }

        switch context {
        case .initialConnect:
            resetToFreshStart(modelContext: modelContext, settings: settings)
        case .deferredConnect:
            if hasMeaningfulLocalData(localEntries, settings: settings) {
                ensureTodayEntry(modelContext: modelContext, settings: settings)
                let refreshedEntries = fetchEntries(modelContext: modelContext)
                saveSnapshot(from: refreshedEntries)
            } else {
                resetToFreshStart(modelContext: modelContext, settings: settings)
            }
        }
    }

    func captureMidnightSnapshotIfNeeded(modelContext: ModelContext,
                                         settings: SettingsStore,
                                         isConnected: Bool) {
        guard isConnected else { return }
        ensureTodayEntry(modelContext: modelContext, settings: settings)
        let entries = fetchEntries(modelContext: modelContext)
        saveSnapshot(from: entries)
    }

    func captureSnapshotNow(modelContext: ModelContext, settings: SettingsStore, isConnected: Bool) {
        guard isConnected else { return }
        ensureTodayEntry(modelContext: modelContext, settings: settings)
        let entries = fetchEntries(modelContext: modelContext)
        saveSnapshot(from: entries)
    }

    private func loadSnapshot() -> AppleSnapshot? {
        store.synchronize()
        guard let data = store.data(forKey: snapshotKey), !data.isEmpty else {
            return nil
        }
        return try? JSONDecoder().decode(AppleSnapshot.self, from: data)
    }

    private func saveSnapshot(from entries: [DayEntry]) {
        let snapshots = entries.map { DayEntrySnapshot(from: $0) }
        let snapshot = AppleSnapshot(entries: snapshots, savedAt: Date())
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        store.set(data, forKey: snapshotKey)
        store.synchronize()
    }

    private func resetToFreshStart(modelContext: ModelContext, settings: SettingsStore) {
        deleteAllEntries(modelContext: modelContext)
        ensureTodayEntry(modelContext: modelContext, settings: settings)
        let entries = fetchEntries(modelContext: modelContext)
        saveSnapshot(from: entries)
    }

    private func replaceLocalEntries(with snapshots: [DayEntrySnapshot], modelContext: ModelContext) {
        deleteAllEntries(modelContext: modelContext)
        snapshots.forEach { snapshot in
            let entry = DayEntry(day: snapshot.day, itemCount: snapshot.itemCount)
            entry.id = snapshot.id
            entry.items = snapshot.items
            entry.isLocked = snapshot.isLocked
            entry.wasCompleted = snapshot.wasCompleted
            entry.score = snapshot.score
            entry.createdAt = snapshot.createdAt
            entry.updatedAt = snapshot.updatedAt
            modelContext.insert(entry)
        }
        try? modelContext.save()
    }

    private func deleteAllEntries(modelContext: ModelContext) {
        let entries = fetchEntries(modelContext: modelContext)
        entries.forEach { _ = $0.items.count }
        entries.forEach { modelContext.delete($0) }
        try? modelContext.save()
    }

    private func fetchEntries(modelContext: ModelContext) -> [DayEntry] {
        let descriptor = FetchDescriptor<DayEntry>()
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    private func hasMeaningfulLocalData(_ entries: [DayEntry], settings: SettingsStore) -> Bool {
        guard !entries.isEmpty else { return false }
        if entries.count > 1 {
            return true
        }

        guard let entry = entries.first else { return false }
        if entry.isLocked || entry.wasCompleted || entry.score != nil {
            return true
        }

        if entry.items.contains(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            return true
        }

        let today = Calendar.current.startOfDay(for: Date())
        if !Calendar.current.isDate(entry.day, inSameDayAs: today) {
            return true
        }

        return entry.itemCount != settings.dailyItemCount
    }

    private func ensureTodayEntry(modelContext: ModelContext, settings: SettingsStore) {
        settings.clampDailyCount()
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let descriptor = FetchDescriptor<DayEntry>(
            predicate: #Predicate { $0.day == today }
        )
        if let existing = try? modelContext.fetch(descriptor).first {
            if !existing.isLocked {
                existing.resizeItemsIfNeeded(to: settings.dailyItemCount)
            }
            return
        }

        let entry = DayEntry(day: today, itemCount: settings.dailyItemCount)
        modelContext.insert(entry)
        try? modelContext.save()
    }
}
