//NEW DOC  DateFormatting.swift
import Foundation

enum DateFormatting {
    static func formattedDayString(_ date: Date, language: AppLanguage) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: language.localeIdentifier)
        f.dateStyle = .full
        f.timeStyle = .none
        return f.string(from: date)
    }
}
