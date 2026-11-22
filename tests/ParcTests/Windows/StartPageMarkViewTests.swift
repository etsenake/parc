import AppKit
import Testing
@testable import Parc
@testable import ParcCore
@testable import ParcKit

@MainActor private struct MarkRig {
    let mark = StartPageMarkView(frame: NSRect(x: 0, y: 0, width: 65, height: 96))
    let red = theme(1, 0, 0, noise: 0.4), blue = theme(0, 0, 1, noise: 0.7), colourless = SpaceTheme()

    init() {
        _ = NSApplication.shared
        mark.appearance = NSAppearance(named: .aqua)
        mark.layoutSubtreeIfNeeded()
    }

    static func views(in view: NSView) -> [NSView] { view.subviews + view.subviews.flatMap(views) }

    var renderer: ThemeRendererView? { Self.views(in: mark).compactMap { $0 as? ThemeRendererView }.first }

    var ink: NSView? {
        Self.views(in: mark).first { type(of: $0) == NSView.self && $0.layer?.backgroundColor != nil && !$0.isHidden }
    }

    var inkColor: CGColor? { ink?.layer?.backgroundColor }

    func monochrome() {
        mark.style = .monochrome
    }
}

private func theme(_ red: Double, _ green: Double, _ blue: Double, noise: Double) -> SpaceTheme {
    var theme = SpaceTheme.singleColor(ThemeColor(red: red, green: green, blue: blue)!)
    theme.noise = noise
    return theme
}

private func components(_ color: CGColor?) -> [CGFloat] {
    color?.converted(to: CGColorSpace(name: CGColorSpace.extendedSRGB)!, intent: .defaultIntent, options: nil)?.components ?? []
}

private func same(_ a: CGColor?, _ b: CGColor?) -> Bool {
    let x = components(a), y = components(b)
    return x.count == 4 && y.count == 4 && zip(x, y).allSatisfy { abs($0 - $1) < 1e-4 }
}

@MainActor private func tint(_ theme: SpaceTheme) -> CGColor {
    let palette = ThemeChromePalette(theme: theme, appearance: NSAppearance(named: .aqua)!)
    let content = palette.contentAppearance
    guard theme.isValid, theme.colorCount > 0 else { return palette.foregroundSecondary.cgColor(in: content) }
    let color = palette.maxContrastColor.cgColor(in: content)
    return color.copy(alpha: StartPageMarkView.tintAlpha) ?? color
}

@MainActor struct StartPageMarkViewTests {
    @Test func changingSpacesLeavesTheRestingMarkSilent() {
        var ticks = 0
        let mark = StartPageMarkView(frame: NSRect(x: 0, y: 0, width: 65, height: 96)) { ticks += 1 }
        let red = theme(1, 0, 0, noise: 0.4), blue = theme(0, 0, 1, noise: 0.7)
        let host = NSView()
        mark.effectsHost = host
        mark.style = .monochrome
        mark.theme = red
        mark.pagingTransition = ThemePagingTransition(from: red, theme: blue, progress: 0.5)
        mark.theme = blue
        mark.pagingTransition = nil
        mark.layoutSubtreeIfNeeded()
        #expect(ticks == 0)
    }

    @Test func draggingTheMarkNeverMovesTheWindow() {
        #expect(!MarkRig().mark.mouseDownCanMoveWindow)
    }

    @Test func theMarkIsDecorativeForAccessibility() {
        let mark = MarkRig().mark
        #expect(!mark.isAccessibilityElement() && mark.accessibilityChildren()?.isEmpty == true)
    }

    @Test func theStartPageShowsTheMultiColourMarkAndBuildsNoGradientRendererForIt() {
        let rig = MarkRig()
        #expect(rig.mark.style == .borderless && rig.renderer == nil)
    }

    @Test func aColouredThemeFillsTheMarkWithItsGradientAndTint() throws {
        let rig = MarkRig()
        rig.monochrome()
        rig.mark.theme = rig.red
        let renderer = try #require(rig.renderer)
        #expect(renderer.theme == rig.red && renderer.pagingTransition == nil && !renderer.isHidden)
        #expect(same(rig.inkColor, tint(rig.red)))
    }

    @Test func aSwipeReachesTheMarksGradientAndBlendsItsTint() throws {
        let rig = MarkRig()
        rig.monochrome()
        rig.mark.theme = rig.red
        let renderer = try #require(rig.renderer)
        let swipe = ThemePagingTransition(from: rig.red, theme: rig.blue, progress: 0.25)
        rig.mark.pagingTransition = swipe
        #expect(renderer.pagingTransition == swipe)
        #expect(same(rig.inkColor, StartPageMarkTint.blend(tint(rig.red), tint(rig.blue), progress: 0.25)))
    }

