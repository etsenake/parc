import AppKit
import MetalKit
import Testing
@testable import Parc
@testable import ParcCore

@MainActor
struct FloatingSidebarSwipeTests {
    struct Material: Equatable {
        var kind: NSVisualEffectView.Material, withinWindow: Bool, alpha: CGFloat, hidden: Bool, side: NSAppearance.Name?
    }

    @MainActor final class Swipe {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 300), styleMask: [.borderless], backing: .buffered, defer: true)
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 300))
        let surface = ThemeRendererView(frame: NSRect(x: 5, y: 5, width: 200, height: 290))
        let light: SpaceTheme, alsoLight: SpaceTheme, dark: SpaceTheme, uncoloured: SpaceTheme
        let automatic = SpaceTheme.singleColor(ThemeColor(red: 0.42, green: 0.36, blue: 0.86)!)

        init() {
            window.isReleasedWhenClosed = false
            window.appearance = NSAppearance(named: .aqua)
            root.wantsLayer = true
            window.contentView = root
            root.addSubview(surface)
            var light = SpaceTheme.singleColor(ThemeColor(red: 0.8, green: 0.88, blue: 0.97)!); light.appearance = .light
            var alsoLight = SpaceTheme.singleColor(ThemeColor(red: 0.95, green: 0.8, blue: 0.6)!); alsoLight.appearance = .light
            var dark = SpaceTheme.singleColor(ThemeColor(red: 0.36, green: 0.22, blue: 0.62)!); dark.appearance = .dark
            var uncoloured = SpaceTheme(); uncoloured.appearance = .dark
            (self.light, self.alsoLight, self.dark, self.uncoloured) = (light, alsoLight, dark, uncoloured)
            surface.floatingCornerRadius = FloatingSidebarSurface.cornerRadius
        }

        deinit { MainActor.assumeIsolated { window.contentView = nil } }

        var rendersColour: Bool { surface.subviews.contains { $0 is MTKView } }
        var blurs: [NSVisualEffectView] { surface.subviews.compactMap { $0 as? NSVisualEffectView } }
        static func side(_ appearance: NSAppearance) -> NSAppearance.Name? { appearance.bestMatch(from: [.aqua, .darkAqua]) }
        var materials: [Material] {
            blurs.map {
                Material(kind: $0.material, withinWindow: $0.blendingMode == .withinWindow, alpha: $0.alphaValue,
                         hidden: $0.isHidden, side: Self.side($0.effectiveAppearance))
            }
        }
        var shown: [Material] { materials.filter { !$0.hidden } }
        func across(_ from: SpaceTheme, _ to: SpaceTheme, _ progress: CGFloat) {
            surface.pagingTransition = ThemePagingTransition(from: from, theme: to, progress: progress)
        }
        func crossfaded() -> (base: NSVisualEffectView, crossfade: NSVisualEffectView) {
            surface.theme = light
            across(light, dark, 0.3)
            return (blurs[0], blurs[1])
        }
    }

    @Test func removingTextureFromBothSpacesRemovesTheOverlayThroughoutTheSwipe() throws {
        let canvas = try #require(FloatingSidebarSwipeCommitTests.Canvas(floating: true))
        var from = SpaceTheme.singleColor(try #require(ThemeColor(red: 0.8, green: 0.2, blue: 0.3)))
        var to = SpaceTheme.singleColor(try #require(ThemeColor(red: 0.2, green: 0.3, blue: 0.8)))
        from.noise = 1
        to.noise = 1
        to.texture = .tweed
        let textured = canvas.render(from, ThemePagingTransition(from: from, theme: to, progress: 0.5))
        from.noise = 0
        to.noise = 0
        let plain = canvas.render(from, ThemePagingTransition(from: from, theme: to, progress: 0.5))
        try #require(!plain.isEmpty && plain.count == textured.count)
        #expect(plain != textured)
    }

    private static func blur(_ alpha: CGFloat, _ side: NSAppearance.Name) -> Material {
        Material(kind: .popover, withinWindow: true, alpha: alpha, hidden: false, side: side)
    }

    @Test func anUncolouredDarkStyleSpacesBlurStaysDarkInAnAquaWindow() {
        let swipe = Swipe()
        swipe.surface.theme = swipe.uncoloured
        #expect(swipe.materials.map(\.side) == [.darkAqua])
    }

    @Test func aColouredSpaceForcedDarkKeepsADarkBlurInAnAquaWindow() throws {
        let swipe = Swipe()
        try #require(swipe.rendersColour)
        swipe.surface.theme = swipe.dark
        #expect(swipe.materials == [Self.blur(1, .darkAqua)])
    }

    @Test func aSpaceForcedDarkGivesItsTextDarkAquaToMatchItsBlur() throws {
        let swipe = Swipe()
        try #require(swipe.rendersColour)
        swipe.surface.theme = swipe.dark
        #expect(swipe.surface.palette.contentAppearance.flatMap(Swipe.side) == .darkAqua)
    }

    @Test func aSpaceForcedLightHasOneFloatingBlurOnTheLightSide() throws {
        let swipe = Swipe()
        try #require(swipe.rendersColour)
        swipe.surface.theme = swipe.light
        #expect(swipe.materials == [Self.blur(1, .aqua)])
    }

    @Test func aSwipeBetweenTwoLightSideSpacesAddsNoSecondBlur() throws {
        let swipe = Swipe()
        try #require(swipe.rendersColour)
        swipe.surface.theme = swipe.light
        swipe.across(swipe.light, swipe.alsoLight, 0.5)
        #expect(swipe.shown == [Self.blur(1, .aqua)])
    }

    @Test func aLightToDarkSwipeLaysTheCrossfadeJustAboveTheBlurAndUnderTheTheme() throws {
        let swipe = Swipe()
        try #require(swipe.rendersColour)
        let (base, crossfade) = swipe.crossfaded()
        let subviews = swipe.surface.subviews
        #expect(swipe.blurs.count == 2)
        #expect(subviews.firstIndex(of: crossfade) == subviews.firstIndex(of: base).map { $0 + 1 })
        #expect(try #require(subviews.firstIndex { $0 is MTKView }) > subviews.firstIndex(of: crossfade)!)
    }

    @Test func theCrossfadeIsTheFloatingBlursTwin() throws {
        let swipe = Swipe()
        try #require(swipe.rendersColour)
        let crossfade = swipe.crossfaded().crossfade
        #expect(crossfade.state == .followsWindowActiveState)
        #expect(crossfade.isEmphasized)
        #expect(crossfade.maskImage.map { $0.size == NSSize(width: 17, height: 17) && $0.capInsets.left == 8 } == true)
    }

    @Test func theCrossfadePassesClicksThrough() throws {
        let swipe = Swipe()
        try #require(swipe.rendersColour)
        #expect(swipe.crossfaded().crossfade.hitTest(NSPoint(x: 50, y: 50)) == nil)
    }

    @Test func theCrossfadeFollowsTheSurfacesSize() throws {
        let swipe = Swipe()
        try #require(swipe.rendersColour)
        let (base, crossfade) = swipe.crossfaded()
        swipe.surface.setFrameSize(NSSize(width: 180, height: 270))
        swipe.surface.layout()
        #expect(crossfade.frame == swipe.surface.bounds && base.frame == swipe.surface.bounds)
    }

    @Test(arguments: [CGFloat(0), 0.3, 0.6, 0.9, 0.95, 1])
    func aLightToDarkSwipeBlendsTheLeftPagesBlurUnderTheRightPagesUnchangedByTheCommit(_ progress: CGFloat) throws {
        let swipe = Swipe()
        try #require(swipe.rendersColour)
        _ = swipe.crossfaded()
        let blend = FloatingSidebarSurface.pagingBlend(progress: progress)
        let expected = [Self.blur(blend.base, .aqua), Self.blur(blend.incoming, .darkAqua)]
        swipe.surface.theme = swipe.light
        swipe.across(swipe.light, swipe.dark, progress)
        let before = swipe.materials
        swipe.surface.theme = swipe.dark
        #expect(before == expected)
        #expect(swipe.materials == expected)
    }

    @Test func atRestOnlyTheArrivedSpacesBlurShows() throws {
        let swipe = Swipe()
        try #require(swipe.rendersColour)
        let crossfade = swipe.crossfaded().crossfade
        swipe.surface.theme = swipe.dark
        swipe.surface.pagingTransition = nil
        #expect(swipe.shown == [Self.blur(1, .darkAqua)])
        #expect(crossfade.isHidden)
    }

    @Test func aDarkToLightSwipeUsesTheDarkPagesBlurAsTheBase() throws {
        let swipe = Swipe()
        try #require(swipe.rendersColour)
        _ = swipe.crossfaded()
        swipe.surface.theme = swipe.dark
        swipe.across(swipe.dark, swipe.light, 0.3)
        #expect(swipe.materials == [Self.blur(1, .darkAqua), Self.blur(FloatingSidebarSurface.pagingBlend(progress: 0.3).incoming, .aqua)])
    }

    @Test func draggingPastAPageBoundaryHandsOverToTheSameBlur() throws {
        let swipe = Swipe()
        try #require(swipe.rendersColour)
        _ = swipe.crossfaded()
        func visible() -> [Material] {
            swipe.materials.filter { !$0.hidden && $0.alpha > 0 }.map { var material = $0; material.alpha = 1; return material }.suffix(1)
        }
        swipe.across(swipe.light, swipe.dark, 1)
        let leaving = visible()
        swipe.across(swipe.dark, swipe.alsoLight, 0)
        #expect(leaving == visible())
        #expect(leaving == [Self.blur(1, .darkAqua)])
    }

    @Test func aForcedUncolouredToColouredSwipeBlendsTheTwoBlurs() throws {
        let swipe = Swipe()
        try #require(swipe.rendersColour)
        _ = swipe.crossfaded()
        swipe.across(swipe.uncoloured, swipe.light, 0.5)
        #expect(swipe.shown.map(\.side) == [.darkAqua, .aqua])
    }

    @Test func pastNinetyPercentIntoASameSideSpaceTheBlurIsWholeAgain() throws {
        let swipe = Swipe()
        try #require(swipe.rendersColour)
        _ = swipe.crossfaded()
        swipe.across(swipe.light, swipe.alsoLight, 0.95)
        #expect(swipe.shown == [Self.blur(1, .aqua)])
    }

    private func late(_ swipe: Swipe) -> [Material] {
        let late = FloatingSidebarSurface.pagingBlend(progress: 0.95)
        return [Self.blur(late.base, .darkAqua), Self.blur(late.incoming, .aqua)]
    }

    @Test func lateInTheSwipeTheBaseFadesBeneathTheCrossfade() throws {
        let swipe = Swipe()
        try #require(swipe.rendersColour)
        _ = swipe.crossfaded()
        swipe.across(swipe.uncoloured, swipe.light, 0.95)
        #expect(swipe.materials == late(swipe))
    }

    enum Without: CaseIterable { case material, background, incognito, locked }

    @Test(arguments: Without.allCases)
    func aSurfaceThatCannotShowItDrawsNoCrossfadeAndResetsTheBlur(_ without: Without) throws {
        let swipe = Swipe()
        try #require(swipe.rendersColour)
        let (base, crossfade) = swipe.crossfaded()
        swipe.across(swipe.uncoloured, swipe.light, 0.95)
        switch without {
        case .material: swipe.surface.drawsMaterial = false
        case .background: swipe.surface.drawsBackground = false
        case .incognito: swipe.surface.incognito = true
        case .locked: swipe.surface.floatingCornerRadius = nil
        }
        #expect(crossfade.isHidden && base.alphaValue == 1)
        if without == .locked { #expect(swipe.materials.first?.withinWindow == false) }
    }

    @Test func restoringThePrivateSurfaceRestoresItsBlend() throws {
        let swipe = Swipe()
        try #require(swipe.rendersColour)
        _ = swipe.crossfaded()
        swipe.across(swipe.uncoloured, swipe.light, 0.95)
        swipe.surface.incognito = true
        swipe.surface.incognito = false
        #expect(swipe.materials == late(swipe))
    }

    @Test func floatingAgainRestoresTheCrossfadeWithTheCurrentMask() throws {
        let swipe = Swipe()
        try #require(swipe.rendersColour)
        let crossfade = swipe.crossfaded().crossfade
        swipe.across(swipe.uncoloured, swipe.light, 0.95)
        swipe.surface.floatingCornerRadius = nil
        swipe.surface.floatingCornerRadius = 12
        #expect(!crossfade.isHidden)
        #expect(crossfade.maskImage.map { $0.size == NSSize(width: 25, height: 25) && $0.capInsets.left == 12 } == true)
        swipe.surface.floatingCornerRadius = FloatingSidebarSurface.cornerRadius
        #expect(crossfade.maskImage.map { $0.size == NSSize(width: 17, height: 17) } == true)
    }

    @Test func aForcedDarkSpacesBlurInADarkAquaWindow() throws {
        let swipe = Swipe()
        try #require(swipe.rendersColour)
        swipe.surface.theme = swipe.dark
        swipe.window.appearance = NSAppearance(named: .darkAqua)
        #expect(swipe.shown == [Self.blur(1, .darkAqua)])
    }

    @Test func aLockedSurfaceKeepsItsLightThemesSideInADarkAquaWindow() throws {
        let swipe = Swipe()
        try #require(swipe.rendersColour)
        swipe.window.appearance = NSAppearance(named: .darkAqua)
        swipe.surface.floatingCornerRadius = nil
        swipe.surface.theme = swipe.light
        #expect(swipe.shown.map(\.side) == [.aqua])
        #expect(swipe.shown.first?.kind.rawValue == 1)
    }

    @Test func aFloatingForcedLightSpaceKeepsALightBlurInADarkAquaWindow() throws {
        let swipe = Swipe()
        try #require(swipe.rendersColour)
        swipe.window.appearance = NSAppearance(named: .darkAqua)
        swipe.surface.theme = swipe.light
        #expect(swipe.shown == [Self.blur(1, .aqua)])
    }

    @Test func anAutomaticColouredSpacesBlurFollowsADarkAquaWindow() throws {
        let swipe = Swipe()
        try #require(swipe.rendersColour)
        swipe.window.appearance = NSAppearance(named: .darkAqua)
        swipe.surface.theme = swipe.automatic
        #expect(swipe.shown.map(\.side) == [.darkAqua])
    }

    @Test func theFloatingBlurTakesTheAppearanceTheWindowInherits() throws {
        let swipe = Swipe()
        try #require(swipe.rendersColour)
        swipe.surface.theme = swipe.automatic
        swipe.window.appearance = nil
        let inherited = try #require(Swipe.side(swipe.window.effectiveAppearance))
        #expect(swipe.shown.map(\.side) == [inherited])
    }

    @Test(arguments: [NSAppearance.Name.darkAqua, .aqua])
    func theFloatingBlurFollowsTheWindowsAppearanceAsItChanges(_ name: NSAppearance.Name) throws {
        let swipe = Swipe()
        try #require(swipe.rendersColour)
        swipe.surface.theme = swipe.automatic
        swipe.window.appearance = NSAppearance(named: name == .aqua ? .darkAqua : .aqua)
        swipe.window.appearance = NSAppearance(named: name)
        #expect(swipe.shown.map(\.side) == [name])
    }

    enum Moment: CaseIterable { case resting, beforeCommit, afterCommit, arrived }

    @Test(arguments: Moment.allCases)
    func aColouredToUncolouredAutomaticSwipeKeepsTheWindowsAppearanceAndOneBlur(_ moment: Moment) throws {
        let swipe = Swipe()
        try #require(swipe.rendersColour)
        let away = ThemePagingTransition(from: swipe.automatic, theme: SpaceTheme(), progress: 0.6)
        switch moment {
        case .resting: swipe.surface.theme = swipe.automatic
        case .beforeCommit: swipe.surface.theme = swipe.automatic; swipe.surface.pagingTransition = away
        case .afterCommit: swipe.surface.theme = SpaceTheme(); swipe.surface.pagingTransition = away
        case .arrived: swipe.surface.theme = SpaceTheme()
        }
        #expect(swipe.blurs.filter { !$0.isHidden }.map(\.effectiveAppearance.name) == [swipe.window.effectiveAppearance.name])
    }

    @Test func automaticToForcedDarkInAnAquaWindowBlendsTheTwoBlurs() throws {
        let swipe = Swipe()
        try #require(swipe.rendersColour)
        swipe.surface.theme = swipe.automatic
        swipe.across(swipe.automatic, swipe.dark, 0.5)
        #expect(swipe.shown.map(\.side) == [.aqua, .darkAqua])
    }

    @Test func turningTheWindowDarkAquaMidSwipeLeavesOneDarkBlur() throws {
        let swipe = Swipe()
        try #require(swipe.rendersColour)
        swipe.surface.theme = swipe.automatic
        swipe.across(swipe.automatic, swipe.dark, 0.5)
        swipe.window.appearance = NSAppearance(named: .darkAqua)
        #expect(swipe.shown == [Self.blur(1, .darkAqua)])
    }

    @Test func turningTheWindowBackToAquaMidSwipeBlendsThemAgain() throws {
        let swipe = Swipe()
        try #require(swipe.rendersColour)
        swipe.surface.theme = swipe.automatic
        swipe.across(swipe.automatic, swipe.dark, 0.5)
        swipe.window.appearance = NSAppearance(named: .darkAqua)
        swipe.window.appearance = NSAppearance(named: .aqua)
        #expect(swipe.shown.map(\.side) == [.aqua, .darkAqua])
    }
}
