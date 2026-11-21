import AppKit
import Testing
@testable import Parc
import ParcCore

@MainActor
struct SidebarPlusMenuPaletteTests {
    fileprivate enum Theme: CaseIterable, Sendable {
        case purple, blue, colourless
        var value: SpaceTheme {
            switch self {
            case .purple: SpaceTheme(primaryColor: ThemeColor(hex: "3D2468"), colorCount: 1, appearance: .dark, noise: 0.3)
            case .blue: SpaceTheme(primaryColor: ThemeColor(hex: "3F9BD6"), colorCount: 2, noise: 0.3)
            case .colourless: SpaceTheme()
            }
        }
    }

    nonisolated private static let themesAndModes = Theme.allCases.flatMap { theme in [false, true].map { (theme, $0) } }

    private func resolved(_ color: NSColor, dark: Bool) -> [CGFloat] {
        var components: [CGFloat] = []
        NSAppearance(named: dark ? .darkAqua : .aqua)!.performAsCurrentDrawingAppearance {
            let value = color.usingColorSpace(.extendedSRGB)!
            components = [value.redComponent, value.greenComponent, value.blueComponent, value.alphaComponent]
        }
        return components
    }

    private func same(_ a: NSColor, _ b: NSColor, dark: Bool) -> Bool {
        zip(resolved(a, dark: dark), resolved(b, dark: dark)).allSatisfy { abs($0 - $1) < 1e-5 }
    }

    private func grey(dark: Bool) -> NSColor {
        dark ? NSColor(srgbRed: 121 / 255, green: 120 / 255, blue: 129 / 255, alpha: 1)
            : NSColor(srgbRed: 171 / 255, green: 171 / 255, blue: 171 / 255, alpha: 1)
    }

    @Test(arguments: themesAndModes)
    fileprivate func theCardBaseIsBlackOrWhite(theme: Theme, dark: Bool) {
        #expect(same(ParcMenuColors(theme: theme.value).base, dark ? .black : .white, dark: dark))
    }

    @Test(arguments: themesAndModes)
    fileprivate func theCardIsBackgroundExtra(theme: Theme, dark: Bool) {
        let palette = ThemeChromePalette(theme: theme.value, isDark: dark)
        #expect(same(ParcMenuColors(theme: theme.value).background, palette.backgroundExtra, dark: dark))
    }

    @Test(arguments: themesAndModes)
    fileprivate func rowsAndSeparatorsAreHover(theme: Theme, dark: Bool) {
        let palette = ThemeChromePalette(theme: theme.value, isDark: dark)
        #expect(same(ParcMenuColors(theme: theme.value).hover, palette.hover, dark: dark))
    }

    @Test(arguments: themesAndModes)
    fileprivate func shortcutsAreSubtitle(theme: Theme, dark: Bool) {
        let palette = ThemeChromePalette(theme: theme.value, isDark: dark)
        #expect(same(ParcMenuColors(theme: theme.value).subtitle, palette.subtitle, dark: dark))
    }

    @Test(arguments: themesAndModes)
    fileprivate func titlesAndIconsAreBasePrimary(theme: Theme, dark: Bool) {
        #expect(same(ParcMenuColors(theme: theme.value).title, dark ? .white : .black, dark: dark))
    }

    @Test(arguments: themesAndModes)
    fileprivate func disabledTitlesAndShortcutsShareTheMenuGrey(theme: Theme, dark: Bool) {
        let colors = ParcMenuColors(theme: theme.value)
        #expect(same(colors.disabledTitle, grey(dark: dark), dark: dark))
        #expect(same(colors.disabledSubtitle, grey(dark: dark), dark: dark))
    }

    @Test func aForcedDarkThemeStillShowsItsLightHalfInALightApp() {
        let purple = Theme.purple.value
        #expect(!same(ParcMenuColors(theme: purple).background, ThemeChromePalette(theme: purple, isDark: true).backgroundExtra, dark: false))
    }
}

@MainActor
struct SidebarPlusMenuRenderingTests {
    private let colors = ParcMenuColors(theme: SpaceTheme(primaryColor: ThemeColor(hex: "3D2468"), colorCount: 1, appearance: .dark, noise: 0.3))
    private let rows = SidebarPlusMenuModel.rows(privateBrowsing: false, canCreateEasel: true, canCreateNote: true, canSplit: true) { id in
        id == "newTab:" ? "⌘T" : id == "createEasel:" ? "⌃⇧E" : id == "createNote:" ? "⌃⇧N" : id == "split:" ? "⌃⇧=" : ""
    }
    private let shortcutBox = NSRect(x: 140, y: 105, width: 62, height: 40)
    private let titleBox = NSRect(x: 48, y: 8, width: 110, height: 40)

