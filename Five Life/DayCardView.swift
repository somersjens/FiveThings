//NEW DOC  DayCardView.swift
import SwiftUI
import SwiftData

struct DayCardView: View {
    @Environment(\.modelContext) private var modelContext
    @ObservedObject var settings: SettingsStore
    @ObservedObject var vm: ContentViewModel

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

    private let rowSpacing: CGFloat = 10

    @FocusState private var focusedIndex: Int?

    private static let fullMoonTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()

    private var isEditable: Bool { !entry.isLocked }

    private var isToday: Bool {
        Calendar.current.isDate(entry.day, inSameDayAs: Date())
    }

    private var dateString: String {
        DateFormatting.formattedDayString(entry.day, language: settings.language)
    }

    private var moonPhase: MoonPhaseKind? {
        settings.moonEnabled ? MoonPhase.phase(on: entry.day) : nil
    }

    private var fullMoonTimeText: String? {
        guard settings.moonEnabled, moonPhase == .fullMoon else { return nil }
        let fullMoonDate = MoonPhase.fullMoonDate(near: entry.day)
        guard Calendar.current.isDate(fullMoonDate, inSameDayAs: entry.day) else { return nil }
        DayCardView.fullMoonTimeFormatter.locale = settings.locale
        return DayCardView.fullMoonTimeFormatter.string(from: fullMoonDate)
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

    private var shouldPulse: Bool {
        !entry.isLocked && entry.isComplete(requiredCount: requiredCount) && !showSuccess
    }

    private var outlineColor: Color {
        if showSuccess { return Color.brandAccent }
        if shouldPulse { return .yellow }
        if entry.isLocked { return Color.brandAccent }
        return .orange
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            VStack(spacing: rowSpacing) {
                if hasOptionalRows && !entry.isLocked {
                    Text(settings.language == .dutch
                         ? "Optioneel (boven je huidige ingestelde aantal)"
                         : "Optional (above your current set amount)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 4)
                }

                ForEach(0..<displayCount, id: \.self) { idx in
                    entryRow(idx)
                }

                if isEditable {
                    Color.clear
                        .frame(height: rowSpacing)
                }
            }
            .coordinateSpace(name: "entryList")
            .overlay {
                dragOverlay
            }

            if showIncompleteHint {
                Text(settings.language == .dutch
                     ? "Vul alle velden in om te vergrendelen."
                     : "Fill all fields to lock.")
                    .font(.footnote)
                    .foregroundStyle(.black)
                    .transition(.opacity)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.background)
                .shadow(radius: 6, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(outlineColor, lineWidth: 3)
        )
        .animation(.easeInOut(duration: 0.2), value: outlineColor)
        .overlay(alignment: .topTrailing) {
            if showSuccess && entry.isLocked {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 28, weight: .semibold))
                    .padding(10)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .onAppear {
            syncEntryCounts()
        }
        .onChange(of: settings.dailyItemCount) { _, _ in
            syncEntryCounts()
        }
        .onChange(of: entry.isLocked) { _, locked in
            if !locked {
                showSuccess = false
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                Text(dateString)
                    .font(.headline)

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
                        Text(holiday)
                            .font(.subheadline)
                            .foregroundStyle(.black)
                    }
                    if let phase = moonPhase {
                        moonLine(phase)
                    }
                }
            }

            Spacer()

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
                    .font(.system(size: 18, weight: .semibold))
                    .padding(10)
                    .background(.thinMaterial)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(entry.isLocked
                                ? (settings.language == .dutch ? "Ontgrendelen" : "Unlock")
                                : (settings.language == .dutch ? "Vergrendelen" : "Lock"))
        }
    }

    private func moonLine(_ phase: MoonPhaseKind) -> some View {
        let timeText = fullMoonTimeText
        return HStack(spacing: 6) {
            Image(systemName: phase.sfSymbolName)
            Text(timeText == nil
                 ? phase.localizedName(language: settings.language)
                 : "\(phase.localizedName(language: settings.language)) • \(timeText ?? "")")
        }
        .font(.subheadline)
        .foregroundStyle(.black)
    }

    private func entryRow(_ idx: Int) -> some View {
        let showsRemove = isEditable && idx >= requiredCount
        let styledRow = rowContainer(idx: idx,
                                     showsRemove: showsRemove,
                                     applyInsertionPadding: true,
                                     trackSize: true)
        let interactiveRow = styledRow
            .opacity(isDragging && dragIndex == idx ? 0 : 1)
            .allowsHitTesting(!(isDragging && dragIndex == idx))
            .zIndex(dragIndex == idx ? 1 : 0)
            .simultaneousGesture(dragGesture(for: idx))
        return isEditable ? AnyView(interactiveRow) : AnyView(styledRow)
    }

