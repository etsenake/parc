import AppKit
import MetalKit
import Testing
@testable import ParcCore
@testable import ParcKit

@MainActor
struct FloatingSidebarSurfaceTests {
    @MainActor final class Surface {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        let window: NSWindow
        let page: NSView
        let container = ThemeRendererView(frame: NSRect(x: 5, y: 5, width: 200, height: 390))
        let windowMaterial: NSVisualEffectView.Material

        init() {
            root.wantsLayer = true
            window = NSWindow(contentRect: root.frame, styleMask: [.borderless], backing: .buffered, defer: true)
            window.isReleasedWhenClosed = false
            window.contentView = root
            page = NSView(frame: root.bounds)
            page.wantsLayer = true
            root.addSubview(page)
            root.addSubview(container)
            container.coordinateSpace = root
            container.theme = .singleColor(ThemeColor(red: 0.42, green: 0.36, blue: 0.86)!)
            container.addSubview(NSView(frame: container.bounds))
            windowMaterial = container.subviews.compactMap { $0 as? NSVisualEffectView }.first!.material
        }

        deinit { MainActor.assumeIsolated { window.contentView = nil } }

        var materials: [NSVisualEffectView] { container.subviews.compactMap { $0 as? NSVisualEffectView } }
        var material: NSVisualEffectView { materials[0] }
        var canvas: MTKView? { container.subviews.compactMap { $0 as? MTKView }.first }
        var shadows: [FloatingSidebarShadowView] { container.subviews.compactMap { $0 as? FloatingSidebarShadowView } }
        var shadow: FloatingSidebarShadowView { shadows[0] }

        func float() { container.floatingCornerRadius = FloatingSidebarSurface.cornerRadius }

        func prepareDock() -> NSVisualEffectView {
            float()
            container.preparesFloatingDock = true
            return materials[1]
        }

        func dock() {
            root.layoutSubtreeIfNeeded(); root.display(); CATransaction.flush()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.08
                context.timingFunction = CAMediaTimingFunction(controlPoints: 0.25, 0.46, 0.45, 0.94)
                context.allowsImplicitAnimation = true
                container.docksFloatingSurface = true
            }
        }

