import AppKit
import MetalKit
import Testing
@testable import Parc
@testable import ParcCore

@MainActor
struct FloatingSidebarSwipeDockTests {
    @MainActor final class Docking {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 300), styleMask: [.borderless], backing: .buffered, defer: true)
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 300))
        let surface = ThemeRendererView(frame: NSRect(x: 5, y: 5, width: 200, height: 290))
        let light: SpaceTheme, alsoLight: SpaceTheme, dark: SpaceTheme

        init() {
            window.isReleasedWhenClosed = false
            window.appearance = NSAppearance(named: .aqua)
            root.wantsLayer = true
            window.contentView = root
            root.addSubview(surface)
            var light = SpaceTheme.singleColor(ThemeColor(red: 0.8, green: 0.88, blue: 0.97)!); light.appearance = .light
            var alsoLight = SpaceTheme.singleColor(ThemeColor(red: 0.95, green: 0.8, blue: 0.6)!); alsoLight.appearance = .light
            var dark = SpaceTheme.singleColor(ThemeColor(red: 0.36, green: 0.22, blue: 0.62)!); dark.appearance = .dark
            (self.light, self.alsoLight, self.dark) = (light, alsoLight, dark)
            surface.floatingCornerRadius = FloatingSidebarSurface.cornerRadius
            surface.drawsBackground = true
        }

        deinit { MainActor.assumeIsolated { window.contentView = nil } }

        var rendersColour: Bool { surface.subviews.contains { $0 is MTKView } }
        var blurs: [NSVisualEffectView] { surface.subviews.compactMap { $0 as? NSVisualEffectView } }
        func swipe(_ progress: CGFloat, to theme: SpaceTheme? = nil) {
            surface.pagingTransition = ThemePagingTransition(from: light, theme: theme ?? dark, progress: progress)
        }
        func prepared() -> (base: NSVisualEffectView, crossfade: NSVisualEffectView, dock: NSVisualEffectView, dockCrossfade: NSVisualEffectView) {
            surface.theme = light
            swipe(0.95)
            surface.preparesFloatingDock = true
            let blurs = self.blurs
            return (blurs[0], blurs[1], blurs[2], blurs[3])
        }
        func dock() {
            root.layoutSubtreeIfNeeded(); root.display(); CATransaction.flush()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.08
                context.allowsImplicitAnimation = true
                surface.docksFloatingSurface = true
            }
        }
    }

    private static func near(_ a: CGFloat, _ b: CGFloat, _ tolerance: CGFloat = 0.002) -> Bool { abs(a - b) <= tolerance }
    enum Part: CaseIterable { case blur, crossfade, dock, dockCrossfade }

    @Test func preparingTheDockMidSwipeAddsTheWindowsMaterialAndItsCrossfade() throws {
        let docking = Docking()
        try #require(docking.rendersColour)
        docking.surface.theme = docking.light
        docking.swipe(0.95)
        #expect(docking.blurs.count == 2)
        docking.surface.preparesFloatingDock = true
        #expect(docking.blurs.count == 4)
    }

    @Test func theWindowsMaterialAndItsCrossfadeLieOverBothBlursAndUnderTheTheme() throws {
        let docking = Docking()
        try #require(docking.rendersColour)
        let parts = docking.prepared()
        let subviews = docking.surface.subviews
        #expect(subviews.firstIndex(of: parts.dock) == subviews.firstIndex(of: parts.crossfade).map { $0 + 1 })
        #expect(subviews.firstIndex(of: parts.dockCrossfade) == subviews.firstIndex(of: parts.dock).map { $0 + 1 })
        #expect(try #require(subviews.firstIndex { $0 is MTKView }) > subviews.firstIndex(of: parts.dockCrossfade)!)
    }

    @Test func theWindowsMaterialTakesTheLeftPagesStyleAndItsCrossfadeTheRightPages() throws {
        let docking = Docking()
        try #require(docking.rendersColour)
        let parts = docking.prepared()
        #expect(parts.dock.material.rawValue == 1 && parts.dock.appearance?.name == .aqua)
        #expect(parts.dockCrossfade.material.rawValue == 2 && parts.dockCrossfade.appearance?.name == .darkAqua)
        #expect(parts.dockCrossfade.blendingMode == .behindWindow && parts.dockCrossfade.isEmphasized)
        #expect(parts.dockCrossfade.maskImage === parts.dock.maskImage)
    }

    @Test func preparingLeavesTheSwipesBlendUntouched() throws {
        let docking = Docking()
        try #require(docking.rendersColour)
        let parts = docking.prepared()
        let blend = FloatingSidebarSurface.pagingBlend(progress: 0.95)
        #expect(parts.dock.alphaValue == 0 && parts.dockCrossfade.alphaValue == 0 && !parts.dockCrossfade.isHidden)
        #expect(Self.near(parts.base.alphaValue, blend.base) && Self.near(parts.crossfade.alphaValue, blend.incoming))
    }

    @Test func dockingFadesBothBlursOutAndTheWindowsMaterialsInToTheSwipesProgress() throws {
        let docking = Docking()
        try #require(docking.rendersColour)
        let parts = docking.prepared()
        docking.dock()
        #expect(parts.base.alphaValue == 0 && parts.crossfade.alphaValue == 0)
        #expect(parts.dock.alphaValue == 1 && Self.near(parts.dockCrossfade.alphaValue, 0.95))
    }

    @Test func theDockCrossfadesFadeHasNoFixedEndSoItFollowsTheSwipe() throws {
        let docking = Docking()
        try #require(docking.rendersColour)
        let parts = docking.prepared()
        docking.dock()
        let fade = try #require(parts.dockCrossfade.layer?.animation(forKey: "opacity") as? CABasicAnimation)
        #expect(fade.toValue == nil && fade.byValue == nil)
    }

    @Test(arguments: Part.allCases)
    func everyMaterialFadesOnTheGroupsTiming(_ part: Part) throws {
        let docking = Docking()
        try #require(docking.rendersColour)
        let parts = docking.prepared()
        docking.dock()
        let view = switch part { case .blur: parts.base; case .crossfade: parts.crossfade; case .dock: parts.dock; case .dockCrossfade: parts.dockCrossfade }
        let fade = try #require(view.layer?.animation(forKey: "opacity") as? CABasicAnimation)
        #expect(Self.near(fade.duration, 0.08, 1e-6))
    }

    @Test func theSwipeSettlingMidDockKeepsBothBlursFadedAndMovesTheWindowsCrossfade() throws {
        let docking = Docking()
        try #require(docking.rendersColour)
        let parts = docking.prepared()
        docking.dock()
        docking.swipe(0.97)
        #expect(parts.base.alphaValue == 0 && parts.crossfade.alphaValue == 0)
        #expect(Self.near(parts.dockCrossfade.alphaValue, 0.97))
    }

    @Test func theCommitAndTheEndOfPreparationKeepTheFadesAndBothDockedStyles() throws {
        let docking = Docking()
        try #require(docking.rendersColour)
        let parts = docking.prepared()
        docking.dock()
        docking.swipe(0.97)
        docking.surface.theme = docking.dark
        docking.surface.preparesFloatingDock = false
        #expect(parts.base.alphaValue == 0 && parts.crossfade.alphaValue == 0)
        #expect(parts.dock.alphaValue == 1 && Self.near(parts.dockCrossfade.alphaValue, 0.97))
        #expect(parts.dock.material.rawValue == 1 && parts.dockCrossfade.material.rawValue == 2)
    }

    @Test func aReversedDockRestoresTheSwipesBlendAndHidesTheWindowsMaterials() throws {
        let docking = Docking()
        try #require(docking.rendersColour)
        let parts = docking.prepared()
        docking.dock()
        docking.swipe(0.97)
        docking.surface.preparesFloatingDock = false
        docking.surface.docksFloatingSurface = false
        let resumed = FloatingSidebarSurface.pagingBlend(progress: 0.97)
        #expect(Self.near(parts.base.alphaValue, resumed.base) && Self.near(parts.crossfade.alphaValue, resumed.incoming))
        #expect(parts.dock.isHidden && parts.dockCrossfade.isHidden)
        #expect([parts.base, parts.crossfade, parts.dock, parts.dockCrossfade].allSatisfy { $0.layer?.animation(forKey: "opacity") == nil })
    }

    @Test func aSwipeEndingMidDockLetsTheCrossfadeFinishFading() throws {
        let docking = Docking()
        try #require(docking.rendersColour)
        let parts = docking.prepared()
        docking.dock()
        docking.surface.theme = docking.dark
        docking.surface.pagingTransition = nil
        #expect(!parts.crossfade.isHidden && parts.crossfade.alphaValue == 0)
        #expect(parts.crossfade.layer?.animation(forKey: "opacity") != nil)
    }

    @Test func aSwipeEndingMidDockSettlesTheWindowsMaterialOnTheArrivedSpacesStyle() throws {
        let docking = Docking()
        try #require(docking.rendersColour)
        let parts = docking.prepared()
        docking.dock()
        docking.surface.theme = docking.dark
        docking.surface.pagingTransition = nil
        #expect(parts.dockCrossfade.isHidden)
        #expect(parts.dock.material.rawValue == 2 && parts.dock.appearance?.name == .darkAqua)
    }

    @Test func reversingADockAfterTheSwipeEndedHidesTheCrossfadeAndShowsTheWholeBlur() throws {
        let docking = Docking()
        try #require(docking.rendersColour)
        let parts = docking.prepared()
        docking.dock()
        docking.surface.pagingTransition = nil
        docking.surface.docksFloatingSurface = false
        #expect(parts.crossfade.isHidden && parts.base.alphaValue == 1)
        #expect(parts.crossfade.layer?.animation(forKey: "opacity") == nil)
    }

    @Test func pagesComingToAgreeMidDockLetTheCrossfadeFinishFading() throws {
        let docking = Docking()
        try #require(docking.rendersColour)
        let parts = docking.prepared()
        docking.swipe(0.97)
        docking.dock()
        docking.swipe(0.97, to: docking.alsoLight)
        #expect(!parts.crossfade.isHidden && parts.crossfade.alphaValue == 0)
        #expect(parts.crossfade.layer?.animation(forKey: "opacity") != nil)
        docking.surface.docksFloatingSurface = false
        #expect(parts.crossfade.isHidden && parts.base.alphaValue == 1)
    }

    @Test func aDockSettlingMidSwipeHidesEveryCrossfadeAndRestoresTheBlur() throws {
        let docking = Docking()
        try #require(docking.rendersColour)
        let parts = docking.prepared()
        docking.swipe(0.97)
        docking.surface.docksFloatingSurface = true
        docking.surface.floatingCornerRadius = nil
        docking.surface.docksFloatingSurface = false
        #expect(parts.crossfade.isHidden && parts.base.alphaValue == 1)
        #expect(parts.dock.isHidden && parts.dockCrossfade.isHidden)
    }

    @MainActor final class HandOff {
        struct Look: Equatable { var kind: Int, side: NSAppearance.Name?, alpha: CGFloat }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300), styleMask: [.borderless], backing: .buffered, defer: true)
        let root = ThemeRendererView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        let surface = ThemeRendererView(frame: NSRect(x: 5, y: 5, width: 200, height: 290))
        let uncoloured: SpaceTheme, light: SpaceTheme

        init() {
            window.isReleasedWhenClosed = false
            window.appearance = NSAppearance(named: .aqua)
            window.contentView = root
            root.addSubview(surface)
            surface.coordinateSpace = root
            var uncoloured = SpaceTheme(); uncoloured.appearance = .dark
            var light = SpaceTheme.singleColor(ThemeColor(red: 0.8, green: 0.88, blue: 0.97)!); light.appearance = .light
            (self.uncoloured, self.light) = (uncoloured, light)
            root.theme = uncoloured; surface.theme = uncoloured
            surface.floatingCornerRadius = FloatingSidebarSurface.cornerRadius
            surface.drawsBackground = true
        }

        deinit { MainActor.assumeIsolated { window.contentView = nil } }

        var rendersColour: Bool { surface.subviews.contains { $0 is MTKView } }
        func publish(_ progress: CGFloat?) {
            let transition = progress.map { ThemePagingTransition(from: uncoloured, theme: light, progress: $0) }
            root.pagingTransition = transition; surface.pagingTransition = transition
        }
        func dockMidSwipe() {
            publish(0.6)
            surface.preparesFloatingDock = true
            root.layoutSubtreeIfNeeded(); root.display(); CATransaction.flush()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.08
                context.allowsImplicitAnimation = true
                surface.docksFloatingSurface = true
            }
        }
        private func looks(_ views: [NSVisualEffectView]) -> [Look] {
            views.filter { !$0.isHidden }.map { Look(kind: $0.material.rawValue, side: $0.appearance?.name, alpha: $0.alphaValue) }
        }
        var windowBlend: [Look] { looks(root.subviews.compactMap { $0 as? NSVisualEffectView }) }
        var docked: [Look] { looks(Array(surface.subviews.compactMap { $0 as? NSVisualEffectView }.suffix(2))) }
    }

    @Test(arguments: [CGFloat(0.6), 0.8, 0.97])
    func theDockingSidebarsMaterialsMatchTheWindowsOwnBlendAsTheSwipeSettles(_ progress: CGFloat) throws {
        let handOff = HandOff()
        try #require(handOff.rendersColour)
        handOff.dockMidSwipe()
        handOff.publish(progress)
        #expect(handOff.windowBlend.count == 2)
        #expect(handOff.docked == handOff.windowBlend)
    }

    @Test func theCommitLeavesBothBlendsAlike() throws {
        let handOff = HandOff()
        try #require(handOff.rendersColour)
        handOff.dockMidSwipe()
        handOff.publish(0.97)
        handOff.root.theme = handOff.light; handOff.surface.theme = handOff.light
        #expect(handOff.docked == handOff.windowBlend)
    }

    @Test func onceSettledTheSidebarDrawsNoBackdropAndTheWindowsBlendShowsThrough() throws {
        let handOff = HandOff()
        try #require(handOff.rendersColour)
        handOff.dockMidSwipe()
        handOff.publish(0.97)
        handOff.root.theme = handOff.light; handOff.surface.theme = handOff.light
        handOff.surface.drawsBackground = false
        handOff.surface.floatingCornerRadius = nil
        handOff.surface.docksFloatingSurface = false
        #expect(handOff.surface.subviews.compactMap { $0 as? NSVisualEffectView }.allSatisfy { $0.isHidden })
        #expect(handOff.windowBlend.count == 2)
        handOff.publish(nil)
        #expect(handOff.windowBlend.count == 1)
    }
}
