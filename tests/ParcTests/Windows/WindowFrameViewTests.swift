import AppKit
import Metal
import SceneKit
import Testing
@testable import Parc
@testable import ParcCore

struct WindowFrameViewTests {
    private typealias CrankView = WindowFrameCrankView

    @Test(arguments: [(90.0, 0.0, 1.0), (-30.0, cos(Double.pi / 6), -0.5)]) @MainActor
    func theKnobFollowsTheArmAngle(angle: Double, xFraction: Double, yFraction: Double) {
        let model = makeModel()
        let reach = WindowFrameCrankModel.armLength * WindowFrameCrankModel.scale
        model.setArm(degrees: angle)
        #expect(near(model.knobCenter, CGPoint(x: reach * xFraction, y: reach * yFraction), 0.05))
    }

    @Test @MainActor
    func theShadowRotorsFollowTheCrankAngle() {
        let model = WindowFrameCrankModel(side: WindowFrameCrankView.side, palette: light)
        model.setArm(degrees: -30)
        #expect(model.ghostRotors.count == WindowFrameCrankModel.shadowSpread.count)
        #expect(model.ghostRotors.allSatisfy { near($0.eulerAngles.z, model.rotor.eulerAngles.z, 0.0001) })
    }

    @Test @MainActor
    func theCrankFitsThePlacementRadiusAndLength() {
        let model = WindowFrameCrankModel(side: WindowFrameCrankView.side, palette: light)
        let (low, high) = model.rotor.boundingBox
        let scale = WindowFrameCrankModel.scale
        #expect(abs(high.x * scale - WindowFrameCrankPlacement.swingRadius) < 2)
        #expect((high.x - low.x) * scale > 100 && (high.x - low.x) * scale < 112)
    }

    @Test @MainActor
    func theCrankViewContainsTheWholeCircleOfLights() {
        #expect(WindowFrameCrankView.side >= 2 * WindowFrameCrankPlacement.extent)
    }

    @Test @MainActor
    func aPaletteReusesItsLightingEnvironment() {
        let model = WindowFrameCrankModel(side: WindowFrameCrankView.side, palette: light)
        #expect(model.scene.lightingEnvironment.contents != nil)
        let environment = WindowFrameCrankModel.cachedEnvironment(deep: light.deep, dark: false)
        #expect(environment != nil && (model.scene.lightingEnvironment.contents as AnyObject) === environment)
    }

    @Test @MainActor
    func aDarkPaletteRelightsTheMetal() {
        let model = WindowFrameCrankModel(side: WindowFrameCrankView.side, palette: light)
        model.apply(dark)
        #expect(near(model.scene.lightingEnvironment.intensity, 1.6, 0.001))
    }

    @Test @MainActor
    func switchingPalettesReusesBothLightingEnvironments() throws {
        let model = makeModel()
        let inLight = try #require(model.scene.lightingEnvironment.contents as AnyObject?)
        model.apply(dark)
        let inDark = try #require(model.scene.lightingEnvironment.contents as AnyObject?)
        model.apply(light)
        #expect((model.scene.lightingEnvironment.contents as AnyObject?) === inLight)
        model.apply(dark)
        #expect((model.scene.lightingEnvironment.contents as AnyObject?) === inDark)
    }

    @Test @MainActor
    func eachCrankGetsItsOwnNodesFromSharedGeometry() throws {
        let model = WindowFrameCrankModel(side: WindowFrameCrankView.side, palette: light)
        let twin = WindowFrameCrankModel(side: WindowFrameCrankView.side, palette: dark)
        #expect(twin.arm?.geometry != nil && twin.arm?.geometry === model.arm?.geometry)
        #expect(twin.knob !== model.knob && twin.rotor.childNodes.count == model.rotor.childNodes.count)
    }

    @Test @MainActor
    func thePaddleRisesTowardTheKnob() throws {
        let model = WindowFrameCrankModel(side: WindowFrameCrankView.side, palette: light)
        let arm = WindowFrameCrankModel.positions(model.arm?.geometry ?? SCNGeometry())
        let knobEnd = arm.filter { $0.x > 45 }.map(\.z), hubEnd = arm.filter { $0.x < 5 }.map(\.z)
        let rise = (knobEnd.max() ?? 0) - (hubEnd.max() ?? 0)
        #expect(!knobEnd.isEmpty && !hubEnd.isEmpty && abs(rise - WindowFrameCrankModel.paddleLift) < 0.5)
    }

    @Test @MainActor
    func thePaddleGeometryIsSharedAtTheSameDepth() {
        #expect(WindowFrameCrankModel.paddleGeometry(depth: WindowFrameCrankModel.paddleDepth) === WindowFrameCrankModel.paddleGeometry(depth: WindowFrameCrankModel.paddleDepth))
    }

