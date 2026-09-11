import SwiftUI
#if !os(watchOS)
import UIKit
#endif

enum Theme {
    #if os(watchOS)
    static let background = Color.black
    static let surface = Color(red: 0.06, green: 0.10, blue: 0.18)
    static let elevated = Color(red: 0.10, green: 0.16, blue: 0.26)
    static let textPrimary = Color.white
    static let textSecondary = Color(white: 0.7)
    #else
    static let background = Color(light: .init(0.95, 0.97, 1), dark: .init(0.025, 0.045, 0.09))
    static let surface = Color(light: .init(1, 1, 1), dark: .init(0.055, 0.085, 0.15))
    static let elevated = Color(light: .init(0.90, 0.94, 0.99), dark: .init(0.09, 0.14, 0.23))
    static let textPrimary = Color(light: .init(0.04, 0.08, 0.15), dark: .init(1, 1, 1))
    static let textSecondary = Color(light: .init(0.34, 0.40, 0.50), dark: .init(0.64, 0.70, 0.80))
    #endif

    static let cyan = Color(red: 0.22, green: 0.86, blue: 0.96)
    static let violet = Color(red: 0.48, green: 0.40, blue: 0.98)
    static let mint = Color(red: 0.25, green: 0.88, blue: 0.66)
    static let warning = Color(red: 1.0, green: 0.65, blue: 0.24)
    static let cardRadius: CGFloat = 24

    static var forecastGradient: LinearGradient {
        LinearGradient(colors: [cyan, violet], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

#if !os(watchOS)
private extension Color {
    struct RGB {
        let red: Double
        let green: Double
        let blue: Double

        init(_ red: Double, _ green: Double, _ blue: Double) {
            self.red = red
            self.green = green
            self.blue = blue
        }
    }

    init(light: RGB, dark: RGB) {
        self.init(uiColor: UIColor { traits in
            let value = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: value.red, green: value.green, blue: value.blue, alpha: 1)
        })
    }
}
#endif
