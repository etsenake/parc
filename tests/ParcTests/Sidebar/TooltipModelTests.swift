import AppKit
import Testing
@testable import Parc
@testable import ParcCore
@testable import ParcKit

@MainActor
struct TooltipModelTests {
    static let commandS = KeyboardShortcut(key: "s", flags: .command)

    private static func near(_ a: CGFloat, _ b: CGFloat, _ tolerance: CGFloat = 0.001) -> Bool { abs(a - b) <= tolerance }
    private static func near(_ a: CGRect, _ b: CGRect) -> Bool {
        near(a.minX, b.minX) && near(a.minY, b.minY) && near(a.width, b.width) && near(a.height, b.height)
    }
    static func components(_ color: NSColor) -> [CGFloat] {
        let c = color.usingColorSpace(.extendedSRGB)!
        return [c.redComponent, c.greenComponent, c.blueComponent, c.alphaComponent]
    }
    static func same(_ a: NSColor, _ b: NSColor) -> Bool { zip(components(a), components(b)).allSatisfy { abs($0 - $1) < 0.0005 } }
    static func gray(_ color: NSColor, _ white: CGFloat) -> Bool {
        same(color, NSColor(colorSpace: .extendedSRGB, components: [white, white, white, 1], count: 4))
    }

    @Test func aStandardTooltipShowsBottomTrailingAfterAnIdleDelay() {
        let standard = TooltipConfiguration("Hide sidebar")
        #expect(standard.anchor == .bottomTrailing)
        #expect(standard.behavior == .onMouseIdle(delay: 0.45))
    }

    @Test func aStandardTooltipHasNoShortcutWidthLimitAllowedModifiersOrPalette() {
        let standard = TooltipConfiguration("Hide sidebar")
        #expect(standard.shortcut == nil && standard.maxWidth == nil && standard.allowedModifierKeys == [] && standard.palette == nil)
    }

    @Test func theMaximumWidthIs296Points() {
        #expect(TooltipConfiguration.defaultMaxWidth == 296)
    }

    @Test func theAnchorsAreTheEightEdgesThenTheCursor() {
        #expect(TooltipConfiguration.Anchor.allCases.map(\.rawValue) == Array(0...8))
        #expect(TooltipConfiguration.Anchor.allCases.last == .cursor)
    }

    @Test func theShortcutTakesPartInEquality() {
        #expect(TooltipConfiguration("Go back", shortcut: .command("goBack:")) != TooltipConfiguration("Go back"))
    }

    @Test func aStandardTooltipIsPlainTextShownWithoutABindingAnchoredToTheViewsBounds() {
        let standard = TooltipConfiguration("Hide sidebar")
        #expect(standard.style == .standard && !standard.requiresShortcut && standard.anchorRect == nil)
    }

    @Test func styleAnchorRectAndTheBindingRequirementTakePartInEquality() {
        #expect(TooltipConfiguration("Tab", style: .label(subtitle: "Double-click to rename")) != TooltipConfiguration("Tab", style: .label(subtitle: nil)))
        #expect(TooltipConfiguration("Tab", anchorRect: .zero) != TooltipConfiguration("Tab"))
        #expect(TooltipConfiguration("Tab", requiresShortcut: true) != TooltipConfiguration("Tab"))
    }

