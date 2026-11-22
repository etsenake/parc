import AppKit
import Testing
@testable import Parc
@testable import ParcCore

@MainActor private struct Hierarchy {
    let root = ThemeRendererView(frame: NSRect(x: 0, y: 0, width: 1240, height: 840))
    let card = NSView(frame: NSRect(x: 10, y: 10, width: 1220, height: 820))
    let page = StartPageView()

    init() {
        _ = NSApplication.shared
        root.addSubview(card)
        page.frame = card.bounds
        card.addSubview(page)
        page.coordinateSpace = root
        page.needsLayout = true
        page.layoutSubtreeIfNeeded()
    }

    func hit(_ point: CGPoint) -> NSView? { page.hitTest(card.convert(point, from: page)) }

    func showChrome() {
        page.showsWindowChrome = true
        page.layoutSubtreeIfNeeded()
    }
}

@MainActor struct StartPageViewTests {
    @Test func theTintedPaperFillsThePageBeneathEverything() {
        let h = Hierarchy()
        #expect(h.page.paper.frame == h.page.bounds && h.page.subviews.first === h.page.paper)
    }

    @Test func theViewPlacesTheMarkAndSlotFromTheLayout() {
        let h = Hierarchy()
        let layout = StartPageLayout(size: h.page.bounds.size, barRestHeight: 64, chromeOrigin: nil, showsWindowButtons: true)
        #expect(h.page.mark.frame == layout.mark && h.page.commandBarSlot.frame == layout.commandBarSlot)
        #expect(h.page.mark.superview === h.page && h.page.commandBarSlot.superview === h.page)
    }

    @Test func theChromeAnchorsToTheFloatingSidebarsCornerInTheWindowsSpace() {
        #expect(Hierarchy().page.chromeOrigin == CGPoint(x: -5, y: -5))
    }

    @Test func theOwnersRestingHeightRecentresThePair() {
        let h = Hierarchy()
        h.page.barRestHeight = 52
        h.page.layoutSubtreeIfNeeded()
        #expect(h.page.commandBarSlot.frame == StartPageLayout(size: h.page.bounds.size, barRestHeight: 52, chromeOrigin: nil,
                                                               showsWindowButtons: true).commandBarSlot)
    }

    @Test func resizingRelaysOutTheSlotAndPaper() {
        let h = Hierarchy()
        h.page.frame.size = NSSize(width: 700, height: 500)
        h.page.layoutSubtreeIfNeeded()
        #expect(h.page.commandBarSlot.frame.width == 620 && h.page.paper.frame == h.page.bounds)
    }

    @Test func aDockedSidebarKeepsThePagesChromeHidden() {
        let h = Hierarchy()
        #expect(h.page.windowButtons.isHidden && h.page.sidebarButton.isHidden)
    }

    @Test func aHiddenSidebarShowsTheWindowButtonsAndTheSidebarButton() {
        let h = Hierarchy()
        h.showChrome()
        #expect(!h.page.windowButtons.isHidden && !h.page.sidebarButton.isHidden)
    }

    @Test func thePagesChromeLinesUpWithTheFloatingSidebars() {
        let h = Hierarchy()
        h.showChrome()
        let floating = SidebarPresentationFrame.floating.rect(width: 260, in: h.root.bounds)
        let header = SidebarChromeLayout.toolbar(width: 260, windowButtons: WindowStandardButtons.stackSize, showsNavigation: false)
        #expect(h.page.convert(h.page.windowButtons.frame, to: h.root) == header.windowButtons?.offsetBy(dx: floating.minX, dy: floating.minY))
        #expect(h.page.convert(h.page.sidebarButton.frame, to: h.root) == header.toggle?.offsetBy(dx: floating.minX, dy: floating.minY))
    }

    @Test func theSidebarButtonIsStyledLikeTheSidebarsToggle() {
        let h = Hierarchy()
        let button = h.page.sidebarButton
        #expect(button.translucentFace != nil && button.imagePosition == .imageOnly && button.focusRingCornerRadius == 5)
    }

    @Test func theSidebarButtonAsksTheWindowToShowTheSidebar() {
        let h = Hierarchy()
        var toggles = 0
        h.page.onToggleSidebar = { toggles += 1 }
        h.page.sidebarButton.sendAction(h.page.sidebarButton.action, to: h.page.sidebarButton.target)
        #expect(toggles == 1)
    }

    @Test func withTheSystemsOwnButtonsOnlyTheSidebarButtonRemainsInTheLeadingSlot() {
        let h = Hierarchy()
        h.showChrome()
        h.page.showsWindowButtons = false
        h.page.layoutSubtreeIfNeeded()
        #expect(h.page.windowButtons.isHidden && !h.page.sidebarButton.isHidden)
        #expect(h.page.sidebarButton.frame.minX == SidebarChromeLayout.navigationLeading + h.page.chromeOrigin.x)
    }

    @Test func dockingTheSidebarHidesThePagesChromeAgain() {
        let h = Hierarchy()
        h.showChrome()
        h.page.showsWindowChrome = false
        h.page.layoutSubtreeIfNeeded()
        #expect(h.page.windowButtons.isHidden && h.page.sidebarButton.isHidden)
    }

    @Test func withoutACoordinateSpaceTheChromeMeasuresFromThePageCorner() {
        _ = NSApplication.shared
        let loose = StartPageView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        loose.showsWindowChrome = true
        loose.layoutSubtreeIfNeeded()
        #expect(loose.chromeOrigin == .zero && loose.sidebarButton.frame.minY == SidebarChromeLayout.headerTop + 4)
    }
}

