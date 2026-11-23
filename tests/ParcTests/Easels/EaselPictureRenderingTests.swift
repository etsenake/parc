import AppKit
import Testing
@testable import ParcCore
@testable import ParcEasels

struct EaselPictureRenderingTests {
    enum Variant: CaseIterable {
        case plain, turned, croppedAndMasked, webCard
    }

    private static let sourceWidth = 3000, sourceHeight = 1500

    private static let checkerboard: (pixels: [UInt8], png: Data) = {
        let width = sourceWidth, height = sourceHeight
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width where (x + y) % 2 == 1 {
                let index = (y * width + x) * 4
                pixels[index] = 0; pixels[index + 1] = 0; pixels[index + 2] = 0
            }
        }
        let data = Data(pixels)
        let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                            provider: CGDataProvider(data: data as CFData)!, decode: nil, shouldInterpolate: true, intent: .defaultIntent)!
        let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!
        return (pixels, png)
    }()

    @MainActor
    private final class Board {
        let session: EaselSession
        let canvas: EaselCanvasView
        let asset: String
        let item: EaselItem

        init(_ variant: Variant) throws {
            _ = NSApplication.shared
            let date = Date(timeIntervalSince1970: 0)
            session = try EaselSession(inMemory: EaselDocument(id: UUID(), title: "Pictures", createdAt: date, modifiedAt: date, items: []), assets: [:])
            asset = try session.importPNG(EaselPictureRenderingTests.checkerboard.png)
            var item: EaselItem
            switch variant {
            case .plain:
                item = EaselItem(kind: .image, frame: .init(x: 20, y: 20, width: 300, height: 150), assetID: asset)
            case .turned:
                item = EaselItem(kind: .image, frame: .init(x: 20, y: 20, width: 150, height: 300), assetID: asset, quarterTurns: 1)
            case .croppedAndMasked:
                item = EaselItem(kind: .image, frame: .init(x: 20, y: 20, width: 300, height: 150), assetID: asset,
                                 crop: .init(x: 0.25, y: 0.25, width: 0.5, height: 0.5), mask: .rounded)
            case .webCard:
                item = EaselItem(kind: .webCard, frame: .init(x: 20, y: 20, width: 300, height: 150), url: "https://example.org", assetID: asset,
                                 capturedAt: date)
            }
            self.item = item
            try session.perform("Seed") { $0.items = [item] }
            canvas = makeTestEaselCanvas(session: session)
            canvas.appearance = NSAppearance(named: .aqua)
        }

        func render(scale: CGFloat, quality: CGInterpolationQuality = .none, draw: ((NSRect) -> Void)? = nil) throws -> CGImage {
            let frame = canvas.rect(item)
            let width = Int((frame.width * scale).rounded()), height = Int((frame.height * scale).rounded())
            let context = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                                 space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                                 bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.translateBy(x: 0, y: CGFloat(height)); context.scaleBy(x: scale, y: -scale)
            context.translateBy(x: -frame.minX, y: -frame.minY)
            context.interpolationQuality = quality
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
            if let draw { draw(frame) } else { canvas.drawObject(item, showsEditor: false) }
            NSGraphicsContext.restoreGraphicsState()
            return try #require(context.makeImage())
        }
    }

    private static func grays(_ image: CGImage, inset: Double) -> [[Double]] {
        let bytes = image.dataProvider!.data! as Data
        let left = Int(Double(image.width) * inset), top = Int(Double(image.height) * inset)
        return (top..<(image.height - top)).map { y in
            (left..<(image.width - left)).map { x in Double(bytes[y * image.bytesPerRow + x * 4]) }
        }
    }

    private static func boxAverage(width: Int, height: Int) -> [[Double]] {
        let pixels = checkerboard.pixels
        let stepX = sourceWidth / width, stepY = sourceHeight / height
        return (0..<height).map { row in
            (0..<width).map { column in
                var sum = 0.0
                for y in (row * stepY)..<((row + 1) * stepY) {
                    for x in (column * stepX)..<((column + 1) * stepX) { sum += Double(pixels[(y * sourceWidth + x) * 4]) }
                }
                return sum / Double(stepX * stepY)
            }
        }
    }

    private static func meanError(_ values: [[Double]], against reference: (Int, Int) -> Double) -> Double {
        var total = 0.0, count = 0.0
        for (y, row) in values.enumerated() {
            for (x, value) in row.enumerated() { total += abs(value - reference(x, y)); count += 1 }
        }
        return total / max(1, count)
    }

    @MainActor @Test
    func aHeavilyShrunkPictureMatchesAnAreaAveragedReference() throws {
        let board = try Board(.plain)
        let rendered = try board.render(scale: 1)
        let reference = Self.boxAverage(width: rendered.width, height: rendered.height)
        let inset = 0.05
        let left = Int(Double(rendered.width) * inset), top = Int(Double(rendered.height) * inset)
        let error = Self.meanError(Self.grays(rendered, inset: inset)) { reference[$1 + top][$0 + left] }
        #expect(error < 6, "A 10× smaller checkerboard averages to even grey, like an area-averaged downsample")
        let picture = try #require(board.canvas.image(board.asset))
        let nearest = try board.render(scale: 1) { frame in
            picture.draw(in: frame, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true,
                         hints: [.interpolation: NSImageInterpolation.none.rawValue])
        }
        let aliased = Self.meanError(Self.grays(nearest, inset: inset)) { reference[$1 + top][$0 + left] }
        #expect(aliased > 60, "Nearest-neighbour sampling of the same picture flickers between black and white")
        #expect(error * 8 < aliased)
    }

    @MainActor @Test(arguments: Variant.allCases)
    func everyPictureKindDrawsCrisplyAtALargeDownscale(_ variant: Variant) throws {
        let board = try Board(variant)
        for quality in [CGInterpolationQuality.none, .low, .default] {
            let rendered = try board.render(scale: 1, quality: quality)
            let error = Self.meanError(Self.grays(rendered, inset: 0.25)) { _, _ in 127.5 }
            #expect(error < 8, "\(variant) at interpolation \(quality.rawValue) shows the checkerboard as even grey, mean error \(error)")
        }
    }

    @MainActor @Test
    func theDownsampledBitmapFollowsTheOnScreenPixelSize() throws {
        let board = try Board(.plain)
        var seen = Set<EaselPixelSize>()
        for magnification in [0.5, 1, 2] as [CGFloat] {
            for backing in [1, 2] as [CGFloat] {
                let scale = magnification * backing
                let rendered = try board.render(scale: scale)
                let error = Self.meanError(Self.grays(rendered, inset: 0.1)) { _, _ in 127.5 }
                #expect(error < 8, "Drawn crisply at \(scale)× pixels per point")
                let sizes = EaselPictureCache.shared.pixelSizes(of: board.asset)
                let target = 300 * scale
                let matched = sizes.first { CGFloat($0.width) >= target && CGFloat($0.width) < target * 1.2 }
                #expect(matched != nil, "A bitmap matched to \(target) pixels is cached, have \(sizes)")
                seen.formUnion(sizes)
            }
        }
        #expect(seen.count >= 4, "Each change of magnification or backing scale refreshes the cached bitmap")
        let before = EaselPictureCache.shared.pixelSizes(of: board.asset)
        _ = try board.render(scale: 12, quality: .high)
        #expect(EaselPictureCache.shared.pixelSizes(of: board.asset) == before, "At or above native size the original is drawn")
    }

    @MainActor @Test
    func pdfExportsKeepTheFullPicture() throws {
        let board = try Board(.plain)
        #expect(board.canvas.exportPDF(title: "Pictures") != nil)
        #expect(EaselPictureCache.shared.pixelSizes(of: board.asset).isEmpty)
    }

    @MainActor @Test
    func thePictureLevelsNeverShrinkBelowTheTarget() {
        let native = EaselPixelSize(width: 5000, height: 2500)
        #expect(EaselPictureRenderer.level(native: native, target: CGSize(width: 5000, height: 2500)) == nil)
        #expect(EaselPictureRenderer.level(native: native, target: CGSize(width: 6000, height: 3000)) == nil)
        #expect(EaselPictureRenderer.level(native: native, target: CGSize(width: 4500, height: 2250)) == nil)
        for width in stride(from: 40.0, through: 4000, by: 37) {
            let level = EaselPictureRenderer.level(native: native, target: CGSize(width: width, height: width / 2))
            #expect(level.map { Double($0.width) >= width && Double($0.width) < width * 1.2 } == true, "\(width) → \(String(describing: level))")
        }
    }

    @MainActor @Test
    func theCacheStaysWithinItsPixelBudget() throws {
        let cache = EaselPictureCache(pixelBudget: 250)
        func image() -> CGImage? {
            CGContext(data: nil, width: 10, height: 10, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?.makeImage()
        }
        let keys = (0..<3).map { EaselPictureCache.Key(asset: "a\($0)", width: 10, height: 10) }
        _ = cache.image(keys[0], make: image)
        _ = cache.image(keys[1], make: image)
        _ = cache.image(keys[0]) { Issue.record("A cached bitmap is reused"); return nil }
        _ = cache.image(keys[2], make: image)
        #expect(cache.pixelTotal <= 250)
        #expect(!cache.pixelSizes(of: "a0").isEmpty, "The most recently drawn picture stays")
        #expect(cache.pixelSizes(of: "a1").isEmpty, "The least recently drawn picture goes first")
    }
}
