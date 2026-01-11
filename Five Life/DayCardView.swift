//NEW DOC  DayCardView.swift
import SwiftUI
import SwiftData

struct DayCardView: View {
    @Environment(\.modelContext) private var modelContext
    @ObservedObject var settings: SettingsStore
    @ObservedObject var vm: ContentViewModel

    @Bindable var entry: DayEntry

    @State private var readyToLockPulse: Bool = false
    @State private var showSuccess: Bool = false
    @State private var showIncompleteHint: Bool = false

    @FocusState private var focusedIndex: Int?

    private var isEditable: Bool { !entry.isLocked }

    private var dateString: String {
        DateFormatting.formattedDayString(entry.day, language: settings.language)
    }

    private var moonPhase: MoonPhaseKind? {
        settings.moonEnabled ? MoonPhase.namedPhaseIfNear(entry.day) : nil
    }

    private var outlineColor: Color {
        if showSuccess { return .green }
        if readyToLockPulse { return .yellow }
        if entry.isLocked { return Color.brandAccent.opacity(0.45) }
        return Color.brandAccent
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            VStack(spacing: 10) {
                ForEach(0..<entry.itemCount, id: \.self) { idx in
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
                .strokeBorder(outlineColor, lineWidth: readyToLockPulse ? 4 : 2)
                .animation(readyToLockPulse ? .easeInOut(duration: 0.9).repeatForever(autoreverses: true) : .default,
                           value: readyToLockPulse)
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
            // Keep itemCount stable for older days; only resize unlocked days if settings changed and it's today.
            // (Today creation/resize is handled in vm.ensureTodayEntry)
            if entry.items.count != entry.itemCount {
                entry.resizeItemsIfNeeded(to: entry.itemCount)
            }
        }
        .onChange(of: entry.items) { _, _ in
            if !entry.isLocked, !entry.isComplete {
                readyToLockPulse = false
            }
        }
        .onChange(of: entry.isLocked) { _, locked in
            if locked {
                readyToLockPulse = false
                showSuccess = false
            }
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
                    vm.unlock(entry, modelContext: modelContext)
                    readyToLockPulse = false
                    showSuccess = false
                } else {
                    // If unlocked: allow lock only if complete, otherwise show hint
                    if entry.isComplete {
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
                Image(systemName: entry.isLocked ? "lock.fill" : (readyToLockPulse ? "lock.open.fill" : "lock.open"))
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
                .submitLabel(idx == entry.itemCount - 1 ? .done : .next)
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
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.secondary.opacity(0.08))
        )
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

        if index < entry.itemCount - 1 {
            focusedIndex = index + 1
            return
        }

        focusedIndex = nil
        if entry.isComplete {
            withAnimation(.easeInOut(duration: 0.2)) {
                readyToLockPulse = true
            }
        } else {
            withAnimation(.easeInOut(duration: 0.2)) { showIncompleteHint = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                withAnimation(.easeInOut(duration: 0.2)) { showIncompleteHint = false }
            }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }

    private func triggerLockFlow() {
        vm.lock(entry, modelContext: modelContext)
        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
            readyToLockPulse = false
            showSuccess = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            withAnimation(.easeInOut(duration: 0.2)) {
                showSuccess = false
            }
        }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }
}
