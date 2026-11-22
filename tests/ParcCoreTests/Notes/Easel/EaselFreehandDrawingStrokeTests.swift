import Foundation
import Testing
@testable import ParcCore

struct EaselFreehandDrawingStrokeTests {
    @Test
    func theFirstSampleAlwaysLands() {
        var points: [EaselPoint] = []
        #expect(EaselDrawing.append(EaselFreehandDrawingTestsSupport.p(10, 10), to: &points, scale: 1), "The first sample always lands")
    }

    @Test
    func sampleSpacingFollowsCanvasZoom() {
        var points: [EaselPoint] = []
        #expect(EaselDrawing.append(EaselFreehandDrawingTestsSupport.p(10, 10), to: &points, scale: 1), "The first sample always lands")
        #expect(!EaselDrawing.append(EaselFreehandDrawingTestsSupport.p(10.4, 10), to: &points, scale: 1), "Jitter under a point is skipped at 100%")
        #expect(EaselDrawing.append(EaselFreehandDrawingTestsSupport.p(10.4, 10), to: &points, scale: 4), "Zoomed in, a quarter point is enough travel")
    }

    @Test
    func nonfiniteSamplesNeverEnterAStroke() {
        var points: [EaselPoint] = []
        #expect(EaselDrawing.append(EaselFreehandDrawingTestsSupport.p(10, 10), to: &points, scale: 1), "The first sample always lands")
        #expect(!EaselDrawing.append(EaselFreehandDrawingTestsSupport.p(.nan, 3), to: &points, scale: 1), "Broken samples never enter a stroke")
    }

    @Test
    func strokesStopAtTheirPointBudget() {
        var points: [EaselPoint] = []
        points = Array(repeating: EaselFreehandDrawingTestsSupport.p(0, 0), count: EaselDrawing.maximumPoints)
        #expect(!EaselDrawing.append(EaselFreehandDrawingTestsSupport.p(50, 50), to: &points, scale: 1), "Strokes stop growing at the point budget")
    }

    @Test
    func smoothingSoftensSpikesAndKeepsBothEnds() {
        let spiky = [EaselFreehandDrawingTestsSupport.p(0, 0), EaselFreehandDrawingTestsSupport.p(10, 0), EaselFreehandDrawingTestsSupport.p(20, 10), EaselFreehandDrawingTestsSupport.p(30, 0), EaselFreehandDrawingTestsSupport.p(40, 0)]
        let smooth = EaselDrawing.smoothed(spiky)
        #expect(smooth.first == spiky.first && smooth.last == spiky.last, "Smoothing keeps both ends where the pen was")
        #expect(smooth[2].y < 10 && smooth[2].y > 0, "Smoothing softens a spike without erasing it")
    }

    @Test
    func simplifyingAStraightRunKeepsOnlyItsEnds() {
        let line = (0...100).map { EaselFreehandDrawingTestsSupport.p(Double($0), 0.0) }
        #expect(EaselDrawing.simplified(line, tolerance: 0.35) == [EaselFreehandDrawingTestsSupport.p(0, 0), EaselFreehandDrawingTestsSupport.p(100, 0)], "A straight run collapses to its two ends")
    }

    @Test
    func simplifyingACornerPreservesTheBend() {
        let corner = (0...50).map { EaselFreehandDrawingTestsSupport.p(Double($0), 0.0) } + (1...50).map { EaselFreehandDrawingTestsSupport.p(50.0, Double($0)) }
        let kept = EaselDrawing.simplified(corner, tolerance: 0.35)
        #expect(kept == [EaselFreehandDrawingTestsSupport.p(0, 0), EaselFreehandDrawingTestsSupport.p(50, 0), EaselFreehandDrawingTestsSupport.p(50, 50)], "A real corner survives simplification")
    }

