import AppKit
import MetalKit
import Testing
import ParcCore
@testable import Parc

@MainActor
private final class ActivityWindow: NSWindow {
    var reportsKey = false
    var reportsMain = false
    override var isKeyWindow: Bool { reportsKey }
    override var isMainWindow: Bool { reportsMain }

    convenience init(size: NSSize = NSSize(width: 800, height: 600), appearance: NSAppearance.Name = .aqua) {
        _ = NSApplication.shared
        self.init(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: true)
        isReleasedWhenClosed = false
        self.appearance = NSAppearance(named: appearance)
    }
}

@MainActor
private final class PendingCanvas: ThemeMetalCanvas {
    private var pending = false
    override var needsDisplay: Bool {
        get { pending }
        set { pending = newValue }
    }
}

@MainActor
private final class Surface {
    let window: ActivityWindow
    let root: ThemeRendererView
    nonisolated static let darkTheme = SpaceTheme.singleColor(ThemeColor(red: 0.04, green: 0.03, blue: 0.08)!)
    nonisolated static let lightTheme = SpaceTheme.singleColor(ThemeColor(red: 0.98, green: 0.97, blue: 0.99)!)

    init(size: NSSize = NSSize(width: 800, height: 600), appearance: NSAppearance.Name = .aqua, theme: SpaceTheme = Surface.darkTheme,
         tracksPendingRedraws: Bool = false) {
        window = ActivityWindow(size: size, appearance: appearance)
        let frame = NSRect(origin: .zero, size: size)
        root = tracksPendingRedraws
            ? ThemeRendererView(frame: frame, makeCanvas: { PendingCanvas(frame: $0, device: $1) })
            : ThemeRendererView(frame: frame)
        window.contentView = root
        root.theme = theme
    }

    deinit { MainActor.assumeIsolated { window.contentView = nil } }

    var materials: [NSVisualEffectView] { root.subviews.compactMap { $0 as? NSVisualEffectView } }
    var material: NSVisualEffectView { materials[0] }
    var canvases: [MTKView] { root.subviews.compactMap { $0 as? MTKView } }

    func settleCanvas() throws {
        let canvas = try #require(canvases.first)
        canvas.draw(canvas.bounds)
        canvas.needsDisplay = false
    }

    func post(_ name: Notification.Name) {
        NotificationCenter.default.post(name: name, object: window)
    }

    func noisy() {
        var theme = Surface.darkTheme
        theme.noise = 0.5
        root.theme = theme
    }
}

struct ThemeRendererViewTests {
    @Test @MainActor func theWindowMaterialUsesTheRecoveredStyleAndEmphasis() {
        let surface = Surface()
        #expect(surface.material.material.rawValue == 1)
        #expect(surface.material.isEmphasized)
    }

    @Test @MainActor func theNativeBackdropKeepsTheWindowsCompositing() {
        let surface = Surface()
        #expect(surface.material.blendingMode == .behindWindow)
        #expect(surface.material.state == .followsWindowActiveState)
    }

    @Test @MainActor func layoutSizesTheMaterialToTheBounds() {
        let surface = Surface()
        surface.root.layout()
        #expect(surface.material.frame == surface.root.bounds)
    }

    @Test @MainActor func aNoOpLayoutSkipsOnLayout() {
        let surface = Surface()
        surface.root.layout()
        var layouts = 0
        surface.root.onLayout = { layouts += 1 }
        surface.root.layout()
        #expect(layouts == 0)
        #expect(surface.material.frame == surface.root.bounds)
    }

    @Test @MainActor func aRealBoundsChangeFiresOnLayoutAndSyncsTheSurfaces() {
        let surface = Surface()
        surface.root.layout()
        var layouts = 0
        surface.root.onLayout = { layouts += 1 }
        surface.root.setFrameSize(NSSize(width: 640, height: 480))
        surface.root.layout()
        #expect(layouts == 1)
        #expect(surface.material.frame == surface.root.bounds)
    }

    @Test @MainActor func aFollowUpLayoutAtTheNewSizeIsANoOp() {
        let surface = Surface()
        surface.root.setFrameSize(NSSize(width: 640, height: 480))
        surface.root.layout()
        var layouts = 0
        surface.root.onLayout = { layouts += 1 }
        surface.root.layout()
        #expect(layouts == 0)
    }

