import AppKit
import QuartzCore
import Testing
@testable import Parc
@testable import ParcCore

@MainActor
struct SplitPaneMenuArtworkTests {
    private static var artwork: URL? {
        Bundle.module.url(forResource: "SplitViews", withExtension: nil)?.appendingPathComponent("SplitPaneMenu", isDirectory: true)
    }

    private static func pixels(_ image: NSImage, _ appearance: NSAppearance.Name) -> Data {
        let size = image.size
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2),
                                      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                      colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        bitmap.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSAppearance(named: appearance)!.performAsCurrentDrawingAppearance { image.draw(in: NSRect(origin: .zero, size: size)) }
        NSGraphicsContext.restoreGraphicsState()
        return Data(bytes: bitmap.bitmapData!, count: bitmap.bytesPerRow * bitmap.pixelsHigh)
    }

    private static func rendition(_ file: String) throws -> NSImage {
        let directory = try #require(artwork)
        return try #require(NSImage(contentsOf: directory.appendingPathComponent(file + "@2x.png")))
    }

    private static func menu(_ orientation: SplitOrientation, index: Int, count: Int, layout: BrowserSplitLayout? = nil) -> NSMenu {
        let directory = artwork
        return SplitPaneMenu.make(orientation: orientation, index: index, count: count, layout: layout,
                                  artwork: { SplitPaneMenuArtwork.image($0, in: directory) }) { _ in {} }
    }

    private static func shows(_ menu: NSMenu, _ names: [String?]) throws -> Bool {
        guard menu.items.count == names.count else { return false }
        for (item, name) in zip(menu.items, names) {
            guard let name else {
                if !item.isSeparatorItem { return false }
                continue
            }
            guard let image = item.image else { return false }
            if #available(macOS 27, *), item.preferredImageVisibility != .visible { return false }
            let light = try rendition(name), dark = try rendition(name + "-dark")
            let matches = image.size == light.size && pixels(image, .aqua) == pixels(light, .aqua)
                && pixels(image, .darkAqua) == pixels(dark, .darkAqua) && pixels(image, .aqua) != pixels(image, .darkAqua)
            if !matches { return false }
        }
        return true
    }

    @Test func aHorizontalSplitsItemsShowTheirArtworkLightOrDarkByAppearance() throws {
        let menu = Self.menu(.horizontal, index: 0, count: 2)
        #expect(try Self.shows(menu, ["icon-split-move-left", "icon-split-move-right", nil, "icon-split-add-right", "icon-split-add-left",
                                      "icon-split-stack-add-top", "icon-split-stack-add-bottom", nil,
                                      "icon-separate-from-split", "icon-split-vertical", nil, "icon-split-copy-links-horizontal"]))
    }

    @Test func aVerticalSplitTakesTheVerticalSeparateConvertAndCopyLinksArtwork() throws {
        let menu = Self.menu(.vertical, index: 3, count: 4)
        #expect(try Self.shows(menu, ["icon-split-move-top", "icon-split-move-bottom", nil, "icon-split-add-top", "icon-split-add-bottom",
                                      "icon-split-stack-add-left", "icon-split-stack-add-right", nil,
                                      "icon-separate-from-split-menu-bottom", "icon-split-horizontal", nil,
                                      "icon-split-copy-links-vertical"]))
    }

    @Test func stackMovesShareTheMatchingMoveArtwork() throws {
        let shape = BrowserSplitLayout.shape(orientation: .horizontal, sizes: [1, 2], factors: [0.5, 0.5], stackFactors: [[1], [0.5, 0.5]])
        let layout = BrowserSplitLayout(id: UUID(), spaceID: UUID(), tabIDs: [UUID(), UUID(), UUID()], orientation: .horizontal,
                                        widthFactors: shape.widthFactors, stacks: shape.stacks)
        let menu = Self.menu(.horizontal, index: 2, count: 3, layout: layout)
        #expect(try Self.shows(menu, ["icon-split-move-left", "icon-split-move-right", "icon-split-move-top", "icon-split-move-bottom", nil,
                                      "icon-split-add-right", "icon-split-add-left", "icon-split-stack-add-top",
                                      "icon-split-stack-add-bottom", nil, "icon-separate-from-split", "icon-split-vertical", nil,
                                      "icon-split-copy-links-horizontal"]))
    }

    @Test func aSolePanesAddRowsShowTheirArtwork() throws {
        let menu = Self.menu(.vertical, index: 0, count: 1)
        #expect(try Self.shows(menu, ["icon-split-add-left", "icon-split-add-right", nil, "icon-split-add-top", "icon-split-add-bottom"]))
    }

    @Test func artworkDrawsAtItsCatalogSizes() {
        let sizes = Self.menu(.horizontal, index: 0, count: 2).items.compactMap(\.image).map(\.size)
        let eighteen = NSSize(width: 18, height: 18)
        #expect(sizes == [eighteen, eighteen, eighteen, eighteen, eighteen, eighteen, eighteen, NSSize(width: 22, height: 22), eighteen])
    }

    @Test func aMissingDirectoryYieldsNoImage() {
        #expect(SplitPaneMenuArtwork.image("icon-split-move-left", in: nil) == nil)
    }

    @Test func aMissingDarkRenditionYieldsNoImage() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("parc-split-artwork-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = try #require(Self.artwork)
        try FileManager.default.copyItem(at: source.appendingPathComponent("icon-split-move-left.png"),
                                         to: directory.appendingPathComponent("icon-split-move-left.png"))
        #expect(SplitPaneMenuArtwork.image("icon-split-move-left", in: directory) == nil)
    }
}
