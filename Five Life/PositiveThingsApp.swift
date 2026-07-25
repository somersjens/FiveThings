//NEW DOC  PositiveThingsApp.swift
import SwiftUI
import SwiftData

@main
struct PositiveThingsApp: App {
    init() {
        DataProtectionManager.configureDefaultFileProtection()
        UserDefaults.standard.removeObject(forKey: "faceIdLockEnabled")
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: [DayEntry.self])
    }
}
