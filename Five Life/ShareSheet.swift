import SwiftUI
import UIKit

struct ShareSheetItem: Identifiable {
    let id = UUID()
    let items: [Any]
    let cleanupURLs: [URL]

    init(items: [Any], cleanupURLs: [URL] = []) {
        self.items = items
        self.cleanupURLs = cleanupURLs
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    let cleanupURLs: [URL]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        controller.completionWithItemsHandler = { _, _, _, _ in
            cleanupURLs.forEach { url in
                try? FileManager.default.removeItem(at: url)
            }
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
