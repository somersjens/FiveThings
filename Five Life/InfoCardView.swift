import SwiftUI

struct InfoCardView: View {
    @Environment(\.responsiveTypeScale) private var responsiveTypeScale
    @Environment(\.colorScheme) private var colorScheme

    let title: String
    let items: [String]
    let infoAction: () -> Void
    let infoAccessibilityLabel: String
    let linkAction: (String) -> Void
    let numberText: (Int) -> String

    @ScaledMetric(relativeTo: .body) private var rowSpacing: CGFloat = 10
    @ScaledMetric(relativeTo: .body) private var headerIconSize: CGFloat = 31
    @ScaledMetric(relativeTo: .footnote) private var headerIconFontSize: CGFloat = 14
    @ScaledMetric(relativeTo: .subheadline) private var titleFontSize: CGFloat = 16

    private var scaledRowSpacing: CGFloat { rowSpacing * responsiveTypeScale }
    private var scaledHeaderIconSize: CGFloat { headerIconSize * responsiveTypeScale }
    private var scaledHeaderIconFontSize: CGFloat { headerIconFontSize * responsiveTypeScale }

    private var entryRowMinHeight: CGFloat {
        UIFontMetrics(forTextStyle: .body).scaledValue(for: 34 * responsiveTypeScale)
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
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    rowView(number: index + 1, text: item)
                }
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
                .strokeBorder(Color.brandAccent, lineWidth: 3)
        )
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(title)
                .font(.system(size: titleFontSize * responsiveTypeScale, weight: .semibold))
                .foregroundStyle(.primary)

            Spacer()

            Button(action: infoAction) {
                Image(systemName: "info.circle")
                    .font(.system(size: scaledHeaderIconFontSize, weight: .semibold))
                    .frame(width: scaledHeaderIconSize, height: scaledHeaderIconSize)
                    .background(.thinMaterial)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(infoAccessibilityLabel)
        }
    }

    private func rowView(number: Int, text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text(numberText(number))
                .font(.system(.body, design: .rounded).weight(.semibold))
                .frame(width: 22, alignment: .leading)
                .foregroundStyle(.primary)

            Text(formattedRowText(text))
                .font(.body)
                .lineLimit(4)
                .lineSpacing(0)
                .fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .multilineTextAlignment(.leading)
                .environment(\.openURL, OpenURLAction { url in
                    guard url.scheme == "info" else {
                        return .systemAction
                    }
                    if let action = url.host, !action.isEmpty {
                        linkAction(action)
                    }
                    return .handled
                })
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .frame(minHeight: entryRowMinHeight, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(rowBackgroundColor)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func formattedRowText(_ text: String) -> AttributedString {
        var attributed = (try? AttributedString(markdown: text)) ?? AttributedString(text)
        for run in attributed.runs {
            if run.link != nil {
                attributed[run.range].foregroundColor = Color.brandAccent
                attributed[run.range].underlineStyle = nil
            }
        }
        return attributed
    }
}