    @Test @MainActor
    func theCrankLabelDoesNotCastAShadow() throws {
        let model = WindowFrameCrankModel(side: WindowFrameCrankView.side, palette: light)
        let planes = model.scene.rootNode.childNodes { node, _ in node.geometry is SCNPlane }
        #expect(planes.count == 1)
    }

    @Test @MainActor
    func tinyCrankPartsDoNotCastShadows() throws {
        let model = WindowFrameCrankModel(side: WindowFrameCrankView.side, palette: light)
        #expect(model.shadowParts > 0 && model.shadowParts < model.root.childNodes { node, _ in node.geometry != nil }.count)
    }

    @Test @MainActor
    func presentingSlidesFromTheCornerAndSettlesInPlace() {
        #expect(CrankView.presentation(0, reduceMotion: false) == (0, CrankView.slideDistance))
        #expect(CrankView.presentation(CrankView.presentDuration, reduceMotion: false) == (1, 0))
        #expect(CrankView.presentation(0.15, reduceMotion: false).offset < 0)
    }

    @Test @MainActor
    func reduceMotionFadesInWithoutSliding() {
        let fixture = Harness(reduceMotion: true)
        fixture.view.present()
        fixture.advance(0.1)
        #expect(fixture.view.stageOffset == .zero)
        #expect(fixture.view.alphaValue > 0 && fixture.view.alphaValue < 1)
        fixture.advance(0.1)
        #expect(fixture.view.stageOffset == .zero)
        #expect(fixture.view.alphaValue == 1)
    }

    @Test @MainActor
    func dismissalReachesZeroAlpha() {
        #expect(CrankView.dismissal(CrankView.dismissDuration, reduceMotion: false).alpha == 0)
        #expect(CrankView.dismissal(0.1, reduceMotion: true).offset == 0)
    }

    @Test @MainActor
    func theSettleSpringOvershootsBeforeReturningToRest() {
        #expect(CrankView.settleRemaining(0, reduceMotion: false) == 1)
        #expect((CrankView.settleRemaining(0.15, reduceMotion: false) ?? 0) < 0)
        #expect(CrankView.settleRemaining(CrankView.settleDuration, reduceMotion: false) == nil)
    }

    @Test(arguments: 0..<15) @MainActor
    func reduceMotionSettlesWithoutOvershoot(sample: Int) {
        let t = Double(sample) / 100
        #expect((CrankView.settleRemaining(t, reduceMotion: true) ?? 0) >= 0)
    }

    @Test @MainActor
    func anIdleCrankIsHiddenAndLetsClicksThrough() {
        let h = Harness(value: 10, palette: light)
        let view = h.view
        #expect(view.phase == .idle && view.alphaValue == 0 && view.sceneView.isHidden)
        #expect(view.hitTest(h.superPoint(view.hub)) == nil)
    }

    @Test @MainActor
    func presentingMakesTheCrankVisibleAndStartsItsSlide() {
        let fixture = Harness()
        let view = fixture.view
        view.present()
        #expect(view.phase == .presenting)
        #expect(!view.sceneView.isHidden)
        #expect(view.stageOffset.x < 0 && view.stageOffset.y < 0)
        #expect(view.isAnimating)
    }

    @Test @MainActor
    func presentationSettlesAndStopsTheTimer() {
        let view = Harness.presented().view
        #expect(view.phase == .shown)
        #expect(view.alphaValue == 1)
        #expect(view.stageOffset == .zero)
        #expect(!view.isAnimating)
    }

    @Test(arguments: [(CGFloat(0), CGFloat(0), true), (CGFloat(115), 0, true),
                      (CGFloat(118), 0, false), (CGFloat(-142), -142, false)]) @MainActor
    func hitTestingFollowsTheCircularLights(xOffset: CGFloat, yOffset: CGFloat, catches: Bool) {
        let view = Harness.presented().view
        let point = CGPoint(x: view.hub.x + xOffset, y: view.hub.y + yOffset)
        #expect((view.hitTest(point) === view) == catches)
    }

    @Test @MainActor
    func theCrankIsAnAccessibleSlider() {
        let view = Harness().view
        #expect(view.isAccessibilityElement() && view.accessibilityRole() == .slider && view.accessibilityLabel() == "Window frame")
        #expect(view.accessibilityValueDescription() == "10 points, Classic")
        #expect((view.accessibilityValue() as? NSNumber)?.intValue == 10)
        #expect((view.accessibilityMinValue() as? NSNumber)?.intValue == 3 && (view.accessibilityMaxValue() as? NSNumber)?.intValue == 13)
    }

    @Test(arguments: [(true, 11, "11 points, Roomy"), (false, 9, "9 points, Comfy")]) @MainActor
    func voiceOverStepsTheFrame(up: Bool, point: Int, description: String) {
        let view = Harness.presented().view
        let accepted = up ? view.accessibilityPerformIncrement() : view.accessibilityPerformDecrement()
        #expect(accepted)
        #expect(view.crank.value == point)
        #expect(view.accessibilityValueDescription() == description)
    }

