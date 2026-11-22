import AppKit
import Testing
@testable import ParcKit

@MainActor
struct SiteControlCenterArtworkTests {
    private func library() throws -> SiteControlCenterArtwork.Library {
        let directory = try #require(Bundle.module.url(forResource: "SiteControlCenter", withExtension: nil))
        return SiteControlCenterArtwork.Library(directory: directory)
    }

    @Test func theAppLoadsItsArtworkFromTheBundlesSiteControlCenterResources() {
        #expect(SiteControlCenterArtwork.directory
            == Bundle.main.resourceURL?.appendingPathComponent("SiteControlCenter", isDirectory: true))
    }

    @Test(arguments: [("icon-control-center", 18), ("copy-url", 19), ("capture-full-page", 19),
                      ("popup-blocked", 18), ("redirect-blocked", 18)])
    func eachGlyphLoadsAsATemplateWithItsRetinaAndVectorRenditions(_ name: String, _ side: Int) throws {
        let image = try #require(try library().image(name))

        #expect(image.size == NSSize(width: side, height: side))
        #expect(image.isTemplate)
        #expect(image.representations.contains { $0.pixelsWide == side * 2 })
        #expect(image.representations.contains { $0 is NSPDFImageRep })
    }

    @Test func theEntryGlyphIsTheCachedBundledImage() throws {
        let artwork = try library()
        let glyph = try #require(artwork.controlCenter)
        #expect(glyph === artwork.image("icon-control-center"))
    }

    @Test func aMissingGlyphLoadsNothing() throws {
        #expect(try library().image("missing") == nil)
        #expect(SiteControlCenterArtwork.Library(directory: nil).controlCenter == nil)
    }
}
