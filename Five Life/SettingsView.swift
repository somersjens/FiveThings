//NEW DOC  SettingsView.swift
import AuthenticationServices
import LocalAuthentication
import SwiftUI
import SwiftData
import UIKit

struct SettingsView: View {
    @ObservedObject var settings: SettingsStore
    @Binding var showDeleteAllOption: Bool
    var showsNavigation: Bool = true
    @Environment(\.modelContext) private var modelContext
    @StateObject private var notifier = NotificationManager.shared
    @StateObject private var appleSignInCoordinator = AppleSignInCoordinator()
    private let settingsRowHeight: CGFloat = 44

    @State private var dailyReminderEnabled: Bool = false
    @State private var nextDayReminderEnabled: Bool = false
    @State private var dailyReminderPickerDate: Date = Date()
    @State private var nextDayReminderPickerDate: Date = Date()
    @State private var faceIdLockEnabled: Bool = false
    @State private var isFaceIdAuthenticating: Bool = false
    @State private var showFaceIdSettingsAlert: Bool = false
    @State private var appleIdConnected: Bool = false
    @State private var addDayDigits: String = ""
    @State private var addDayText: String = ""
    @State private var addDayMessage: String?
    @State private var addDayMessageIsError: Bool = true
    @State private var addDayMessageTask: Task<Void, Never>?
    @State private var addDayHasExistingEntry = false
    @State private var secretSaveMessage: String?
    @State private var secretSaveMessageTask: Task<Void, Never>?
    @FocusState private var addDayFieldFocused: Bool
    @State private var isSigningInWithApple: Bool = false
    @AppStorage("hasSeenAccessScreen") private var hasSeenAccessScreen: Bool = false
    private let defaultDailyReminderTime = ReminderTime(hour: 22, minute: 0)
    private let defaultNextDayReminderTime = ReminderTime(hour: 9, minute: 0)