    private func rowContainer(idx: Int,
                              showsRemove: Bool,
                              applyInsertionPadding: Bool,
                              trackSize: Bool) -> some View {
        let baseRow = rowContent(idx: idx)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .padding(.trailing, showsRemove ? 28 : 0)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(.systemGray6))
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
                        vm.removeItem(entry, index: idx, modelContext: modelContext)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 26, height: 26)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(settings.language == .dutch ? "Optionele regel verwijderen" : "Remove optional entry")
                    .padding(.trailing, 6)
                }
            }
    }

    private func rowContent(idx: Int) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(idx + 1).")
                .font(.system(.body, design: .rounded).weight(.semibold))
                .frame(width: 28, alignment: .leading)
                .foregroundStyle(.black)

            if isEditable {
                TextField(
                    settings.language == .dutch ? "Schrijf iets positiefs…" : "Write something positive…",
                    text: Binding(
                        get: { entry.items[safe: idx] ?? "" },
                        set: { newValue in
                            if idx < entry.items.count {
                                let hasNewline = newValue.contains("\n")
                                let sanitized = newValue.replacingOccurrences(of: "\n", with: "")
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
                .lineLimit(1...4)
                .foregroundStyle(.black)
                .focused($focusedIndex, equals: idx)
                .disabled(isDragging || suppressFocus)
                .submitLabel(idx == displayCount - 1 ? .done : .next)
                .onSubmit {
                    handleSubmit(at: idx)
                }
            } else {
                Text(highlightedText(entry.items[safe: idx] ?? ""))
                    .foregroundStyle(.black)
                    .lineLimit(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var dragOverlay: some View {
        GeometryReader { _ in
            if let dragIndex, let frame = rowFrames[dragIndex], isDragging {
                rowContainer(idx: dragIndex,
                             showsRemove: isEditable && dragIndex >= requiredCount,
                             applyInsertionPadding: false,
                             trackSize: false)
                    .frame(width: frame.width, height: frame.height, alignment: .leading)
                    .position(x: frame.midX + dragOffset.width, y: frame.midY + dragOffset.height)
                    .zIndex(2)
                    .allowsHitTesting(false)
            }
        }
    }

    private func dragGesture(for idx: Int) -> some Gesture {
        LongPressGesture(minimumDuration: 0.5)
            .sequenced(before: DragGesture(minimumDistance: 6))
            .onChanged { value in
                switch value {
                case .first(true):
                    suppressFocus = true
                    focusedIndex = nil
                case .second(true, let dragValue?):
                    if dragIndex == nil {
                        dragIndex = idx
                        isDragging = true
                    }
                    guard dragIndex == idx else { return }
                    dragOffset = dragValue.translation
                    let currentY = (rowFrames[idx]?.midY ?? 0) + dragValue.translation.height
                    updateDropTarget(currentY: currentY, source: idx)
                default:
                    break
                }
            }
            .onEnded { value in
                switch value {
                case .second(true, _):
                    completeDrag()
                default:
                    suppressFocus = false
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
            dragIndex = nil
            dropTarget = nil
            dragOffset = .zero
            isDragging = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                suppressFocus = false
            }
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
            vm.moveItem(entry, from: source, to: target, modelContext: modelContext)
        }
    }

    private func highlightedText(_ text: String) -> AttributedString {
        let query = vm.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return AttributedString(text) }

        var attributed = AttributedString(text)
        var searchRange = text.startIndex..<text.endIndex

        while let foundRange = text.range(of: query,
                                          options: [.caseInsensitive, .diacriticInsensitive],
                                          range: searchRange) {
            if let lowerBound = AttributedString.Index(foundRange.lowerBound, within: attributed),
               let upperBound = AttributedString.Index(foundRange.upperBound, within: attributed) {
                attributed[lowerBound..<upperBound].font = .body.weight(.bold)
            }
            searchRange = foundRange.upperBound..<text.endIndex
        }

        return attributed
    }

    private func dragInsertionPadding(for idx: Int) -> EdgeInsets {
        guard let dragIndex, let dropTarget, dragIndex != idx else { return EdgeInsets() }
        guard dropTarget.index == idx else { return EdgeInsets() }

        let dragHeight = rowHeights[dragIndex] ?? rowHeights[idx] ?? 44
        let gap = dragHeight + rowSpacing

        switch dropTarget.position {
        case .above:
            return EdgeInsets(top: gap, leading: 0, bottom: 0, trailing: 0)
        case .below:
            return EdgeInsets(top: 0, leading: 0, bottom: gap, trailing: 0)
        }
    }

    private func handleSubmit(at index: Int) {
        guard isEditable else { return }

        if index < displayCount - 1 {
            focusedIndex = index + 1
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