    @Test @MainActor func nativeTextGetsTheContrastingAppearance() {
        let surface = Surface()
        let content = NSView(frame: surface.root.bounds)
        content.appearance = surface.root.palette.contentAppearance
        surface.root.addSubview(content)
        #expect(content.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua)
    }

    @Test @MainActor func aNestedThemeTakesItsUnderlayFromTheWindowNotTheTextAppearance() {
        let surface = Surface()
        let content = NSView(frame: surface.root.bounds)
        content.appearance = surface.root.palette.contentAppearance
        surface.root.addSubview(content)
        let nested = ThemeRendererView(frame: content.bounds)
        content.addSubview(nested)
        nested.theme = Surface.darkTheme
        #expect(!nested.surfaceStyle.backgroundIsDark)
    }

    @MainActor private func unthemedNeighbor(in surface: Surface) -> (nested: ThemeRendererView, content: NSView) {
        let content = NSView(frame: surface.root.bounds)
        content.appearance = surface.root.palette.contentAppearance
        surface.root.addSubview(content)
        let nested = ThemeRendererView(frame: content.bounds)
        content.addSubview(nested)
        nested.theme = Surface.darkTheme
        let neighbor = NSView(frame: content.bounds)
        nested.addSubview(neighbor)
        nested.onPaletteChange = { neighbor.appearance = $0.contentAppearance }
        nested.theme = SpaceTheme()
        return (nested, neighbor)
    }

    @Test @MainActor func unthemedNeighborContentFollowsTheWindowInsteadOfTheSpacesContrast() {
        let surface = Surface()
        let neighbor = unthemedNeighbor(in: surface).content
        #expect(neighbor.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .aqua)
    }

    @Test @MainActor func aWindowAppearanceChangeRepublishesAnUnthemedNeighborsScheme() {
        let surface = Surface()
        let neighbor = unthemedNeighbor(in: surface).content
        surface.window.appearance = NSAppearance(named: .darkAqua)
        #expect(neighbor.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua)
    }

    @Test @MainActor func aWindowAppearanceChangeReachesTheRootAndNestedSurfaces() {
        let surface = Surface()
        let nested = unthemedNeighbor(in: surface).nested
        surface.window.appearance = NSAppearance(named: .darkAqua)
        #expect(surface.root.surfaceStyle.backgroundIsDark)
        #expect(nested.surfaceStyle.backgroundIsDark)
    }

    @Test @MainActor func aThemeChangePublishesTheCompletePaletteImmediately() {
        let surface = Surface()
        var publications = 0
        surface.root.onPaletteChange = { _ in publications += 1 }
        surface.root.theme = Surface.lightTheme
        #expect(publications == 1)
        #expect(!surface.root.palette.isDark)
        #expect(surface.root.layer?.animationKeys()?.isEmpty != false)
    }

    @Test @MainActor func anUnchangedThemeDoesNotRepublish() {
        let surface = Surface(theme: Surface.lightTheme)
        var publications = 0
        surface.root.onPaletteChange = { _ in publications += 1 }
        surface.root.theme = Surface.lightTheme
        #expect(publications == 0)
    }

    @Test @MainActor func aLightColorKeepsDarkTextAfterTheMacTurnsDark() {
        let surface = Surface(theme: Surface.lightTheme)
        surface.window.appearance = NSAppearance(named: .darkAqua)
        #expect(!surface.root.palette.isDark)
    }

    @Test @MainActor func aColoredAutomaticSpacesWindowMaterialFollowsTheMacIntoDark() {
        let surface = Surface(theme: Surface.lightTheme)
        surface.window.appearance = NSAppearance(named: .darkAqua)
        #expect(surface.material.material.rawValue == 2)
    }

    @Test @MainActor func aLockedSidebarHidesTheMaterial() {
        let surface = Surface()
        surface.root.drawsBackground = false
        #expect(surface.material.isHidden)
        surface.root.drawsBackground = true
        #expect(surface.root.drawsMaterial && !surface.material.isHidden)
    }

