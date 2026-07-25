//NEW DOC  DateFormatting.swift
import Foundation

enum DateFormatting {
    static func formattedDayString(_ date: Date, language: AppLanguage) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: language.localeIdentifier)
        f.dateStyle = .full
        f.timeStyle = .none
        f.timeZone = TimeZone(secondsFromGMT: 0)
        let formatted = f.string(from: date)
        guard let firstCharacter = formatted.first,
              firstCharacter.unicodeScalars.contains(where: CharacterSet.letters.contains) else {
            return formatted
        }

        let capitalizedFirstCharacter = String(firstCharacter).uppercased(with: f.locale)
        return capitalizedFirstCharacter + formatted.dropFirst()
    }
}
