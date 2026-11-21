import Testing
@testable import ParcCore

struct CaptureFrameApplyTests {
    let color = CaptureFrameSettings(background: .color, fraction: 0.5, watermark: true)

    @Test func addingAFrameToAnUnframedCaptureIsAPendingChange() {
        #expect(CaptureFrameApply.state(committed: nil, draft: color, renderable: true) == .pending)
    }

    @Test func reopeningAFrameWithoutChangesLeavesApplyQuiet() {
        #expect(CaptureFrameApply.state(committed: color, draft: color, renderable: true) == .unchanged)
    }

    @Test func aNewColorIsAPendingChange() {
        var moved = color
        moved.fraction = 0.8
        #expect(CaptureFrameApply.state(committed: color, draft: moved, renderable: true).isPrimary)
    }

    @Test func sliderJitterIsNotAChange() {
        var moved = color
        moved.fraction = 0.5004
        #expect(CaptureFrameApply.state(committed: color, draft: moved, renderable: true) == .unchanged)
    }

    @Test func theColorSliderDoesNotChangeAWebsiteColoredFrame() {
        let website = CaptureFrameSettings(background: .page, fraction: 0.2, watermark: true)
        var moved = website
        moved.fraction = 0.9
        #expect(CaptureFrameApply.state(committed: website, draft: moved, renderable: true) == .unchanged)
    }

    @Test func hidingTheWatermarkIsAChange() {
        var bare = color
        bare.watermark = false
        #expect(CaptureFrameApply.state(committed: color, draft: bare, renderable: true) == .pending)
    }

    @Test func aFrameThatCannotRenderCannotBeApplied() {
        #expect(CaptureFrameApply.state(committed: nil, draft: color, renderable: false) == .unavailable)
        #expect(!CaptureFrameApply.unavailable.isPrimary)
    }
}