@MainActor struct StartPageHitTestingTests {
    private func slotWithBarCard(_ h: Hierarchy) -> NSView {
        let bar = NSView(frame: NSRect(x: 0, y: 0, width: h.page.commandBarSlot.frame.width, height: 64))
        h.page.commandBarSlot.addSubview(bar)
        return bar
    }

    @Test func theBarCardInsideTheSlotTakesItsClicks() {
        let h = Hierarchy()
        let bar = slotWithBarCard(h)
        let slot = h.page.commandBarSlot.frame
        #expect(h.hit(CGPoint(x: slot.midX, y: slot.minY + 32)) === bar)
    }

    @Test func theSlotBelowTheBarCardFallsThroughToThePageBackground() {
        let h = Hierarchy()
        _ = slotWithBarCard(h)
        let slot = h.page.commandBarSlot.frame
        #expect(h.hit(CGPoint(x: slot.midX, y: slot.minY + 200)) === h.page)
    }

    @Test func theSlotItselfNeverSwallowsAClick() {
        let h = Hierarchy()
        let slot = h.page.commandBarSlot.frame
        let point = h.page.convert(CGPoint(x: slot.midX, y: slot.minY + 200), to: h.page.commandBarSlot.superview)
        #expect(h.page.commandBarSlot.hitTest(point) == nil)
    }

    @Test func theBackgroundRoutesClicksToThePageSoItCanDragTheWindow() {
        let h = Hierarchy()
        #expect(h.hit(CGPoint(x: 20, y: 400)) === h.page)
    }

    @Test func theMarkGetsItsOwnClicks() {
        let h = Hierarchy()
        #expect(h.hit(CGPoint(x: h.page.mark.frame.midX, y: h.page.mark.frame.midY)) === h.page.mark)
    }

    @Test func hiddenChromeTakesNoClicks() {
        let h = Hierarchy()
        let toggle = h.page.sidebarButton.frame
        #expect(h.hit(CGPoint(x: toggle.midX, y: toggle.midY)) === h.page)
    }

    @Test func theShownSidebarButtonTakesItsClick() {
        let h = Hierarchy()
        h.showChrome()
        let shown = h.page.sidebarButton.frame
        #expect(h.hit(CGPoint(x: shown.midX, y: shown.midY)) === h.page.sidebarButton)
    }

    @Test func aStartPageFadingOutLetsEveryClickReachTheNewPage() {
        let h = Hierarchy()
        let bar = slotWithBarCard(h)
        h.showChrome()
        let slot = h.page.commandBarSlot.frame, shown = h.page.sidebarButton.frame
        h.page.isDeparting = true
        #expect(h.hit(CGPoint(x: 20, y: 400)) == nil)
        #expect(h.hit(CGPoint(x: slot.midX, y: slot.minY + 32)) == nil)
        #expect(h.hit(CGPoint(x: shown.midX, y: shown.midY)) == nil)
        _ = bar
    }
}

@MainActor struct StartPageAccessibilityTests {
    @Test func thePageIsOneLabelledGroup() {
        let page = Hierarchy().page
        #expect(page.isAccessibilityElement() && page.accessibilityRole() == .group && page.accessibilityLabel() == "Start page")
    }

    @Test func theSidebarButtonSaysWhatItDoes() {
        let button = Hierarchy().page.sidebarButton
        #expect(button.accessibilityLabel() == "Show sidebar" && button.cell?.accessibilityLabel() == "Show sidebar")
    }

    @Test func thePaperAndSlotAddNoElements() {
        let page = Hierarchy().page
        #expect(!page.paper.isAccessibilityElement() && !page.commandBarSlot.isAccessibilityElement())
    }

