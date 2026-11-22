import AppKit
import ParcCore

public struct ParcMenuColors {
    package let base: NSColor
    package let background: NSColor
    package let hover: NSColor
    package let title: NSColor
    package let subtitle: NSColor
    package let disabledTitle: NSColor
    package let disabledSubtitle: NSColor

    package init(theme: SpaceTheme) {
        let light = ThemeChromePalette(theme: theme, isDark: false)
        let dark = ThemeChromePalette(theme: theme, isDark: true)
        func either(_ light: NSColor, _ dark: NSColor) -> NSColor {
            NSColor(name: nil) { $0.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light }
        }
        base = either(.white, .black)
        background = either(light.backgroundExtra, dark.backgroundExtra)
        hover = either(light.hover, dark.hover)
        title = either(.black, .white)
        subtitle = either(light.subtitle, dark.subtitle)
        let disabled = either(NSColor(srgbRed: 171 / 255, green: 171 / 255, blue: 171 / 255, alpha: 1),
                              NSColor(srgbRed: 121 / 255, green: 120 / 255, blue: 129 / 255, alpha: 1))
        disabledTitle = disabled
        disabledSubtitle = disabled
    }

    package func fillBackground(_ path: NSBezierPath) {
        base.setFill()
        path.fill()
        background.setFill()
        path.fill()
    }
}