    @Test @MainActor func aLibraryCardOmitsTheMaterialButStillPaintsItsColors() throws {
        let surface = Surface()
        surface.root.drawsMaterial = false
        #expect(surface.material.isHidden)
        #expect(try #require(surface.canvases.first).isHidden == false)
        surface.root.drawsMaterial = true
        #expect(!surface.material.isHidden)
    }

    @Test @MainActor func removingTheLastColorKeepsTheNativeDarkBackingAndRetiresTheCanvas() {
        let surface = Surface(appearance: .darkAqua)
        surface.root.theme = SpaceTheme()
        #expect(!surface.material.isHidden && surface.material.material.rawValue == 2)
        #expect(surface.canvases.allSatisfy { $0.isHidden })
    }

    @Test @MainActor func aMalformedThemeNeverReachesMetal() {
        let surface = Surface()
        var invalid = Surface.darkTheme
        invalid.intensity = .nan
        surface.root.theme = invalid
        #expect(surface.canvases.allSatisfy { $0.isHidden })
    }

    @Test @MainActor func detachingTheRendererTreeLeavesContentOwnershipAlone() {
        let surface = Surface()
        let nested = ThemeRendererView(frame: surface.root.bounds)
        surface.root.addSubview(nested)
        surface.window.contentView = nil
        #expect(surface.root.window == nil && nested.window == nil)
        #expect(nested.superview === surface.root)
    }
}

struct ThemeWindowActivityTests {
    @MainActor private final class Pair {
        let parent = ActivityWindow(size: NSSize(width: 100, height: 100))
        let child = ActivityWindow(size: NSSize(width: 10, height: 10))
        init() { parent.addChildWindow(child, ordered: .above) }
        deinit { MainActor.assumeIsolated { parent.removeChildWindow(child) } }
    }

    @Test @MainActor func anInactiveOwnershipChainIsDimmed() {
        let pair = Pair()
        #expect(!ThemeWindowActivity.isActive(pair.child))
    }

    @Test @MainActor func aMainWindowAndItsDescendantsStayActive() {
        let pair = Pair()
        pair.parent.reportsMain = true
        #expect(ThemeWindowActivity.isActive(pair.parent) && ThemeWindowActivity.isActive(pair.child))
    }

    @Test @MainActor func aKeyChildIsActiveWithoutPromotingItsParent() {
        let pair = Pair()
        pair.child.reportsKey = true
        #expect(ThemeWindowActivity.isActive(pair.child))
        #expect(!ThemeWindowActivity.isActive(pair.parent))
    }

    @Test @MainActor func aParentsActivationTargetsTheChildSurfaceOnly() {
        let pair = Pair()
        #expect(ThemeWindowActivity.contains(pair.parent, in: pair.child))
        #expect(!ThemeWindowActivity.contains(pair.child, in: pair.parent))
    }

    @Test @MainActor func aReparentedSurfaceDropsItsPreviousOwner() {
        let pair = Pair()
        pair.parent.removeChildWindow(pair.child)
        #expect(!ThemeWindowActivity.contains(pair.parent, in: pair.child))
    }

    @Test @MainActor func aDetachedRendererHasNoActiveOwner() {
        #expect(!ThemeWindowActivity.isActive(nil))
    }
}

struct ThemeCanvasActivityTests {
    @Test @MainActor func aZeroNoiseThemeSkipsActivityInvalidation() throws {
        let surface = Surface(tracksPendingRedraws: true)
        try surface.settleCanvas()
        let before = surface.root.canvasActivityDisplayInvalidations
        surface.window.reportsKey = true
        surface.post(NSWindow.didBecomeKeyNotification)
        #expect(surface.root.canvasActivityDisplayInvalidations == before)
    }

    @Test @MainActor func aNoisyThemeRedrawsWhenBecomingKeyFlipsActivity() throws {
        let surface = Surface(tracksPendingRedraws: true)
        surface.noisy()
        try surface.settleCanvas()
        let before = surface.root.canvasActivityDisplayInvalidations
        surface.window.reportsKey = true
        surface.post(NSWindow.didBecomeKeyNotification)
        #expect(surface.root.canvasActivityDisplayInvalidations == before + 1)
    }

