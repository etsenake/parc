import AppKit
import Testing
@testable import Parc

struct NavigationLoadingTestsArtwork {
    private typealias GlyphScene = NavigationLoadingTestsSupport.GlyphScene

    @MainActor private static var fixtureArtwork: URL? { NavigationControlArtwork.resourcesDirectory(in: .module) }

    @MainActor @Test func theForceReloadArtworkLoadsFromTheBundlesNavigationControlsResourcesWithItsRetinaRendition() throws {
        let force = try #require(NavigationControlArtwork.forceReload(in: Self.fixtureArtwork))
        #expect(force.size == NSSize(width: 22, height: 15))
        #expect(force.isTemplate)
        #expect(force.representations.contains { $0.pixelsWide == 44 })
    }

    @MainActor @Test func aBundleWithoutTheArtworkHasNoForceReloadImage() {
        let empty = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        #expect(NavigationControlArtwork.forceReload(in: empty) == nil)
    }

    @MainActor @Test func theForceDefaultDrawsTheForceReloadArtwork() throws {
        let s = GlyphScene()
        s.glyph.artworkDirectory = Self.fixtureArtwork
        s.glyph.update(loading: false, forceReload: true, animated: false)
        let force = try #require(NavigationControlArtwork.forceReload(in: Self.fixtureArtwork))
        #expect(s.glyph.idleImage === force)
    }

    @MainActor @Test func glyphsAreSixteenPointMedium() {
        _ = NSApplication.shared
        let glyph = ReloadGlyph(view: NSView(), pointSize: SidebarChromeLayout.navigationGlyphPointSize, rasterized: true)
        #expect(SidebarChromeLayout.navigationGlyphPointSize == 16)
        #expect(glyph.pointSize == 16)
    }

    @MainActor @Test func theArrowAndStopAreOneXAndTwoXTemplates() {
        let arrow = NavigationControlArtwork.symbol("arrow.clockwise", pointSize: 16)
        #expect(arrow?.isTemplate == true)
        #expect(arrow?.representations.count == 2)
        #expect(NavigationControlArtwork.symbol("xmark", pointSize: 16) != nil)
    }

    @MainActor @Test func theGlyphFrameIsWholePoints() {
        let arrow = NavigationControlArtwork.symbol("arrow.clockwise", pointSize: 16)
        #expect(arrow.map { $0.size.width == $0.size.width.rounded() && $0.size.height == $0.size.height.rounded() } == true)
    }

    @MainActor @Test func aSymbolIsRenderedOncePerSymbolAndSize() {
        let arrow = NavigationControlArtwork.symbol("arrow.clockwise", pointSize: 16)
        #expect(NavigationControlArtwork.symbol("arrow.clockwise", pointSize: 16) === arrow)
    }

    @MainActor @Test func theNavigationArtworkLivesInTheBundlesNavigationControlsResources() {
        #expect(NavigationControlArtwork.directory == Bundle.main.resourceURL?.appendingPathComponent("NavigationControls", isDirectory: true))
    }
}
