import AppKit
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import Parc

extension CapturePortraitTestsSupport {
    struct CapturePortraitEditsTests {
        @MainActor
        private struct EditedPortraitFixture {
            let fixture: PortraitFixture
            let capture: CapturedImage
            let editedSource: CGImage

            init() throws {
                fixture = try PortraitFixture()
                capture = try CapturedImage(pngData: fixture.original, backingScale: 2)
                try capture.crop(to: CGRect(x: 160, y: 0, width: 160, height: 160))
                try capture.applyFrame(fixture.composition(backingScale: 2))
                let context = PortraitFixture.context(width: 320, height: 160)
                context.draw(fixture.source, in: CGRect(x: 0, y: 0, width: 320, height: 160))
                context.setFillColor(NSColor.green.cgColor)
                context.fill(CGRect(x: 180, y: 20, width: 20, height: 20))
                editedSource = context.makeImage()!
            }
        }

        @MainActor @Test func anAcceptedEditReplacesTheSourceButNotTheOriginal() throws {
            let edited = try EditedPortraitFixture()
            try edited.capture.applyEditedOriginal(edited.editedSource)
            #expect(edited.capture.originalPNG == edited.fixture.original && edited.capture.sourcePNG != edited.fixture.original)
        }

        @MainActor @Test func anAcceptedEditKeepsTheCropAndTheFrame() throws {
            let edited = try EditedPortraitFixture()
            try edited.capture.applyEditedOriginal(edited.editedSource)
            #expect(edited.capture.unframedPixels.width == 160 && edited.capture.frame != nil)
        }

        @MainActor @Test func anAcceptedEditReappliesTheOriginalCrop() throws {
            let edited = try EditedPortraitFixture()
            try edited.capture.applyEditedOriginal(edited.editedSource)
            #expect(PortraitFixture.sample(edited.capture.unframedPixels, x: 30, y: 30)[1] > 245)
        }

        @MainActor @Test func anEditWithMismatchedDimensionsIsRefused() throws {
            let edited = try EditedPortraitFixture()
            let small = try #require(edited.fixture.source.cropping(to: CGRect(x: 0, y: 0, width: 10, height: 10)))
            #expect(throws: (any Error).self) { try edited.capture.applyEditedOriginal(small) }
        }

        @MainActor @Test func aRefusedEditLeavesTheAcceptedCapture() throws {
            let edited = try EditedPortraitFixture()
            try edited.capture.applyEditedOriginal(edited.editedSource)
            let accepted = edited.capture.pngData, acceptedSource = edited.capture.sourcePNG
            let small = try #require(edited.fixture.source.cropping(to: CGRect(x: 0, y: 0, width: 10, height: 10)))
            _ = try? edited.capture.applyEditedOriginal(small)
            #expect(edited.capture.pngData == accepted && edited.capture.sourcePNG == acceptedSource)
        }

        @MainActor @Test func removingTheFrameAfterAnEditLeavesTheUnframedCapture() throws {
            let edited = try EditedPortraitFixture()
            try edited.capture.applyEditedOriginal(edited.editedSource)
            edited.capture.removeFrame()
            #expect(edited.capture.pngData == edited.capture.unframedPNG)
        }

        @MainActor @Test func recroppingAnEditedCaptureRetainsTheEditedPixels() throws {
            let edited = try EditedPortraitFixture()
            try edited.capture.applyEditedOriginal(edited.editedSource)
            let acceptedSource = edited.capture.sourcePNG
            edited.capture.removeFrame()
            try edited.capture.crop(to: CGRect(x: 0, y: 0, width: 320, height: 160))
            #expect(edited.capture.pngData == acceptedSource)
        }

        @MainActor @Test func recroppingAnEditedCaptureKeepsTheOriginalAndBackingScale() throws {
            let edited = try EditedPortraitFixture()
            try edited.capture.applyEditedOriginal(edited.editedSource)
            try edited.capture.crop(to: CGRect(x: 0, y: 0, width: 320, height: 160))
            #expect(edited.capture.originalPNG == edited.fixture.original && edited.capture.backingScale == 2)
        }
    }
}