    @Test @MainActor
    func changingPaletteUpdatesBothTheMetalAndLights() {
        let view = Harness().view
        view.palette = dark
        #expect(view.lights.palette == dark && near(view.model.scene.lightingEnvironment.intensity, 1.6, 0.001))
    }

    @Test @MainActor
    func dismissingMidEntranceStartsFromTheCurrentPresentation() {
        let early = Harness(value: 10, palette: light)
        early.view.present()
        early.advance(0.05)
        let alpha = early.view.alphaValue, offset = early.view.stageOffset
        #expect(alpha > 0 && alpha < 0.9)
        early.view.dismiss(commit: true)
        early.advance(1.0 / 60)
        #expect(early.view.alphaValue <= alpha && early.view.stageOffset.x <= offset.x + 0.001 && early.view.stageOffset.x > offset.x - 2)
    }

    @Test @MainActor
    func dismissalStartsAtTheSuppliedEntranceState() {
        #expect(CrankView.dismissal(0, reduceMotion: false, from: (0.3, 5)) == (0.3, 5))
    }

    @Test(arguments: [(UInt16(126), 11), (124, 11), (123, 9), (125, 9)]) @MainActor
    func arrowKeysStepTheFrame(key: UInt16, point: Int) {
        let h = Harness.presented()
        h.view.keyDown(with: h.key(key))
        #expect(h.view.crank.value == point)
        #expect(h.events == [.notch(point)])
    }

    @Test @MainActor
    func anArrowNotchClicksAndTicks() {
        let h = Harness.steppedUp()
        #expect(h.output.played == [.notch(11)] && h.haptics == [.alignment])
    }

    @Test @MainActor
    func aNotchUpdatesTheLightsAndReadout() {
        let view = Harness.steppedUp().view
        #expect(view.lights.litCount == 9 && view.lights.readout == 11)
    }

    @Test @MainActor
    func aNewlyLitPillPopsWithSparkles() {
        let view = Harness.steppedUp().view
        #expect(!view.lights.sparkles.isEmpty && view.lights.pop[8] < WindowFrameCrankLightsView.popDuration)
    }

    @Test @MainActor
    func anArrowStepSpringsToTheNewFrameWithASmallOvershoot() throws {
        let h = Harness.steppedUp()
        h.sample(0.6)
        let peak = try #require(h.previews.max())
        #expect(h.previews.last == 11)
        #expect(peak > 11 && peak < 11.2)
    }

    @Test @MainActor
    func settledSparklesStopTheAnimation() {
        let h = Harness.steppedUp()
        let view = h.view
        h.advance(1)
        #expect(view.lights.sparkles.isEmpty && !view.lights.isAnimating && !view.isAnimating)
    }

    @Test @MainActor
    func theRenderedArmRestsAtTheCrankAngle() {
        let h = Harness.steppedUp()
        let view = h.view
        h.advance(1)
        #expect(near(CGFloat(view.model.armDegrees), CGFloat(view.crank.armDegrees), 0.0001))
    }

    @Test @MainActor
    func trackpadScrollTurnsTheCrankOneToOne() {
        let h = Harness.presented()
        let reference = h.scrollTrackpad()
        #expect(h.view.crank == reference)
        #expect(h.previews.last == CGFloat(reference.displayed))
    }

    @Test @MainActor
    func scrollMomentumDoesNotContinueTurning() {
        let h = Harness.presented()
        let held = h.scrollTrackpad()
        h.view.scrollWheel(with: h.scroll(400, precise: true, momentum: 2))
        #expect(h.view.crank == held)
    }

    @Test @MainActor
    func liftingTheTrackpadFingersSettlesAtTheNearestPoint() {
        let h = Harness.presented()
        var expected = h.scrollTrackpad()
        h.view.scrollWheel(with: h.scroll(0, precise: true, phase: 4))
        expected.release()
        #expect(h.view.crank == expected)
        h.advance(1)
        #expect(h.previews.last == CGFloat(expected.value))
    }

    @Test @MainActor
    func aMouseWheelClickTurnsTheCrank() {
        let h = Harness.presented()
        h.view.scrollWheel(with: h.scroll(-3, precise: false))
        #expect(h.view.crank.displayed != 10)
    }

    @Test @MainActor
    func theWheelReleasesAfterItsShortIdleDelay() {
        let h = Harness.presented()
        h.view.scrollWheel(with: h.scroll(-3, precise: false))
        h.advance(0.24)
        #expect(h.view.isWaitingForGesture)
        h.advance(0.02)
        #expect(h.view.crank.displayed == Double(h.view.crank.value))
        #expect(!h.view.isWaitingForGesture)
    }

    @Test @MainActor
    func draggingTheKnobClockwiseByAThirdOfATurnAddsAPoint() {
        let h = Harness.presented()
        h.dragKnob(degrees: 120)
        #expect(h.view.crank.value == 11)
        #expect(h.events.last == .notch(11))
    }

