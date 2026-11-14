import AppKit

@MainActor @main struct StartPageMarkViewTests {
    static var count = 0
    static func check(_ value: @autoclosure () -> Bool, _ message: String) {
        count += 1
        guard value() else { fatalError("StartPageMarkView: \(message)") }
    }

    static func views(in view: NSView) -> [NSView] { view.subviews + view.subviews.flatMap(views) }
    static func renderer(_ mark: StartPageMarkView) -> ThemeRendererView? { views(in: mark).compactMap { $0 as? ThemeRendererView }.first }
    static func ink(_ mark: StartPageMarkView) -> NSView? {
        views(in: mark).first { type(of: $0) == NSView.self && $0.layer?.backgroundColor != nil && !$0.isHidden }
    }
    static func components(_ color: CGColor?) -> [CGFloat] {
        color?.converted(to: CGColorSpace(name: CGColorSpace.extendedSRGB)!, intent: .defaultIntent, options: nil)?.components ?? []
    }
    static func same(_ a: CGColor?, _ b: CGColor?) -> Bool {
        let x = components(a), y = components(b)
        return x.count == 4 && y.count == 4 && zip(x, y).allSatisfy { abs($0 - $1) < 1e-4 }
    }

    static func theme(_ red: Double, _ green: Double, _ blue: Double, noise: Double) -> SpaceTheme {
        var theme = SpaceTheme.singleColor(ThemeColor(red: red, green: green, blue: blue)!)
        theme.noise = noise
        return theme
    }

    static func tint(_ theme: SpaceTheme) -> CGColor {
        let palette = ThemeChromePalette(theme: theme, isDark: false)
        guard theme.isValid, theme.colorCount > 0 else { return palette.foregroundSecondary.cgColor }
        return palette.maxContrastColor.cgColor.copy(alpha: StartPageMarkView.tintAlpha)!
    }

    static func main() {
        let mark = StartPageMarkView(frame: NSRect(x: 0, y: 0, width: 65, height: 96))
        mark.appearance = NSAppearance(named: .aqua)
        mark.layoutSubtreeIfNeeded()
        check(!mark.mouseDownCanMoveWindow, "dragging the mark never moves the window")
        check(!mark.isAccessibilityElement() && mark.accessibilityChildren()?.isEmpty == true, "the mark is decorative for accessibility")
        check(mark.style == .borderless && renderer(mark) == nil, "the start page shows the multi-colour mark and builds no gradient renderer for it")
        mark.style = .monochrome
        let red = theme(1, 0, 0, noise: 0.4), blue = theme(0, 0, 1, noise: 0.7), colourless = SpaceTheme()
        mark.theme = red
        guard let renderer = renderer(mark) else { return check(false, "a coloured theme fills the mark with its gradient") }
        check(renderer.theme == red && renderer.pagingTransition == nil && !renderer.isHidden, "at rest the mark draws its own Space")
        check(same(ink(mark)?.layer?.backgroundColor, tint(red)), "at rest the mark carries its Space's tint")

        let swipe = ThemePagingTransition(from: red, theme: blue, progress: 0.25)
        mark.pagingTransition = swipe
        check(renderer.pagingTransition != nil, "a swipe reaches the mark's gradient")
        check(renderer.pagingTransition == swipe, "the mark's gradient keeps its texture through a swipe")
        check(same(ink(mark)?.layer?.backgroundColor, StartPageMarkTint.blend(tint(red), tint(blue), progress: 0.25)),
              "the mark's tint blends through a swipe")
        mark.pagingTransition = ThemePagingTransition(from: red, theme: blue, progress: 0.75)
        check(same(ink(mark)?.layer?.backgroundColor, StartPageMarkTint.blend(tint(red), tint(blue), progress: 0.75)),
              "the tint follows the swipe's progress")

        mark.pagingTransition = ThemePagingTransition(from: red, theme: colourless, progress: 0.5)
        check(!renderer.isHidden && renderer.pagingTransition?.theme == colourless, "a swipe toward a colourless Space fades the gradient out")
        check(same(ink(mark)?.layer?.backgroundColor, StartPageMarkTint.blend(tint(red), tint(colourless), progress: 0.5)),
              "a colourless side refreshes the tint toward the label colour")

        mark.pagingTransition = nil
        mark.theme = colourless
        check(renderer.isHidden && same(ink(mark)?.layer?.backgroundColor, tint(colourless)), "a colourless Space inks the mark")
        let arriving = ThemePagingTransition(from: colourless, theme: blue, progress: 0.4)
        mark.pagingTransition = arriving
        check(!renderer.isHidden && renderer.pagingTransition == arriving, "a swipe from a colourless Space shows the incoming gradient")
        check(same(ink(mark)?.layer?.backgroundColor, StartPageMarkTint.blend(tint(colourless), tint(blue), progress: 0.4)),
              "the tint blends from the label colour toward the incoming Space")
        mark.pagingTransition = ThemePagingTransition(from: colourless, theme: SpaceTheme(), progress: 0.4)
        check(renderer.isHidden && renderer.pagingTransition == nil, "a swipe between colourless Spaces keeps the ink")

        mark.pagingTransition = nil
        mark.theme = blue
        check(!renderer.isHidden && renderer.pagingTransition == nil && same(ink(mark)?.layer?.backgroundColor, tint(blue)),
              "the end of a swipe settles on the new Space")

        mark.incognito = true
        mark.pagingTransition = swipe
        check(renderer.isHidden && renderer.pagingTransition == nil, "a private window ignores swipes")
        check(same(ink(mark)?.layer?.backgroundColor, ThemeChromePalette(theme: IncognitoWindowTheme.paletteTheme, isDark: false).foregroundSecondary.cgColor),
              "a private window keeps its own ink")
        mark.incognito = false
        mark.style = .borderless
        check(renderer.isHidden && renderer.pagingTransition == nil && ink(mark) == nil, "the colour mark ignores swipes")

        let host = NSView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        mark.effectsHost = host
        check(mark.effectsHost === host && host.subviews.isEmpty, "the effects host stays empty at rest")
        check(ThemeHapticFeedback.performed == 0, "nothing ticks at rest")
        print("StartPageMarkView: \(count) assertions passed")
    }
}
