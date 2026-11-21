import Foundation

@main
struct EaselSnapFeedbackTests {
    static func expect(_ value: Bool, _ message: String) {
        if !value { failTest(message) }
    }

    static func near(_ a: Double, _ b: Double, _ tolerance: Double = 1e-6) -> Bool { abs(a - b) <= tolerance }

    static func main() {
        guides()
        reveals()
        highlights()
        rotation()
        sections()
        folds()
        equalSizes()
        print("EaselSnapFeedbackTests passed")
    }

    static func guides() {
        expect(near(EaselFeedbackCurve.guideOpacity(0), 0), "a new guide starts transparent")
        expect(near(EaselFeedbackCurve.guideOpacity(0.08), 1), "a guide is fully in after 0.08 s")
        expect(EaselFeedbackCurve.guideOpacity(0.04) > 0.5, "a guide fades in on an ease-out")
        expect(near(EaselFeedbackCurve.markScale(0, reduced: false), EaselFeedbackCurve.markFrom), "end marks start small")
        let peak = stride(from: 0.0, to: EaselFeedbackCurve.markPop, by: 0.005).map { EaselFeedbackCurve.markScale($0, reduced: false) }.max() ?? 0
        expect(peak > 1, "end marks overshoot as they pop")
        expect(near(EaselFeedbackCurve.markScale(1, reduced: false), 1), "end marks rest at full size")
        expect(near(EaselFeedbackCurve.markScale(0, reduced: true), 1), "Reduce Motion keeps end marks still")
        let a = EaselGuideSnapKey(anchor: .left, coordinate: 120.001), b = EaselGuideSnapKey(anchor: .left, coordinate: 120.002)
        expect(a == b, "the same guide keeps one key while held")
        expect(a != EaselGuideSnapKey(anchor: .centerX, coordinate: 120), "different anchors are different engagements")
    }

    static func reveals() {
        let pieces: [[EaselConnectorRoute.Segment]] = [[.line(.init(x: 0, y: 0), .init(x: 100, y: 0)),
                                                       .line(.init(x: 100, y: 0), .init(x: 100, y: 100))]]
        expect(near(EaselConnectorReveal.length(of: pieces), 200), "piece length sums segments")
        let half = EaselConnectorReveal.trimmed(pieces, fraction: 0.5)
        expect(half.count == 1 && half[0].count == 1 && half[0][0].end == EaselPoint(x: 100, y: 0), "half a route stops at the corner")
        let quarter = EaselConnectorReveal.trimmed(pieces, fraction: 0.75)
        expect(quarter[0].count == 2 && near(quarter[0][1].end.y, 50), "a partial segment is cut at its arc length")
        expect(EaselConnectorReveal.trimmed(pieces, fraction: 1) == pieces, "a finished reveal draws the whole route")
        expect(EaselConnectorReveal.trimmed(pieces, fraction: 0).isEmpty, "a reveal starts empty")
        let curve: [[EaselConnectorRoute.Segment]] = [[.cubic(.init(x: 0, y: 0), .init(x: 0, y: 50), .init(x: 100, y: 50), .init(x: 100, y: 0))]]
        let tip = EaselConnectorReveal.tip(curve, fraction: 0.5)
        expect(tip.map { near($0.x, 50, 2) } == true, "a curve reveals by arc length")
        expect(near(EaselFeedbackCurve.revealFraction(0, reduced: false), 0), "drawing starts at the start")
        expect(near(EaselFeedbackCurve.revealFraction(0.25, reduced: false), 1), "drawing finishes in 0.25 s")
        expect(near(EaselFeedbackCurve.revealFraction(0, reduced: true), 1), "Reduce Motion draws the whole connector at once")
        expect(near(EaselFeedbackCurve.headScale(0, reduced: false), 0), "an arrowhead pops from nothing")
        let peak = stride(from: 0.0, to: EaselFeedbackCurve.headPop, by: 0.005).map { EaselFeedbackCurve.headScale($0, reduced: false) }.max() ?? 0
        expect(peak > 1.02, "an arrowhead overshoots")
        expect(near(EaselFeedbackCurve.headScale(1, reduced: false), 1), "an arrowhead rests at full size")
        expect(!EaselFeedbackCurve.revealFinished(0.3, reduced: false, drawsLine: true), "the head pops after the line")
        expect(EaselFeedbackCurve.revealFinished(0.7, reduced: false, drawsLine: true), "the reveal ends")
        expect(EaselFeedbackCurve.revealFinished(0.16, reduced: true, drawsLine: true), "the reduced fade is short")
    }

    static func highlights() {
        expect(near(EaselFeedbackCurve.highlighted(0, from: 4, to: 5.5), 4), "an anchor dot grows from its size")
        expect(near(EaselFeedbackCurve.highlighted(1, from: 4, to: 5.5), 5.5), "an anchor dot settles at its target")
        expect(near(EaselFeedbackCurve.trayLevel(0.1, from: 0, rising: true), 1), "a tray brightens in 0.1 s")
        expect(near(EaselFeedbackCurve.trayLevel(0.1, from: 0.6, rising: false), 0), "a tray dims from where it is")
        expect(near(EaselFeedbackCurve.flashLevel(EaselFeedbackCurve.flashRise), 1), "a flash peaks quickly")
        expect(near(EaselFeedbackCurve.flashLevel(EaselFeedbackCurve.flash), 0), "a flash ends")
        expect(near(EaselFeedbackCurve.grownValue(0, from: 220, to: 260), 220), "sticky growth starts at the old height")
        expect(near(EaselFeedbackCurve.grownValue(1, from: 220, to: 260), 260), "sticky growth lands at the new height")
        expect(near(EaselFeedbackCurve.tableSlideProgress(0), 0) && near(EaselFeedbackCurve.tableSlideProgress(1), 1), "table slides run 0 to 1")
    }

