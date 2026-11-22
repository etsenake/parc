import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import Parc
@testable import ParcNotes

struct NotePageCoverGalleryTests {
    static let styleIDs = NoteCoverGallery.styles.map(\.id)

    func pixels(_ image: CGImage) -> [UInt8] {
        let width = image.width, height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        bytes.withUnsafeMutableBytes { buffer in
            let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                    space: NoteCoverGallery.colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        return bytes
    }

    func render(_ id: String, size: CGSize) throws -> CGImage {
        let style = try #require(NoteCoverGallery.style(id: id))
        return try #require(NoteCoverGallery.image(for: style, pixelSize: size, grain: nil, sand: nil))
    }

    @Test func coverIdsAreUnique() {
        let styles = NoteCoverGallery.styles
        #expect(Set(styles.map(\.id)).count == styles.count)
    }

    @Test func coverNamesAreUnique() {
        let styles = NoteCoverGallery.styles
        #expect(Set(styles.map(\.name)).count == styles.count)
    }

    @Test func everyPatternShowsUpAtLeastOnce() {
        let expected: Set<NoteCoverStyle.Pattern> = [.mesh, .waves, .confetti, .stripes, .grid, .ripples, .paper]
        #expect(Set(NoteCoverGallery.styles.map(\.pattern)) == expected)
    }

    @Test func coversExportAtNotionsRecommendedWidth() {
        #expect(NoteCoverGallery.exportPixelSize == CGSize(width: 1500, height: 600))
    }

    @Test func thumbnailsShareTheExportsFiveByTwoShape() {
        let size = NoteCoverGallery.thumbnailPixelSize
        #expect(abs(size.width / size.height - 2.5) < 0.001)
    }

    @Test(arguments: NotePageCoverGalleryTests.styleIDs)
    func aCoverRendersAtTheExportSize(id: String) throws {
        let full = try render(id, size: NoteCoverGallery.exportPixelSize)
        #expect(full.width == 1500)
        #expect(full.height == 600)
    }

    @Test(arguments: NotePageCoverGalleryTests.styleIDs)
    func aCoverRendersAtTheThumbnailSize(id: String) throws {
        let thumbnail = try render(id, size: NoteCoverGallery.thumbnailPixelSize)
        #expect(thumbnail.width == 360)
        #expect(thumbnail.height == 144)
    }

    @Test(arguments: NotePageCoverGalleryTests.styleIDs)
    func aCoverIsFullyOpaque(id: String) throws {
        let bytes = pixels(try render(id, size: NoteCoverGallery.thumbnailPixelSize))
        #expect(stride(from: 3, to: bytes.count, by: 4).allSatisfy { bytes[$0] == 255 })
    }

    @Test(arguments: NotePageCoverGalleryTests.styleIDs)
    func aCoverIsNotAFlatFill(id: String) throws {
        let bytes = pixels(try render(id, size: NoteCoverGallery.thumbnailPixelSize))
        let lumas = stride(from: 0, to: bytes.count, by: 4).map { (Int(bytes[$0]) * 3 + Int(bytes[$0 + 1]) * 6 + Int(bytes[$0 + 2])) / 10 }
        #expect(Set(lumas).count > 1)
    }

    @Test func theSameCoverAlwaysDrawsTheSamePixels() throws {
        let first = try render("confetti", size: NoteCoverGallery.thumbnailPixelSize)
        let second = try render("confetti", size: NoteCoverGallery.thumbnailPixelSize)
        #expect(pixels(first) == pixels(second))
    }

    @Test func differentCoversDrawDifferently() throws {
        let first = try render("confetti", size: NoteCoverGallery.thumbnailPixelSize)
        let other = try render("indigo-hour", size: NoteCoverGallery.thumbnailPixelSize)
        #expect(pixels(first) != pixels(other))
    }

    @Test func coversEncodeToJpegFiles() throws {
        let data = try #require(NoteCoverGallery.encoded(try render("confetti", size: NoteCoverGallery.thumbnailPixelSize)))
        #expect(data.starts(with: [0xFF, 0xD8, 0xFF]))
    }

    @Test func anEncodedCoverDecodesAtItsSize() throws {
        let data = try #require(NoteCoverGallery.encoded(try render("confetti", size: NoteCoverGallery.thumbnailPixelSize)))
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let decoded = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(decoded.width == 360)
        #expect(decoded.height == 144)
    }

    @Test func randomCoversComeFromTheGallery() {
        var generator = NoteCoverRandom(seed: 7)
        let picks = (0..<40).map { _ in NoteCoverGallery.random(using: &generator).id }
        #expect(picks.allSatisfy { NoteCoverGallery.style(id: $0) != nil })
    }

    @Test func randomCoversVary() {
        var generator = NoteCoverRandom(seed: 7)
        let picks = (0..<40).map { _ in NoteCoverGallery.random(using: &generator).id }
        #expect(Set(picks).count > 1)
    }

    @Test func savedCoversGetAFriendlyName() throws {
        #expect(NoteCoverGallery.suggestedName(for: try #require(NoteCoverGallery.style(id: "confetti"))) == "Cover Confetti")
    }
}