    @Test @MainActor
    func releasingTheKnobSettlesTheFrame() {
        let h = Harness.presented()
        h.dragKnob(degrees: 100)
        h.view.mouseUp(with: h.mouse(.leftMouseUp, h.view.hub))
        #expect(h.view.crank.displayed == 11)
    }

    @Test @MainActor
    func draggingTheLightsDoesNotTurnTheCrank() {
        let h = Harness.presented()
        let view = h.view
        let hub = view.hub
        let before = view.crank
        view.mouseDown(with: h.mouse(.leftMouseDown, CGPoint(x: hub.x, y: hub.y + 100)))
        view.mouseDragged(with: h.mouse(.leftMouseDragged, CGPoint(x: hub.x + 100, y: hub.y)))
        view.mouseUp(with: h.mouse(.leftMouseUp, CGPoint(x: hub.x + 100, y: hub.y)))
        #expect(view.crank == before)
    }

    @Test @MainActor
    func keysStopAtTheThickestPointWithAThunk() {
        let h = Harness.presented(value: 13)
        let view = h.view
        view.keyDown(with: h.key(126))
        #expect(view.crank.value == 13 && h.events.last == .end(.thick) && h.output.played.last == .end(.thick))
    }

    @Test @MainActor
    func theEndFlashFades() {
        let h = Harness.presented(value: 13)
        let view = h.view
        view.keyDown(with: h.key(126))
        #expect(view.flash == 1)
        h.advance(1)
        #expect(view.flash == 0)
    }

    @Test @MainActor
    func pushingPastTheEndAddsGiveAndFlashes() {
        let h = Harness.presented(value: 13)
        let view = h.view
        view.turn(by: 60)
        #expect(h.events.last == .end(.thick) && view.crank.strain > 0 && view.flash == 1)
    }

    @Test @MainActor
    func theCrankTremblesAndKeepsAnimatingWhileStrained() {
        let h = Harness.presented(value: 13)
        let view = h.view
        view.turn(by: 60)
        h.advance(0.05)
        #expect(view.tremble != 0 && !near(CGFloat(view.model.armDegrees), CGFloat(view.crank.armDegrees), 0.0001))
        #expect(view.isAnimating)
    }

    @Test @MainActor
    func reduceMotionStillsTheTremble() {
        let h = Harness.presented(value: 13)
        let view = h.view
        view.turn(by: 60)
        h.advance(0.05)
        h.reduceMotion = true
        h.advance(0.05)
        #expect(view.tremble == 0)
    }

    @Test @MainActor
    func lettingGoOfStrainSpringsBackToTheEndpoint() {
        let h = Harness.presented(value: 13)
        let view = h.view
        view.turn(by: 60)
        view.releaseTurn()
        h.advance(1)
        #expect(view.crank.value == 13 && h.previews.last == 13 && view.crank.strain == 0)
    }

    @Test @MainActor
    func reduceMotionUpdatesLightsWithoutSparkles() {
        let h = Harness.presented(value: 13, reduceMotion: true)
        let view = h.view
        let sparkles = view.lights.sparkles.count
        view.keyDown(with: h.key(125))
        #expect(view.lights.sparkles.count == sparkles && view.lights.litCount == 10)
        h.advance(1)
        #expect(h.previews.last == 12)
    }

    @Test @MainActor
    func escapeDismissesAndLetsClicksThrough() {
        let h = Harness.escaping()
        let view = h.view
        #expect(view.phase == .dismissing(commit: false) && view.hitTest(h.superPoint(view.hub)) == nil)
    }

    @Test @MainActor
    func escapeRestoresTheReadoutImmediately() {
        let h = Harness.escaping()
        let view = h.view
        #expect(view.lights.readout == 10 && view.lights.litCount == 8)
    }

    @Test @MainActor
    func escapeRestoresTheAccessibleValueImmediately() {
        let h = Harness.escaping()
        let view = h.view
        #expect(view.value == 10 && (view.accessibilityValue() as? NSNumber)?.intValue == 10 && view.accessibilityValueDescription() == "10 points, Classic")
    }

    @Test @MainActor
    func keysDoNotChangeTheCrankWhileItIsLeaving() {
        let h = Harness.escaping()
        let view = h.view
        view.keyDown(with: h.key(126))
        #expect(view.crank.value == 12)
    }

    @Test @MainActor
    func escapeRestoresTheOriginalFrame() {
        let h = Harness.escaping()
        h.advance(0.6)
        #expect(h.finishes == [Finish(commit: false, value: 10)])
        #expect(h.previews.contains { $0 > 10.5 } && h.previews.last == 10)
    }

    @Test @MainActor
    func dismissalHidesTheSceneAndStopsTheTimer() {
        let h = Harness.escaping()
        let view = h.view
        h.advance(0.6)
        #expect(view.phase == .finished && view.sceneView.isHidden && view.alphaValue == 0 && !view.isAnimating)
    }

