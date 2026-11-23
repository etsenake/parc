import AppKit
import ImageIO
import Testing
@testable import ParcEasels
@testable import ParcLibrary

extension CapturePortraitTestsSupport {
    struct CaptureSharpnessTests {
        static let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

        @MainActor static func pattern(width: Int, height: Int, space: CGColorSpace = sRGB) -> CGImage {
            let context = PortraitFixture.context(width: width, height: height, space: space)
            let bytes = context.data!.assumingMemoryBound(to: UInt8.self)
            for y in 0..<height {
                for x in 0..<width {
                    let index = y * context.bytesPerRow + x * 4
                    bytes[index] = (x + y) % 2 == 0 ? 255 : 0
                    bytes[index + 1] = UInt8((x &* 37 &+ y &* 11) & 255)
                    bytes[index + 2] = UInt8((x ^ (y &* 3)) & 255)
                    bytes[index + 3] = 255
                }
            }
            return context.makeImage()!
        }

        @MainActor static func noise(width: Int, height: Int) -> CGImage {
            let context = PortraitFixture.context(width: width, height: height)
            let bytes = context.data!.assumingMemoryBound(to: UInt8.self)
            var state: UInt32 = 0x9E37_79B9
            for y in 0..<height {
                for x in 0..<width {
                    let index = y * context.bytesPerRow + x * 4
                    for channel in 0..<3 {
                        state = state &* 1_664_525 &+ 1_013_904_223
                        bytes[index + channel] = UInt8(state >> 24)
                    }
                    bytes[index + 3] = 255
                }
            }
            return context.makeImage()!
        }

        @MainActor static func rows(_ image: CGImage, space: CGColorSpace) -> [[UInt8]] {
            let context = PortraitFixture.context(width: image.width, height: image.height, space: space)
            context.interpolationQuality = .none
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            let bytes = context.data!.assumingMemoryBound(to: UInt8.self)
            return (0..<image.height).map { Array(UnsafeBufferPointer(start: bytes + $0 * context.bytesPerRow, count: image.width * 4)) }
        }

        @MainActor static func decoded(_ png: Data) throws -> CGImage {
            let source = try #require(CGImageSourceCreateWithData(png as CFData, nil))
            return try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        }

