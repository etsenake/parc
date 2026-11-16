import AppKit
import Foundation

@main
@MainActor
struct ShortcutSmileyTimerIdleTests {
    static var checks = 0
    static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        precondition(condition(), message)
        checks += 1
    }

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
        let earlyB = artwork.presentationFingerprint(seconds: 0.5, size: size)
        check(earlyA == earlyB, "early hold shares one presentation fingerprint")
        let mid = artwork.presentationFingerprint(seconds: 1.5, size: size)
        check(mid != earlyA, "active keyframes change the presentation fingerprint")
        let late = artwork.presentationFingerprint(seconds: 4.2, size: size)
        let end = artwork.presentationFingerprint(seconds: artwork.duration, size: size)
        check(late == end, "late hold matches the end-frame presentation fingerprint")
        check(earlyA != end, "start pose fingerprint differs from the end-frame settle pose")
        let resized = artwork.presentationFingerprint(seconds: 0, size: CGSize(width: 64, height: 64))
        check(resized != earlyA, "bounds size remains part of the presentation fingerprint")

        var clock: CFTimeInterval = 0
        let frame = 1.0 / 60
        func advance(_ timers: [FrameSource], until time: CFTimeInterval) {
            while clock < time, armed(timers) {
                clock += frame
                timers.forEach { $0.fire() }
            }
        }
        let view = ShortcutSmileyView(frame: NSRect(x: 0, y: 0, width: 50, height: 50))
        view.now = { clock }
        let window = NSWindow(contentRect: view.frame, styleMask: [.titled], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let attached = cueTimers { window.contentView = view }
        check(armed(attached) != reduceMotion, "attaching arms the 60 Hz cue timer only while motion is allowed")
        advance(attached, until: 0.05)
        let beforeRestart = Redraws.count(view)
        let restartedAt = clock
        let cue = cueTimers {
            NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
        }
        let afterAttach = Redraws.count(view)
        check(afterAttach == beforeRestart + 1 && !armed(attached), "restarting playback dirties the first cue frame once")
        let drawn = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
        view.cacheDisplay(in: view.bounds, to: drawn)
        check((0..<drawn.pixelsHigh).contains { y in (0..<drawn.pixelsWide).contains { x in (drawn.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0 } },
              "the view draws its artwork from the bundle's Shortcuts resources")
        let holdStart = Redraws.count(view)

        if reduceMotion {
            check(!armed(cue), "Reduce Motion never arms the 60 Hz cue timer")
        } else {
            check(armed(cue), "visible cue arms the 60 Hz timer while motion is allowed")
            advance(cue, until: restartedAt + 0.55)
            check(armed(cue), "early hold keeps the timer armed until motion starts")
            check(Redraws.count(view) == holdStart,
                  "identical early-hold ticks skip needsDisplay")

            let replacements = cueTimers { advance(cue, until: restartedAt + artwork.duration + 1) }
            check(!armed(cue) && !armed(replacements) && clock - restartedAt < artwork.duration,
                  "returning to the resting pose idle-stops the cue timer before the composition ends")
            let settledInvalidations = Redraws.count(view)
            check(settledInvalidations > holdStart, "active keyframes still dirty while showing")
            let rearmed = cueTimers {
                for _ in 0..<30 {
                    clock += frame
                    (cue + replacements).forEach { $0.fire() }
                }
            }
            check(Redraws.count(view) == settledInvalidations && !armed(cue + replacements) && rearmed.isEmpty,
                  "post-settle idle stays stopped with no further dirties")

            let driving = ShortcutSmileyView(frame: NSRect(x: 0, y: 0, width: 50, height: 50))
            driving.now = { clock }
            let host = NSWindow(contentRect: driving.frame, styleMask: [.titled], backing: .buffered, defer: true)
            host.isReleasedWhenClosed = false
            let drivingCue = cueTimers { host.contentView = driving }
            check(armed(drivingCue), "fresh visible cue arms the timer")
            driving.isHidden = true
            clock += frame
            drivingCue.forEach { $0.fire() }
            check(!armed(drivingCue), "hidden cue idle-stops the 60 Hz timer on its next tick")
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
