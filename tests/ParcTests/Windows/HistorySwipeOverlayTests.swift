import CoreGraphics
import Foundation
@testable import ParcCore
import Testing
@testable import Parc

struct HistorySwipeOverlayTests {
    private func close(_ a: Double, _ b: Double, _ tolerance: Double = 1e-6) -> Bool { abs(a - b) <= tolerance }
    private func close(_ a: CGFloat, _ b: CGFloat, _ tolerance: CGFloat = 1e-6) -> Bool { abs(a - b) <= tolerance }
    private func close(_ a: CGRect, _ b: CGRect, _ tolerance: CGFloat = 1e-6) -> Bool {
        close(a.minX, b.minX, tolerance) && close(a.minY, b.minY, tolerance)
            && close(a.width, b.width, tolerance) && close(a.height, b.height, tolerance)
    }

    @Test
    func circleMetricsMatchTheRestingAndArmedDesign() {
        #expect(Metrics.restingDiameter == 72 && Metrics.armedDiameter == 82 && Metrics.edgeInset == 14)
    }

    @Test
    func chevronMetricsMatchTheRestingAndArmedDesign() {
        #expect(Metrics.restingChevron == 28 && Metrics.armedChevron == 34 && Metrics.chevronPointSize == 28 && Metrics.restingChevronOpacity == 0.5)
    }

    @Test
    func cardMetricsFitHistoryRows() {
        #expect(Metrics.cardWidth == 200 && Metrics.rowHeight == 38 && Metrics.cardInset == 8 && Metrics.cardRadius == 18)
    }

    @Test
    func rowMetricsFitTitlesAndFavicons() {
        #expect(Metrics.highlightRadius == 10 && Metrics.faviconSize == 16 && Metrics.faviconRadius == 4 && Metrics.titleSize == 13 && Metrics.titleGap == 8)
    }

    @Test
    func ringAndShadowMetricsMatchTheIndicator() {
        #expect(Metrics.ringWidth == 1 && Metrics.shadowRadius == 8 && Metrics.shadowDrop == 2)
    }

