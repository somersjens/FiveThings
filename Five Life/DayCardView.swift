//NEW DOC  DayCardView.swift
import SwiftUI
import SwiftData
import UIKit

struct DayCardView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.responsiveTypeScale) private var responsiveTypeScale
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var settings: SettingsStore
    @ObservedObject var vm: ContentViewModel
    let searchHighlightsEnabled: Bool

    @Bindable var entry: DayEntry

    @State private var showSuccess: Bool = false
    @State private var showIncompleteHint: Bool = false
    @State private var dragIndex: Int?
    @State private var dropTarget: DropTarget?
    @State private var rowHeights: [Int: CGFloat] = [:]
    @State private var rowFrames: [Int: CGRect] = [:]
    @State private var dragOffset: CGSize = .zero
    @State private var isDragging: Bool = false
    @State private var suppressFocus: Bool = false
    @State private var showScoreEditor: Bool = false
    @State private var scoreDraft: Double = 6
    @State private var undoHistory: [UndoSnapshot] = []
    @State private var activeEditIndex: Int? = nil
    @State private var hasCapturedEditSnapshot: Bool = false

    @ScaledMetric(relativeTo: .body) private var rowSpacing: CGFloat = 10
    @ScaledMetric(relativeTo: .body) private var headerIconSize: CGFloat = 31
    @ScaledMetric(relativeTo: .footnote) private var headerIconFontSize: CGFloat = 14
    @ScaledMetric(relativeTo: .body) private var rowTrailingControlPadding: CGFloat = 28
    @ScaledMetric(relativeTo: .subheadline) private var dateFontSize: CGFloat = 16
    @ScaledMetric(relativeTo: .title) private var scoreValueFontSize: CGFloat = 32
    @ScaledMetric(relativeTo: .headline) private var removeButtonFontSize: CGFloat = 18

    private var scaledRowSpacing: CGFloat { rowSpacing * responsiveTypeScale }
    private var scaledHeaderIconSize: CGFloat { headerIconSize * responsiveTypeScale }
    private var scaledHeaderIconFontSize: CGFloat { headerIconFontSize * responsiveTypeScale }
    private var scaledRowTrailingControlPadding: CGFloat { rowTrailingControlPadding * responsiveTypeScale }

    private var entryRowMinHeight: CGFloat {
        UIFontMetrics(forTextStyle: .body).scaledValue(for: 34 * responsiveTypeScale)
    }

    @FocusState private var focusedIndex: Int?

    private var isEditable: Bool { !entry.isLocked }
    private var canDragEntries: Bool {
        isEditable && entry.isComplete(requiredCount: requiredCount)
    }

    private var isToday: Bool {
        Calendar.current.isDate(entry.day, inSameDayAs: Date())
    }

    private var dateString: String {
        DateFormatting.formattedDayString(entry.day, language: settings.language)
    }

    private var normalizedSearchQuery: String {
        guard searchHighlightsEnabled else { return "" }
        return vm.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var moonPhase: MoonPhaseKind? {
        settings.moonEnabled ? MoonPhase.phase(on: entry.day) : nil
    }

    private var moonDescription: String? {
        guard settings.moonEnabled else { return nil }
        return MoonPhase.description(on: entry.day, language: settings.language, locale: settings.locale)
    }

    private var holidayNames: [String] {
        guard settings.holidaysEnabled else { return [] }
        return HolidayProvider.holidayNames(on: entry.day, language: settings.language)
    }

    private var requiredCount: Int {
        if entry.isLocked { return entry.itemCount }
        if isToday { return settings.dailyItemCount }
        return min(entry.itemCount, settings.dailyItemCount)
    }

    private var displayCount: Int {
        if entry.isLocked {
            return max(entry.itemCount, entry.items.count)
        }

        var count = max(requiredCount, entry.items.count)
        if isToday {
            count = max(count, settings.dailyItemCount)
        } else if settings.dailyItemCount > entry.itemCount {
            count = max(count, settings.dailyItemCount)
        }
        return count
    }

    private var hasOptionalRows: Bool {
        displayCount > requiredCount
    }

    private var canRemoveOptionalRows: Bool {
        entry.itemCount > settings.dailyItemCount
    }

    private var shouldPulse: Bool {
        !entry.isLocked && entry.isComplete(requiredCount: requiredCount) && !showSuccess
    }

    private var outlineColor: Color {
        if showSuccess { return Color.brandAccent }
        if shouldPulse { return .yellow }
        if entry.isLocked { return Color.brandAccent }
        return .orange
    }

    private var cardBackgroundColor: Color {
        colorScheme == .dark ? Color.brandBackground : Color(.systemBackground)
    }

    private var rowBackgroundColor: Color {
        colorScheme == .dark ? Color.brandSurface : Color(.systemGray6)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            VStack(spacing: scaledRowSpacing) {
                ForEach(0..<displayCount, id: \.self) { idx in
                    entryRow(idx)
                }
            }
            .coordinateSpace(name: "entryList")
            .overlay {
                dragOverlay
            }

            if showIncompleteHint {
                Text(L10n.string("daycard.complete.to.lock", language: settings.language))
                    .font(.footnote)
                    .foregroundStyle(.primary)
                    .transition(.opacity)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(cardBackgroundColor)
                .shadow(radius: 6, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(outlineColor, lineWidth: 3)
        )
        .animation(nil, value: entry.isLocked)
        .animation(nil, value: displayCount)
        .animation(.easeInOut(duration: 0.2), value: outlineColor)
        .onAppear {
            syncEntryCounts()
        }
        .onChange(of: settings.dailyItemCount) { _, _ in
            syncEntryCounts()
        }
        .onChange(of: entry.isLocked) { _, locked in
            if !locked {
                showSuccess = false
            } else {
                focusedIndex = nil
                clearUndoHistory()
            }
        }
        .onChange(of: focusedIndex) { _, newValue in
            if let newValue {
                trackEditSession(for: newValue)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 6) {
                highlightedText(dateString,
                                baseFont: .system(size: dateFontSize * responsiveTypeScale, weight: .semibold))

                if holidayNames.isEmpty {
                    if let phase = moonPhase {
                        moonLine(phase)
                    } else {
                        Text(" ")
                            .font(.subheadline)
                            .foregroundStyle(.white)
                    }
                } else {
                    ForEach(holidayNames.prefix(2), id: \.self) { holiday in
                        highlightedText(holiday, baseFont: .subheadline)
                            .foregroundStyle(.primary)
                    }
                    if let phase = moonPhase {
                        moonLine(phase)
                    }
                }
            }

            Spacer()

            if settings.scoreEnabled {
                Button {
                    guard !entry.isLocked else { return }
                    scoreDraft = Double(entry.score ?? 6)
                    showScoreEditor = true
                } label: {
                    scoreBadge
                        .frame(width: scaledHeaderIconSize, height: scaledHeaderIconSize)
                        .background(.thinMaterial)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(entry.isLocked)
                .accessibilityLabel(entry.score == nil
                                    ? L10n.string("daycard.score.title", language: settings.language)
                                    : L10n.string("daycard.score.adjust", language: settings.language))
            }

            if !entry.isLocked {
                Button {
                    if undoHistory.isEmpty {
                        if isCardCompletelyEmpty {
                            focusedIndex = nil
                        }
                        return
                    }
                    undoLastChange()
                } label: {
                    Image(systemName: "arrow.uturn.left")
                        .font(.system(size: scaledHeaderIconFontSize, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: scaledHeaderIconSize, height: scaledHeaderIconSize)
                        .background(.thinMaterial)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .opacity(undoHistory.isEmpty ? 0.4 : 1)
                .accessibilityLabel(L10n.string("daycard.undo", language: settings.language))
            }

            Button {
                if entry.isLocked {
                    vm.unlock(entry, settings: settings, modelContext: modelContext)
                    showSuccess = false
                } else {
                    // If unlocked: allow lock only if complete, otherwise show hint
                    if entry.isComplete(requiredCount: requiredCount) {
                        triggerLockFlow()
                    } else {
                        withAnimation(.easeInOut(duration: 0.2)) { showIncompleteHint = true }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                            withAnimation(.easeInOut(duration: 0.2)) { showIncompleteHint = false }
                        }
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }
                }
            } label: {
                Image(systemName: entry.isLocked ? "lock.fill" : (shouldPulse ? "lock.open.fill" : "lock.open"))
                    .font(.system(size: scaledHeaderIconFontSize, weight: .semibold))
                    .frame(width: scaledHeaderIconSize, height: scaledHeaderIconSize)
                    .background(.thinMaterial)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(entry.isLocked
                                ? L10n.string("daycard.unlock", language: settings.language)
                                : L10n.string("daycard.lock", language: settings.language))
        }
        .sheet(isPresented: $showScoreEditor) {
            scoreEditorSheet
        }
    }

    @ViewBuilder
    private var scoreBadge: some View {
        if let score = entry.score {
            highlightedText("\(score)", baseFont: .system(size: scaledHeaderIconFontSize, weight: .semibold))
                .foregroundStyle(.primary)
        } else {
            Image(systemName: "star.fill")
                .font(.system(size: scaledHeaderIconFontSize, weight: .semibold))
                .foregroundStyle(Color.brandAccent)
        }
    }

    private func moonLine(_ phase: MoonPhaseKind) -> some View {
        return HStack(spacing: 6) {
            Image(systemName: phase.sfSymbolName)
            highlightedText(moonDescription ?? phase.localizedName(language: settings.language),
                            baseFont: .subheadline)
        }
        .font(.subheadline)
        .foregroundStyle(.primary)
    }

    private var scoreEditorSheet: some View {
        VStack(spacing: 16) {
            Text(L10n.string("daycard.score.title", language: settings.language))
                .font(.headline)

            Text("\(Int(scoreDraft.rounded()))")
                .font(.system(size: scoreValueFontSize * responsiveTypeScale, weight: .bold))
                .monospacedDigit()

            GeometryReader { proxy in
                HStack {
                    Spacer()
                    Slider(value: $scoreDraft, in: 1...10)
                        .tint(Color.brandAccent)
                        .frame(width: proxy.size.width * 0.8)
                    Spacer()
                }
            }
            .frame(height: 44)

            HStack(spacing: 12) {
                Button {
                    updateScore(nil)
                    showScoreEditor = false
                } label: {
                    Text(L10n.string("common.clear", language: settings.language))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(.systemGray))
                .foregroundStyle(.white)

                Button {
                    updateScore(Int(scoreDraft.rounded()))
                    showScoreEditor = false
                } label: {
                    Text(L10n.string("common.save", language: settings.language))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.brandAccent)
            }
        }
        .padding()
        .presentationDetents([.height(260)])
    }

    private func entryRow(_ idx: Int) -> some View {
        let showsRemove = isEditable && canRemoveOptionalRows && idx >= requiredCount
        let styledRow = rowContainer(idx: idx,
                                     showsRemove: showsRemove,
                                     applyInsertionPadding: true,
                                     trackSize: true)
        let interactiveRow = styledRow
            .opacity(isDragging && dragIndex == idx ? 0 : 1)
            .allowsHitTesting(!(isDragging && dragIndex == idx))
            .zIndex(dragIndex == idx ? 1 : 0)
            .simultaneousGesture(canDragEntries ? longPressGesture(for: idx) : nil)
            .simultaneousGesture(canDragEntries ? activeDragGesture(for: idx) : nil)
        return AnyView(interactiveRow)
    }

    private func rowContainer(idx: Int,
                              showsRemove: Bool,
                              applyInsertionPadding: Bool,
                              trackSize: Bool) -> some View {
        let baseRow = rowContent(idx: idx)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .frame(minHeight: entryRowMinHeight, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(rowBackgroundColor)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

        return baseRow
            .background(
                Group {
                    if trackSize {
                        GeometryReader { proxy in
                            Color.clear
                                .onAppear {
                                    rowHeights[idx] = proxy.size.height
                                    rowFrames[idx] = proxy.frame(in: .named("entryList"))
                                }
                                .onChange(of: proxy.size.height) { _, newValue in
                                    rowHeights[idx] = newValue
                                }
                                .onChange(of: proxy.frame(in: .named("entryList"))) { _, newValue in
                                    rowFrames[idx] = newValue
                                }
                        }
                    }
                }
            )
            .padding(applyInsertionPadding ? dragInsertionPadding(for: idx) : EdgeInsets())
            .animation(.spring(response: 0.3, dampingFraction: 0.85), value: dropTarget)
            .overlay(alignment: .trailing) {
                if showsRemove {
                    Button {
                        pushUndoSnapshot(force: true)
                        vm.removeItem(entry, index: idx, modelContext: modelContext)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: removeButtonFontSize * responsiveTypeScale, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 26, height: 26)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L10n.string("daycard.remove.optional", language: settings.language))
                    .padding(.trailing, 6)
                }
            }
    }

    private func rowContent(idx: Int) -> some View {
        let showsOptionalPlaceholder = hasOptionalRows && !entry.isLocked && idx >= requiredCount
        let placeholderText = showsOptionalPlaceholder
            ? L10n.string("daycard.placeholder.optional", language: settings.language)
            : L10n.string("daycard.placeholder.entry", language: settings.language)
        return HStack(alignment: .top, spacing: 6) {
            Text("\(idx + 1).")
                .font(.system(.body, design: .rounded).weight(.semibold))
                .frame(width: 22, alignment: .leading)
                .foregroundStyle(.primary)

            rowTextView(placeholderText: placeholderText, idx: idx)
        }
    }

    private func rowTextField(placeholderText: String, idx: Int) -> some View {
        TextField(
            placeholderText,
            text: Binding(
                get: { entry.items[safe: idx] ?? "" },
                set: { newValue in
                    guard !entry.isLocked else { return }
                    if idx < entry.items.count {
                        let hasNewline = newValue.contains("\n")
                        let sanitized = newValue.replacingOccurrences(of: "\n", with: "")
                        if entry.items[idx] != sanitized {
                            trackEditSession(for: idx)
                            pushUndoSnapshot()
                            hasCapturedEditSnapshot = true
                        }
                        vm.updateItem(entry, index: idx, text: sanitized, modelContext: modelContext)
                        if hasNewline {
                            handleSubmit(at: idx)
                        }
                    }
                }
            ),
            axis: .vertical
        )
        .textFieldStyle(.plain)
        .font(.body)
        .lineLimit(1...4)
        .lineSpacing(0)
        .fixedSize(horizontal: false, vertical: true)
        .foregroundStyle(.primary)
        .multilineTextAlignment(.leading)
        .focused($focusedIndex, equals: idx)
        .disabled(entry.isLocked || isDragging || suppressFocus)
        .allowsHitTesting(!(entry.isLocked || isDragging || suppressFocus))
        .submitLabel(nextEmptyEntryIndex(after: idx) == nil ? .done : .next)
        .onSubmit {
            guard !entry.isLocked else { return }
            handleSubmit(at: idx)
        }
    }

    @ViewBuilder
    private func rowTextView(placeholderText: String, idx: Int) -> some View {
        if entry.isLocked {
            let text = entry.items[safe: idx] ?? ""
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(placeholderText)
                    .font(.body)
                    .lineSpacing(0)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                highlightedText(text, baseFont: .body)
                    .lineLimit(4)
                    .lineSpacing(0)
                    .fixedSize(horizontal: false, vertical: true)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .multilineTextAlignment(.leading)
            }
        } else {
            rowTextField(placeholderText: placeholderText, idx: idx)
        }
    }

    private func highlightedText(_ text: String, baseFont: Font) -> Text {
        guard !normalizedSearchQuery.isEmpty else {
            return Text(text).font(baseFont)
        }
        var attributed = AttributedString(text)
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        var searchRange = text.startIndex..<text.endIndex
        while let range = text.range(of: normalizedSearchQuery, options: options, range: searchRange) {
            if let attributedRange = Range(range, in: attributed) {
                attributed[attributedRange].foregroundColor = Color.brandAccent
                attributed[attributedRange].font = baseFont.weight(.bold)
            }
            searchRange = range.upperBound..<text.endIndex
        }
        return Text(attributed).font(baseFont)
    }

    private var dragOverlay: some View {
        GeometryReader { _ in
            if let dragIndex, let frame = rowFrames[dragIndex], isDragging {
                rowContainer(idx: dragIndex,
                             showsRemove: isEditable && canRemoveOptionalRows && dragIndex >= requiredCount,
                             applyInsertionPadding: false,
                             trackSize: false)
                    .frame(width: frame.width, height: frame.height, alignment: .leading)
                    .position(x: frame.midX + dragOffset.width, y: frame.midY + dragOffset.height)
                    .zIndex(2)
                    .allowsHitTesting(false)
            }
        }
    }

    private func longPressGesture(for idx: Int) -> some Gesture {
        LongPressGesture(minimumDuration: 0.6)
            .onEnded { _ in
                beginDrag(at: idx)
            }
    }

    private func activeDragGesture(for idx: Int) -> some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { dragValue in
                guard dragIndex == idx, isDragging else { return }
                dragOffset = dragValue.translation
                let currentY = (rowFrames[idx]?.midY ?? 0) + dragValue.translation.height
                updateDropTarget(currentY: currentY, source: idx)
            }
            .onEnded { _ in
                if dragIndex == idx, isDragging {
                    completeDrag()
                } else {
                    resetDragState()
                }
            }
    }

    private func updateDropTarget(currentY: CGFloat, source: Int) {
        let indices = (0..<displayCount)
            .filter { $0 != source }
            .filter { rowFrames[$0] != nil }

        guard !indices.isEmpty else {
            dropTarget = nil
            return
        }

        for idx in indices {
            if let frame = rowFrames[idx], currentY < frame.midY {
                dropTarget = DropTarget(index: idx, position: .above)
                return
            }
        }

        if let last = indices.last {
            dropTarget = DropTarget(index: last, position: .below)
        }
    }

    private func completeDrag() {
        defer {
            resetDragState()
        }

        suppressFocus = true
        guard let source = dragIndex, let dropTarget else { return }
        let offset = dropTarget.position == .below ? 1 : 0
        let count = entry.items.count
        var target = dropTarget.index + offset
        if source < target {
            target -= 1
        }
        target = max(0, min(count - 1, target))
        guard source != target else { return }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            pushUndoSnapshot(force: true)
            vm.moveItem(entry, from: source, to: target, modelContext: modelContext)
        }
    }

    private func beginDrag(at index: Int) {
        guard dragIndex == nil, canDragEntries else { return }
        dragIndex = index
        isDragging = true
        suppressFocus = true
        focusedIndex = nil
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func resetDragState() {
        dragIndex = nil
        dropTarget = nil
        dragOffset = .zero
        isDragging = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            suppressFocus = false
        }
    }

    private func dragInsertionPadding(for idx: Int) -> EdgeInsets {
        guard let dragIndex, let dropTarget, dragIndex != idx else { return EdgeInsets() }
        guard dropTarget.index == idx else { return EdgeInsets() }

        let dragHeight = rowHeights[dragIndex] ?? rowHeights[idx] ?? 44
        let gap = dragHeight + scaledRowSpacing

        switch dropTarget.position {
        case .above:
            return EdgeInsets(top: gap, leading: 0, bottom: 0, trailing: 0)
        case .below:
            return EdgeInsets(top: 0, leading: 0, bottom: gap, trailing: 0)
        }
    }

    private func handleSubmit(at index: Int) {
        guard isEditable else { return }

        if let nextIndex = nextEmptyEntryIndex(after: index) {
            focusedIndex = nextIndex
            return
        }

        focusedIndex = nil
        if !entry.isComplete(requiredCount: requiredCount) {
            withAnimation(.easeInOut(duration: 0.2)) { showIncompleteHint = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                withAnimation(.easeInOut(duration: 0.2)) { showIncompleteHint = false }
            }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }

    private func trackEditSession(for index: Int) {
        guard activeEditIndex != index else { return }
        activeEditIndex = index
        hasCapturedEditSnapshot = false
    }

    private func pushUndoSnapshot(force: Bool = false) {
        if !force, hasCapturedEditSnapshot {
            return
        }
        let snapshot = UndoSnapshot(items: entry.items, focusedIndex: activeEditIndex ?? focusedIndex)
        if undoHistory.last != snapshot {
            undoHistory.append(snapshot)
        }
    }

    private func undoLastChange() {
        guard let snapshot = undoHistory.popLast() else { return }
        entry.items = snapshot.items
        entry.updatedAt = Date()
        try? modelContext.save()
        focusedIndex = snapshot.focusedIndex
        activeEditIndex = snapshot.focusedIndex
        hasCapturedEditSnapshot = false
    }

    private func clearUndoHistory() {
        undoHistory.removeAll()
        activeEditIndex = nil
        hasCapturedEditSnapshot = false
    }

    private func nextEmptyEntryIndex(after index: Int) -> Int? {
        let trimmedItems = (0..<displayCount).map { entry.items[safe: $0] ?? "" }
        let orderedIndices = Array((index + 1)..<displayCount) + Array(0..<index)
        for idx in orderedIndices {
            if trimmedItems[idx].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return idx
            }
        }
        return nil
    }

    private var isCardCompletelyEmpty: Bool {
        (0..<displayCount)
            .allSatisfy { (entry.items[safe: $0] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private func triggerLockFlow() {
        vm.lock(entry, requiredCount: requiredCount, modelContext: modelContext)
        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
            showSuccess = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            withAnimation(.easeInOut(duration: 0.2)) {
                showSuccess = false
            }
        }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    private func updateScore(_ score: Int?) {
        guard !entry.isLocked else { return }
        if let score {
            entry.score = max(1, min(10, score))
        } else {
            entry.score = nil
        }
        entry.updatedAt = Date()
        try? modelContext.save()
    }

    private func syncEntryCounts() {
        if entry.isLocked {
            entry.ensureItemsCount(atLeast: entry.itemCount)
            return
        }

        if isToday {
            entry.resizeItemsIfNeeded(to: settings.dailyItemCount)
            return
        }

        let required = min(entry.itemCount, settings.dailyItemCount)
        entry.ensureItemsCount(atLeast: required)
        if settings.dailyItemCount > entry.itemCount {
            entry.ensureItemsCount(atLeast: settings.dailyItemCount)
        }
    }
}

private enum DropPosition {
    case above
    case below
}

private struct DropTarget: Equatable {
    let index: Int
    let position: DropPosition
}

private struct UndoSnapshot: Equatable {
    let items: [String]
    let focusedIndex: Int?
}