    @Test func voiceOverMeetsTheWindowControlsThenTheSidebarButtonThenTheBar() {
        let h = Hierarchy()
        let window = NSWindow(contentRect: h.root.frame, styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        window.contentView = h.root
        h.page.commandBarSlot.addSubview(NSButton(title: "Bar", target: nil, action: nil))
        h.showChrome()
        let children = (h.page.accessibilityChildren() ?? []).compactMap { ($0 as? NSView) ?? ($0 as? NSCell)?.controlView }
        #expect(h.page.windowButtons.buttons.count == 3)
        let order = children.map { child in
            child.isDescendant(of: h.page.windowButtons) ? 0 : child === h.page.sidebarButton ? 1 : child.isDescendant(of: h.page.commandBarSlot) ? 2 : 3
        }
        #expect(order == [0, 0, 0, 1, 2], "order \(order)")
        window.contentView = nil
    }
}

private let violet = SpaceTheme.singleColor(ThemeColor(red: 0.42, green: 0.36, blue: 0.86)!)
private let amber = SpaceTheme.singleColor(ThemeColor(red: 0.9, green: 0.55, blue: 0.2)!)
private let multiColor = SpaceTheme(primaryColor: ThemeColor(red: 0.48, green: 0.87, blue: 0.38)!, colorCount: 3, wheel: .complimentary)

struct StartPagePaperStyleTests {
    typealias Style = StartPagePaperStyle

    @Test(arguments: [false, true])
    func aColourlessThemeIsPlainSolidPaper(dark: Bool) {
        let style = Style(theme: SpaceTheme(), dark: dark)
        #expect(style.glows.isEmpty && style.base == (dark ? Style.colorlessDark : Style.colorlessLight))
    }

    @Test func everyThemeColourGlowsFromItsCorner() {
        let light = Style(theme: multiColor, dark: false)
        #expect(light.glows.count == 3 && light.glows.map(\.anchor) == Style.anchors)
    }

    @Test func theGlowsAreTheThemesOwnColours() {
        let colors = multiColor.colors.map { ThemeRenderMath.srgb($0) }.map { SIMD3(Double($0.x), Double($0.y), Double($0.z)) }
        #expect(Style(theme: multiColor, dark: false).glows.map(\.color) == colors)
    }

    @Test func lightPaperIsTheThemesAverageTintMostlyWhite() {
        let colors = multiColor.colors.map { ThemeRenderMath.srgb($0) }.map { SIMD3(Double($0.x), Double($0.y), Double($0.z)) }
        let average = colors.reduce(SIMD3<Double>(repeating: 0), +) / 3
        #expect(Style(theme: multiColor, dark: false).base == Style.mix(average, SIMD3(repeating: 1), Style.lightTint))
    }

    @Test func darkPaperIsTheThemesAverageTintMostlyNearBlack() {
        let colors = multiColor.colors.map { ThemeRenderMath.srgb($0) }.map { SIMD3(Double($0.x), Double($0.y), Double($0.z)) }
        let average = colors.reduce(SIMD3<Double>(repeating: 0), +) / 3
        #expect(Style(theme: multiColor, dark: true).base == Style.mix(average, Style.darkBase, Style.darkTint))
    }

    @Test func glowsAndGrainAreSofterInTheDark() {
        let light = Style(theme: multiColor, dark: false), dark = Style(theme: multiColor, dark: true)
        #expect(light.glowStrength == 0.55 && dark.glowStrength == 0.42 && light.grain > dark.grain)
    }

    @Test func aSingleColourGlowsFromTheTopLeftCorner() {
        let single = Style(theme: violet, dark: false)
        #expect(single.glows.count == 1 && single.glows.first?.anchor == Style.anchors[0])
    }

    @Test func aGlowFadesFromItsCentreToNothing() {
        #expect(Style.glowAlpha(at: 0, strength: 0.5) == 0.5 && Style.glowAlpha(at: 1, strength: 0.5) == 0)
        #expect(Style.glowAlpha(at: 0.3, strength: 0.5) > Style.glowAlpha(at: 0.6, strength: 0.5))
    }

    @Test func aGlowIsCentredOnItsAnchorWithA62PercentRadius() {
        let frame = Style.glowFrame(CGPoint(x: 1, y: 0.25), in: CGSize(width: 1000, height: 600))
        #expect(frame.midX == 1000 && frame.midY == 150 && frame.width == 1240 && frame.height == 1240)
    }
}

@MainActor struct StartPagePaperViewTests {
    @Test func thePaperTakesNoClicksAndAddsNoElement() {
        let paper = Hierarchy().page.paper
        #expect(paper.hitTest(CGPoint(x: 10, y: 10)) == nil && !paper.isAccessibilityElement())
    }