    @Test
    func overlaySpringsUseTheGestureTimings() {
        #expect(Timing.arm == .init(damping: 0.70, response: 0.18) && Timing.morph == .init(damping: 0.77, response: 0.22)
              && Timing.selection == .init(damping: 0.9, response: 0.27))
    }

    @Test
    func theListSwapFadesScalesAndBlurs() {
        #expect(Timing.fade == 0.18 && Timing.swap == 0.22 && Timing.swapScale == 0.9 && Timing.blur == 10)
    }

    @Test
    func endingScalesTheIndicatorDown() {
        #expect(Timing.collapse == 0.2 && Timing.collapseScale == 0.01)
    }

    @Test
    func reduceMotionMetricsUseShortCrossfades() {
        #expect(Metrics.reducedAppearance == 0.2 && Timing.reducedFade == 0.12 && Timing.reducedSwap == 0.15 && Timing.reducedCollapse == 0.15)
    }

    @Test
    func theLeanUsesARubberBand() {
        #expect(Metrics.rowLean == 0.1)
    }

    @Test
    func easingCurvesHaveFixedEndpoints() {
        let out = HistorySwipeCurve.easeOut, ease = HistorySwipeCurve.easeIn
        #expect(out(0) == 0 && out(1) == 1 && ease(0) == 0 && ease(1) == 1)
    }

    @Test
    func easingCurvesBiasTheMidpoint() {
        let out = HistorySwipeCurve.easeOut, ease = HistorySwipeCurve.easeIn
        #expect(close(out(0.5), 0.7713235628639843, 1e-6) && close(ease(0.5), 0.31535681250589304, 1e-6))
    }

    @Test(arguments: 0..<100)
    func easeOutNeverRunsBackward(sample: Int) {
        let current = Double(sample) / 100
        let next = Double(sample + 1) / 100
        #expect(HistorySwipeCurve.easeOut(current) <= HistorySwipeCurve.easeOut(next))
    }

    @Test
    func linearEasingPreservesProgress() {
        #expect(HistorySwipeCurve.linear(0.3) == 0.3)
    }

    @Test
    func springPositionAndVelocityAreIndependentOfFrameRate() {
        var arm = HistorySwipeSpring(72, Timing.arm, tolerance: 0.01)
        var stepped = arm
        arm.advance(toward: 82, by: 0.1)
        for _ in 0..<100 { stepped.advance(toward: 82, by: 0.001) }
        #expect(close(arm.value, stepped.value, 1e-9) && close(arm.velocity, stepped.velocity, 1e-7))
    }

    @Test
    func armingSpringPeaksAtTheDampedHalfPeriod() {
        let zeta = 0.70, omega = 2 * Double.pi / 0.18, damped = omega * (1 - zeta * zeta).squareRoot()
        var peak = HistorySwipeSpring(72, Timing.arm, tolerance: 0.0001)
        peak.advance(toward: 82, by: Double.pi / damped)
        #expect(close(peak.value, 82 + 10 * exp(-zeta * Double.pi / (1 - zeta * zeta).squareRoot()), 1e-9)
              && abs(peak.velocity) < 1e-9)
    }

    @Test
    func armingSpringSnapsToRest() {
        var settle = HistorySwipeSpring(72, Timing.arm, tolerance: 0.01)
        settle.advance(toward: 82, by: 0.6)
        #expect(settle.value == 82 && settle.velocity == 0)
    }

    @Test
    func criticalAndOverdampedSpringsApproachWithoutOvershoot() {
        var critical = HistorySwipeSpring(0, .init(damping: 1, response: 0.2), tolerance: 1e-6)
        var heavy = HistorySwipeSpring(0, .init(damping: 1.5, response: 0.2), tolerance: 1e-6)
        critical.advance(toward: 1, by: 0.1)
        heavy.advance(toward: 1, by: 0.1)
        #expect(critical.value > 0 && critical.value < 1 && heavy.value > 0 && heavy.value < critical.value)
    }

    @Test(arguments: [HistorySwipeDirection.back, .forward])
    func theCircleStartsJustOutsideThePane(direction: HistorySwipeDirection) throws {
        var driver = Driver()
        driver.send(.begin(direction))
        let circle = try #require(driver.frame).circle
        if direction == .back {
            #expect(circle.maxX == 0)
        } else {
            #expect(circle.minX == Self.pane.width)
        }
    }

    @Test
    func theCircleTracksFingerTravelImmediately() {
        var back = Driver()
        back.send(.begin(.back))
        back.progress(0.5)
        #expect(back.frame.map { close($0.circle.minX, 0.5 * 86 - 72) } == true)
    }

    @Test
    func backPlacesTheCircleAtItsInsetAtCommit() {
        var back = Driver()
        back.send(.begin(.back))
        back.progress(1)
        #expect(back.frame.map { close($0.circle.minX, 14) && close($0.circle.midY, Self.pane.height / 2) } == true)
    }

    @Test
    func forwardMirrorsTheInsetAtCommit() {
        var forward = Driver()
        forward.send(.begin(.forward))
        forward.progress(1)
        #expect(forward.frame.map { close($0.circle.maxX, Self.pane.width - 14) } == true)
    }

    @Test
    func theChevronIsCenteredInTheCircle() {
        var forward = Driver()
        forward.send(.begin(.forward))
        forward.progress(1)
        #expect(forward.frame.map { close($0.chevronCenter.x, $0.circle.midX) && close($0.chevronCenter.y, $0.circle.midY) } == true)
    }

    @Test
    func theRestingCircleFollowsTheRubberBandPastCommit() {
        var back = Driver()
        back.send(.begin(.back))
        back.progress(band(2))
        #expect(back.frame.map { close($0.circle.minX, 14 + 86 * (band(2) - 1)) } == true)
    }

    @Test
    func theArmedCircleFollowsTheRubberBandAtItsLargerSize() {
        var armed = Driver.armed(stretch: band(2))
        #expect(armed.frame.map { abs($0.circle.minX - 26.5) < 0.1 && close($0.circle.width, 82) } == true)
        armed.progress(band(1.5))
        #expect(armed.frame.map { close($0.circle.minX, CGFloat(band(1.5)) * 96 - 82) } == true)
    }

    @Test
    func theUnarmedChevronIsSmallAndDim() {
        var driver = Driver()
        driver.send(.begin(.back))
        driver.progress(1)
        #expect(driver.frame.map { $0.wash == 0 && $0.chevronOpacity == 0.5 && $0.chevronSize == 28 } == true)
    }

    @Test
    func armingPlaysALevelChangeHaptic() {
        var driver = Driver()
        driver.send(.begin(.back))
        driver.progress(1)
        driver.send(.armed(true))
        #expect(driver.haptics == [.levelChange])
    }

    @Test
    func armingBrightensTheWashAndChevronWithEaseOut() {
        var driver = Driver()
        driver.send(.begin(.back))
        driver.progress(1)
        driver.send(.armed(true))
        driver.advance(0.09)
        let half = HistorySwipeCurve.easeOut(0.5)
        #expect(driver.frame.map { close($0.wash, half) && close($0.chevronOpacity, 0.5 + 0.5 * half) } == true)
    }

    @Test
    func armingCompletesTheFade() {
        var driver = Driver()
        driver.send(.begin(.back))
        driver.progress(1)
        let start = driver.time
        driver.send(.armed(true))
        driver.advance(0.09)
        driver.advance(0.6)
        #expect(driver.frame.map { $0.wash == 1 && $0.chevronOpacity == 1 } == true && driver.time - start > Timing.fade)
    }

    @Test
    func armingOvershootsTheCircleDiameterAndSettles() throws {
        var driver = Driver()
        driver.send(.begin(.back))
        driver.progress(1)
        driver.send(.armed(true))
        driver.advance(0.09)
        var sizes: [CGFloat] = []
        for _ in 0..<60 {
            driver.advance(0.01)
            if let frame = driver.frame { sizes.append(frame.circle.width) }
        }
        let peak = try #require(sizes.max())
        #expect(peak > 82.3 && peak < 82.6)
        #expect(sizes.last == 82)
    }

    @Test
    func theArmedChevronRestsAtFullSize() {
        var driver = Driver()
        driver.send(.begin(.back))
        driver.progress(1)
        driver.send(.armed(true))
        driver.advance(0.09)
        var sizes: [CGFloat] = []
        for _ in 0..<60 {
            driver.advance(0.01)
            if let frame = driver.frame { sizes.append(frame.circle.width) }
        }
        #expect(driver.frame?.chevronSize == 34 && !driver.model.isAnimating)
    }

    @Test
    func disarmingIsSilent() {
        var driver = Driver()
        driver.send(.begin(.back))
        driver.progress(1)
        driver.send(.armed(true))
        driver.send(.armed(false))
        #expect(driver.haptics == [.levelChange])
    }

    @Test
    func disarmingFadesTheWashAndChevron() {
        var driver = Driver()
        driver.send(.begin(.back))
        driver.progress(1)
        driver.send(.armed(true))
        driver.advance(0.6)
        driver.send(.armed(false))
        driver.advance(Timing.fade + 0.0001)
        #expect(driver.frame?.wash == 0 && driver.frame?.chevronOpacity == 0.5)
    }

    @Test
    func disarmingReturnsTheCircleAndChevronToRest() {
        var driver = Driver()
        driver.send(.begin(.back))
        driver.progress(1)
        driver.send(.armed(true))
        driver.advance(0.6)
        driver.send(.armed(false))
        driver.settle()
        #expect(driver.frame?.circle.width == 72 && driver.frame?.chevronSize == 28)
    }

    @Test
    func committingCollapsesInPlaceWithBlurAndFade() throws {
        var commit = Driver.armed()
        let before = try #require(commit.frame).capsule
        commit.send(.commit(.adjacent(.back)))
        commit.advance(0.1)
        let amount = HistorySwipeCurve.easeIn(0.5)
        #expect(commit.frame.map { close($0.opacity, 1 - amount) && close($0.scale, 1 - 0.99 * amount)
                && close($0.blur, 10 * amount) && close($0.capsule, before) } == true)
    }

    @Test
    func commitAndCancelHaveTheSameCollapse() {
        var commit = Driver.armed()
        var cancel = Driver.armed()
        commit.send(.commit(.adjacent(.back)))
        cancel.send(.cancel)
        commit.advance(0.1)
        cancel.advance(0.1)
        #expect(commit.frame == cancel.frame)
    }

    @Test(arguments: [HistorySwipeOutput.commit(.adjacent(.back)), .cancel])
    func endingDoesNotPlayAHaptic(output: HistorySwipeOutput) {
        var driver = Driver.armed()
        driver.send(output)
        #expect(driver.haptics == [.levelChange])
    }

    @Test
    func theIndicatorIsGoneAfterCollapse() {
        var commit = Driver.armed()
        commit.send(.commit(.adjacent(.back)))
        commit.advance(0.1)
        commit.advance(0.1001)
        #expect(commit.frame == nil && !commit.model.isAnimating)
    }

    @Test
    func lateProgressCannotReviveTheIndicator() {
        var commit = Driver.armed()
        commit.send(.commit(.adjacent(.back)))
        commit.advance(0.1)
        commit.advance(0.1001)
        commit.send(.progress(HistorySwipeProgress(fraction: 1, stretch: 1)))
        #expect(commit.frame == nil)
    }

    @Test
    func openingTheListPlaysAGenericHaptic() {
        var driver = Driver.armed(back: 3)
        driver.send(.hold)
        driver.send(.selection(0))
        #expect(driver.haptics == [.levelChange, .generic])
    }

    @Test
    func theListStartsHiddenInsideTheCircle() throws {
        var driver = Driver.armed(back: 3)
        let circle = try #require(driver.frame).circle
        driver.send(.hold)
        driver.send(.selection(0))
        #expect(driver.frame.map { close($0.capsule, circle) && $0.list?.opacity == 0 && $0.list?.scale == 0.9
                && $0.list?.blur == 10 && $0.chevronOpacity == 1 } == true)
    }

    @Test
    func theListAndChevronEaseThroughTheSwap() throws {
        var driver = Driver.armed(back: 3)
        driver.send(.hold)
        driver.send(.selection(0))
        driver.advance(0.11)
        let half = HistorySwipeCurve.easeOut(0.5)
        let frame = try #require(driver.frame)
        let list = try #require(frame.list)
        #expect(close(list.opacity, half) && close(frame.chevronScale, 1 - 0.1 * half)
                && close(frame.chevronBlur, 10 * half) && close(frame.chevronOpacity, 1 - half))
    }

    @Test
    func theCircleMorphsTowardTheCardOnASpring() {
        var driver = Driver.armed(back: 3)
        driver.send(.hold)
        driver.send(.selection(0))
        let opened = driver.time
        driver.advance(0.11)
        let zeta = 0.77, omega = 2 * Double.pi / 0.22, damped = omega * (1 - zeta * zeta).squareRoot()
        let t = driver.time - opened
        let morph = 1 - exp(-zeta * omega * t) * (cos(damped * t) + zeta * omega / damped * sin(damped * t))
        #expect(driver.frame.map { close($0.capsule.width, 82 + (200 - 82) * CGFloat(morph), 1e-6) } == true)
    }

    @Test
    func theSwapEndsWithOnlyTheUnblurredList() {
        var driver = Driver.armed(back: 3)
        driver.send(.hold)
        driver.send(.selection(0))
        driver.advance(0.11)
        driver.advance(0.1101)
        #expect(driver.frame.map { $0.list?.opacity == 1 && $0.list?.scale == 1 && $0.list?.blur == 0 && $0.chevronOpacity == 0 } == true)
    }

    @Test
    func theOpenCardRestsAtItsListGeometry() throws {
        var driver = Driver.armed(back: 3)
        driver.send(.hold)
        driver.send(.selection(0))
        driver.settle()
        let frame = try #require(driver.frame)
        let list = try #require(frame.list)
        #expect(close(frame.capsule, list.card) && frame.cornerRadius == 18)
    }

    @Test
    func theCardFitsTheCurrentPageAndHistoryRows() throws {
        let back = Driver.holding(.back, back: 3)
        let frame = try #require(back.frame)
        let list = try #require(frame.list)
        #expect(list.rows == 4 && close(list.card.width, 200) && close(list.card.height, 4 * 38 + 16))
    }

    @Test
    func theBackCardAnchorsToTheLeftEdge() throws {
        let back = Driver.holding(.back, back: 3)
        let frame = try #require(back.frame)
        let list = try #require(frame.list)
        #expect(close(list.card.minX, frame.circle.minX))
    }

    @Test
    func theForwardCardAnchorsToTheRightEdge() throws {
        let forward = Driver.holding(.forward, forward: 3)
        let ahead = try #require(forward.frame)
        let rows = try #require(ahead.list)
        #expect(close(rows.card.maxX, ahead.circle.maxX))
    }

    @Test
    func theListHighlightsTheCurrentPageAtTheCircleCenter() throws {
        let back = Driver.holding(.back, back: 3)
        let frame = try #require(back.frame)
        let list = try #require(frame.list)
        #expect(list.selection == 0 && close(list.highlight.midY, frame.circle.midY) && close(list.row(0), list.highlight))
    }

    @Test
    func backRowsStackAboveTheCurrentPage() throws {
        let back = Driver.holding(.back, back: 3)
        let frame = try #require(back.frame)
        let list = try #require(frame.list)
        #expect(close(list.row(1).maxY, list.row(0).minY) && close(list.row(2).maxY, list.row(1).minY)
              && close(list.row(3).maxY, list.row(2).minY))
    }

    @Test
    func forwardRowsStackBelowTheCurrentPage() throws {
        let forward = Driver.holding(.forward, forward: 3)
        let rows = try #require(forward.frame?.list)
        #expect(close(rows.row(0), rows.highlight) && close(rows.row(1).minY, rows.row(0).maxY)
              && close(rows.row(3).minY, rows.row(2).maxY))
    }

    @Test
    func rowsAndHighlightSitInsideTheCardInsets() throws {
        let back = Driver.holding(.back, back: 3)
        let frame = try #require(back.frame)
        let list = try #require(frame.list)
        #expect(close(list.row(0).minX, list.content.minX + 8) && close(list.row(0).width, 184)
              && close(list.highlight.width, 184))
    }

    @Test
    func eachHistoryDetentPlaysAnAlignmentHaptic() {
        var driver = Driver.holding(.back, back: 3)
        driver.send(.selection(1))
        driver.send(.detent)
        #expect(driver.haptics.last == .alignment)
    }

    @Test
    func theCardSlidesWhileTheHighlightStaysStill() throws {
        var driver = Driver.holding(.back, back: 3)
        let before = try #require(driver.frame?.list).content
        driver.send(.selection(1))
        driver.advance(0.1)
        let moving = try #require(driver.frame?.list)
        #expect(close(moving.highlight.midY, Self.pane.height / 2) && moving.content.minY > before.minY
              && moving.content.minY < before.minY + 38)
    }

    @Test
    func theCardFollowsTheSelectionSpring() throws {
        var driver = Driver.holding(.back, back: 3)
        let before = try #require(driver.frame?.list).content
        driver.send(.selection(1))
        driver.advance(0.1)
        let moving = try #require(driver.frame?.list)
        let zeta = 0.9, omega = 2 * Double.pi / 0.27, damped = omega * (1 - zeta * zeta).squareRoot()
        let shift = 38 * (1 - exp(-zeta * omega * 0.1) * (cos(damped * 0.1) + zeta * omega / damped * sin(damped * 0.1)))
        #expect(close(moving.content.minY, before.minY + CGFloat(shift), 1e-6))
    }

    @Test
    func aBackStepSettlesThePreviousPageUnderTheHighlight() throws {
        var driver = Driver.holding(.back, back: 3)
        let before = try #require(driver.frame?.list).content
        driver.send(.selection(1))
        driver.settle()
        let settled = try #require(driver.frame?.list)
        #expect(close(settled.content.minY, before.minY + 38) && close(settled.row(1), settled.highlight))
    }

    @Test
    func aForwardStepSlidesTheCardUp() throws {
        var forward = Driver.holding(.forward, forward: 3)
        let top = try #require(forward.frame?.list).content
        forward.send(.selection(3))
        forward.settle()
        let list = try #require(forward.frame?.list)
        #expect(close(list.content.minY, top.minY - 114) && close(list.row(3), list.highlight))
    }

    @Test
    func selectionClampsAtTheLastRow() {
        var forward = Driver.holding(.forward, forward: 3)
        forward.send(.selection(9))
        forward.settle()
        #expect(forward.frame?.list?.selection == 3)
    }

    @Test(arguments: [(0.0, Double(0)), (0.5, CGFloat(38 * (1 - 1 / 1.05))), (-0.5, CGFloat(-38 * (1 - 1 / 1.05)))])
    func theLeanFollowsASignedRubberBand(remainder: Double, expected: CGFloat) {
        #expect(close(Geometry.lean(remainder: remainder), expected))
    }

    @Test
    func theLeanOnlyHintsAtTheNextRow() {
        #expect(Geometry.lean(remainder: 0.99) < 3.5 && Geometry.lean(remainder: 20) < 38)
    }

    @Test
    func theLeanRidesTheSelectionSpring() throws {
        var driver = Driver.holding(.back, back: 3)
        let before = try #require(driver.frame?.list)
        driver.send(.rowRemainder(0.5))
        driver.advance(0.1)
        let zeta = 0.9, omega = 2 * Double.pi / 0.27, damped = omega * (1 - zeta * zeta).squareRoot()
        let lean = Double(Geometry.lean(remainder: 0.5))
        let shift = lean * (1 - exp(-zeta * omega * 0.1) * (cos(damped * 0.1) + zeta * omega / damped * sin(damped * 0.1)))
        let current = try #require(driver.frame?.list)
        #expect(close(current.content.minY, before.content.minY + CGFloat(shift), 1e-6))
    }

    @Test
    func theListLeansTowardThePreviousRowUnderAFixedHighlight() throws {
        var driver = Driver.holding(.back, back: 3)
        let before = try #require(driver.frame?.list)
        driver.send(.rowRemainder(0.5))
        let lean = Double(Geometry.lean(remainder: 0.5))
        driver.settle()
        let leaning = try #require(driver.frame?.list)
        #expect(close(leaning.content.minY, before.content.minY + CGFloat(lean)) && close(leaning.highlight, before.highlight)
              && leaning.highlight.midY < leaning.row(0).midY && leaning.highlight.midY > leaning.row(1).midY)
    }

    @Test
    func aNegativeRemainderLeansTheOtherWay() throws {
        var driver = Driver.holding(.back, back: 3)
        let before = try #require(driver.frame?.list)
        let lean = Double(Geometry.lean(remainder: 0.5))
        driver.send(.rowRemainder(-0.5))
        driver.settle()
        let current = try #require(driver.frame?.list)
        #expect(close(current.content.minY, before.content.minY - CGFloat(lean)))
    }

    @Test
    func clearingTheRemainderSettlesSquarelyOnTheNextRow() throws {
        var driver = Driver.holding(.back, back: 3)
        let before = try #require(driver.frame?.list)
        driver.send(.rowRemainder(0.5))
        driver.send(.selection(1))
        driver.send(.rowRemainder(0))
        driver.settle()
        let current = try #require(driver.frame?.list)
        #expect(close(current.content.minY, before.content.minY + 38))
        #expect(close(current.row(1), current.highlight))
    }

    @Test
    func theForwardCardLeansTowardNewerEntries() throws {
        let lean = Double(Geometry.lean(remainder: 0.5))
        var forward = Driver.holding(.forward, forward: 3)
        let top = try #require(forward.frame?.list).content
        forward.send(.rowRemainder(0.5))
        forward.settle()
        let current = try #require(forward.frame?.list)
        #expect(close(current.content.minY, top.minY - CGFloat(lean)))
    }

    @Test
    func aClosedListIgnoresRemainder() {
        var closed = Driver.armed()
        closed.send(.rowRemainder(0.5))
        #expect(closed.model.remainder == 0)
    }

    @Test
    func disarmingSilentlyClosesTheList() {
        var driver = Driver.holding(.back, back: 3)
        driver.send(.selection(2))
        driver.settle()
        driver.send(.rowRemainder(0.5))
        driver.progress(0.9)
        driver.send(.armed(false))
        #expect(driver.haptics == [.levelChange, .generic] && !driver.model.listOpen && !driver.model.armed)
    }

    @Test
    func closingTheListClearsItsLean() {
        var driver = Driver.holding(.back, back: 3)
        driver.send(.selection(2))
        driver.settle()
        driver.send(.rowRemainder(0.5))
        driver.progress(0.9)
        driver.send(.armed(false))
        #expect(driver.model.remainder == 0)
    }

    @Test
    func closingTheListStartsAtTheOpenCard() throws {
        var driver = Driver.holding(.back, back: 3)
        driver.send(.selection(2))
        driver.settle()
        let open = try #require(driver.frame?.list)
        driver.send(.rowRemainder(0.5))
        driver.progress(0.9)
        driver.send(.armed(false))
        let start = try #require(driver.frame)
        #expect(close(start.capsule, open.card) && start.list?.opacity == 1 && start.chevronOpacity == 0)
    }

    @Test
    func theClosingListBlursAndShrinks() throws {
        var driver = Driver.holding(.back, back: 3)
        driver.send(.selection(2))
        driver.settle()
        driver.send(.rowRemainder(0.5))
        driver.progress(0.9)
        driver.send(.armed(false))
        driver.advance(0.11)
        let mid = try #require(driver.frame), half = HistorySwipeCurve.easeOut(0.5)
        let swapIn = 1 - half
        #expect(mid.list.map { close($0.opacity, swapIn) && close($0.scale, 0.9 + 0.1 * swapIn) && close($0.blur, 10 * half) } == true)
    }

    @Test
    func theChevronSwapsBackInWhileTheListCloses() throws {
        var driver = Driver.holding(.back, back: 3)
        driver.send(.selection(2))
        driver.settle()
        driver.send(.rowRemainder(0.5))
        driver.progress(0.9)
        driver.send(.armed(false))
        driver.advance(0.11)
        let mid = try #require(driver.frame), half = HistorySwipeCurve.easeOut(0.5)
        let swapIn = 1 - half, armedAmount = 1 - HistorySwipeCurve.easeOut(0.11 / 0.18)
        #expect(close(mid.chevronOpacity, (0.5 + 0.5 * armedAmount) * half) && close(mid.chevronScale, 1 - 0.1 * swapIn)
              && close(mid.chevronBlur, 10 * swapIn))
    }

    @Test
    func theClosingCardFoldsTowardTheCircleAndKeepsItsRows() throws {
        var driver = Driver.holding(.back, back: 3)
        driver.send(.selection(2))
        driver.settle()
        driver.send(.rowRemainder(0.5))
        driver.progress(0.9)
        driver.send(.armed(false))
        driver.advance(0.11)
        let zeta = 0.77, omega = 2 * Double.pi / 0.22, damped = omega * (1 - zeta * zeta).squareRoot(), t = 0.11
        let morph = exp(-zeta * omega * t) * (cos(damped * t) + zeta * omega / damped * sin(damped * t))
        let mid = try #require(driver.frame)
        #expect(close(mid.capsule.width, mid.circle.width + (200 - mid.circle.width) * CGFloat(morph), 1e-6)
              && mid.list.map { close($0.row(2), $0.highlight) } == true)
    }

    @Test
    func theFoldEndsAtTheRestingCircle() throws {
        var driver = Driver.holding(.back, back: 3)
        driver.send(.selection(2))
        driver.settle()
        driver.send(.rowRemainder(0.5))
        driver.progress(0.9)
        driver.send(.armed(false))
        driver.settle()
        let rest = try #require(driver.frame)
        #expect(rest.list == nil && close(rest.capsule, rest.circle) && rest.cornerRadius == 36 && rest.circle.width == 72
              && rest.chevronOpacity == 0.5 && rest.chevronScale == 1 && rest.chevronBlur == 0 && rest.wash == 0
              && !driver.model.isAnimating)
    }

    @Test
    func rearmingAndReopeningPlayTheirHapticsAgain() {
        var driver = Driver.holding(.back, back: 3)
        driver.send(.selection(2))
        driver.settle()
        driver.send(.rowRemainder(0.5))
        driver.progress(0.9)
        driver.send(.armed(false))
        driver.settle()
        driver.progress(1.1)
        driver.send(.armed(true))
        driver.settle()
        driver.send(.hold)
        driver.send(.selection(0))
        #expect(driver.haptics == [.levelChange, .generic, .levelChange, .generic])
    }

    @Test
    func theListReopensFromTheCircle() throws {
        var driver = Driver.holding(.back, back: 3)
        driver.send(.selection(2))
        driver.settle()
        driver.send(.rowRemainder(0.5))
        driver.progress(0.9)
        driver.send(.armed(false))
        driver.settle()
        driver.progress(1.1)
        driver.send(.armed(true))
        driver.settle()
        let circle = try #require(driver.frame).circle
        driver.send(.hold)
        driver.send(.selection(0))
        #expect(driver.frame.map { close($0.capsule, circle) && $0.list?.opacity == 0 && $0.list?.scale == 0.9 && $0.list?.blur == 10 } == true)
    }

    @Test
    func theReopenedListResetsToTheCurrentPage() throws {
        var driver = Driver.holding(.back, back: 3)
        driver.send(.selection(2))
        driver.settle()
        driver.send(.rowRemainder(0.5))
        driver.progress(0.9)
        driver.send(.armed(false))
        driver.settle()
        driver.progress(1.1)
        driver.send(.armed(true))
        driver.settle()
        driver.send(.hold)
        driver.send(.selection(0))
        driver.settle()
        let frame = try #require(driver.frame)
        let list = try #require(frame.list)
        #expect(close(frame.capsule, list.card) && close(list.row(0), list.highlight))
    }

    @Test
    func reopeningMidCollapsePreservesTheCurrentFrame() throws {
        var driver = Driver.holding(.back, back: 3)
        driver.send(.selection(2))
        driver.settle()
        driver.progress(0.9)
        driver.send(.armed(false))
        driver.advance(0.1)
        driver.progress(1.1)
        driver.send(.armed(true))
        let before = try #require(driver.frame)
        driver.send(.hold)
        driver.send(.selection(0))
        let after = try #require(driver.frame)
        let previousList = try #require(before.list)
        let reopenedList = try #require(after.list)
        #expect(close(after.capsule, before.capsule))
        #expect(close(reopenedList.content, previousList.content))
        #expect(close(reopenedList.opacity, previousList.opacity))
        #expect(close(after.chevronOpacity, before.chevronOpacity))
    }

    @Test
    func reopeningMidCollapseMorphsSmoothly() throws {
        var driver = Driver.holding(.back, back: 3)
        driver.send(.selection(2))
        driver.settle()
        driver.progress(0.9)
        driver.send(.armed(false))
        driver.advance(0.1)
        driver.progress(1.1)
        driver.send(.armed(true))
        driver.send(.hold)
        driver.send(.selection(0))
        var widths: [CGFloat] = []
        for _ in 0..<60 {
            driver.advance(1.0 / 120)
            widths.append(try #require(driver.frame).capsule.width)
        }
        let jumps = zip(widths, widths.dropFirst()).map { abs($1 - $0) }
        let largestJump = try #require(jumps.max())
        #expect(largestJump < 20)
    }

    @Test
    func reopeningMidCollapseEndsOnTheCurrentPage() throws {
        var driver = Driver.holding(.back, back: 3)
        driver.send(.selection(2))
        driver.settle()
        driver.progress(0.9)
        driver.send(.armed(false))
        driver.advance(0.1)
        driver.progress(1.1)
        driver.send(.armed(true))
        driver.send(.hold)
        driver.send(.selection(0))
        driver.settle()
        let frame = try #require(driver.frame)
        let list = try #require(frame.list)
        #expect(close(frame.capsule, list.card) && close(list.row(0), list.highlight) && list.opacity == 1)
    }

    @Test(arguments: 0...50)
    func eachBackRowCanScrollIntoView(row: Int) throws {
        var driver = Driver.holding(.back, back: 50)
        driver.send(.selection(row))
        driver.settle()
        let list = try #require(driver.frame?.list)
        #expect(close(list.row(row), list.highlight))
        #expect(list.card.contains(list.highlight))
    }

    @Test(arguments: 0...50)
    func theLongCardStaysInsideThePaneWhileRowsScroll(row: Int) throws {
        var driver = Driver.holding(.back, back: 50)
        driver.send(.selection(row))
        driver.settle()
        let card = try #require(driver.frame?.list).card
        #expect(card.minY >= 14 - 1e-9)
        #expect(card.maxY <= Self.pane.height - 14 + 1e-9)
    }

    @Test
    func theLongCardClipsTheFullList() throws {
        let driver = Driver.holding(.back, back: 50)
        let list = try #require(driver.frame?.list)
        #expect(close(list.content.height, 51 * 38 + 16) && list.card.height < list.content.height)
    }

    @Test
    func theCapsuleFollowsTheVisibleCard() throws {
        let driver = Driver.holding(.back, back: 50)
        let frame = try #require(driver.frame)
        let list = try #require(frame.list)
        #expect(close(frame.capsule, list.card))
    }

    @Test
    func aShortListShowsTheWholeCard() throws {
        let short = try #require(Driver.holding(.back, back: 2).frame?.list)
        #expect(close(short.card, short.content))
    }

    @Test
    func aShortPaneKeepsTheScrollingCardInside() throws {
        var squat = Driver.holding(.forward, forward: 30)
        squat.size = CGSize(width: 600, height: 300)
        squat.send(.selection(15))
        squat.settle()
        let list = try #require(squat.frame?.list)
        #expect(close(list.row(15), list.highlight) && list.card.minY >= 14 && list.card.maxY <= 286)
    }

    @Test
    func reduceMotionHidesTheCircleBelowTheThreshold() {
        var driver = Driver(reduced: true)
        driver.send(.begin(.back))
        driver.progress(0.1)
        #expect(driver.frame?.opacity == 0)
    }

    @Test
    func reduceMotionFadesInAStaticCircle() {
        var driver = Driver(reduced: true)
        driver.send(.begin(.back))
        driver.progress(0.1)
        driver.progress(0.25)
        driver.advance(0.06)
        #expect(driver.frame.map { close($0.opacity, 0.5) && close($0.circle.minX, 14) && $0.circle.width == 72 } == true)
    }

    @Test
    func reduceMotionKeepsTheCircleStillDuringTravel() throws {
        var driver = Driver(reduced: true)
        driver.send(.begin(.back))
        driver.progress(0.1)
        driver.progress(0.25)
        driver.advance(0.1201)
        driver.progress(0.8)
        let still = try #require(driver.frame).circle
        driver.progress(band(2))
        #expect(driver.frame.map { $0.opacity == 1 && close($0.circle, still) } == true)
    }

    @Test
    func reduceMotionKeepsTheArmingHaptic() {
        var driver = Driver(reduced: true)
        driver.send(.begin(.back))
        driver.progress(0.25)
        driver.send(.armed(true))
        #expect(driver.haptics == [.levelChange])
    }

    @Test
    func reduceMotionArmingCrossfadesLinearly() {
        var driver = Driver(reduced: true)
        driver.send(.begin(.back))
        driver.progress(0.25)
        driver.send(.armed(true))
        driver.advance(0.06)
        #expect(driver.frame.map { close($0.wash, 0.5) } == true)
    }

    @Test
    func reduceMotionArmingChangesOnlyOpacity() {
        var driver = Driver(reduced: true)
        driver.send(.begin(.back))
        driver.progress(0.25)
        driver.send(.armed(true))
        driver.settle()
        #expect(driver.frame.map { $0.circle.width == 72 && $0.chevronSize == 28 && $0.wash == 1 && $0.chevronOpacity == 1 } == true)
    }

    @Test
    func reduceMotionReplacesTheCircleWithoutMorphing() throws {
        var driver = Driver(reduced: true)
        driver.send(.begin(.back))
        driver.progress(0.25)
        driver.send(.armed(true))
        driver.settle()
        #expect(driver.frame.map { $0.circle.width == 72 && $0.chevronSize == 28 && $0.wash == 1 && $0.chevronOpacity == 1 } == true)
        driver.send(.hold)
        driver.send(.selection(0))
        let frame = try #require(driver.frame)
        let list = try #require(frame.list)
        #expect(close(frame.capsule, list.card) && frame.opacity == 0 && list.scale == 1
                && list.blur == 0 && frame.chevronBlur == 0 && frame.chevronScale == 1)
    }

    @Test
    func reduceMotionCrossfadesInTheList() throws {
        var driver = Driver(reduced: true)
        driver.send(.begin(.back))
        driver.progress(0.25)
        driver.send(.armed(true))
        driver.settle()
        driver.send(.hold)
        driver.send(.selection(0))
        driver.advance(0.075)
        let frame = try #require(driver.frame)
        let list = try #require(frame.list)
        #expect(close(frame.opacity, 0.5) && close(list.opacity, 0.5))
    }

    @Test(arguments: [0.0, 0.6])
    func reduceMotionSelectionDoesNotSlideOrLean(remainder: Double) throws {
        var driver = Driver.holding(.back, reduced: true)
        let originalY = try #require(driver.frame?.list).content.minY
        driver.send(.selection(1))
        driver.send(.rowRemainder(remainder))
        let immediate = try #require(driver.frame?.list)
        #expect(close(immediate.content.minY, originalY + 38))
        driver.settle()
        let settled = try #require(driver.frame?.list)
        #expect(close(settled.content.minY, originalY + 38))
    }

    @Test
    func reduceMotionEndingOnlyFades() {
        var driver = Driver.holding(.back, reduced: true)
        driver.send(.selection(1))
        driver.send(.commit(.entry(.back, distance: 1)))
        driver.advance(0.075)
        #expect(driver.frame.map { close($0.opacity, 0.5) && $0.scale == 1 && $0.blur == 0 } == true)
    }

    @Test
    func reduceMotionEndingRemovesTheIndicator() {
        var driver = Driver.holding(.back, reduced: true)
        driver.send(.commit(.entry(.back, distance: 1)))
        driver.advance(0.155)
        #expect(driver.frame == nil)
    }

    @Test
    func reduceMotionFadesOutWhenBackingOff() {
        var retreat = Driver(reduced: true)
        retreat.send(.begin(.back))
        retreat.progress(0.5)
        retreat.advance(0.2)
        retreat.progress(0.1)
        retreat.advance(0.1201)
        #expect(retreat.frame?.opacity == 0)
    }

    @Test
    func reduceMotionReplacesTheClosingCardWithTheCircle() {
        var driver = Driver.holding(.back, back: 3, reduced: true)
        driver.send(.selection(2))
        driver.settle()
        driver.progress(0.9)
        driver.send(.armed(false))
        #expect(driver.frame.map { $0.list == nil && close($0.capsule, $0.circle) && $0.opacity == 0 && $0.scale == 1 && $0.blur == 0 } == true)
    }

    @Test
    func reduceMotionCrossfadesTheCircleBackIn() {
        var driver = Driver.holding(.back, back: 3, reduced: true)
        driver.send(.selection(2))
        driver.settle()
        driver.progress(0.9)
        driver.send(.armed(false))
        driver.advance(0.075)
        #expect(driver.frame.map { close($0.opacity, 0.5) && $0.chevronBlur == 0 && $0.chevronScale == 1 } == true)
    }

    @Test
    func reduceMotionClosingSettlesOnAStaticCircle() {
        var driver = Driver.holding(.back, back: 3, reduced: true)
        driver.send(.selection(2))
        driver.settle()
        driver.progress(0.9)
        driver.send(.armed(false))
        driver.settle()
        #expect(driver.frame.map { $0.opacity == 1 && $0.list == nil && $0.circle.width == 72 } == true && !driver.model.isAnimating)
    }

    @Test
    func reduceMotionReopensTheCardOnTheCurrentPage() throws {
        var driver = Driver.holding(.back, back: 3, reduced: true)
        driver.send(.selection(2))
        driver.settle()
        driver.progress(0.9)
        driver.send(.armed(false))
        driver.settle()
        driver.send(.armed(true))
        driver.send(.hold)
        driver.send(.selection(0))
        let frame = try #require(driver.frame)
        let list = try #require(frame.list)
        #expect(close(frame.capsule, list.card) && frame.opacity == 0 && close(list.row(0), list.highlight))
    }

    @Test
    func reduceMotionCrossfadesTheReopenedCard() {
        var driver = Driver.holding(.back, back: 3, reduced: true)
        driver.send(.selection(2))
        driver.settle()
        driver.progress(0.9)
        driver.send(.armed(false))
        driver.settle()
        driver.send(.armed(true))
        driver.send(.hold)
        driver.send(.selection(0))
        driver.advance(0.075)
        #expect(driver.frame.map { close($0.opacity, 0.5) } == true)
    }

    @Test
    func reduceMotionLeavesAnOpenListVisibleWithShortTravel() {
        var open = Driver.holding(.back, back: 3, reduced: true)
        open.send(.selection(2))
        open.progress(0.12)
        open.settle()
        #expect(open.frame.map { $0.opacity == 1 && $0.list != nil } == true)
    }

    @Test
    func reduceMotionClosingAtShortTravelDoesNotFlash() throws {
        var open = Driver.holding(.back, back: 3, reduced: true)
        open.send(.selection(2))
        open.progress(0.12)
        open.settle()
        open.send(.armed(false))
        var brightest = try #require(open.frame).opacity
        for _ in 0..<40 {
            open.advance(1.0 / 120)
            brightest = max(brightest, open.frame?.opacity ?? 0)
        }
        #expect(brightest == 0 && open.frame?.list == nil)
    }

    @Test
    func aNarrowBackPaneNarrowsTheCard() throws {
        var driver = Driver.holding(.back, back: 3)
        driver.size = CGSize(width: 220, height: 500)
        let list = try #require(driver.frame?.list)
        #expect(close(list.card.minX, 14) && close(list.card.width, 192))
    }

    @Test
    func aNarrowForwardPaneContainsTheCard() throws {
        var right = Driver.holding(.forward, forward: 3)
        right.size = CGSize(width: 260, height: 500)
        let list = try #require(right.frame?.list)
        #expect(list.card.minX >= 14 && list.card.maxX <= 246)
    }

    @Test
    func aSplitUsesItsOwnPaneBounds() {
        var split = Driver.armed(.forward)
        split.size = CGSize(width: 412, height: 664)
        #expect(split.frame.map { close($0.circle.maxX, 398) } == true)
    }

    @Test(arguments: [(true, Double(1), Double(0.15), Double(0.25), Double(0), Double(1)),
                      (false, Double(0), Double(0.125), Double(0.2), Double(0.4), Double(0))])
    func overlayColorsFollowTheAppearance(dark: Bool, ringWhite: Double, ring: Double, shadow: Double, wash: Double, highlight: Double) {
        let look = HistorySwipeOverlayLook(dark: dark)
        #expect(look.ringWhite == ringWhite)
        #expect(look.ringAlpha == ring)
        #expect(look.shadowAlpha == shadow)
        #expect(look.washAlpha == wash)
        #expect(look.highlightWhite == highlight)
        #expect(look.highlightAlpha == 0.1)
    }

    @Test
    func recognizerCommitTravelPlacesTheCircleAtItsInset() {
        var hand = Fingers(back: 50)
        hand.open()
        hand.touch(.moved, 0.38)
        #expect(hand.overlay.frame.map { abs($0.circle.minX - 14) < 0.001 } == true)
    }

    @Test
    func recognizerArmingProducesOneHaptic() {
        var hand = Fingers(back: 50)
        hand.open()
        hand.touch(.moved, 0.38)
        #expect(hand.overlay.haptics == [.levelChange])
    }

    @Test
    func recognizerHoldOpensTheListWithAHaptic() {
        var hand = Fingers(back: 50)
        hand.open()
        hand.touch(.moved, 0.38)
        hand.clock()
        #expect(hand.overlay.haptics == [.levelChange, .generic] && hand.overlay.model.listOpen)
    }

    @Test
    func recognizerHoldHighlightsTheCurrentPage() throws {
        var hand = Fingers(back: 50)
        hand.open()
        hand.touch(.moved, 0.38)
        hand.clock()
        let list = try #require(hand.overlay.frame?.list)
        #expect(hand.overlay.model.selection == 0 && close(list.row(0), list.highlight))
    }

    @Test
    func recognizerRowTravelProducesOneHapticPerRow() {
        var hand = Fingers(back: 50)
        hand.open()
        hand.touch(.moved, 0.38)
        hand.clock()
        hand.touch(.moved, 0.38, 0.70)
        hand.touch(.moved, 0.38, 0.88)
        #expect(hand.overlay.model.selection == 4 && hand.overlay.haptics.filter { $0 == .alignment }.count == 4)
    }

    @Test
    func recognizerRemainderReachesTheOverlay() {
        var hand = Fingers(back: 50)
        hand.open()
        hand.touch(.moved, 0.38)
        hand.clock()
        hand.touch(.moved, 0.38, 0.70)
        hand.touch(.moved, 0.38, 0.88)
        #expect(abs(hand.overlay.model.remainder - 0.75) < 1e-9)
    }

    @Test
    func edgeScrollingVisitsEveryRowAndHighlightsTheOldest() throws {
        var hand = Fingers(back: 50)
        hand.open()
        hand.touch(.moved, 0.38)
        hand.clock()
        hand.touch(.moved, 0.38, 0.70)
        hand.touch(.moved, 0.38, 0.88)
        hand.scrollToHistoryEdge()
        hand.overlay.settle()
        #expect(hand.overlay.model.selection == 50 && hand.overlay.haptics.filter { $0 == .alignment }.count == 50)
        let list = try #require(hand.overlay.frame?.list)
        #expect(close(list.row(50), list.highlight))
    }

    @Test
    func releasingAtTheEdgeCommitsTheOldestEntry() {
        var hand = Fingers(back: 50)
        hand.open()
        hand.touch(.moved, 0.38)
        hand.clock()
        hand.touch(.moved, 0.38, 0.70)
        hand.touch(.moved, 0.38, 0.88)
        hand.scrollToHistoryEdge()
        hand.overlay.settle()
        hand.touch(.ended, 0.38)
        #expect(hand.recognizer.state == .completed)
        #expect(hand.commits == [.entry(.back, distance: 50)])
    }

    @Test
    func theListCollapsesAfterTheOldestEntryCommits() {
        var hand = Fingers(back: 50)
        hand.open()
        hand.touch(.moved, 0.38)
        hand.clock()
        hand.touch(.moved, 0.38, 0.70)
        hand.touch(.moved, 0.38, 0.88)
        hand.scrollToHistoryEdge()
        hand.overlay.settle()
        hand.touch(.ended, 0.38)
        hand.overlay.advance(Timing.collapse + 0.0001)
        #expect(hand.overlay.frame == nil)
    }

    @Test
    func theReducedMotionListHighlightsTheRecognizerSelection() throws {
        var hand = Fingers(back: 3, reduced: true)
        hand.open()
        hand.touch(.moved, 0.38)
        hand.clock()
        hand.touch(.moved, 0.38, 0.59)
        hand.touch(.moved, 0.38, 0.67)
        hand.overlay.settle()
        let frame = try #require(hand.overlay.frame)
        let list = try #require(frame.list)
        #expect(hand.recognizer.selection == 2 && frame.opacity == 1 && close(list.row(2), list.highlight))
    }

    @Test
    func backingOffClosesBothTheRecognizerListAndOverlay() {
        var hand = Fingers(back: 3, reduced: true)
        hand.open()
        hand.touch(.moved, 0.38)
        hand.clock()
        hand.touch(.moved, 0.38, 0.59)
        hand.touch(.moved, 0.38, 0.67)
        hand.overlay.settle()
        hand.touch(.moved, 0.3096, 0.67)
        #expect(hand.recognizer.state == .tracking && !hand.overlay.model.listOpen && hand.overlay.frame?.list == nil)
    }

    @Test
    func theReducedMotionIndicatorHidesBelowTheTravelThreshold() {
        var hand = Fingers(back: 3, reduced: true)
        hand.open()
        hand.touch(.moved, 0.38)
        hand.clock()
        hand.touch(.moved, 0.38, 0.59)
        hand.touch(.moved, 0.38, 0.67)
        hand.overlay.settle()
        hand.touch(.moved, 0.3096, 0.67)
        hand.overlay.settle()
        #expect(hand.overlay.frame?.opacity == 0)
    }

    @Test
    func releasingAfterBackingOffNavigatesNowhere() {
        var hand = Fingers(back: 3, reduced: true)
        hand.open()
        hand.touch(.moved, 0.38)
        hand.clock()
        hand.touch(.moved, 0.38, 0.59)
        hand.touch(.moved, 0.38, 0.67)
        hand.overlay.settle()
        hand.touch(.moved, 0.3096, 0.67)
        hand.touch(.ended, 0.3096)
        #expect(hand.commits.isEmpty && hand.outputs.last == .cancel)
    }

    @Test
    func rearmingUnderReduceMotionReopensOnTheCurrentPage() throws {
        var back = Fingers(back: 3, reduced: true)
        back.open()
        back.touch(.moved, 0.38)
        back.clock()
        back.touch(.moved, 0.38, 0.59)
        back.touch(.moved, 0.36, 0.59)
        back.touch(.moved, 0.385, 0.59)
        back.clock()
        back.overlay.settle()
        let frame = try #require(back.overlay.frame)
        let list = try #require(frame.list)
        #expect(back.overlay.model.listOpen && frame.opacity == 1 && close(list.row(0), list.highlight))
    }

    @Test
    func releasingImmediatelyAfterReopeningCancels() {
        var back = Fingers(back: 3, reduced: true)
        back.open()
        back.touch(.moved, 0.38)
        back.clock()
        back.touch(.moved, 0.38, 0.59)
        back.touch(.moved, 0.36, 0.59)
        back.touch(.moved, 0.385, 0.59)
        back.clock()
        back.overlay.settle()
        back.touch(.ended, 0.385)
        #expect(back.commits.isEmpty && back.outputs.last == .cancel)
    }

    @Test
    func anIdleOverlayHasNoFrameOrAnimation() {
        let idle = Driver()
        #expect(idle.frame == nil && !idle.model.isAnimating)
    }

    @Test
    func outputsBeforeBeginDoNotDrawOrPlayHaptics() {
        var idle = Driver()
        idle.send(.progress(HistorySwipeProgress(fraction: 1, stretch: 1)))
        idle.send(.armed(true))
        idle.send(.hold)
        #expect(idle.frame == nil && idle.haptics.isEmpty)
    }

    @Test
    func aNewSwipeStartsFreshDuringCollapse() {
        var again = Driver.armed()
        again.send(.cancel)
        again.advance(0.05)
        again.send(.begin(.forward))
        #expect(again.frame.map { $0.opacity == 1 && $0.scale == 1 && $0.direction == .forward && $0.wash == 0 } == true)
    }

    @Test
    func resetImmediatelyDropsTheIndicator() {
        var reset = Driver.holding()
        reset.model.reset()
        #expect(reset.frame == nil && !reset.model.isAnimating)
    }

    private typealias Metrics = HistorySwipeOverlayMetrics
    private typealias Timing = HistorySwipeOverlayTiming
    private typealias Geometry = HistorySwipeOverlayGeometry
    private typealias Haptic = HistorySwipeOverlayModel.Haptic

    private static let pane = CGSize(width: 832, height: 664)

    private func band(_ progress: Double, _ resistance: Double = 0.15) -> Double {
        let resisted = (progress - 1) * resistance
        return 1 + resisted / (resisted + 1)
    }

    private struct Driver {
        var model = HistorySwipeOverlayModel()
        var time = 10.0
        var haptics: [Haptic] = []
        var size = HistorySwipeOverlayTests.pane

        init(back: Int = 3, forward: Int = 2, reduced: Bool = false) {
            model.backRows = back
            model.forwardRows = forward
            model.prefersReducedMotion = reduced
        }

        mutating func send(_ output: HistorySwipeOutput, after delay: Double = 0) {
            time += delay
            if let haptic = model.receive(output, at: time) { haptics.append(haptic) }
        }

        mutating func progress(_ value: Double, after delay: Double = 0) {
            send(.progress(HistorySwipeProgress(fraction: min(max(value, 0), 1), stretch: value)), after: delay)
        }

        mutating func advance(_ delay: Double) {
            time += delay
            model.advance(to: time)
        }

        mutating func settle() {
            advance(1.5)
        }

        var frame: HistorySwipeOverlayFrame? { model.frame(in: size) }

        static func armed(_ direction: HistorySwipeDirection = .back, back: Int = 3, forward: Int = 2,
                          reduced: Bool = false, stretch: Double = 1) -> Driver {
            var driver = Driver(back: back, forward: forward, reduced: reduced)
            driver.send(.begin(direction))
            driver.progress(stretch)
            driver.send(.armed(true))
            driver.settle()
            return driver
        }

        static func holding(_ direction: HistorySwipeDirection = .back, back: Int = 3, forward: Int = 2,
                            reduced: Bool = false) -> Driver {
            var driver = armed(direction, back: back, forward: forward, reduced: reduced)
            driver.send(.hold)
            driver.send(.selection(0))
            driver.settle()
            return driver
        }
    }

    private struct Environment: HistorySwipeEnvironment {
        var back = 3
        var forward = 0
        var swipesBetweenPages = true
        var allowsHistorySwipe = true
        func historyEntries(toward direction: HistorySwipeDirection) -> Int { direction == .back ? back : forward }
    }

    private struct Fingers {
        var recognizer = HistorySwipeRecognizer()
        var overlay = Driver()
        var environment = Environment()
        var time = 10.0
        var x = 0.30
        var y = 0.5
        var lastStep = HistorySwipeStep()
        var outputs: [HistorySwipeOutput] = []

        init(back: Int, reduced: Bool = false) {
            environment.back = back
            overlay = Driver(back: back, forward: 0, reduced: reduced)
        }

        mutating func feed(_ input: HistorySwipeInput) {
            lastStep = recognizer.receive(input, in: environment)
            outputs += lastStep.outputs
            for output in lastStep.outputs { overlay.time = max(overlay.time, time); overlay.send(output) }
        }

        var commits: [HistorySwipeCommit] {
            outputs.compactMap { if case let .commit(commit) = $0 { commit } else { nil } }
        }

        var points: [HistorySwipePoint] { [HistorySwipePoint(x: x - 0.06, y: y), HistorySwipePoint(x: x + 0.06, y: y)] }

        mutating func touch(_ phase: HistorySwipeTouchPhase, _ x: Double, _ y: Double? = nil) {
            time += 0.008
            self.x = x
            if let y { self.y = y }
            feed(.touches(phase, points, time: time))
        }

        mutating func scroll(_ phase: HistorySwipeEventPhase, dx: Double) {
            feed(.scroll(HistorySwipeScroll(phase: phase, deltaX: dx, directionInverted: true)))
        }

        mutating func open() {
            touch(.began, 0.30)
            scroll(.mayBegin, dx: 0)
            touch(.moved, 0.302)
            scroll(.began, dx: 2)
            feed(.pageScroll(.began(synthetic: false, momentum: false)))
            feed(.overscroll(propagatesX: true))
            feed(.pageScroll(.updated(consumed: false)))
            touch(.moved, 0.305)
            scroll(.changed, dx: 3)
        }

        mutating func scrollToHistoryEdge() {
            for _ in 0..<environment.back {
                guard lastStep.clockDeadline != nil else { break }
                clock()
            }
        }

        mutating func clock() {
            guard let deadline = lastStep.clockDeadline else { return }
            time = deadline
            feed(.clock(deadline))
        }
    }
}
