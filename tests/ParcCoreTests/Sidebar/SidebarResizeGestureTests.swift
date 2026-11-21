import Foundation
import Testing
@testable import ParcCore

struct SidebarResizeGestureTests {
    typealias G = SidebarResizeGesture

    @Test func theGestureKeepsTheRecoveredLimitsDetentAndReleaseHold() {
        #expect(G.minimumWidth == 164 && G.maximumWidth == 500 && G.collapseThreshold == 82, "recovered limits")
        #expect(G.defaultWidth == 8 + 8 + 4 * 47 + 3 * 8 && G.snapBand == 14 && G.snapMaximumVelocity == 50, "recovered detent")
        #expect(G.releaseFeedbackHold == 0.5, "recovered release hold")
    }

    @Test func draggingRoundsClampsPreviewsHiddenAndCommitsOrRestoresOnRelease() {
        var g = G(width: 300, locked: true)
        #expect(!g.canSnap && !g.isSnapped && g.effectiveWidth == 300, "begin is unarmed at the store width")
        let r1 = g.change(translationX: 0.5, velocityX: 0, now: 0)
        #expect(r1.width == 301, "ties round away from zero")
        let r2 = g.change(translationX: 0.49, velocityX: 0, now: 0)
        #expect(r2.width == 300, "below half rounds down")
        let r3 = g.change(translationX: 400, velocityX: 0, now: 0)
        #expect(r3.width == 500, "hard maximum without rubber band")
        var low = G(width: 200, locked: true)
        let r4 = low.change(translationX: -36.5, velocityX: 0, now: 0)
        #expect(r4.width == 164, "164 minimum after rounding 163.5")
        let r5 = low.change(translationX: -118, velocityX: 0, now: 0)
        #expect(r5.width == 164, "exactly 82 is clamped, not previewed")
        let r6 = low.end(.ended, translationX: -118)
        #expect(r6.collapses, "release exactly at 82 collapses")

        let previewing = low.change(translationX: -118.6, velocityX: -900, now: 0)
        #expect(previewing.width == 0 && previewing.events == [.previewHiddenChanged(true)] && low.isPreviewingHidden, "below 82 previews hidden once")
        let r7 = low.change(translationX: -150, velocityX: -900, now: 0)
        #expect(r7.events.isEmpty, "staying hidden repeats nothing")
        let r8 = low.change(translationX: -150, velocityX: 0, now: 0)
        #expect(r8 == .init(width: 0, widthChanged: false, events: []), "unchanged width needs no relayout")
        let committedCollapse = low.end(.ended, translationX: -150)
        #expect(committedCollapse == .init(width: 200, collapses: true), "locked collapse commits widthOnBegin")
        let restored = low.change(translationX: -30, velocityX: 900, now: 0)
        #expect(restored.width == 170 && restored.events == [.previewHiddenChanged(false)], "leaving preview publishes once")
        let r9 = low.end(.ended, translationX: -30)
        #expect(r9 == .init(width: 170, collapses: false), "ordinary release commits effective width")
        var floating = G(width: 200, locked: false)
        _ = floating.change(translationX: -190, velocityX: 0, now: 0)
        #expect(floating.isPreviewingHidden, "floating drag also previews")
        let r10 = floating.end(.ended, translationX: -190)
        #expect(r10 == .init(width: 164, collapses: false), "floating preview clamps without collapse")
        let r11 = low.end(.cancelled, translationX: -150)
        #expect(r11 == .init(width: 200, collapses: false), "cancel restores widthOnBegin")
        let r12 = low.end(.failed, translationX: 300)
        #expect(r12 == .init(width: 200, collapses: false), "failure restores widthOnBegin")
        #expect(G(width: 600, locked: true).end(.cancelled, translationX: 0).width == 500, "restored width is clamped")
    }

    @Test func anUnarmedBandPassesThroughUntilTheDragLeavesIt() {
        var inside = G(width: 230, locked: true)
        let r13 = inside.change(translationX: -1, velocityX: -10, now: 0)
        #expect(r13 == .init(width: 229, widthChanged: true, events: []), "unarmed band passes through")
        #expect(!inside.canSnap, "inside band stays unarmed")
        let r14 = inside.change(translationX: 12, velocityX: 10, now: 0)
        #expect(r14.width == 242 && inside.canSnap, "leaving the band arms at 14")
    }

