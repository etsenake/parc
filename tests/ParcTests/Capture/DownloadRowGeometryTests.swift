import AppKit
import Testing
@testable import Parc
@testable import ParcCore
@testable import ParcKit
@testable import ParcLibrary

struct DownloadRowGeometryTests {
    typealias Fixture = DownloadListPresentationTests.Fixture

    @MainActor private func favicon() throws -> NSImage {
        try #require(LibraryArtwork(folder: LibraryArtwork.directory(in: .module)).emptyFavicon)
    }

    @MainActor private func placeholder(in fixture: Fixture) throws -> CALayer {
        let cell = try fixture.cell(4)
        let artwork = try #require(cell.subviews.compactMap { $0 as? DownloadArtworkView }.first)
        artwork.artwork = LibraryArtwork(folder: LibraryArtwork.directory(in: .module))
        cell.layoutSubtreeIfNeeded()
        artwork.layout()
        return try #require(artwork.layer?.sublayers?.first)
    }

    @MainActor @Test func theLibraryUsesItsBundlesArtworkDirectory() {
        #expect(LibraryArtwork.directory == Bundle.main.resourceURL?.appendingPathComponent("Library", isDirectory: true))
    }

    @MainActor @Test func theEmptyFaviconKeepsItsOriginalRetinaAndStandardRenditions() throws {
        let image = try favicon()
        #expect(image.isTemplate && image.size == NSSize(width: 14, height: 14))
        #expect(image.representations.compactMap { ($0 as? NSBitmapImageRep)?.pixelsWide }.sorted() == [14, 28])
    }