    @Test @MainActor
    func dismissalReleasesTheAudioOutput() {
        let h = Harness.escaping()
        h.advance(0.6)
        #expect(h.output.stops == 1)
    }

    @Test @MainActor
    func aSecondDismissDoesNotFinishAgain() {
        let h = Harness.escaping()
        let view = h.view
        h.advance(0.6)
        view.dismiss(commit: true)
        h.advance(0.5)
        #expect(h.finishes.count == 1)
    }

    @Test @MainActor
    func returnKeepsTheUpdatedFrame() {
        let keep = Harness(value: 7, palette: dark)
        keep.view.present()
        keep.advance(0.5)
        keep.view.keyDown(with: keep.key(125))
        keep.view.keyDown(with: keep.key(36))
        keep.advance(0.5)
        #expect(keep.finishes == [Finish(commit: true, value: 6)])
    }

    @Test @MainActor
    func dismissingMidTurnKeepsTheNearestPoint() {
        let held = Harness(value: 10, palette: light)
        held.view.present()
        held.advance(0.5)
        held.view.turn(by: 80)
        held.view.dismiss(commit: true)
        held.advance(0.6)
        #expect(held.finishes == [Finish(commit: true, value: 11)])
    }

    @Test(arguments: [true, false]) @MainActor
    func clickingInsideOrOutsideControlsDismissal(inside: Bool) {
        let h = Harness.presented(hosted: true)
        let point = inside ? CGPoint(x: h.view.hub.x, y: h.view.hub.y + 60) : CGPoint(x: -20, y: -20)
        h.view.outsideClick(h.mouse(.leftMouseDown, point))
        #expect(h.view.phase == (inside ? .shown : .dismissing(commit: true)))
        h.advance(0.5)
        if inside {
            #expect(h.finishes.isEmpty)
        } else {
            #expect(h.finishes == [Finish(commit: true, value: 10)])
        }
    }

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
    func finishingNowStopsMotionAndReleasesAudio() {
        let h = Harness.presented()
        h.view.turn(by: 80)
        h.view.finishNow(commit: true)
        #expect(h.view.phase == .finished && !h.view.isAnimating && !h.view.isWaitingForGesture && h.view.alphaValue == 0)
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
        let back = Harness(value: 10, palette: light)
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
        let still = Harness(value: 9, palette: light)
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

    @Test @MainActor
    func presentingTakesFocusAndUsesTheWindowBackingScale() throws {
        let h = Harness(hosted: true)
        let window = try #require(h.window)
        let prior = h.makeFocusView()
        window.makeFirstResponder(prior)
        h.view.present()
        #expect(window.firstResponder === h.view)
        #expect(h.view.sceneView.layer?.contentsScale == window.backingScaleFactor * WindowFrameCrankSceneView.supersampling)
        #expect(!window.isVisible)
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
    func movingFocusCommitsAndLeavesTheNewResponderAlone() throws {
        let h = Harness.presented(hosted: true)
        let window = try #require(h.window)
        let other = h.makeFocusView()
        h.view.keyDown(with: h.key(125))
        window.makeFirstResponder(other)
        #expect(h.view.phase == .dismissing(commit: true))
        h.advance(0.5)
        #expect(h.finishes == [Finish(commit: true, value: 9)])
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

    @Test @MainActor
    func aTrackpadTurnRemainsHeldThroughAShortPause() {
        let h = Harness.presented()
        h.view.scrollWheel(with: h.scroll(30, precise: true, phase: 1))
        #expect(h.view.crank.displayed > 10.2 && h.view.isWaitingForGesture)
        h.advance(0.3)
        #expect(h.view.crank.displayed > 10.2 && h.view.isWaitingForGesture)
    }

    @Test @MainActor
    func aMissingTrackpadEndReleasesAfterTheGestureIdleDelay() {
        let h = Harness.presented()
        h.view.scrollWheel(with: h.scroll(30, precise: true, phase: 1))
        h.advance(0.59)
        #expect(h.view.isWaitingForGesture)
        h.advance(0.02)
        #expect(h.view.crank.displayed == Double(h.view.crank.value))
        #expect(!h.view.isWaitingForGesture)
    }

    @Test @MainActor
    func horizontalTrackpadInputAlsoTurnsTheCrank() {
        let h = Harness.presented()
        let view = h.view
        var reference = view.crank
        let sideways = h.scroll(0, precise: true, phase: 1, horizontal: 20)
        view.scrollWheel(with: sideways)
        reference.turn(degrees: WindowFrameCrank.scrollDegrees(deltaY: Double(sideways.scrollingDeltaX), precise: true))
        #expect(view.crank == reference)
    }

    @Test(arguments: [(CGFloat(3), CGFloat(-1), CGFloat(3)), (1, -2, -2)]) @MainActor
    func theLargerScrollAxisWins(x: CGFloat, y: CGFloat, delta: CGFloat) {
        #expect(CrankView.scrollDelta(x: x, y: y) == delta)
    }

    @Test @MainActor
    func grabbingMidSettleContinuesFromTheDisplayedPoint() {
        let h = Harness.presented()
        let view = h.view
        view.keyDown(with: h.key(126))
        h.advance(0.03)
        let shown = h.previews.last ?? 0
        #expect(abs(shown - CGFloat(view.crank.value)) > 0.05)
        view.turn(by: 1)
        #expect(abs((h.previews.last ?? 0) - (shown + 1 / 120)) < 0.0001)
    }

    @Test @MainActor
    func grabbingDuringSpringBackContinuesFromTheGive() {
        let h = Harness.presented(value: 13)
        let view = h.view
        view.turn(by: 40)
        view.releaseTurn()
        h.advance(0.02)
        let strained = h.previews.last ?? 0
        #expect(strained > 13)
        view.turn(by: -1)
        #expect(abs((h.previews.last ?? 0) - CGFloat(WindowFrameCrank.rubber(WindowFrameCrankView.raw(showing: Double(strained)) - 1.0 / 120))) < 0.0001)
    }

    @Test(arguments: [13.2, 2.9]) @MainActor
    func theGiveTransformCanBeInverted(point: Double) {
        #expect(abs(WindowFrameCrank.rubber(CrankView.raw(showing: point)) - point) < 0.0001)
    }

    @Test(arguments: [0, 7]) @MainActor
    func litPillsGlow(index: Int) throws {
        let image = try LightsImage()
        #expect(image.alpha(at: image.lights.pillCenter(index)) > 0.5)
    }

    @Test @MainActor
    func unlitPillsAreFainterThanLitPills() throws {
        let image = try LightsImage()
        let unlit = image.alpha(at: image.lights.pillCenter(10))
        #expect(unlit > 0)
        #expect(unlit < image.alpha(at: image.lights.pillCenter(7)))
    }

    @Test @MainActor
    func theLightsDoNotPaintABackdrop() throws {
        let image = try LightsImage()
        #expect(image.alpha(at: CGPoint(x: image.lights.bounds.midX + 50, y: image.lights.bounds.midY + 30)) == 0)
    }

    @Test @MainActor
    func theReadoutSitsUnderTheArc() throws {
        let image = try LightsImage()
        let center = CGPoint(x: image.lights.bounds.midX, y: image.lights.bounds.midY - WindowFrameCrankPlacement.lightsRadius)
        #expect(image.alpha(at: center) > 0.8)
    }

    @Test(arguments: [false, true]) @MainActor
    func theCrankRendersOpaqueAtTheHubAndKnob(knob: Bool) throws {
        let model = makeModel()
        let image = try CrankImage(model: model)
        let offset = knob ? model.knobCenter : .zero
        #expect(image.alpha(x: offset.x, y: offset.y) > 0.9)
    }

    @Test(arguments: [false, true]) @MainActor
    func theCrankRendersWithTransparentCorners(positiveCorner: Bool) throws {
        let image = try CrankImage(model: makeModel())
        let corner = (CrankView.side / 2 - 4) * (positiveCorner ? 1 : -1)
        #expect(image.alpha(x: corner, y: corner) == 0)
    }

    @Test @MainActor
    func theCrankShadowIsSoftAndDoesNotAccumulateWherePartsOverlap() throws {
        let image = try shadowImage()
        let offset = WindowFrameCrankModel.shadowOffset
        let hub = image.alpha(x: offset.dx, y: offset.dy)
        let arm = image.alpha(x: offset.dx, y: offset.dy + 36)
        #expect(arm > 0.2 && arm < 0.7)
        #expect(abs(hub - arm) < 0.03)
    }

    @Test @MainActor
    func theCrankShadowEndsPastTheKnob() throws {
        let image = try shadowImage()
        let offset = WindowFrameCrankModel.shadowOffset
        #expect(image.alpha(x: offset.dx, y: offset.dy + 110) < 0.02)
    }

    private static let lightPalette = WindowFrameCrankPalette(
        accent: NSColor(srgbRed: 0.76, green: 0.31, blue: 0.42, alpha: 1),
        deep: NSColor(srgbRed: 0.93, green: 0.59, blue: 0.71, alpha: 1),
        cap: NSColor(srgbRed: 0.90, green: 0.56, blue: 0.62, alpha: 1), dark: false
    )
    private var light: WindowFrameCrankPalette { Self.lightPalette }
    private let dark = WindowFrameCrankPalette(
        accent: NSColor(srgbRed: 0.30, green: 0.55, blue: 1, alpha: 1),
        deep: NSColor(srgbRed: 0.05, green: 0.06, blue: 0.08, alpha: 1),
        cap: NSColor(srgbRed: 0.14, green: 0.15, blue: 0.18, alpha: 1), dark: true
    )

    private func near(_ a: CGFloat, _ b: CGFloat, _ tolerance: CGFloat = 0.01) -> Bool {
        abs(a - b) < tolerance
    }

    private func near(_ a: CGPoint, _ b: CGPoint, _ tolerance: CGFloat = 0.01) -> Bool {
        hypot(a.x - b.x, a.y - b.y) < tolerance
    }

    @MainActor
    private func makeModel() -> WindowFrameCrankModel {
        WindowFrameCrankModel(side: CrankView.side, palette: light)
    }

    @MainActor
    private func shadowImage() throws -> CrankImage {
        let model = makeModel()
        model.setArm(degrees: 90)
        model.root.isHidden = true
        return try CrankImage(model: model)
    }

    private struct Finish: Equatable {
        let commit: Bool
        let value: Int
    }

    @MainActor
    private final class Harness {
        let window: NSWindow?
        let view: WindowFrameCrankView
        let output = RecordingOutput()
        var haptics: [NSHapticFeedbackManager.FeedbackPattern] = []
        var events: [WindowFrameCrank.Event] = []
        var previews: [CGFloat] = []
        var finishes: [Finish] = []
        private let clock: TestClock
        var reduceMotion: Bool {
            get { clock.reduceMotion }
            set { clock.reduceMotion = newValue }
        }

        init(value: Int = 10, palette: WindowFrameCrankPalette? = nil, reduceMotion: Bool = false, hosted: Bool = false) {
            _ = NSApplication.shared
            if hosted {
                let host = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
                                    styleMask: .borderless, backing: .buffered, defer: false)
                host.isReleasedWhenClosed = false
                window = host
            } else {
                window = nil
            }
            let clock = TestClock(reduceMotion: reduceMotion)
            self.clock = clock
            let feedback = WindowFrameCrankFeedback(allowsSound: { true }, haptic: { clock.haptics.append($0) },
                                                    output: { [output] in output }, now: { clock.time })
            view = WindowFrameCrankView(value: value, palette: palette ?? WindowFrameViewTests.lightPalette,
                                       feedback: feedback, reducesMotion: { clock.reduceMotion },
                                       now: { clock.time }, startTimer: clock.startTimer)
            if let window {
                view.frame.origin = CGPoint(x: 40, y: 30)
                window.contentView?.addSubview(view)
            }
            view.onEvent = { [weak self] event in
                self?.haptics = clock.haptics
                self?.events.append(event)
            }
            view.onPreview = { [weak self] in self?.previews.append($0) }
            view.onFinish = { [weak self] in self?.finishes.append(Finish(commit: $0, value: $1)) }
        }

        deinit {
            MainActor.assumeIsolated {
                if let window {
                    view.removeFromSuperview()
                    window.close()
                }
            }
        }

        static func presented(value: Int = 10, reduceMotion: Bool = false, hosted: Bool = false) -> Harness {
            let fixture = Harness(value: value, reduceMotion: reduceMotion, hosted: hosted)
            fixture.view.present()
            fixture.advance(0.5)
            return fixture
        }

        static func steppedUp() -> Harness {
            let fixture = presented()
            fixture.view.keyDown(with: fixture.key(126))
            return fixture
        }

        static func escaping(hosted: Bool = false) -> Harness {
            let fixture = presented(hosted: hosted)
            fixture.view.keyDown(with: fixture.key(126))
            fixture.view.keyDown(with: fixture.key(126))
            fixture.advance(0.1)
            fixture.view.keyDown(with: fixture.key(53))
            return fixture
        }

        func advance(_ seconds: Double) {
            clock.time += seconds
            if let pending = clock.wheel, pending.deadline <= clock.time {
                clock.wheel = nil
                if pending.timer.isValid { pending.timer.fire() }
            }
            view.advance(by: seconds)
        }

        func sample(_ seconds: Double) {
            let frameInterval = 1.0 / 60
            for _ in 0..<Int((seconds / frameInterval).rounded(.up)) { advance(frameInterval) }
        }

        func superPoint(_ local: CGPoint) -> CGPoint { view.convert(local, to: view.superview) }

        func mouse(_ type: NSEvent.EventType, _ local: CGPoint) -> NSEvent {
            let point = view.convert(local, to: nil)
            return NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: 0,
                                      windowNumber: window?.windowNumber ?? 0, context: nil,
                                      eventNumber: 0, clickCount: 1, pressure: 1)!
        }

        func key(_ code: UInt16) -> NSEvent {
            NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                             windowNumber: window?.windowNumber ?? 0, context: nil, characters: "",
                             charactersIgnoringModifiers: "", isARepeat: false, keyCode: code)!
        }

        func scroll(_ delta: Int32, precise: Bool, phase: Int64 = 0, momentum: Int64 = 0, horizontal: Int32 = 0) -> NSEvent {
            let event = CGEvent(scrollWheelEvent2Source: nil, units: precise ? .pixel : .line, wheelCount: 2,
                                wheel1: delta, wheel2: horizontal, wheel3: 0)!
            event.setIntegerValueField(.scrollWheelEventScrollPhase, value: phase)
            event.setIntegerValueField(.scrollWheelEventMomentumPhase, value: momentum)
            event.setIntegerValueField(.scrollWheelEventIsContinuous, value: precise ? 1 : 0)
            return NSEvent(cgEvent: event)!
        }

        func scrollTrackpad() -> WindowFrameCrank {
            var reference = WindowFrameCrank(value: view.crank.value)
            let began = scroll(40, precise: true, phase: 1)
            let changed = scroll(40, precise: true, phase: 2)
            view.scrollWheel(with: began)
            view.scrollWheel(with: changed)
            reference.turn(degrees: WindowFrameCrank.scrollDegrees(deltaY: Double(began.scrollingDeltaY), precise: true))
            reference.turn(degrees: WindowFrameCrank.scrollDegrees(deltaY: Double(changed.scrollingDeltaY), precise: true))
            return reference
        }

        func dragKnob(degrees: CGFloat) {
            let hub = view.hub
            let radius: CGFloat = 60
            let angle = (90 - degrees) * .pi / 180
            view.mouseDown(with: mouse(.leftMouseDown, CGPoint(x: hub.x, y: hub.y + radius)))
            view.mouseDragged(with: mouse(.leftMouseDragged, CGPoint(x: hub.x + radius * cos(angle), y: hub.y + radius * sin(angle))))
        }

        func makeFocusView() -> NSView {
            let responder = FocusView(frame: NSRect(x: 600, y: 400, width: 60, height: 20))
            window?.contentView?.addSubview(responder)
            return responder
        }
    }

