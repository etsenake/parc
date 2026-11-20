import CoreGraphics
import Foundation
import ImageIO

@main
struct NotePageCoverGalleryTests {
    static func expect(_ value: Bool, _ message: String) {
        if !value { failTest(message) }
    }

    static func pixels(_ image: CGImage) -> [UInt8] {
        let width = image.width, height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        bytes.withUnsafeMutableBytes { buffer in
            let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                    space: NoteCoverGallery.colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        return bytes
    }

    static func main() {
        let styles = NoteCoverGallery.styles
        expect(styles.count == 12, "the gallery offers a dozen covers")
        expect(Set(styles.map(\.id)).count == styles.count && Set(styles.map(\.name)).count == styles.count, "cover ids and names are unique")
        expect(Set(styles.map(\.pattern)).count == 7, "every pattern shows up at least once")
        expect(NoteCoverGallery.exportPixelSize == CGSize(width: 1500, height: 600), "covers export at Notion's recommended 1,500 px width")
        let ratio = NoteCoverGallery.thumbnailPixelSize.width / NoteCoverGallery.thumbnailPixelSize.height
        expect(abs(ratio - 2.5) < 0.001, "thumbnails share the export's 5:2 shape")
        let tile = NoteCoverGallery.style(id: "confetti")!
        for style in styles {
            guard let full = NoteCoverGallery.image(for: style, pixelSize: NoteCoverGallery.exportPixelSize, grain: nil, sand: nil) else {
                failTest("\(style.name) renders at full size")
            }
            expect(full.width == 1500 && full.height == 600, "\(style.name) renders 1500×600")
            let thumb = NoteCoverGallery.image(for: style, pixelSize: NoteCoverGallery.thumbnailPixelSize, grain: nil, sand: nil)
            expect(thumb?.width == 360 && thumb?.height == 144, "\(style.name) thumbnail renders 360×144")
            let bytes = pixels(full)
            var minimum = 255, maximum = 0
            var opaque = true
            for index in stride(from: 0, to: bytes.count, by: 4 * 97) {
                let luma = (Int(bytes[index]) * 3 + Int(bytes[index + 1]) * 6 + Int(bytes[index + 2])) / 10
                minimum = min(minimum, luma); maximum = max(maximum, luma)
                if bytes[index + 3] != 255 { opaque = false }
            }
            expect(opaque, "\(style.name) is fully opaque")
            expect(maximum - minimum > 12, "\(style.name) isn't a flat fill (spread \(maximum - minimum))")
        }
        let first = NoteCoverGallery.image(for: tile, pixelSize: NoteCoverGallery.thumbnailPixelSize, grain: nil, sand: nil)!
        let second = NoteCoverGallery.image(for: tile, pixelSize: NoteCoverGallery.thumbnailPixelSize, grain: nil, sand: nil)!
        expect(pixels(first) == pixels(second), "the same cover always draws the same pixels")
        let other = NoteCoverGallery.image(for: NoteCoverGallery.style(id: "indigo-hour")!, pixelSize: NoteCoverGallery.thumbnailPixelSize,
                                           grain: nil, sand: nil)!
        expect(pixels(first) != pixels(other), "different covers draw differently")
        guard let data = NoteCoverGallery.image(for: tile, pixelSize: NoteCoverGallery.exportPixelSize, grain: nil, sand: nil)
            .flatMap({ NoteCoverGallery.encoded($0) }) else { failTest("covers encode to JPEG") }
        expect(data.count > 10_000 && data.count < 1_500_000, "a cover JPEG stays a sensible size (\(data.count) bytes)")
        expect(data.starts(with: [0xFF, 0xD8, 0xFF]), "covers are JPEG files")
        let source = CGImageSourceCreateWithData(data as CFData, nil)
        let decoded = source.flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) }
        expect(decoded?.width == 1500 && decoded?.height == 600, "the encoded cover decodes at full size")
        var generator = NoteCoverRandom(seed: 7)
        let picks = (0..<40).map { _ in NoteCoverGallery.random(using: &generator).id }
        expect(Set(picks).count > 6 && picks.allSatisfy { NoteCoverGallery.style(id: $0) != nil }, "random covers come from the gallery")
        expect(NoteCoverGallery.suggestedName(for: tile) == "Cover Confetti", "saved covers get a friendly name")
        print("NotePageCoverGalleryTests passed")
    }
}
