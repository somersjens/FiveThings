import Foundation
import UIKit

enum ExportFormat {
    case pdf
    case csv

    var fileExtension: String {
        switch self {
        case .pdf:
            return "pdf"
        case .csv:
            return "csv"
        }
    }
}

enum ExportError: Error {
    case encodingFailed
}

enum ExportService {
    private static let csvDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "dd-MM-yyyy"
        return formatter
    }()

    static func export(entries: [DayEntry], language: AppLanguage, format: ExportFormat) throws -> URL {
        let destination = makeTemporaryURL(withExtension: format.fileExtension)
        switch format {
        case .csv:
            let csvString = csvContent(entries: entries)
            guard let data = csvString.data(using: .utf8) else {
                throw ExportError.encodingFailed
            }
            try data.write(to: destination, options: .atomic)
        case .pdf:
            let pdfData = pdfContent(entries: entries, language: language)
            try pdfData.write(to: destination, options: .atomic)
        }
        return destination
    }

    private static func csvContent(entries: [DayEntry]) -> String {
        let hasScore = entries.contains { $0.score != nil }
        var lines: [String] = ["Date, entry, Description, score"]

        for entry in entries {
            let dateString = csvDateFormatter.string(from: entry.day)
            let items = sanitizedItems(from: entry)
            let scoreString = hasScore ? (entry.score.map(String.init) ?? "") : ""

            for (index, item) in items.enumerated() {
                let ordinal = ordinalEntry(for: index + 1)
                let fields = [dateString, ordinal, item, scoreString]
                lines.append(fields.map { csvEscape($0) }.joined(separator: ","))
            }
        }

        return lines.joined(separator: "\n")
    }

    private static func pdfContent(entries: [DayEntry], language: AppLanguage) -> Data {
        let pageRect = CGRect(x: 0, y: 0, width: 595.2, height: 841.8)
        let margin: CGFloat = 36
        let columnSpacing: CGFloat = 24
        let columnWidth = (pageRect.width - (margin * 2) - columnSpacing) / 2
        let topY = margin

        let headerFont = UIFont.systemFont(ofSize: 14, weight: .semibold)
        let bodyFont = UIFont.systemFont(ofSize: 12, weight: .regular)
        let headerAttributes: [NSAttributedString.Key: Any] = [
            .font: headerFont,
            .foregroundColor: UIColor.black
        ]
        let bodyAttributes: [NSAttributedString.Key: Any] = [
            .font: bodyFont,
            .foregroundColor: UIColor.black
        ]

        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)
        return renderer.pdfData { context in
            var currentColumn = 0
            var currentY = topY

            func columnX(_ column: Int) -> CGFloat {
                margin + CGFloat(column) * (columnWidth + columnSpacing)
            }

            func heightForText(_ text: String, attributes: [NSAttributedString.Key: Any]) -> CGFloat {
                let bounding = (text as NSString).boundingRect(
                    with: CGSize(width: columnWidth, height: .greatestFiniteMagnitude),
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    attributes: attributes,
                    context: nil
                )
                return ceil(bounding.height)
            }

            func beginNewPage() {
                context.beginPage()
                currentColumn = 0
                currentY = topY
            }

            beginNewPage()

            for entry in entries {
                let dateString = DateFormatting.formattedDayString(entry.day, language: language)
                let headerText: String
                if let score = entry.score {
                    headerText = "\(dateString) (score \(score))"
                } else {
                    headerText = dateString
                }

                let items = sanitizedItems(from: entry).map { "- \(capitalizedFirstLetter($0))" }

                let headerHeight = heightForText(headerText, attributes: headerAttributes)
                let headerSpacing: CGFloat = 4
                let itemSpacing: CGFloat = 2
                let blockSpacing: CGFloat = 10

                var itemsHeight: CGFloat = 0
                for (index, item) in items.enumerated() {
                    itemsHeight += heightForText(item, attributes: bodyAttributes)
                    if index != items.count - 1 {
                        itemsHeight += itemSpacing
                    }
                }

                let blockHeight = headerHeight
                    + (items.isEmpty ? 0 : headerSpacing + itemsHeight)
                    + blockSpacing

                let remainingHeight = pageRect.height - margin - currentY
                if blockHeight > remainingHeight {
                    if currentColumn == 0 {
                        currentColumn = 1
                        currentY = topY
                    } else {
                        beginNewPage()
                    }
                }

                let x = columnX(currentColumn)
                var drawY = currentY

                let headerRect = CGRect(x: x, y: drawY, width: columnWidth, height: headerHeight)
                (headerText as NSString).draw(in: headerRect, withAttributes: headerAttributes)
                drawY += headerHeight

                if !items.isEmpty {
                    drawY += headerSpacing
                    for item in items {
                        let itemHeight = heightForText(item, attributes: bodyAttributes)
                        let itemRect = CGRect(x: x, y: drawY, width: columnWidth, height: itemHeight)
                        (item as NSString).draw(in: itemRect, withAttributes: bodyAttributes)
                        drawY += itemHeight + itemSpacing
                    }
                }

                currentY = drawY + blockSpacing
            }
        }
    }

    private static func sanitizedItems(from entry: DayEntry) -> [String] {
        entry.items
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func ordinalEntry(for index: Int) -> String {
        let suffix: String
        let tens = index % 100
        if tens >= 11 && tens <= 13 {
            suffix = "th"
        } else {
            switch index % 10 {
            case 1: suffix = "st"
            case 2: suffix = "nd"
            case 3: suffix = "rd"
            default: suffix = "th"
            }
        }
        return "\(index)\(suffix) entry"
    }

    private static func csvEscape(_ value: String) -> String {
        if value.contains("\"") {
            let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(escaped)\""
        }
        if value.contains(",") || value.contains("\n") {
            return "\"\(value)\""
        }
        return value
    }

    private static func capitalizedFirstLetter(_ value: String) -> String {
        guard let first = value.first else { return value }
        let firstString = String(first)
        let rest = value.dropFirst()
        if firstString.uppercased() == firstString {
            return value
        }
        return firstString.uppercased() + rest
    }

    private static func makeTemporaryURL(withExtension fileExtension: String) -> URL {
        let dateStamp = ISO8601DateFormatter().string(from: Date())
        let filename = "FiveThings-Export-\(dateStamp).\(fileExtension)"
        return FileManager.default.temporaryDirectory.appendingPathComponent(filename)
    }
}
