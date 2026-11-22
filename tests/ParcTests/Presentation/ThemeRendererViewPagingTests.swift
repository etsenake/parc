import AppKit
import MetalKit
import Testing
import ParcCore
@testable import Parc
@testable import ParcKit

extension ThemeRendererViewTestsSupport {
    struct ThemeRendererViewPagingTests {
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

        enum Suppression: CaseIterable { case floating, locked, libraryCard }

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
}
