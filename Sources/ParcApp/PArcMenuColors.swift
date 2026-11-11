import AppKit

struct PArcMenuColors {
    let base: NSColor
    let background: NSColor
    let hover: NSColor
    let title: NSColor
    let subtitle: NSColor
    let disabledTitle: NSColor
    let disabledSubtitle: NSColor

    init(theme: SpaceTheme) {
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

    func fillBackground(_ path: NSBezierPath) {
        base.setFill()
        path.fill()
        background.setFill()
        path.fill()
    }
}
