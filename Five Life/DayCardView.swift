//NEW DOC  DayCardView.swift
import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct DayCardView: View {
    @Environment(\.modelContext) private var modelContext
    @ObservedObject var settings: SettingsStore
    @ObservedObject var vm: ContentViewModel

    @Bindable var entry: DayEntry

    @State private var showSuccess: Bool = false
    @State private var showIncompleteHint: Bool = false
    @State private var pulseAnimation: Bool = false
    @State private var dragIndex: Int?
    @State private var dropTarget: DropTarget?
    @State private var rowHeights: [Int: CGFloat] = [:]

    @FocusState private var focusedIndex: Int?

    private var isEditable: Bool { !entry.isLocked }

    private var isToday: Bool {
        Calendar.current.isDate(entry.day, inSameDayAs: Date())
    }

    private var dateString: String {
        DateFormatting.formattedDayString(entry.day, language: settings.language)
    }

    private var moonPhase: MoonPhaseKind? {
        settings.moonEnabled ? MoonPhase.namedPhaseIfNear(entry.day) : nil
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
        if showSuccess { return .green }
        if shouldPulse { return .yellow }
        if entry.isLocked { return Color.brandAccent.opacity(0.45) }
        return Color.brandAccent
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            VStack(spacing: 10) {
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
                .strokeBorder(outlineColor, lineWidth: 2)
        )
        .overlay(
            Group {
                if shouldPulse {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color.yellow, lineWidth: 3)
                        .opacity(pulseAnimation ? 0.2 : 1)
                        .onAppear {
                            updatePulseAnimation()
                        }
                        .onDisappear {
                            pulseAnimation = false
                        }
                }
            }
        )
        .overlay(alignment: .topTrailing) {
            if showSuccess {
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
        .onChange(of: entry.items) { _, _ in
            updatePulseAnimation()
        }
        .onChange(of: entry.isLocked) { _, locked in
            if locked {
                showSuccess = false
            }
            updatePulseAnimation()
        }
        .onChange(of: shouldPulse) { _, _ in
            updatePulseAnimation()
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                Text(dateString)
                    .font(.headline)

                if let phase = moonPhase {
                    HStack(spacing: 6) {
                        Image(systemName: phase.sfSymbolName)
                        Text(phase.localizedName(language: settings.language))
                    }
                    .font(.subheadline)
                    .foregroundStyle(.black)
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

    private func entryRow(_ idx: Int) -> some View {
        let showsRemove = isEditable && idx >= requiredCount
        let rowContent = HStack(alignment: .top, spacing: 10) {
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
        let styledRow = rowContent
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .padding(.trailing, showsRemove ? 28 : 0)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.secondary.opacity(0.08))
            )
            .background(
                GeometryReader { proxy in
                    Color.clear
                        .onAppear {
                            rowHeights[idx] = proxy.size.height
                        }
                        .onChange(of: proxy.size.height) { _, newValue in
                            rowHeights[idx] = newValue
                        }
                }
            )
            .overlay(alignment: dropTarget?.position == .above ? .top : .bottom) {
                if dropTarget?.index == idx {
                    Rectangle()
                        .fill(Color.brandAccent)
                        .frame(height: 3)
                        .clipShape(Capsule())
                        .padding(.horizontal, 8)
                        .transition(.opacity)
                }
            }
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
        let interactiveRow = styledRow
            .onDrag {
                dragIndex = idx
                return NSItemProvider(object: "" as NSString)
            } preview: {
                styledRow
            }
            .onDrop(of: [UTType.text], delegate: ItemDropDelegate(destination: idx,
                                                                   entry: entry,
                                                                   dragIndex: $dragIndex,
                                                                   dropTarget: $dropTarget,
                                                                   rowHeight: rowHeights[idx] ?? 0,
                                                                   vm: vm,
                                                                   modelContext: modelContext))
        return isEditable ? AnyView(interactiveRow) : AnyView(styledRow)
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

    private func updatePulseAnimation() {
        guard shouldPulse else {
            pulseAnimation = false
            return
        }

        pulseAnimation = false
        withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
            pulseAnimation = true
        }
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

private struct ItemDropDelegate: DropDelegate {
    let destination: Int
    let entry: DayEntry
    @Binding var dragIndex: Int?
    @Binding var dropTarget: DropTarget?
    let rowHeight: CGFloat
    let vm: ContentViewModel
    let modelContext: ModelContext

    func dropEntered(info: DropInfo) {
        updateDropTarget(with: info)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        updateDropTarget(with: info)
        return DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        guard let source = dragIndex, source != destination else {
            dragIndex = nil
            dropTarget = nil
            return true
        }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            let offset = dropTarget?.position == .below ? 1 : 0
            let count = entry.items.count
            var target = destination + offset
            if source < target {
                target -= 1
            }
            target = max(0, min(count - 1, target))
            vm.moveItem(entry, from: source, to: target, modelContext: modelContext)
        }
        dragIndex = nil
        dropTarget = nil
        return true
    }

    func dropExited(info: DropInfo) {
        dropTarget = nil
    }

    private func updateDropTarget(with info: DropInfo) {
        guard rowHeight > 0 else { return }
        let isBelow = info.location.y > rowHeight / 2
        let position: DropPosition = isBelow ? .below : .above
        if dropTarget?.index != destination || dropTarget?.position != position {
            dropTarget = DropTarget(index: destination, position: position)
        }
    }
}
