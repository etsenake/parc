import AppKit
import Metal
import SceneKit
import Testing
@testable import ParcCore
@testable import ParcSettings

struct WindowFrameViewTestsFocus {
    private typealias Harness = WindowFrameViewTestsSupport.Harness
    private typealias Finish = WindowFrameViewTestsSupport.Finish

    @Test @MainActor
    func presentingTakesFocus() throws {
        let h = Harness(hosted: true)
        let window = try #require(h.window)
        let prior = h.makeFocusView()
        window.makeFirstResponder(prior)
        h.view.present()
        #expect(window.firstResponder === h.view)
        #expect(!window.isVisible)
    }

    @Test @MainActor
    func theCrankUsesTheWindowBackingScale() throws {
        let h = Harness(hosted: true)
        let window = try #require(h.window)
        let prior = h.makeFocusView()
        window.makeFirstResponder(prior)
        h.view.present()
        #expect(h.view.sceneView.layer?.contentsScale == window.backingScaleFactor * WindowFrameCrankSceneView.supersampling)
    }

    @Test(arguments: [true, false]) @MainActor
    func dismissingReturnsFocusToThePreviousViewIfItIsStillPresent(removed: Bool) throws {
        let h = Harness(hosted: true)
        let window = try #require(h.window)
        let prior = h.makeFocusView()
        window.makeFirstResponder(prior)
        h.view.present()
        h.advance(0.5)
        if removed { prior.removeFromSuperview() }
        h.view.keyDown(with: h.key(36))
        h.advance(0.5)
        #expect(h.finishes == [Finish(commit: true, value: 10)])
        #expect((window.firstResponder === prior) == !removed)
    }

    @Test @MainActor
    func movingFocusCommitsTheFrame() throws {
        let h = Harness.presented(hosted: true)
        let window = try #require(h.window)
        let other = h.makeFocusView()
        h.view.keyDown(with: h.key(125))
        window.makeFirstResponder(other)
        #expect(h.view.phase == .dismissing(commit: true))
        h.advance(0.5)
        #expect(h.finishes == [Finish(commit: true, value: 9)])
    }

    @Test @MainActor
    func dismissingAfterFocusMovesLeavesTheNewResponderAlone() throws {
        let h = Harness.presented(hosted: true)
        let window = try #require(h.window)
        let other = h.makeFocusView()
        h.view.keyDown(with: h.key(125))
        window.makeFirstResponder(other)
        h.advance(0.5)
        #expect(window.firstResponder === other)
    }

    @Test @MainActor
    func leavingTheWindowMidTurnKeepsTheNearestPoint() {
        let held = Harness(hosted: true)
        held.view.present()
        held.advance(0.5)
        held.view.turn(by: 80)
        held.view.removeFromSuperview()
        #expect(held.finishes == [Finish(commit: true, value: 11)] && held.previews.last == 11)
        #expect(held.view.phase == .finished && !held.view.isAnimating && held.output.stops == 1)
    }

    @Test @MainActor
    func leavingTheWindowDuringEscapeRestoresTheOriginal() {
        let escaping = Harness.escaping(hosted: true)
        escaping.advance(0.05)
        #expect(escaping.previews.last != 10)
        escaping.view.removeFromSuperview()
        #expect(escaping.finishes == [Finish(commit: false, value: 10)] && escaping.previews.last == 10)
    }

    @Test @MainActor
    func leavingTheWindowDuringEntranceFinishesImmediately() {
        let arriving = Harness(value: 8, hosted: true)
        arriving.view.present()
        arriving.view.removeFromSuperview()
        #expect(arriving.finishes == [Finish(commit: true, value: 8)] && !arriving.view.isAnimating)
    }

    @Test @MainActor
    func aDetachedCrankWithNoOwnerTearsDownQuietly() {
        let abandoned = Harness(hosted: true)
        abandoned.view.present()
        abandoned.advance(0.5)
        abandoned.view.onPreview = nil
        abandoned.view.onEvent = nil
        abandoned.view.onFinish = nil
        abandoned.view.removeFromSuperview()
        #expect(abandoned.finishes.isEmpty && abandoned.output.stops == 1 && !abandoned.view.isAnimating)
    }
}
