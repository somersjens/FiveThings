//NEW DOC  SearchAndSortBar.swift
import SwiftUI

struct SearchAndSortBar: View {
    @ObservedObject var settings: SettingsStore
    @Binding var text: String
    @Binding var newestFirst: Bool
    @Binding var finishedLimit: ContentViewModel.FinishedCardsLimit
    @Environment(\.responsiveTypeScale) private var responsiveTypeScale
    @ScaledMetric(relativeTo: .footnote) private var filterFontSize: CGFloat = 12
    @ScaledMetric(relativeTo: .headline) private var sortIconSize: CGFloat = 16
    @ScaledMetric(relativeTo: .body) private var controlSize: CGFloat = 40

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.black)

                TextField(L10n.string("search.placeholder", language: settings.language),
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
                    .accessibilityLabel(L10n.string("search.clear", language: settings.language))
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
                Text(finishedLimit.displayText(language: settings.language))
                    .font(.system(size: filterFontSize * responsiveTypeScale, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(.black)
                    .frame(width: controlSize * responsiveTypeScale,
                           height: controlSize * responsiveTypeScale)
                    .background(.secondary.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.string("filters.show.last",
                                            language: settings.language,
                                            finishedLimit.displayText(language: settings.language)))

            Button {
                newestFirst.toggle()
            } label: {
                Image(systemName: newestFirst ? "arrow.down" : "arrow.up")
                    .font(.system(size: sortIconSize * responsiveTypeScale, weight: .semibold))
                    .padding(12)
                    .background(.secondary.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(newestFirst
                                ? L10n.string("filters.sort.newest.first", language: settings.language)
                                : L10n.string("filters.sort.oldest.first", language: settings.language))
        }
    }
}
