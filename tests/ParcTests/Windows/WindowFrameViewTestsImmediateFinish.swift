import AppKit
import Metal
import SceneKit
import Testing
@testable import ParcCore
@testable import ParcSettings
@testable import Parc

struct WindowFrameViewTestsImmediateFinish {
    private typealias Support = WindowFrameViewTestsSupport

    private typealias Harness = Support.Harness
    private typealias Finish = Support.Finish

    @Test @MainActor
    func aHeldTurnExposesThePointItWouldSettleOn() {
        let h = Harness.presented()
        h.view.turn(by: 80)
        #expect(h.view.value == 11)
    }

    @Test @MainActor
    func finishingNowKeepsAndReportsTheFinalFrame() {
        let h = Harness.presented()
        h.view.turn(by: 80)
        let previews = h.previews.count
        h.view.finishNow(commit: true)
        #expect(h.finishes == [Finish(commit: true, value: 11)])
        #expect(h.previews.count == previews + 1 && h.previews.last == 11)
    }

    @Test @MainActor
    func finishingNowStopsMotion() {
        let h = Harness.presented()
        h.view.turn(by: 80)
        h.view.finishNow(commit: true)
        #expect(h.view.phase == .finished && !h.view.isAnimating && !h.view.isWaitingForGesture && h.view.alphaValue == 0)
    }

    @Test @MainActor
    func finishingNowReleasesAudio() {
        let h = Harness.presented()
        h.view.turn(by: 80)
        h.view.finishNow(commit: true)
        #expect(h.output.stops == 1 && h.view.value == 11)
    }

    @Test @MainActor
    func finishingNowIsIdempotent() {
        let h = Harness.presented()
        h.view.turn(by: 80)
        h.view.finishNow(commit: true)
        h.view.finishNow(commit: false)
        h.view.dismiss(commit: false)
        #expect(h.finishes.count == 1)
    }

    @Test @MainActor
    func finishingNowWithoutCommitRestoresTheOriginal() {
        let back = Harness(value: 10, palette: Support.light)
        back.view.present()
        back.advance(0.5)
        back.view.keyDown(with: back.key(126))
        back.advance(1)
        back.view.turn(by: 30)
        back.view.finishNow(commit: false)
        #expect(back.finishes == [Finish(commit: false, value: 10)] && back.previews.last == 10 && back.view.value == 10)
    }

    @Test @MainActor
    func finishingAnUnchangedCrankStillReportsTheFrame() {
        let still = Harness(value: 9, palette: Support.light)
        still.view.present()
        still.advance(0.5)
        let before = still.previews.count
        still.view.finishNow(commit: true)
        #expect(still.previews.count == before + 1 && still.previews.last == 9 && still.finishes == [Finish(commit: true, value: 9)])
    }

    @Test @MainActor
    func finishingNowHonorsAnEscapeAlreadyInProgress() {
        let escaping = Harness.escaping()
        escaping.view.finishNow(commit: true)
        #expect(escaping.finishes == [Finish(commit: false, value: 10)])
    }
}
