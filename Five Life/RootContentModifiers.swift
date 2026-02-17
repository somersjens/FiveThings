import SwiftData
import SwiftUI

struct RootContentBaseModifier: ViewModifier {
    let mainBackground: Color
    let hasSeenAccessScreen: Bool
    let headerView: AnyView
    let shareSheetItem: Binding<ShareSheetItem?>
    let lockOverlay: AnyView

    func body(content: Content) -> some View {
        content
            .background(mainBackground.ignoresSafeArea())
            .safeAreaInset(edge: .top) {
                if hasSeenAccessScreen {
                    headerView
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: shareSheetItem) { item in
                ShareSheet(items: item.items)
            }
            .overlay {
                if hasSeenAccessScreen {
                    lockOverlay
                }
            }
    }
}

struct RootContentTaskModifier: ViewModifier {
    private let autoEntryAnimation = Animation.snappy(duration: 0.34, extraBounce: 0)

    let settings: SettingsStore
    let vm: ContentViewModel
    let notifier: NotificationManager
    let modelContext: ModelContext
    let entries: [DayEntry]
    let refreshEntryLists: () -> Void
    let scheduleMidnightRefresh: () -> Void

    func body(content: Content) -> some View {
        content.task {
            let didCreateTodayEntry = withAnimation(autoEntryAnimation) {
                vm.ensureTodayEntry(modelContext: modelContext, settings: settings)
            }
            if didCreateTodayEntry {
                refreshEntryLists()
            }
            await notifier.refreshAuthorizationStatus()
            let dailyReminderDate = vm.dailyReminderDate(allEntries: entries,
                                                         reminderTime: settings.dailyReminderTime)
            await notifier.scheduleDailyReminder(time: settings.dailyReminderTime,
                                                 reminderDate: dailyReminderDate,
                                                 language: settings.language,
                                                 dailyCount: settings.dailyItemCount)

            let nextReminderDate = vm.nextDayReminderDate(allEntries: entries,
                                                          reminderTime: settings.nextDayReminderTime)
            await notifier.scheduleNextDayIfNeeded(time: settings.nextDayReminderTime,
                                                  reminderDate: nextReminderDate,
                                                  language: settings.language,
                                                  dailyCount: settings.dailyItemCount)
            scheduleMidnightRefresh()
            refreshEntryLists()
        }
    }
}

struct RootContentEntriesChangeModifier: ViewModifier {
    let settings: SettingsStore
    let vm: ContentViewModel
    let notifier: NotificationManager
    let entries: [DayEntry]
    let refreshEntryLists: () -> Void

    func body(content: Content) -> some View {
        content
            .onChange(of: entries.count) { _, _ in
                // Keep “next day if needed” in sync when entries are created or removed.
                Task {
                    let dailyReminderDate = vm.dailyReminderDate(allEntries: entries,
                                                                 reminderTime: settings.dailyReminderTime)
                    await notifier.scheduleDailyReminder(time: settings.dailyReminderTime,
                                                         reminderDate: dailyReminderDate,
                                                         language: settings.language,
                                                         dailyCount: settings.dailyItemCount)
                    let nextReminderDate = vm.nextDayReminderDate(allEntries: entries,
                                                                  reminderTime: settings.nextDayReminderTime)
                    await notifier.scheduleNextDayIfNeeded(time: settings.nextDayReminderTime,
                                                          reminderDate: nextReminderDate,
                                                          language: settings.language,
                                                          dailyCount: settings.dailyItemCount)
                }
                refreshEntryLists()
            }
            .onChange(of: entries.map(\.isLocked)) { _, _ in
                Task {
                    let dailyReminderDate = vm.dailyReminderDate(allEntries: entries,
                                                                 reminderTime: settings.dailyReminderTime)
                    await notifier.scheduleDailyReminder(time: settings.dailyReminderTime,
                                                         reminderDate: dailyReminderDate,
                                                         language: settings.language,
                                                         dailyCount: settings.dailyItemCount)
                    let nextReminderDate = vm.nextDayReminderDate(allEntries: entries,
                                                                  reminderTime: settings.nextDayReminderTime)
                    await notifier.scheduleNextDayIfNeeded(time: settings.nextDayReminderTime,
                                                          reminderDate: nextReminderDate,
                                                          language: settings.language,
                                                          dailyCount: settings.dailyItemCount)
                }
                refreshEntryLists()
            }
            .onChange(of: entries.map(\.day)) { _, _ in
                refreshEntryLists()
            }
            .onChange(of: entries.map(\.updatedAt)) { _, _ in
                refreshEntryLists()
            }
            .onChange(of: entries.map(\.wasCompleted)) { _, _ in
                refreshEntryLists()
            }
    }
}

struct RootContentSettingsChangeModifier: ViewModifier {
    let settings: SettingsStore
    let vm: ContentViewModel
    let notifier: NotificationManager
    let modelContext: ModelContext
    let entries: [DayEntry]
    let unfinishedEntries: [DayEntry]
    let refreshEntryLists: () -> Void
    let showNextSeeYouTomorrowMessage: () -> Void