    @Test
    func simplifyingADenseCurveKeepsItWithinTolerance() {
        let wave = (0...400).map { index -> EaselPoint in
            let x = Double(index) * 0.5
            return EaselFreehandDrawingTestsSupport.p(x, sin(x / 6) * 20)
        }
        let simple = EaselDrawing.simplified(wave, tolerance: 0.35)
        #expect(simple.count < wave.count / 3, "A dense curve keeps far fewer points")
        for point in wave {
            let distance = zip(simple, simple.dropFirst()).map { EaselDrawing.segmentDistance(point, $0, $1) }.min() ?? .infinity
            #expect(distance <= 0.35 + 1e-9, "Simplified curves stay within the tolerance")
        }
    }

    @Test
    func finishingATapMakesATwoPointDot() {
        #expect(EaselDrawing.finished([EaselFreehandDrawingTestsSupport.p(5, 5)], scale: 1) == [EaselFreehandDrawingTestsSupport.p(5, 5), EaselFreehandDrawingTestsSupport.p(5, 5)], "A click becomes a dot with two equal points")
    }

    @Test
    func finishingATwoPointStrokeLeavesItUntouched() {
        #expect(EaselDrawing.finished([EaselFreehandDrawingTestsSupport.p(1, 1), EaselFreehandDrawingTestsSupport.p(9, 9)], scale: 1) == [EaselFreehandDrawingTestsSupport.p(1, 1), EaselFreehandDrawingTestsSupport.p(9, 9)], "Two points pass through untouched")
    }

    @Test
    func aSimplifiedSpiralKeepsItsEndsAndStaysClose() {
        let spiral = (0..<20_000).map { index -> EaselPoint in
            let turn = Double(index) * 0.01
            return EaselFreehandDrawingTestsSupport.p(500 + cos(turn) * (10 + turn * 3), 500 + sin(turn) * (10 + turn * 3))
        }
        let tight = EaselDrawing.simplified(spiral, tolerance: 0.35)
        #expect(tight.first == spiral.first && tight.last == spiral.last && tight.count < spiral.count, "A long spiral simplifies and keeps its ends")
        for point in stride(from: 0, to: spiral.count, by: 97).map({ spiral[$0] }) {
            let distance = zip(tight, tight.dropFirst()).map { EaselDrawing.segmentDistance(point, $0, $1) }.min() ?? .infinity
            #expect(distance <= 0.35 * 1.5 + 1e-9, "A simplified spiral stays close to what was drawn")
        }
    }

    @Test
    func bunchedSamplesCollapseToTwoPoints() {
        let jitter = (0..<1_000).map { EaselFreehandDrawingTestsSupport.p(Double($0) * 0.01, 0) }
        #expect(EaselDrawing.simplified(jitter, tolerance: 0.35).count == 2, "Samples bunched on one spot collapse quickly")
    }

    @Test
    func finishingACurveKeepsItsEnds() {
        let wave = (0...400).map { index -> EaselPoint in
            let x = Double(index) * 0.5
            return EaselFreehandDrawingTestsSupport.p(x, sin(x / 6) * 20)
        }
        let finished = EaselDrawing.finished(wave, scale: 2)
        #expect(finished.first == wave.first && finished.last == wave.last, "Finishing keeps the stroke's ends")
    }

    @Test
    func finishingAnEmptyStrokeReturnsNothing() {
        #expect(EaselDrawing.finished([], scale: 1).isEmpty, "Nothing drawn finishes as nothing")
    }

    @Test
    func aNearlyLevelLineSettlesExactlyLevel() {
        let flat = EaselDrawing.straightEnd(from: EaselFreehandDrawingTestsSupport.p(0, 0), to: EaselFreehandDrawingTestsSupport.p(100, 4), strict: false)
        #expect(EaselFreehandDrawingTestsSupport.near(flat.y, 0) && EaselFreehandDrawingTestsSupport.near(flat.x, hypot(100, 4)), "A nearly level line settles exactly level")
    }

