//NEW DOC  SettingsView.swift
import AuthenticationServices
import SwiftUI
import SwiftData
import UIKit
import UniformTypeIdentifiers

private struct TabletSettingsSwitchModifier: ViewModifier {
    let isTabletLayout: Bool

    func body(content: Content) -> some View {
        let scale: CGFloat = isTabletLayout ? 1.10 : 1
        content
            .scaleEffect(scale, anchor: .trailing)
            .frame(width: 51 * scale, height: 31 * scale, alignment: .trailing)
    }
}

private extension View {
    func tabletSettingsSwitch(isTabletLayout: Bool) -> some View {
        modifier(TabletSettingsSwitchModifier(isTabletLayout: isTabletLayout))
    }
}

struct SettingsView: View {
    @ObservedObject var settings: SettingsStore
    @Binding var showSecretMenu: Bool
    @Binding var requestedInfo: SettingsInfo?
    var showsNavigation: Bool = true
    var isSettingsCardExpanded: Bool = true
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
    @ScaledMetric(relativeTo: .body) private var bodyFontSize: CGFloat = 17
    @ScaledMetric(relativeTo: .headline) private var headlineFontSize: CGFloat = 17
    @ScaledMetric(relativeTo: .footnote) private var footnoteFontSize: CGFloat = 13
    @ScaledMetric(relativeTo: .caption) private var captionFontSize: CGFloat = 12
    @ScaledMetric(relativeTo: .body) private var addDayInputFontSize: CGFloat = 15

    @State private var dailyReminderEnabled: Bool = false
    @State private var nextDayReminderEnabled: Bool = false
    @State private var dailyReminderPickerDate: Date = Date()
    @State private var nextDayReminderPickerDate: Date = Date()
    @State private var appleIdConnected: Bool = false
    @State private var addDayDigits: String = ""
    @State private var addDayText: String = ""
    @State private var addDayMessage: String?
    @State private var addDayMessageIsError: Bool = true
    @State private var addDayMessageTask: Task<Void, Never>?
    @State private var addDayHasExistingEntry = false
    @State private var addDayFieldFocused: Bool = false
    @State private var isSigningInWithApple: Bool = false
    @State private var showImportPicker: Bool = false
    @State private var importErrorMessage: String?
    @AppStorage("hasSeenAccessScreen") private var hasSeenAccessScreen: Bool = false
    @State private var showLanguagePicker: Bool = false
    private let defaultDailyReminderTime = ReminderTime(hour: 21, minute: 55)
    private let defaultNextDayReminderTime = ReminderTime(hour: 9, minute: 0)
    private let secretRowHeightMultiplier: CGFloat = 1.5
    @State private var isDeleteAllConfirming: Bool = false
    @State private var activeInfo: SettingsInfo?
    @State private var infoFrames: [SettingsInfo: CGRect] = [:]
    @State private var infoPopoverSize: CGSize = .zero

    init(
        settings: SettingsStore,
        showSecretMenu: Binding<Bool>,
        requestedInfo: Binding<SettingsInfo?>,
        showsNavigation: Bool = true,
        isSettingsCardExpanded: Bool = true
    ) {
        self.settings = settings
        self._showSecretMenu = showSecretMenu
        self._requestedInfo = requestedInfo
        self.showsNavigation = showsNavigation
        self.isSettingsCardExpanded = isSettingsCardExpanded

        let defaultDailyTime = ReminderTime(hour: 21, minute: 55)
        let defaultNextDayTime = ReminderTime(hour: 9, minute: 0)

        let dailyPickerDate = settings.dailyReminderTime
            .flatMap { Calendar.current.date(from: $0.asDateComponents()) }
            ?? Self.defaultReminderDate(for: defaultDailyTime)
        let nextDayPickerDate = settings.nextDayReminderTime
            .flatMap { Calendar.current.date(from: $0.asDateComponents()) }
            ?? Self.defaultReminderDate(for: defaultNextDayTime)

        _dailyReminderEnabled = State(initialValue: settings.dailyReminderTime != nil)
        _nextDayReminderEnabled = State(initialValue: settings.nextDayReminderTime != nil)
        _dailyReminderPickerDate = State(initialValue: dailyPickerDate)
        _nextDayReminderPickerDate = State(initialValue: nextDayPickerDate)
    }

    enum SettingsInfo {
        case language
        case addDay
        case entriesPerDay
        case appleId
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

    private final class WarningSwitch: UISwitch {
        var showsDisconnectedWarning: Bool = false {
            didSet { updateAppearance() }
        }
        var warningOffColor: UIColor = .clear {
            didSet { updateAppearance() }
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            updateAppearance()
        }

