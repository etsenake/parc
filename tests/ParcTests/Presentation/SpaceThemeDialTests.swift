import AppKit
import Testing
import ParcCore
@testable import Parc

extension SpaceThemeControlTests {
    private func noiseTheme(_ value: Double) -> SpaceTheme {
        var theme = SpaceTheme()
        theme.noise = value
        return theme
    }

    private func right(_ f: Fixture) -> NSPoint { NSPoint(x: f.noise.bounds.width - 2, y: f.noise.bounds.midY) }
    private func bottom(_ f: Fixture) -> NSPoint { NSPoint(x: f.noise.bounds.midX, y: f.noise.bounds.height - 2) }
    private func offset(_ f: Fixture, _ x: CGFloat, _ y: CGFloat) -> NSPoint {
        NSPoint(x: f.noise.bounds.midX + x, y: f.noise.bounds.midY + y)
    }

    @Test func aDialDragWaitsForTenPointsBeforeEditing() throws {
        let f = try Fixture(noiseTheme(0.25))
        try f.press(f.noise, right(f))
        try f.drag(f.noise, NSPoint(x: right(f).x - 3, y: right(f).y + 2))
        #expect(f.view.theme.noise == 0.25)
        #expect(f.previews == 0)
    }

    @Test func aRecognizedDialDragPreviewsTheAbsoluteClockwiseAngle() throws {
        let f = try Fixture(noiseTheme(0.25))
        try f.press(f.noise, right(f))
        try f.drag(f.noise, bottom(f))
        #expect(Self.near(f.view.theme.noise, 0.5))
        #expect(f.commits == 0)
    }

    @Test func aDialDragCommitsWhenThePointerReleases() throws {
        let f = try Fixture(noiseTheme(0.25))
        try f.press(f.noise, right(f))
        try f.drag(f.noise, bottom(f))
        try f.release(f.noise, bottom(f))
        #expect(f.commits == 1)
    }

    @Test func aRotationWaitsForOneDegree() throws {
        let f = try Fixture(noiseTheme(0.5))
        f.rotate(.began, 0.4)
        f.rotate(.changed, 0.4)
        #expect(f.view.theme.noise == 0.5)
    }

    @Test func subthresholdRotationAccumulatesAtHalfARevolutionPerTurn() throws {
        let f = try Fixture(noiseTheme(0.5))
        f.rotate(.began, 0.4)
        f.rotate(.changed, 0.4)
        f.rotate(.changed, 0.4)
        #expect(Self.near(f.view.theme.noise, 0.5 + 1.2 / 720))
    }

    private func recognizedRotation(_ f: Fixture) {
        f.rotate(.began, 0.4)
        f.rotate(.changed, 0.4)
        f.rotate(.changed, 0.4)
        f.rotate(.changed, 72)
    }

    @Test func laterRotationAppliesEachEventsDeltaOnce() throws {
        let f = try Fixture(noiseTheme(0.5))
        recognizedRotation(f)
        #expect(Self.near(f.view.theme.noise, 0.6 + 1.2 / 720))
    }

    @Test func theEndOfARotationDoesNotReplayASample() throws {
        let f = try Fixture(noiseTheme(0.5))
        recognizedRotation(f)
        f.rotate(.ended, 99)
        #expect(Self.near(f.view.theme.noise, 0.6 + 1.2 / 720))
        #expect(f.commits == 1)
    }

    @Test func undoRestoresTheWholeRotation() throws {
        let f = try Fixture(noiseTheme(0.5))
        recognizedRotation(f)
        f.rotate(.ended)
        f.view.undo(nil)
        #expect(Self.near(f.view.theme.noise, 0.5))
    }

    @Test func negativeRotationClampsAtZero() throws {
        let f = try Fixture(noiseTheme(0.5))
        f.rotate(.began, -720)
        #expect(f.view.theme.noise == 0)
    }

    @Test func aCancelledRotationCommitsItsAdmittedValueOnce() throws {
        let f = try Fixture(noiseTheme(0.5))
        f.rotate(.began, -720)
        f.rotate(.cancelled)
        #expect(f.commits == 1)
        #expect(f.view.theme.noise == 0)
    }

    @Test func aClickInsideTheKnobsCircleCyclesTheTexture() throws {
        let f = try Fixture(noiseTheme(0.5))
        try f.click(f.noise, offset(f, 19, 0))
        #expect(f.view.theme.texture == .sand)
        #expect(f.view.theme.noise == 0.5)
        #expect(f.commits == 1)
    }

