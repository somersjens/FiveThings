//NEW DOC  SettingsView.swift
import AuthenticationServices
import LocalAuthentication
import SwiftUI
import SwiftData
import UIKit
import UniformTypeIdentifiers

struct SettingsView: View {
    @ObservedObject var settings: SettingsStore
    @Binding var showSecretMenu: Bool
    var showsNavigation: Bool = true
    @Environment(\.modelContext) private var modelContext
    @Environment(\.responsiveTypeScale) private var responsiveTypeScale
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var notifier = NotificationManager.shared
    @StateObject private var appleSignInCoordinator = AppleSignInCoordinator()
    @ScaledMetric(relativeTo: .body) private var settingsRowHeight: CGFloat = 44
    @ScaledMetric(relativeTo: .headline) private var addDayButtonFontSize: CGFloat = 16
    @ScaledMetric(relativeTo: .headline) private var addDayButtonSize: CGFloat = 28
    @ScaledMetric(relativeTo: .footnote) private var stepperFontSize: CGFloat = 14
    @ScaledMetric(relativeTo: .body) private var stepperButtonSize: CGFloat = 28

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
    @FocusState private var addDayFieldFocused: Bool
    @State private var isSigningInWithApple: Bool = false
    @State private var showImportPicker: Bool = false
    @State private var importErrorMessage: String?
    @AppStorage("hasSeenAccessScreen") private var hasSeenAccessScreen: Bool = false
    @State private var showLanguagePicker: Bool = false
    private let defaultDailyReminderTime = ReminderTime(hour: 22, minute: 0)
    private let defaultNextDayReminderTime = ReminderTime(hour: 9, minute: 0)
    private let secretRowHeightMultiplier: CGFloat = 1.5
    @State private var isDeleteAllConfirming: Bool = false
    @State private var activeInfo: SettingsInfo?
    @State private var infoFrames: [SettingsInfo: CGRect] = [:]
    @State private var infoPopoverSize: CGSize = .zero

    private enum SettingsInfo {
        case language
        case addDay
        case entriesPerDay
        case appleId
        case faceId
        case scoreDay
        case statistics
        case holidays
        case moonInfo
        case reminderEvening
        case reminderNextDay
    }

    private struct SettingsInfoFramePreferenceKey: PreferenceKey {
        static var defaultValue: [SettingsInfo: CGRect] = [:]

        static func reduce(value: inout [SettingsInfo: CGRect], nextValue: () -> [SettingsInfo: CGRect]) {
            value.merge(nextValue(), uniquingKeysWith: { $1 })
        }
    }

    private struct SettingsInfoPopoverSizePreferenceKey: PreferenceKey {
        static var defaultValue: CGSize = .zero