    @Test @MainActor func becomingMainWhileKeyLeavesActivityAndSkipsTheRedraw() throws {
        let surface = Surface(tracksPendingRedraws: true)
        surface.noisy()
        surface.window.reportsKey = true
        try surface.settleCanvas()
        let before = surface.root.canvasActivityDisplayInvalidations
        surface.window.reportsMain = true
        surface.post(NSWindow.didBecomeMainNotification)
        #expect(surface.root.canvasActivityDisplayInvalidations == before)
    }

    @Test @MainActor func pairedKeyAndMainNotificationsRedrawOnce() throws {
        let surface = Surface(tracksPendingRedraws: true)
        surface.noisy()
        try surface.settleCanvas()
        let before = surface.root.canvasActivityDisplayInvalidations
        surface.window.reportsKey = true
        surface.window.reportsMain = true
        surface.post(NSWindow.didBecomeKeyNotification)
        surface.post(NSWindow.didBecomeMainNotification)
        #expect(surface.root.canvasActivityDisplayInvalidations == before + 1)
    }

    @Test @MainActor func resigningKeyWhileMainKeepsActivityAndSkipsTheRedraw() throws {
        let surface = Surface(tracksPendingRedraws: true)
        surface.noisy()
        surface.window.reportsKey = true
        surface.window.reportsMain = true
        try surface.settleCanvas()
        let before = surface.root.canvasActivityDisplayInvalidations
        surface.window.reportsKey = false
        surface.post(NSWindow.didResignKeyNotification)
        #expect(surface.root.canvasActivityDisplayInvalidations == before)
    }

    @Test @MainActor func resigningMainAfterKeyFlipsActivityAndRedraws() throws {
        let surface = Surface(tracksPendingRedraws: true)
        surface.noisy()
        surface.window.reportsMain = true
        try surface.settleCanvas()
        let before = surface.root.canvasActivityDisplayInvalidations
        surface.window.reportsMain = false
        surface.post(NSWindow.didResignMainNotification)
        #expect(surface.root.canvasActivityDisplayInvalidations == before + 1)
    }

    @Test @MainActor func aThemeRefreshRepublishesThePaletteWithoutTheActivityPath() throws {
        let surface = Surface(tracksPendingRedraws: true)
        surface.noisy()
        try surface.settleCanvas()
        let before = surface.root.canvasActivityDisplayInvalidations
        surface.root.theme = Surface.lightTheme
        #expect(surface.root.canvasActivityDisplayInvalidations == before)
        #expect(!surface.root.palette.isDark)
    }
}

struct ThemePagingMaterialTests {
    static let light = SpaceTheme(primaryColor: ThemeColor(red: 0.66, green: 0.8, blue: 0.96)!, colorCount: 2, appearance: .light)
    static let alsoLight = SpaceTheme(primaryColor: ThemeColor(red: 0.95, green: 0.8, blue: 0.6)!, colorCount: 1, appearance: .light)
    static let dark = SpaceTheme(primaryColor: ThemeColor(red: 0.4, green: 0.27, blue: 0.8)!, colorCount: 2, appearance: .dark)

    @MainActor private func surface(theme: SpaceTheme = Self.light, from: SpaceTheme = Self.light, to: SpaceTheme? = Self.dark,
                                    progress: CGFloat = 0.3) -> Surface {
        let surface = Surface(size: NSSize(width: 300, height: 200), theme: theme)
        surface.root.pagingTransition = to.map { ThemePagingTransition(from: from, theme: $0, progress: progress) }
        return surface
    }

    @MainActor private func isDark(_ view: NSVisualEffectView) -> Bool { view.appearance?.name == .darkAqua }

    @Test @MainActor func aSwipeBetweenSameStyleSpacesAddsNoMaterial() {
        #expect(surface(to: Self.alsoLight).materials.count == 1)
    }

    @Test @MainActor func aLightToDarkSwipeAddsTheForegroundMaterialJustAboveTheBaseAndUnderTheTheme() throws {
        let surface = surface()
        try #require(surface.materials.count == 2)
        let subviews = surface.root.subviews
        let base = try #require(subviews.firstIndex(of: surface.materials[0]))
        let foreground = try #require(subviews.firstIndex(of: surface.materials[1]))
        #expect(foreground == base + 1)
        #expect(subviews.firstIndex { $0 is MTKView }.map { $0 > foreground } != false)
    }