    @Test
    func aNearlyUprightLineSettlesExactlyUpright() {
        let steep = EaselDrawing.straightEnd(from: EaselFreehandDrawingTestsSupport.p(0, 0), to: EaselFreehandDrawingTestsSupport.p(3, -100), strict: false)
        #expect(EaselFreehandDrawingTestsSupport.near(steep.x, 0), "A nearly upright line settles exactly upright")
    }

    @Test
    func aDeliberateAngleStaysWhereItWasDrawn() {
        let free = EaselDrawing.straightEnd(from: EaselFreehandDrawingTestsSupport.p(0, 0), to: EaselFreehandDrawingTestsSupport.p(100, 58), strict: false)
        #expect(free == EaselFreehandDrawingTestsSupport.p(100, 58), "A deliberate angle stays where it was drawn")
    }

    @Test
    func strictStraighteningSnapsToFortyFiveDegrees() {
        let strict = EaselDrawing.straightEnd(from: EaselFreehandDrawingTestsSupport.p(0, 0), to: EaselFreehandDrawingTestsSupport.p(100, 58), strict: true)
        #expect(EaselFreehandDrawingTestsSupport.near(strict.x, strict.y), "Strict lines snap to 45 degree steps")
    }

    @Test
    func aLevelLineStoresRelativePointsInAOnePointTallFrame() {
        let placed = EaselDrawing.geometry([EaselFreehandDrawingTestsSupport.p(10, 20), EaselFreehandDrawingTestsSupport.p(110, 20)])!
        #expect(placed.frame == EaselRect(x: 10, y: 20, width: 100, height: 1), "A level line keeps a one point tall frame")
        #expect(placed.points == [EaselFreehandDrawingTestsSupport.p(0, 0), EaselFreehandDrawingTestsSupport.p(100, 0)], "Points become relative to the frame")
    }

    @Test
    func onlyTwoPointDrawingsCountAsStraightLines() {
        #expect(EaselDrawing.isStraight(EaselFreehandDrawingTestsSupport.stroke([EaselFreehandDrawingTestsSupport.p(0, 0), EaselFreehandDrawingTestsSupport.p(40, 40)])) && !EaselDrawing.isStraight(EaselFreehandDrawingTestsSupport.stroke([EaselFreehandDrawingTestsSupport.p(0, 0), EaselFreehandDrawingTestsSupport.p(4, 9), EaselFreehandDrawingTestsSupport.p(40, 40)])), "Only two point drawings count as straight lines")
    }

    @Test
    func twoPointsDrawAStraightSegment() {
        #expect(EaselDrawing.smoothPath([EaselFreehandDrawingTestsSupport.p(0, 0), EaselFreehandDrawingTestsSupport.p(10, 0)]) == [.move(EaselFreehandDrawingTestsSupport.p(0, 0)), .line(EaselFreehandDrawingTestsSupport.p(10, 0))], "Two points draw a straight segment")
    }

    @Test
    func onePointDrawsADot() {
        #expect(EaselDrawing.smoothPath([EaselFreehandDrawingTestsSupport.p(3, 3)]) == [.move(EaselFreehandDrawingTestsSupport.p(3, 3)), .line(EaselFreehandDrawingTestsSupport.p(3, 3))], "One point draws a dot")
    }

    @Test
    func roundedCornersKeepTheExactEndpoints() {
        let curve = EaselDrawing.smoothPath([EaselFreehandDrawingTestsSupport.p(0, 0), EaselFreehandDrawingTestsSupport.p(10, 0), EaselFreehandDrawingTestsSupport.p(10, 10)])
        #expect(curve == [.move(EaselFreehandDrawingTestsSupport.p(0, 0)), .line(EaselFreehandDrawingTestsSupport.p(5, 0)), .quad(EaselFreehandDrawingTestsSupport.p(10, 5), control: EaselFreehandDrawingTestsSupport.p(10, 0)), .line(EaselFreehandDrawingTestsSupport.p(10, 10))], "Corners round through midpoints and the ends stay exact")
    }

