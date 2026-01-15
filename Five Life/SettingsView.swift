//NEW DOC  SettingsView.swift
import LocalAuthentication
import SwiftUI
import SwiftData

struct SettingsView: View {
    @ObservedObject var settings: SettingsStore
    var showsNavigation: Bool = true
    @Environment(\.modelContext) private var modelContext
    @StateObject private var notifier = NotificationManager.shared
    private let settingsRowHeight: CGFloat = 44

    @State private var dailyReminderEnabled: Bool = false
    @State private var nextDayReminderEnabled: Bool = false
    @State private var dailyReminderPickerDate: Date = Date()
    @State private var nextDayReminderPickerDate: Date = Date()
    @State private var faceIdLockEnabled: Bool = false
    @State private var addDayDigits: String = ""
    @State private var addDayText: String = ""
    @State private var addDayMessage: String?
    @State private var addDayMessageIsError: Bool = true
    @State private var addDayMessageTask: Task<Void, Never>?
    @FocusState private var addDayFieldFocused: Bool

    private var languageSection: some View {
        HStack {
            Text(settings.language == .dutch ? "Taal van de app" : "App language")
                .font(.body.weight(.semibold))
            Spacer()
            Menu {
                Picker("", selection: Binding(
                    get: { settings.language },
                    set: { settings.language = $0 }
                )) {
                    ForEach(AppLanguage.allCases) { lang in
                        Text(lang.displayName).tag(lang)
                    }
                }
                .labelsHidden()
            } label: {
                settingsPickerLabel(text: settings.language.displayName)
            }
        }
        .frame(height: settingsRowHeight)
        .tint(.brandAccent)
    }

    private var itemsPerDaySection: some View {
        HStack {
            Text(settings.language == .dutch ? "Aantal per dag" : "Entries per day")
                .font(.body.weight(.semibold))
            Spacer()
            HStack(spacing: 10) {
                settingsStepperButton(
                    systemName: "minus",
                    isDisabled: settings.dailyItemCount <= 1
                ) {
                    settings.dailyItemCount = max(1, settings.dailyItemCount - 1)
                }

                Text("\(settings.dailyItemCount)")
                    .font(.body.monospacedDigit())
                    .foregroundStyle(.black)

                settingsStepperButton(
                    systemName: "plus",
                    isDisabled: settings.dailyItemCount >= 10
                ) {
                    settings.dailyItemCount = min(10, settings.dailyItemCount + 1)
                }
            }
        }
        .frame(height: settingsRowHeight)
    }

