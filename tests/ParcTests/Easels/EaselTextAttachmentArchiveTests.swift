import AppKit
import Foundation
import Testing
@testable import ParcCore
@testable import ParcEasels

@MainActor
struct EaselTextAttachmentArchiveTests {
    private static var png: Data {
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2, bitsPerSample: 8,
            samplesPerPixel: 3, hasAlpha: false, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 6, bitsPerPixel: 24)!
        bitmap.bitmapData!.initialize(repeating: 128, count: 12)
        return bitmap.representation(using: .png, properties: [:])!
    }

    private func decoded(_ value: NSAttributedString) throws -> NSAttributedString {
        let data = try NSKeyedArchiver.archivedData(withRootObject: value, requiringSecureCoding: false)
        let unarchiver = try NSKeyedUnarchiver(forReadingFrom: data)
        unarchiver.requiresSecureCoding = false
        return try #require(unarchiver.decodeObject(forKey: NSKeyedArchiveRootObjectKey) as? NSAttributedString)
    }

    @Test func anArchivedInlineMentionComesBackAsPlainText() throws {
        let result = try decoded(EaselInlineText.character(.equation("x^2"), attributes: [:]))
        #expect(result.length == 1)
        #expect(EaselInlineText.inline(at: 0, in: result) == nil)
    }

    @Test func anArchivedPictureComesBackAsPlainText() throws {
        let source = try EaselTextAttachments.image(data: Self.png)
        let result = try decoded(EaselTextAttachments.character(source, attributes: [:]))
        #expect(result.length == 1)
        #expect(!EaselTextAttachments.hasImages(result))
    }
}