    @Test func aClickBeyondTheKnobsCircleSetsTheDialByAngle() throws {
        let f = try Fixture(noiseTheme(0.5))
        try f.click(f.noise, offset(f, 24, 0))
        #expect(f.view.theme.texture == .grain)
        #expect(Self.near(f.view.theme.noise, 0.25))
        #expect(f.commits == 1)
    }

    @Test func theKnobFramesCornerOutsideTheCircleBelongsToTheRing() throws {
        let f = try Fixture(noiseTheme(0.5))
        try f.click(f.noise, offset(f, 19, 8))
        #expect(f.view.theme.texture == .grain)
        #expect(Self.near(f.view.theme.noise, 0.3))
        #expect(f.commits == 1)
    }

    @Test func aKnobPressNeverDragsTheDialAndReleasingOutsideDoesNothing() throws {
        let f = try Fixture(noiseTheme(0.5))
        try f.press(f.noise, f.center(f.noise))
        try f.drag(f.noise, right(f))
        try f.drag(f.noise, bottom(f))
        try f.release(f.noise, bottom(f))
        #expect(f.view.theme == noiseTheme(0.5))
        #expect(f.commits == 0)
    }

    @Test func aKnobPressReleasedBackOnTheKnobStillClicks() throws {
        let f = try Fixture(noiseTheme(0.5))
        try f.press(f.noise, f.center(f.noise))
        try f.drag(f.noise, right(f))
        try f.release(f.noise, offset(f, -10, 10))
        #expect(f.view.theme.texture == .sand)
        #expect(f.commits == 1)
    }

    @Test func aRotationThatBeginsOverTheRingIsIgnored() throws {
        let f = try Fixture(noiseTheme(0.5))
        let ring = offset(f, 24, 0)
        f.rotate(at: ring, .began, 36)
        f.rotate(at: ring, .changed, 36)
        f.rotate(at: ring, .ended)
        #expect(f.view.theme.noise == 0.5)
        #expect(f.commits == 0)
    }

    @Test func aRotationThatBeginsOnTheKnobAdjustsTheNoiseOnce() throws {
        let f = try Fixture(noiseTheme(0.5))
        let knob = offset(f, 0, -19)
        f.rotate(at: knob, .began, 18)
        f.rotate(at: knob, .ended)
        #expect(Self.near(f.view.theme.noise, 0.525))
        #expect(f.commits == 1)
    }

    @Test func theKnobFramesCornerShowsThePointingHand() throws {
        let f = try Fixture(noiseTheme(0.5))
        try f.move(f.noise, offset(f, 19, 19))
        #expect(f.cursor.current == .pointingHand)
    }

    @Test func beyondTheKnobFrameTheDialShowsTheOpenHand() throws {
        let f = try Fixture(noiseTheme(0.5))
        try f.move(f.noise, offset(f, 24, 0))
        #expect(f.cursor.current == .openHand)
    }

    @Test(arguments: [(19.0, 19.0, 0.45), (24.0, 0.0, 0.3)])
    func theWheelCountsOnlyTheKnobsRectangularFrameAsTheCentre(example: (Double, Double, Double)) throws {
        let f = try Fixture(noiseTheme(0.3))
        try f.move(f.noise, offset(f, example.0, example.1))
        f.scroll(phase: .began, 1)
        f.delivery.deliver()
        #expect(Self.near(f.view.theme.noise, example.2))
    }

