//NEW DOC  DateFormatting.swift
import Foundation

enum DateFormatting {
    static func formattedDayString(_ date: Date, language: AppLanguage) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: language.localeIdentifier)
        f.dateStyle = .full
        f.timeStyle = .none
        f.timeZone = TimeZone(secondsFromGMT: 0)
        return f.string(from: date)
    }
}