        override func setOn(_ on: Bool, animated: Bool) {
            super.setOn(on, animated: animated)
            updateAppearance()
        }

        private func updateAppearance() {
            guard showsDisconnectedWarning, !isOn else {
                layer.borderColor = nil
                layer.borderWidth = 0
                return
            }

            backgroundColor = warningOffColor
            tintColor = warningOffColor
            layer.cornerRadius = bounds.height / 2
            layer.masksToBounds = true

            if let track = subviews.first?.subviews.first {
                track.backgroundColor = warningOffColor
                track.layer.cornerRadius = bounds.height / 2
                track.layer.masksToBounds = true
            }
        }
    }

    private struct AppleIdSwitch: UIViewRepresentable {
        @Binding var isOn: Bool
        let showsDisconnectedWarning: Bool
        let isEnabled: Bool

        func makeUIView(context: Context) -> UISwitch {
            let uiSwitch = WarningSwitch()
            uiSwitch.addTarget(context.coordinator, action: #selector(Coordinator.valueChanged), for: .valueChanged)
            return uiSwitch
        }

        func updateUIView(_ uiView: UISwitch, context: Context) {
            let shouldAnimate = context.transaction.animation != nil
            uiView.setOn(isOn, animated: shouldAnimate)
            uiView.isEnabled = isEnabled
            uiView.onTintColor = UIColor(Color.brandAccent)
            let warningOffColor = UIColor(Color.red.opacity(0.15))
            if let warningSwitch = uiView as? WarningSwitch {
                warningSwitch.warningOffColor = warningOffColor
                warningSwitch.showsDisconnectedWarning = showsDisconnectedWarning
            }
        }

        func makeCoordinator() -> Coordinator {
            Coordinator(isOn: $isOn)
        }

        final class Coordinator: NSObject {
            private var isOn: Binding<Bool>

            init(isOn: Binding<Bool>) {
                self.isOn = isOn
            }

            @objc func valueChanged(_ sender: UISwitch) {
                isOn.wrappedValue = sender.isOn
            }
        }
    }

