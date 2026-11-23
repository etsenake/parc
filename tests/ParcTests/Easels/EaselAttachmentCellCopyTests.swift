import AppKit
import Foundation
import Testing
@testable import ParcCore
@testable import ParcEasels

@MainActor
struct EaselAttachmentCellCopyTests {
    @Test func aCopiedInlineCellIsTheSameSafeCell() throws {
        var original: EaselInlineCell? = EaselInlineCell(inline: .equation("x^2 + y^2 = z^2 + a + b + c + d + e"))
        _ = original?.cellSize()
        let copy = try #require(original?.copy() as? EaselInlineCell)
        #expect(copy === original)
        original = nil
        #expect(copy.inline.tex == "x^2 + y^2 = z^2 + a + b + c + d + e")
        #expect(copy.cellSize().width > 0)
    }

    @Test func aCopiedPictureCellIsTheSameSafeCell() throws {
        let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2, bitsPerSample: 8,
            samplesPerPixel: 3, hasAlpha: false, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 6, bitsPerPixel: 24))
        bitmap.bitmapData?.initialize(repeating: 128, count: 12)
        let source = try EaselTextAttachments.image(data: try #require(bitmap.representation(using: .png, properties: [:])))
        var original: EaselImageAttachmentCell? = EaselImageAttachmentCell(source: source)
        original?.canvasWidth = 300
        let copy = try #require(original?.copy() as? EaselImageAttachmentCell)
        #expect(copy === original)
        original = nil
        #expect(copy.canvasWidth == 300)
        #expect(copy.cellSize().width == 300)
    }
}
