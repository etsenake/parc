import AppKit
import Testing
@testable import Parc

@MainActor private final class Timers {
    var scheduled: [(delay: TimeInterval, work: @MainActor () -> Void)] = []
    var consumed = 0

    func schedule(_ delay: TimeInterval, _ work: @escaping @MainActor () -> Void) { scheduled.append((delay, work)) }

    func runDeferred() {
        while consumed < scheduled.count {
            let item = scheduled[consumed]
            consumed += 1
            if item.delay == 0 { item.work() }
        }
    }

    func runTimeouts() {
        for item in scheduled where item.delay > 0 { item.work() }
    }
}

@MainActor private final class Scene {
    let timers = Timers()
    let main = Scene.window(), other = Scene.window()
    var resumed: [String] = []
    lazy var waits = WindowRestoreWaits(timeout: 0.5) { [timers] in timers.schedule($0, $1) }

    static func window() -> NSWindow {
        _ = NSApplication.shared
        return NSWindow(contentRect: NSRect(x: 0, y: 0, width: 40, height: 40), styleMask: [.titled], backing: .buffered, defer: true)
    }

    func restore(_ window: NSWindow? = nil) {
        NotificationCenter.default.post(name: NSWindow.didDeminiaturizeNotification, object: window ?? main)
    }
}

struct WindowRestoreWaitsTests {
    @MainActor @Test func aSecondRequestWhileTheWindowRestoresKeepsTheFirstOneWaiting() {
        let s = Scene()
        s.waits.wait(for: s.main) { s.resumed.append("address") }
        s.waits.wait(for: s.main) { s.resumed.append("tab") }
        #expect(s.waits.count == 2)
        #expect(s.resumed.isEmpty)
    }

    @MainActor @Test func deliveryNeverRunsInsideAppKitsRestoreNotification() {
        let s = Scene()
        s.waits.wait(for: s.main) { s.resumed.append("address") }
        s.restore()
        #expect(s.resumed.isEmpty)
        #expect(s.timers.scheduled.map(\.delay) == [0.5, 0])
    }

    @MainActor @Test func oneRestoreDeliversEveryWaitingRequestInOrder() {
        let s = Scene()
        s.waits.wait(for: s.main) { s.resumed.append("address") }
        s.waits.wait(for: s.main) { s.resumed.append("tab") }
        s.restore()
        s.timers.runDeferred()
        #expect(s.resumed == ["address", "tab"])
        #expect(s.waits.count == 0)
    }

    @MainActor @Test func aFinishedWaitNeverResumesAgainFromALaterRestoreOrItsTimeout() {
        let s = Scene()
        s.waits.wait(for: s.main) { s.resumed.append("address") }
        s.restore()
        s.timers.runDeferred()
        s.restore()
        s.timers.runDeferred()
        s.timers.runTimeouts()
        #expect(s.resumed == ["address"])
    }

    @MainActor @Test func aFinishedWaitLeavesNoObserverHoldingItsRequest() {
        final class Request {}
        let s = Scene()
        var request: Request? = Request()
        weak let held = request
        s.waits.wait(for: s.main) { [request] in _ = request; s.resumed.append("address") }
        request = nil
        s.restore()
        s.timers.runDeferred()
        s.timers.scheduled.removeAll()
        #expect(held == nil)
    }

    @MainActor @Test func anotherWindowsRestoreDoesNotCountAsThisWindows() {
        let s = Scene()
        s.waits.wait(for: s.main) { s.resumed.append("timed out") }
        s.restore(s.other)
        #expect(s.timers.scheduled.map(\.delay) == [0.5])
        s.timers.runDeferred()
        #expect(s.resumed.isEmpty)
        #expect(s.waits.count == 1)
    }

    @MainActor @Test func aWindowThatNeverRestoresResumesAtTheTimeout() {
        let s = Scene()
        s.waits.wait(for: s.main) { s.resumed.append("timed out") }
        s.timers.runTimeouts()
        #expect(s.resumed == ["timed out"])
        #expect(s.waits.count == 0)
    }

    @MainActor @Test func theTimeoutIsTheOneTheWaitsWereBuiltWith() {
        let s = Scene()
        s.waits.wait(for: s.main) {}
        #expect(s.timers.scheduled.map(\.delay) == [0.5])
    }

    @MainActor @Test func aWindowClosingWhileItRestoresResumesTheWait() {
        let s = Scene()
        s.waits.wait(for: s.main) { s.resumed.append("closed") }
        NotificationCenter.default.post(name: NSWindow.willCloseNotification, object: s.main)
        s.timers.runDeferred()
        #expect(s.resumed == ["closed"])
    }

    @MainActor @Test func theClosedWaitsTimeoutStaysQuiet() {
        let s = Scene()
        s.waits.wait(for: s.main) { s.resumed.append("closed") }
        NotificationCenter.default.post(name: NSWindow.willCloseNotification, object: s.main)
        s.timers.runDeferred()
        s.timers.runTimeouts()
        #expect(s.resumed == ["closed"])
    }
}