    @Test(arguments: [(NSAppearance.Name.aqua, false), (NSAppearance.Name.darkAqua, true)])
    func thePaperFollowsTheAppearanceItLivesIn(name: NSAppearance.Name, dark: Bool) {
        let page = Hierarchy().page
        page.theme = multiColor
        page.appearance = NSAppearance(named: name)
        page.viewDidChangeEffectiveAppearance()
        page.paper.viewDidChangeEffectiveAppearance()
        page.paper.updateLayer()
        #expect(page.paper.style.dark == dark)
        let base = page.paper.style.base
        let drawn = page.paper.layer?.backgroundColor.flatMap(NSColor.init(cgColor:))?.usingColorSpace(.sRGB)
        #expect(drawn.map { abs($0.redComponent - base.x) < 0.002 && abs($0.greenComponent - base.y) < 0.002 } == true)
    }

    @Test func threeRadialGlowsSitOnTheTint() {
        let page = Hierarchy().page
        page.theme = multiColor
        page.appearance = NSAppearance(named: .aqua)
        page.viewDidChangeEffectiveAppearance()
        page.paper.viewDidChangeEffectiveAppearance()
        page.paper.updateLayer()
        let glows = page.paper.layer?.sublayers?.first?.sublayers ?? []
        #expect(glows.count == 3 && glows.allSatisfy { ($0 as? CAGradientLayer)?.type == .radial })
    }

    @Test func aSpaceSwipePreparesTheIncomingSpacesPaper() {
        let page = Hierarchy().page
        page.theme = multiColor
        page.paper.updateLayer()
        page.pagingTransition = ThemePagingTransition(from: violet, theme: amber, progress: 0.25)
        #expect(page.paper.incomingStyle != nil)
    }

    @Test func theSwipeCrossFadesTheTwoSpacesGlows() {
        let page = Hierarchy().page
        page.theme = multiColor
        page.paper.updateLayer()
        page.pagingTransition = ThemePagingTransition(from: violet, theme: amber, progress: 0.25)
        let layers = page.paper.layer?.sublayers ?? []
        #expect(layers.count >= 2 && abs(layers[0].opacity - 0.75) < 0.001 && abs(layers[1].opacity - 0.25) < 0.001)
    }

    @Test func theSwipesEndLeavesOneSpacesPaper() {
        let page = Hierarchy().page
        page.theme = multiColor
        page.paper.updateLayer()
        page.pagingTransition = ThemePagingTransition(from: violet, theme: amber, progress: 0.25)
        let layers = page.paper.layer?.sublayers ?? []
        page.pagingTransition = nil
        #expect(page.paper.incomingStyle == nil && layers[1].opacity == 0)
    }

    @Test func aPrivateWindowsPaperUsesThePrivatePalette() {
        let page = Hierarchy().page
        page.incognito = true
        #expect(page.paper.effectiveTheme == IncognitoWindowTheme.paletteTheme)
    }

    private func textured(_ base: SpaceTheme, _ texture: SpaceTheme.Texture) -> SpaceTheme {
        var theme = base
        theme.noise = 1
        theme.texture = texture
        theme.intensity = 1
        theme.appearance = .automatic
        return theme
    }

    @Test func theMarkSharesTheWindowsCoordinateSpace() {
        let h = Hierarchy()
        #expect(h.page.mark.coordinateSpace === h.root)
    }

    @Test func theThemeReachesThePaperAndTheMark() {
        let page = Hierarchy().page
        let theme = textured(violet, .tweed)
        page.theme = theme
        #expect(page.paper.theme == theme && page.mark.theme == theme)
    }

    @Test func aSpaceSwipeReachesThePaperAndTheMark() {
        let page = Hierarchy().page
        let swipe = ThemePagingTransition(from: violet, theme: amber, progress: 0.3)
        page.pagingTransition = swipe
        #expect(page.paper.pagingTransition == swipe && page.mark.pagingTransition == swipe)
    }

    @Test func aPrivateWindowReachesThePaperAndTheMark() {
        let page = Hierarchy().page
        page.incognito = true
        #expect(page.paper.incognito && page.mark.incognito)
    }

    @Test func theBarAndChromeFollowThePagesOwnAppearance() {
        let page = Hierarchy().page
        page.theme = violet
        page.appearance = NSAppearance(named: .darkAqua)
        page.viewDidChangeEffectiveAppearance()
        #expect(page.commandBarSlot.appearance == nil && page.windowButtons.appearance == nil && page.sidebarButton.appearance == nil)
    }

    @Test(arguments: [(NSAppearance.Name.darkAqua, true), (NSAppearance.Name.aqua, false)])
    func theToggleTakesTheTitleColourOfTheCurrentAppearance(name: NSAppearance.Name, dark: Bool) {
        let page = Hierarchy().page
        page.theme = violet
        page.appearance = NSAppearance(named: name)
        page.viewDidChangeEffectiveAppearance()
        #expect(page.sidebarButton.contentTintColor == ThemeChromePalette(theme: violet, isDark: dark).title)
    }
}
