//NEW DOC  Localization.swift
import Foundation

enum L10n {
    static func string(_ key: String, language: AppLanguage, _ args: CVarArg...) -> String {
        let bundle = bundle(for: language)
        let format = NSLocalizedString(key, bundle: bundle, comment: "")
        if args.isEmpty {
            return format
        }
        let placeholders = formatPlaceholders(in: format)
        guard !placeholders.isEmpty else {
            return format
        }

        let usesPositionalIndexes = placeholders.contains { $0.index != nil }
        if usesPositionalIndexes {
            if matchesPlaceholderTypes(placeholders: placeholders, args: args) {
                return String(format: format,
                              locale: Locale(identifier: language.localeIdentifier),
                              arguments: args)
            }
            return safeFormat(format: format, placeholders: placeholders, args: args)
        }

        if matchesPlaceholderTypes(placeholders: placeholders, args: args) {
            return String(format: format, locale: Locale(identifier: language.localeIdentifier), arguments: args)
        }

        if let reorderedArgs = reorderArgumentsByType(placeholders: placeholders, args: args),
           matchesPlaceholderTypes(placeholders: placeholders, args: reorderedArgs) {
            return String(format: format, locale: Locale(identifier: language.localeIdentifier), arguments: reorderedArgs)
        }

        return safeFormat(format: format, placeholders: placeholders, args: args)
    }

    private static func bundle(for language: AppLanguage) -> Bundle {
        if let path = Bundle.main.path(forResource: language.localizationCode, ofType: "lproj"),
           let bundle = Bundle(path: path) {
            return bundle
        }
        return .main
    }

    private enum FormatArgType {
        case object
        case integer
        case floating
        case other
    }

    private struct FormatPlaceholder {
        let range: NSRange
        let index: Int?
        let type: FormatArgType
    }

    private static func formatPlaceholders(in format: String) -> [FormatPlaceholder] {
        let pattern = "%(?!%)(?:(\\d+)\\$)?[+-]?(?:\\d+)?(?:\\.\\d+)?([@a-zA-Z])"
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return []
        }
        let range = NSRange(format.startIndex..<format.endIndex, in: format)
        let matches = regex.matches(in: format, range: range)
        return matches.compactMap { match -> FormatPlaceholder? in
            let indexRange = match.range(at: 1)
            let specifierRange = match.range(at: 2)
            guard let typeCharRange = Range(specifierRange, in: format) else {
                return nil
            }
            guard let typeChar = format[typeCharRange].first else {
                return nil
            }
            let index: Int?
            if let indexRange = Range(indexRange, in: format) {
                index = Int(format[indexRange])
            } else {
                index = nil
            }
            return FormatPlaceholder(range: match.range, index: index, type: formatArgType(for: typeChar))
        }
    }

    private static func formatArgType(for typeChar: Character) -> FormatArgType {
        switch typeChar {
        case "@":
            return .object
        case "d", "i", "u", "x", "X", "o", "c":
            return .integer
        case "f", "F", "e", "E", "g", "G", "a", "A":
            return .floating
        default:
            return .other
        }
    }

    private static func argType(_ arg: CVarArg) -> FormatArgType {
        switch arg {
        case is Int, is Int8, is Int16, is Int32, is Int64,
             is UInt, is UInt8, is UInt16, is UInt32, is UInt64,
             is Bool:
            return .integer
        case is Double, is Float:
            return .floating
        default:
            return .object
        }
    }

    private static func matchesPlaceholderTypes(placeholders: [FormatPlaceholder], args: [CVarArg]) -> Bool {
        guard !placeholders.isEmpty else { return true }
        if placeholders.count > args.count {
            return false
        }
        for (index, placeholder) in placeholders.enumerated() {
            if placeholder.type == .other {
                continue
            }
            let argIndex = (placeholder.index ?? (index + 1)) - 1
            guard argIndex >= 0, argIndex < args.count else {
                return false
            }
            let argType = argType(args[argIndex])
            if placeholder.type != .object, placeholder.type != argType {
                return false
            }
        }
        return true
    }

    private static func reorderArgumentsByType(placeholders: [FormatPlaceholder], args: [CVarArg]) -> [CVarArg]? {
        var unusedIndices = Array(args.indices)
        var reordered: [CVarArg] = []
        reordered.reserveCapacity(placeholders.count)
        for placeholder in placeholders {
            let desiredType = placeholder.type
            if desiredType == .other {
                if let index = unusedIndices.first {
                    reordered.append(args[index])
                    unusedIndices.removeFirst()
                    continue
                } else {
                    return nil
                }
            }
            if desiredType == .object {
                if let index = unusedIndices.first {
                    reordered.append(args[index])
                    unusedIndices.removeFirst()
                    continue
                }
                return nil
            }
            guard let matchIndex = unusedIndices.first(where: { argType(args[$0]) == desiredType }) else {
                return nil
            }
            reordered.append(args[matchIndex])
            unusedIndices.removeAll { $0 == matchIndex }
        }
        return reordered
    }


    private static func safeFormat(format: String, placeholders: [FormatPlaceholder], args: [CVarArg]) -> String {
        let nsFormat = format as NSString
        var output = ""
        var currentLocation = 0
        var argIndex = 0
        for placeholder in placeholders {
            let range = placeholder.range
            let prefixLength = range.location - currentLocation
            if prefixLength > 0 {
                let prefixRange = NSRange(location: currentLocation, length: prefixLength)
                output += nsFormat.substring(with: prefixRange)
            }
            let replacement: String
            if let explicitIndex = placeholder.index {
                let index = explicitIndex - 1
                if index >= 0, index < args.count {
                    replacement = String(describing: args[index])
                } else {
                    replacement = ""
                }
            } else if argIndex < args.count {
                replacement = String(describing: args[argIndex])
                argIndex += 1
            } else {
                replacement = ""
            }
            output += replacement
            currentLocation = range.location + range.length
        }
        if currentLocation < nsFormat.length {
            let suffixRange = NSRange(location: currentLocation, length: nsFormat.length - currentLocation)
            output += nsFormat.substring(with: suffixRange)
        }
        return output
    }
}
