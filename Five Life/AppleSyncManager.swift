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

    init(id: UUID,
         day: Date,
         itemCount: Int,
         items: [String],
         isLocked: Bool,
         wasCompleted: Bool,
         score: Int?,
         createdAt: Date,
         updatedAt: Date) {
        self.id = id
        self.day = day
        self.itemCount = itemCount
        self.items = items
        self.isLocked = isLocked
        self.wasCompleted = wasCompleted
        self.score = score
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    init(from entry: DayEntry) {
        id = entry.id
        day = entry.day
        let clampedCount = max(1, min(10, entry.itemCount))
        itemCount = clampedCount
        if entry.items.count > clampedCount {
            items = Array(entry.items.prefix(clampedCount))
        } else if entry.items.count < clampedCount {
            items = entry.items + Array(repeating: "", count: clampedCount - entry.items.count)
        } else {
            items = entry.items
        }
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
                              context: SignInContext) async {
        let localEntries = fetchEntries(modelContext: modelContext)
        switch context {
        case .initialConnect:
            if let snapshot = await loadSnapshotWithRetry(), !snapshot.entries.isEmpty {
                replaceLocalEntries(with: snapshot.entries, modelContext: modelContext)
                ensureTodayEntry(modelContext: modelContext, settings: settings)
                return
            }
            resetToFreshStart(modelContext: modelContext, settings: settings)
        case .deferredConnect:
            let snapshot = await loadSnapshotWithRetry()
            if let snapshot, !snapshot.entries.isEmpty {
                let appleLineCount = storedLineCount(for: snapshot.entries)
                let localLineCount = storedLineCount(for: localEntries)
                if appleLineCount > localLineCount {
                    replaceLocalEntries(with: snapshot.entries, modelContext: modelContext)
                    ensureTodayEntry(modelContext: modelContext, settings: settings)
                    return
                }
            }

            if hasMeaningfulLocalData(localEntries, settings: settings) {
                ensureTodayEntry(modelContext: modelContext, settings: settings)
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
        return try? configuredDecoder().decode(AppleSnapshot.self, from: data)
    }

    private func saveSnapshot(from entries: [DayEntry]) {
        let snapshots = entries.map { DayEntrySnapshot(from: $0) }
        let snapshot = AppleSnapshot(entries: snapshots, savedAt: Date())
        guard let data = try? configuredEncoder().encode(snapshot) else { return }
        store.set(data, forKey: snapshotKey)
        store.synchronize()
    }

    private func loadSnapshotWithRetry() async -> AppleSnapshot? {
        if let snapshot = loadSnapshot() {
            return snapshot
        }
        let delays: [TimeInterval] = [0.5, 1, 2, 4, 8]
        for delay in delays {
            await waitForExternalChangeOrDelay(delay)
            if let snapshot = loadSnapshot() {
                return snapshot
            }
        }
        return nil
    }

    private func waitForExternalChangeOrDelay(_ delay: TimeInterval) async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                let nanoseconds = UInt64(delay * 1_000_000_000)
                try? await Task.sleep(nanoseconds: nanoseconds)
            }
            group.addTask { [store] in
                let stream = AsyncStream<Void> { continuation in
                    let token = NotificationCenter.default.addObserver(
                        forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
                        object: store,
                        queue: .main
                    ) { _ in
                        continuation.yield()
                        continuation.finish()
                    }
                    continuation.onTermination = { _ in
                        NotificationCenter.default.removeObserver(token)
                    }
                }
                for await _ in stream {
                    break
                }
            }
            await group.next()
            group.cancelAll()
        }
    }

    private func configuredEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            var container = encoder.singleValueContainer()
            try container.encode(formatter.string(from: date))
        }
        return encoder
    }

    private func configuredDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let container = try decoder.singleValueContainer()
            if let string = try? container.decode(String.self),
               let date = formatter.date(from: string) {
                return date
            }
            if let timestamp = try? container.decode(Double.self) {
                return Date(timeIntervalSinceReferenceDate: timestamp)
            }
            if let timestamp = try? container.decode(Int.self) {
                return Date(timeIntervalSinceReferenceDate: Double(timestamp))
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date value")
        }
        return decoder
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
            let sanitizedSnapshot = sanitizeSnapshot(snapshot)
            let entry = DayEntry(day: sanitizedSnapshot.day, itemCount: sanitizedSnapshot.itemCount)
            entry.id = sanitizedSnapshot.id
            entry.items = sanitizedSnapshot.items
            entry.isLocked = sanitizedSnapshot.isLocked
            entry.wasCompleted = sanitizedSnapshot.wasCompleted
            entry.score = sanitizedSnapshot.score
            entry.createdAt = sanitizedSnapshot.createdAt
            entry.updatedAt = sanitizedSnapshot.updatedAt
            modelContext.insert(entry)
        }
        try? modelContext.save()
    }

    private func sanitizeSnapshot(_ snapshot: DayEntrySnapshot) -> DayEntrySnapshot {
        let clampedCount = max(1, min(10, snapshot.itemCount))
        var sanitizedItems = snapshot.items
        if sanitizedItems.count > clampedCount {
            sanitizedItems = Array(sanitizedItems.prefix(clampedCount))
        } else if sanitizedItems.count < clampedCount {
            sanitizedItems.append(contentsOf: Array(repeating: "", count: clampedCount - sanitizedItems.count))
        }
        return DayEntrySnapshot(
            id: snapshot.id,
            day: snapshot.day,
            itemCount: clampedCount,
            items: sanitizedItems,
            isLocked: snapshot.isLocked,
            wasCompleted: snapshot.wasCompleted,
            score: snapshot.score,
            createdAt: snapshot.createdAt,
            updatedAt: snapshot.updatedAt
        )
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

    private func storedLineCount(for entries: [DayEntrySnapshot]) -> Int {
        entries.reduce(0) { total, entry in
            total + entry.items.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count
        }
    }

    private func storedLineCount(for entries: [DayEntry]) -> Int {
        entries.reduce(0) { total, entry in
            total + entry.items.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count
        }
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