    @MainActor @Test func theEmptyFaviconIsCenteredAndMasksTheSemanticPrimaryTint() throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        let layer = try placeholder(in: fixture)
        #expect(!layer.isHidden && layer.frame == NSRect(x: 9, y: 9, width: 14, height: 14))
        #expect(layer.mask?.frame == layer.bounds)
        #expect(layer.backgroundColor == NSColor.labelColor.cgColor)
    }

    @MainActor @Test func theEmptyFaviconHasClearCornersAndTranslucentInk() throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        let layer = try placeholder(in: fixture)
        let side = 28
        let context = try #require(CGContext(data: nil, width: side, height: side, bitsPerComponent: 8,
            bytesPerRow: side * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.scaleBy(x: 2, y: 2)
        layer.render(in: context)
        let bytes = try #require(context.data).assumingMemoryBound(to: UInt8.self)
        func alpha(_ x: Int, _ y: Int) -> Int { Int(bytes[(y * side + x) * 4 + 3]) }
        #expect(abs(Double(alpha(14, 14)) - NSColor.labelColor.alphaComponent * 72) < 2)
        #expect(alpha(0, 0) == 0 && alpha(27, 27) == 0)
    }

    struct Slot: Sendable, CustomTestStringConvertible {
        let width: CGFloat
        let row: Int
        var testDescription: String { "row \(row) at \(Int(width))" }
        static let all = [CGFloat(320), 400].flatMap { width in (1...4).map { Slot(width: width, row: $0) } }
    }

    @MainActor private func laidOut(_ slot: Slot) throws -> (Fixture, NSView) {
        let fixture = try Fixture()
        fixture.view.frame.size.width = slot.width
        fixture.view.needsLayout = true
        fixture.view.layoutSubtreeIfNeeded()
        let cell = try fixture.cell(slot.row)
        cell.needsLayout = true
        cell.layoutSubtreeIfNeeded()
        return (fixture, cell)
    }

    @MainActor @Test(arguments: Slot.all)
    func theRowControlsStayInsideTheLibraryBounds(_ slot: Slot) throws {
        let (fixture, cell) = try laidOut(slot)
        defer { fixture.teardown() }
        #expect(cell.subviews.allSatisfy { $0.isHidden || ($0.frame.minX >= 0 && $0.frame.maxX <= cell.bounds.width + 1) })
    }

    @MainActor @Test(arguments: Slot.all)
    func theListUsesTheCompactRowHeight(_ slot: Slot) throws {
        let (fixture, _) = try laidOut(slot)
        defer { fixture.teardown() }
        #expect(fixture.view.tableView(fixture.table, heightOfRow: slot.row) == 56)
    }

    @MainActor @Test(arguments: Slot.all)
    func theRowKeepsItsTwoLineTypeHierarchy(_ slot: Slot) throws {
        let (fixture, cell) = try laidOut(slot)
        defer { fixture.teardown() }
        let labels = fixture.labels(cell)
        #expect(labels.count == 2 && labels[0].font?.pointSize == 14 && labels[1].font?.pointSize == 12)
    }

    @MainActor @Test(arguments: Slot.all)
    func theTitleAndSubtitleLinesAreTwoPointsApart(_ slot: Slot) throws {
        let (fixture, cell) = try laidOut(slot)
        defer { fixture.teardown() }
        let labels = fixture.labels(cell)
        let font = try #require(labels[0].font)
        let line = font.ascender - font.descender + font.leading
        #expect(abs(labels[1].frame.minY - labels[0].frame.minY - line - 2) <= 0.5)
    }

    @MainActor @Test(arguments: Slot.all)
    func theFileImageIsTwentyFourPointsWhileOtherArtworkKeepsThirtyTwo(_ slot: Slot) throws {
        let (fixture, cell) = try laidOut(slot)
        defer { fixture.teardown() }
        let image = try #require(cell.subviews.compactMap { $0 as? NSImageView }.first)
        let side: CGFloat = slot.row == 1 ? 24 : 32
        #expect(image.frame.size == NSSize(width: side, height: side))
    }

    @MainActor @Test(arguments: Slot.all)
    func everyRowStateHasOnlyTheConditionalMoreTarget(_ slot: Slot) throws {
        let (fixture, cell) = try laidOut(slot)
        defer { fixture.teardown() }
        let buttons = cell.subviews.compactMap { $0 as? NSButton }
        let shown = buttons.filter { !$0.isHidden }
        #expect(buttons.count == 1)
        #expect(shown.allSatisfy {
            $0.parcTooltip?.label == "More download actions" && $0.toolTip == nil
                && $0.frame.size == NSSize(width: 32, height: 32) && $0.frame.maxY <= 56
        })
    }

    @MainActor @Test(arguments: Slot.all)
    func theNativeItemLabelOwnsTextAndArtworkSemanticsOnce(_ slot: Slot) throws {
        let (fixture, cell) = try laidOut(slot)
        defer { fixture.teardown() }
        let image = try #require(cell.subviews.compactMap { $0 as? NSImageView }.first)
        #expect(fixture.labels(cell).allSatisfy { $0.isAccessibilityHidden() } && image.isAccessibilityHidden())
    }

    @MainActor @Test(arguments: Slot.all)
    func longTitlesCannotOverlapTheActions(_ slot: Slot) throws {
        let (fixture, cell) = try laidOut(slot)
        defer { fixture.teardown() }
        let title = try #require(fixture.labels(cell).first)
        let action = cell.subviews.compactMap { $0 as? NSButton }.filter { !$0.isHidden }.min { $0.frame.minX < $1.frame.minX }
        #expect(action.map { title.frame.maxX + 8 <= $0.frame.minX } ?? (title.frame.maxX <= cell.bounds.width - 12))
    }

    @MainActor @Test(arguments: Slot.all)
    func theSourceStaysAvailableWithoutAThirdVisualLine(_ slot: Slot) throws {
        let (fixture, cell) = try laidOut(slot)
        defer { fixture.teardown() }
        #expect(fixture.labels(cell)[1].toolTip?.contains("example.invalid") == true)
    }

    @MainActor @Test(arguments: Slot.all)
    func theSourceContextIsSpokenOncePerRow(_ slot: Slot) throws {
        let (fixture, cell) = try laidOut(slot)
        defer { fixture.teardown() }
        #expect((cell.accessibilityLabel() ?? "").components(separatedBy: "example.invalid").count == 2)
    }

    @MainActor @Test(arguments: Slot.all)
    func theNativeCellAccessibilityExcludesDecorativeTextAndArtwork(_ slot: Slot) throws {
        let (fixture, cell) = try laidOut(slot)
        defer { fixture.teardown() }
        let children = cell.accessibilityChildren() ?? []
        #expect(children.allSatisfy { $0 is NSButton } && children.count <= 1)
    }
}
