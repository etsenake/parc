import AppKit
import MetalKit
import Testing
import ParcCore
@testable import Parc
@testable import ParcKit

extension ThemeRendererViewTestsSupport {
    struct ThemeRendererViewAppearanceTests {
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
}
