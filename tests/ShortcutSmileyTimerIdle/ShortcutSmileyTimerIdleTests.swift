import AppKit
import Foundation

/// P1: ShortcutSmileyView 60 Hz timer idle-stops when hidden/settled and skips
/// `needsDisplay` when the presentation fingerprint is unchanged. Active
/// keyframe motion still dirties; shortcut binding behavior is untouched.
@main
@MainActor
struct ShortcutSmileyTimerIdleTests {
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
        guard let jsonURL = Bundle.main.url(forResource: "smiley", withExtension: "json", subdirectory: "Shortcuts") else {
            preconditionFailure("smiley.json must be in the bundle's Shortcuts resources")
        }
        let data = try Data(contentsOf: jsonURL)
        let artwork = try preconditionArtwork(ShortcutSmileyArtwork(data: data))

        let size = CGSize(width: 50, height: 50)
        let earlyA = artwork.presentationFingerprint(seconds: 0, size: size)
        let earlyB = artwork.presentationFingerprint(seconds: 0.5, size: size) // frame 15 < first key 27
        check(earlyA == earlyB, "early hold shares one presentation fingerprint")
        let mid = artwork.presentationFingerprint(seconds: 1.5, size: size) // frame 45, mid blink/smile
        check(mid != earlyA, "active keyframes change the presentation fingerprint")
        let late = artwork.presentationFingerprint(seconds: 4.2, size: size) // frame 126 > last key 119
        let end = artwork.presentationFingerprint(seconds: artwork.duration, size: size)
        check(late == end, "late hold matches the end-frame presentation fingerprint")
        // This artwork's final pose is a near-rest (p ends at 50.135/70.022); start≠end.
        check(earlyA != end, "start pose fingerprint differs from the end-frame settle pose")
        let resized = artwork.presentationFingerprint(seconds: 0, size: CGSize(width: 64, height: 64))
        check(resized != earlyA, "bounds size remains part of the presentation fingerprint")

        let view = ShortcutSmileyView(frame: NSRect(x: 0, y: 0, width: 50, height: 50))
        let window = NSWindow(contentRect: view.frame, styleMask: [.titled], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        // Attaching arms playback (unless Reduce Motion).
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let attached = cueTimers { window.contentView = view }
        check(armed(attached) != reduceMotion, "attaching arms the 60 Hz cue timer only while motion is allowed")
        // AppKit's own deferred attach invalidations land on the next pass.
        RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.05))
        // The accessibility-options notification restarts playback from the first frame.
        let beforeRestart = Redraws.count(view)
        let cue = cueTimers {
            NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
        }
        let afterAttach = Redraws.count(view)
        check(afterAttach == beforeRestart + 1 && !armed(attached), "restarting playback dirties the first cue frame once")
        let drawn = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
        view.cacheDisplay(in: view.bounds, to: drawn)
        check((0..<drawn.pixelsHigh).contains { y in (0..<drawn.pixelsWide).contains { x in (drawn.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0 } },
              "the view draws its artwork from the bundle's Shortcuts resources")

        if reduceMotion {
            check(!armed(cue), "Reduce Motion never arms the 60 Hz cue timer")
        } else {
            check(armed(cue), "visible cue arms the 60 Hz timer while motion is allowed")
            // Spin through the early hold (~0.9s of identical resting frames).
            let earlyDeadline = Date(timeIntervalSinceNow: 0.55)
            while Date() < earlyDeadline {
                RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.02))
            }
            check(armed(cue), "early hold keeps the timer armed until motion starts")
            check(Redraws.count(view) == afterAttach,
                  "identical early-hold ticks skip needsDisplay")

            let deadline = Date(timeIntervalSinceNow: 5.5)
            while armed(cue), Date() < deadline {
                RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.05))
            }
            check(!armed(cue), "returning to the resting pose idle-stops the cue timer")
            let settledInvalidations = Redraws.count(view)
            check(settledInvalidations > afterAttach, "active keyframes still dirty while showing")
            for _ in 0..<30 {
                RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.02))
            }
            check(Redraws.count(view) == settledInvalidations && !armed(cue),
                  "post-settle idle stays stopped with no further dirties")

            // Hidden while driving: re-attach a fresh view and hide mid-play.
            let driving = ShortcutSmileyView(frame: NSRect(x: 0, y: 0, width: 50, height: 50))
            let host = NSWindow(contentRect: driving.frame, styleMask: [.titled], backing: .buffered, defer: true)
            host.isReleasedWhenClosed = false
            let drivingCue = cueTimers { host.contentView = driving }
            check(armed(drivingCue), "fresh visible cue arms the timer")
            driving.isHidden = true
            // Next tick observes isHidden and idle-stops.
            let hideDeadline = Date(timeIntervalSinceNow: 0.25)
            while armed(drivingCue), Date() < hideDeadline {
                RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.02))
            }
            check(!armed(drivingCue), "hidden cue idle-stops the 60 Hz timer")
            host.close()
        }

        window.close()
        print("ShortcutSmileyTimerIdleTests: \(checks) checks passed")
    }

    static func preconditionArtwork(_ artwork: ShortcutSmileyArtwork?) throws -> ShortcutSmileyArtwork {
        guard let artwork else { preconditionFailure("smiley.json must parse as ShortcutSmileyArtwork") }
        return artwork
    }
}