    @Test
    func emptyStrokesHaveNoPath() {
        #expect(EaselDrawing.smoothPath([]).isEmpty, "No points, no path")
    }

    private enum Flip: String, CaseIterable, CustomTestStringConvertible {
        case neither, horizontal, vertical, both

        var testDescription: String { rawValue }
        var flips: (Bool, Bool) { (self == .horizontal || self == .both, self == .vertical || self == .both) }
    }

    @Test(arguments: [0.0, 30, -75, 180], Flip.allCases)
    private func placingATransformedStrokeKeepsEveryVisiblePoint(_ rotation: Double, _ flip: Flip) throws {
        let flips = flip.flips
        var item = EaselFreehandDrawingTestsSupport.stroke([EaselFreehandDrawingTestsSupport.p(100, 100), EaselFreehandDrawingTestsSupport.p(160, 120), EaselFreehandDrawingTestsSupport.p(200, 180)])
        item.rotation = rotation
        item.flipHorizontal = flips.0 ? true : nil
        item.flipVertical = flips.1 ? true : nil
        let visual = EaselDrawing.visualPoints(item)
        let moved = visual.map { EaselFreehandDrawingTestsSupport.p($0.x + 37, $0.y - 12) }
        let placed = try #require(EaselDrawing.placing(moved, like: item), "Placing failed")
        var copy = item
        copy.frame = placed.frame; copy.points = placed.points
        let again = EaselDrawing.visualPoints(copy)
        #expect(zip(again, moved).allSatisfy { EaselFreehandDrawingTestsSupport.near($0, $1, 1e-6) }, "Placing keeps every visible point for rotation \(rotation) and flips \(flips)")
    }

    @Test
    func strokesTurnClockwiseAroundTheirFrameCentre() {
        var turned = EaselFreehandDrawingTestsSupport.stroke([EaselFreehandDrawingTestsSupport.p(0, 0), EaselFreehandDrawingTestsSupport.p(100, 0)])
        turned.rotation = 90
        let ends = EaselDrawing.visualPoints(turned)
        #expect(EaselFreehandDrawingTestsSupport.near(ends[0], EaselFreehandDrawingTestsSupport.p(50.5, -49.5), 1e-6) && EaselFreehandDrawingTestsSupport.near(ends[1], EaselFreehandDrawingTestsSupport.p(50.5, 50.5), 1e-6), "Rotation turns clockwise around the frame centre")
    }

    @Test
    func aClickNearAStrokeCatchesIt() {
        let marker = EaselFreehandDrawingTestsSupport.stroke([EaselFreehandDrawingTestsSupport.p(0, 0), EaselFreehandDrawingTestsSupport.p(100, 0), EaselFreehandDrawingTestsSupport.p(100, 100)])
        #expect(EaselDrawing.touches(marker, from: EaselFreehandDrawingTestsSupport.p(50, 8), to: EaselFreehandDrawingTestsSupport.p(50, 8), scale: 1), "A click near a stroke catches it")
        #expect(!EaselDrawing.touches(marker, from: EaselFreehandDrawingTestsSupport.p(50, 20), to: EaselFreehandDrawingTestsSupport.p(50, 20), scale: 1), "A click well away misses")
    }

    @Test
    func aSwipeCatchesOnlyStrokesItCrosses() {
        let marker = EaselFreehandDrawingTestsSupport.stroke([EaselFreehandDrawingTestsSupport.p(0, 0), EaselFreehandDrawingTestsSupport.p(100, 0), EaselFreehandDrawingTestsSupport.p(100, 100)])
        #expect(EaselDrawing.touches(marker, from: EaselFreehandDrawingTestsSupport.p(50, -50), to: EaselFreehandDrawingTestsSupport.p(60, 60), scale: 1), "A swipe that crosses a stroke catches it")
        #expect(!EaselDrawing.touches(marker, from: EaselFreehandDrawingTestsSupport.p(-50, -50), to: EaselFreehandDrawingTestsSupport.p(-40, 60), scale: 1), "A swipe beside a stroke leaves it")
    }

