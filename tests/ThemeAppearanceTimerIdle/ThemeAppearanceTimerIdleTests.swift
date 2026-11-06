import AppKit
import Foundation

/// P2: ThemeAppearanceButton 60 Hz timer idle-stops when hidden/detached/unselected
/// and skips `needsDisplay` when the presentation fingerprint is unchanged.
/// Active keyframe motion still dirties; appearance selection behavior is untouched.
@main
@MainActor
struct ThemeAppearanceTimerIdleTests {
    static var checks = 0
    static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        precondition(condition(), message)
        checks += 1
    }

    /// The cue's 60 Hz timers scheduled while `body` runs.
    static func cueTimers(_ body: () -> Void) -> [FrameSource] {
        FrameSources.scheduled(during: body).filter { $0.timer?.timeInterval == 1 / 60 }
    }
    static func armed(_ timers: [FrameSource]) -> Bool { timers.contains(where: \.isLive) }

    static func main() throws {
        _ = NSApplication.shared
        FrameSources.install()
        Redraws.install()
        check(Bundle.main.url(forResource: "moon", withExtension: "json", subdirectory: "ThemeEditor") != nil
              && ThemeAppearanceAnimation(name: "moon") != nil, "the appearance animations load from the bundle's ThemeEditor resources")

        let moon = try preconditionAnimation(ThemeAppearanceAnimation(name: "moon"))
        let size = CGSize(width: 28, height: 28)
        // Moon holds after the last star key (t=82) until loop wrap at op=90.
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
        let button = ThemeAppearanceButton(appearance: .dark)
        button.setFrameSize(NSSize(width: 40, height: 40))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 40, height: 40),
                              styleMask: [.titled], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        window.contentView = button
        let beforeSelect = Redraws.count(button)
        // A first selection starts playback at zero; this clock starts microseconds earlier, so it reads slightly ahead.
        let selectedAt = CACurrentMediaTime()
        let cue = cueTimers { button.isSelected = true }
        func playbackSeconds() -> Double { CACurrentMediaTime() - selectedAt }
        let afterSelect = Redraws.count(button)
        check(afterSelect > beforeSelect, "selecting dirties the first appearance frame")

        if reduceMotion {
            check(!armed(cue), "Reduce Motion never arms the 60 Hz appearance timer")
        } else {
            check(armed(cue), "selected visible cue arms the 60 Hz timer while motion is allowed")

            // Enter the moon post-key hold by fingerprint (not wall-clock), then
            // assert several ticks skip needsDisplay while the loop timer stays armed.
            let artworkSize = button.bounds.insetBy(dx: 6, dy: 6).size
            let holdFingerprint = moon.presentationFingerprint(seconds: 82.0 / 60.0, size: artworkSize)
            let enterHold = Date(timeIntervalSinceNow: 2.5)
            var inHold = false
            while Date() < enterHold {
                RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.01))
                let current = moon.presentationFingerprint(seconds: playbackSeconds(), size: artworkSize)
                if current == holdFingerprint {
                    inHold = true
                    break
                }
            }
            check(inHold && armed(cue),
                  "looping moon reaches a hold region with the timer still armed")
            // Allow the first in-hold tick to latch lastDisplayFingerprint (may dirty once).
            let catchUp = Date(timeIntervalSinceNow: 0.05)
            while Date() < catchUp {
                RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.01))
                if moon.presentationFingerprint(seconds: playbackSeconds(), size: artworkSize) != holdFingerprint {
                    inHold = false
                    break
                }
            }
            check(inHold && armed(cue),
                  "still in moon hold after fingerprint latch")
            let beforeHoldProbe = Redraws.count(button)
            var holdSkipTicks = 0
            let probeDeadline = Date(timeIntervalSinceNow: 0.2)
            while Date() < probeDeadline {
                RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.01))
                let current = moon.presentationFingerprint(seconds: playbackSeconds(), size: artworkSize)
                if current != holdFingerprint { break }
                check(Redraws.count(button) == beforeHoldProbe,
                      "identical moon hold ticks skip needsDisplay")
                holdSkipTicks += 1
                if holdSkipTicks >= 3 { break }
            }
            check(holdSkipTicks >= 3, "observed at least three in-hold ticks that skipped needsDisplay")
            check(beforeHoldProbe > afterSelect, "active keyframes still dirty while selected")
            // The loop wraps out of the hold on the same timer.
            let wrapDeadline = Date(timeIntervalSinceNow: 0.5)
            while Redraws.count(button) == beforeHoldProbe, Date() < wrapDeadline {
                RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.01))
            }
            check(Redraws.count(button) > beforeHoldProbe && armed(cue),
                  "the armed timer resumes dirtying when the loop leaves the hold")

            // Hidden while driving idle-stops.
            button.isHidden = true
            let hideDeadline = Date(timeIntervalSinceNow: 0.25)
            while armed(cue), Date() < hideDeadline {
                RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.02))
            }
            check(!armed(cue), "hidden appearance cue idle-stops the 60 Hz timer")
            let hiddenInvalidations = Redraws.count(button)
            for _ in 0..<20 {
                RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.02))
            }
            check(Redraws.count(button) == hiddenInvalidations && !armed(cue),
                  "post-hide idle stays stopped with no further dirties")

            // Unhide re-arms while still selected.
            let unhidden = cueTimers { button.isHidden = false }
            check(armed(unhidden), "unhiding a selected cue re-arms the 60 Hz timer")

            // Ancestor hide must idle-stop via isHiddenOrHasHiddenAncestor.
            let nest = NSView(frame: NSRect(x: 0, y: 0, width: 40, height: 40))
            let nested = cueTimers {
                window.contentView = nest
                nest.addSubview(button)
                button.frame = nest.bounds
                button.isSelected = true
            }
            check(armed(nested) && !armed(unhidden), "nested selected cue arms the timer")
            nest.isHidden = true
            let ancestorDeadline = Date(timeIntervalSinceNow: 0.25)
            while armed(nested), Date() < ancestorDeadline {
                RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.02))
            }
            check(!armed(nested), "ancestor-hidden appearance cue idle-stops the 60 Hz timer")
            let reshown = cueTimers { nest.isHidden = false }
            check(armed(reshown), "ancestor unhide re-arms a selected cue")

            // Deselect settles (freezes) and idle-stops.
            button.isSelected = false
            check(!armed(cue + unhidden + nested + reshown), "unselected appearance cue idle-stops the 60 Hz timer")

            // Detach idle-stops a freshly selected driver.
            let driving = ThemeAppearanceButton(appearance: .light)
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
    static func run(while condition: () -> Bool, for seconds: Double) {
        let deadline = Date(timeIntervalSinceNow: seconds)
        while condition(), Date() < deadline { RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.01)) }
    }

    /// The button style's motion timer runs only while hover or press is moving.
    static func buttonMotionTimers() {
        SystemOverrides.install(); SystemOverrides.reduceMotion = false
        defer { SystemOverrides.reduceMotion = nil }
        let button = ThemeAppearanceButton(appearance: .light)
        button.setFrameSize(NSSize(width: 32, height: 32))
        let window = offscreenWindow(button)
        defer { window.close() }
        func event(_ type: NSEvent.EventType) -> NSEvent {
            NSEvent.enterExitEvent(with: type, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
                                   context: nil, eventNumber: 0, trackingNumber: 0, userData: nil)!
        }
        let hover = cueTimers { button.mouseEntered(with: event(.mouseEntered)) }
        check(armed(hover), "hover arms the button style's 60 Hz motion timer")
        run(while: { armed(hover) }, for: 0.5)
        check(!armed(hover), "the motion timer stops once the hover settles")
        let settled = Redraws.count(button)
        run(while: { true }, for: 0.1)
        check(Redraws.count(button) == settled, "a settled button makes no further redraws")
        let press = cueTimers { button.highlight(true) }
        check(armed(press), "a press arms the motion timer for its spring")
        run(while: { armed(press) }, for: 1.5)
        check(!armed(press), "the motion timer stops once the press spring settles")
        let release = cueTimers { button.highlight(false) }
        run(while: { armed(release) }, for: 1.5)
        check(!armed(release), "the motion timer stops once the release settles")

        let again = cueTimers { button.mouseEntered(with: event(.mouseEntered)) }
        check(armed(again), "a new hover arms the motion timer")
        SystemOverrides.reduceMotion = true
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
                                                   object: NSWorkspace.shared)
        RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.005))
        check(!armed(again), "Reduce Motion switched on mid-animation settles the motion at once")
        let reduced = cueTimers { button.mouseExited(with: event(.mouseExited)) }
        check(!armed(reduced), "under Reduce Motion a hover change arms no timer")
    }

    /// A pad drag refreshes the editor every frame; − and + redraw only when
    /// their own state changes.
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
