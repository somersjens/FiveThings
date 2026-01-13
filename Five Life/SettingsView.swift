//NEW DOC  SettingsView.swift
import LocalAuthentication
import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: SettingsStore
    var showsNavigation: Bool = true
    @StateObject private var notifier = NotificationManager.shared

    @State private var dailyReminderEnabled: Bool = false
    @State private var nextDayReminderEnabled: Bool = false
    @State private var dailyReminderPickerDate: Date = Date()
    @State private var nextDayReminderPickerDate: Date = Date()
    @State private var faceIdLockEnabled: Bool = false

    private var basicSettingsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(settings.language == .dutch ? "Aantal per dag" : "Items per day")
                Spacer()
                Picker("", selection: Binding(
                    get: { settings.dailyItemCount },
                    set: { settings.dailyItemCount = max(1, min(10, $0)) }
                )) {
                    ForEach(1...10, id: \.self) { count in
                        Text("\(count)").tag(count)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .foregroundStyle(.black)
                .tint(.black)
            }

            HStack {
                Text(settings.language == .dutch ? "Taal van de app" : "App language")
                Spacer()
                Picker("", selection: Binding(
                    get: { settings.language },
                    set: { settings.language = $0 }
                )) {
                    ForEach(AppLanguage.allCases) { lang in
                        Text(lang.displayName).tag(lang)
                    }
                }
                .labelsHidden()
                .foregroundStyle(.black)
                .tint(.black)
            }

            Toggle(settings.language == .dutch ? "Toon maaninfo" : "Show moon info",
                   isOn: Binding(get: { settings.moonEnabled }, set: { settings.moonEnabled = $0 }))

            Toggle(settings.language == .dutch ? "Toon speciale feestdagen" : "Show special holidays",
                   isOn: Binding(get: { settings.holidaysEnabled }, set: { settings.holidaysEnabled = $0 }))

            Toggle(settings.language == .dutch ? "Toon statistieken" : "Show statistics",
                   isOn: Binding(get: { settings.statisticsEnabled }, set: { settings.statisticsEnabled = $0 }))

            HStack {
                Text(settings.language == .dutch ? "Vergrendel met Face ID" : "Lock with Face ID")
                Spacer()
                Toggle("", isOn: Binding(
                    get: { faceIdLockEnabled },
                    set: { newValue in
                        handleFaceIdToggleChange(newValue)
                    }
                ))
                .labelsHidden()
            }
        }
    }

    private var reminderSettingsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(settings.language == .dutch ? "Dagelijkse reminder" : "Daily reminder")
                Spacer()
                if dailyReminderEnabled {
                    DatePicker("",
                               selection: $dailyReminderPickerDate,
                               displayedComponents: .hourAndMinute)
                        .labelsHidden()
                        .onChange(of: dailyReminderPickerDate) { _, newValue in
                            settings.dailyReminderTime = ReminderTime.from(date: newValue)
                        }
                }
                Toggle("", isOn: $dailyReminderEnabled)
                    .labelsHidden()
            }

            HStack {
                Text(settings.language == .dutch ? "Volgende dag als nodig" : "Next day if needed")
                Spacer()
                if nextDayReminderEnabled {
                    DatePicker("",
                               selection: $nextDayReminderPickerDate,
                               displayedComponents: .hourAndMinute)
                        .labelsHidden()
                        .onChange(of: nextDayReminderPickerDate) { _, newValue in
                            settings.nextDayReminderTime = ReminderTime.from(date: newValue)
                        }
                }
                Toggle("", isOn: $nextDayReminderEnabled)
                    .labelsHidden()
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

            Section {
                reminderSettingsSection
            }
        }
    }

    private var inlineSettings: some View {
        VStack(alignment: .leading, spacing: 16) {
            basicSettingsSection
            reminderSettingsSection
        }
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

            faceIdLockEnabled = settings.faceIdLockEnabled
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

    private func handleFaceIdToggleChange(_ enabled: Bool) {
        if !enabled {
            settings.faceIdLockEnabled = false
            faceIdLockEnabled = false
            return
        }

        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            settings.faceIdLockEnabled = false
            faceIdLockEnabled = false
            return
        }

        let reason = settings.language == .dutch
            ? "Activeer Face ID om je kaarten te vergrendelen."
            : "Enable Face ID to lock your cards."

        context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) { success, _ in
            Task { @MainActor in
                settings.faceIdLockEnabled = success
                faceIdLockEnabled = success
            }
        }
    }
}