    @MainActor
    private final class TestClock {
        var time: TimeInterval = 0
        var wheel: (deadline: TimeInterval, timer: Timer)?
        var haptics: [NSHapticFeedbackManager.FeedbackPattern] = []
        var reduceMotion: Bool

        init(reduceMotion: Bool) { self.reduceMotion = reduceMotion }

        func startTimer(_ period: TimeInterval, _ repeats: Bool, _ tick: @escaping @Sendable (Timer) -> Void) -> Timer {
            let timer = Timer(timeInterval: period, repeats: repeats, block: tick)
            if !repeats { wheel = (time + period, timer) }
            return timer
        }
    }

    @MainActor
    private final class RecordingOutput: WindowFrameCrankSoundOutput {
        var played: [WindowFrameCrankCue] = []
        var stops = 0
        func warm() {}
        func play(_ cue: WindowFrameCrankCue) { played.append(cue) }
        func stop() { stops += 1 }
    }

    @MainActor
    private final class FocusView: NSView {
        override var acceptsFirstResponder: Bool { true }
    }

    @MainActor
    private struct LightsImage {
        let lights: WindowFrameCrankLightsView
        let bitmap: NSBitmapImageRep

        init() throws {
            let frame = CGRect(x: 0, y: 0, width: CrankView.side, height: CrankView.side)
            lights = WindowFrameCrankLightsView(frame: frame, litCount: 8, readout: 10, palette: lightPalette)
            let image = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(frame.width),
                                                       pixelsHigh: Int(frame.height), bitsPerSample: 8, samplesPerPixel: 4,
                                                       hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                                       bytesPerRow: 0, bitsPerPixel: 0))
            bitmap = image
            let context = try #require(NSGraphicsContext(bitmapImageRep: image))
            NSGraphicsContext.saveGraphicsState()
            defer { NSGraphicsContext.restoreGraphicsState() }
            NSGraphicsContext.current = context
            context.cgContext.clear(frame)
            lights.draw(frame)
        }

        func alpha(at point: CGPoint) -> CGFloat {
            bitmap.colorAt(x: Int(point.x), y: Int(lights.bounds.height - point.y))?.alphaComponent ?? 0
        }
    }

    @MainActor
    private struct CrankImage {
        let bitmap: NSBitmapImageRep

        init(model: WindowFrameCrankModel) throws {
            let device = try #require(MTLCreateSystemDefaultDevice())
            let renderer = SCNRenderer(device: device, options: nil)
            renderer.scene = model.scene
            renderer.pointOfView = model.camera
            renderer.autoenablesDefaultLighting = false
            let side = CrankView.side
            let snapshot = renderer.snapshot(atTime: 0, with: CGSize(width: side, height: side), antialiasingMode: .none)
            var rect = CGRect(origin: .zero, size: snapshot.size)
            bitmap = NSBitmapImageRep(cgImage: try #require(snapshot.cgImage(forProposedRect: &rect, context: nil, hints: nil)))
        }

        func alpha(x: CGFloat, y: CGFloat) -> CGFloat {
            let side = CrankView.side
            let column = Int((side / 2 + x) * CGFloat(bitmap.pixelsWide) / side)
            let row = Int((side / 2 - y) * CGFloat(bitmap.pixelsHigh) / side)
            return bitmap.colorAt(x: column, y: row)?.alphaComponent ?? 0
        }
    }
}
