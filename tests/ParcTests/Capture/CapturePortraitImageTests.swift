import AppKit
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import Parc
@testable import ParcLibrary

extension CapturePortraitTestsSupport {
    struct CapturePortraitImageTests {
        @MainActor @Test func applyingAFrameKeepsTheOriginalAndTheUnframedBytes() throws {
            let fixture = try PortraitFixture()
            let (capture, _) = try fixture.framed()
            #expect(capture.originalPNG == fixture.original && capture.unframedPNG == fixture.original)
        }

        @MainActor @Test func applyingAFrameGrowsTheImageToTheFramedSize() throws {
            let fixture = try PortraitFixture()
            let (capture, _) = try fixture.framed()
            #expect(capture.pixels.width == 704 && capture.pixels.height == 544)
        }

        @MainActor @Test func editingAFrameNeverFramesItsPreviousOutput() throws {
            let fixture = try PortraitFixture()
            let (capture, style) = try fixture.framed()
            var edited = style
            edited.options.background = .color
            try capture.applyFrame(edited)
            #expect(capture.pixels.width == 704 && capture.pixels.height == 544)
        }

        @MainActor @Test func removingTheFrameRestoresTheOriginalBytes() throws {
            let fixture = try PortraitFixture()
            let (capture, _) = try fixture.framed()
            capture.removeFrame()
            #expect(capture.frame == nil && capture.pngData == fixture.original)
        }

        @MainActor @Test func croppingAFramedCaptureKeepsTheOriginalAndFramesTheCrop() throws {
            let fixture = try PortraitFixture()
            let (capture, _) = try fixture.framed()
            try capture.crop(to: CGRect(x: 160, y: 0, width: 160, height: 160))
            #expect(capture.originalPNG == fixture.original && capture.unframedPixels.width == 160)
            #expect(capture.pixels.width == 544 && capture.pixels.height == 544)
        }

        @MainActor @Test func theFramedCropShowsTheCroppedColor() throws {
            let fixture = try PortraitFixture()
            let (capture, _) = try fixture.framed()
            try capture.crop(to: CGRect(x: 160, y: 0, width: 160, height: 160))
            #expect(PortraitFixture.sample(capture.pixels, x: 240, y: 240)[2] > 245)
        }

        @MainActor @Test func removingTheFrameFromACropLeavesTheCroppedBytes() throws {
            let fixture = try PortraitFixture()
            let (capture, _) = try fixture.framed()
            try capture.crop(to: CGRect(x: 160, y: 0, width: 160, height: 160))
            let cropped = capture.unframedPNG
            capture.removeFrame()
            #expect(capture.pngData == cropped && capture.pixels.width == 160)
        }

        @MainActor @Test func aFrameThatCannotRenderLeavesTheCommittedCapture() throws {
            let fixture = try PortraitFixture()
            let (capture, _) = try fixture.framed()
            let committed = capture.pngData
            #expect(throws: (any Error).self) {
                try capture.applyFrame(PortraitCaptureComposition(options: fixture.options, palette: [], pageColor: nil, desktop: nil))
            }
            #expect(capture.pngData == committed && capture.frame != nil)
        }

        @MainActor @Test func anOutOfImageCropFailsAndLeavesTheCommittedCapture() throws {
            let fixture = try PortraitFixture()
            let (capture, _) = try fixture.framed()
            try capture.crop(to: CGRect(x: 160, y: 0, width: 160, height: 160))
            let committed = capture.pngData, cropped = capture.unframedPNG
            #expect(throws: (any Error).self) { try capture.crop(to: CGRect(x: 900, y: 900, width: 1, height: 1)) }
            #expect(capture.pngData == committed && capture.unframedPNG == cropped)
        }

        @MainActor @Test func recroppingToTheFullSourceRestoresTheOriginalBytes() throws {
            let fixture = try PortraitFixture()
            let (capture, _) = try fixture.framed()
            try capture.crop(to: CGRect(x: 160, y: 0, width: 160, height: 160))
            try capture.crop(to: CGRect(x: 0, y: 0, width: 320, height: 160))
            capture.removeFrame()
            #expect(capture.pngData == fixture.original)
        }

        @MainActor @Test func aTallSourceIsFramedAtTheCappedHeight() throws {
            let fixture = try PortraitFixture()
            let tall = PortraitFixture.context(width: 300, height: 4000)
            tall.setFillColor(NSColor.red.cgColor)
            tall.fill(CGRect(x: 0, y: 0, width: 300, height: 4000))
            let tallPNG = try PortraitFixture.png(tall.makeImage()!)
            let capture = try CapturedImage(pngData: tallPNG)
            try capture.applyFrame(fixture.composition())
            #expect(capture.pixels.height == 2544 && capture.unframedPixels.height == 4000)
        }

        @MainActor @Test func removingATallSourceFrameRestoresTheFullHeight() throws {
            let fixture = try PortraitFixture()
            let tall = PortraitFixture.context(width: 300, height: 4000)
            tall.setFillColor(NSColor.red.cgColor)
            tall.fill(CGRect(x: 0, y: 0, width: 300, height: 4000))
            let tallPNG = try PortraitFixture.png(tall.makeImage()!)
            let capture = try CapturedImage(pngData: tallPNG)
            try capture.applyFrame(fixture.composition())
            capture.removeFrame()
            #expect(capture.pngData == tallPNG && capture.pixels.height == 4000)
        }

        @MainActor @Test func invalidImageDataFails() {
            #expect(throws: (any Error).self) { try CapturedImage(pngData: Data([0, 1, 2])) }
        }

        @MainActor @Test func aRetinaFrameIsEncodedAtDoubleDensity() throws {
            let fixture = try PortraitFixture()
            let (capture, _) = try fixture.framed(.page, backingScale: 2)
            let encoded = try #require(CGImageSourceCreateWithData(capture.pngData as CFData, nil))
            let properties = try #require(CGImageSourceCopyPropertiesAtIndex(encoded, 0, nil)) as NSDictionary
            #expect(abs((properties[kCGImagePropertyDPIWidth] as! Double) - 144) < 0.1)
        }

        @MainActor @Test func removingARetinaFrameRestoresTheOriginalBytes() throws {
            let fixture = try PortraitFixture()
            let (capture, _) = try fixture.framed(.page, backingScale: 2)
            capture.removeFrame()
            #expect(capture.pngData == fixture.original)
        }
    }
}
