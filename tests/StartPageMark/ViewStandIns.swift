import AppKit

struct ThemePagingTransition: Equatable {
    var from: SpaceTheme
    var theme: SpaceTheme
    var progress: CGFloat
}

enum IncognitoWindowTheme {
    static let paletteTheme = SpaceTheme.singleColor(ThemeColor(red: 0.18420, green: 0.22480, blue: 1)!)
}

enum ParcBrandMark {
    enum Style: Equatable { case monochrome, borderless }

    static func image(_ style: Style) -> NSImage? {
        NSImage(size: NSSize(width: 162, height: 240), flipped: false) { rect in
            NSColor.black.setFill()
            rect.fill()
            return true
        }
    }
}

enum ThemeHapticFeedback {
    @MainActor static var performed = 0
    @MainActor static func perform() { performed += 1 }
}

struct ThemeChromePalette {
    let isDark: Bool
    let foregroundPrimary: NSColor
    let foregroundSecondary: NSColor
    let foregroundTertiary: NSColor
    let maxContrastColor: NSColor

    var contentAppearance: NSAppearance? { NSAppearance(named: isDark ? .darkAqua : .aqua) }

    init(theme: SpaceTheme, appearance: NSAppearance) {
        self.init(theme: theme, isDark: appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua)
    }

    init(theme: SpaceTheme, isDark: Bool) {
        self.isDark = isDark
        foregroundPrimary = NSColor(srgbRed: isDark ? 1 : 0, green: isDark ? 1 : 0, blue: isDark ? 1 : 0, alpha: 1)
        foregroundSecondary = NSColor(srgbRed: 0.4, green: 0.4, blue: 0.45, alpha: 1)
        foregroundTertiary = NSColor(srgbRed: 0.7, green: 0.7, blue: 0.75, alpha: 1)
        let primary = theme.primaryColor
        maxContrastColor = NSColor(srgbRed: 1 - (primary?.red ?? 0), green: 1 - (primary?.green ?? 0), blue: 1 - (primary?.blue ?? 0), alpha: 1)
    }
}

extension NSColor {
    func cgColor(in appearance: NSAppearance?) -> CGColor { cgColor }
}

@MainActor
final class ThemeRendererView: NSView {
    weak var coordinateSpace: NSView?
    var theme = SpaceTheme()
    var drawsMaterial = true
    var pagingTransition: ThemePagingTransition?
    func invalidateCoordinates() {}
}
