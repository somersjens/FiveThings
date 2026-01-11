//NEW DOC  SettingsView.swift
import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: SettingsStore
    var showsNavigation: Bool = true
    @StateObject private var notifier = NotificationManager.shared

    @State private var dailyReminderEnabled: Bool = false
    @State private var nextDayReminderEnabled: Bool = false
    @State private var dailyReminderPickerDate: Date = Date()
    @State private var nextDayReminderPickerDate: Date = Date()

    private var basicSettingsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Stepper(value: Binding(
                get: { settings.dailyItemCount },
                set: { settings.dailyItemCount = max(3, min(10, $0)) }
            ), in: 3...10) {
                Text(settings.language == .dutch
                     ? "Aantal dingen per dag: \(settings.dailyItemCount)"
                     : "Things per day: \(settings.dailyItemCount)")
            }

            Picker(settings.language == .dutch ? "Taal" : "Language", selection: Binding(
                get: { settings.language },
                set: { settings.language = $0 }
            )) {
                ForEach(AppLanguage.allCases) { lang in
                    Text(lang.displayName).tag(lang)
                }
            }

            Toggle(settings.language == .dutch ? "Toon maaninfo" : "Show moon info",
                   isOn: Binding(get: { settings.moonEnabled }, set: { settings.moonEnabled = $0 }))
        }
    }

    private var reminderSettingsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(settings.language == .dutch ? "Herinneringen" : "Reminders")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            Toggle(settings.language == .dutch ? "Dagelijkse reminder" : "Daily reminder",
                   isOn: $dailyReminderEnabled)

            if dailyReminderEnabled {
                DatePicker(settings.language == .dutch ? "Tijd" : "Time",
                           selection: $dailyReminderPickerDate,
                           displayedComponents: .hourAndMinute)
                    .onChange(of: dailyReminderPickerDate) { _, newValue in
                        settings.dailyReminderTime = ReminderTime.from(date: newValue)
                    }
            }

            Toggle(settings.language == .dutch ? "Volgende dag als nodig" : "Next day if needed",
                   isOn: $nextDayReminderEnabled)

            if nextDayReminderEnabled {
                DatePicker(settings.language == .dutch ? "Tijd" : "Time",
                           selection: $nextDayReminderPickerDate,
                           displayedComponents: .hourAndMinute)
                    .onChange(of: nextDayReminderPickerDate) { _, newValue in
                        settings.nextDayReminderTime = ReminderTime.from(date: newValue)
                    }
            }

            if notifier.authorizationStatus == .denied {
                Text(settings.language == .dutch
                     ? "Notificaties zijn uitgeschakeld. Zet ze aan in Instellingen."
                     : "Notifications are disabled. Enable them in Settings.")
                    .font(.footnote)
                    .foregroundStyle(.black)
            }
        }
    }

    private var settingsForm: some View {
        Form {
            Section {
                basicSettingsSection
            }

            Section(header: Text(settings.language == .dutch ? "Herinneringen" : "Reminders")) {
                reminderSettingsSection
            }
        }
    }

    private var inlineSettings: some View {
        VStack(alignment: .leading, spacing: 16) {
            basicSettingsSection
            reminderSettingsSection
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.secondary.opacity(0.08))
        )
    }

    var body: some View {
        Group {
            if showsNavigation {
                NavigationStack {
                    settingsForm
                        .navigationTitle(settings.language == .dutch ? "Instellingen" : "Settings")
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button(settings.language == .dutch ? "Gereed" : "Done") {
                                    // Dismiss handled by parent sheet
                                }
                            }
                        }
                }
            } else {
                inlineSettings
            }
        }
        .task {
            await notifier.refreshAuthorizationStatus()

            // Hydrate toggles from stored optionals
            dailyReminderEnabled = (settings.dailyReminderTime != nil)
            nextDayReminderEnabled = (settings.nextDayReminderTime != nil)

            if let rt = settings.dailyReminderTime {
                dailyReminderPickerDate = Calendar.current.date(from: rt.asDateComponents()) ?? Date()
            }
            if let rt = settings.nextDayReminderTime {
                nextDayReminderPickerDate = Calendar.current.date(from: rt.asDateComponents()) ?? Date()
            }
        }
        .onChange(of: dailyReminderEnabled) { _, enabled in
            if !enabled { settings.dailyReminderTime = nil }
            else { settings.dailyReminderTime = ReminderTime.from(date: dailyReminderPickerDate) }
        }
        .onChange(of: nextDayReminderEnabled) { _, enabled in
            if !enabled { settings.nextDayReminderTime = nil }
            else { settings.nextDayReminderTime = ReminderTime.from(date: nextDayReminderPickerDate) }
        }
    }
}
