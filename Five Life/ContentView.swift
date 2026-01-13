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

    @Environment(\.scenePhase) private var scenePhase

    private var unfinished: [DayEntry] {
        entries
            .filter { !$0.isLocked }
            .sorted { $0.day > $1.day }
    }

    private var finished: [DayEntry] {
        let base = entries.filter { $0.isLocked }
        let limited = vm.limitedFinishedEntries(from: base)
        let sorted = limited.sorted { vm.newestFirst ? ($0.day > $1.day) : ($0.day < $1.day) }
        let q = vm.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return sorted }
        return sorted.filter { entry in
            entryMatchesSearch(entry, query: q)
        }
    }

    private func entryMatchesSearch(_ entry: DayEntry, query: String) -> Bool {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return true }

        if entry.items.joined(separator: " ")
            .range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil {
            return true
        }

        let dayString = DateFormatting.formattedDayString(entry.day, language: settings.language)
        if dayString.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil {
            return true
        }

        let numericFormatter = DateFormatter()
        numericFormatter.locale = Locale(identifier: "en_US_POSIX")
        numericFormatter.dateFormat = "dd-MM-yyyy"
        let numericDate = numericFormatter.string(from: entry.day)
        if numericDate.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil {
            return true
        }

        if settings.moonEnabled {
            let phase = MoonPhase.phase(on: entry.day)
            let phaseName = phase.localizedName(language: settings.language)
            if phaseName.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil {
                return true
            }
        }

        if settings.holidaysEnabled {
            let holidayNames = HolidayProvider.holidayNames(on: entry.day, language: settings.language)
            if holidayNames.contains(where: { name in
                name.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil
            }) {
                return true
            }
        }

        return false
    }

    private var dailyTitle: String {
        let count = settings.dailyItemCount
        return settings.language == .dutch ? "Elke dag \(count)" : "\(count) Things everyday"
    }

    private var lifeTitle: String {
        let word = numberWord(for: settings.dailyItemCount)
        return "\(word) Life"
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
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 14) {
                        if showSettings {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Text(settings.language == .dutch ? "Instellingen" : "Settings")
                                        .font(.title3.weight(.semibold))

                                    Spacer()

                                    Button {
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                            showSettings.toggle()
                                        }
                                    } label: {
                                        Image(systemName: "xmark")
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundStyle(.secondary)
                                            .padding(8)
                                            .background(.thinMaterial)
                                            .clipShape(Circle())
                                    }
                                    .accessibilityLabel(settings.language == .dutch ? "Sluiten" : "Close")
                                }

                                SettingsView(settings: settings, showsNavigation: false)
                                    .padding(.top, 4)
                            }
                            .padding(14)
                            .background(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .fill(Color(.systemGray6))
                                    .shadow(radius: 6, y: 2)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .strokeBorder(Color.gray.opacity(0.4), lineWidth: 3)
                            )
                            .transition(.move(edge: .top).combined(with: .opacity))
                        }

                        // Unfinished section
                        if !unfinished.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                ForEach(unfinished) { entry in
                                    DayCardView(settings: settings, vm: vm, entry: entry)
                                        .matchedGeometryEffect(id: entry.id, in: cardNamespace)
                                        .transition(.opacity)
                                }
                            }
                            .animation(.spring(response: 0.5, dampingFraction: 0.85), value: unfinished.map(\.id))
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
                            .padding(.vertical, 8)

                        // Search + sort (finished only)
                        SearchAndSortBar(settings: settings,
                                         text: $vm.searchText,
                                         newestFirst: $vm.newestFirst,
                                         finishedLimit: $vm.finishedLimit)

                        // Finished section
                        VStack(alignment: .leading, spacing: 10) {
                            if finished.isEmpty {
                                Text(settings.language == .dutch
                                     ? "Geen kaarten gevonden."
                                     : "No cards found.")
                                    .foregroundStyle(.black)
                                    .padding(.horizontal, 4)
                            } else {
                                ForEach(finished) { entry in
                                    DayCardView(settings: settings, vm: vm, entry: entry)
                                        .matchedGeometryEffect(id: entry.id, in: cardNamespace)
                                        .transition(.opacity)
                                }
                            }
                        }
                        .animation(.spring(response: 0.5, dampingFraction: 0.85), value: finished.map(\.id))
                        .animation(.spring(response: 0.5, dampingFraction: 0.85), value: vm.searchText)
                        .animation(.spring(response: 0.5, dampingFraction: 0.85), value: vm.newestFirst)
                        .animation(.spring(response: 0.5, dampingFraction: 0.85), value: vm.finishedLimit)

                        // Share option bottom
                        VStack(spacing: 10) {
                            Divider().opacity(0.6)
                            ShareLink(
                                item: "Check out this app! (App Store link placeholder)",
                                subject: Text("Positive Things"),
                                message: Text(settings.language == .dutch
                                              ? "Dit helpt me elke dag 3–10 positieve dingen op te schrijven."
                                              : "This helps me write 3–10 positive things every day.")
                            ) {
                                HStack {
                                    Image(systemName: "square.and.arrow.up")
                                    Text(settings.language == .dutch ? "Deel de app" : "Share the app")
                                }
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .fill(.secondary.opacity(0.12))
                                )
                            }
                        }
                        .padding(.top, 10)
                    }
                    .padding(16)
                }
            }
            .background(Color.brandBackground.ignoresSafeArea())
            .safeAreaInset(edge: .top) {
                headerView
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .overlay(lockOverlay)
            .onChange(of: showSettings) { _, expanded in
                if !expanded {
                    // Apply notification changes after closing settings
                    Task {
                        await notifier.scheduleDailyReminder(time: settings.dailyReminderTime, language: settings.language)
                        let shouldScheduleNext = vm.shouldScheduleNextDayReminder(allEntries: entries)
                        await notifier.scheduleNextDayIfNeeded(time: settings.nextDayReminderTime,
                                                              shouldSchedule: shouldScheduleNext,
                                                              language: settings.language)
                    }
                }
            }
            .task {
                vm.ensureTodayEntry(modelContext: modelContext, settings: settings)
                await notifier.refreshAuthorizationStatus()
                await notifier.scheduleDailyReminder(time: settings.dailyReminderTime, language: settings.language)

                let shouldScheduleNext = vm.shouldScheduleNextDayReminder(allEntries: entries)
                await notifier.scheduleNextDayIfNeeded(time: settings.nextDayReminderTime,
                                                      shouldSchedule: shouldScheduleNext,
                                                      language: settings.language)
                scheduleMidnightRefresh()
            }
            .onChange(of: entries.count) { _, _ in
                // Keep “next day if needed” in sync when entries are created/locked/unlocked.
                Task {
                    let shouldScheduleNext = vm.shouldScheduleNextDayReminder(allEntries: entries)
                    await notifier.scheduleNextDayIfNeeded(time: settings.nextDayReminderTime,
                                                          shouldSchedule: shouldScheduleNext,
                                                          language: settings.language)
                }
            }
            .onChange(of: settings.dailyItemCount) { _, _ in
                vm.ensureTodayEntry(modelContext: modelContext, settings: settings)
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
}
