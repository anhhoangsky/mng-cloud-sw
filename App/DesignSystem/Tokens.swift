import SwiftUI
import UIKit

/// Design tokens ported from `ui/assets/app.css` (light/dark values).
enum Palette {
    static let bg = Color.mng(light: 0xFFFFFF, dark: 0x07090D)
    static let bgGrouped = Color.mng(light: 0xF2F2F7, dark: 0x0B0F15)
    static let bgElevated = Color.mng(light: 0xFFFFFF, dark: 0x10151D)
    static let bgElevated2 = Color.mng(light: 0xF2F2F7, dark: 0x161D27)

    static let text = Color.mng(light: 0x000000, dark: 0xF2F5F9)
    static let text2 = Color.mng(light: 0x3C3C43, dark: 0xE3E9F1)
    static let text3 = Color.mng(light: 0x3C3C43, lightAlpha: 0.6, dark: 0xF2F5F9, darkAlpha: 0.62)
    static let text4 = Color.mng(light: 0x3C3C43, lightAlpha: 0.36, dark: 0xF2F5F9, darkAlpha: 0.42)
    static let textMuted = Color.mng(light: 0x6E6E73, dark: 0x9AA7B6)

    static let sep = Color.mng(light: 0x3C3C43, lightAlpha: 0.22, dark: 0xFFFFFF, darkAlpha: 0.12)
    static let hairline = Color.mng(light: 0x3C3C43, lightAlpha: 0.29, dark: 0xFFFFFF, darkAlpha: 0.09)
    static let fill = Color.mng(light: 0x787880, lightAlpha: 0.12, dark: 0xFFFFFF, darkAlpha: 0.08)
    static let fill2 = Color.mng(light: 0x787880, lightAlpha: 0.16, dark: 0xFFFFFF, darkAlpha: 0.12)
    static let fill3 = Color.mng(light: 0x787880, lightAlpha: 0.24, dark: 0xFFFFFF, darkAlpha: 0.16)

    static let accent = Color.mng(light: 0x007AFF, dark: 0x7DD3FC)
    static let accentStrong = Color.mng(light: 0x0066D6, dark: 0x38BDF8)
    static let accentInk = Color.mng(light: 0xFFFFFF, dark: 0x041018)
    static let accentSoft = Color.mng(light: 0x007AFF, lightAlpha: 0.12, dark: 0x7DD3FC, darkAlpha: 0.12)

    static let danger = Color.mng(light: 0xFF3B30, dark: 0xFB7185)
    static let dangerSoft = Color.mng(light: 0xFF3B30, lightAlpha: 0.12, dark: 0xFB7185, darkAlpha: 0.12)
    static let green = Color.mng(light: 0x34C759, dark: 0x34D399)
    static let orange = Color.mng(light: 0xFF9500, dark: 0xFBBF24)

    static let brandBlue = Color.mng(light: 0x0082C9, dark: 0x38BDF8)
    static let seafile = Color.mng(light: 0x0A7C74, dark: 0x2DD4BF)
    static let icloud = Color.mng(light: 0x1C8BFA, dark: 0x60A5FA)
}

enum Tokens {
    enum Radius {
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 28
    }

    enum Spacing {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 24
    }

    enum Layout {
        static let sidebarWidth: CGFloat = 264
        static let tabBarHeight: CGFloat = 68
        static let contentMaxWidth: CGFloat = 1500
        static let gridGap: CGFloat = 2
        static let cardGap: CGFloat = 18
    }

    enum Motion {
        static let ease = Animation.timingCurve(0.32, 0.72, 0, 1, duration: 0.32)
        static let fade = Animation.easeOut(duration: 0.2)
        static let viewer = Animation.easeOut(duration: 0.24)
        /// `--glass-ease` + `--glass-dur` from `app.css`.
        static let glass = Animation.timingCurve(1, 0, 0.4, 1, duration: 0.32)
        /// `--spring` used by the compact thumb and the press states.
        static let spring = Animation.spring(response: 0.34, dampingFraction: 0.72)
    }
}

extension Color {
    /// Parses the `#rgb`/`#rrggbb` colors the server stores in `CloudCard.color`.
    static func mngHex(_ string: String) -> Color? {
        var hex = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if hex.hasPrefix("#") {
            hex.removeFirst()
        }
        if hex.count == 3 {
            hex = hex.map { "\($0)\($0)" }.joined()
        }
        guard hex.count == 6, let value = UInt32(hex, radix: 16) else {
            return nil
        }
        return Color(uiColor: UIColor(hex: value, alpha: 1))
    }

    /// Dynamic color from the legacy light/dark palette.
    static func mng(
        light: UInt32,
        lightAlpha: CGFloat = 1,
        dark: UInt32,
        darkAlpha: CGFloat = 1
    ) -> Color {
        Color(uiColor: UIColor { traits in
            let isDark = traits.userInterfaceStyle == .dark
            return UIColor(
                hex: isDark ? dark : light,
                alpha: isDark ? darkAlpha : lightAlpha
            )
        })
    }
}

extension Font {
    /// A fixed-size font that still follows the user's Dynamic Type setting.
    ///
    /// The web client uses pixel sizes, so the app keeps them but scales them
    /// with the system text size. The growth is capped at 1.6× so the big
    /// headlines stay usable at the accessibility sizes; a display title can
    /// pass a lower cap when matching a fixed web size matters more.
    static func mng(
        _ size: CGFloat,
        weight: Weight = .regular,
        design: Design? = nil,
        cap: CGFloat = 1.6
    ) -> Font {
        let base: UIFont
        if design == .monospaced {
            base = UIFont.monospacedSystemFont(
                ofSize: size,
                weight: mngUIWeight(weight)
            )
        } else {
            base = UIFont.systemFont(ofSize: size, weight: mngUIWeight(weight))
        }
        let factor = min(max(UIFontMetrics.default.scaledValue(for: 1), 1), cap)
        return Font(base.withSize(size * factor))
    }

    private static func mngUIWeight(_ weight: Weight) -> UIFont.Weight {
        switch weight {
        case .ultraLight: return .ultraLight
        case .thin: return .thin
        case .light: return .light
        case .medium: return .medium
        case .semibold: return .semibold
        case .bold: return .bold
        case .heavy: return .heavy
        case .black: return .black
        default: return .regular
        }
    }
}

private extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat) {
        let red = CGFloat((hex >> 16) & 0xFF) / 255
        let green = CGFloat((hex >> 8) & 0xFF) / 255
        let blue = CGFloat(hex & 0xFF) / 255
        self.init(red: red, green: green, blue: blue, alpha: alpha)
    }
}
