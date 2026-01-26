//NEW DOC  ContentView.swift
import LocalAuthentication
import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme

    @StateObject private var settings = SettingsStore()
    @StateObject private var vm = ContentViewModel()
    @StateObject private var notifier = NotificationManager.shared

    @Query(sort: \DayEntry.day, order: .reverse) private var entries: [DayEntry]

    @State private var showSettings: Bool = false
    @State private var showSecretMenu: Bool = false
    @State private var isUnlocked: Bool = true
    @State private var isUnlocking: Bool = false
    @State private var hasAppeared: Bool = false
    @State private var midnightTask: Task<Void, Never>?
    @State private var showExportOptions: Bool = false
    @State private var shareSheetItem: ShareSheetItem?
    @State private var settingsScrollTask: Task<Void, Never>?
    @State private var infoCardScrollTask: Task<Void, Never>?
    @State private var scrollToTopTrigger = 0
    @State private var scrollToFooterTrigger = 0
    @State private var pendingSettingsOpen = false
    @State private var pendingSettingsClose = false
    @State private var suppressSettingsAutoScroll = false
    @State private var pendingSettingsInfoRequest: SettingsView.SettingsInfo?
    @State private var settingsInfoTask: Task<Void, Never>?
    @State private var pendingInfoCardScroll = false
    @State private var dismissedEmptyLimitNotice = false
    @State private var showsReturnToMainMenuOnly = false
    @State private var highlightLockIcons = false
    @State private var highlightSearchPlaceholder = false
    @State private var highlightSortArrow = false
    @State private var highlightFilterLimit = false
    @State private var highlightScrollToTop = false
    @State private var highlightFooterLinks = false
    @State private var requestedSettingsInfo: SettingsView.SettingsInfo?
    @AppStorage("hasSeenAccessScreen") private var hasSeenAccessScreen: Bool = false
    @AppStorage("hasDismissedInfoCard") private var hasDismissedInfoCard: Bool = false
    @AppStorage("seeYouTomorrowIndexEnglish") private var seeYouTomorrowIndexEnglish: Int = 0
    @AppStorage("seeYouTomorrowIndexDutch") private var seeYouTomorrowIndexDutch: Int = 0
    @State private var seeYouTomorrowMessageKey: String = "cards.see.you.tomorrow.1"
    @State private var lastUnfinishedCount: Int = -1

    @Environment(\.scenePhase) private var scenePhase

    @ScaledMetric(relativeTo: .headline) private var statsValueFontSize: CGFloat = 18
    @ScaledMetric(relativeTo: .title) private var lockIconSize: CGFloat = 48
    @ScaledMetric(relativeTo: .headline) private var settingsGearSize: CGFloat = 18

    private static let numericDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "dd-MM-yyyy"
        return formatter
    }()

    private var mainBackground: Color {
        colorScheme == .dark ? Color.brandSecondarySurface : Color.brandBackground
    }

    private var settingsCardOuterBackground: Color {
        colorScheme == .dark ? Color.brandBackground : Color(.systemGray6)
    }

    private var settingsCardInnerBackground: Color {
        colorScheme == .dark ? Color.brandSurface : Color(.systemBackground)
    }

    private func requiredCount(for entry: DayEntry) -> Int {
        if entry.isLocked { return entry.itemCount }
        if Calendar.current.isDate(entry.day, inSameDayAs: Date()) { return settings.dailyItemCount }
        return min(entry.itemCount, settings.dailyItemCount)
    }

    private func isFinishedEntry(_ entry: DayEntry) -> Bool {
        entry.isLocked || entry.wasCompleted
    }

    private func isEntryEmptyForLimit(_ entry: DayEntry) -> Bool {
        guard !entry.isLocked, !entry.wasCompleted, entry.score == nil else { return false }
        return entry.items.allSatisfy { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private var unfinished: [DayEntry] {
        entries
            .filter { !isFinishedEntry($0) }
            .sorted { $0.day > $1.day }
    }

    private var finished: [DayEntry] {
        let base = entries.filter { isFinishedEntry($0) }
        let limited = vm.limitedFinishedEntries(from: base)
        let sorted = limited.sorted { vm.newestFirst ? ($0.day > $1.day) : ($0.day < $1.day) }
        let normalizedQuery = vm.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else { return sorted }
        return sorted.filter { entry in
            entryMatchesSearch(entry, normalizedQuery: normalizedQuery)
        }
    }

    private var exportEntries: [DayEntry] {
        let sorted = entries.sorted { lhs, rhs in
            vm.newestFirst ? (lhs.day > rhs.day) : (lhs.day < rhs.day)
        }

        switch vm.finishedLimit {
        case .all:
            return sorted
        default:
            return Array(sorted.prefix(vm.finishedLimit.rawValue))
        }
    }

    private func entryMatchesSearch(_ entry: DayEntry, normalizedQuery: String) -> Bool {
        guard !normalizedQuery.isEmpty else { return true }

        let searchSnapshot = vm.searchSnapshot(for: entry) ?? DayEntrySnapshot(from: entry)
        if searchSnapshot.items.joined(separator: " ")
            .range(of: normalizedQuery, options: [.caseInsensitive, .diacriticInsensitive]) != nil {
            return true
        }

        let dayString = DateFormatting.formattedDayString(searchSnapshot.day, language: settings.language)
        if dayString.range(of: normalizedQuery, options: [.caseInsensitive, .diacriticInsensitive]) != nil {
            return true
        }

        let numericDate = ContentView.numericDateFormatter.string(from: searchSnapshot.day)
        if numericDate.range(of: normalizedQuery, options: [.caseInsensitive, .diacriticInsensitive]) != nil {
            return true
        }

        if settings.moonEnabled {
            let phase = MoonPhase.phase(on: searchSnapshot.day)
            let phaseName = phase.localizedName(language: settings.language)
            if phaseName.range(of: normalizedQuery, options: [.caseInsensitive, .diacriticInsensitive]) != nil {
                return true
            }
        }

        if settings.holidaysEnabled {
            let holidayNames = HolidayProvider.holidayNames(on: searchSnapshot.day, language: settings.language)
            if holidayNames.contains(where: { name in
                name.range(of: normalizedQuery, options: [.caseInsensitive, .diacriticInsensitive]) != nil
            }) {
                return true
            }
        }

        if settings.scoreEnabled,
           let score = searchSnapshot.score,
           let queryScore = Int(normalizedQuery.trimmingCharacters(in: .whitespacesAndNewlines)),
           (1...10).contains(queryScore),
           score == queryScore {
            return true
        }

        return false
    }

    private var shouldShowInfoCard: Bool {
        !hasDismissedInfoCard
    }

    private var infoCardEntries: [String] {
        let localizedCount = localizedCountText(settings.dailyItemCount)
        return (1...10)
            .map { index in
                let key = "info.card.entry.\(index)"
                if index == 1 {
                    return L10n.string(key, language: settings.language, localizedCount)
                }
                if index == 4 {
                    return infoCardEntryFour
                }
                return L10n.string(key, language: settings.language)
            }
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private var infoCardEntryFour: String {
        let entryKey: String
        switch (vm.newestFirst, vm.finishedLimit) {
        case (true, .all):
            entryKey = "info.card.entry.4a"
        case (false, .all):
            entryKey = "info.card.entry.4b"
        case (true, _):
            entryKey = "info.card.entry.4c"
        case (false, _):
            entryKey = "info.card.entry.4d"
        }

        switch vm.finishedLimit {
        case .all:
            return L10n.string(entryKey, language: settings.language)
        default:
            let localizedDays = localizedCountText(vm.finishedLimit.rawValue)
            return L10n.string(entryKey,
                               language: settings.language,
                               localizedDays)
        }
    }

    private var dailyTitle: String {
        let count = settings.dailyItemCount
        return L10n.string("title.daily", language: settings.language, count)
    }

    private var lifeTitle: String {
        let word = numberWord(for: settings.dailyItemCount)
        return L10n.string("title.happy", language: settings.language, word)
    }

    private let settingsTopID = "settingsTop"
    private let footerLinksID = "footerLinks"
    private let infoCardID = "infoCard"
    private let infoCardDismissAnimation = Animation.easeInOut(duration: 0.35)
    private let settingsScrollDuration: Double = 0.48
    private let scrollToTopDuration: Double = 0.2
    private let scrollToFooterDuration: Double = 0.6
    private let settingsOpenAnimationDuration: Double = 0.45
    private let highlightPulseDuration: Double = 0.5
    private let seeYouTomorrowMessageCount = 20

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
        URL(string: "https://apps.apple.com/app/id6757990326?action=write-review")!
    }

    private var shareURL: URL {
        URL(string: "https://apps.apple.com/app/id6757990326")!
    }

    private var feedbackURL: URL {
        URL(string: "mailto:jens@hakketjak.nl")!
    }

    private func seeYouTomorrowIndex(for language: AppLanguage) -> Int {
        switch language {
        case .english:
            return seeYouTomorrowIndexEnglish
        case .dutch:
            return seeYouTomorrowIndexDutch
        default:
            return seeYouTomorrowIndexEnglish
        }
    }

    private func setSeeYouTomorrowIndex(_ index: Int, for language: AppLanguage) {
        switch language {
        case .english:
            seeYouTomorrowIndexEnglish = index
        case .dutch:
            seeYouTomorrowIndexDutch = index
        default:
            seeYouTomorrowIndexEnglish = index
        }
    }

    private func showNextSeeYouTomorrowMessage() {
        let language = settings.language
        var index = seeYouTomorrowIndex(for: language)
        if index < 0 || index >= seeYouTomorrowMessageCount {
            index = 0
        }

        let messageNumber = index + 1
        seeYouTomorrowMessageKey = "cards.see.you.tomorrow.\(messageNumber)"

        let nextIndex = (index + 1) % seeYouTomorrowMessageCount
        setSeeYouTomorrowIndex(nextIndex, for: language)
    }

    private var footerLinks: some View {
        VStack(spacing: 16) {
            HStack(spacing: 4) {
                Link(destination: reviewURL) {
                    Text(L10n.string("footer.review", language: settings.language))
                        .padding(.vertical, 10)
                }
                .buttonStyle(.plain)

                Text(" | ")

                Link(destination: shareURL) {
                    Text(L10n.string("footer.share", language: settings.language))
                        .padding(.vertical, 10)
                }
                .buttonStyle(.plain)

                Text(" | ")

                Link(destination: feedbackURL) {
                    Text(L10n.string("footer.feedback", language: settings.language))
                        .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity)
            .multilineTextAlignment(.center)
        }
        .font(.footnote.weight(.semibold))
        .foregroundStyle(highlightFooterLinks ? .orange : .secondary)
        .animation(.easeInOut(duration: 0.25), value: highlightFooterLinks)
        .id(footerLinksID)
    }

    private func emptyLimitNotice(scale: CGFloat) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                dismissedEmptyLimitNotice = true
            }
        } label: {
            Text(L10n.string("cards.empty.limit.notice", language: settings.language))
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 10)
                .padding(.horizontal, 12)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(.secondary.opacity(0.10))
                )
        }
        .buttonStyle(.plain)
        .padding(.top, 4)
        .transition(.opacity.combined(with: .move(edge: .top)))
        .accessibilityLabel(L10n.string("cards.empty.limit.notice", language: settings.language))
    }

    private func filterActiveNotice(scale: CGFloat, limit: ContentViewModel.FinishedCardsLimit) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                vm.finishedLimit = .all
            }
        } label: {
            Text(L10n.string("filters.active.notice", language: settings.language, limit.rawValue))
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 10)
                .padding(.horizontal, 12)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(.secondary.opacity(0.10))
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.string("filters.active.notice", language: settings.language, limit.rawValue))
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
        case 1: return L10n.string("number.one", language: settings.language)
        case 2: return L10n.string("number.two", language: settings.language)
        case 3: return L10n.string("number.three", language: settings.language)
        case 4: return L10n.string("number.four", language: settings.language)
        case 5: return L10n.string("number.five", language: settings.language)
        case 6: return L10n.string("number.six", language: settings.language)
        case 7: return L10n.string("number.seven", language: settings.language)
        case 8: return L10n.string("number.eight", language: settings.language)
        case 9: return L10n.string("number.nine", language: settings.language)
        case 10: return L10n.string("number.ten", language: settings.language)
        default: return "\(count)"
        }
    }

    private func localizedCountText(_ count: Int) -> String {
        let formatter = NumberFormatter()
        let localeIdentifier = settings.language.localeIdentifier
        if let numberingSystem = settings.language.numberingSystemOverride {
            formatter.locale = Locale(identifier: "\(localeIdentifier)@numbers=\(numberingSystem)")
        } else {
            formatter.locale = Locale(identifier: localeIdentifier)
        }
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: count)) ?? "\(count)"
    }

    private var headerView: some View {
        ZStack {
            HStack {
                Button {
                    handleSettingsToggle()
                } label: {
                    Image(systemName: "gearshape.fill")
                        .foregroundStyle(.secondary)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.string("settings.show", language: settings.language))

                Spacer()

                Button {
                    scrollToTopTrigger += 1
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(highlightScrollToTop ? .orange : .secondary)
                        .frame(width: 32, height: 32)
                        .scaleEffect(highlightScrollToTop ? 1.2 : 1)
                        .animation(.easeInOut(duration: 0.25), value: highlightScrollToTop)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.string("scroll.to.top", language: settings.language))
            }

            Button {
                handleSettingsToggle()
            } label: {
                HStack(spacing: 6) {
                    Text(lifeTitle)
                        .font(.title.bold())
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .allowsTightening(true)

                    Image("NoBackground")
                        .resizable()
                        .scaledToFit()
                        .frame(height: 24)
                        .accessibilityHidden(true)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 56)
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.string("settings.show", language: settings.language))
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(mainBackground)
    }

    private func statisticsRow(scale: CGFloat) -> some View {
        let stats = statisticsSnapshot
        let streakLabel = L10n.string("stats.streak", language: settings.language)
        let daysLabel = L10n.string("stats.days", language: settings.language)
        let entriesLabel = L10n.string("stats.entries", language: settings.language)
        return HStack(spacing: 10) {
            statisticsBox(title: streakLabel, value: stats.streak, scale: scale)
            statisticsBox(title: daysLabel, value: stats.days, scale: scale)
            statisticsBox(title: entriesLabel, value: stats.entries, scale: scale)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
    }

    private func statisticsBox(title: String, value: Int, scale: CGFloat) -> some View {
        VStack(spacing: 4) {
            Text(localizedCountText(value))
                .font(.system(size: statsValueFontSize * scale,
                              weight: .bold,
                              design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .monospacedDigit()
            Text(title)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.secondary.opacity(0.10))
        )
    }

    @ViewBuilder
    private func lockOverlay(scale: CGFloat) -> some View {
        if settings.faceIdLockEnabled && !isUnlocked {
            mainBackground
                .ignoresSafeArea()

            VStack(spacing: 16) {
                Image(systemName: "faceid")
                    .font(.system(size: lockIconSize * scale))
                    .foregroundStyle(.secondary)

                Text(L10n.string("lock.faceid.title", language: settings.language))
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.center)

                Button {
                    attemptUnlock()
                } label: {
                    Text(L10n.string("lock.faceid.action", language: settings.language))
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
        GeometryReader { proxy in
            let scale = ResponsiveTypeScale.scale(for: proxy.size.width)
            let unfinishedEntries = unfinished
            let finishedEntries = finished
            let emptyUnfinishedEntries = unfinishedEntries.filter { isEntryEmptyForLimit($0) }
            let thirdEmptyEntryID = emptyUnfinishedEntries.count >= 3 ? emptyUnfinishedEntries[2].id : nil
            let pinnedCardCount = 3
            let pinnedUnfinishedEntries = Array(unfinishedEntries.prefix(pinnedCardCount))
            let remainingUnfinishedEntries = Array(unfinishedEntries.dropFirst(pinnedCardCount))
            let pinnedFinishedEntries = Array(
                finishedEntries.prefix(max(0, pinnedCardCount - pinnedUnfinishedEntries.count))
            )
            let remainingFinishedEntries = Array(finishedEntries.dropFirst(pinnedFinishedEntries.count))
            NavigationStack {
                rootContent(
                    scale: scale,
                    unfinishedEntries: unfinishedEntries,
                    finishedEntries: finishedEntries,
                    thirdEmptyEntryID: thirdEmptyEntryID,
                    pinnedUnfinishedEntries: pinnedUnfinishedEntries,
                    remainingUnfinishedEntries: remainingUnfinishedEntries,
                    pinnedFinishedEntries: pinnedFinishedEntries,
                    remainingFinishedEntries: remainingFinishedEntries
                )
            }
            .environment(\.layoutDirection, settings.language.isRightToLeft ? .rightToLeft : .leftToRight)
            .environment(\.responsiveTypeScale, scale)
        }
    }

    private func rootContent(
        scale: CGFloat,
        unfinishedEntries: [DayEntry],
        finishedEntries: [DayEntry],
        thirdEmptyEntryID: DayEntry.ID?,
        pinnedUnfinishedEntries: [DayEntry],
        remainingUnfinishedEntries: [DayEntry],
        pinnedFinishedEntries: [DayEntry],
        remainingFinishedEntries: [DayEntry]
    ) -> some View {
        let header = AnyView(headerView)
        let overlay = AnyView(lockOverlay(scale: scale))
        return ZStack {
            scrollContent(
                scale: scale,
                unfinishedEntries: unfinishedEntries,
                finishedEntries: finishedEntries,
                thirdEmptyEntryID: thirdEmptyEntryID,
                pinnedUnfinishedEntries: pinnedUnfinishedEntries,
                remainingUnfinishedEntries: remainingUnfinishedEntries,
                pinnedFinishedEntries: pinnedFinishedEntries,
                remainingFinishedEntries: remainingFinishedEntries
            )

            if !hasSeenAccessScreen {
                AccessScreenView(settings: settings,
                                 hasSeenAccessScreen: $hasSeenAccessScreen,
                                 showsReturnToMainMenuOnly: $showsReturnToMainMenuOnly)
                    .transition(.opacity)
            }
        }
        .modifier(RootContentBaseModifier(
            mainBackground: mainBackground,
            hasSeenAccessScreen: hasSeenAccessScreen,
            headerView: header,
            shareSheetItem: $shareSheetItem,
            lockOverlay: overlay
        ))
        .modifier(RootContentTaskModifier(
            settings: settings,
            vm: vm,
            notifier: notifier,
            modelContext: modelContext,
            entries: entries,
            refreshEntryLists: refreshEntryLists,
            scheduleMidnightRefresh: scheduleMidnightRefresh
        ))
        .modifier(RootContentEntriesChangeModifier(
            settings: settings,
            vm: vm,
            notifier: notifier,
            entries: entries,
            refreshEntryLists: refreshEntryLists
        ))
        .modifier(RootContentSettingsChangeModifier(
            settings: settings,
            vm: vm,
            notifier: notifier,
            modelContext: modelContext,
            unfinishedEntries: unfinishedEntries,
            refreshEntryLists: refreshEntryLists,
            showNextSeeYouTomorrowMessage: showNextSeeYouTomorrowMessage
        ))
        .modifier(RootContentUnfinishedChangeModifier(
            lastUnfinishedCount: $lastUnfinishedCount,
            unfinishedEntries: unfinishedEntries,
            showNextSeeYouTomorrowMessage: showNextSeeYouTomorrowMessage
        ))
        .modifier(RootContentLifecycleModifier(
            hasAppeared: $hasAppeared,
            isUnlocked: $isUnlocked,
            lastUnfinishedCount: $lastUnfinishedCount,
            settings: settings,
            unfinishedEntries: unfinishedEntries,
            updateUnlockStateIfNeeded: updateUnlockStateIfNeeded,
            showNextSeeYouTomorrowMessage: showNextSeeYouTomorrowMessage
        ))
        .modifier(RootContentScenePhaseModifier(
            isUnlocked: $isUnlocked,
            midnightTask: $midnightTask,
            settings: settings,
            vm: vm,
            modelContext: modelContext,
            scenePhase: scenePhase,
            refreshEntryLists: refreshEntryLists,
            scheduleMidnightRefresh: scheduleMidnightRefresh,
            updateUnlockStateIfNeeded: updateUnlockStateIfNeeded
        ))
    }

    private func scrollContent(
        scale: CGFloat,
        unfinishedEntries: [DayEntry],
        finishedEntries: [DayEntry],
        thirdEmptyEntryID: DayEntry.ID?,
        pinnedUnfinishedEntries: [DayEntry],
        remainingUnfinishedEntries: [DayEntry],
        pinnedFinishedEntries: [DayEntry],
        remainingFinishedEntries: [DayEntry]
    ) -> some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 14) {
                    Color.clear
                        .frame(height: 1)
                        .id(settingsTopID)

                    if showSettings {
                        settingsSection(scale: scale)
                    }

                    unfinishedSection(
                        scale: scale,
                        unfinishedEntries: unfinishedEntries,
                        thirdEmptyEntryID: thirdEmptyEntryID,
                        pinnedUnfinishedEntries: pinnedUnfinishedEntries,
                        remainingUnfinishedEntries: remainingUnfinishedEntries
                    )

                    Rectangle()
                        .fill(Color.brandAccent)
                        .frame(height: 5)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .padding(.top, 8)

                    if settings.statisticsEnabled {
                        statisticsRow(scale: scale)
                    }

                    SearchAndSortBar(settings: settings,
                                     text: $vm.searchText,
                                     newestFirst: $vm.newestFirst,
                                     finishedLimit: $vm.finishedLimit,
                                     highlightSearchPlaceholder: highlightSearchPlaceholder,
                                     highlightSortArrow: highlightSortArrow,
                                     highlightFilterLimit: highlightFilterLimit)

                    finishedSection(
                        finishedEntries: finishedEntries,
                        pinnedFinishedEntries: pinnedFinishedEntries,
                        remainingFinishedEntries: remainingFinishedEntries
                    )

                    if vm.finishedLimit != .all {
                        filterActiveNotice(scale: scale, limit: vm.finishedLimit)
                            .padding(.top, 6)
                    }

                    VStack(spacing: 10) {
                        Divider().opacity(0.6)
                        footerLinks
                    }
                    .padding(.top, 10)
                }
                .padding(16)
            }
            .onTapGesture {
                if showExportOptions {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        showExportOptions = false
                    }
                }
            }
            .onChange(of: showSettings) { _, expanded in
                if expanded {
                    if suppressSettingsAutoScroll {
                        suppressSettingsAutoScroll = false
                    } else {
                        scrollSettingsIntoView(using: proxy)
                    }
                    if let pendingInfo = pendingSettingsInfoRequest {
                        let delay = scrollToTopDuration + settingsOpenAnimationDuration + 0.05
                        scheduleSettingsInfoPopover(pendingInfo, delay: delay)
                    }
                } else {
                    showSecretMenu = false
                    pendingSettingsInfoRequest = nil
                    settingsInfoTask?.cancel()
                    if showExportOptions {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            showExportOptions = false
                        }
                    }
                    // Apply notification changes after closing settings
                    Task {
                        await notifier.scheduleDailyReminder(time: settings.dailyReminderTime,
                                                            language: settings.language,
                                                            dailyCount: settings.dailyItemCount)
                        let nextReminderDate = vm.nextDayReminderDate(allEntries: entries,
                                                                      reminderTime: settings.nextDayReminderTime)
                        await notifier.scheduleNextDayIfNeeded(time: settings.nextDayReminderTime,
                                                              reminderDate: nextReminderDate,
                                                              language: settings.language)
                    }
                }
            }
            .onChange(of: showSecretMenu) { _, _ in
                if showSettings {
                    scrollSettingsIntoView(using: proxy)
                }
            }
            .onChange(of: showExportOptions) { _, _ in
                if showSettings {
                    scrollSettingsIntoView(using: proxy)
                }
            }
            .onChange(of: pendingSettingsOpen) { _, shouldOpen in
                if shouldOpen {
                    openSettingsAfterScroll(using: proxy)
                }
            }
            .onChange(of: pendingSettingsClose) { _, shouldClose in
                if shouldClose {
                    closeSettingsAfterScroll(using: proxy)
                }
            }
            .onChange(of: scrollToTopTrigger) { _, _ in
                scrollToTop(using: proxy)
            }
            .onChange(of: scrollToFooterTrigger) { _, _ in
                scrollToFooter(using: proxy)
            }
        }
    }

    private func settingsSection(scale: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(L10n.string("settings.title", language: settings.language))
                    .font(.title3.weight(.semibold))
                    .onTapGesture(count: 5) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showSecretMenu = true
                        }
                    }
                Spacer()
                HStack(spacing: 12 * 1.2) {
                    Button {
                        hasDismissedInfoCard = false
                        if vm.newestFirst {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                vm.newestFirst = false
                            }
                        } else {
                            vm.newestFirst = false
                        }
                        pendingInfoCardScroll = true
                        pendingSettingsClose = true
                    } label: {
                        Image(systemName: "info")
                            .font(.system(size: settingsGearSize * scale,
                                          weight: .semibold))
                            .foregroundStyle(Color(.systemGray))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L10n.string("info.card.button", language: settings.language))

                    Button {
                        showsReturnToMainMenuOnly = true
                        hasSeenAccessScreen = false
                        pendingSettingsClose = true
                    } label: {
                        Image("Settings_clover")
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .frame(width: settingsGearSize * scale * 1.2,
                                   height: settingsGearSize * scale * 1.2)
                            .foregroundStyle(Color(.systemGray))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L10n.string("access.back.main.menu", language: settings.language))

                    Button {
                        pendingSettingsClose = true
                    } label: {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: settingsGearSize * scale,
                                          weight: .semibold))
                            .foregroundStyle(Color(.systemGray))
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(height: 44)
            .padding(.horizontal, 28)
            .padding(.top, 4)

            VStack(spacing: 16) {
                SettingsView(settings: settings,
                             showSecretMenu: $showSecretMenu,
                             requestedInfo: $requestedSettingsInfo,
                             showsNavigation: false)

                Button {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        showExportOptions.toggle()
                    }
                } label: {
                    Text(L10n.string("export.title", language: settings.language))
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

                if showExportOptions {
                    HStack(spacing: 12) {
                        Button {
                            handleExport(format: .pdf)
                        } label: {
                            Text(L10n.string("export.pdf", language: settings.language))
                                .font(.headline)
                                .foregroundStyle(.primary)
                                .frame(width: 80, height: 36)
                                .background(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(Color.brandAccent.opacity(0.2))
                                )
                        }
                        .buttonStyle(.plain)

                        Button {
                            handleExport(format: .csv)
                        } label: {
                            Text(L10n.string("export.csv", language: settings.language))
                                .font(.headline)
                                .foregroundStyle(.primary)
                                .frame(width: 80, height: 36)
                                .background(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(Color.brandAccent.opacity(0.2))
                                )
                        }
                        .buttonStyle(.plain)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 14)
            .padding(.top, 8)
            .padding(.bottom, 14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(settingsCardInnerBackground)
            )
            .padding(.horizontal, 14)
            .padding(.bottom, 14)
        }
        .padding(.top, 8)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(settingsCardOuterBackground)
                .shadow(radius: 6, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.gray.opacity(0.3), lineWidth: 2)
        )
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    private func unfinishedSection(
        scale: CGFloat,
        unfinishedEntries: [DayEntry],
        thirdEmptyEntryID: DayEntry.ID?,
        pinnedUnfinishedEntries: [DayEntry],
        remainingUnfinishedEntries: [DayEntry]
    ) -> some View {
        Group {
            if !unfinishedEntries.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(pinnedUnfinishedEntries) { entry in
                        DayCardView(settings: settings,
                                    vm: vm,
                                    searchHighlightsEnabled: false,
                                    highlightLockIcon: highlightLockIcons,
                                    entry: entry)
                            .transition(.identity)

                        if !dismissedEmptyLimitNotice,
                           let thirdEmptyEntryID,
                           entry.id == thirdEmptyEntryID {
                            emptyLimitNotice(scale: scale)
                        }
                    }

                    if !remainingUnfinishedEntries.isEmpty {
                        LazyVStack(alignment: .leading, spacing: 10) {
                            ForEach(remainingUnfinishedEntries) { entry in
                                DayCardView(settings: settings,
                                            vm: vm,
                                            searchHighlightsEnabled: false,
                                            highlightLockIcon: highlightLockIcons,
                                            entry: entry)
                                    .transition(.identity)

                                if !dismissedEmptyLimitNotice,
                                   let thirdEmptyEntryID,
                                   entry.id == thirdEmptyEntryID {
                                    emptyLimitNotice(scale: scale)
                                }
                            }
                        }
                    }
                }
                .animation(.easeInOut(duration: 0.25),
                           value: unfinishedEntries.map(\.id))
                .animation(.easeInOut(duration: settingsOpenAnimationDuration),
                           value: showSettings)
            } else {
                Text(L10n.string(seeYouTomorrowMessageKey, language: settings.language))
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color.brandAccent)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .multilineTextAlignment(.center)
                    .padding(.vertical, 8)
            }
        }
    }

    private func finishedSection(
        finishedEntries: [DayEntry],
        pinnedFinishedEntries: [DayEntry],
        remainingFinishedEntries: [DayEntry]
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if shouldShowInfoCard, !vm.newestFirst {
                InfoCardView(title: L10n.string("info.card.title", language: settings.language),
                             items: infoCardEntries,
                             infoAction: {
                                 withAnimation(infoCardDismissAnimation) {
                                     hasDismissedInfoCard = true
                                 }
                             },
                             infoAccessibilityLabel: L10n.string("info.card.button", language: settings.language),
                             linkAction: handleInfoCardLink,
                             numberText: { "\(localizedCountText($0))." },
                             linkHighlightDuration: highlightPulseDuration,
                             linkHighlightCycles: 3)
                    .id(infoCardID)
                    .transition(.opacity)
            }

            ForEach(pinnedFinishedEntries) { entry in
                DayCardView(settings: settings,
                            vm: vm,
                            searchHighlightsEnabled: true,
                            highlightLockIcon: highlightLockIcons,
                            entry: entry)
                    .transition(.opacity)
            }

            if !remainingFinishedEntries.isEmpty {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(remainingFinishedEntries) { entry in
                        DayCardView(settings: settings,
                                    vm: vm,
                                    searchHighlightsEnabled: true,
                                    highlightLockIcon: highlightLockIcons,
                                    entry: entry)
                            .transition(.opacity)
                    }
                }
            }

            if shouldShowInfoCard, vm.newestFirst {
                InfoCardView(title: L10n.string("info.card.title", language: settings.language),
                             items: infoCardEntries,
                             infoAction: {
                                 withAnimation(infoCardDismissAnimation) {
                                     hasDismissedInfoCard = true
                                 }
                             },
                             infoAccessibilityLabel: L10n.string("info.card.button", language: settings.language),
                             linkAction: handleInfoCardLink,
                             numberText: { "\(localizedCountText($0))." },
                             linkHighlightDuration: highlightPulseDuration,
                             linkHighlightCycles: 3)
                    .id(infoCardID)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25),
                   value: finishedEntries.map(\.id))
        .animation(.easeInOut(duration: 0.25), value: vm.searchText)
        .animation(.easeInOut(duration: 0.25), value: vm.newestFirst)
        .animation(.easeInOut(duration: 0.25), value: vm.finishedLimit)
        .animation(infoCardDismissAnimation, value: shouldShowInfoCard)
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
                let nextReminderDate = await MainActor.run {
                    vm.nextDayReminderDate(allEntries: entries, reminderTime: settings.nextDayReminderTime)
                }
                await notifier.scheduleNextDayIfNeeded(time: settings.nextDayReminderTime,
                                                      reminderDate: nextReminderDate,
                                                      language: settings.language)
            }
        }
    }

    private func handleExport(format: ExportFormat) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            showExportOptions = false
        }

        do {
            let url = try ExportService.export(entries: exportEntries,
                                                language: settings.language,
                                                format: format,
                                                filterContext: ExportService.ExportFilterContext(
                                                    finishedLimit: vm.finishedLimit,
                                                    newestFirst: vm.newestFirst
                                                ))
            shareSheetItem = ShareSheetItem(items: [url])
        } catch {
            return
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

    private func handleSettingsToggle() {
        if showSettings {
            pendingSettingsClose = true
        } else {
            pendingSettingsOpen = true
        }
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
        let reason = L10n.string("lock.faceid.reason", language: settings.language)

        context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) { success, _ in
            Task { @MainActor in
                isUnlocked = success
                isUnlocking = false
            }
        }
    }

    private func refreshEntryLists() {
        let emptyCount = unfinished.filter { isEntryEmptyForLimit($0) }.count
        if emptyCount < 3, dismissedEmptyLimitNotice {
            dismissedEmptyLimitNotice = false
        }
    }

    private func scrollSettingsIntoView(using proxy: ScrollViewProxy) {
        settingsScrollTask?.cancel()
        settingsScrollTask = Task { @MainActor in
            let animation = Animation.easeInOut(duration: settingsScrollDuration)
            await Task.yield()
            withAnimation(animation) {
                proxy.scrollTo(settingsTopID, anchor: .top)
            }
        }
    }

    private func scrollToTop(using proxy: ScrollViewProxy) {
        settingsScrollTask?.cancel()
        settingsScrollTask = Task { @MainActor in
            let animation = Animation.easeOut(duration: scrollToTopDuration)
            await Task.yield()
            withAnimation(animation) {
                proxy.scrollTo(settingsTopID, anchor: .top)
            }
        }
    }

    private func scrollToFooter(using proxy: ScrollViewProxy) {
        settingsScrollTask?.cancel()
        settingsScrollTask = Task { @MainActor in
            let animation = Animation.easeInOut(duration: scrollToFooterDuration)
            await Task.yield()
            withAnimation(animation) {
                proxy.scrollTo(footerLinksID, anchor: .bottom)
            }
        }
    }

    private func scheduleInfoCardScroll(using proxy: ScrollViewProxy, delay: Double) {
        infoCardScrollTask?.cancel()
        infoCardScrollTask = Task { @MainActor in
            let sleepTime = UInt64(delay * 1_000_000_000)
            try? await Task.sleep(nanoseconds: sleepTime)
            await Task.yield()
            let animation = Animation.easeInOut(duration: scrollToFooterDuration)
            withAnimation(animation) {
                proxy.scrollTo(infoCardID, anchor: .top)
            }
        }
    }

    private func openSettingsAfterScroll(using proxy: ScrollViewProxy) {
        settingsScrollTask?.cancel()
        settingsScrollTask = Task { @MainActor in
            let animation = Animation.easeInOut(duration: scrollToTopDuration)
            await Task.yield()
            withAnimation(animation) {
                proxy.scrollTo(settingsTopID, anchor: .top)
            }
            suppressSettingsAutoScroll = true
            pendingSettingsOpen = false
            withAnimation(.easeInOut(duration: settingsOpenAnimationDuration)) {
                showSettings = true
            }
        }
    }

    private func closeSettingsAfterScroll(using proxy: ScrollViewProxy) {
        settingsScrollTask?.cancel()
        settingsScrollTask = Task { @MainActor in
            let animation = Animation.easeOut(duration: scrollToTopDuration)
            await Task.yield()
            withAnimation(animation) {
                proxy.scrollTo(settingsTopID, anchor: .top)
            }
            let shouldScrollToInfoCard = pendingInfoCardScroll
            pendingInfoCardScroll = false
            withAnimation(.easeInOut(duration: settingsOpenAnimationDuration)) {
                showSettings = false
            }
            if shouldScrollToInfoCard {
                scheduleInfoCardScroll(using: proxy,
                                       delay: settingsOpenAnimationDuration + 0.05)
            }
            pendingSettingsClose = false
        }
    }

    private func handleInfoCardLink(_ action: String) {
        switch action {
        case "lock":
            pulseHighlight($highlightLockIcons)
        case "settings":
            pendingSettingsInfoRequest = .entriesPerDay
            if showSettings {
                scheduleSettingsInfoPopover(.entriesPerDay, delay: 0.05)
            } else {
                pendingSettingsOpen = true
            }
        case "search":
            pulseHighlight($highlightSearchPlaceholder)
        case "sort":
            pulseHighlight($highlightSortArrow)
        case "filter":
            pulseHighlight($highlightFilterLimit)
        case "top":
            pulseHighlight($highlightScrollToTop)
        case "footer":
            scrollToFooterTrigger += 1
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64((scrollToFooterDuration + 0.1) * 1_000_000_000))
                pulseHighlight($highlightFooterLinks)
            }
        case "highlight":
            break
        default:
            break
        }
    }

    private func scheduleSettingsInfoPopover(_ info: SettingsView.SettingsInfo, delay: Double) {
        settingsInfoTask?.cancel()
        settingsInfoTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            requestedSettingsInfo = info
            pendingSettingsInfoRequest = nil
        }
    }

    private func pulseHighlight(_ binding: Binding<Bool>, cycles: Int = 3) {
        Task { @MainActor in
            for _ in 0..<cycles {
                withAnimation(.easeInOut(duration: highlightPulseDuration)) {
                    binding.wrappedValue = true
                }
                try? await Task.sleep(nanoseconds: UInt64(highlightPulseDuration * 1_000_000_000))
                withAnimation(.easeInOut(duration: highlightPulseDuration)) {
                    binding.wrappedValue = false
                }
                try? await Task.sleep(nanoseconds: UInt64(highlightPulseDuration * 1_000_000_000))
            }
        }
    }
}
