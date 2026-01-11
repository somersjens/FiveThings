//NEW DOC  DateFormatting.swift
import Foundation

enum DateFormatting {
    static func formattedDayString(_ date: Date, language: AppLanguage) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: language.localeIdentifier)

        switch language {
        case .dutch:
            // Example: "zondag 10 januari 2026"
            f.dateFormat = "EEEE d MMMM yyyy"
            return f.string(from: date)
        case .english:
            // Example: "Sunday January 10, 2026"
            f.dateFormat = "EEEE MMMM d, yyyy"
            return f.string(from: date)
        }
    }
}