        @MainActor static func dpi(_ png: Data) throws -> Double {
            let source = try #require(CGImageSourceCreateWithData(png as CFData, nil))
            let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil)) as NSDictionary
            return properties[kCGImagePropertyDPIWidth] as? Double ?? 72
        }

        @MainActor static func bitmap(_ image: CGImage, space: CGColorSpace) -> CGContext {
            let context = PortraitFixture.context(width: image.width, height: image.height, space: space)
            context.interpolationQuality = .none
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return context
        }

        @MainActor static func changedPixels(in output: CGImage, geometry: PortraitCaptureGeometry, source: CGImage) throws -> Int {
            let content = geometry.content
            let crop = try #require(output.cropping(to: CGRect(x: content.minX, y: geometry.canvas.height - content.maxY,
                                                              width: content.width, height: content.height)))
            guard crop.width == source.width, crop.height == source.height else { return source.width * source.height }
            let space = source.colorSpace ?? sRGB
            let expected = bitmap(source, space: space), actual = bitmap(crop, space: space)
            let wanted = expected.data!.assumingMemoryBound(to: UInt8.self), found = actual.data!.assumingMemoryBound(to: UInt8.self)
            let corner = Int((6 * geometry.density).rounded(.up))
            var changed = 0
            for y in 0..<source.height {
                let row = wanted + y * expected.bytesPerRow, other = found + y * actual.bytesPerRow
                if memcmp(row, other, source.width * 4) == 0 { continue }
                let rounded = y < corner || y >= source.height - corner
                for x in 0..<source.width where !(rounded && (x < corner || x >= source.width - corner)) {
                    if memcmp(row + x * 4, other + x * 4, 3) != 0 { changed += 1 }
                }
            }
            return changed
        }

        @MainActor static func framedCapture(_ source: CGImage, backingScale: CGFloat) throws -> (PortraitFixture, CapturedImage) {
            let fixture = try PortraitFixture()
            fixture.options.background = .page
            let capture = try CapturedImage(pngData: try PortraitFixture.png(source), backingScale: backingScale)
            try capture.applyFrame(fixture.composition(backingScale: backingScale))
            return (fixture, capture)
        }

        struct Source: CustomTestStringConvertible, Sendable {
            let testDescription: String
            let width: Int
            let height: Int
            let scale: CGFloat

            static let odd: [Self] = [
                .init(testDescription: "Odd Retina region", width: 801, height: 401, scale: 2),
                .init(testDescription: "Odd 3x element", width: 1000, height: 601, scale: 3),
                .init(testDescription: "Odd Retina sliver", width: 1441, height: 37, scale: 2),
                .init(testDescription: "Even Retina viewport", width: 1280, height: 800, scale: 2),
            ]
            static let large: [Self] = [
                .init(testDescription: "Wide standard display", width: 3001, height: 1999, scale: 1),
                .init(testDescription: "Big Retina window", width: 4801, height: 1351, scale: 2),
            ]
        }

        @MainActor @Test(arguments: Source.odd)
        func theFramedPNGHoldsEveryCapturedPixelUnchanged(_ sample: Source) throws {
            let source = Self.pattern(width: sample.width, height: sample.height)
            let (_, capture) = try Self.framedCapture(source, backingScale: sample.scale)
            let geometry = try #require(PortraitCaptureRenderer.geometry(pixels: CGSize(width: sample.width, height: sample.height),
                                                                        backingScale: sample.scale))
            #expect(geometry.content.size == CGSize(width: sample.width, height: sample.height))
            #expect(geometry.content.minX == geometry.content.minX.rounded() && geometry.content.minY == geometry.content.minX)
            let output = try Self.decoded(capture.pngData)
            #expect(CGFloat(output.width) == geometry.canvas.width && CGFloat(output.height) == geometry.canvas.height)
            #expect(try Self.changedPixels(in: output, geometry: geometry, source: source) == 0)
            #expect(abs(try Self.dpi(capture.pngData) - 72 * sample.scale) < 0.1)
        }

        @MainActor @Test(arguments: Source.large)
        func capturesBiggerThanTheOldSizeCapKeepFullResolution(_ sample: Source) throws {
            let source = Self.pattern(width: sample.width, height: sample.height)
            let (_, capture) = try Self.framedCapture(source, backingScale: sample.scale)
            let geometry = try #require(PortraitCaptureRenderer.geometry(pixels: CGSize(width: sample.width, height: sample.height),
                                                                        backingScale: sample.scale))
            #expect(geometry.content.size == CGSize(width: sample.width, height: sample.height))
            #expect(try Self.changedPixels(in: capture.pixels, geometry: geometry, source: source) == 0)
        }

        @MainActor @Test func aCroppedFrameKeepsEveryPixelOfTheCrop() throws {
            let source = Self.pattern(width: 801, height: 401)
            let (_, capture) = try Self.framedCapture(source, backingScale: 2)
            let crop = CGRect(x: 13, y: 7, width: 501, height: 333)
            try capture.crop(to: crop)
            let cropped = try #require(source.cropping(to: crop))
            let geometry = try #require(PortraitCaptureRenderer.geometry(pixels: crop.size, backingScale: 2))
            #expect(try Self.changedPixels(in: capture.pixels, geometry: geometry, source: cropped) == 0)
        }

        @MainActor @Test func aWideGamutCaptureKeepsItsExactPixels() throws {
            let p3 = try #require(CGColorSpace(name: CGColorSpace.displayP3))
            let source = Self.pattern(width: 641, height: 359, space: p3)
            let fixture = try PortraitFixture()
            fixture.options.background = .page
            let output = try fixture.render(backingScale: 2, source: source)
            let geometry = try #require(PortraitCaptureRenderer.geometry(pixels: CGSize(width: 641, height: 359), backingScale: 2))
            #expect(output.colorSpace?.name == CGColorSpace.displayP3)
            #expect(try Self.changedPixels(in: output, geometry: geometry, source: source) == 0)
        }

        @MainActor @Test func aTallPageKeepsEveryPixelByNarrowingItsMargin() throws {
            let geometry = try #require(PortraitCaptureRenderer.geometry(pixels: CGSize(width: 2880, height: 16000), backingScale: 2))
            #expect(geometry.content.size == CGSize(width: 2880, height: 16000) && geometry.density == 2)
            #expect(geometry.canvas.height <= 16_384 && geometry.content.minX >= 80 && geometry.fitsOutputLimits)
        }

        @MainActor @Test func aPageTooTallForAnyMarginShrinksOnlyEnoughToFit() throws {
            let geometry = try #require(PortraitCaptureRenderer.geometry(pixels: CGSize(width: 2880, height: 16384), backingScale: 2))
            #expect(geometry.fitsOutputLimits && geometry.canvas.height >= 16_380)
            #expect(geometry.density < 2 && geometry.density > 1.98)
        }

        @MainActor @Test func aHugeCaptureStaysWithinTheEaselPixelBudget() throws {
            let geometry = try #require(PortraitCaptureRenderer.geometry(pixels: CGSize(width: 9000, height: 9000), backingScale: 1))
            #expect(geometry.fitsOutputLimits && geometry.canvas.width * geometry.canvas.height > 79_000_000)
        }

        @MainActor @Test func aFrameAtTheSizeLimitIsAcceptedByEasels() throws {
            let source = Self.pattern(width: 300, height: 16_380)
            let (_, capture) = try Self.framedCapture(source, backingScale: 1)
            #expect(capture.pixels.height <= 16_384)
            #expect(try EaselImagePlacement.pixelSize(capture.pngData).height == CGFloat(capture.pixels.height))
        }

        @MainActor @Test func aFrameOverTheByteLimitShrinksUntilItFitsAndKeepsItsScreenSize() throws {
            let fixture = try PortraitFixture()
            fixture.options.background = .page
            let source = Self.noise(width: 300, height: 300)
            let full = try #require(PortraitCaptureRenderer.geometry(pixels: CGSize(width: 300, height: 300), backingScale: 2))
            let (image, png) = try CapturedImage.framed(source, fixture.composition(backingScale: 2), maximumBytes: 100_000)
            #expect(png.count <= 100_000)
            #expect(CGFloat(image.width) < full.canvas.width)
            let points = CGFloat(image.width) * 72 / CGFloat(try Self.dpi(png))
            #expect(abs(points - full.canvas.width / 2) < 2)
        }

        @MainActor @Test func aPreviewThatFitsOnScreenIsTheFinalImage() throws {
            let fixture = try PortraitFixture()
            fixture.options.background = .page
            let source = Self.pattern(width: 801, height: 401)
            let final = try fixture.render(backingScale: 2, source: source)
            let preview = try PortraitCaptureRenderer.render(source: source, options: fixture.options, palette: fixture.palette,
                pageColor: .green, desktop: nil, backingScale: 2, fitting: CGSize(width: 4000, height: 4000))
            #expect(Self.rows(preview, space: Self.sRGB) == Self.rows(final, space: Self.sRGB))
        }

        @MainActor @Test func aPreviewFillsTheDevicePixelsItIsShownAt() throws {
            let fixture = try PortraitFixture()
            fixture.options.background = .page
            let source = Self.pattern(width: 1441, height: 901)
            let box = CGSize(width: 1200, height: 900)
            let full = try #require(PortraitCaptureRenderer.geometry(pixels: CGSize(width: 1441, height: 901), backingScale: 2))
            let preview = try PortraitCaptureRenderer.render(source: source, options: fixture.options, palette: fixture.palette,
                pageColor: .green, desktop: nil, backingScale: 2, fitting: box)
            #expect(preview.width == 1200 && abs(CGFloat(preview.height) - full.canvas.height * 1200 / full.canvas.width) < 1)
        }

        @MainActor @Test func theLivePreviewFollowsThePictureSize() throws {
            _ = NSApplication.shared
            let fixture = try PortraitFixture()
            let view = PortraitCaptureView(source: fixture.source, pageColor: .green, composition: fixture.composition(),
                                           previewPixels: CGSize(width: 200, height: 200), defaults: fixture.defaults)
            let first = try #require(view.previewImage)
            #expect(first.width == 200 && first.height == 120)
            view.previewPixels = CGSize(width: 300, height: 300)
            view.harnessFraction(0.5)
            let second = try #require(view.previewImage)
            #expect(second.width == 300 && second.height == 180)
        }

        @MainActor @Test func thePictureShowsAnImageOfItsOwnPixelSizeAsIs() {
            let image = Self.pattern(width: 64, height: 32)
            #expect(CapturePictureView.displayed(image, pixels: CGSize(width: 64, height: 32)) === image)
        }

        @MainActor @Test func thePictureShowsANearlyMatchingImagePixelForPixel() throws {
            let image = Self.pattern(width: 65, height: 33)
            let shown = try #require(CapturePictureView.displayed(image, pixels: CGSize(width: 64, height: 32)))
            #expect(shown.width == 64 && shown.height == 32)
            let expected = Self.rows(image, space: Self.sRGB), actual = Self.rows(shown, space: Self.sRGB)
            #expect((0..<32).allSatisfy { actual[$0] == Array(expected[$0][4...]) })
        }

        @MainActor @Test func thePictureDownsamplesToExactlyItsPixels() throws {
            let image = Self.pattern(width: 400, height: 240)
            let shown = try #require(CapturePictureView.displayed(image, pixels: CGSize(width: 301, height: 181)))
            #expect(shown.width == 301 && shown.height == 181)
        }

        @MainActor @Test func thePictureReportsItsPixelSizeOncePerChange() {
            let view = CapturePictureView(frame: .zero)
            var reports: [CGSize] = []
            view.onPixelSizeChange = { reports.append($0) }
            view.setFrameSize(NSSize(width: 120, height: 80))
            view.setFrameSize(NSSize(width: 120, height: 80))
            #expect(reports == [view.pixelSize] && view.pixelSize.width >= 120)
        }

        @MainActor @Test func aMovingPictureReportsItsSizeOnlyOnceItSettles() {
            let view = CapturePictureView(frame: .zero)
            var reports: [CGSize] = []
            view.onPixelSizeChange = { reports.append($0) }
            view.keepsRendering = true
            view.setFrameSize(NSSize(width: 300, height: 200))
            view.setFrameSize(NSSize(width: 240, height: 160))
            #expect(reports.isEmpty)
            view.keepsRendering = false
            #expect(reports == [view.pixelSize])
        }
    }
}