    @Test
    func theEraserKeepsItsScreenSizeWhenZoomed() {
        let marker = EaselFreehandDrawingTestsSupport.stroke([EaselFreehandDrawingTestsSupport.p(0, 0), EaselFreehandDrawingTestsSupport.p(100, 0), EaselFreehandDrawingTestsSupport.p(100, 100)])
        #expect(!EaselDrawing.touches(marker, from: EaselFreehandDrawingTestsSupport.p(50, 8), to: EaselFreehandDrawingTestsSupport.p(50, 8), scale: 2), "Zoomed in, the eraser shrinks on the board to stay the same on screen")
        #expect(EaselDrawing.touches(marker, from: EaselFreehandDrawingTestsSupport.p(50, 15), to: EaselFreehandDrawingTestsSupport.p(50, 15), scale: 0.5), "Zoomed out, the eraser covers more of the board")
        #expect(EaselFreehandDrawingTestsSupport.near(EaselDrawing.eraserRadius(scale: 2), EaselDrawing.eraserRadius / 2), "The eraser radius scales with zoom")
    }

    @Test
    func lockedDrawingsNeverErase() {
        let marker = EaselFreehandDrawingTestsSupport.stroke([EaselFreehandDrawingTestsSupport.p(0, 0), EaselFreehandDrawingTestsSupport.p(100, 0), EaselFreehandDrawingTestsSupport.p(100, 100)])
        var locked = marker
        locked.locked = true
        #expect(!EaselDrawing.touches(locked, from: EaselFreehandDrawingTestsSupport.p(50, 0), to: EaselFreehandDrawingTestsSupport.p(50, 0), scale: 1), "Locked drawings never erase")
    }

    @Test
    func tapeIsCaughtWithinItsFlatEndedOutline() {
        let tape = EaselFreehandDrawingTestsSupport.stroke([EaselFreehandDrawingTestsSupport.p(0, 0), EaselFreehandDrawingTestsSupport.p(200, 0)], brush: .washi)
        #expect(EaselDrawing.touches(tape, from: EaselFreehandDrawingTestsSupport.p(100, 20), to: EaselFreehandDrawingTestsSupport.p(100, 20), scale: 1), "Tape is caught across its whole width")
        #expect(!EaselDrawing.touches(tape, from: EaselFreehandDrawingTestsSupport.p(100, 30), to: EaselFreehandDrawingTestsSupport.p(100, 30), scale: 1), "Tape has an edge")
        #expect(!EaselDrawing.touches(tape, from: EaselFreehandDrawingTestsSupport.p(220, 0), to: EaselFreehandDrawingTestsSupport.p(220, 0), scale: 1), "Tape ends are flat, not rounded")
        #expect(EaselDrawing.touches(tape, from: EaselFreehandDrawingTestsSupport.p(208, 0), to: EaselFreehandDrawingTestsSupport.p(208, 0), scale: 1), "The eraser still catches a tape end it overlaps")
    }

    @Test
    func rotatedTapeIsCaughtInItsTurnedPosition() {
        let tape = EaselFreehandDrawingTestsSupport.stroke([EaselFreehandDrawingTestsSupport.p(0, 0), EaselFreehandDrawingTestsSupport.p(200, 0)], brush: .washi)
        var turnedTape = tape
        turnedTape.rotation = 90
        #expect(EaselDrawing.touches(turnedTape, from: EaselFreehandDrawingTestsSupport.p(100, -80), to: EaselFreehandDrawingTestsSupport.p(100, -80), scale: 1), "Rotated tape is caught where it shows")
        #expect(!EaselDrawing.touches(turnedTape, from: EaselFreehandDrawingTestsSupport.p(20, 0), to: EaselFreehandDrawingTestsSupport.p(20, 0), scale: 1), "Rotated tape no longer covers its old spot")
    }

