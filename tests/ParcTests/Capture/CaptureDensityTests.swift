import AppKit
import ImageIO
import Testing
@testable import ParcLibrary

extension CapturePortraitTestsSupport {
    struct CaptureDensityTests {
        @MainActor private static func dpi(_ png: Data) throws -> Double {
            let source = try #require(CGImageSourceCreateWithData(png as CFData, nil))
            let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil)) as NSDictionary
            return properties[kCGImagePropertyDPIWidth] as? Double ?? 72
        }

        @MainActor private static func decoded(_ png: Data) throws -> CGImage {
            let source = try #require(CGImageSourceCreateWithData(png as CFData, nil))
            return try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        }

        @MainActor private static func bitmap(_ image: CGImage) -> Data {
            let context = PortraitFixture.context(width: image.width, height: image.height)
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return Data(bytes: context.data!, count: context.bytesPerRow * image.height)
        }

        struct Scale: CustomTestStringConvertible, Sendable {
            let testDescription: String
            let scale: CGFloat
            static let cases: [Self] = [.init(testDescription: "Retina", scale: 2), .init(testDescription: "3×", scale: 3)]
        }

        @MainActor @Test(arguments: Scale.cases)
        func aCaptureDeclaresTheDisplayDensitySoItOpensAtScreenSize(_ sample: Scale) throws {
            let fixture = try PortraitFixture()
            let capture = try CapturedImage(pngData: fixture.original, backingScale: sample.scale)
            #expect(abs(try Self.dpi(capture.pngData) - 72 * sample.scale) < 0.1)
            let opened = try #require(NSImage(data: capture.pngData))
            #expect(abs(opened.size.width - 320 / sample.scale) < 0.01 && abs(opened.size.height - 160 / sample.scale) < 0.01)
        }

        @MainActor @Test func declaringTheDensityKeepsEveryDevicePixel() throws {
            let fixture = try PortraitFixture()
            let capture = try CapturedImage(pngData: fixture.original, backingScale: 2)
            let output = try Self.decoded(capture.pngData)
            #expect(output.width == 320 && output.height == 160)
            #expect(Self.bitmap(output) == Self.bitmap(try Self.decoded(fixture.original)))
        }

        @MainActor @Test func aStandardDisplayCaptureKeepsItsBytes() throws {
            let fixture = try PortraitFixture()
            #expect(try CapturedImage(pngData: fixture.original, backingScale: 1).pngData == fixture.original)
        }

        @MainActor @Test func declaringTheDensityTwiceChangesNothing() throws {
            let fixture = try PortraitFixture()
            let once = CapturedImage.declaringDensity(fixture.original, backingScale: 2)
            #expect(once != fixture.original && CapturedImage.declaringDensity(once, backingScale: 2) == once)
        }

        @MainActor @Test func aRetinaCropKeepsDevicePixelsAndDensity() throws {
            let fixture = try PortraitFixture()
            let capture = try CapturedImage(pngData: fixture.original, backingScale: 2)
            try capture.crop(to: CGRect(x: 160, y: 0, width: 160, height: 160))
            #expect(capture.pixels.width == 160 && capture.pixels.height == 160)
            #expect(abs(try Self.dpi(capture.pngData) - 144) < 0.1)
        }

        @MainActor @Test func aRetinaFrameRendersEveryDevicePixelOfTheCapture() throws {
            let fixture = try PortraitFixture()
            let (capture, _) = try fixture.framed(.page, backingScale: 2)
            let geometry = try #require(PortraitCaptureRenderer.geometry(pixels: CGSize(width: 320, height: 160), backingScale: 2))
            #expect(capture.pixels.width == Int(geometry.canvas.width) && capture.pixels.height == Int(geometry.canvas.height))
            #expect(geometry.content.size == CGSize(width: 320, height: 160) && geometry.content.minX == 80)
        }

        @MainActor @Test func reopeningACaptureAfterRemovingItsFrameGivesTheDensityTaggedOriginal() throws {
            let fixture = try PortraitFixture()
            let (capture, _) = try fixture.framed(.page, backingScale: 2)
            capture.removeFrame()
            #expect(abs(try Self.dpi(capture.pngData) - 144) < 0.1 && capture.pixels.width == 320)
        }

        @MainActor @Test func aDamagedPNGIsLeftAlone() {
            let damaged = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A] + Array(repeating: 0xFF, count: 40))
            #expect(CapturedImage.declaringDensity(damaged, backingScale: 2) == damaged)
        }
    }

    struct CaptureFrameGeometryTests {
        struct Source: CustomTestStringConvertible, Sendable {
            let testDescription: String
            let size: CGSize
            static let cases: [Self] = [
                .init(testDescription: "Laptop visible area", size: .init(width: 1440, height: 900)),
                .init(testDescription: "Wide region", size: .init(width: 1800, height: 600)),
                .init(testDescription: "Square element", size: .init(width: 900, height: 900)),
                .init(testDescription: "Tall full page", size: .init(width: 1200, height: 9000)),
            ]
        }

        @MainActor @Test(arguments: Source.cases)
        func theCaptureFillsMostOfTheFrameAndKeepsItsShape(_ sample: Source) throws {
            let geometry = try #require(PortraitCaptureRenderer.geometry(pixels: sample.size, backingScale: 1))
            let canvas = geometry.canvas, content = geometry.content
            let coverage = (content.width * content.height) / (canvas.width * canvas.height)
            #expect(coverage >= 0.6)
            #expect(content.size == sample.size)
        }

        @MainActor @Test(arguments: Source.cases)
        func theBackgroundShowsEvenlyOnEverySide(_ sample: Source) throws {
            let geometry = try #require(PortraitCaptureRenderer.geometry(pixels: sample.size, backingScale: 1))
            let canvas = geometry.canvas, content = geometry.content
            let sides = [content.minX, content.minY, canvas.width - content.maxX, canvas.height - content.maxY]
            #expect(sides.allSatisfy { $0 == sides[0] } && sides[0] >= 40)
        }

        @MainActor @Test func aLaptopCaptureCoversNoticeablyMoreThanTheOldFixedMargin() throws {
            let canvas = try #require(PortraitCaptureRenderer.geometry(pixels: CGSize(width: 2880, height: 1800), backingScale: 2)).canvas
            #expect(2880 / canvas.width > 0.85 && 1800 / canvas.height > 0.8)
        }

        @MainActor @Test func framesOfTheSameAreaShareOneMarginWhateverTheirShape() {
            let wide = PortraitCaptureRenderer.margin(content: CGSize(width: 1600, height: 400))
            let square = PortraitCaptureRenderer.margin(content: CGSize(width: 800, height: 800))
            let tall = PortraitCaptureRenderer.margin(content: CGSize(width: 400, height: 1600))
            #expect(wide == square && square == tall)
        }

        @MainActor @Test func marginsStayWithinTheirBounds() {
            #expect(PortraitCaptureRenderer.margin(content: CGSize(width: 40, height: 40)) == 40)
            #expect(PortraitCaptureRenderer.margin(content: CGSize(width: 2160, height: 2160)) == 160)
        }
    }
}