    @Test func theTintFollowsTheSwipesProgress() {
        let rig = MarkRig()
        rig.monochrome()
        rig.mark.theme = rig.red
        rig.mark.pagingTransition = ThemePagingTransition(from: rig.red, theme: rig.blue, progress: 0.75)
        #expect(same(rig.inkColor, StartPageMarkTint.blend(tint(rig.red), tint(rig.blue), progress: 0.75)))
    }

    @Test func aSwipeTowardAColourlessSpaceFadesTheGradientOutAndRefreshesTheTint() throws {
        let rig = MarkRig()
        rig.monochrome()
        rig.mark.theme = rig.red
        let renderer = try #require(rig.renderer)
        rig.mark.pagingTransition = ThemePagingTransition(from: rig.red, theme: rig.colourless, progress: 0.5)
        #expect(!renderer.isHidden && renderer.pagingTransition?.theme == rig.colourless)
        #expect(same(rig.inkColor, StartPageMarkTint.blend(tint(rig.red), tint(rig.colourless), progress: 0.5)))
    }

    @Test func aColourlessSpaceInksTheMark() throws {
        let rig = MarkRig()
        rig.monochrome()
        rig.mark.theme = rig.red
        let renderer = try #require(rig.renderer)
        rig.mark.theme = rig.colourless
        #expect(renderer.isHidden && same(rig.inkColor, tint(rig.colourless)))
    }

    @Test func aSwipeFromAColourlessSpaceShowsTheIncomingGradient() throws {
        let rig = MarkRig()
        rig.monochrome()
        rig.mark.theme = rig.red
        let renderer = try #require(rig.renderer)
        rig.mark.theme = rig.colourless
        let arriving = ThemePagingTransition(from: rig.colourless, theme: rig.blue, progress: 0.4)
        rig.mark.pagingTransition = arriving
        #expect(!renderer.isHidden && renderer.pagingTransition == arriving)
        #expect(same(rig.inkColor, StartPageMarkTint.blend(tint(rig.colourless), tint(rig.blue), progress: 0.4)))
    }

    @Test func aSwipeBetweenColourlessSpacesKeepsTheInk() throws {
        let rig = MarkRig()
        rig.monochrome()
        rig.mark.theme = rig.red
        let renderer = try #require(rig.renderer)
        rig.mark.theme = rig.colourless
        rig.mark.pagingTransition = ThemePagingTransition(from: rig.colourless, theme: SpaceTheme(), progress: 0.4)
        #expect(renderer.isHidden && renderer.pagingTransition == nil)
    }

    @Test func theEndOfASwipeSettlesOnTheNewSpace() throws {
        let rig = MarkRig()
        rig.monochrome()
        rig.mark.theme = rig.red
        let renderer = try #require(rig.renderer)
        rig.mark.pagingTransition = ThemePagingTransition(from: rig.red, theme: rig.blue, progress: 0.4)
        rig.mark.pagingTransition = nil
        rig.mark.theme = rig.blue
        #expect(!renderer.isHidden && renderer.pagingTransition == nil && same(rig.inkColor, tint(rig.blue)))
    }

    @Test func aPrivateWindowIgnoresSwipesAndKeepsItsOwnInk() throws {
        let rig = MarkRig()
        rig.monochrome()
        rig.mark.theme = rig.red
        let renderer = try #require(rig.renderer)
        rig.mark.incognito = true
        rig.mark.pagingTransition = ThemePagingTransition(from: rig.red, theme: rig.blue, progress: 0.25)
        #expect(renderer.isHidden && renderer.pagingTransition == nil)
        #expect(same(rig.inkColor, ThemeChromePalette(theme: IncognitoWindowTheme.paletteTheme, isDark: false).foregroundSecondary.cgColor))
    }

    @Test func theColourMarkIgnoresSwipes() throws {
        let rig = MarkRig()
        rig.monochrome()
        rig.mark.theme = rig.red
        let renderer = try #require(rig.renderer)
        rig.mark.style = .borderless
        rig.mark.pagingTransition = ThemePagingTransition(from: rig.red, theme: rig.blue, progress: 0.25)
        #expect(renderer.isHidden && renderer.pagingTransition == nil && rig.ink == nil)
    }

    @Test func theEffectsHostStaysEmptyAtRest() {
        let rig = MarkRig()
        let host = NSView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        rig.mark.effectsHost = host
        #expect(rig.mark.effectsHost === host && host.subviews.isEmpty)
    }
}
