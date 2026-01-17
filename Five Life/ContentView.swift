//NEW DOC  ContentView.swift
import LocalAuthentication
import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext

    @StateObject private var settings = SettingsStore()
    @StateObject private var vm = ContentViewModel()
    @StateObject private var notifier = NotificationManager.shared

    @Query(sort: \DayEntry.day, order: .reverse) private var entries: [DayEntry]

    @Namespace private var cardNamespace

    @State private var showSettings: Bool = false
    @State private var isUnlocked: Bool = true
    @State private var isUnlocking: Bool = false
    @State private var hasAppeared: Bool = false
    @State private var midnightTask: Task<Void, Never>?
    @State private var cachedUnfinishedEntryIDs: [UUID] = []
    @State private var cachedFinishedEntryIDs: [UUID] = []
    @AppStorage("hasSeenAccessScreen") private var hasSeenAccessScreen: Bool = false

    @Environment(\.scenePhase) private var scenePhase

    private static let numericDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "dd-MM-yyyy"
        return formatter
    }()

    private var unfinished: [DayEntry] {
        entries
            .filter { !$0.isLocked }
            .sorted { $0.day > $1.day }
    }

    private var finished: [DayEntry] {
        let base = entries.filter { $0.isLocked }
        let limited = vm.limitedFinishedEntries(from: base)
        let sorted = limited.sorted { vm.newestFirst ? ($0.day > $1.day) : ($0.day < $1.day) }
        let normalizedQuery = vm.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else { return sorted }
        return sorted.filter { entry in
            entryMatchesSearch(entry, normalizedQuery: normalizedQuery)
        }
    }

    private func entryMatchesSearch(_ entry: DayEntry, normalizedQuery: String) -> Bool {
        guard !normalizedQuery.isEmpty else { return true }

        if entry.items.joined(separator: " ")
            .range(of: normalizedQuery, options: [.caseInsensitive, .diacriticInsensitive]) != nil {
            return true
        }

        let dayString = DateFormatting.formattedDayString(entry.day, language: settings.language)
        if dayString.range(of: normalizedQuery, options: [.caseInsensitive, .diacriticInsensitive]) != nil {
            return true
        }

        let numericDate = ContentView.numericDateFormatter.string(from: entry.day)
        if numericDate.range(of: normalizedQuery, options: [.caseInsensitive, .diacriticInsensitive]) != nil {
            return true
        }

        if settings.moonEnabled {
            let phase = MoonPhase.phase(on: entry.day)
            let phaseName = phase.localizedName(language: settings.language)
            if phaseName.range(of: normalizedQuery, options: [.caseInsensitive, .diacriticInsensitive]) != nil {
                return true
            }
        }

        if settings.holidaysEnabled {
            let holidayNames = HolidayProvider.holidayNames(on: entry.day, language: settings.language)
            if holidayNames.contains(where: { name in
                name.range(of: normalizedQuery, options: [.caseInsensitive, .diacriticInsensitive]) != nil
            }) {
                return true
            }
        }

        if settings.scoreEnabled,
           let score = entry.score,
           let queryScore = Int(normalizedQuery.trimmingCharacters(in: .whitespacesAndNewlines)),
           (1...10).contains(queryScore),
           score == queryScore {
            return true
        }

        return false
    }

    private var dailyTitle: String {
        let count = settings.dailyItemCount
        return settings.language == .dutch ? "Elke dag \(count)" : "\(count) Things everyday"
    }

    private var lifeTitle: String {
        let word = numberWord(for: settings.dailyItemCount)
        return "Happy \(word)"
    }

    private struct StatisticsSnapshot {
        let streak: Int
        let days: Int
        let entries: Int
    }

    private var completedEntries: [DayEntry] {
        entries.filter { $0.isLocked || $0.wasCompleted }
    }

    private var statisticsSnapshot: StatisticsSnapshot {
        let completed = completedEntries
        let totalDays = completed.count
        let totalEntries = completed.reduce(0) { $0 + $1.itemCount }
        let streak = calculateStreak(from: completed)
        return StatisticsSnapshot(streak: streak, days: totalDays, entries: totalEntries)
    }

    private var reviewURL: URL {
        URL(string: "https://example.com/review")!
    }

    private var shareURL: URL {
        URL(string: "https://example.com/share")!
    }

    private var feedbackURL: URL {
        URL(string: "https://example.com/feedback")!
    }

    private var footerLinks: some View {
        VStack(spacing: 16) {
            HStack(spacing: 4) {
                Link(destination: reviewURL) {
                    Text(settings.language == .dutch ? "Schrijf een review" : "Write a review")
                        .foregroundStyle(.primary)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.plain)

                Text("|")

                Link(destination: shareURL) {
                    Text(settings.language == .dutch ? "Deel met vrienden" : "Share the friends")
                        .foregroundStyle(.primary)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.plain)

                Text("|")

                Link(destination: feedbackURL) {
                    Text(settings.language == .dutch ? "Stuur feedback" : "Send feedback")
                        .foregroundStyle(.primary)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity)
            .multilineTextAlignment(.center)
        }
        .font(.footnote.weight(.semibold))
        .foregroundStyle(.secondary)
    }

    private func calculateStreak(from entries: [DayEntry]) -> Int {
        let calendar = Calendar.current
        let uniqueDays = Array(Set(entries.map { calendar.startOfDay(for: $0.day) }))
            .sorted(by: >)
        guard let mostRecent = uniqueDays.first else { return 0 }
        var streak = 1
        var currentDay = mostRecent
        for day in uniqueDays.dropFirst() {
            guard let expected = calendar.date(byAdding: .day, value: -1, to: currentDay) else {
                break
            }
            if calendar.isDate(day, inSameDayAs: expected) {
                streak += 1
                currentDay = day
            } else {
                break
            }
        }
        return streak
    }

    private func numberWord(for count: Int) -> String {
        switch count {
        case 1: return "One"
        case 2: return "Two"
        case 3: return "Three"
        case 4: return "Four"
        case 5: return "Five"
        case 6: return "Six"
        case 7: return "Seven"
        case 8: return "Eight"
        case 9: return "Nine"
        case 10: return "Ten"
        default: return "\(count)"
        }
    }

    private var headerView: some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                showSettings.toggle()
            }
        } label: {
            ZStack {
                HStack(spacing: 6) {
                    Text(lifeTitle)
                        .font(.title.bold())

                    Image("NoBackground")
                        .resizable()
                        .scaledToFit()
                        .frame(height: 24)
                        .accessibilityHidden(true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .overlay(alignment: .trailing) {
                Image(systemName: "gearshape.fill")
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.brandBackground)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(settings.language == .dutch ? "Instellingen tonen" : "Show settings")
    }

    private var statisticsRow: some View {
        let stats = statisticsSnapshot
        let streakLabel = settings.language == .dutch ? "Streak" : "Streak"
        let daysLabel = settings.language == .dutch ? "Dagen" : "Days"
        let entriesLabel = settings.language == .dutch ? "Items" : "Entries"
        return HStack(spacing: 6) {
            Text("\(streakLabel): \(stats.streak)")
            Text("|")
                .foregroundStyle(.secondary)
            Text("\(daysLabel): \(stats.days)")
            Text("|")
                .foregroundStyle(.secondary)
            Text("\(entriesLabel): \(stats.entries)")
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.black)
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var lockOverlay: some View {
        if settings.faceIdLockEnabled && !isUnlocked {
            Color.brandBackground
                .ignoresSafeArea()

            VStack(spacing: 16) {
                Image(systemName: "faceid")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)

                Text(settings.language == .dutch ? "Ontgrendel met Face ID" : "Unlock with Face ID")
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.center)

                Button {
                    attemptUnlock()
                } label: {
                    Text(settings.language == .dutch ? "Ontgrendel" : "Unlock")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(.secondary.opacity(0.12))
                        )
                }
                .disabled(isUnlocking)
            }
            .padding(24)
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                ScrollViewReader { proxy in
                    ScrollView(showsIndicators: false) {
                        let unfinishedEntries = cachedUnfinishedEntryIDs.compactMap { id in
                            entries.first { $0.id == id }
                        }
                        let finishedEntries = cachedFinishedEntryIDs.compactMap { id in
                            entries.first { $0.id == id }
                        }
                        LazyVStack(alignment: .leading, spacing: 14) {
                            Color.clear
                                .frame(height: 0)
                                .id("settingsTop")

                            if showSettings {
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Text(settings.language == .dutch ? "Instellingen" : "Settings")
                                            .font(.title3.weight(.semibold))
                                        Spacer()
                                        Image(systemName: "gearshape.fill")
                                            .font(.system(size: 18, weight: .semibold))
                                            .foregroundStyle(Color(.systemGray))
                                            .onTapGesture {
                                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                                    showSettings = false
                                                }
                                            }
                                    }
                                    .frame(height: 44)
                                    .padding(.horizontal, 28)
                                    .padding(.top, 4)

                                    VStack(spacing: 16) {
                                        SettingsView(settings: settings, showsNavigation: false)

                                        Button {
                                            // TODO: Export action
                                        } label: {
                                            Text(settings.language == .dutch
                                                 ? "Exporteren naar PDF/CSV"
                                                 : "Export to PDF/CSV")
                                                .font(.headline)
                                                .frame(maxWidth: .infinity)
                                                .padding(.vertical, 10)
                                                .background(
                                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                                        .fill(Color.brandAccent.opacity(0.2))
                                                )
                                        }
                                        .buttonStyle(.plain)
                                        .frame(maxWidth: 260)
                                        .padding(.bottom, 6)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.horizontal, 14)
                                    .padding(.top, 8)
                                    .padding(.bottom, 14)
                                    .background(
                                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                                            .fill(Color(.systemBackground))
                                    )
                                    .padding(.horizontal, 14)
                                    .padding(.bottom, 14)
                                }
                                .padding(.top, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                                        .fill(Color(.systemGray6))
                                        .shadow(radius: 6, y: 2)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                                        .strokeBorder(Color.gray.opacity(0.3), lineWidth: 2)
                                )
                                .transition(.move(edge: .top).combined(with: .opacity))
                            }

                        // Unfinished section
                        if !unfinishedEntries.isEmpty {
                            LazyVStack(alignment: .leading, spacing: 10) {
                                ForEach(unfinishedEntries) { entry in
                                    DayCardView(settings: settings, vm: vm, entry: entry)
                                        .matchedGeometryEffect(id: entry.id, in: cardNamespace)
                                        .transition(.opacity)
                                }
                            }
                            .animation(.spring(response: 0.5, dampingFraction: 0.85),
                                       value: unfinishedEntries.map(\.id))
                        } else {
                            Text(settings.language == .dutch ? "Tot morgen!" : "See you tomorrow!")
                                .font(.title3.weight(.semibold))
                                .frame(maxWidth: .infinity, alignment: .center)
                                .multilineTextAlignment(.center)
                                .padding(.vertical, 8)
                        }

                        // Thick divider
                        Rectangle()
                            .fill(Color.brandAccent)
                            .frame(height: 6)
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            .padding(.top, 8)

                        if settings.statisticsEnabled {
                            statisticsRow
                        }

                        // Search + sort (finished only)
                        SearchAndSortBar(settings: settings,
                                         text: $vm.searchText,
                                         newestFirst: $vm.newestFirst,
                                         finishedLimit: $vm.finishedLimit)

                        // Finished section
                        LazyVStack(alignment: .leading, spacing: 10) {
                            if finishedEntries.isEmpty {
                                Text(settings.language == .dutch
                                     ? "Geen kaarten gevonden."
                                     : "No cards found.")
                                    .foregroundStyle(.black)
                                    .padding(.horizontal, 4)
                            } else {
                                ForEach(finishedEntries) { entry in
                                    DayCardView(settings: settings, vm: vm, entry: entry)
                                        .matchedGeometryEffect(id: entry.id, in: cardNamespace)
                                        .transition(.opacity)
                                }
                            }
                        }
                        .animation(.spring(response: 0.5, dampingFraction: 0.85),
                                   value: finishedEntries.map(\.id))
                        .animation(.spring(response: 0.5, dampingFraction: 0.85), value: vm.searchText)
                        .animation(.spring(response: 0.5, dampingFraction: 0.85), value: vm.newestFirst)
                        .animation(.spring(response: 0.5, dampingFraction: 0.85), value: vm.finishedLimit)

                        // Footer links
                        VStack(spacing: 10) {
                            Divider().opacity(0.6)
                            footerLinks
                        }
                        .padding(.top, 10)
                    }
                        .padding(16)
                    }
                    .onChange(of: showSettings) { _, expanded in
                        if expanded {
                            withAnimation(.easeInOut(duration: 0.6)) {
                                proxy.scrollTo("settingsTop", anchor: .top)
                            }
                        } else {
                            // Apply notification changes after closing settings
                            Task {
                                await notifier.scheduleDailyReminder(time: settings.dailyReminderTime,
                                                                    language: settings.language,
                                                                    dailyCount: settings.dailyItemCount)
                                let shouldScheduleNext = vm.shouldScheduleNextDayReminder(allEntries: entries)
                                await notifier.scheduleNextDayIfNeeded(time: settings.nextDayReminderTime,
                                                                      shouldSchedule: shouldScheduleNext,
                                                                      language: settings.language)
                            }
                        }
                    }
                }

                if !hasSeenAccessScreen {
                    AccessScreenView(settings: settings, hasSeenAccessScreen: $hasSeenAccessScreen)
                        .transition(.opacity)
                }
            }
            .background(Color.brandBackground.ignoresSafeArea())
            .safeAreaInset(edge: .top) {
                if hasSeenAccessScreen {
                    headerView
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .overlay {
                if hasSeenAccessScreen {
                    lockOverlay
                }
            }
            .task {
                vm.ensureTodayEntry(modelContext: modelContext, settings: settings)
                await notifier.refreshAuthorizationStatus()
                await notifier.scheduleDailyReminder(time: settings.dailyReminderTime,
                                                    language: settings.language,
                                                    dailyCount: settings.dailyItemCount)

                let shouldScheduleNext = vm.shouldScheduleNextDayReminder(allEntries: entries)
                await notifier.scheduleNextDayIfNeeded(time: settings.nextDayReminderTime,
                                                      shouldSchedule: shouldScheduleNext,
                                                      language: settings.language)
                scheduleMidnightRefresh()
                refreshEntryLists()
            }
            .onChange(of: entries.count) { _, _ in
                // Keep “next day if needed” in sync when entries are created/locked/unlocked.
                Task {
                    let shouldScheduleNext = vm.shouldScheduleNextDayReminder(allEntries: entries)
                    await notifier.scheduleNextDayIfNeeded(time: settings.nextDayReminderTime,
                                                          shouldSchedule: shouldScheduleNext,
                                                          language: settings.language)
                }
                refreshEntryLists()
            }
            .onChange(of: entries.map(\.isLocked)) { _, _ in
                refreshEntryLists()
            }
            .onChange(of: entries.map(\.day)) { _, _ in
                refreshEntryLists()
            }
            .onChange(of: settings.dailyItemCount) { _, _ in
                vm.ensureTodayEntry(modelContext: modelContext, settings: settings)
                Task {
                    await notifier.scheduleDailyReminder(time: settings.dailyReminderTime,
                                                        language: settings.language,
                                                        dailyCount: settings.dailyItemCount)
                }
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
            }
            .onChange(of: settings.moonEnabled) { _, _ in
                refreshEntryLists()
            }
            .onChange(of: settings.holidaysEnabled) { _, _ in
                refreshEntryLists()
            }
            .onAppear {
                if !hasAppeared {
                    hasAppeared = true
                    if settings.faceIdLockEnabled {
                        isUnlocked = false
                        updateUnlockStateIfNeeded()
                    }
                }
            }
            .onChange(of: settings.faceIdLockEnabled) { _, _ in
                if settings.faceIdLockEnabled {
                    isUnlocked = false
                }
                updateUnlockStateIfNeeded()
            }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active, settings.faceIdLockEnabled {
                    isUnlocked = false
                }
                if phase == .active {
                    vm.ensureTodayEntry(modelContext: modelContext, settings: settings)
                    scheduleMidnightRefresh()
                    updateUnlockStateIfNeeded()
                } else {
                    vm.flushPendingSaves(modelContext: modelContext)
                    midnightTask?.cancel()
                    midnightTask = nil
                }
            }
        }
    }

    private func scheduleMidnightRefresh() {
        midnightTask?.cancel()
        midnightTask = Task {
            while !Task.isCancelled {
                let interval = secondsUntilNextDay()
                let sleepTime = UInt64(interval * 1_000_000_000)
                try? await Task.sleep(nanoseconds: sleepTime)
                if Task.isCancelled {
                    return
                }
                await MainActor.run {
                    vm.ensureTodayEntry(modelContext: modelContext, settings: settings)
                    AppleSyncManager.shared.captureMidnightSnapshotIfNeeded(
                        modelContext: modelContext,
                        settings: settings,
                        isConnected: settings.appleIdConnected
                    )
                }
                let shouldScheduleNext = await MainActor.run {
                    vm.shouldScheduleNextDayReminder(allEntries: entries)
                }
                await notifier.scheduleNextDayIfNeeded(time: settings.nextDayReminderTime,
                                                      shouldSchedule: shouldScheduleNext,
                                                      language: settings.language)
            }
        }
    }

    private func secondsUntilNextDay() -> TimeInterval {
        let calendar = Calendar.current
        let now = Date()
        let todayStart = calendar.startOfDay(for: now)
        let tomorrowStart = calendar.date(byAdding: .day, value: 1, to: todayStart) ?? todayStart.addingTimeInterval(86_400)
        let interval = tomorrowStart.timeIntervalSince(now)
        return max(interval, 1)
    }

    private func updateUnlockStateIfNeeded() {
        if !settings.faceIdLockEnabled {
            isUnlocked = true
            return
        }

        guard !isUnlocked else {
            return
        }
        attemptUnlock()
    }

    private func attemptUnlock() {
        guard settings.faceIdLockEnabled, !isUnlocking else { return }

        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            isUnlocked = false
            return
        }

        isUnlocking = true
        let reason = settings.language == .dutch
            ? "Ontgrendel je kaarten met Face ID."
            : "Unlock your cards with Face ID."

        context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) { success, _ in
            Task { @MainActor in
                isUnlocked = success
                isUnlocking = false
            }
        }
    }

    private func refreshEntryLists() {
        cachedUnfinishedEntryIDs = unfinished.map(\.id)
        cachedFinishedEntryIDs = finished.map(\.id)
    }
}
