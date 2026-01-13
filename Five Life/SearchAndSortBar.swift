//NEW DOC  SearchAndSortBar.swift
import SwiftUI

struct SearchAndSortBar: View {
    @ObservedObject var settings: SettingsStore
    @Binding var text: String
    @Binding var newestFirst: Bool
    @Binding var finishedLimit: ContentViewModel.FinishedCardsLimit

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.black)

                TextField(settings.language == .dutch ? "Zoek in kaarten…" : "Search cards…",
                          text: $text)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .foregroundStyle(.black)

                if !text.isEmpty {
                    Button {
                        text = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.black)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(settings.language == .dutch ? "Wis zoekopdracht" : "Clear search")
                }
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.secondary.opacity(0.10))
            )

            Button {
                finishedLimit = finishedLimit.next()
            } label: {
                Text(finishedLimit.displayText)
                    .font(.system(size: 12, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(.black)
                    .frame(width: 40, height: 40)
                    .background(.secondary.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(settings.language == .dutch
                                ? "Laatste \(finishedLimit.displayText) kaarten tonen"
                                : "Show last \(finishedLimit.displayText) cards")

            Button {
                newestFirst.toggle()
            } label: {
                Image(systemName: newestFirst ? "arrow.down" : "arrow.up")
                    .font(.system(size: 16, weight: .semibold))
                    .padding(12)
                    .background(.secondary.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(settings.language == .dutch
                                ? (newestFirst ? "Nieuw naar oud" : "Oud naar nieuw")
                                : (newestFirst ? "New to old" : "Old to new"))
        }
    }
}
