import AppKit
import Foundation

@main
@MainActor
struct ThemeAppearanceTimerIdleTests {
    static var checks = 0
    static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        precondition(condition(), message)
        checks += 1
    }

    static func cueTimers(_ body: () -> Void) -> [FrameSource] {
        FrameSources.scheduled(during: body).filter { $0.timer?.timeInterval == 1 / 60 }
    }
    static func armed(_ timers: [FrameSource]) -> Bool { timers.contains(where: \.isLive) }

    static func main() { exitOnFailure(runChecks) }
    static func runChecks() throws {
        _ = NSApplication.shared
        FrameSources.install()
        Redraws.install()
        check(Bundle.main.url(forResource: "moon", withExtension: "json", subdirectory: "ThemeEditor") != nil
              && ThemeAppearanceAnimation(name: "moon") != nil, "the appearance animations load from the bundle's ThemeEditor resources")

        let moon = try preconditionAnimation(ThemeAppearanceAnimation(name: "moon"))
        let size = CGSize(width: 28, height: 28)
        let holdA = moon.presentationFingerprint(seconds: 82.0 / 60.0, size: size)
        let holdB = moon.presentationFingerprint(seconds: 88.0 / 60.0, size: size)
        check(holdA == holdB, "post-keyframe moon hold shares one presentation fingerprint")
        let mid = moon.presentationFingerprint(seconds: 30.0 / 60.0, size: size)
        check(mid != holdA, "active moon keyframes change the presentation fingerprint")
        let resized = moon.presentationFingerprint(seconds: 82.0 / 60.0, size: CGSize(width: 40, height: 40))
        check(resized != holdA, "bounds size remains part of the presentation fingerprint")

        let sun = try preconditionAnimation(ThemeAppearanceAnimation(name: "sun"))
        let sunA = sun.presentationFingerprint(seconds: 0.1, size: size)
        let sunB = sun.presentationFingerprint(seconds: 0.4, size: size)
        check(sunA != sunB, "sun rotation motion changes the presentation fingerprint")

        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        var clock: CFTimeInterval = 0
        let frame = 1.0 / 60
        var seen: [FrameSource] = []
        func tick(_ timers: [FrameSource]) {
            clock += frame
            timers.forEach { $0.fire() }
        }
        func record(_ body: () -> Void) -> [FrameSource] {
            let timers = cueTimers(body)
            seen += timers
            return timers
        }
        let button = ThemeAppearanceButton(appearance: .dark)
        button.now = { clock }
        button.setFrameSize(NSSize(width: 40, height: 40))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 40, height: 40),
                              styleMask: [.titled], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        window.contentView = button
        let beforeSelect = Redraws.count(button)
        let selectedAt = clock
        let cue = record { button.isSelected = true }
        func playbackSeconds() -> Double { clock - selectedAt }
        let afterSelect = Redraws.count(button)
        check(afterSelect > beforeSelect, "selecting dirties the first appearance frame")

        if reduceMotion {
            check(!armed(cue), "Reduce Motion never arms the 60 Hz appearance timer")
        } else {
            check(armed(cue), "selected visible cue arms the 60 Hz timer while motion is allowed")

            let artworkSize = button.bounds.insetBy(dx: 6, dy: 6).size
            let holdFingerprint = moon.presentationFingerprint(seconds: 82.0 / 60.0, size: artworkSize)
            func inHold() -> Bool { moon.presentationFingerprint(seconds: playbackSeconds(), size: artworkSize) == holdFingerprint }
            _ = record { while !inHold(), playbackSeconds() < 2.5, armed(cue) { tick(cue) } }
            check(inHold() && armed(cue),
                  "looping moon reaches a hold region with the timer still armed")
            let beforeHoldProbe = Redraws.count(button)
            var holdSkipTicks = 0
            _ = record {
                for _ in 0..<3 {
                    tick(cue)
                    guard inHold() else { break }
                    check(Redraws.count(button) == beforeHoldProbe,
                          "identical moon hold ticks skip needsDisplay")
                    holdSkipTicks += 1
                }
            }
            check(holdSkipTicks >= 3 && armed(cue) && seen.count == 1, "observed at least three in-hold ticks that skipped needsDisplay")
            check(beforeHoldProbe > afterSelect, "active keyframes still dirty while selected")
            let leaveBy = clock + 0.5
            _ = record { while Redraws.count(button) == beforeHoldProbe, clock < leaveBy, armed(cue) { tick(cue) } }
            check(Redraws.count(button) > beforeHoldProbe && !inHold() && armed(cue) && seen.count == 1,
                  "the armed timer resumes dirtying when the loop leaves the hold")

            _ = record {
                button.isHidden = true
                if armed(seen) { tick(seen) }
            }
            check(!armed(seen), "hidden appearance cue idle-stops the 60 Hz timer")
            let hiddenInvalidations = Redraws.count(button)
            let hiddenRearms = cueTimers { for _ in 0..<20 { tick(seen) } }
            check(Redraws.count(button) == hiddenInvalidations && !armed(seen) && hiddenRearms.isEmpty,
                  "post-hide idle stays stopped with no further dirties")

            let unhidden = cueTimers { button.isHidden = false }
            check(armed(unhidden), "unhiding a selected cue re-arms the 60 Hz timer")

            let nest = NSView(frame: NSRect(x: 0, y: 0, width: 40, height: 40))
            let nested = cueTimers {
                window.contentView = nest
                nest.addSubview(button)
                button.frame = nest.bounds
                button.isSelected = true
            }
            check(armed(nested) && !armed(unhidden), "nested selected cue arms the timer")
            nest.isHidden = true
            if armed(nested) { tick(nested) }
            check(!armed(nested), "ancestor-hidden appearance cue idle-stops the 60 Hz timer")
            let reshown = cueTimers { nest.isHidden = false }
            check(armed(reshown), "ancestor unhide re-arms a selected cue")

            button.isSelected = false
            check(!armed(cue + unhidden + nested + reshown), "unselected appearance cue idle-stops the 60 Hz timer")

            let driving = ThemeAppearanceButton(appearance: .light)
            driving.now = { clock }
            driving.setFrameSize(NSSize(width: 40, height: 40))
            let host = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 40, height: 40),
                                styleMask: [.titled], backing: .buffered, defer: true)
            host.isReleasedWhenClosed = false
            host.contentView = driving
            let drivingCue = cueTimers { driving.isSelected = true }
            check(armed(drivingCue), "fresh selected sun arms the timer")
            host.contentView = NSView(frame: .zero)
            check(!armed(drivingCue), "detached appearance cue idle-stops the 60 Hz timer")
            host.close()
        }

        window.close()
        buttonMotionTimers()
        padButtonsSkipDragRedraws()
        print("ThemeAppearanceTimerIdleTests: \(checks) checks passed")
    }

    static func offscreenWindow(_ view: NSView) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(origin: NSPoint(x: -10000, y: -10000), size: view.frame.size),
                              styleMask: [.borderless], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        window.contentView = view
        return window
    }

    static func buttonMotionTimers() {
        SystemOverrides.install(); SystemOverrides.reduceMotion = false
        defer { SystemOverrides.reduceMotion = nil }
        var clock: CFTimeInterval = 0
        func run(_ timers: [FrameSource], while condition: () -> Bool, for seconds: Double) {
            let end = clock + seconds
            while condition(), clock < end {
                clock += 1.0 / 60
                timers.forEach { $0.fire() }
            }
        }
        var seen: [FrameSource] = []
        func record(_ body: () -> Void) -> [FrameSource] {
            let timers = cueTimers(body)
            seen += timers
            return timers
        }
        let button = ThemeAppearanceButton(appearance: .light)
        button.now = { clock }
        button.setFrameSize(NSSize(width: 32, height: 32))
        let window = offscreenWindow(button)
        defer { window.close() }
        func event(_ type: NSEvent.EventType) -> NSEvent {
            NSEvent.enterExitEvent(with: type, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
                                   context: nil, eventNumber: 0, trackingNumber: 0, userData: nil)!
        }
        let hover = record { button.mouseEntered(with: event(.mouseEntered)) }
        check(armed(hover), "hover arms the button style's 60 Hz motion timer")
        _ = record { run(hover, while: { armed(hover) }, for: 0.5) }
        check(!armed(seen), "the motion timer stops once the hover settles")
        let settled = Redraws.count(button)
        let rearmed = cueTimers { run(seen, while: { true }, for: 0.1) }
        check(Redraws.count(button) == settled && rearmed.isEmpty, "a settled button makes no further redraws")
        let press = record { button.highlight(true) }
        check(armed(press), "a press arms the motion timer for its spring")
        _ = record { run(press, while: { armed(press) }, for: 1.5) }
        check(!armed(seen), "the motion timer stops once the press spring settles")
        _ = record { button.highlight(false) }
        _ = record { run(seen, while: { armed(seen) }, for: 1.5) }
        check(!armed(seen), "the motion timer stops once the release settles")

        let again = cueTimers { button.mouseEntered(with: event(.mouseEntered)) }
        check(armed(again), "a new hover arms the motion timer")
        SystemOverrides.reduceMotion = true
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
                                                   object: NSWorkspace.shared)
        check(!armed(again), "Reduce Motion switched on mid-animation settles the motion at once")
        let reduced = cueTimers { button.mouseExited(with: event(.mouseExited)) }
        check(!armed(reduced), "under Reduce Motion a hover change arms no timer")
    }

    static func padButtonsSkipDragRedraws() {
        var theme = SpaceTheme.singleColor(ThemeColor(red: 0.2, green: 0.6, blue: 0.9)!); theme.colorCount = 2
        let editor = SpaceThemeEditorView(theme: theme, performHapticFeedback: {})
        editor.layoutSubtreeIfNeeded()
        let window = offscreenWindow(editor)
        defer { window.contentView = nil; window.close() }
        func find(_ label: String, in view: NSView) -> NSView? {
            if view.accessibilityLabel() == label { return view }
            for sub in view.subviews { if let found = find(label, in: sub) { return found } }
            return nil
        }
        let pad = find("Theme color pad", in: editor)!, remove = find("Remove color", in: editor)!, add = find("Add color", in: editor)!
        func mouse(_ type: NSEvent.EventType, _ point: NSPoint) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: pad.convert(point, to: nil), modifierFlags: [], timestamp: 0,
                               windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 0)!
        }
        let start = NSPoint(x: pad.bounds.midX - 40, y: pad.bounds.midY)
        pad.mouseDown(with: mouse(.leftMouseDown, start))
        let removeRedraws = Redraws.count(remove), addRedraws = Redraws.count(add)
        for step in 1...10 { pad.mouseDragged(with: mouse(.leftMouseDragged, NSPoint(x: start.x + CGFloat(step) * 6, y: start.y))) }
        check(Redraws.count(remove) == removeRedraws && Redraws.count(add) == addRedraws,
              "− and + are not redrawn on each pad-drag frame")
        pad.mouseUp(with: mouse(.leftMouseUp, NSPoint(x: start.x + 60, y: start.y)))
    }

    static func preconditionAnimation(_ animation: ThemeAppearanceAnimation?) throws -> ThemeAppearanceAnimation {
        guard let animation else { preconditionFailure("ThemeEditor JSON must parse as ThemeAppearanceAnimation") }
        return animation
    }
}
