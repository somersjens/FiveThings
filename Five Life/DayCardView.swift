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
        if entry.isLocked { return .secondary.opacity(0.35) }
        return .secondary.opacity(0.25)
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
                    .foregroundStyle(.secondary)
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
                .stroke(outlineColor, lineWidth: readyToLockPulse ? 4 : 2)
                .scaleEffect(readyToLockPulse ? 1.01 : 1.0)
                .animation(readyToLockPulse ? .easeInOut(duration: 0.9).repeatForever(autoreverses: true) : .default, value: readyToLockPulse)
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
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(dateString)
                        .font(.headline)

                    if let phase = moonPhase {
                        HStack(spacing: 6) {
                            Image(systemName: phase.sfSymbolName)
                            Text(phase.localizedName(language: settings.language))
                        }
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    }
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
                .foregroundStyle(.secondary)

            TextField(
                settings.language == .dutch ? "Schrijf iets positiefs…" : "Write something positive…",
                text: Binding(
                    get: { entry.items[safe: idx] ?? "" },
                    set: { newValue in
                        if idx < entry.items.count {
                            vm.updateItem(entry, index: idx, text: newValue, modelContext: modelContext)
                        }
                    }
                ),
                axis: .vertical
            )
            .textFieldStyle(.plain)
            .lineLimit(1...4)
            .disabled(!isEditable)
            .focused($focusedIndex, equals: idx)
            .submitLabel(idx == entry.itemCount - 1 ? .done : .next)
            .onSubmit {
                handleSubmit(at: idx)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.secondary.opacity(0.08))
        )
    }

    private func handleSubmit(at index: Int) {
        guard isEditable else { return }

        if index < entry.itemCount -