    private var languageSection: some View {
        HStack {
            infoTitle(L10n.string("settings.app.language", language: settings.language), info: .language)
            Spacer()
            Button {
                showLanguagePicker = true
            } label: {
                settingsPickerLabel(text: settings.language.shortDisplayName, flag: settings.language.flagEmoji)
            }
        }
        .frame(minHeight: scaledSettingsRowHeight)
        .tint(.brandAccent)
        .sheet(isPresented: $showLanguagePicker) {
            VStack(spacing: 12) {
                HStack {
                    Text(L10n.string("settings.app.language", language: settings.language))
                        .font(.system(size: headlineFontSize * responsiveTypeScale, weight: .semibold))
                    Spacer()
                    Button(L10n.string("common.done", language: settings.language)) {
                        showLanguagePicker = false
                    }
                    .font(.system(size: headlineFontSize * responsiveTypeScale, weight: .semibold))
                    .foregroundStyle(Color.brandAccent)
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)

                Picker("", selection: Binding(
                    get: { settings.language },
                    set: { settings.language = $0 }
                )) {
                    ForEach(AppLanguage.orderedByLanguageName) { lang in
                        HStack {
                            Text(lang.displayName)
                            Spacer()
                            Text(lang.flagEmoji)
                        }
                        .padding(.horizontal, 20)
                        .tag(lang)
                    }
                }
                .font(.system(size: addDayInputFontSize * responsiveTypeScale))
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
                .font(.system(size: bodyFontSize * responsiveTypeScale, weight: .semibold))
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
                    .font(.system(size: bodyFontSize * responsiveTypeScale))
                    .monospacedDigit()
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
                AppleIdSwitch(isOn: Binding(
                    get: { appleIdConnected },
                    set: { newValue in
                        handleAppleIdToggleChange(newValue)
                    }
                ),
                showsDisconnectedWarning: settings.appleIdEverConnected && !appleIdConnected,
                isEnabled: !isSigningInWithApple)
                    .accessibilityLabel(L10n.string("settings.apple.id.connect", language: settings.language))
                    .tabletSettingsSwitch(isTabletLayout: responsiveTypeScale >= 1.30)
            }
            .frame(minHeight: scaledSettingsRowHeight)

            Divider().overlay(Color.gray.opacity(0.3))

            HStack {
                infoTitle(L10n.string("settings.score.day", language: settings.language), info: .scoreDay)
                Spacer()
                Toggle("", isOn: Binding(get: { settings.scoreEnabled }, set: { settings.scoreEnabled = $0 }))
                    .labelsHidden()
                    .tabletSettingsSwitch(isTabletLayout: responsiveTypeScale >= 1.30)
            }
            .frame(minHeight: scaledSettingsRowHeight)

            Divider().overlay(Color.gray.opacity(0.3))

            HStack {
                infoTitle(L10n.string("settings.statistics", language: settings.language), info: .statistics)
                Spacer()
                Toggle("", isOn: Binding(get: { settings.statisticsEnabled }, set: { settings.statisticsEnabled = $0 }))
                    .labelsHidden()
                    .tabletSettingsSwitch(isTabletLayout: responsiveTypeScale >= 1.30)
            }
            .frame(minHeight: scaledSettingsRowHeight)

            Divider().overlay(Color.gray.opacity(0.3))

            HStack {
                infoTitle(L10n.string("settings.holidays", language: settings.language), info: .holidays)
                Spacer()
                Toggle("", isOn: Binding(get: { settings.holidaysEnabled }, set: { settings.holidaysEnabled = $0 }))
                    .labelsHidden()
                    .tabletSettingsSwitch(isTabletLayout: responsiveTypeScale >= 1.30)
            }
            .frame(minHeight: scaledSettingsRowHeight)

            Divider().overlay(Color.gray.opacity(0.3))

            HStack {
                infoTitle(L10n.string("settings.moon.info", language: settings.language), info: .moonInfo)
                Spacer()
                Toggle("", isOn: Binding(get: { settings.moonEnabled }, set: { settings.moonEnabled = $0 }))
                    .labelsHidden()
                    .tabletSettingsSwitch(isTabletLayout: responsiveTypeScale >= 1.30)
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
                .font(.system(size: bodyFontSize * responsiveTypeScale, weight: .semibold))
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

            if let rangeWarning = addDayRangeWarning {
                Text(rangeWarning)
                    .font(.system(size: footnoteFontSize * responsiveTypeScale))
                    .foregroundStyle(.red)
            }

            if let instruction = addDayInstructionText {
                Text(instruction.text)
                    .font(.system(size: footnoteFontSize * responsiveTypeScale))
                    .foregroundStyle(instruction.isError ? .red : Color.brandAccent)
            }

            if let message = addDayMessage {
                Text(message)
                    .font(.system(size: footnoteFontSize * responsiveTypeScale))
                    .foregroundStyle(addDayMessageIsError ? .red : Color.brandAccent)
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

    private var addDayRangeWarning: String? {
        guard addDayDigits.count == 8,
              let selectedDay = parseAddDayDate() else {
            return nil
        }
        return isAddDayWithinRange(selectedDay)
            ? nil
            : L10n.string("settings.day.range", language: settings.language)
    }

    private var addDayInstructionText: (text: String, isError: Bool)? {
        guard addDayDigits.count == 8,
              let selectedDay = parseAddDayDate(),
              isAddDayWithinRange(selectedDay) else {
            return nil
        }

        if addDayHasExistingEntry {
            return (L10n.string("settings.day.delete.hint", language: settings.language), true)
        }

        return (L10n.string("settings.day.create.hint", language: settings.language), false)
    }

    private var addDayFormat: AddDayDateFormat {
        AddDayDateFormat.format(for: settings.language)
    }

    private var addDayInputField: some View {
        let format = addDayFormat
        let fieldWidth = addDayFieldWidth(for: format)
        return ZStack(alignment: .leading) {
            AddDayTextField(text: $addDayText,
                            isFocused: $addDayFieldFocused,
                            accessibilityLabel: L10n.string("common.date", language: settings.language),
                            accessibilityHint: format.accessibilityHint) { oldValue, newValue in
                let filtered = newValue.filter(\.isWholeNumber)
                var nextDigits = String(filtered.prefix(8))
                if newValue.count < oldValue.count,
                   oldValue.hasSuffix(format.separator),
                   !newValue.hasSuffix(format.separator),
                   format.separatorPositions.contains(nextDigits.count),
                   !nextDigits.isEmpty {
                    nextDigits = String(nextDigits.dropLast())
                }
                addDayDigits = nextDigits
                addDayMessage = nil
                updateAddDayExistingEntry()
                let formatted = formattedAddDayDigits(nextDigits)
                if nextDigits.count == 8 {
                    addDayFieldFocused = false
                }
                return formatted
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(addDayDisplayText(addDayDigits))
                .font(.system(size: addDayInputFontSize * responsiveTypeScale))
                .monospacedDigit()
                .foregroundStyle(Color.brandAccent)
                .allowsHitTesting(false)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: fieldWidth,
               height: max(21, (addDayInputFontSize * responsiveTypeScale) + 4))
        .padding(.vertical, 3)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(addDayFieldBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.gray.opacity(0.3), lineWidth: 1)
        )
    }

    private func addDayFieldWidth(for format: AddDayDateFormat) -> CGFloat {
        let font = UIFont.monospacedDigitSystemFont(ofSize: addDayInputFontSize * responsiveTypeScale,
                                                    weight: .regular)
        let formatText = format.formatString as NSString
        let width = formatText.size(withAttributes: [.font: font]).width
        return ceil(width + 2)
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
                    reminderTimePicker(isVisible: isSettingsCardExpanded,
                                       selection: $dailyReminderPickerDate) { newValue in
                        settings.dailyReminderTime = ReminderTime.from(date: newValue)
                    }
                }
                Toggle("", isOn: $dailyReminderEnabled)
                    .labelsHidden()
                    .tabletSettingsSwitch(isTabletLayout: responsiveTypeScale >= 1.30)
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
                    reminderTimePicker(isVisible: isSettingsCardExpanded,
                                       selection: $nextDayReminderPickerDate) { newValue in
                        settings.nextDayReminderTime = ReminderTime.from(date: newValue)
                    }
                }
                Toggle("", isOn: $nextDayReminderEnabled)
                    .labelsHidden()
                    .tabletSettingsSwitch(isTabletLayout: responsiveTypeScale >= 1.30)
            }
            .frame(minHeight: scaledSettingsRowHeight)

            if notifier.authorizationStatus == .denied,
               (dailyReminderEnabled || nextDayReminderEnabled) {
                Text(L10n.string("settings.notifications.disabled", language: settings.language))
                    .font(.system(size: footnoteFontSize * responsiveTypeScale))
                    .foregroundStyle(.primary)
            }
        }
        .tint(.brandAccent)
    }

