import Foundation

@main struct SidebarResizeGestureTests {
    static var count = 0
    static func check(_ value: @autoclosure () -> Bool, _ message: String) {
        count += 1
        guard value() else { fatalError("SidebarResizeGesture: \(message)") }
    }
    static func main() {
        typealias G = SidebarResizeGesture
        check(G.minimumWidth == 164 && G.maximumWidth == 500 && G.collapseThreshold == 82, "recovered limits")
        check(G.defaultWidth == 8 + 8 + 4 * 47 + 3 * 8 && G.snapBand == 14 && G.snapMaximumVelocity == 50, "recovered detent")
        check(G.releaseFeedbackHold == 0.5, "recovered release hold")

        // Rounding is half away from zero of widthOnBegin + translation, then a hard clamp.
        var g = G(width: 300, locked: true)
        check(!g.canSnap && !g.isSnapped && g.effectiveWidth == 300, "begin is unarmed at the store width")
        check(g.change(translationX: 0.5, velocityX: 0, now: 0).width == 301, "ties round away from zero")
        check(g.change(translationX: 0.49, velocityX: 0, now: 0).width == 300, "below half rounds down")
        check(g.change(translationX: 400, velocityX: 0, now: 0).width == 500, "hard maximum without rubber band")
        var low = G(width: 200, locked: true)
        check(low.change(translationX: -36.5, velocityX: 0, now: 0).width == 164, "164 minimum after rounding 163.5")
        check(low.change(translationX: -118, velocityX: 0, now: 0).width == 164, "exactly 82 is clamped, not previewed")
        check(low.end(.ended, translationX: -118).collapses, "release exactly at 82 collapses")

        // Collapse preview and its single boundary events.
        let previewing = low.change(translationX: -118.6, velocityX: -900, now: 0)
        check(previewing.width == 0 && previewing.events == [.previewHiddenChanged(true)] && low.isPreviewingHidden, "below 82 previews hidden once")
        check(low.change(translationX: -150, velocityX: -900, now: 0).events.isEmpty, "staying hidden repeats nothing")
        check(low.change(translationX: -150, velocityX: 0, now: 0) == .init(width: 0, widthChanged: false, events: []), "unchanged width needs no relayout")
        let committedCollapse = low.end(.ended, translationX: -150)
        check(committedCollapse == .init(width: 200, collapses: true), "locked collapse commits widthOnBegin")
        let restored = low.change(translationX: -30, velocityX: 900, now: 0)
        check(restored.width == 170 && restored.events == [.previewHiddenChanged(false)], "leaving preview publishes once")
        check(low.end(.ended, translationX: -30) == .init(width: 170, collapses: false), "ordinary release commits effective width")
        var floating = G(width: 200, locked: false)
        _ = floating.change(translationX: -190, velocityX: 0, now: 0)
        check(floating.isPreviewingHidden, "floating drag also previews")
        check(floating.end(.ended, translationX: -190) == .init(width: 164, collapses: false), "floating preview clamps without collapse")
        check(low.end(.cancelled, translationX: -150) == .init(width: 200, collapses: false), "cancel restores widthOnBegin")
        check(low.end(.failed, translationX: 300) == .init(width: 200, collapses: false), "failure restores widthOnBegin")
        check(G(width: 600, locked: true).end(.cancelled, translationX: 0).width == 500, "restored width is clamped")

        // Arming: a drag beginning inside the band never snaps until it has left once.
        var inside = G(width: 230, locked: true)
        check(inside.change(translationX: -1, velocityX: -10, now: 0) == .init(width: 229, widthChanged: true, events: []), "unarmed band passes through")
        check(!inside.canSnap, "inside band stays unarmed")
        check(inside.change(translationX: 12, velocityX: 10, now: 0).width == 242 && inside.canSnap, "leaving the band arms at 14")

        // Velocity gate and direction test (proposed > 228) XOR (vx < 0).
        var s = G(width: 300, locked: true)
        _ = s.change(translationX: -30, velocityX: -200, now: 1)
        check(s.canSnap, "outside the band arms")
        check(s.change(translationX: -70, velocityX: -50, now: 1).width == 230 && !s.isSnapped, "|vx| at 50 skips the snap")
        check(s.change(translationX: -62, velocityX: -10, now: 1).width == 238 && !s.isSnapped, "above the default moving left does not snap")
        let engaged = s.change(translationX: -63, velocityX: 10, now: 2)
        check(engaged == .init(width: 228, widthChanged: true, events: [.snapEngaged]) && s.isSnapped, "above the default moving right snaps")
        check(s.timeOfSnap == 2, "snap time recorded")
        check(s.change(translationX: -60, velocityX: 900, now: 2.1) == .init(width: 228, widthChanged: false, events: []), "snapped holds within the band at any velocity")
        check(s.change(translationX: -85, velocityX: -900, now: 2.2).width == 228, "snapped holds on the other side")
        let early = s.change(translationX: -86, velocityX: -900, now: 2.3)
        check(early == .init(width: 214, widthChanged: true, events: [.snapReleased(haptic: false)]) && !s.isSnapped, "short hold releases without haptic")
        let again = s.change(translationX: -77, velocityX: -10, now: 3)
        check(again.width == 228 && again.events == [.snapEngaged], "below the default moving left snaps")
        check(s.change(translationX: -73, velocityX: 0, now: 3.5).width == 228, "hold continues")
        check(s.change(translationX: -58, velocityX: 0, now: 3.5).events == [.snapReleased(haptic: false)], "exactly 0.5 s is not longer")
        _ = s.change(translationX: -63, velocityX: 0, now: 4)
        check(s.isSnapped, "zero velocity above the default snaps")
        let late = s.change(translationX: -40, velocityX: 0, now: 4.51)
        check(late.width == 260 && late.events == [.snapReleased(haptic: true)], "hold longer than 0.5 s releases with haptic")
        check(s.change(translationX: -40, velocityX: 0, now: 5).events.isEmpty, "release fires once")
        check(s.end(.ended, translationX: -40) == .init(width: 260, collapses: false), "release after a snap commits the live width")
        var held = G(width: 300, locked: true)
        _ = held.change(translationX: -30, velocityX: 0, now: 0); _ = held.change(translationX: -66, velocityX: 0, now: 0)
        check(held.end(.ended, translationX: -66) == .init(width: 228, collapses: false), "release while snapped commits the default")
        var dive = G(width: 300, locked: true)
        _ = dive.change(translationX: -30, velocityX: 0, now: 0); _ = dive.change(translationX: -66, velocityX: 0, now: 0)
        let dived = dive.change(translationX: -280, velocityX: -900, now: 1)
        check(dived.events == [.snapReleased(haptic: true), .previewHiddenChanged(true)] && dived.width == 0, "events keep the order")

        // Breakpoints: the first i with 0 <= width < b[i], otherwise the count.
        check(G.breakpointIndex(for: 99, in: [100, 200]) == 0 && G.breakpointIndex(for: 100, in: [100, 200]) == 1, "breakpoint boundaries")
        check(G.breakpointIndex(for: 300, in: [100, 200]) == 2 && G.breakpointIndex(for: 50, in: []) == 0, "past the last breakpoint")
        var b = G(width: 150, locked: false, breakpoints: [100, 200])
        check(b.breakpointIndex == 1, "initial breakpoint index")
        check(b.change(translationX: 10, velocityX: 0, now: 0).events.isEmpty, "same breakpoint is silent")
        check(b.change(translationX: 60, velocityX: 0, now: 0).events == [.breakpointChanged(2)], "crossing a breakpoint publishes")
        check(b.change(translationX: -140, velocityX: 0, now: 0).events == [.previewHiddenChanged(true), .breakpointChanged(0)], "hidden preview is below the first breakpoint")

        // Invalid native input cannot alter the session.
        var invalid = G(width: 240, locked: true)
        check(invalid.change(translationX: .nan, velocityX: 0, now: 0) == .init(width: 240, widthChanged: false, events: []), "non-finite translation ignored")
        check(invalid.change(translationX: 0, velocityX: .infinity, now: 0).width == 240, "non-finite velocity ignored")
        check(invalid.end(.ended, translationX: .nan) == .init(width: 240, collapses: false), "non-finite release does not collapse")
        print("SidebarResizeGesture: \(count) assertions passed")
    }
}