    @Test func snappingToTheDefaultWidthDependsOnDirectionVelocityAndHoldTime() {
        var s = G(width: 300, locked: true)
        _ = s.change(translationX: -30, velocityX: -200, now: 1)
        #expect(s.canSnap, "outside the band arms")
        let r15 = s.change(translationX: -70, velocityX: -50, now: 1)
        #expect(r15.width == 230 && !s.isSnapped, "|vx| at 50 skips the snap")
        let r16 = s.change(translationX: -62, velocityX: -10, now: 1)
        #expect(r16.width == 238 && !s.isSnapped, "above the default moving left does not snap")
        let engaged = s.change(translationX: -63, velocityX: 10, now: 2)
        #expect(engaged == .init(width: 228, widthChanged: true, events: [.snapEngaged]) && s.isSnapped, "above the default moving right snaps")
        #expect(s.timeOfSnap == 2, "snap time recorded")
        let r17 = s.change(translationX: -60, velocityX: 900, now: 2.1)
        #expect(r17 == .init(width: 228, widthChanged: false, events: []), "snapped holds within the band at any velocity")
        let r18 = s.change(translationX: -85, velocityX: -900, now: 2.2)
        #expect(r18.width == 228, "snapped holds on the other side")
        let early = s.change(translationX: -86, velocityX: -900, now: 2.3)
        #expect(early == .init(width: 214, widthChanged: true, events: [.snapReleased(haptic: false)]) && !s.isSnapped, "short hold releases without haptic")
        let again = s.change(translationX: -77, velocityX: -10, now: 3)
        #expect(again.width == 228 && again.events == [.snapEngaged], "below the default moving left snaps")
        let r19 = s.change(translationX: -73, velocityX: 0, now: 3.5)
        #expect(r19.width == 228, "hold continues")
        let r20 = s.change(translationX: -58, velocityX: 0, now: 3.5)
        #expect(r20.events == [.snapReleased(haptic: false)], "exactly 0.5 s is not longer")
        _ = s.change(translationX: -63, velocityX: 0, now: 4)
        #expect(s.isSnapped, "zero velocity above the default snaps")
        let late = s.change(translationX: -40, velocityX: 0, now: 4.51)
        #expect(late.width == 260 && late.events == [.snapReleased(haptic: true)], "hold longer than 0.5 s releases with haptic")
        let r21 = s.change(translationX: -40, velocityX: 0, now: 5)
        #expect(r21.events.isEmpty, "release fires once")
        let r22 = s.end(.ended, translationX: -40)
        #expect(r22 == .init(width: 260, collapses: false), "release after a snap commits the live width")
    }

    @Test func releasingWhileSnappedCommitsTheDefaultAndADiveKeepsEventOrder() {
        var held = G(width: 300, locked: true)
        _ = held.change(translationX: -30, velocityX: 0, now: 0); _ = held.change(translationX: -66, velocityX: 0, now: 0)
        let r23 = held.end(.ended, translationX: -66)
        #expect(r23 == .init(width: 228, collapses: false), "release while snapped commits the default")
        var dive = G(width: 300, locked: true)
        _ = dive.change(translationX: -30, velocityX: 0, now: 0); _ = dive.change(translationX: -66, velocityX: 0, now: 0)
        let dived = dive.change(translationX: -280, velocityX: -900, now: 1)
        #expect(dived.events == [.snapReleased(haptic: true), .previewHiddenChanged(true)] && dived.width == 0, "events keep their order")
    }

    @Test func breakpointsPublishOnlyWhenCrossed() {
        #expect(G.breakpointIndex(for: 99, in: [100, 200]) == 0 && G.breakpointIndex(for: 100, in: [100, 200]) == 1, "breakpoint boundaries")
        #expect(G.breakpointIndex(for: 300, in: [100, 200]) == 2 && G.breakpointIndex(for: 50, in: []) == 0, "past the last breakpoint")
        var b = G(width: 150, locked: false, breakpoints: [100, 200])
        #expect(b.breakpointIndex == 1, "initial breakpoint index")
        let r24 = b.change(translationX: 10, velocityX: 0, now: 0)
        #expect(r24.events.isEmpty, "same breakpoint is silent")
        let r25 = b.change(translationX: 60, velocityX: 0, now: 0)
        #expect(r25.events == [.breakpointChanged(2)], "crossing a breakpoint publishes")
        let r26 = b.change(translationX: -140, velocityX: 0, now: 0)
        #expect(r26.events == [.previewHiddenChanged(true), .breakpointChanged(0)], "hidden preview is below the first breakpoint")
    }

    @Test func nonFiniteInputIsIgnored() {
        var invalid = G(width: 240, locked: true)
        let r27 = invalid.change(translationX: .nan, velocityX: 0, now: 0)
        #expect(r27 == .init(width: 240, widthChanged: false, events: []), "non-finite translation ignored")
        let r28 = invalid.change(translationX: 0, velocityX: .infinity, now: 0)
        #expect(r28.width == 240, "non-finite velocity ignored")
        let r29 = invalid.end(.ended, translationX: .nan)
        #expect(r29 == .init(width: 240, collapses: false), "non-finite release does not collapse")

    }
}