        func render() -> NSBitmapImageRep {
            root.layoutSubtreeIfNeeded(); root.display(); CATransaction.flush()
            let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 600, pixelsHigh: 400, bitsPerSample: 8, samplesPerPixel: 4,
                                       hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            let context = NSGraphicsContext(bitmapImageRep: rep)!.cgContext
            context.translateBy(x: 0, y: 400); context.scaleBy(x: 1, y: -1)
            root.layer!.render(in: context)
            return rep
        }
    }

    enum Fading: CaseIterable { case shadow, blur, dock }

    private static func near(_ a: CGFloat, _ b: CGFloat, _ tolerance: CGFloat = 0.002) -> Bool { abs(a - b) <= tolerance }
    private static func white(_ rep: NSBitmapImageRep, _ x: Int, _ y: Int) -> CGFloat {
        rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceGray)?.whiteComponent ?? -1
    }
    private static func maskedToEight(_ view: NSVisualEffectView) -> Bool {
        view.maskImage.map { $0.size == NSSize(width: 17, height: 17) && $0.capInsets.left == 8 } == true
    }

    @Test func theWindowsOwnSurfaceUsesTheBehindWindowMaterialWithoutShadowOrEdge() {
        let surface = Surface()
        #expect(surface.material.blendingMode == .behindWindow)
        #expect(surface.shadows.isEmpty)
        #expect(surface.container.layer?.borderWidth == 0)
    }

    @Test func aFloatingSurfaceUsesAnEmphasizedWithinWindowPopoverBlur() {
        let surface = Surface()
        surface.float()
        #expect(surface.material.blendingMode == .withinWindow)
        #expect(surface.material.material == .popover)
        #expect(surface.material.isEmphasized)
    }

    @Test func aFloatingSurfaceMasksItsBlurToTheCornerRadius() {
        let surface = Surface()
        surface.float()
        #expect(Self.maskedToEight(surface.material))
    }

    @Test func aFloatingSurfaceRoundsItsTheme() throws {
        let surface = Surface()
        surface.float()
        let canvas = try #require(surface.canvas)
        #expect(canvas.layer?.cornerRadius == 8 && canvas.clipsToBounds)
    }

    @Test func aFloatingSurfaceDrawsItsOwnRoundedOnePointEdge() {
        let surface = Surface()
        surface.float()
        #expect(surface.container.layer?.cornerRadius == 8)
        #expect(surface.container.layer?.borderWidth == 1)
        #expect(surface.container.layer?.borderColor == FloatingSidebarSurface.borderColor)
    }

    @Test func aFloatingSurfaceUndoesTheCornerClipSoItsShadowShows() {
        let surface = Surface()
        surface.float()
        #expect(!surface.container.clipsToBounds)
        #expect(surface.container.layer?.masksToBounds == false)
    }

    @Test func aFloatingSurfaceLaysOneShadowUnderItsMaterialAndTheme() {
        let surface = Surface()
        surface.float()
        #expect(surface.shadows.count == 1)
        #expect(surface.container.subviews.first === surface.shadow)
    }

    @Test func theShadowReachesTenPointsPastTheSurfaceOnEverySide() {
        let surface = Surface()
        surface.float()
        #expect(surface.shadow.frame == surface.container.bounds.insetBy(dx: -10, dy: -10))
    }

    @Test func theShadowShowsTheDropShadowArtworkAtTwentyPercent() {
        let surface = Surface()
        surface.float()
        #expect(surface.shadow.alphaValue == 0.2)
        #expect(!surface.shadow.isHidden)
        #expect(surface.shadow.image === FloatingSidebarSurface.shadowImage)
    }

    @Test func theShadowTakesNoClickAndIsNoAccessibilityElement() {
        let surface = Surface()
        surface.float()
        #expect(surface.shadow.hitTest(NSPoint(x: 50, y: 50)) == nil)
        #expect(!surface.shadow.isAccessibilityElement())
    }

    @Test func theShadowFollowsTheSurfacesSize() {
        let surface = Surface()
        surface.float()
        surface.container.frame = NSRect(x: 5, y: 5, width: 240, height: 380)
        #expect(surface.shadow.frame == surface.container.bounds.insetBy(dx: -10, dy: -10))
    }

    @Test func aThemeChangeKeepsTheFloatingMaterial() {
        let surface = Surface()
        surface.float()
        surface.container.theme = .singleColor(ThemeColor(red: 0.2, green: 0.6, blue: 0.4)!)
        #expect(surface.material.blendingMode == .withinWindow)
        #expect(surface.material.material == .popover)
    }

    @Test func theShadowArtworkStretchesFromItsCapInsetsAxesIndependently() throws {
        let surface = Surface()
        surface.float()
        surface.shadow.image = try FloatingSidebarArtworkTests.shadowImage()
        surface.container.drawsBackground = false
        _ = surface.render()
        let center = surface.shadow.layer?.contentsCenter ?? .zero
        #expect(surface.shadow.layer?.contents != nil)
        #expect(surface.shadow.layer?.contentsGravity == .resize)
        #expect(Self.near(center.minX, 19.0 / 40) && Self.near(center.minY, 20.0 / 40))
        #expect(Self.near(center.width, 1.0 / 40) && Self.near(center.height, 1.0 / 40))
    }

    @Test func theShadowDarkensJustOutsideTheSurfaceButNotFifteenPointsOut() throws {
        let surface = Surface()
        surface.float()
        surface.shadow.image = try FloatingSidebarArtworkTests.shadowImage()
        surface.container.drawsBackground = false
        surface.page.layer?.backgroundColor = NSColor.white.cgColor
        let light = surface.render()
        let edge = Int(surface.container.frame.maxX), middle = Int(surface.container.frame.midY)
        #expect(Self.white(light, edge, middle) < 0.95)
        #expect(Self.white(light, edge + 15, middle) > 0.99)
    }

    @Test func aLightOnePointEdgeShowsJustInsideTheSurface() throws {
        let surface = Surface()
        surface.float()
        surface.shadow.image = try FloatingSidebarArtworkTests.shadowImage()
        surface.container.drawsBackground = false
        surface.page.layer?.backgroundColor = NSColor.black.cgColor
        let dark = surface.render()
        let edge = Int(surface.container.frame.maxX), middle = Int(surface.container.frame.midY)
        #expect(Self.white(dark, edge - 1, middle) > 0.2)
        #expect(Self.white(dark, edge - 3, middle) < 0.02)
    }

    @Test func theCanvasDrawsASwipeIntoAColouredSpace() throws {
        let surface = Surface()
        surface.float()
        surface.container.theme = SpaceTheme()
        surface.container.pagingTransition = ThemePagingTransition(from: SpaceTheme(),
                                                                   theme: .singleColor(ThemeColor(red: 0.9, green: 0.4, blue: 0.2)!),
                                                                   progress: 0.4)
        #expect(try #require(surface.canvas).isHidden == false)
    }

    @Test func anUncolouredSpaceAtRestDrawsNoCanvas() throws {
        let surface = Surface()
        surface.float()
        surface.container.theme = SpaceTheme()
        surface.container.pagingTransition = ThemePagingTransition(from: SpaceTheme(), theme: .singleColor(ThemeColor(red: 0.9, green: 0.4, blue: 0.2)!),
                                                                   progress: 0.4)
        surface.container.pagingTransition = nil
        #expect(try #require(surface.canvas).isHidden)
    }

    @Test func thereIsNoDockMaterialBeforeTheFirstDock() {
        let surface = Surface()
        surface.float()
        #expect(surface.materials.count == 1)
    }

    @Test func preparingTheDockLaysTheWindowMaterialOverTheBlurAndUnderTheTheme() throws {
        let surface = Surface()
        let dock = surface.prepareDock()
        let blurIndex = try #require(surface.container.subviews.firstIndex(of: surface.material))
        #expect(surface.materials.count == 2)
        #expect(surface.container.subviews.firstIndex(of: dock) == blurIndex + 1)
        if let canvas = surface.canvas { #expect(try #require(surface.container.subviews.firstIndex(of: canvas)) > blurIndex + 1) }
    }

    @Test func theDockMaterialIsTheWindowSurfacesBehindWindowMaterialOnItsSideMaskedToTheRadius() {
        let surface = Surface()
        let dock = surface.prepareDock()
        let side: NSAppearance.Name = surface.container.surfaceStyle.backgroundIsDark ? .darkAqua : .aqua
        #expect(dock.blendingMode == .behindWindow)
        #expect(dock.isEmphasized)
        #expect(dock.material == surface.windowMaterial)
        #expect(dock.appearance?.name == side)
        #expect(Self.maskedToEight(dock))
    }

    @Test func aPreparedDockMaterialIsUnhiddenAtZeroWithTheBlurAndShadowUntouched() {
        let surface = Surface()
        let dock = surface.prepareDock()
        #expect(!dock.isHidden && dock.alphaValue == 0)
        #expect(surface.material.alphaValue == 1)
        #expect(surface.shadow.alphaValue == 0.2)
    }

    @Test func theDockMaterialPassesClicksThrough() {
        let surface = Surface()
        let dock = surface.prepareDock()
        #expect(dock.hitTest(NSPoint(x: 50, y: 50)) == nil)
        #expect(!dock.isAccessibilityElement())
    }

    @Test func theCornersMaskEdgeAndBlurStayThroughTheSlide() {
        let surface = Surface()
        _ = surface.prepareDock()
        surface.dock()
        #expect(surface.container.layer?.cornerRadius == 8)
        #expect(surface.material.maskImage != nil)
        #expect(surface.container.layer?.borderWidth == 1)
        #expect(surface.material.blendingMode == .withinWindow)
        if let canvas = surface.canvas { #expect(canvas.layer?.cornerRadius == 8) }
    }

    @Test func dockingFadesTheShadowOut() {
        let surface = Surface()
        _ = surface.prepareDock()
        surface.dock()
        #expect(surface.shadow.alphaValue == 0 && !surface.shadow.isHidden)
    }

    @Test func dockingFadesTheBlurOutAndTheWindowsMaterialIn() {
        let surface = Surface()
        let dock = surface.prepareDock()
        surface.dock()
        #expect(surface.material.alphaValue == 0)
        #expect(dock.alphaValue == 1 && !dock.isHidden)
    }

    @Test(arguments: Fading.allCases)
    func dockingFadesOnTheGroupsTiming(_ part: Fading) throws {
        let surface = Surface()
        let dock = surface.prepareDock()
        surface.dock()
        let view: NSView = switch part { case .shadow: surface.shadow; case .blur: surface.material; case .dock: dock }
        let fade = try #require(view.layer?.animation(forKey: "opacity") as? CABasicAnimation)
        #expect(Self.near(fade.duration, 0.08, 1e-6))
    }

    @Test func aFullPassMidDockKeepsTheFadedShadowAndTheCrossFadedMaterials() {
        let surface = Surface()
        let dock = surface.prepareDock()
        surface.dock()
        surface.float()
        surface.container.docksFloatingSurface = true
        surface.container.preparesFloatingDock = false
        #expect(surface.shadow.alphaValue == 0 && surface.container.layer?.cornerRadius == 8)
        #expect(surface.material.alphaValue == 0 && dock.alphaValue == 1 && !dock.isHidden)
    }

    @Test func aReversedDockFloatsWithItsShadowCornersAndMask() {
        let surface = Surface()
        _ = surface.prepareDock()
        surface.dock()
        surface.container.preparesFloatingDock = false
        surface.container.docksFloatingSurface = false
        #expect(surface.shadow.alphaValue == 0.2 && !surface.shadow.isHidden)
        #expect(surface.container.layer?.cornerRadius == 8)
        #expect(surface.material.maskImage != nil)
    }

    @Test func aReversedDockShowsTheBlurAndHidesTheDockMaterial() {
        let surface = Surface()
        let dock = surface.prepareDock()
        surface.dock()
        surface.container.preparesFloatingDock = false
        surface.container.docksFloatingSurface = false
        #expect(surface.material.alphaValue == 1)
        #expect(dock.isHidden && dock.alphaValue == 0)
    }

    @Test func aReversedDockLeavesNoFadeInFlight() {
        let surface = Surface()
        let dock = surface.prepareDock()
        surface.dock()
        surface.container.preparesFloatingDock = false
        surface.container.docksFloatingSurface = false
        #expect([surface.shadow as NSView, surface.material, dock].allSatisfy { $0.layer?.animation(forKey: "opacity") == nil })
    }

    private func settled() -> (Surface, NSVisualEffectView) {
        let surface = Surface()
        let dock = surface.prepareDock()
        surface.container.preparesFloatingDock = false
        surface.dock()
        surface.container.floatingCornerRadius = nil
        surface.container.docksFloatingSurface = false
        return (surface, dock)
    }

    @Test func aSettledDockUsesTheWindowsOwnMaterialAgain() {
        let (surface, _) = settled()
        #expect(surface.material.blendingMode == .behindWindow)
        #expect(surface.material.material == surface.windowMaterial)
        #expect(surface.material.maskImage == nil)
    }

    @Test func aSettledDockRestoresTheBlursAlphaAndHidesTheDockMaterial() {
        let (surface, dock) = settled()
        #expect(surface.material.alphaValue == 1)
        #expect(dock.isHidden && dock.alphaValue == 0)
    }

    @Test func aSettledSurfaceHasNoEdgeOrCorners() {
        let (surface, _) = settled()
        #expect(surface.container.layer?.borderWidth == 0)
        #expect(surface.container.layer?.borderColor == nil)
        #expect(surface.container.layer?.cornerRadius == 0)
    }

    @Test func aSettledSurfacesThemeIsSquareAndUnclipped() throws {
        let (surface, _) = settled()
        let canvas = try #require(surface.canvas)
        #expect(!canvas.clipsToBounds && canvas.layer?.cornerRadius == 0)
    }

    @Test func aSettledSurfaceHidesItsShadowReadyForTheNextFloat() {
        let (surface, _) = settled()
        #expect(surface.shadow.isHidden && surface.shadow.alphaValue == 0.2)
    }

    @Test func aSettledSurfaceStaysUnclipped() {
        let (surface, _) = settled()
        #expect(!surface.container.clipsToBounds)
        #expect(surface.container.layer?.masksToBounds == false)
    }

    @Test func floatingAgainReusesTheShadow() {
        let (surface, _) = settled()
        let shadow = surface.shadow
        surface.float()
        #expect(surface.shadows.count == 1 && surface.shadows.first === shadow)
        #expect(!shadow.isHidden && shadow.alphaValue == 0.2)
    }

    @Test func floatingAgainKeepsTheDockMaterialHiddenForTheNextDock() {
        let (surface, dock) = settled()
        surface.float()
        #expect(surface.materials.count == 2 && surface.materials[1] === dock)
        #expect(dock.isHidden)
        #expect(surface.material.alphaValue == 1)
    }

    @Test(arguments: [true, false])
    func theSidebarContentClipsOnlyWhileFloating(_ floating: Bool) {
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
        content.wantsLayer = true
        content.layer?.cornerRadius = floating ? FloatingSidebarSurface.cornerRadius : 0
        content.clipsToBounds = floating
        #expect(content.layer?.masksToBounds == floating)
        #expect(content.layer?.cornerRadius == (floating ? 8 : 0))
    }
}
