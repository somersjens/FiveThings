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
    static let tabletMinimumWidth: CGFloat = 700

    static func scale(for width: CGFloat) -> CGFloat {
        if isTabletLayout(width: width) {
            return 1.30
        }

        let referenceWidth: CGFloat = 393
        let rawScale = width / referenceWidth
        return min(max(rawScale, 0.9), 1.25)
    }

    static func isTabletLayout(width: CGFloat) -> Bool {
        width >= tabletMinimumWidth
    }

    static func horizontalContentPadding(for width: CGFloat) -> CGFloat {
        guard isTabletLayout(width: width) else { return 16 }
        return min(max(width * 0.07, 48), 88)
    }

    static func cardContentPadding(for scale: CGFloat) -> CGFloat {
        scale >= 1.30 ? 22 : 14 * scale
    }
}