    @Test @MainActor func theFromStylesMaterialSitsUnderTheToStylesAtTheSwipesProgress() throws {
        let surface = surface()
        try #require(surface.materials.count == 2)
        let base = surface.materials[0], foreground = surface.materials[1]
        #expect(base.material.rawValue == 1 && !isDark(base))
        #expect(foreground.material.rawValue == 2 && isDark(foreground))
        #expect(!foreground.isHidden && abs(foreground.alphaValue - 0.3) < 0.001)
    }

    @Test @MainActor func theForegroundMaterialIsBuiltAsTheWindowsOwnAndCoversTheSurface() throws {
        let surface = surface()
        try #require(surface.materials.count == 2)
        let foreground = surface.materials[1]
        #expect(foreground.blendingMode == .behindWindow && foreground.state == .followsWindowActiveState && foreground.isEmphasized)
        surface.root.layout()
        #expect(foreground.frame == surface.root.bounds)
    }

    @Test @MainActor func theSameForegroundFollowsTheSwipe() throws {
        let surface = surface()
        try #require(surface.materials.count == 2)
        let foreground = surface.materials[1]
        surface.root.pagingTransition = ThemePagingTransition(from: Self.light, theme: Self.dark, progress: 0.8)
        #expect(surface.materials.count == 2 && surface.materials[1] === foreground)
        #expect(abs(foreground.alphaValue - 0.8) < 0.001)
    }

    @Test @MainActor func aCommitMidSwipeLeavesBothMaterials() throws {
        let surface = surface(progress: 0.8)
        surface.root.theme = Self.dark
        try #require(surface.materials.count == 2)
        let base = surface.materials[0], foreground = surface.materials[1]
        #expect(base.material.rawValue == 1 && !isDark(base))
        #expect(foreground.material.rawValue == 2 && isDark(foreground) && abs(foreground.alphaValue - 0.8) < 0.001)
    }

    @Test @MainActor func theLeftPagesStyleIsTheBase() throws {
        let surface = surface(theme: Self.dark, from: Self.dark, to: Self.light, progress: 0.2)
        try #require(surface.materials.count == 2)
        let base = surface.materials[0], foreground = surface.materials[1]
        #expect(base.material.rawValue == 2 && isDark(base))
        #expect(foreground.material.rawValue == 1 && !isDark(foreground) && abs(foreground.alphaValue - 0.2) < 0.001)
    }

    @Test @MainActor func atRestOnlyTheThemesOwnMaterialShows() throws {
        let surface = surface(theme: Self.dark, from: Self.dark, to: Self.light, progress: 0.2)
        try #require(surface.materials.count == 2)
        surface.root.pagingTransition = nil
        let base = surface.materials[0], foreground = surface.materials[1]
        #expect(foreground.isHidden && !base.isHidden)
        #expect(base.material.rawValue == 2 && isDark(base))
    }

    enum Suppression: CaseIterable { case floating, locked, libraryCard }

    @Test(arguments: Suppression.allCases)
    @MainActor func surfacesWithoutTheWindowsMaterialNeverShowTheCrossfade(suppression: Suppression) throws {
        let surface = surface(theme: Self.dark, from: Self.dark, to: Self.light, progress: 0.5)
        try #require(surface.materials.count == 2)
        let foreground = surface.materials[1]
        switch suppression {
        case .floating: surface.root.floatingCornerRadius = 8
        case .locked: surface.root.drawsBackground = false
        case .libraryCard: surface.root.drawsMaterial = false
        }
        #expect(foreground.isHidden)
        switch suppression {
        case .floating: surface.root.floatingCornerRadius = nil
        case .locked: surface.root.drawsBackground = true
        case .libraryCard: surface.root.drawsMaterial = true
        }
        #expect(!foreground.isHidden)
    }

    @Test @MainActor func aSwipeTowardsAnUncolouredSpaceInALightWindowCrossfadesToLight() throws {
        let surface = surface(theme: Self.dark, from: Self.dark, to: SpaceTheme(), progress: 0.5)
        try #require(surface.materials.count == 2)
        let foreground = surface.materials[1]
        #expect(!foreground.isHidden && foreground.material.rawValue == 1 && !isDark(foreground))
    }

