//NEW DOC  ContentView.swift
import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext

    @StateObject private var settings = SettingsStore()
    @StateObject private var vm = ContentViewModel()
    @StateObject private var notifier = NotificationManager.shared

    @Query(sort: \DayEntry.day, order: .reverse) private var entries: [DayEntry]

    @State private var showSettings: Bool = false

    private var unfinished: [DayEntry] {
        entries
            .filter { !$0.isLocked }
            .sorted { $0.day > $1.day }
    }

    private var finished: [DayEntry] {
        let base = entries.filter { $0.isLocked }
        let sorted = base.sorted { vm.newestFirst ? ($0.day > $1.day) : ($0.day < $1.day) }
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

        if settings.moonEnabled, let phase = MoonPhase.namedPhaseIfNear(entry.day) {
            let phaseName = phase.localizedName(language: settings.language)
            if phaseName.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil {
                return true
            }
        }

        return false
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    // Unfinished section
                    if !unfinished.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(settings.language == .dutch ? "Onvoltooid" : "Unfinished")
                                .font(.title3.weight(.semibold))
                                .padding(.horizontal, 4)

                            ForEach(unfinished) { entry in
                                DayCardView(settings: settings, vm: vm, entry: entry)
                            }
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(settings.language == .dutch ? "Alles is af!" : "All done!")
                                .font(.title3.weight(.semibold))
                            Text(settings.language == .dutch
                                 ? "Je hebt geen open kaarten."
                                 : "You have no open cards.")
                                .foregroundStyle(.black)
                        }
                        .padding(.vertical, 8)
                    }

                    // Thick divider
                    Rectangle()
                        .fill(Color.brandAccent)
                        .frame(height: 6)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .padding(.vertical, 8)

                    // Search + sort (finished only)
                    SearchAndSortBar(settings: settings, text: $vm.searchText, newestFirst: $vm.newestFirst)

                    // Finished section
                    VStack(alignment: .leading, spacing: 10) {
                        Text(settings.language == .dutch ? "Vergrendeld" : "Locked")
                            .font(.title3.weight(.semibold))
                            .padding(.horizontal, 4)

                        if finished.isEmpty {
                            Text(settings.language == .dutch
                                 ? "Geen vergrendelde kaarten gevonden."
                                 : "No locked cards found.")
                                .foregroundStyle(.black)
                                .padding(.horizontal, 4)
                        } else {
                            ForEach(finished) { entry in
                                DayCardView(settings: settings, vm: vm, entry: entry)
                            }
                        }
                    }

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
            .background(Color.brandBackground.ignoresSafeArea())
            .navigationTitle(settings.language == .dutch ? "Positieve dingen" : "Positive things")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape.fill")
                    }
                    .accessibilityLabel(settings.language == .dutch ? "Instellingen" : "Settings")
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView(settings: settings)
                    .presentationDetents([.medium, .large])
                    .onDisappear {
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
        }
    }
}
