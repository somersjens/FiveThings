//NEW DOC  BrandColors.swift
import SwiftUI
import UIKit

extension Color {
    static let brandAccent = Color(red: 0x52 / 255, green: 0xA4 / 255, blue: 0x92 / 255)
    static let brandBackground = Color(uiColor: UIColor { traits in
        if traits.userInterfaceStyle == .dark {
            return UIColor(red: 0.12, green: 0.13, blue: 0.13, alpha: 1)
        }
        return UIColor(red: 0xBF / 255, green: 0xF6 / 255, blue: 0xEA / 255, alpha: 1)
    })
    static let brandSurface = Color(uiColor: UIColor { traits in
        if traits.userInterfaceStyle == .dark {
            return UIColor(red: 0.18, green: 0.19, blue: 0.20, alpha: 1)
        }
        return UIColor(white: 1, alpha: 0.92)
    })
    static let brandSecondarySurface = Color(uiColor: UIColor { traits in
        if traits.userInterfaceStyle == .dark {
            return UIColor(red: 0.22, green: 0.23, blue: 0.24, alpha: 1)
        }
        return UIColor(white: 1, alpha: 0.85)
    })
}