    private struct Ink {
        var color: [CGFloat]
        var width: CGFloat
    }

    private func resolved(_ color: NSColor, dark: Bool) -> [CGFloat] {
        var components: [CGFloat] = []
        NSAppearance(named: dark ? .darkAqua : .aqua)!.performAsCurrentDrawingAppearance {
            let value = color.usingColorSpace(.extendedSRGB)!
            components = [value.redComponent, value.greenComponent, value.blueComponent, value.alphaComponent]
        }
        return components
    }

    private func over(_ foreground: NSColor, _ background: [CGFloat], dark: Bool) -> [CGFloat] {
        let f = resolved(foreground, dark: dark)
        return (0..<3).map { (f[$0] * f[3] + background[$0] * (1 - f[3])) * 255 }
    }

    private func opaque(_ color: NSColor, dark: Bool) -> [CGFloat] {
        resolved(color, dark: dark).prefix(3).map { $0 * 255 }
    }

    private func background(dark: Bool) -> [CGFloat] {
        over(colors.background, resolved(colors.base, dark: dark), dark: dark)
    }

    private func highlight(dark: Bool) -> [CGFloat] {
        over(colors.hover, background(dark: dark).map { $0 / 255 }, dark: dark)
    }

    private func render(_ view: NSView, dark: Bool) -> NSBitmapImageRep {
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: view.frame.size), styleMask: [.borderless], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.contentView = view
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(view.bounds.width * 2), pixelsHigh: Int(view.bounds.height * 2),
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0)!.retagging(with: .sRGB)!
        rep.size = view.bounds.size
        view.cacheDisplay(in: view.bounds, to: rep)
        window.contentView = nil
        return rep
    }

    private func card(_ rows: [SidebarPlusRow], dark: Bool) -> NSBitmapImageRep {
        render(SidebarPlusMenuView(rows: rows, colors: colors) { _ in }, dark: dark)
    }

    private func pixel(_ rep: NSBitmapImageRep, _ x: CGFloat, _ y: CGFloat) -> [CGFloat] {
        var raw = [Int](repeating: 0, count: 4)
        rep.getPixel(&raw, atX: Int(x * 2), y: Int(y * 2))
        return raw.prefix(3).map(CGFloat.init)
    }

    private func near(_ a: [CGFloat], _ b: [CGFloat], _ tolerance: CGFloat = 2) -> Bool {
        zip(a, b).allSatisfy { abs($0 - $1) <= tolerance }
    }

    private func ink(_ rep: NSBitmapImageRep, _ box: NSRect, background: [CGFloat]) -> Ink {
        var best: (CGFloat, [CGFloat]) = (0, background)
        var minX = CGFloat.infinity, maxX = -CGFloat.infinity
        for py in Int(box.minY * 2)..<Int(box.maxY * 2) {
            for px in Int(box.minX * 2)..<Int(box.maxX * 2) {
                let value = pixel(rep, CGFloat(px) / 2, CGFloat(py) / 2)
                let distance = zip(value, background).map { ($0 - $1) * ($0 - $1) }.reduce(0, +)
                if distance > best.0 { best = (distance, value) }
                if distance > 40 * 40 { minX = min(minX, CGFloat(px) / 2); maxX = max(maxX, CGFloat(px + 1) / 2) }
            }
        }
        return Ink(color: best.1, width: maxX - minX)
    }

    private func typeset(_ text: NSAttributedString) -> CGFloat {
        text.boundingRect(with: .zero, options: [.usesLineFragmentOrigin, .usesDeviceMetrics]).width
    }

    private func typeset(_ text: String, _ attributes: [NSAttributedString.Key: Any]) -> CGFloat {
        typeset(NSAttributedString(string: text, attributes: attributes))
    }

    @Test(arguments: [false, true])
    func theCardIsBackgroundExtraOverTheBase(dark: Bool) {
        #expect(near(pixel(card(rows, dark: dark), 100, 4), background(dark: dark)))
    }

    @Test(arguments: [false, true])
    func bothSeparatorsAreOnePointOfHover(dark: Bool) {
        let rep = card(rows, dark: dark)
        let line = over(colors.hover, background(dark: dark).map { $0 / 255 }, dark: dark)
        #expect(near(pixel(rep, 100, 96.5), line))
        #expect(near(pixel(rep, 100, 193.5), line))
        #expect(near(pixel(rep, 100, 95), background(dark: dark)))
        #expect(near(pixel(rep, 100, 98), background(dark: dark)))
    }

    @Test(arguments: [false, true])
    func onlyTheHighlightedNewTabRowIsFilled(dark: Bool) {
        let rep = card(rows, dark: dark)
        #expect(near(pixel(rep, 120, 245), highlight(dark: dark)))
        #expect(near(pixel(rep, 120, 205), background(dark: dark)))
    }

    @Test(arguments: [false, true])
    func titlesAreThirteenPointMediumBasePrimary(dark: Bool) {
        let title = ink(card(rows, dark: dark), titleBox, background: background(dark: dark))
        #expect(near(title.color, opaque(colors.title, dark: dark), 3))
        #expect(abs(title.width - typeset("New Space", [.font: NSFont.systemFont(ofSize: 13, weight: .medium)])) <= 1)
    }

    @Test(arguments: [false, true])
    func shortcutsAreThirteenPointSubtitleKernedTwo(dark: Bool) {
        let shortcut = ink(card(rows, dark: dark), shortcutBox, background: background(dark: dark))
        #expect(near(shortcut.color, over(colors.subtitle, background(dark: dark).map { $0 / 255 }, dark: dark), 3))
        #expect(abs(shortcut.width - typeset("⌃⇧E", [.font: NSFont.systemFont(ofSize: 13), .kern: 2])) <= 1)
    }

    @Test(arguments: [false, true])
    func theHighlightedRowKeepsTheSubtitleShortcutColour(dark: Bool) {
        let shortcut = ink(card(rows, dark: dark), NSRect(x: 150, y: 242, width: 52, height: 40), background: highlight(dark: dark))
        #expect(near(shortcut.color, over(colors.subtitle, highlight(dark: dark).map { $0 / 255 }, dark: dark), 3))
    }

    private var keypadRows: [SidebarPlusRow] {
        SidebarPlusMenuModel.rows(privateBrowsing: false, canCreateEasel: true, canCreateNote: true, canSplit: true) {
            $0 == "newTab:" ? "⌃Keypad 1" : $0 == "createEasel:" ? "⌃SS" : ""
        }
    }

    @Test(arguments: [false, true])
    func aKeypadShortcutTracksOnlyItsModifier(dark: Bool) {
        let keypad = ink(card(keypadRows, dark: dark), NSRect(x: 112, y: 250, width: 84, height: 24), background: highlight(dark: dark))
        let text = NSMutableAttributedString(string: "⌃", attributes: [.font: NSFont.systemFont(ofSize: 13), .kern: 2])
        text.append(NSAttributedString(string: "Keypad 1", attributes: [.font: NSFont.systemFont(ofSize: 13)]))
        #expect(abs(keypad.width - typeset(text)) <= 1)
        #expect(near(keypad.color, over(colors.subtitle, highlight(dark: dark).map { $0 / 255 }, dark: dark), 3))
    }

    @Test(arguments: [false, true])
    func aShortcutWithoutASpaceTracksEveryCharacter(dark: Bool) {
        let doubled = ink(card(keypadRows, dark: dark), shortcutBox, background: background(dark: dark))
        #expect(abs(doubled.width - typeset("⌃SS", [.font: NSFont.systemFont(ofSize: 13), .kern: 2])) <= 1)
    }

    private var disabledRows: [SidebarPlusRow] {
        SidebarPlusMenuModel.rows(privateBrowsing: true, canCreateEasel: false, canCreateNote: false, canSplit: false) {
            $0 == "createEasel:" ? "⌃⇧E" : ""
        }
    }

    @Test(arguments: [false, true])
    func disabledTitlesAreMenuDisabledText(dark: Bool) {
        let title = ink(card(disabledRows, dark: dark), titleBox, background: background(dark: dark))
        #expect(near(title.color, opaque(colors.disabledTitle, dark: dark), 3))
    }

    @Test(arguments: [false, true])
    func disabledShortcutsAreMenuSubtitle(dark: Bool) {
        let shortcut = ink(card(disabledRows, dark: dark), shortcutBox, background: background(dark: dark))
        #expect(near(shortcut.color, over(colors.disabledSubtitle, background(dark: dark).map { $0 / 255 }, dark: dark), 3))
    }

    @Test(arguments: [false, true])
    func theTailMatchesTheCard(dark: Bool) {
        let chrome = SidebarPlusMenuChrome(card: SidebarPlusMenuView(rows: rows, colors: colors) { _ in }, tailX: 190)
        #expect(near(pixel(render(chrome, dark: dark), 190, 296 - 4.5), background(dark: dark)))
    }

    @Test func aDarkThemedHUDDrawsTheThemesLightHalfInALightApp() {
        #expect(near(pixel(card(rows, dark: false), 100, 4), background(dark: false)))
        #expect(!near(background(dark: false), background(dark: true)))
    }
}