        static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
            value = nextValue()
        }
    }

    private var languageSection: some View {
        HStack {
            infoTitle(L10n.string("settings.app.language", language: settings.language), info: .language)
            Spacer()
            Button {
                showLanguagePicker = true
            } label: {
                settingsPickerLabel(text: settings.language.localizedCountryName, flag: settings.language.flagEmoji)
            }
        }
        .frame(minHeight: scaledSettingsRowHeight)
        .tint(.brandAccent)
        .sheet(isPresented: $showLanguagePicker) {
            VStack(spacing: 12) {
                HStack {
                    Text(L10n.string("settings.app.language", language: settings.language))
                        .font(.headline)
                    Spacer()
                    Button(L10n.string("common.done", language: settings.language)) {
                        showLanguagePicker = false
                    }
                    .font(.headline)
                    .foregroundStyle(Color.brandAccent)
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)

                Picker("", selection: Binding(
                    get: { settings.language },
                    set: { settings.language = $0 }
                )) {
                    ForEach(AppLanguage.orderedByCountryName) { lang in
                        HStack {
                            Text(lang.localizedCountryName)
                            Spacer()
                            Text(lang.flagEmoji)
                        }
                        .tag(lang)
                    }
                }
                .pickerStyle(.wheel)
                .labelsHidden()
                .frame(maxWidth: .infinity)
            }
            .padding(.bottom, 12)
            .presentationDetents([.height(360)])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(24)
        }
    }

    private var deleteAllEntriesSection: some View {
        HStack {
            Text(deleteAllConfirmationTitle)
                .font(.body.weight(.semibold))
            Spacer()
            HStack(spacing: 8) {
                if isDeleteAllConfirming {
                    deleteAllActionButton(
                        title: L10n.string("common.yes", language: settings.language),
                        background: Color.red.opacity(0.15),
                        foreground: .red
                    ) {
                        deleteAllEntries()
                        closeSecretMenu()
                    }

                    deleteAllActionButton(
                        title: L10n.string("common.no", language: settings.language),
                        background: Color(.systemGray5),
                        foreground: .primary
                    ) {
                        closeSecretMenu()
                    }
                } else {
                    deleteAllActionButton(
                        title: L10n.string("common.no", language: settings.language),
                        background: Color(.systemGray5),
                        foreground: .primary
                    ) {
                        closeSecretMenu()
                    }

                    deleteAllActionButton(
                        title: L10n.string("common.yes", language: settings.language),
                        background: Color.red.opacity(0.15),
                        foreground: .red
                    ) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isDeleteAllConfirming = true
                        }
                    }
                }
            }
        }
        .frame(height: secretRowHeight)
    }

    private var itemsPerDaySection: some View {
        HStack {
            infoTitle(L10n.string("settings.entries.per.day", language: settings.language), info: .entriesPerDay)
            Spacer()
            HStack(spacing: 10) {
                settingsStepperButton(
                    systemName: "minus",
                    isDisabled: settings.dailyItemCount <= 1
                ) {
                    settings.dailyItemCount = max(1, settings.dailyItemCount - 1)
                }

                Text(localizedCountText(settings.dailyItemCount))
                    .font(.body.monospacedDigit())
                    .foregroundStyle(Color.brandAccent)

                settingsStepperButton(
                    systemName: "plus",
                    isDisabled: settings.dailyItemCount >= 10
                ) {
                    settings.dailyItemCount = min(10, settings.dailyItemCount + 1)
                }
            }
        }
        .frame(minHeight: scaledSettingsRowHeight)
    }

    private var otherSettingsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                infoTitle(L10n.string("settings.apple.id.connect", language: settings.language), info: .appleId)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .layoutPriority(1)
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
            .frame(minHeight: scaledSettingsRowHeight)

            Divider().overlay(Color.gray.opacity(0.3))

            HStack {
                infoTitle(L10n.string("settings.faceid.lock", language: settings.language), info: .faceId)
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
                .disabled(isFaceIdAuthenticating)
            }
            .frame(minHeight: scaledSettingsRowHeight)

            Divider().overlay(Color.gray.opacity(0.3))

            HStack {
                infoTitle(L10n.string("settings.score.day", language: settings.language), info: .scoreDay)
                Spacer()
                Toggle("", isOn: Binding(get: { settings.scoreEnabled }, set: { settings.scoreEnabled = $0 }))
                    .labelsHidden()
            }
            .frame(minHeight: scaledSettingsRowHeight)

            Divider().overlay(Color.gray.opacity(0.3))

            HStack {
                infoTitle(L10n.string("settings.statistics", language: settings.language), info: .statistics)
                Spacer()
                Toggle("", isOn: Binding(get: { settings.statisticsEnabled }, set: { settings.statisticsEnabled = $0 }))
                    .labelsHidden()
            }
            .frame(minHeight: scaledSettingsRowHeight)

            Divider().overlay(Color.gray.opacity(0.3))

            HStack {
                infoTitle(L10n.string("settings.holidays", language: settings.language), info: .holidays)
                Spacer()
                Toggle("", isOn: Binding(get: { settings.holidaysEnabled }, set: { settings.holidaysEnabled = $0 }))
                    .labelsHidden()
            }
            .frame(minHeight: scaledSettingsRowHeight)

            Divider().overlay(Color.gray.opacity(0.3))

            HStack {
                infoTitle(L10n.string("settings.moon.info", language: settings.language), info: .moonInfo)
                Spacer()
                Toggle("", isOn: Binding(get: { settings.moonEnabled }, set: { settings.moonEnabled = $0 }))
                    .labelsHidden()
            }
            .frame(minHeight: scaledSettingsRowHeight)

        }
        .tint(.brandAccent)
    }

    private var secretMenuSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            deleteAllEntriesSection
            Divider().overlay(Color.gray.opacity(0.3))
            secretActionRow(
                title: L10n.string("settings.secret.snapshot", language: settings.language),
                yesAction: {
                    AppleSyncManager.shared.captureSnapshotNow(modelContext: modelContext,
                                                               settings: settings,
                                                               isConnected: settings.appleIdConnected)
                    closeSecretMenu()
                }
            )
            Divider().overlay(Color.gray.opacity(0.3))
            secretActionRow(
                title: L10n.string("settings.secret.access", language: settings.language),
                yesAction: {
                    hasSeenAccessScreen = false
                    closeSecretMenu()
                }
            )
            Divider().overlay(Color.gray.opacity(0.3))
            secretActionRow(
                title: L10n.string("settings.secret.import", language: settings.language),
                yesAction: {
                    showImportPicker = true
                    closeSecretMenu()
                }
            )
        }
    }

    private func secretActionRow(title: String, yesAction: @escaping () -> Void) -> some View {
        HStack {
            Text(title)
                .font(.body.weight(.semibold))
            Spacer()
            HStack(spacing: 8) {
                deleteAllActionButton(
                    title: L10n.string("common.no", language: settings.language),
                    background: Color(.systemGray5),
                    foreground: .primary
                ) {
                    closeSecretMenu()
                }
                deleteAllActionButton(
                    title: L10n.string("common.yes", language: settings.language),
                    background: Color.brandAccent.opacity(0.2),
                    foreground: .primary
                ) {
                    yesAction()
                }
            }
        }
        .frame(height: secretRowHeight)
    }

    private var addDaySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                infoTitle(addDayTitle, info: .addDay)

                Spacer(minLength: 8)

                HStack(spacing: 8) {
                    addDayInputField

                    Button {
                        handleAddDay()
                    } label: {
                        Image(systemName: addDayHasExistingEntry ? "xmark" : "checkmark")
                            .font(.system(size: addDayButtonFontSize * responsiveTypeScale, weight: .semibold))
                            .frame(width: addDayButtonSize * responsiveTypeScale,
                                   height: addDayButtonSize * responsiveTypeScale)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(addDayHasExistingEntry ? Color.red.opacity(0.15) : Color.brandAccent)
                            )
                            .foregroundStyle(addDayHasExistingEntry ? .red : .white)
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
                .foregroundStyle(colorScheme == .dark ? .white : .primary)
                .allowsHitTesting(false)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 100, height: 21)
        .padding(.vertical, 3)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(settingsCardOuterBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.gray.opacity(0.3), lineWidth: 1)
        )
    }

    private var settingsCardOuterBackground: Color {
        colorScheme == .dark ? Color.brandBackground : Color(.systemGray6)
    }

    private var reminderSettingsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                infoTitle(L10n.string("settings.reminder.evening", language: settings.language), info: .reminderEvening)
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
            .frame(minHeight: scaledSettingsRowHeight)

            Divider().overlay(Color.gray.opacity(0.3))

            HStack {
                infoTitle(L10n.string("settings.reminder.next.day", language: settings.language), info: .reminderNextDay)
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
            .frame(minHeight: scaledSettingsRowHeight)

            if notifier.authorizationStatus == .denied,
               (dailyReminderEnabled || nextDayReminderEnabled) {
                Text(L10n.string("settings.notifications.disabled", language: settings.language))
                    .font(.footnote)
                    .foregroundStyle(.primary)
            }
        }
        .tint(.brandAccent)
    }

    private var settingsForm: some View {
        Form {
            if showSecretMenu {
                Section {
                    secretMenuSection
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
        .animation(.easeInOut(duration: 0.12), value: settings.language)
    }

    private var inlineSettings: some View {
        VStack(alignment: .leading, spacing: 0) {
            if showSecretMenu {
                secretMenuSection
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
        .animation(.easeInOut(duration: 0.12), value: settings.language)
    }

    var body: some View {
        ZStack {
            if showsNavigation {
                NavigationStack {
                    settingsForm
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .principal) {
                                Text(L10n.string("settings.title", language: settings.language))
                                    .font(.headline)
                                    .onTapGesture(count: 5) {
                                        withAnimation(.easeInOut(duration: 0.2)) {
                                            showSecretMenu = true
                                        }
                                    }
                            }
                        }
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button(L10n.string("common.done", language: settings.language)) {
                                    // Dismiss handled by parent sheet
                                }
                            }
                        }
                }
                .zIndex(0)
            } else {
                inlineSettings
                    .zIndex(0)
            }

            infoOverlay
                .zIndex(100)
        }
        .coordinateSpace(name: "settingsView")
        .onPreferenceChange(SettingsInfoFramePreferenceKey.self) { frames in
            infoFrames = frames
        }
        .onPreferenceChange(SettingsInfoPopoverSizePreferenceKey.self) { newSize in
            infoPopoverSize = newSize
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
        .alert(L10n.string("settings.import.error.title", language: settings.language),
               isPresented: Binding(
                get: { importErrorMessage != nil },
                set: { newValue in
                    if !newValue { importErrorMessage = nil }
                }
               )) {
            Button(L10n.string("common.close", language: settings.language), role: .cancel) { }
        } message: {
            Text(importErrorMessage ?? "")
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
        .onChange(of: showSecretMenu) { _, newValue in
            if !newValue {
                isDeleteAllConfirming = false
            }
        }
        .fileImporter(isPresented: $showImportPicker,
                      allowedContentTypes: [.commaSeparatedText],
                      allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                handleImportFile(url: url)
            case .failure:
                importErrorMessage = L10n.string("settings.import.error.format", language: settings.language)
            }
        }
    }

    private var infoOverlay: some View {
        GeometryReader { proxy in
            if let info = activeInfo, let anchor = infoFrames[info] {
                let horizontalPadding: CGFloat = 16
                let verticalSpacing: CGFloat = 6
                let maxWidth: CGFloat = 320
                let availableWidth = min(maxWidth, proxy.size.width - (horizontalPadding * 2))
                let clampedX = min(
                    max(anchor.minX, horizontalPadding),
                    proxy.size.width - horizontalPadding - availableWidth
                )
                let proposedY = anchor.maxY + verticalSpacing
                let maxY = proxy.size.height - infoPopoverSize.height - 12
                let clampedY = min(proposedY, max(12, maxY))

                ZStack(alignment: .topLeading) {
                    Color.black.opacity(0.001)
                        .ignoresSafeArea()
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.18)) {
                                activeInfo = nil
                            }
                        }

                    infoPopover(text: infoPopoverText(for: info))
                        .frame(width: availableWidth, alignment: .leading)
                        .offset(x: clampedX, y: clampedY)
                        .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .topLeading)))
                }
            }
        }
    }

    private var scaledSettingsRowHeight: CGFloat {
        settingsRowHeight * responsiveTypeScale
    }

    private var secretRowHeight: CGFloat {
        scaledSettingsRowHeight * secretRowHeightMultiplier
    }

    private var deleteAllConfirmationTitle: String {
        if isDeleteAllConfirming {
            return L10n.string("settings.delete.confirm", language: settings.language)
        }
        return L10n.string("settings.delete.all", language: settings.language)
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
                settings.appleSnapshotDeletionPending = true
                showAddDayMessage(L10n.string("settings.day.deleted", language: settings.language), isError: false)
            }
            addDayDigits = ""
            addDayText = ""
            return
        }

        guard isAddDayWithinRange(normalizedDay) else {
            showAddDayMessage(L10n.string("settings.day.range", language: settings.language))
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

    private func isAddDayWithinRange(_ date: Date) -> Bool {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        guard let minDate = calendar.date(byAdding: .year, value: -100, to: today),
              let maxDate = calendar.date(byAdding: .year, value: 100, to: today) else {
            return true
        }
        return date >= minDate && date <= maxDate
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
        let digitColor = Color.primary
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

    private func settingsPickerLabel(text: String, flag: String) -> some View {
        HStack(spacing: 6) {
            Text(text)
                .foregroundStyle(.primary)
                .contentTransition(.opacity)
                .animation(.easeInOut(duration: 0.2), value: text)
            Text(flag)
            Image(systemName: "chevron.down")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.brandAccent)
        }
    }

    private func localizedCountText(_ count: Int) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: settings.language.localeIdentifier)
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: count)) ?? "\(count)"
    }

    private func infoTitle(_ title: String, info: SettingsInfo) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                if activeInfo == info {
                    activeInfo = nil
                } else {
                    activeInfo = info
                }
            }
        } label: {
            Text(title)
                .font(.body.weight(.semibold))
                .foregroundStyle(.primary)
                .contentTransition(.opacity)
                .animation(.easeInOut(duration: 0.2), value: title)
        }
        .buttonStyle(.plain)
        .background(
            GeometryReader { proxy in
                Color.clear.preference(
                    key: SettingsInfoFramePreferenceKey.self,
                    value: [info: proxy.frame(in: .named("settingsView"))]
                )
            }
        )
    }

    private func infoPopover(text: String) -> some View {
        Text(text)
            .font(.body)
            .foregroundStyle(.primary)
            .multilineTextAlignment(.leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: 320, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(.systemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.brandAccent, lineWidth: 2.5)
            )
            .shadow(color: Color.black.opacity(0.12), radius: 8, x: 0, y: 4)
            .padding(8)
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(key: SettingsInfoPopoverSizePreferenceKey.self, value: proxy.size)
                }
            )
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.18)) {
                    activeInfo = nil
                }
            }
    }

    private func infoPopoverText(for info: SettingsInfo) -> String {
        switch info {
        case .language:
            return L10n.string("settings.info.language", language: settings.language)
        case .addDay:
            return L10n.string("settings.info.add.day", language: settings.language)
        case .entriesPerDay:
            return L10n.string("settings.info.entries.per.day", language: settings.language)
        case .appleId:
            return L10n.string("settings.info.apple.id", language: settings.language)
        case .faceId:
            return L10n.string("settings.info.faceid", language: settings.language)
        case .scoreDay:
            return L10n.string("settings.info.score.day", language: settings.language)
        case .statistics:
            return L10n.string("settings.info.statistics", language: settings.language)
        case .holidays:
            return L10n.string("settings.info.holidays", language: settings.language)
        case .moonInfo:
            return L10n.string("settings.info.moon", language: settings.language)
        case .reminderEvening:
            return L10n.string("settings.info.reminder.evening", language: settings.language)
        case .reminderNextDay:
            return L10n.string("settings.info.reminder.next.day", language: settings.language)
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
                .font(.system(size: stepperFontSize * responsiveTypeScale, weight: .semibold))
                .frame(width: stepperButtonSize * responsiveTypeScale,
                       height: stepperButtonSize * responsiveTypeScale)
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

    private func deleteAllEntries() {
        let descriptor = FetchDescriptor<DayEntry>()
        let entriesToDelete = (try? modelContext.fetch(descriptor)) ?? []
        entriesToDelete.forEach { _ = $0.items.count }
        entriesToDelete.forEach { entry in
            modelContext.delete(entry)
        }
        try? modelContext.save()
        settings.appleSnapshotDeletionPending = true
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

    private func closeSecretMenu() {
        withAnimation(.easeInOut(duration: 0.2)) {
            showSecretMenu = false
        }
        isDeleteAllConfirming = false
    }

    private func handleImportFile(url: URL) {
        let canAccess = url.startAccessingSecurityScopedResource()
        defer {
            if canAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        guard let data = try? Data(contentsOf: url),
              let contents = String(data: data, encoding: .utf8) else {
            importErrorMessage = L10n.string("settings.import.error.format", language: settings.language)
            return
        }

        switch parseImportContents(contents) {
        case .success(let result):
            mergeImportedEntries(result.entries)
        case .failure(let error):
            if case .issues(let issues) = error {
                importErrorMessage = importErrorMessage(for: issues)
            } else {
                importErrorMessage = L10n.string("settings.import.error.format", language: settings.language)
            }
        }
    }

    private struct ImportResult {
        let entries: [DayEntry]
    }

    private enum ImportIssue: Hashable {
        case fileFormat
        case date
        case number
        case entry
        case score
    }

    private enum ImportError: Error {
        case issues(Set<ImportIssue>)
    }

    private func parseImportContents(_ contents: String) -> Result<ImportResult, ImportError> {
        let rawLines = contents
            .split(whereSeparator: \.isNewline)
            .map { String($0) }
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        guard !rawLines.isEmpty else {
            return .failure(.issues([.fileFormat]))
        }

        var lines = rawLines
        if let first = lines.first {
            let fields = parseCSVLine(first)
            if fields.first?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "date" {
                lines.removeFirst()
            }
        }

        guard !lines.isEmpty else {
            return .failure(.issues([.fileFormat]))
        }

        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateFormat = "dd-MM-yyyy"

        var issues: Set<ImportIssue> = []
        var entriesByDate: [Date: [Int: String]] = [:]
        var maxNumberByDate: [Date: Int] = [:]
        var scoresByDate: [Date: Int] = [:]

        for line in lines {
            let fields = parseCSVLine(line)
            guard fields.count == 3 || fields.count == 4 else {
                issues.insert(.fileFormat)
                continue
            }

            let dateText = fields[0].trimmingCharacters(in: .whitespacesAndNewlines)
            guard let date = dateFormatter.date(from: dateText) else {
                issues.insert(.date)
                continue
            }
            let normalizedDate = Calendar.current.startOfDay(for: date)

            let numberText = fields[1].trimmingCharacters(in: .whitespacesAndNewlines)
            guard let number = Int(numberText), (1...10).contains(number) else {
                issues.insert(.number)
                continue
            }

            let entryText = fields[2].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !entryText.isEmpty else {
                issues.insert(.entry)
                continue
            }

            if fields.count == 4 {
                let scoreText = fields[3].trimmingCharacters(in: .whitespacesAndNewlines)
                if !scoreText.isEmpty {
                    guard let parsed = Int(scoreText) else {
                        issues.insert(.score)
                        continue
                    }
                    if let existingScore = scoresByDate[normalizedDate], existingScore != parsed {
                        issues.insert(.score)
                        continue
                    }
                    scoresByDate[normalizedDate] = parsed
                }
            }

            var existing = entriesByDate[normalizedDate, default: [:]]
            existing[number] = entryText
            entriesByDate[normalizedDate] = existing
            maxNumberByDate[normalizedDate] = max(maxNumberByDate[normalizedDate] ?? 0, number)

        }

        guard issues.isEmpty else {
            return .failure(.issues(issues))
        }

        let entries = entriesByDate.map { date, itemsByNumber in
            let maxNumber = maxNumberByDate[date] ?? 1
            let entry = DayEntry(day: date, itemCount: maxNumber)
            for (number, text) in itemsByNumber {
                let index = number - 1
                if index >= 0, index < entry.items.count {
                    entry.items[index] = text
                }
            }
            entry.isLocked = true
            entry.wasCompleted = true
            entry.score = scoresByDate[date]
            return entry
        }

        return .success(ImportResult(entries: entries))
    }

    private func mergeImportedEntries(_ entries: [DayEntry]) {
        for entry in entries {
            let normalizedDate = Calendar.current.startOfDay(for: entry.day)
            let descriptor = FetchDescriptor<DayEntry>(
                predicate: #Predicate { $0.day == normalizedDate }
            )
            if let existing = try? modelContext.fetch(descriptor).first {
                existing.itemCount = entry.itemCount
                existing.items = entry.items
                existing.isLocked = true
                existing.wasCompleted = true
                if let score = entry.score {
                    existing.score = score
                }
                existing.updatedAt = Date()
            } else {
                modelContext.insert(entry)
            }
        }
        try? modelContext.save()
    }

    private func parseCSVLine(_ line: String) -> [String] {
        var fields: [String] = []
        var current = ""
        var inQuotes = false
        var iterator = line.makeIterator()
        var previousWasQuote = false

        while let char = iterator.next() {
            if inQuotes {
                if char == "\"" {
                    if let next = iterator.next() {
                        if next == "\"" {
                            current.append("\"")
                            previousWasQuote = false
                        } else if next == "," {
                            inQuotes = false
                            fields.append(current)
                            current = ""
                            previousWasQuote = false
                        } else {
                            inQuotes = false
                            current.append(next)
                            previousWasQuote = false
                        }
                    } else {
                        inQuotes = false
                        previousWasQuote = true
                    }
                } else {
                    current.append(char)
                    previousWasQuote = false
                }
            } else {
                if char == "\"" {
                    inQuotes = true
                } else if char == "," {
                    fields.append(current)
                    current = ""
                } else {
                    current.append(char)
                }
            }
        }

        if previousWasQuote || !current.isEmpty || line.hasSuffix(",") {
            fields.append(current)
        }
        return fields
    }

    private func importErrorMessage(for issues: Set<ImportIssue>) -> String {
        var parts: [String] = []
        if issues.contains(.fileFormat) {
            parts.append(L10n.string("settings.import.error.format", language: settings.language))
        }
        if issues.contains(.date) {
            parts.append(L10n.string("settings.import.error.date", language: settings.language))
        }
        if issues.contains(.number) {
            parts.append(L10n.string("settings.import.error.number", language: settings.language))
        }
        if issues.contains(.entry) {
            parts.append(L10n.string("settings.import.error.entry", language: settings.language))
        }
        if issues.contains(.score) {
            parts.append(L10n.string("settings.import.error.score", language: settings.language))
        }
        return parts.joined(separator: "\n")
    }
}
