import SwiftUI

private struct ResponsiveTypeScaleKey: EnvironmentKey {
    static let defaultValue: CGFloat = 1.0
}

extension EnvironmentValues {
    var responsiveTypeScale: CGFloat {
        get { self[ResponsiveTypeScaleKey.self] }
        set { self[ResponsiveTypeScaleKey.self] = newValue }
    }
}

enum ResponsiveTypeScale {
    static func scale(for width: CGFloat) -> CGFloat {
        let referenceWidth: CGFloat = 393
        let rawScale = width / referenceWidth
        return min(max(rawScale, 0.9), 1.25)
    }
}