    @Test
    func theEraserLeavesOtherObjectsAlone() {
        let note = EaselFreehandDrawingTestsSupport.object(.sticky, 0, 0, 100, 100)
        #expect(!EaselDrawing.touches(note, from: EaselFreehandDrawingTestsSupport.p(50, 50), to: EaselFreehandDrawingTestsSupport.p(50, 50), scale: 1), "The eraser leaves everything but drawings alone")
    }

    @Test
    func aSwipeCollectsEveryDrawingItCrosses() {
        let marker = EaselFreehandDrawingTestsSupport.stroke([EaselFreehandDrawingTestsSupport.p(0, 0), EaselFreehandDrawingTestsSupport.p(100, 0), EaselFreehandDrawingTestsSupport.p(100, 100)])
        let tape = EaselFreehandDrawingTestsSupport.stroke([EaselFreehandDrawingTestsSupport.p(0, 0), EaselFreehandDrawingTestsSupport.p(200, 0)], brush: .washi)
        let note = EaselFreehandDrawingTestsSupport.object(.sticky, 0, 0, 100, 100)
        let ids = EaselDrawing.erased([marker, tape, note], from: EaselFreehandDrawingTestsSupport.p(10, -5), to: EaselFreehandDrawingTestsSupport.p(10, 5), scale: 1)
        #expect(ids == [marker.id, tape.id], "One swipe collects every drawing it crosses")
    }

    @Test
    func distantLongStrokesAreSkippedByTheirBounds() {
        let far = EaselFreehandDrawingTestsSupport.stroke((0..<5_000).map { EaselFreehandDrawingTestsSupport.p(Double($0) + 1_000, 1_000) })
        #expect(!EaselDrawing.touches(far, from: EaselFreehandDrawingTestsSupport.p(0, 0), to: EaselFreehandDrawingTestsSupport.p(10, 10), scale: 1), "Distant long strokes are skipped by their bounds")
    }

    @Test
    func aTapLeavesADotAndKeepsItsDrawingStyle() throws {
        var template = EaselItem(kind: .freehand, frame: EaselRect(x: 0, y: 0, width: 1, height: 1), zIndex: 7, color: "#2C6C91")
        template.brush = .marker
        let tap = try #require(EaselDrawing.strokeItem([EaselFreehandDrawingTestsSupport.p(40, 50)], like: template, straight: false, strict: false, scale: 1), "A tap draws")
        #expect(tap.points.count == 2 && tap.points[0] == tap.points[1] && tap.frame.x == 40 && tap.frame.y == 50, "A tap leaves a dot of two equal points")
        #expect(tap.brush == .marker && tap.zIndex == 7 && tap.color == "#2C6C91", "New strokes keep the brush, layer and colour they started with")
    }

    @Test
    func shiftTurnsAWobbleIntoALevelLine() throws {
        var template = EaselItem(kind: .freehand, frame: EaselRect(x: 0, y: 0, width: 1, height: 1), zIndex: 7, color: "#2C6C91")
        template.brush = .marker
        let wobble = [EaselFreehandDrawingTestsSupport.p(0, 0), EaselFreehandDrawingTestsSupport.p(30, 1.5), EaselFreehandDrawingTestsSupport.p(60, -1), EaselFreehandDrawingTestsSupport.p(100, 3)]
        let line = try #require(EaselDrawing.strokeItem(wobble, like: template, straight: true, strict: false, scale: 1), "Shift draws")
        #expect(line.points.count == 2 && line.frame.height == 1 && EaselFreehandDrawingTestsSupport.near(line.points[1].x, hypot(100, 3)), "Shift turns a wobbly stroke into one level line from where it started")
    }