    private func rescheduleReminders() {
        Task {
            let dailyReminderDate = vm.dailyReminderDate(allEntries: entries,
                                                         reminderTime: settings.dailyReminderTime)
            await notifier.scheduleDailyReminder(time: settings.dailyReminderTime,
                                                 reminderDate: dailyReminderDate,
                                                 language: settings.language,
                                                 dailyCount: settings.dailyItemCount)
            let nextReminderDate = vm.nextDayReminderDate(allEntries: entries,
                                                          reminderTime: settings.nextDayReminderTime)
            await notifier.scheduleNextDayIfNeeded(time: settings.nextDayReminderTime,
                                                   reminderDate: nextReminderDate,
                                                   language: settings.language,
                                                   dailyCount: settings.dailyItemCount)
        }
    }

    func body(content: Content) -> some View {
        content
            .onChange(of: settings.dailyItemCount) { _, _ in
                vm.ensureTodayEntry(modelContext: modelContext, settings: settings)
                refreshEntryLists()
                rescheduleReminders()
            }
            .onChange(of: settings.dailyReminderTime) { _, _ in
                rescheduleReminders()
            }
            .onChange(of: settings.nextDayReminderTime) { _, _ in
                rescheduleReminders()
            }
            .onChange(of: vm.searchText) { _, _ in
                refreshEntryLists()
            }
            .onChange(of: vm.newestFirst) { _, _ in
                refreshEntryLists()
            }
            .onChange(of: vm.finishedLimit) { _, _ in
                refreshEntryLists()
            }
            .onChange(of: settings.language) { _, _ in
                refreshEntryLists()
                rescheduleReminders()
                if unfinishedEntries.isEmpty {
                    showNextSeeYouTomorrowMessage()
                }
            }
            .onChange(of: settings.moonEnabled) { _, _ in
                refreshEntryLists()
            }
            .onChange(of: settings.holidaysEnabled) { _, _ in
                refreshEntryLists()
            }
    }
}

struct RootContentUnfinishedChangeModifier: ViewModifier {
    @Binding var lastUnfinishedCount: Int
    let unfinishedEntries: [DayEntry]
    let showNextSeeYouTomorrowMessage: () -> Void

    func body(content: Content) -> some View {
        content.onChange(of: unfinishedEntries.count) { oldValue, newValue in
            if newValue == 0, oldValue > 0 {
                showNextSeeYouTomorrowMessage()
            }
            lastUnfinishedCount = newValue
        }
    }
}

struct RootContentLifecycleModifier: ViewModifier {
    @Binding var hasAppeared: Bool
    @Binding var isUnlocked: Bool
    @Binding var lastUnfinishedCount: Int

    let settings: SettingsStore
    let unfinishedEntries: [DayEntry]
    let updateUnlockStateIfNeeded: () -> Void
    let showNextSeeYouTomorrowMessage: () -> Void

    func body(content: Content) -> some View {
        content
            .onAppear {
                if !hasAppeared {
                    hasAppeared = true
                    if settings.faceIdLockEnabled {
                        isUnlocked = false
                        updateUnlockStateIfNeeded()
                    }
                }
                if lastUnfinishedCount == -1 {
                    lastUnfinishedCount = unfinishedEntries.count
                    if unfinishedEntries.isEmpty {
                        showNextSeeYouTomorrowMessage()
                    }
                }
            }
            .onChange(of: settings.faceIdLockEnabled) { _, _ in
                if settings.faceIdLockEnabled {
                    isUnlocked = false
                }
                updateUnlockStateIfNeeded()
            }
    }
}

struct RootContentScenePhaseModifier: ViewModifier {
    private let autoEntryAnimation = Animation.snappy(duration: 0.34, extraBounce: 0)

    @Binding var isUnlocked: Bool
    @Binding var midnightTask: Task<Void, Never>?

    let settings: SettingsStore
    let vm: ContentViewModel
    let modelContext: ModelContext
    let scenePhase: ScenePhase
    let refreshEntryLists: () -> Void
    let scheduleMidnightRefresh: () -> Void
    let updateUnlockStateIfNeeded: () -> Void

    func body(content: Content) -> some View {
        content.onChange(of: scenePhase) { _, phase in
            if phase != .active, settings.faceIdLockEnabled {
                isUnlocked = false
            }
            if phase == .active {
                withAnimation(autoEntryAnimation) {
                    vm.ensureTodayEntry(modelContext: modelContext, settings: settings)
                    AppleSyncManager.shared.catchUpSnapshotIfNeeded(
                        modelContext: modelContext,
                        settings: settings,
                        isConnected: settings.appleIdConnected
                    )
                }
                scheduleMidnightRefresh()
                updateUnlockStateIfNeeded()
                refreshEntryLists()
            } else {
                vm.flushPendingSaves(modelContext: modelContext)
                midnightTask?.cancel()
                midnightTask = nil
            }
        }
    }
}
