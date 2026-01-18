//NEW DOC  Localization.swift
import Foundation

enum L10n {
    static func string(_ key: String, language: AppLanguage, _ args: CVarArg...) -> String {
        let bundle = bundle(for: language)
        let format = NSLocalizedString(key, bundle: bundle, comment: "")
        if args.isEmpty {
            return format
        }
        return String(format: format, locale: Locale(identifier: language.localeIdentifier), arguments: args)
    }

    private static func bundle(for language: AppLanguage) -> Bundle {
        if let path = Bundle.main.path(forResource: language.localizationCode, ofType: "lproj"),
           let bundle = Bundle(path: path) {
            return bundle
        }
        return .main
    }
}