    @Test func theTwoShadowsAreInOrder() {
        #expect(TooltipShadow.standard == [TooltipShadow(radius: 2.5, offset: .zero, opacity: 0.18),
                                           TooltipShadow(radius: 10, offset: CGSize(width: 0, height: 2.5), opacity: 0.15)])
    }

    @Test func theWindowOutsetIsTheLargestOffsetPlusThreeTimesTheLargestRadius() {
        #expect(TooltipShadow.windowMargin == 32.5)
    }

    @Test func fadesTakeTheirRecoveredDurations() {
        #expect(TooltipTiming.presentDuration == 0.05 && TooltipTiming.exitDuration == 0.3 && TooltipTiming.cursorExitDuration == 0.1)
        #expect(TooltipTiming.interruptionDuration == 0.1 && TooltipTiming.shortcutDismissalDelay == 0.25)
    }

    @Test func idleBackstopAndCursorWarmTimingTakeTheirRecoveredValues() {
        #expect(TooltipTiming.pointerStopDelay == 0.08 && TooltipTiming.hitTestInterval == 0.25)
        #expect(TooltipTiming.cursorWarmInterval == 0.6 && TooltipTiming.cursorWarmDelay == 0.01)
    }

    @Test func theNeutralPaletteTakesItsGreys() {
        let neutral = TooltipColorPalette.neutral
        #expect(Self.gray(neutral.title.light, 0) && Self.gray(neutral.title.dark, 1))
        #expect(Self.gray(neutral.background.light, 1) && Self.gray(neutral.background.dark, 0.17))
        #expect(Self.gray(neutral.keyForeground.light, 0.9) && Self.gray(neutral.keyForeground.dark, 0.28))
        #expect(Self.gray(neutral.keyBackground.light, 0.66) && Self.gray(neutral.keyBackground.dark, 0.45))
        #expect(Self.gray(neutral.keyTitle.light, 0) && Self.gray(neutral.keyTitle.dark, 1))
    }

    @Test func darkAquaResolvesTheDarkVariantAndAnythingElseTheLightOne() {
        let neutral = TooltipColorPalette.neutral
        #expect(neutral.background.resolved(dark: true) === neutral.background.dark)
        #expect(neutral.background.resolved(dark: false) === neutral.background.light)
    }

    private static let theme = SpaceTheme(primaryColor: ThemeColor.hsl(hue: 0.575, saturation: 1, lightness: 0.7, colorSpace: .displayP3), colorCount: 2)

    @Test func aThemedPalettesTitleAndBackgroundFollowTheSemanticPalettesLightDarkSplit() {
        let light = ThemeChromePalette(theme: Self.theme, isDark: false), dark = ThemeChromePalette(theme: Self.theme, isDark: true)
        let themed = TooltipColorPalette(theme: Self.theme)
        #expect(Self.same(themed.title.light, light.title) && Self.same(themed.title.dark, dark.title))
        #expect(Self.same(themed.background.light, light.background) && Self.same(themed.background.dark, dark.background))
    }

    enum Key: CaseIterable { case face, base, glyph }

    @Test(arguments: Key.allCases)
    func aThemedPalettesKeysTakeTheLightPalettesValueInBothAppearances(_ key: Key) {
        let light = ThemeChromePalette(theme: Self.theme, isDark: false), dark = ThemeChromePalette(theme: Self.theme, isDark: true)
        let themed = TooltipColorPalette(theme: Self.theme)
        let (color, role, darkRole) = switch key {
        case .face: (themed.keyForeground, light.hover, dark.hover)
        case .base: (themed.keyBackground, light.focus, dark.focus)
        case .glyph: (themed.keyTitle, light.maxContrastColor, dark.maxContrastColor)
        }
        #expect(Self.same(color.light, role) && Self.same(color.dark, role))
        #expect(!Self.same(color.dark, darkRole))
    }

    @Test func aWideGamutThemeKeepsItsExtendedSRGBComponents() {
        #expect(Self.components(TooltipColorPalette(theme: Self.theme).keyTitle.light)[0] < 0)
    }

    @Test func aColourlessOrInvalidThemeKeepsTheNeutralPalette() {
        #expect(TooltipColorPalette(theme: SpaceTheme()) == .neutral)
        #expect(TooltipColorPalette(theme: SpaceTheme(primaryColor: nil, colorCount: 2)) == .neutral)
    }

    @Test func commandSIsOneModifierKeycapThenTheUppercasedKey() {
        #expect(TooltipKeycap.keycaps(for: Self.commandS) == [TooltipKeycap(glyph: "⌘", trigger: .modifier(.command)),
                                                              TooltipKeycap(glyph: "S", trigger: .key("s"))])
    }

    @Test func modifiersShowInControlOptionShiftCommandOrder() {
        #expect(TooltipKeycap.keycaps(for: KeyboardShortcut(key: "k", flags: [.command, .shift, .option, .control])).map(\.glyph) == ["⌃", "⌥", "⇧", "⌘", "K"])
    }

    @Test func anUppercaseBindingShowsItsImpliedShift() {
        #expect(TooltipKeycap.keycaps(for: KeyboardShortcut(key: "K", flags: .command)).map(\.glyph) == ["⇧", "⌘", "K"])
    }

    @Test(arguments: [(" ", "⎵"), ("\t", "TAB"), ("\u{F704}", "F1"), ("\u{F70D}", "F10"), ("\u{F717}", "F20"),
                      ("s", "S"), ("1", "1"), ("[", "["), ("é", "É"),
                      ("\r", "↩"), ("\u{7f}", "⌫"), ("\u{1b}", "⎋"), ("\u{f700}", "↑"), ("\u{f728}", "⌦")])
    func eachKeyShowsItsGlyph(_ key: String, _ glyph: String) {
        #expect(TooltipKeycap.glyph(forKey: key) == glyph)
    }

    @Test func aModifierKeycapIsHeldWhileItsFlagIs() {
        let command = TooltipKeycap.keycaps(for: Self.commandS)[0]
        #expect(command.isPressed(modifiers: [.command, .shift], characters: nil))
        #expect(!command.isPressed(modifiers: .shift, characters: "s"))
    }

    @Test func theKeyKeycapIsHeldWhileItsCharacterIsCaseInsensitively() {
        let key = TooltipKeycap.keycaps(for: Self.commandS)[1]
        #expect(key.isPressed(modifiers: [], characters: "S") && key.isPressed(modifiers: .command, characters: "s"))
        #expect(!key.isPressed(modifiers: .command, characters: nil) && !key.isPressed(modifiers: [], characters: "d"))
    }

    @Test(arguments: [(TooltipConfiguration.Anchor.top, [CGFloat(14), 14, 14, 14]), (.bottom, [14, 14, 14, 14]), (.leading, [14, 14, 14, 14]),
                      (.trailing, [14, 14, 14, 14]), (.topLeading, [14, 14, 3, 14]), (.topTrailing, [14, 14, 14, 3]),
                      (.bottomLeading, [14, 3, 14, 14]), (.bottomTrailing, [3, 14, 14, 14]), (.cursor, [3, 14, 14, 14])])
    func eachAnchorTakesItsCornerRadii(_ anchor: TooltipConfiguration.Anchor, _ radii: [CGFloat]) {
        let c = TooltipCorners(anchor: anchor)
        #expect([c.topLeft, c.topRight, c.bottomRight, c.bottomLeft] == radii)
    }

    private static let pill = CGRect(x: 0, y: 0, width: 140, height: 28)

    @Test func theShapeFillsItsRect() {
        #expect(Self.near(TooltipCorners(anchor: .bottomTrailing).path(in: Self.pill).boundingBoxOfPath, Self.pill))
        #expect(Self.near(TooltipCorners(anchor: .top).path(in: Self.pill).boundingBoxOfPath, Self.pill))
    }

    @Test func theAnchorFacingTopLeftCornerIsThreePointsAndTheOthersFourteen() {
        let anchored = TooltipCorners(anchor: .bottomTrailing).path(in: Self.pill), uniform = TooltipCorners(anchor: .top).path(in: Self.pill)
        #expect(anchored.contains(CGPoint(x: 1.5, y: 1.5)) && !uniform.contains(CGPoint(x: 1.5, y: 1.5)))
        #expect(!anchored.contains(CGPoint(x: 1.5, y: 26.5)) && !anchored.contains(CGPoint(x: 138.5, y: 1.5)))
    }

    @Test func aTwentyEightPointPillIsACapsule() {
        let uniform = TooltipCorners(anchor: .top).path(in: Self.pill)
        #expect(uniform.contains(CGPoint(x: 0.5, y: 14)) && uniform.contains(CGPoint(x: 139.5, y: 14)))
    }

    @Test func radiiAreLimitedToHalfTheShorterSide() {
        let tall = TooltipCorners(anchor: .top).path(in: CGRect(x: 0, y: 0, width: 20, height: 10))
        #expect(tall.contains(CGPoint(x: 10, y: 0.5)) && !tall.contains(CGPoint(x: 0.6, y: 0.6)))
    }

    private static let anchorRect = CGRect(x: 100, y: 50, width: 32, height: 32), size = CGSize(width: 140, height: 28)
    private static let clamp = CGRect(x: 8, y: 8, width: 984, height: 584), mouse = CGPoint(x: 300, y: 200)

    @Test(arguments: [(TooltipConfiguration.Anchor.top, CGPoint(x: 46, y: 18)), (.bottom, CGPoint(x: 46, y: 86)), (.leading, CGPoint(x: -44, y: 52)),
                      (.trailing, CGPoint(x: 136, y: 52)), (.topLeading, CGPoint(x: -34, y: 28)), (.topTrailing, CGPoint(x: 126, y: 28)),
                      (.bottomLeading, CGPoint(x: -34, y: 76)), (.bottomTrailing, CGPoint(x: 126, y: 76)), (.cursor, CGPoint(x: 312, y: 212))])
    func eachAnchorPlacesItsOrigin(_ anchor: TooltipConfiguration.Anchor, _ origin: CGPoint) {
        #expect(TooltipPlacement.origin(for: anchor, size: Self.size, anchorRect: Self.anchorRect, clamp: Self.clamp, mouse: Self.mouse) == origin)
    }

    @Test func topAndBottomClampToTheRegionsEdges() {
        #expect(TooltipPlacement.origin(for: .top, size: Self.size, anchorRect: CGRect(x: 0, y: 50, width: 32, height: 32),
                                        clamp: Self.clamp, mouse: Self.mouse).x == 8)
        #expect(TooltipPlacement.origin(for: .bottom, size: Self.size, anchorRect: CGRect(x: 960, y: 50, width: 32, height: 32),
                                        clamp: Self.clamp, mouse: Self.mouse).x == 852)
    }

    @Test func diagonalAnchorsAreNotClamped() {
        #expect(TooltipPlacement.origin(for: .bottomTrailing, size: Self.size, anchorRect: CGRect(x: 960, y: 50, width: 32, height: 32),
                                        clamp: Self.clamp, mouse: Self.mouse).x == 986)
    }

    @Test func theClampRegionIsTheWindowsOnScreenPartInsetByEight() {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        #expect(TooltipPlacement.clampRegion(windowFrame: CGRect(x: 100, y: 100, width: 800, height: 600), screenFrame: screen)
                == CGRect(x: 8, y: 8, width: 784, height: 584))
        #expect(TooltipPlacement.clampRegion(windowFrame: CGRect(x: -100, y: 100, width: 800, height: 600), screenFrame: screen)
                == CGRect(x: 108, y: 8, width: 684, height: 584))
    }

    @Test func topLeftWindowSpaceConvertsToScreenSpace() {
        #expect(TooltipPlacement.screenRect(CGRect(x: 126, y: 76, width: 140, height: 28), windowFrame: CGRect(x: 100, y: 100, width: 800, height: 600))
                == CGRect(x: 226, y: 596, width: 140, height: 28))
    }

    private static let screens = [CGRect(x: 0, y: 0, width: 1440, height: 900), CGRect(x: 1440, y: 0, width: 1920, height: 1080)]

    @Test func theScreenHoldingMostOfTheAnchorIsChosen() {
        #expect(TooltipPlacement.screenIndex(containing: CGRect(x: 1500, y: 500, width: 32, height: 32), screens: Self.screens) == 1)
        #expect(TooltipPlacement.screenIndex(containing: CGRect(x: 1430, y: 500, width: 32, height: 32), screens: Self.screens) == 1)
    }

    @Test func anAnchorOffEveryScreenOrWithoutAreaHasNoScreen() {
        #expect(TooltipPlacement.screenIndex(containing: CGRect(x: 5000, y: 500, width: 32, height: 32), screens: Self.screens) == nil)
        #expect(TooltipPlacement.screenIndex(containing: CGRect(x: 100, y: 100, width: 0, height: 0), screens: Self.screens) == nil)
    }

    private static let window = CGRect(x: 0, y: 0, width: 1000, height: 600)

    @Test func thePreferredAnchorIsUsedWhenItFits() {
        #expect(TooltipPlacement.screenFrame(preferred: .bottomTrailing, size: Self.size, anchorRect: Self.anchorRect, mouse: .zero,
                                             windowFrame: Self.window, screenFrame: Self.window) == CGRect(x: 126, y: 496, width: 140, height: 28))
    }

    @Test func otherwiseTheFittingCandidateNearestThePreferredFrameIsUsed() {
        #expect(TooltipPlacement.screenFrame(preferred: .bottomTrailing, size: Self.size, anchorRect: CGRect(x: 960, y: 560, width: 32, height: 32),
                                             mouse: .zero, windowFrame: Self.window, screenFrame: Self.window)
                == CGRect(x: 852, y: 44, width: 140, height: 28))
    }

    @Test func noTooltipShowsWhenNothingFits() {
        #expect(TooltipPlacement.screenFrame(preferred: .bottomTrailing, size: CGSize(width: 2000, height: 28), anchorRect: Self.anchorRect,
                                             mouse: .zero, windowFrame: Self.window, screenFrame: Self.window) == nil)
    }

    private static func permits(buttons: Int = 0, flags: NSEvent.ModifierFlags = [], allowed: NSEvent.ModifierFlags = [], key: Bool = true) -> Bool {
        TooltipEligibility.permits(pressedMouseButtons: buttons, modifierFlags: flags, allowed: allowed, keyInParentChain: { key })
    }

    @Test func aTooltipIsEligibleWithNoButtonsOrModifiersInAKeyChain() { #expect(Self.permits()) }
    @Test func neverWhileAMouseButtonIsHeld() { #expect(!Self.permits(buttons: 1)) }
    @Test func aHeldModifierBlocksUnlessAllowed() { #expect(!Self.permits(flags: .command) && Self.permits(flags: .command, allowed: .command)) }
    @Test func everyHeldModifierMustBeAllowed() { #expect(!Self.permits(flags: [.command, .shift], allowed: .command)) }
    @Test func capsLockBlocks() { #expect(!Self.permits(flags: .capsLock)) }
    @Test func aKeyWindowUpTheParentChainIsRequired() { #expect(!Self.permits(key: false)) }
}