    private func knobTexture(_ noise: NSView) throws -> [NSColor] {
        let rep = try Self.snapshot(noise)
        let scale = CGFloat(rep.pixelsWide) / noise.bounds.width
        return try (0..<12).map { index in
            let angle = Double(index) * .pi / 6, radius = 6 + Double(index % 3) * 4
            return try #require(rep.colorAt(x: Int((noise.bounds.midX + CGFloat(cos(angle) * radius)) * scale),
                                            y: Int((noise.bounds.midY + CGFloat(sin(angle) * radius)) * scale)))
        }
    }

    @Test func aKnobPressScalesItsTexture() throws {
        let f = try Fixture()
        try f.hoverCenter()
        let resting = try knobTexture(f.noise)
        try f.press(f.noise, f.center(f.noise))
        #expect(try knobTexture(f.noise) != resting)
    }

    @Test func aRotationThatStartsDuringAKnobPressReleasesIt() throws {
        let f = try Fixture()
        try f.hoverCenter()
        let resting = try knobTexture(f.noise)
        try f.press(f.noise, f.center(f.noise))
        f.rotate(.began, 36)
        #expect(try knobTexture(f.noise) == resting)
    }

    @Test func aReleasedKnobPressStaysReleasedForTheRestOfThatPress() throws {
        let f = try Fixture()
        try f.hoverCenter()
        let resting = try knobTexture(f.noise)
        try f.press(f.noise, f.center(f.noise))
        f.rotate(.began, 36)
        try f.drag(f.noise, f.center(f.noise))
        #expect(try knobTexture(f.noise) == resting)
    }

    @Test func releasingAfterTheRotationLeavesTheKnobAtRest() throws {
        let f = try Fixture()
        try f.hoverCenter()
        let resting = try knobTexture(f.noise)
        try f.press(f.noise, f.center(f.noise))
        f.rotate(.began, 36)
        f.rotate(.ended)
        try f.release(f.noise, f.center(f.noise))
        #expect(try knobTexture(f.noise) == resting)
    }

    @Test func pressingAChevronDrawsItAtThePressScale() throws {
        let f = try Fixture()
        let next = try f.button("Next color presets")
        let idle = try Self.pixels(next)
        next.highlight(true)
        #expect(try Self.pixels(next) != idle)
    }

    @Test func releasingAChevronReturnsItToRest() throws {
        let f = try Fixture()
        let next = try f.button("Next color presets")
        let idle = try Self.pixels(next)
        next.highlight(true)
        next.highlight(false)
        #expect(try Self.pixels(next) == idle)
    }

    @Test func theFirstDeliveredWheelTickCommitsOnItsOwn() throws {
        let f = try Fixture(noiseTheme(0.5))
        try f.hoverCenter()
        f.scroll(phase: .began, 1)
        f.delivery.deliver()
        #expect(f.commits == 1)
    }

    private func twoWheelTicks(_ f: Fixture) throws {
        try f.hoverCenter()
        f.scroll(phase: .began, 1)
        f.delivery.deliver()
        f.scroll(phase: .changed, -100)
        f.scroll(phase: .changed, 0.001)
        f.delivery.deliver()
    }

    @Test func theLatestWheelDirectionWinsWithoutScalingByMagnitude() throws {
        let f = try Fixture(noiseTheme(0.5))
        try twoWheelTicks(f)
        #expect(Self.near(f.view.theme.noise, 0.8))
        #expect(f.commits == 2)
    }

    @Test func wheelUndoReversesOneTick() throws {
        let f = try Fixture(noiseTheme(0.5))
        try twoWheelTicks(f)
        f.view.undo(nil)
        #expect(Self.near(f.view.theme.noise, 0.65))
    }

    private func inheritedWheelAfterUndo(_ f: Fixture) throws {
        try twoWheelTicks(f)
        f.view.undo(nil)
        f.scroll(phase: .changed, 1)
        f.scroll(momentum: .changed, 1)
        f.delivery.deliver()
    }

    @Test func undoRejectsInheritedPhysicalAndMomentumWheelInput() throws {
        let f = try Fixture(noiseTheme(0.5))
        try inheritedWheelAfterUndo(f)
        #expect(Self.near(f.view.theme.noise, 0.65))
    }

    @Test func aRejectedWheelContinuationKeepsRedo() throws {
        let f = try Fixture(noiseTheme(0.5))
        try inheritedWheelAfterUndo(f)
        f.view.redo(nil)
        #expect(Self.near(f.view.theme.noise, 0.8))
    }

    @Test func aNewPhysicalWheelBeginResumesAfterCancellation() throws {
        let f = try Fixture(noiseTheme(0.5))
        try inheritedWheelAfterUndo(f)
        f.scroll(phase: .began, -1)
        f.delivery.deliver()
        #expect(Self.near(f.view.theme.noise, 0.55))
    }

    @Test func aLatestZeroWheelDeltaIsFilteredAfterThrottling() throws {
        let f = try Fixture(noiseTheme(0.5))
        try f.hoverCenter()
        f.scroll(phase: .began, -1)
        f.delivery.deliver()
        let before = f.view.theme, commits = f.commits
        f.scroll(phase: .changed, 1)
        f.scroll(phase: .ended, 0)
        f.delivery.deliver()
        #expect(f.view.theme == before)
        #expect(f.commits == commits)
    }

    @Test func aNewRotationRetiresPendingWheelInputEvenWhenItEndsBeforeDelivery() throws {
        let f = try Fixture()
        try f.hoverCenter()
        f.scroll(phase: .began, 1)
        f.rotate(.began, 72)
        f.rotate(.ended)
        let rotated = f.view.theme
        f.delivery.deliver()
        #expect(f.view.theme == rotated)
        #expect(f.commits == 1)
    }

    @Test func enteringTheCentreBeforeDeliveryAdmitsATickObservedOverTheRing() throws {
        let f = try Fixture(noiseTheme(0.4))
        f.scroll(phase: .began, 1)
        try f.hoverCenter()
        f.delivery.deliver()
        #expect(Self.near(f.view.theme.noise, 0.55))
    }

    @Test func aPendingThrottledWheelTickDoesNotRetainARetiredEditor() throws {
        weak var released: SpaceThemeEditorView?
        try autoreleasepool {
            _ = NSApplication.shared
            let editor = SpaceThemeEditorView(theme: SpaceTheme(), performHapticFeedback: {}, cursor: CursorLog().cursor,
                                              resources: ThemeEditorResources(bundle: .module))
            editor.layoutSubtreeIfNeeded()
            released = editor
            let noise = try Self.control("Theme texture and noise", in: editor)
            noise.mouseMoved(with: try Self.mouse(.mouseMoved, noise, NSPoint(x: noise.bounds.midX, y: noise.bounds.midY)))
            noise.scrollWheel(with: ThemeEvent(phase: .began, delta: 1))
        }
        #expect(released == nil)
    }

    private func noiseAnchor(_ f: Fixture) throws -> TooltipAnchorView {
        let anchors = f.noise.subviews.compactMap { $0 as? TooltipAnchorView }
        try #require(anchors.count == 1)
        return anchors[0]
    }

    @Test func theDialsSquareAndRingCarryNoTooltipOfTheirOwn() throws {
        let f = try Fixture()
        #expect(f.noise.parcTooltip == nil)
        #expect(f.noise.subviews.compactMap { $0 as? TooltipAnchorView }.count == 1)
    }

    @Test func theNoiseTooltipBelongsToTheDialsCentreKnobAndSitsBelowIt() throws {
        let f = try Fixture()
        let anchor = try noiseAnchor(f)
        #expect(f.noise.bounds.size == NSSize(width: 80, height: 80))
        #expect(anchor.frame == NSRect(x: 20, y: 20, width: 40, height: 40))
        #expect(anchor.parcTooltip == TooltipConfiguration("Noise", anchor: .bottom))
    }

    @Test func theNoiseTooltipAnchorFollowsTheKnobWhenTheDialResizes() throws {
        let f = try Fixture()
        let anchor = try noiseAnchor(f)
        f.noise.setFrameSize(NSSize(width: 100, height: 100))
        #expect(anchor.frame == NSRect(x: 25, y: 25, width: 50, height: 50))
    }

    @Test func theEditorsTooltipsLeaveTheirPaletteToThePopoverWindow() throws {
        let f = try Fixture()
        let tooltips = Self.descendants(f.view).compactMap(\.parcTooltip)
        #expect(tooltips.count >= 6)
        #expect(tooltips.allSatisfy { $0.palette == nil })
    }

    @Test func theNoiseTooltipTracksThePointerOnlyInsideItsAnchor() throws {
        let f = try Fixture()
        let anchor = try noiseAnchor(f)
        let areas = anchor.trackingAreas
        #expect(areas.count == 1)
        #expect(areas.allSatisfy { $0.options.contains(.inVisibleRect) && $0.options.contains(.mouseEnteredAndExited) })
    }

    @Test(arguments: [(30.0, 0.0, false), (-30.0, -30.0, false), (19.0, 19.0, true)])
    func theNoiseTooltipRegionIsTheCentreKnobsFrame(example: (Double, Double, Bool)) throws {
        let f = try Fixture()
        let anchor = try noiseAnchor(f)
        let region = f.noise.convert(anchor.bounds, from: anchor)
        #expect(region.contains(offset(f, example.0, example.1)) == example.2)
    }

    @Test func inAWindowClicksOnTheKnobStillReachTheDial() throws {
        let f = try Fixture(hosted: true)
        let superview = try #require(f.noise.superview)
        #expect(f.noise.hitTest(f.noise.convert(f.center(f.noise), to: superview)) === f.noise)
    }
}
