//NEW DOC  SettingsView.swift
import LocalAuthentication
import SwiftUI
import SwiftData

struct SettingsView: View {
    @ObservedObject var settings: SettingsStore
    var showsNavigation: Bool = true
    @Environment(\.modelContext) private var modelContext
    @StateObject private var notifier = NotificationManager.shared

    @State private var dailyReminderEnabled: Bool = false
    @State private var nextDayReminderEnabled: Bool = false
    @State private var dailyReminderPickerDate: Date = Date()
    @State private var nextDayReminderPickerDate: Date = Date()
    @State private var faceIdLockEnabled: Bool = false
    @State private var addDayDigits: String = ""
    @State private var addDayMessage: String?
    @State private var addDayMessageIsError: Bool = true

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

    private var addDaySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(settings.language == .dutch ? "Voeg een dag toe" : "Add a day")
                .font(.headline)

            HStack(spacing: 8) {
                addDayInputField

                Button {
                    handleAddDay()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(width: 36, height: 36)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(.secondary.opacity(0.12))
                        )
                }
                .accessibilityLabel(settings.language == .dutch ? "Dag toevoegen" : "Add day")
            }

            Text(settings.language == .dutch
                 ? "Vul DD-MM-JJJJ in."
                 : "Enter DD-MM-YYYY (or MM-DD-YYYY).")
                .font(.footnote)
                .foregroundStyle(.secondary)

            if let message = addDayMessage {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(addDayMessageIsError ? .red : .green)
            }
        }
    }

    private var addDayInputField: some View {
        ZStack(alignment: .leading) {
            Text(addDayAttributedPlaceholder)
                .font(.body.monospacedDigit())

            TextField("", text: addDayDigitsBinding)
                .keyboardType(.numberPad)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                .foregroundStyle(.clear)
                .font(.body.monospacedDigit())
                .tint(.primary)
                .accessibilityLabel(settings.language == .dutch ? "Datum" : "Date")
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(.systemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.gray.opacity(0.3), lineWidth: 1)
        )
    }

    private var addDayDigitsBinding: Binding<String> {
        Binding(
            get: { addDayDigits },
            set: { newValue in
                let filtered = newValue.filter(\.isWholeNumber)
                addDayDigits = String(filtered.prefix(8))
                addDayMessage = nil
            }
        )
    }

    private var addDayAttributedPlaceholder: AttributedString {
        let placeholder = "DD-MM-YYYY"
        var attributed = AttributedString()
        var digitIndex = addDayDigits.startIndex

        for character in placeholder {
            var segment = AttributedString(String(character))
            if character == "D" || character == "M" || character == "Y" {
                if digitIndex < addDayDigits.endIndex {
                    segment = AttributedString(String(addDayDigits[digitIndex]))
                    segment.foregroundColor = .primary
                    digitIndex = addDayDigits.index(after: digitIndex)
                } else {
                    segment.foregroundColor = .secondary
                }
            } else {
                segment.foregroundColor = .secondary
            }
            attributed.append(segment)
        }

        return attributed
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

            Section {
                addDaySection
            }
        }
    }

    private var inlineSettings: some View {
        VStack(alignment: .leading, spacing: 16) {
            basicSettingsSection
            reminderSettingsSection
            addDaySection
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

    private func handleAddDay() {
        guard addDayDigits.count == 8 else {
            addDayMessage = settings.language == .dutch
                ? "Vul een volledige datum in."
                : "Enter a full date."
            addDayMessageIsError = true
            return
        }

        guard let selectedDay = parseAddDayDate() else {
            addDayMessage = settings.language == .dutch
                ? "Ongeldige datum."
                : "Invalid date."
            addDayMessageIsError = true
            return
        }

        let calendar = Calendar.current
        let normalizedDay = calendar.startOfDay(for: selectedDay)
        let today = calendar.startOfDay(for: Date())
        if normalizedDay > today {
            addDayMessage = settings.language == .dutch
                ? "Deze datum ligt in de toekomst."
                : "That date is in the future."
            addDayMessageIsError = true
            return
        }

        let descriptor = FetchDescriptor<DayEntry>(predicate: #Predicate { $0.day == normalizedDay })
        let existing = (try? modelContext.fetch(descriptor))?.first
        if existing != nil {
            addDayMessage = settings.language == .dutch
                ? "Deze dag bestaat al."
                : "That day already exists."
            addDayMessageIsError = true
            return
        }

        let entry = DayEntry(day: normalizedDay, itemCount: settings.dailyItemCount)
        modelContext.insert(entry)
        try? modelContext.save()

        addDayDigits = ""
        addDayMessage = settings.language == .dutch
            ? "Dag toegevoegd."
            : "Day added."
        addDayMessageIsError = false
    }

    private func parseAddDayDate() -> Date? {
        guard let first = intFromDigits(start: 0, length: 2),
              let second = intFromDigits(start: 2, length: 2),
              let year = intFromDigits(start: 4, length: 4) else {
            return nil
        }

        if settings.language == .dutch {
            return dateFrom(day: first, month: second, year: year)
        }

        if let monthFirst = dateFrom(day: second, month: first, year: year) {
            return monthFirst
        }

        return dateFrom(day: first, month: second, year: year)
    }

    private func intFromDigits(start: Int, length: Int) -> Int? {
        guard addDayDigits.count >= start + length else { return nil }
        let startIndex = addDayDigits.index(addDayDigits.startIndex, offsetBy: start)
        let endIndex = addDayDigits.index(startIndex, offsetBy: length)
        return Int(addDayDigits[startIndex..<endIndex])
    }

    private func dateFrom(day: Int, month: Int, year: Int) -> Date? {
        var components = DateComponents()
        components.calendar = Calendar.current
        components.day = day
        components.month = month
        components.year = year
        guard let date = components.date else { return nil }
        let calendar = Calendar.current
        let normalized = calendar.startOfDay(for: date)
        guard calendar.component(.day, from: normalized) == day,
              calendar.component(.month, from: normalized) == month,
              calendar.component(.year, from: normalized) == year else {
            return nil
        }
        return normalized
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