    private func reminderTimePicker(
        isVisible: Bool,
        selection: Binding<Date>,
        onChange: @escaping (Date) -> Void
    ) -> some View {
        DatePicker("",
                   selection: selection,
                   displayedComponents: .hourAndMinute)
            .labelsHidden()
            .datePickerStyle(.compact)
            .foregroundStyle(Color.brandAccent)
            .padding(.trailing, responsiveTypeScale >= 1.30 ? 14 : 10)
            .opacity(isVisible ? 1 : 0)
            .animation(.easeInOut(duration: 0.2), value: isVisible)
            .allowsHitTesting(isVisible)
            .onChange(of: selection.wrappedValue) { _, newValue in
                onChange(newValue)
            }
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
                                    .font(.system(size: headlineFontSize * responsiveTypeScale, weight: .semibold))
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
        .controlSize(responsiveTypeScale >= 1.30 ? .large : .regular)
        .coordinateSpace(name: "settingsView")
        .onPreferenceChange(SettingsInfoFramePreferenceKey.self) { frames in
            infoFrames = frames
        }
        .onPreferenceChange(SettingsInfoPopoverSizePreferenceKey.self) { newSize in
            infoPopoverSize = newSize
        }
        .onChange(of: requestedInfo) { _, newValue in
            guard let newValue else { return }
            withAnimation(.easeInOut(duration: 0.18)) {
                activeInfo = newValue
            }
            requestedInfo = nil
        }
        .task {
            await notifier.refreshAuthorizationStatus()

            // Hydrate toggles from stored optionals
            dailyReminderEnabled = (settings.dailyReminderTime != nil)
            nextDayReminderEnabled = (settings.nextDayReminderTime != nil)

            if let rt = settings.dailyReminderTime {
                dailyReminderPickerDate = Calendar.current.date(from: rt.asDateComponents()) ?? Date()
            } else {
                dailyReminderPickerDate = Self.defaultReminderDate(for: defaultDailyReminderTime)
            }
            if let rt = settings.nextDayReminderTime {
                nextDayReminderPickerDate = Calendar.current.date(from: rt.asDateComponents()) ?? Date()
            } else {
                nextDayReminderPickerDate = Self.defaultReminderDate(for: defaultNextDayReminderTime)
            }

            appleIdConnected = settings.appleIdConnected
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
        .onChange(of: settings.language) { _, _ in
            resetAddDayInput()
        }
        .onAppear {
            addDayFieldFocused = false
            if settings.appleIdConnected && !settings.appleIdEverConnected {
                settings.appleIdEverConnected = true
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

    private static func defaultReminderDate(for time: ReminderTime) -> Date {
        Calendar.current.date(from: time.asDateComponents()) ?? Date()
    }

    private func handleAddDay() {
        guard addDayDigits.count == 8 else {
            return
        }

        guard let selectedDay = parseAddDayDate() else {
            return
        }

        let normalizedDay = DayIdentity.canonicalDate(for: DayIdentity.identifier(for: selectedDay))
        let selectedDayIdentifier = DayIdentity.identifier(for: selectedDay)

        let descriptor = FetchDescriptor<DayEntry>()
        let existing = (try? modelContext.fetch(descriptor))?.first { entry in
            entry.normalizedDayIdentifier == selectedDayIdentifier
        }
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

        let entry = DayEntry(dayIdentifier: selectedDayIdentifier, itemCount: settings.dailyItemCount)
        modelContext.insert(entry)
        try? modelContext.save()
        showAddDayMessage(L10n.string("settings.day.added", language: settings.language), isError: false)

        addDayDigits = ""
        addDayText = ""
        addDayHasExistingEntry = false
    }

    private func resetAddDayInput() {
        addDayMessageTask?.cancel()
        addDayDigits = ""
        addDayText = ""
        addDayMessage = nil
        addDayMessageIsError = true
        addDayHasExistingEntry = false
        addDayFieldFocused = false
    }

    private func parseAddDayDate() -> Date? {
        guard let components = addDayFormat.components(from: addDayDigits) else {
            return nil
        }

        return dateFrom(day: components.day, month: components.month, year: components.year)
    }

    private func isAddDayWithinRange(_ date: Date) -> Bool {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        let today = DayIdentity.canonicalDate(for: DayIdentity.todayIdentifier())
        guard let minDate = calendar.date(byAdding: .year, value: -100, to: today),
              let maxDate = calendar.date(byAdding: .year, value: 100, to: today) else {
            return true
        }
        return date >= minDate && date <= maxDate
    }

    private func formattedAddDayDigits(_ digits: String) -> String {
        let format = addDayFormat
        var formatted = ""
        var remaining = digits

        for (index, component) in format.order.enumerated() {
            let length = format.length(for: component)
            let segment = String(remaining.prefix(length))
            formatted.append(segment)
            remaining = String(remaining.dropFirst(segment.count))

            if index < format.order.count - 1, segment.count == length {
                formatted.append(format.separator)
            }
        }

        return formatted
    }

    private func addDayDisplayText(_ digits: String) -> AttributedString {
        let format = addDayFormat
        let digitColor = Color.brandAccent
        let placeholderColor = Color(.systemGray)

        let segments = format.segmentStrings(for: digits)
        var output = AttributedString("")

        for (index, component) in format.order.enumerated() {
            let value = segments[component, default: ""]
            var valueText = AttributedString(value)
            valueText.foregroundColor = digitColor

            let placeholder = format.placeholder(for: component)
            let remainingCount = max(0, placeholder.count - value.count)
            let placeholderSuffix = String(placeholder.suffix(remainingCount))
            var placeholderText = AttributedString(placeholderSuffix)
            placeholderText.foregroundColor = placeholderColor

            output += valueText
            output += placeholderText

            if index < format.order.count - 1 {
                var separatorText = AttributedString(format.separator)
                separatorText.foregroundColor = placeholderColor
                output += separatorText
            }
        }

        return output
    }

    private func updateAddDayExistingEntry() {
        guard addDayDigits.count == 8,
              let selectedDay = parseAddDayDate() else {
            addDayHasExistingEntry = false
            return
        }
        let selectedDayIdentifier = DayIdentity.identifier(for: selectedDay)
        let descriptor = FetchDescriptor<DayEntry>()
        addDayHasExistingEntry = ((try? modelContext.fetch(descriptor))?.contains { entry in
            entry.normalizedDayIdentifier == selectedDayIdentifier
        }) ?? false
    }

    private struct AddDayDateFormat {
        enum Component {
            case day
            case month
            case year
        }

        let order: [Component]
        let separator: String
        let placeholders: [Component: String]

        var accessibilityHint: String {
            formatString
        }

        var separatorPositions: [Int] {
            var positions: [Int] = []
            var total = 0
            for component in order.dropLast() {
                total += length(for: component)
                positions.append(total)
            }
            return positions
        }

        var formatString: String {
            var output = ""
            for (index, component) in order.enumerated() {
                output.append(placeholder(for: component))
                if index < order.count - 1 {
                    output.append(separator)
                }
            }
            return output
        }

        func length(for component: Component) -> Int {
            switch component {
            case .day, .month:
                return 2
            case .year:
                return 4
            }
        }

        func placeholder(for component: Component) -> String {
            let expectedLength = length(for: component)
            let base = placeholders[component] ?? defaultPlaceholder(for: component)
            if base.count == expectedLength {
                return base
            }
            return defaultPlaceholder(for: component)
        }

        func segmentStrings(for digits: String) -> [Component: String] {
            var result: [Component: String] = [:]
            var index = digits.startIndex
            for component in order {
                guard index < digits.endIndex else { break }
                let length = length(for: component)
                let end = digits.index(index, offsetBy: min(length, digits.distance(from: index, to: digits.endIndex)))
                result[component] = String(digits[index..<end])
                index = end
            }
            return result
        }

        func components(from digits: String) -> (day: Int, month: Int, year: Int)? {
            guard digits.count == 8 else { return nil }
            var values: [Component: Int] = [:]
            var index = digits.startIndex
            for component in order {
                let length = length(for: component)
                guard let end = digits.index(index, offsetBy: length, limitedBy: digits.endIndex) else { return nil }
                let segment = String(digits[index..<end])
                guard let value = Int(segment) else { return nil }
                values[component] = value
                index = end
            }
            guard let day = values[.day],
                  let month = values[.month],
                  let year = values[.year] else {
                return nil
            }
            return (day: day, month: month, year: year)
        }

        private func defaultPlaceholder(for component: Component) -> String {
            switch component {
            case .day:
                return "DD"
            case .month:
                return "MM"
            case .year:
                return "YYYY"
            }
        }

        static func format(for language: AppLanguage) -> AddDayDateFormat {
            switch language {
            case .english:
                return monthDayYear(separator: "/", placeholder: ("MM", "DD", "YYYY"))
            case .englishUK:
                return dayMonthYear(separator: "/", placeholder: ("DD", "MM", "YYYY"))
            case .arabic:
                return dayMonthYear(separator: "/", placeholder: ("DD", "MM", "YYYY"))
            case .bengali:
                return dayMonthYear(separator: "/", placeholder: ("DD", "MM", "YYYY"))
            case .catalan:
                return dayMonthYear(separator: "/", placeholder: ("DD", "MM", "AAAA"))
            case .chineseSimplified:
                return yearMonthDay(separator: "-", placeholder: ("YYYY", "MM", "DD"))
            case .chineseTraditional:
                return yearMonthDay(separator: "/", placeholder: ("YYYY", "MM", "DD"))
            case .croatian:
                return dayMonthYear(separator: ".", placeholder: ("DD", "MM", "GGGG"))
            case .czech:
                return dayMonthYear(separator: ".", placeholder: ("DD", "MM", "RRRR"))
            case .danish:
                return dayMonthYear(separator: "-", placeholder: ("DD", "MM", "ÅÅÅÅ"))
            case .dutch:
                return dayMonthYear(separator: "-", placeholder: ("DD", "MM", "JJJJ"))
            case .filipino:
                return dayMonthYear(separator: "/", placeholder: ("DD", "MM", "YYYY"))
            case .finnish:
                return dayMonthYear(separator: ".", placeholder: ("PP", "KK", "VVVV"))
            case .french:
                return dayMonthYear(separator: "/", placeholder: ("JJ", "MM", "AAAA"))
            case .frenchCanada:
                return dayMonthYear(separator: "/", placeholder: ("JJ", "MM", "AAAA"))
            case .german:
                return dayMonthYear(separator: ".", placeholder: ("TT", "MM", "JJJJ"))
            case .greek:
                return dayMonthYear(separator: "/", placeholder: ("ΗΗ", "ΜΜ", "ΕΕΕΕ"))
            case .hebrew:
                return dayMonthYear(separator: "/", placeholder: ("DD", "MM", "YYYY"))
            case .hindi:
                return dayMonthYear(separator: "/", placeholder: ("DD", "MM", "YYYY"))
            case .hungarian:
                return yearMonthDay(separator: ".", placeholder: ("ÉÉÉÉ", "HH", "NN"))
            case .indonesian:
                return dayMonthYear(separator: "/", placeholder: ("HH", "BB", "TTTT"))
            case .italian:
                return dayMonthYear(separator: "/", placeholder: ("GG", "MM", "AAAA"))
            case .japanese:
                return yearMonthDay(separator: "/", placeholder: ("YYYY", "MM", "DD"))
            case .korean:
                return yearMonthDay(separator: ".", placeholder: ("YYYY", "MM", "DD"))
            case .malay:
                return dayMonthYear(separator: "/", placeholder: ("HH", "BB", "TTTT"))
            case .norwegian:
                return dayMonthYear(separator: ".", placeholder: ("DD", "MM", "ÅÅÅÅ"))
            case .polish:
                return dayMonthYear(separator: ".", placeholder: ("DD", "MM", "RRRR"))
            case .portugueseBrazil:
                return dayMonthYear(separator: "/", placeholder: ("DD", "MM", "AAAA"))
            case .portuguesePortugal:
                return dayMonthYear(separator: "/", placeholder: ("DD", "MM", "AAAA"))
            case .romanian:
                return dayMonthYear(separator: ".", placeholder: ("ZZ", "LL", "AAAA"))
            case .russian:
                return dayMonthYear(separator: ".", placeholder: ("ДД", "ММ", "ГГГГ"))
            case .serbian:
                return dayMonthYear(separator: ".", placeholder: ("DD", "MM", "YYYY"))
            case .slovak:
                return dayMonthYear(separator: ".", placeholder: ("DD", "MM", "RRRR"))
            case .slovenian:
                return dayMonthYear(separator: ".", placeholder: ("DD", "MM", "YYYY"))
            case .spanishMexico:
                return dayMonthYear(separator: "/", placeholder: ("DD", "MM", "AAAA"))
            case .spanishSpain:
                return dayMonthYear(separator: "/", placeholder: ("DD", "MM", "AAAA"))
            case .swedish:
                return yearMonthDay(separator: "-", placeholder: ("ÅÅÅÅ", "MM", "DD"))
            case .tamil:
                return dayMonthYear(separator: "/", placeholder: ("DD", "MM", "YYYY"))
            case .thai:
                return dayMonthYear(separator: "/", placeholder: ("วว", "ดด", "ปปปป"))
            case .turkish:
                return dayMonthYear(separator: ".", placeholder: ("GG", "AA", "YYYY"))
            case .ukrainian:
                return dayMonthYear(separator: ".", placeholder: ("ДД", "ММ", "РРРР"))
            case .vietnamese:
                return dayMonthYear(separator: "/", placeholder: ("NN", "TT", "NNNN"))
            }
        }

        private static func dayMonthYear(separator: String,
                                         placeholder: (String, String, String)) -> AddDayDateFormat {
            AddDayDateFormat(order: [.day, .month, .year],
                             separator: separator,
                             placeholders: [.day: placeholder.0, .month: placeholder.1, .year: placeholder.2])
        }

        private static func monthDayYear(separator: String,
                                         placeholder: (String, String, String)) -> AddDayDateFormat {
            AddDayDateFormat(order: [.month, .day, .year],
                             separator: separator,
                             placeholders: [.day: placeholder.1, .month: placeholder.0, .year: placeholder.2])
        }

        private static func yearMonthDay(separator: String,
                                         placeholder: (String, String, String)) -> AddDayDateFormat {
            AddDayDateFormat(order: [.year, .month, .day],
                             separator: separator,
                             placeholders: [.day: placeholder.2, .month: placeholder.1, .year: placeholder.0])
        }
    }

    private struct AddDayTextField: UIViewRepresentable {
        @Binding var text: String
        @Binding var isFocused: Bool
        let accessibilityLabel: String
        let accessibilityHint: String
        let onChange: (_ oldValue: String, _ newValue: String) -> String

        func makeUIView(context: Context) -> UITextField {
            let textField = UITextField()
            textField.keyboardType = .numberPad
            textField.autocorrectionType = .no
            textField.autocapitalizationType = .none
            textField.font = UIFont.monospacedDigitSystemFont(ofSize: UIFont.preferredFont(forTextStyle: .body).pointSize,
                                                              weight: .regular)
            textField.textColor = UIColor.clear
            textField.tintColor = UIColor(Color.brandAccent)
            textField.delegate = context.coordinator
            textField.accessibilityLabel = accessibilityLabel
            textField.accessibilityHint = accessibilityHint
            return textField
        }

        func updateUIView(_ uiView: UITextField, context: Context) {
            if uiView.text != text {
                uiView.text = text
                context.coordinator.previousText = text
            }

            if isFocused, !uiView.isFirstResponder {
                uiView.becomeFirstResponder()
            } else if !isFocused, uiView.isFirstResponder {
                uiView.resignFirstResponder()
            }
        }

        func makeCoordinator() -> Coordinator {
            Coordinator(self)
        }

        final class Coordinator: NSObject, UITextFieldDelegate {
            private let parent: AddDayTextField
            var previousText: String

            init(_ parent: AddDayTextField) {
                self.parent = parent
                self.previousText = parent.text
            }

            func textField(_ textField: UITextField,
                           shouldChangeCharactersIn range: NSRange,
                           replacementString string: String) -> Bool {
                let oldValue = previousText
                let currentText = textField.text ?? ""
                let updatedText = (currentText as NSString).replacingCharacters(in: range, with: string)
                let cursorPosition = range.location + (string as NSString).length
                let digitsBeforeCursor = digitCount(in: updatedText, upTo: cursorPosition)
                let formatted = parent.onChange(oldValue, updatedText)
                previousText = formatted
                textField.text = formatted
                parent.text = formatted
                setCursorPosition(in: textField, digitsBeforeCursor: digitsBeforeCursor, formatted: formatted)
                return false
            }

            func textFieldDidBeginEditing(_ textField: UITextField) {
                if !parent.isFocused {
                    parent.isFocused = true
                }
            }

            func textFieldDidEndEditing(_ textField: UITextField) {
                if parent.isFocused {
                    parent.isFocused = false
                }
            }

            private func digitCount(in text: String, upTo cursorPosition: Int) -> Int {
                guard cursorPosition > 0 else { return 0 }
                let safePosition = max(0, min(cursorPosition, text.count))
                let prefix = String(text.prefix(safePosition))
                return prefix.filter(\.isWholeNumber).count
            }

            private func setCursorPosition(in textField: UITextField, digitsBeforeCursor: Int, formatted: String) {
                let targetOffset = cursorOffset(for: digitsBeforeCursor, formatted: formatted)
                if let position = textField.position(from: textField.beginningOfDocument, offset: targetOffset) {
                    textField.selectedTextRange = textField.textRange(from: position, to: position)
                }
            }

            private func cursorOffset(for digitsCount: Int, formatted: String) -> Int {
                guard digitsCount > 0 else { return 0 }
                let nsText = formatted as NSString
                var digitsSeen = 0
                for index in 0..<nsText.length {
                    let scalarValue = nsText.character(at: index)
                    if let scalar = UnicodeScalar(scalarValue),
                       CharacterSet.decimalDigits.contains(scalar) {
                        digitsSeen += 1
                        if digitsSeen >= digitsCount {
                            return index + 1
                        }
                    }
                }
                return nsText.length
            }
        }
    }

    private func settingsPickerLabel(text: String, flag: String) -> some View {
        HStack(spacing: 6) {
            Text(text)
                .foregroundStyle(.primary)
                .contentTransition(.opacity)
                .animation(.easeInOut(duration: 0.2), value: text)
            Text(flag)
            Image(systemName: "chevron.down")
                .font(.system(size: captionFontSize * responsiveTypeScale, weight: .semibold))
                .foregroundStyle(Color.brandAccent)
        }
        .font(.system(size: addDayInputFontSize * responsiveTypeScale))
    }

    private func localizedCountText(_ count: Int) -> String {
        let formatter = NumberFormatter()
        let localeIdentifier = settings.language.localeIdentifier
        formatter.locale = Locale(identifier: localeIdentifier)
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
                .font(.system(size: bodyFontSize * responsiveTypeScale, weight: .semibold))
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
            .font(.system(size: bodyFontSize * responsiveTypeScale))
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
                .font(.system(size: footnoteFontSize * responsiveTypeScale, weight: .semibold))
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
                        .fill(stepperButtonBackground)
                )
        }
        .disabled(isDisabled)
        .foregroundStyle(isDisabled ? Color.gray.opacity(0.6) : Color.brandAccent)
    }

    private var switchOffBackground: Color {
        colorScheme == .dark ? Color(.systemGray4) : Color(.systemGray5)
    }

    private var addDayFieldBackground: Color {
        colorScheme == .dark ? switchOffBackground : settingsCardOuterBackground
    }

    private var stepperButtonBackground: Color {
        colorScheme == .dark ? switchOffBackground : Color(.systemGray5)
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
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = TimeZone(secondsFromGMT: 0)
        components.day = day
        components.month = month
        components.year = year
        guard let date = calendar.date(from: components) else { return nil }
        let validated = calendar.dateComponents([.year, .month, .day], from: date)
        guard validated.day == day,
              validated.month == month,
              validated.year == year else {
            return nil
        }
        return DayIdentity.canonicalDate(for: DayIdentity.identifier(year: year, month: month, day: day))
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
            settings.appleIdEverConnected = true
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
        dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)

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
            let normalizedDate = DayIdentity.canonicalDate(for: DayIdentity.canonicalIdentifier(for: date))

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
            let entry = DayEntry(dayIdentifier: DayIdentity.canonicalIdentifier(for: date), itemCount: maxNumber)
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
            entry.normalizeDayIdentity()
            let descriptor = FetchDescriptor<DayEntry>()
            if let existing = (try? modelContext.fetch(descriptor))?.first(where: {
                $0.normalizedDayIdentifier == entry.normalizedDayIdentifier
            }) {
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