    static func rotation() {
        expect(EaselRotationSnap.step(0) == 0 && EaselRotationSnap.step(15) == 1, "15 degree steps")
        expect(EaselRotationSnap.step(360) == 0 && EaselRotationSnap.step(-15) == 23, "steps wrap around the circle")
        expect(EaselRotationSnap.step(.nan) == nil, "invalid angles have no step")
    }

    static func box(_ kind: EaselItemKind, _ x: Double, _ y: Double, _ w: Double, _ h: Double) -> EaselItem {
        EaselItem(kind: kind, frame: EaselRect(x: x, y: y, width: w, height: h), zIndex: 0)
    }

    static func sections() {
        let outer = box(.section, 0, 0, 800, 600), inner = box(.section, 50, 50, 300, 300)
        var sticky = box(.sticky, 900, 900, 100, 100)
        let original = sticky
        sticky.frame.x = 100; sticky.frame.y = 100
        let items = [outer, inner, original]
        expect(EaselSectionDrop.target(moving: [sticky], original: [original], in: items) == inner.id, "the innermost tray lights up")
        sticky.frame.x = 500
        expect(EaselSectionDrop.target(moving: [sticky], original: [original], in: items) == outer.id, "an outer tray lights up outside the inner one")
        var inside = box(.sticky, 400, 400, 50, 50)
        let start = inside
        inside.frame.x = 420
        expect(EaselSectionDrop.target(moving: [inside], original: [start], in: [outer, start]) == nil, "moving within a tray doesn't light it")
        sticky.frame.x = 760
        expect(EaselSectionDrop.target(moving: [sticky], original: [original], in: items) == nil, "half in doesn't count")
    }

    static func folds() {
        let start = EaselFeedbackCurve.foldPresentation(0, toward: EaselPoint(x: -100, y: 0), reduced: false)
        expect(start.isIdentity, "a fold starts where the branch is")
        let end = EaselFeedbackCurve.foldPresentation(EaselFeedbackCurve.fold, toward: EaselPoint(x: -100, y: 0), reduced: false)
        expect(near(end.opacity, 0) && near(end.offset.x, -100), "a fold ends in the parent, transparent")
        let reduced = EaselFeedbackCurve.foldPresentation(0.05, toward: EaselPoint(x: -100, y: 0), reduced: true)
        expect(near(reduced.offset.x, 0) && near(reduced.scale, 1) && reduced.opacity < 1, "Reduce Motion folds by fading only")
        let delays = EaselFeedbackCurve.unfoldDelays(depths: [1, 2, 2, 3])
        expect(delays[0] == 0 && delays[1] == delays[2] && delays[3] > delays[1], "deeper topics unfold later")
        expect((delays.max() ?? 0) <= EaselFeedbackCurve.unfoldSpread + 1e-9, "the unfold spread stays short")
        expect(EaselFeedbackCurve.unfoldDelays(depths: [2, 2]) == [0, 0], "one level unfolds together")
    }

    static func equalSizes() {
        let other = box(.rectangle, 400, 0, 200, 120)
        var item = box(.rectangle, 0, 0, 196, 80)
        let snapped = EaselEqualSize.snap(item, handle: .right, centered: false, candidates: [other], scale: 1, lockedX: false, lockedY: false)
        expect(near(snapped.item.frame.width, 200) && near(snapped.item.frame.x, 0), "a right-edge resize snaps to an equal width")
        expect(snapped.matches == [EaselSizeMatch(other: other.id, horizontal: true)], "the matching object is reported")
        var shifted = item
        shifted.frame.x = 100
        let left = EaselEqualSize.snap(shifted, handle: .left, centered: false, candidates: [other], scale: 1, lockedX: false, lockedY: false)
        expect(near(left.item.frame.x + left.item.frame.width, 296) && near(left.item.frame.width, 200), "a left-edge resize keeps the right edge")
        let locked = EaselEqualSize.snap(item, handle: .right, centered: false, candidates: [other], scale: 1, lockedX: true, lockedY: false)
        expect(near(locked.item.frame.width, 196), "an engaged guide wins over equal size")
        let far = EaselEqualSize.snap(item, handle: .right, centered: false, candidates: [other], scale: 2, lockedX: false, lockedY: false)
        expect(near(far.item.frame.width, 196), "the tolerance is measured on screen")
        item.frame.height = 117
        let corner = EaselEqualSize.snap(item, handle: .bottomRight, centered: false, candidates: [other], scale: 1, lockedX: false, lockedY: false)
        expect(near(corner.item.frame.width, 200) && near(corner.item.frame.height, 120) && corner.matches.count == 2, "a corner snaps both sizes")
        expect(EaselEqualSize.lines(corner.item, matches: corner.matches, in: [other], scale: 1).count == 2, "each match draws a dimension pair")
        expect(!EaselEqualSize.resizes(.sticky) && !EaselEqualSize.resizes(.text), "stickies and text keep their own sizing")
    }
}