    @Test
    func freehandStrokesFinishAsSimplifiedCurves() {
        var template = EaselItem(kind: .freehand, frame: EaselRect(x: 0, y: 0, width: 1, height: 1), zIndex: 7, color: "#2C6C91")
        template.brush = .marker
        guard let curve = EaselDrawing.strokeItem((0...120).map { EaselFreehandDrawingTestsSupport.p(Double($0), sin(Double($0) / 9) * 30) }, like: template,
                                                  straight: false, strict: false, scale: 1) else { Issue.record("Freehand draws"); return }
        #expect(curve.points.count > 2 && curve.points.count < 121, "Freehand strokes are smoothed and simplified when they finish")
        #expect(EaselDrawing.pathElements(curve).contains { if case .quad = $0 { return true } else { return false } }, "New strokes draw through smooth curves")
    }

    @Test
    func legacyDoodlesKeepSharpCorners() {
        let legacy = EaselFreehandDrawingTestsSupport.stroke([EaselFreehandDrawingTestsSupport.p(0, 0), EaselFreehandDrawingTestsSupport.p(5, 15), EaselFreehandDrawingTestsSupport.p(10, 0)])
        #expect(EaselDrawing.pathElements(legacy) == [.move(EaselFreehandDrawingTestsSupport.p(0, 0)), .line(EaselFreehandDrawingTestsSupport.p(5, 15)), .line(EaselFreehandDrawingTestsSupport.p(10, 0))], "Doodles saved before smoothing keep their sharp corners")
    }

    @Test
    func aNudgeTooShortForTapeLaysNothing() {
        var template = EaselItem(kind: .freehand, frame: EaselRect(x: 0, y: 0, width: 1, height: 1), zIndex: 7, color: "#2C6C91")
        template.brush = .marker
        var tapeTemplate = template
        tapeTemplate.brush = .washi
        #expect(EaselDrawing.strokeItem([EaselFreehandDrawingTestsSupport.p(0, 0), EaselFreehandDrawingTestsSupport.p(2, 1)], like: tapeTemplate, straight: false, strict: false, scale: 1) == nil, "A nudge too short for tape lays nothing")
    }

    @Test
    func tapeStaysStraightAndShiftSnapsItsAngle() {
        var template = EaselItem(kind: .freehand, frame: EaselRect(x: 0, y: 0, width: 1, height: 1), zIndex: 7, color: "#2C6C91")
        template.brush = .marker
        var tapeTemplate = template
        tapeTemplate.brush = .washi
        guard let tape = EaselDrawing.strokeItem([EaselFreehandDrawingTestsSupport.p(0, 0), EaselFreehandDrawingTestsSupport.p(40, 3), EaselFreehandDrawingTestsSupport.p(90, 52)], like: tapeTemplate, straight: false, strict: true, scale: 1) else {
            Issue.record("Tape draws")
            return
        }
        #expect(tape.points.count == 2 && EaselFreehandDrawingTestsSupport.near(tape.points[1].x - tape.points[0].x, tape.points[1].y - tape.points[0].y), "Tape is always straight and Shift snaps it to 45 degrees")
    }

    @MainActor @Test
    func aCompletedStrokeIsOneUndoStep() throws {
        var template = EaselItem(kind: .freehand, frame: EaselRect(x: 0, y: 0, width: 1, height: 1), zIndex: 7, color: "#2C6C91")
        template.brush = .marker
        guard let curve = EaselDrawing.strokeItem((0...120).map { EaselFreehandDrawingTestsSupport.p(Double($0), sin(Double($0) / 9) * 30) }, like: template,
                                                  straight: false, strict: false, scale: 1) else { Issue.record("Freehand draws"); return }
        let session = try #require(try? EaselSession(inMemory: EaselFreehandDrawingTestsSupport.document([]), assets: [:]), "Session opens")
        try? session.perform("Draw") { $0.items.append(curve) }
        #expect(session.document.items.count == 1 && session.canUndo, "A finished stroke lands in one change")
        try? session.undo()
        #expect(session.document.items.isEmpty && !session.canUndo, "One Undo takes the whole stroke back")
    }
}
