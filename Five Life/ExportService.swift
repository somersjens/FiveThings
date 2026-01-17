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
    private static let pdfHeaderDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "dd-MM-yyyy"
        return formatter
    }()

    struct ExportFilterContext {
        let finishedLimit: ContentViewModel.FinishedCardsLimit
        let newestFirst: Bool
    }

    static func export(entries: [DayEntry],
                       language: AppLanguage,
                       format: ExportFormat,
                       filterContext: ExportFilterContext) throws -> URL {
        let destination = makeTemporaryURL(withExtension: format.fileExtension)
        switch format {
        case .csv:
            let csvString = csvContent(entries: entries)
            guard let data = csvString.data(using: .utf8) else {
                throw ExportError.encodingFailed
            }
            try data.write(to: destination, options: .atomic)
        case .pdf:
            let pdfData = pdfContent(entries: entries,
                                     language: language,
                                     filterContext: filterContext)
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

    private static func pdfContent(entries: [DayEntry],
                                   language: AppLanguage,
                                   filterContext: ExportFilterContext) -> Data {
        let pageRect = CGRect(x: 0, y: 0, width: 595.2, height: 841.8)
        let margin: CGFloat = 36
        let columnSpacing: CGFloat = 24
        let columnWidth = (pageRect.width - (margin * 2) - columnSpacing) / 2
        let topY = margin
        let headerBottomSpacing: CGFloat = 12
        let headerMaxWidth = pageRect.width - (margin * 2)
        let generationDate = Date()

        let pdfHeaderFont = UIFont.systemFont(ofSize: 9, weight: .semibold)
        let headerFont = UIFont.systemFont(ofSize: 14, weight: .semibold)
        let bodyFont = UIFont.systemFont(ofSize: 12, weight: .regular)
        let pdfHeaderAttributes: [NSAttributedString.Key: Any] = [
            .font: pdfHeaderFont,
            .foregroundColor: UIColor.darkGray
        ]
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
            let totalPages = pdfTotalPages(entries: entries,
                                           language: language,
                                           filterContext: filterContext,
                                           headerAttributes: pdfHeaderAttributes,
                                           headerWidth: headerMaxWidth,
                                           headerBottomSpacing: headerBottomSpacing,
                                           margin: margin,
                                           columnWidth: columnWidth,
                                           pageRect: pageRect)
            var currentColumn = 0
            var currentY = topY
            var currentPage = 1

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

            func headerText(page: Int) -> String {
                pdfHeaderText(language: language,
                              generationDate: generationDate,
                              filterContext: filterContext,
                              page: page,
                              totalPages: totalPages)
            }

            func headerHeight(for page: Int) -> CGFloat {
                let text = headerText(page: page)
                let bounding = (text as NSString).boundingRect(
                    with: CGSize(width: headerMaxWidth, height: .greatestFiniteMagnitude),
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    attributes: pdfHeaderAttributes,
                    context: nil
                )
                return ceil(bounding.height)
            }

            func drawHeader(page: Int) -> CGFloat {
                let text = headerText(page: page)
                let height = headerHeight(for: page)
                let headerRect = CGRect(x: margin, y: topY, width: headerMaxWidth, height: height)
                (text as NSString).draw(in: headerRect, withAttributes: pdfHeaderAttributes)
                return height
            }

            func beginNewPage() {
                context.beginPage()
                currentColumn = 0
                let headerHeight = drawHeader(page: currentPage)
                currentY = topY + headerHeight + headerBottomSpacing
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

                let entryHeaderHeight = heightForText(headerText, attributes: headerAttributes)
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

                let blockHeight = entryHeaderHeight
                    + (items.isEmpty ? 0 : headerSpacing + itemsHeight)
                    + blockSpacing

                let remainingHeight = pageRect.height - margin - currentY
                if blockHeight > remainingHeight {
                    if currentColumn == 0 {
                        currentColumn = 1
                        currentY = topY + headerHeight(for: currentPage) + headerBottomSpacing
                    } else {
                        currentPage += 1
                        beginNewPage()
                    }
                }

                let x = columnX(currentColumn)
                var drawY = currentY

                let headerRect = CGRect(x: x, y: drawY, width: columnWidth, height: entryHeaderHeight)
                (headerText as NSString).draw(in: headerRect, withAttributes: headerAttributes)
                drawY += entryHeaderHeight

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

    private static func pdfTotalPages(entries: [DayEntry],
                                      language: AppLanguage,
                                      filterContext: ExportFilterContext,
                                      headerAttributes: [NSAttributedString.Key: Any],
                                      headerWidth: CGFloat,
                                      headerBottomSpacing: CGFloat,
                                      margin: CGFloat,
                                      columnWidth: CGFloat,
                                      pageRect: CGRect) -> Int {
        let entryHeaderFont = UIFont.systemFont(ofSize: 14, weight: .semibold)
        let entryBodyFont = UIFont.systemFont(ofSize: 12, weight: .regular)
        let entryHeaderAttributes: [NSAttributedString.Key: Any] = [
            .font: entryHeaderFont,
            .foregroundColor: UIColor.black
        ]
        let entryBodyAttributes: [NSAttributedString.Key: Any] = [
            .font: entryBodyFont,
            .foregroundColor: UIColor.black
        ]

        func heightForText(_ text: String, attributes: [NSAttributedString.Key: Any]) -> CGFloat {
            let bounding = (text as NSString).boundingRect(
                with: CGSize(width: columnWidth, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: attributes,
                context: nil
            )
            return ceil(bounding.height)
        }

        func headerHeight(for totalPages: Int) -> CGFloat {
            let sampleHeader = pdfHeaderText(language: language,
                                             generationDate: Date(),
                                             filterContext: filterContext,
                                             page: 1,
                                             totalPages: totalPages)
            let bounding = (sampleHeader as NSString).boundingRect(
                with: CGSize(width: headerWidth, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: headerAttributes,
                context: nil
            )
            return ceil(bounding.height)
        }

        func layoutPageCount(totalPagesEstimate: Int) -> Int {
            let pageHeaderHeight = headerHeight(for: totalPagesEstimate)
            let topY = margin + pageHeaderHeight + headerBottomSpacing

            var pageCount = 1
            var currentColumn = 0
            var currentY = topY

            for entry in entries {
                let dateString = DateFormatting.formattedDayString(entry.day, language: language)
                let headerText: String
                if let score = entry.score {
                    headerText = "\(dateString) (score \(score))"
                } else {
                    headerText = dateString
                }

                let items = sanitizedItems(from: entry).map { "- \(capitalizedFirstLetter($0))" }

                let entryHeaderHeight = heightForText(headerText, attributes: entryHeaderAttributes)
                let headerSpacing: CGFloat = 4
                let itemSpacing: CGFloat = 2
                let blockSpacing: CGFloat = 10

                var itemsHeight: CGFloat = 0
                for (index, item) in items.enumerated() {
                    itemsHeight += heightForText(item, attributes: entryBodyAttributes)
                    if index != items.count - 1 {
                        itemsHeight += itemSpacing
                    }
                }

                let blockHeight = entryHeaderHeight
                    + (items.isEmpty ? 0 : headerSpacing + itemsHeight)
                    + blockSpacing

                let remainingHeight = pageRect.height - margin - currentY
                if blockHeight > remainingHeight {
                    if currentColumn == 0 {
                        currentColumn = 1
                        currentY = topY
                    } else {
                        pageCount += 1
                        currentColumn = 0
                        currentY = topY
                    }
                }

                let itemBlockHeight = entryHeaderHeight
                    + (items.isEmpty ? 0 : headerSpacing + itemsHeight)
                    + blockSpacing
                currentY += itemBlockHeight
            }

            return pageCount
        }

        var lastCount = 0
        var pageCount = 1
        var attempts = 0
        while pageCount != lastCount, attempts < 5 {
            lastCount = pageCount
            pageCount = layoutPageCount(totalPagesEstimate: pageCount)
            attempts += 1
        }

        return pageCount
    }

    private static func pdfHeaderText(language: AppLanguage,
                                      generationDate: Date,
                                      filterContext: ExportFilterContext,
                                      page: Int,
                                      totalPages: Int) -> String {
        let dateString = pdfHeaderDateFormatter.string(from: generationDate)
        let orderText: String
        let limitText: String

        switch language {
        case .dutch:
            orderText = filterContext.newestFirst ? "aflopende" : "oplopende"
            if filterContext.finishedLimit == .all {
                limitText = "alle informatie"
            } else {
                let positionText = "laatste"
                limitText = "de \(positionText) \(filterContext.finishedLimit.rawValue) dagen"
            }
            return "PDF gegenereerd op \(dateString): \(limitText) in \(orderText) volgorde (filter instellingen) - pagina \(page)/\(totalPages)"
        case .english:
            orderText = filterContext.newestFirst ? "descending" : "ascending"
            if filterContext.finishedLimit == .all {
                limitText = "all entries"
            } else {
                let positionText = "last"
                limitText = "the \(positionText) \(filterContext.finishedLimit.rawValue) entries"
            }
            return "PDF generated on \(dateString): \(limitText) in \(orderText) order (filter settings) - page \(page)/\(totalPages)"
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