    private var otherSettingsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(settings.language == .dutch ? "Vergrendel met Face ID" : "Lock with Face ID")
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .layoutPriority(1)
                Spacer()
                Toggle("", isOn: Binding(
                    get: { faceIdLockEnabled },
                    set: { newValue in
                        handleFaceIdToggleChange(newValue)
                    }
                ))
                .labelsHidden()
            }
            .frame(height: settingsRowHeight)

            Divider().overlay(Color.gray.opacity(0.3))

            Toggle(settings.language == .dutch ? "Statistieken" : "Statistics",
                   isOn: Binding(get: { settings.statisticsEnabled }, set: { settings.statisticsEnabled = $0 }))
                .font(.body.weight(.semibold))
                .frame(height: settingsRowHeight)

            Divider().overlay(Color.gray.opacity(0.3))

            Toggle(settings.language == .dutch ? "Feestdagen" : "Special holidays",
                   isOn: Binding(get: { settings.holidaysEnabled }, set: { settings.holidaysEnabled = $0 }))
                .font(.body.weight(.semibold))
                .frame(height: settingsRowHeight)

            Divider().overlay(Color.gray.opacity(0.3))

            Toggle(settings.language == .dutch ? "Maan informatie" : "Moon info",
                   isOn: Binding(get: { settings.moonEnabled }, set: { settings.moonEnabled = $0 }))
                .font(.body.weight(.semibold))
                .frame(height: settingsRowHeight)
        }
        .tint(.brandAccent)
    }

    private var addDaySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(settings.language == .dutch ? "Voeg een dag toe" : "Add a day")
                    .font(.body.weight(.semibold))

                Spacer(minLength: 8)

                HStack(spacing: 8) {
                    addDayInputField

                    Button {
                        handleAddDay()
                    } label: {
                        Image(systemName: "checkmark")
                            .font(.system(size: 16, weight: .semibold))
                            .frame(width: 28, height: 28)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(Color.brandAccent)
                            )
                            .foregroundStyle(.white)
                    }
                    .accessibilityLabel(settings.language == .dutch ? "Dag toevoegen" : "Add day")
                }
            }

            if let message = addDayMessage {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(addDayMessageIsError ? .red : .green)
                    .transition(.opacity)
            }
        }
        .padding(.vertical, 8)
    }

    private var addDayInputField: some View {
        ZStack(alignment: .leading) {
            TextField("", text: $addDayText)
                .keyboardType(.numberPad)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                .font(.body.monospacedDigit())
                .foregroundStyle(.clear)
                .tint(Color(.darkGray))
                .multilineTextAlignment(.leading)
                .focused($addDayFieldFocused)
                .accessibilityLabel(settings.language == .dutch ? "Datum" : "Date")
                .frame(maxWidth: .infinity, alignment: .leading)
                .onChange(of: addDayText) { oldValue, newValue in
                    let filtered = newValue.filter(\.isWholeNumber)
                    var nextDigits = String(filtered.prefix(8))
                    if newValue.count < oldValue.count,
                       oldValue.hasSuffix("-"),
                       !newValue.hasSuffix("-"),
                       (nextDigits.count == 2 || nextDigits.count == 4),
                       !nextDigits.isEmpty {
                        nextDigits = String(nextDigits.dropLast())
                    }
                    addDayDigits = nextDigits
                    addDayMessage = nil
                    let formatted = formattedAddDayDigits(nextDigits)
                    if newValue != formatted {
                        addDayText = formatted
                    }
                    if nextDigits.count == 8 {
                        addDayFieldFocused = false
                    }
                }

            Text(addDayDisplayText(addDayDigits))
                .font(.body.monospacedDigit())
                .allowsHitTesting(false)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 100, height: 21)
        .padding(.vertical, 3)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(.systemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.gray.opacity(0.3), lineWidth: 1)
        )
    }

    private var reminderSettingsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(settings.language == .dutch ? "Avond reminder" : "Evening reminder")
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .layoutPriority(1)
                Spacer()
                if dailyReminderEnabled {
                    DatePicker("",
                               selection: $dailyReminderPickerDate,
                               displayedComponents: .hourAndMinute)
                        .labelsHidden()
                        .datePickerStyle(.compact)
                        .onChange(of: dailyReminderPickerDate) { _, newValue in
                            settings.dailyReminderTime = ReminderTime.from(date: newValue)
                        }
                }
                Toggle("", isOn: $dailyReminderEnabled)
                    .labelsHidden()
            }
            .frame(height: settingsRowHeight)

            Divider().overlay(Color.gray.opacity(0.3))

            HStack {
                Text(settings.language == .dutch ? "Volgende dag reminder" : "Next day reminder")
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .layoutPriority(1)
                Spacer()
                if nextDayReminderEnabled {
                    DatePicker("",
                               selection: $nextDayReminderPickerDate,
                               displayedComponents: .hourAndMinute)
                        .labelsHidden()
                        .datePickerStyle(.compact)
                        .onChange(of: nextDayReminderPickerDate) { _, newValue in
                            settings.nextDayReminderTime = ReminderTime.from(date: newValue)
                        }
                }
                Toggle("", isOn: $nextDayReminderEnabled)
                    .labelsHidden()
            }
            .frame(height: settingsRowHeight)

            if notifier.authorizationStatus == .denied {
                Text(settings.language == .dutch
                     ? "Notificaties zijn uitgeschakeld. Zet ze aan in Instellingen."
                     : "Notifications are disabled. Enable them in Settings.")
                    .font(.footnote)
                    .foregroundStyle(.black)
            }
        }
        .tint(.brandAccent)
    }

    private var settingsForm: some View {
        Form {
            Section {
                languageSection
            }

            Section {
                addDaySection
            }

            Section {
                itemsPerDaySection
            }

            Section {
                otherSettingsSection
            }

            Section {
                reminderSettingsSection
            }
        }
    }

    private var inlineSettings: some View {
        VStack(alignment: .leading, spacing: 0) {
            languageSection
            Divider()
                .overlay(Color.gray.opacity(0.3))
                .frame(height: 1)
            addDaySection
            Divider()
                .overlay(Color.gray.opacity(0.3))
                .frame(height: 1)
            itemsPerDaySection
            Divider()
                .overlay(Color.gray.opacity(0.3))
                .frame(height: 1)
            otherSettingsSection
            Divider()
                .overlay(Color.gray.opacity(0.3))
                .frame(height: 1)
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

    private func handleAddDay() {
        guard addDayDigits.count == 8 else {
            return
        }

        guard let selectedDay = parseAddDayDate() else {
            return
        }

        let calendar = Calendar.current
        let normalizedDay = calendar.startOfDay(for: selectedDay)
        let today = calendar.startOfDay(for: Date())
        if normalizedDay > today {
            showAddDayMessage(settings.language == .dutch
                ? "Deze datum ligt in de toekomst."
                : "That date is in the future.")
            return
        }

        let descriptor = FetchDescriptor<DayEntry>(predicate: #Predicate { $0.day == normalizedDay })
        let existing = (try? modelContext.fetch(descriptor))?.first
        if existing != nil {
            showAddDayMessage(settings.language == .dutch
                ? "Deze dag bestaat al."
                : "That day already exists.")
            return
        }

        let entry = DayEntry(day: normalizedDay, itemCount: settings.dailyItemCount)
        modelContext.insert(entry)
        try? modelContext.save()

        addDayDigits = ""
        addDayText = ""
    }

    private func parseAddDayDate() -> Date? {
        guard let first = intFromDigits(start: 0, length: 2),
              let second = intFromDigits(start: 2, length: 2),
              let year = intFromDigits(start: 4, length: 4) else {
            return nil
        }

        return dateFrom(day: first, month: second, year: year)
    }

    private func formattedAddDayDigits(_ digits: String) -> String {
        var formatted = ""
        let characters = Array(digits)
        for index in 0..<characters.count {
            if index == 2 || index == 4 {
                formatted.append("-")
            }
            formatted.append(characters[index])
        }
        if digits.count == 2 || digits.count == 4 {
            formatted.append("-")
        }
        return formatted
    }

    private func addDayDisplayText(_ digits: String) -> AttributedString {
        let digitColor = Color(.black)
        let placeholderColor = Color(.systemGray3)

        let dayDigits = String(digits.prefix(2))
        let monthDigits = digits.count > 2 ? String(digits.dropFirst(2).prefix(2)) : ""
        let yearDigits = digits.count > 4 ? String(digits.dropFirst(4).prefix(4)) : ""

        let dayPlaceholder = String(repeating: "D", count: max(0, 2 - dayDigits.count))
        let monthPlaceholder = String(repeating: "M", count: max(0, 2 - monthDigits.count))
        let yearPlaceholder = String(repeating: "Y", count: max(0, 4 - yearDigits.count))

        var output = AttributedString("")
        var dayValue = AttributedString(dayDigits)
        dayValue.foregroundColor = digitColor
        var dayFiller = AttributedString(dayPlaceholder)
        dayFiller.foregroundColor = placeholderColor
        var dashOne = AttributedString("-")
        dashOne.foregroundColor = placeholderColor

        var monthValue = AttributedString(monthDigits)
        monthValue.foregroundColor = digitColor
        var monthFiller = AttributedString(monthPlaceholder)
        monthFiller.foregroundColor = placeholderColor
        var dashTwo = AttributedString("-")
        dashTwo.foregroundColor = placeholderColor

        var yearValue = AttributedString(yearDigits)
        yearValue.foregroundColor = digitColor
        var yearFiller = AttributedString(yearPlaceholder)
        yearFiller.foregroundColor = placeholderColor

        output += dayValue
        output += dayFiller
        output += dashOne
        output += monthValue
        output += monthFiller
        output += dashTwo
        output += yearValue
        output += yearFiller

        return output
    }

    private func settingsPickerLabel(text: String) -> some View {
        HStack(spacing: 6) {
            Text(text)
                .foregroundStyle(.black)
            Image(systemName: "chevron.down")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.brandAccent)
        }
    }

    private func settingsStepperButton(systemName: String,
                                       isDisabled: Bool,
                                       action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color(.systemGray5))
                )
        }
        .disabled(isDisabled)
        .foregroundStyle(isDisabled ? Color.gray.opacity(0.6) : Color.brandAccent)
    }

    private func showAddDayMessage(_ message: String) {
        addDayMessageTask?.cancel()
        addDayMessageIsError = true
        withAnimation(.easeInOut(duration: 0.2)) {
            addDayMessage = message
        }
        addDayMessageTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(5))
            withAnimation(.easeInOut(duration: 0.2)) {
                addDayMessage = nil
            }
        }
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
