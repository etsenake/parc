import AppKit
import Testing
@testable import ParcKit
@testable import ParcLibrary
@testable import ParcNotes

extension CapturePortraitTestsSupport {
    struct CapturePortraitWatermarkTests {
        @MainActor
        private struct FramePage {
            let fixture: PortraitFixture
            let view: PortraitCaptureView

            init(fixture: PortraitFixture? = nil, reopening: Bool = false) throws {
                _ = NSApplication.shared
                self.fixture = try fixture ?? PortraitFixture()
                self.fixture.options.background = .desktop
                view = PortraitCaptureView(source: self.fixture.source, pageColor: .green,
                                           composition: reopening ? nil : self.fixture.composition(), defaults: self.fixture.defaults)
                view.setFrameSize(view.fittingSize)
                view.layoutSubtreeIfNeeded()
            }

            var toggle: NoteControlButton? {
                view.subviews.compactMap { $0 as? NoteControlButton }.first { $0.accessibilityLabel() == "Parc watermark" }
            }
        }

        @MainActor private static func bareFrame(_ fixture: PortraitFixture) throws -> CGImage {
            var options = fixture.options
            options.watermark = false
            return try fixture.render(options, desktop: fixture.wallpaper)
        }

        @MainActor private static func bytes(_ image: CGImage) -> Data { image.dataProvider!.data! as Data }

        @MainActor private static func footprintDiffers(_ image: CGImage, from bare: CGImage) -> Bool {
            for y in 8..<32 {
                for x in 140..<260 where PortraitFixture.sample(image, x: x, y: y) != PortraitFixture.sample(bare, x: x, y: y) { return true }
            }
            return false
        }

        @MainActor @Test func theToggleSitsInTheFramePageHeaderAndStartsOn() throws {
            let page = try FramePage()
            let toggle = try #require(page.toggle)
            #expect(toggle.isChecked && toggle.frame.maxY <= PortraitCaptureLayout.headerHeight)
            #expect(page.view.bounds.contains(toggle.frame) && toggle.frame.width > 0)
        }

        @MainActor @Test func turningTheToggleOffLeavesTheCaptionOutOfTheFrame() throws {
            let page = try FramePage()
            try #require(page.toggle).performClick(nil)
            let capture = try CapturedImage(pngData: page.fixture.original)
            try capture.applyFrame(page.view.composition)
            #expect(!page.view.composition.options.watermark && page.toggle?.isChecked == false)
            let bare = try Self.bareFrame(page.fixture)
            #expect(Self.bytes(capture.pixels) == Self.bytes(bare))
        }

        @MainActor @Test func leavingTheToggleOnDrawsTheCaptionIntoTheFrame() throws {
            let page = try FramePage()
            let capture = try CapturedImage(pngData: page.fixture.original)
            try capture.applyFrame(page.view.composition)
            let bare = try Self.bareFrame(page.fixture)
            #expect(page.view.composition.options.watermark && Self.footprintDiffers(capture.pixels, from: bare))
        }

        @MainActor @Test func turningTheToggleOffIsAChangeApplyCanCommit() throws {
            let page = try FramePage()
            try #require(page.toggle).performClick(nil)
            #expect(page.view.applyState == .pending && page.view.captureButton.isEnabled)
        }

        @MainActor @Test func theChoiceIsRememberedForTheNextCapture() throws {
            let page = try FramePage()
            try #require(page.toggle).performClick(nil)
            #expect(!PortraitCaptureOptions(defaults: page.fixture.defaults).watermark)
            let next = try FramePage(fixture: page.fixture, reopening: true)
            #expect(next.toggle?.isChecked == false && !next.view.composition.options.watermark)
        }

        @MainActor @Test func turningItBackOnIsRememberedToo() throws {
            let page = try FramePage()
            let toggle = try #require(page.toggle)
            toggle.performClick(nil)
            toggle.performClick(nil)
            #expect(PortraitCaptureOptions(defaults: page.fixture.defaults).watermark && toggle.isChecked)
        }

        @MainActor @Test func theToggleReportsItsStateToVoiceOver() throws {
            let page = try FramePage()
            let toggle = try #require(page.toggle)
            #expect(toggle.accessibilityRole() == .checkBox && (toggle.accessibilityValue() as? Int) == 1)
            toggle.performClick(nil)
            #expect((toggle.accessibilityValue() as? Int) == 0)
        }

        struct Margin: CustomTestStringConvertible, Sendable {
            let testDescription: String
            let margin: CGFloat
            static let cases: [Self] = [
                .init(testDescription: "Smallest frame", margin: 40),
                .init(testDescription: "Visible area", margin: 91),
                .init(testDescription: "Largest frame", margin: 160),
            ]
        }

        @MainActor @Test(arguments: Margin.cases)
        func theCaptionAndMarkFitInsideTheBottomMargin(_ sample: Margin) {
            let mark = PortraitCaptureRenderer.Watermark(center: CGPoint(x: 500, y: sample.margin / 2), margin: sample.margin)
            #expect(mark.bounds.minY >= 0 && mark.bounds.maxY <= sample.margin - 8)
            #expect(mark.markRect.minX > mark.origin.x && mark.markRect.minY == mark.origin.y)
            #expect(abs(mark.bounds.midX - 500) < 6)
        }

        @MainActor @Test func theCaptionReadsCapturedInFollowedByTheMark() {
            let mark = PortraitCaptureRenderer.Watermark(center: CGPoint(x: 200, y: 50), margin: 100)
            #expect(PortraitCaptureRenderer.Watermark.caption == "Captured in")
            #expect(mark.markRect.minX >= mark.origin.x + mark.textWidth && mark.markRect.height > mark.font.capHeight)
        }

        @MainActor @Test func theMarkIsTheTwoOutlineVectorInsideTheIconBox() {
            let bounds = ParcBrandMark.monochromeBounds
            #expect(CGRect(x: 0, y: 0, width: 24, height: 24).contains(bounds) && bounds.height > 18)
            var subpaths = 0
            ParcBrandMark.monochromePath.applyWithBlock { element in
                if element.pointee.type == .moveToPoint { subpaths += 1 }
            }
            #expect(subpaths == 2)
        }

        @MainActor @Test func anUnreadablePathIsRefused() {
            #expect(ParcBrandMark.path(svg: "M1 2 Q3 4 5 6") == nil && ParcBrandMark.path(svg: "M1") == nil)
            #expect(ParcBrandMark.path(svg: "M0 0L4 0L4 4Z")?.boundingBoxOfPath == CGRect(x: 0, y: 0, width: 4, height: 4))
        }
    }
}
