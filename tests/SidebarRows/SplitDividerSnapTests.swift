import AppKit

@main @MainActor struct SplitDividerSnapTests {
    static var count = 0
    static func check(_ value: @autoclosure () throws -> Bool, _ message: String) throws {
        count += 1
        if try !value() { throw NSError(domain: message, code: count) }
    }
    static func main() { exitOnFailure(runChecks) }
    static func runChecks() throws {
        var state = SplitDividerSnapState()
        try check(!state.update(distance: 0, velocity: 0) && !state.canSnap && !state.isSnapped, "Initial center is unarmed")
        try check(!state.update(distance: -14, velocity: 0) && state.canSnap, "Leaving exact fourteen-point boundary arms")
        try check(!state.update(distance: -6, velocity: -50) && !state.isSnapped, "Moving away from center does not snap")
        try check(!state.update(distance: -6, velocity: 121) && !state.isSnapped, "Fast approach passes through")
        try check(state.update(distance: -6, velocity: 120) && state.isSnapped, "Slow approach at actual velocity boundary snaps")
        try check(!state.update(distance: 13, velocity: 900) && state.isSnapped, "Already snapped stays within the band")
        try check(state.update(distance: 14, velocity: 900) && !state.isSnapped, "Leaving band releases once")
        try check(!state.update(distance: 20, velocity: 900), "Continuing outside does not repeat release")
        try check(state.update(distance: 6, velocity: -50) && state.isSnapped, "Opposite slow approach also snaps")
        try check(!state.update(distance: .nan, velocity: 1) && state.isSnapped, "Invalid input cannot alter native state")
        _ = NSApplication.shared
        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1400, height: 1000), styleMask: .borderless, backing: .buffered, defer: false)
        win.isReleasedWhenClosed = false; defer { win.close() }
        let view = ParcSplitView(frame: win.contentView!.bounds); win.contentView!.addSubview(view)
        for _ in 0..<3 { view.addArrangedSubview(NSView()) }
        view.configure(orientation: .horizontal, factors: [0.3,0.3,0.4])
        let originals = view.arrangedSubviews, originalFrames = originals.map(\.frame)
        var commits: [[Double]] = [], pulses = 0
        view.prepareDividerResize = { { commits.append($0); return true } }
        view.onSnapTransition = { pulses += 1 }
        let origin = NSPoint(x: originals[0].frame.maxX + 3, y: 100)
        let recognizer = view.gestureRecognizers.compactMap { $0 as? NSPanGestureRecognizer }.first!
        func event(_ point: NSPoint) -> NSEvent {
            NSEvent.mouseEvent(with: .leftMouseDown, location: view.convert(point, to: nil), modifierFlags: [], timestamp: 0, windowNumber: win.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
        }
        try check(!view.gestureRecognizer(recognizer, shouldAttemptToRecognizeWith: event(NSPoint(x: 100, y: 100))), "Page content opts out before native recognition")
        try check(view.gestureRecognizer(recognizer, shouldAttemptToRecognizeWith: event(origin)), "Actual divider admits original native pan")
        try check(view.gestureRecognizerShouldBegin(recognizer), "Original admitted views still own gesture")
        view.updateDividerResize(at: NSPoint(x: origin.x + 40, y: origin.y), velocity: 200)
        view.updateDividerResize(at: NSPoint(x: origin.x + 6, y: origin.y), velocity: -50)
        try check(pulses == 1 && abs(originals[0].frame.width - originals[1].frame.width) < 0.001, "Actual pair snaps with one native transition")
        try check(originals[2].frame == originalFrames[2] && commits.isEmpty, "Unrelated pane and durable data stay untouched during preview")
        view.updateDividerResize(at: NSPoint(x: origin.x + 8, y: origin.y), velocity: 500)
        try check(pulses == 1, "In-band preview does not repeat haptic")
        view.updateDividerResize(at: NSPoint(x: origin.x + 20, y: origin.y), velocity: 200)
        try check(pulses == 2, "Actual release emits once")
        view.finishDividerResize(commit: false)
        try check(commits.isEmpty && originals.map(\.frame) == originalFrames, "Canceled native gesture restores original frames without persistence")
        try check(view.beginDividerResize(at: origin), "New gesture owns fresh admission")
        view.updateDividerResize(at: NSPoint(x: origin.x - 40, y: origin.y), velocity: -200)
        view.finishDividerResize(commit: true); view.finishDividerResize(commit: true)
        try check(commits.count == 1 && abs(commits[0][0] + commits[0][1] - 0.6) < 0.000001 && commits[0][2] == 0.4, "Completion preserves pair share and commits once")
        view.configure(orientation: .vertical, factors: [0.3,0.3,0.4])
        let vertical = originals.map(\.frame), verticalOrigin = NSPoint(x: 100, y: originals[0].frame.maxY + 3)
        try check(view.beginDividerResize(at: verticalOrigin), "Vertical native divider admits")
        view.updateDividerResize(at: NSPoint(x: 100, y: verticalOrigin.y + 40), velocity: 0)
        view.updateDividerResize(at: NSPoint(x: 100, y: verticalOrigin.y + 6), velocity: -30)
        try check(abs(originals[0].frame.height - originals[1].frame.height) < 0.001 && originals[2].frame == vertical[2], "Vertical original pair uses same recovered state")
        view.configure(orientation: .horizontal, factors: [0.2,0.3,0.5])
        view.finishDividerResize(commit: true)
        try check(commits.count == 1 && view.isVertical, "Changed authoritative orientation cancels old native completion")
        let newOrigin = NSPoint(x: originals[0].frame.maxX + 3, y: 100)
        try check(view.beginDividerResize(at: newOrigin), "Current layout can start again")
        view.updateDividerResize(at: NSPoint(x: newOrigin.x + 40, y: 100), velocity: 1)
        view.removeFromSuperview(); view.finishDividerResize(commit: true)
        try check(commits.count == 1, "Detachment cancels the actual original gesture")
        let stacked = ParcSplitView(frame: NSRect(x: 0, y: 0, width: 1010, height: 710))
        win.contentView!.addSubview(stacked); defer { stacked.removeFromSuperview() }
        let stackedPanes = (0..<3).map { _ in NSView() }
        stackedPanes.forEach(stacked.addArrangedSubview)
        let shape = BrowserSplitStacks(slotSizes: [2, 1], slotFactors: [0.5, 0.5], stackFactors: [[0.4, 0.6], [1]])
        var stackedChanges: [SplitStackResize] = []
        stacked.prepareStackedResize = { { stackedChanges.append($0); return shape } }
        stacked.onSnapTransition = { pulses += 1 }
        stacked.configure(orientation: .horizontal, factors: shape.flattenedFactors, stacks: shape)
        let stackOrigin = NSPoint(x: 250, y: stackedPanes[0].frame.maxY + 3), before = pulses
        try check(stacked.beginDividerResize(at: stackOrigin), "A stack divider admits a pan")
        stacked.updateDividerResize(at: NSPoint(x: 250, y: stackOrigin.y + 100), velocity: 200)
        stacked.updateDividerResize(at: NSPoint(x: 250, y: stackOrigin.y + 65), velocity: 50)
        try check(pulses == before + 1 && abs(stackedPanes[0].frame.height - stackedPanes[1].frame.height) < 0.001
                  && stackedPanes[2].frame == NSRect(x: 510, y: 0, width: 500, height: 710),
                  "A stack divider snaps to the centre of its own column with one haptic")
        stacked.finishDividerResize(commit: true)
        guard case .divider(0, slot: 0, let share)? = stackedChanges.first else { throw NSError(domain: "stacked snap", code: 0) }
        try check(stackedChanges.count == 1 && abs(share - 0.5) < 0.000001, "The snapped stack divider commits an even pair once")
        print("PASS: \(count) native divider snap/admission/lifetime checks (no browser)")
    }
}