    @Test @MainActor func anUncolouredSpaceInADarkWindowAlreadyHasTheDarkStyle() throws {
        let surface = surface(theme: Self.dark, from: Self.dark, to: SpaceTheme(), progress: 0.5)
        try #require(surface.materials.count == 2)
        surface.window.appearance = NSAppearance(named: .darkAqua)
        #expect(surface.materials[1].isHidden)
    }

    @Test @MainActor func pastOnePageTheLeftPagesStyleIsTheBase() throws {
        let surface = surface(theme: Self.alsoLight, from: Self.dark, to: Self.light, progress: 0.3)
        try #require(surface.materials.count == 2)
        let base = surface.materials[0], foreground = surface.materials[1]
        #expect(base.material.rawValue == 2 && isDark(base))
        #expect(foreground.material.rawValue == 1 && !isDark(foreground))
        #expect(!foreground.isHidden && abs(foreground.alphaValue - 0.3) < 0.001)
    }

    @Test @MainActor func aCommitToEitherPageLeavesBothMaterials() throws {
        let surface = surface(theme: Self.alsoLight, from: Self.dark, to: Self.light, progress: 0.3)
        surface.root.theme = Self.light
        try #require(surface.materials.count == 2)
        #expect(surface.materials[0].material.rawValue == 2 && isDark(surface.materials[0]))
        #expect(!surface.materials[1].isHidden)
    }

    @Test @MainActor func pagesOfOneStyleNeedNoForeground() throws {
        let surface = surface(from: Self.dark, to: Self.light, progress: 0.3)
        try #require(surface.materials.count == 2)
        surface.root.pagingTransition = ThemePagingTransition(from: Self.dark, theme: Self.dark, progress: 0.3)
        #expect(surface.materials[1].isHidden && surface.materials[0].material.rawValue == 2)
    }

    @Test @MainActor func atRestTheBaseReturnsToTheSurfacesOwnStyle() throws {
        let surface = surface(from: Self.dark, to: Self.light, progress: 0.3)
        try #require(surface.materials.count == 2)
        surface.root.pagingTransition = nil
        let base = surface.materials[0]
        #expect(base.material.rawValue == 1 && !isDark(base) && surface.materials[1].isHidden)
    }

    @MainActor private func sidebar(in surface: Surface) -> ThemeRendererView {
        let container = ThemeRendererView(frame: NSRect(x: 0, y: 0, width: 120, height: 200))
        surface.root.addSubview(container)
        container.coordinateSpace = surface.root
        container.drawsBackground = false
        container.theme = Self.light
        container.pagingTransition = ThemePagingTransition(from: Self.light, theme: Self.dark, progress: 0.4)
        container.drawsBackground = true
        return container
    }

    @MainActor private func visibleMaterials(_ view: NSView) -> [NSVisualEffectView] {
        view.subviews.compactMap { $0 as? NSVisualEffectView }.filter { !$0.isHidden }
    }

    @Test @MainActor func aDockedSidebarDrawingAgainMidSwipeAddsNoBehindWindowCrossfade() {
        let surface = surface(to: nil)
        #expect(visibleMaterials(sidebar(in: surface)).count == 1)
    }

    @Test @MainActor func aFloatingSidebarBlendsIntoTheDarkPagesBlurWithinTheWindow() throws {
        let surface = surface(to: nil)
        let container = sidebar(in: surface)
        container.floatingCornerRadius = 8
        container.pagingTransition = ThemePagingTransition(from: Self.light, theme: Self.dark, progress: 0.6)
        let floating = visibleMaterials(container)
        try #require(floating.count == 2)
        #expect(floating.allSatisfy { $0.blendingMode == .withinWindow && $0.material == .popover })
        #expect(floating.map(isDark) == [false, true])
        #expect(abs(floating[1].alphaValue - 0.6 / 0.9) < 0.001)
    }

    @Test @MainActor func aSidebarDockedAgainShowsOnlyItsOwnMaterial() {
        let surface = surface(to: nil)
        let container = sidebar(in: surface)
        container.floatingCornerRadius = 8
        container.pagingTransition = ThemePagingTransition(from: Self.light, theme: Self.dark, progress: 0.6)
        container.floatingCornerRadius = nil
        #expect(visibleMaterials(container).count == 1)
    }
}