    private var languageSection: some View {
        HStack {
            Text(L10n.string("settings.app.language", language: settings.language))
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

    private var deleteAllEntriesSection: some View {
        HStack {
            Text(L10n.string("settings.delete.all", language: settings.language))
                .font(.body.weight(.semibold))
            Spacer()
            HStack(spacing: 8) {
                deleteAllActionButton(
                    title: L10n.string("common.no", language: settings.language),
                    background: Color(.systemGray5),
                    foreground: .primary
                ) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showDeleteAllOption = false
                    }
                }

                deleteAllActionButton(
                    title: L10n.string("common.yes", language: settings.language),
                    background: Color.red.opacity(0.15),
                    foreground: .red
                ) {
                    deleteAllEntries()
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showDeleteAllOption = false
                    }
                }
            }
        }
        .frame(height: settingsRowHeight)
    }

    private var itemsPerDaySection: some View {
        HStack {
            Text(L10n.string("settings.entries.per.day", language: settings.language))
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
                Text(L10n.string("settings.apple.id.connect", language: settings.language))
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .layoutPriority(1)
                    .onTapGesture(count: 5) {
                        hasSeenAccessScreen = false
                    }
                Spacer()
                Toggle("", isOn: Binding(
                    get: { appleIdConnected },
                    set: { newValue in
                        handleAppleIdToggleChange(newValue)
                    }
                ))
                .labelsHidden()
                .disabled(isSigningInWithApple)
            }
            .frame(height: settingsRowHeight)

            Divider().overlay(Color.gray.opacity(0.3))

            HStack {
                Text(L10n.string("settings.faceid.lock", language: settings.language))
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .layoutPriority(1)
                    .onTapGesture(count: 5) {
                        AppleSyncManager.shared.captureSnapshotNow(modelContext: modelContext,
                                                                   settings: settings,
                                                                   isConnected: settings.appleIdConnected)
                        showSecretSaveMessage(L10n.string("settings.secret.save.applied",
                                                          language: settings.language))
                    }
                Spacer()
                Toggle("", isOn: Binding(
                    get: { faceIdLockEnabled },
                    set: { newValue in
                        handleFaceIdToggleChange(newValue)
                    }
                ))
                .labelsHidden()
                .disabled(isFaceIdAuthenticating)
            }
            .frame(height: settingsRowHeight)

            Divider().overlay(Color.gray.opacity(0.3))

            Toggle(L10n.string("settings.score.day", language: settings.language),
                   isOn: Binding(get: { settings.scoreEnabled }, set: { settings.scoreEnabled = $0 }))
                .font(.body.weight(.semibold))
                .frame(height: settingsRowHeight)

            Divider().overlay(Color.gray.opacity(0.3))

            Toggle(L10n.string("settings.statistics", language: settings.language),
                   isOn: Binding(get: { settings.statisticsEnabled }, set: { settings.statisticsEnabled = $0 }))
                .font(.body.weight(.semibold))
                .frame(height: settingsRowHeight)

            Divider().overlay(Color.gray.opacity(0.3))

            Toggle(L10n.string("settings.holidays", language: settings.language),
                   isOn: Binding(get: { settings.holidaysEnabled }, set: { settings.holidaysEnabled = $0 }))
                .font(.body.weight(.semibold))
                .frame(height: settingsRowHeight)

            Divider().overlay(Color.gray.opacity(0.3))

            Toggle(L10n.string("settings.moon.info", language: settings.language),
                   isOn: Binding(get: { settings.moonEnabled }, set: { settings.moonEnabled = $0 }))
                .font(.body.weight(.semibold))
                .frame(height: settingsRowHeight)

            if let message = secretSaveMessage {
                Divider().overlay(Color.gray.opacity(0.3))
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.green)
                    .padding(.top, 6)
                    .transition(.opacity)
            }
        }
        .tint(.brandAccent)
    }

    private var addDaySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(addDayTitle)
                    .font(.body.weight(.semibold))

                Spacer(minLength: 8)

                HStack(spacing: 8) {
                    addDayInputField

                    Button {
                        handleAddDay()
                    } label: {
                        Image(systemName: addDayHasExistingEntry ? "xmark" : "checkmark")
                            .font(.system(size: 16, weight: .semibold))
                            .frame(width: 28, height: 28)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(Color.brandAccent)
                            )
                            .foregroundStyle(.white)
                    }
                    .accessibilityLabel(addDayTitle)
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

    private var addDayTitle: String {
        guard addDayDigits.count == 8 else {
            return L10n.string("settings.day.add.delete", language: settings.language)
        }
        if addDayHasExistingEntry {
            return L10n.string("settings.day.delete", language: settings.language)
        }
        return L10n.string("settings.day.add", language: settings.language)
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
                .accessibilityLabel(L10n.string("common.date", language: settings.language))
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
                    updateAddDayExistingEntry()
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
                Text(L10n.string("settings.reminder.evening", language: settings.language))
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
                Text(L10n.string("settings.reminder.next.day", language: settings.language))
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

            if notifier.authorizationStatus == .denied,
               (dailyReminderEnabled || nextDayReminderEnabled) {
                Text(L10n.string("settings.notifications.disabled", language: settings.language))
                    .font(.footnote)
                    .foregroundStyle(.black)
            }
        }
        .tint(.brandAccent)
    }

    private var settingsForm: some View {
        Form {
            if showDeleteAllOption {
                Section {
                    deleteAllEntriesSection
                }
            }

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
            if showDeleteAllOption {
                deleteAllEntriesSection
                Divider()
                    .overlay(Color.gray.opacity(0.3))
                    .frame(height: 1)
            }
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
                        .navigationTitle(L10n.string("settings.title", language: settings.language))
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button(L10n.string("common.done", language: settings.language)) {
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
            } else {
                dailyReminderPickerDate = defaultReminderDate(for: defaultDailyReminderTime)
            }
            if let rt = settings.nextDayReminderTime {
                nextDayReminderPickerDate = Calendar.current.date(from: rt.asDateComponents()) ?? Date()
            } else {
                nextDayReminderPickerDate = defaultReminderDate(for: defaultNextDayReminderTime)
            }

            faceIdLockEnabled = settings.faceIdLockEnabled
            appleIdConnected = settings.appleIdConnected
        }
        .alert(L10n.string("settings.faceid.required", language: settings.language),
               isPresented: $showFaceIdSettingsAlert) {
            Button(L10n.string("settings.go.to.settings", language: settings.language)) {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button(L10n.string("common.close", language: settings.language), role: .cancel) { }
        } message: {
            Text(L10n.string("settings.faceid.required.message", language: settings.language))
        }
        .onChange(of: dailyReminderEnabled) { _, enabled in
            if !enabled { settings.dailyReminderTime = nil }
            else { settings.dailyReminderTime = ReminderTime.from(date: dailyReminderPickerDate) }
            if enabled {
                Task { await notifier.requestAuthorizationIfNeeded() }
            }
        }
        .onChange(of: nextDayReminderEnabled) { _, enabled in
            if !enabled { settings.nextDayReminderTime = nil }
            else { settings.nextDayReminderTime = ReminderTime.from(date: nextDayReminderPickerDate) }
            if enabled {
                Task { await notifier.requestAuthorizationIfNeeded() }
            }
        }
    }

    private func defaultReminderDate(for time: ReminderTime) -> Date {
        Calendar.current.date(from: time.asDateComponents()) ?? Date()
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

        let descriptor = FetchDescriptor<DayEntry>(predicate: #Predicate { $0.day == normalizedDay })
        let existing = (try? modelContext.fetch(descriptor))?.first
        if existing != nil {
            if let existing {
                addDayHasExistingEntry = false
                _ = existing.items.count
                modelContext.delete(existing)
                try? modelContext.save()
                showAddDayMessage(L10n.string("settings.day.deleted", language: settings.language), isError: false)
            }
            addDayDigits = ""
            addDayText = ""
            return
        }

        let entry = DayEntry(day: normalizedDay, itemCount: settings.dailyItemCount)
        modelContext.insert(entry)
        try? modelContext.save()
        showAddDayMessage(L10n.string("settings.day.added", language: settings.language), isError: false)

        addDayDigits = ""
        addDayText = ""
        addDayHasExistingEntry = false
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

    private func updateAddDayExistingEntry() {
        guard addDayDigits.count == 8,
              let selectedDay = parseAddDayDate() else {
            addDayHasExistingEntry = false
            return
        }
        let normalizedDay = Calendar.current.startOfDay(for: selectedDay)
        let descriptor = FetchDescriptor<DayEntry>(predicate: #Predicate { $0.day == normalizedDay })
        addDayHasExistingEntry = ((try? modelContext.fetch(descriptor))?.first) != nil
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

    private func deleteAllActionButton(title: String,
                                       background: Color,
                                       foreground: Color,
                                       action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.footnote.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(background)
                )
        }
        .buttonStyle(.plain)
        .foregroundStyle(foreground)
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

    private func showAddDayMessage(_ message: String, isError: Bool = true) {
        addDayMessageTask?.cancel()
        addDayMessageIsError = isError
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

    private func showSecretSaveMessage(_ message: String) {
        secretSaveMessageTask?.cancel()
        withAnimation(.easeInOut(duration: 0.2)) {
            secretSaveMessage = message
        }
        secretSaveMessageTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            withAnimation(.easeInOut(duration: 0.2)) {
                secretSaveMessage = nil
            }
        }
    }

    private func deleteAllEntries() {
        let descriptor = FetchDescriptor<DayEntry>()
        let entriesToDelete = (try? modelContext.fetch(descriptor)) ?? []
        entriesToDelete.forEach { _ = $0.items.count }
        entriesToDelete.forEach { entry in
            modelContext.delete(entry)
        }
        try? modelContext.save()
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

        guard !isFaceIdAuthenticating else { return }
        isFaceIdAuthenticating = true
        faceIdLockEnabled = true

        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            settings.faceIdLockEnabled = false
            faceIdLockEnabled = false
            isFaceIdAuthenticating = false
            showFaceIdSettingsAlert = shouldShowFaceIdSettingsAlert(for: error)
            return
        }

        let reason = L10n.string("settings.faceid.reason", language: settings.language)

        context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) { success, error in
            Task { @MainActor in
                settings.faceIdLockEnabled = success
                faceIdLockEnabled = success
                isFaceIdAuthenticating = false
                if !success {
                    showFaceIdSettingsAlert = shouldShowFaceIdSettingsAlert(for: error as NSError?)
                }
            }
        }
    }

    private func shouldShowFaceIdSettingsAlert(for error: NSError?) -> Bool {
        guard let error else { return false }
        let laError = LAError.Code(rawValue: error.code)
        return laError == .biometryLockout || laError == .biometryNotEnrolled || laError == .biometryNotAvailable
    }

    private func handleAppleIdToggleChange(_ enabled: Bool) {
        if !enabled {
            settings.appleIdConnected = false
            appleIdConnected = false
            return
        }

        Task {
            await startAppleSignIn()
        }
    }

    @MainActor
    private func startAppleSignIn() async {
        guard !isSigningInWithApple else { return }
        isSigningInWithApple = true
        defer { isSigningInWithApple = false }

        do {
            let credential = try await appleSignInCoordinator.signIn()
            settings.appleUserIdentifier = credential.user
            settings.appleIdConnected = true
            appleIdConnected = true
            await AppleSyncManager.shared.reconcileAfterSignIn(modelContext: modelContext,
                                                               settings: settings,
                                                               context: .deferredConnect)
        } catch {
            settings.appleIdConnected = false
            appleIdConnected = false
        }
    }
}
