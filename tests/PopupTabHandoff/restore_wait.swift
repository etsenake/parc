import AppKit

@main @MainActor struct RestoreWaitChecks {
    static var checks = 0
    static func check(_ value: @autoclosure () -> Bool, _ message: String) {
        precondition(value(), message); checks += 1
    }
    static func spin(_ seconds: TimeInterval) { RunLoop.main.run(until: Date().addingTimeInterval(seconds)) }
    static func main() { exitOnFailure(runChecks) }
    static func runChecks() {
        NSApplication.shared.setActivationPolicy(.prohibited)
        func window() -> NSWindow {
            NSWindow(contentRect: NSRect(x: 0, y: 0, width: 40, height: 40), styleMask: [.titled],
                     backing: .buffered, defer: true)
        }
        let main = window(), other = window()
        final class Request {}
        let waits = WindowRestoreWaits(timeout: 0.5)
        var resumed: [String] = []
        var request: Request? = Request()
        weak let held = request
        waits.wait(for: main) { [request] in _ = request; resumed.append("address") }
        request = nil
        waits.wait(for: main) { resumed.append("tab") }
        check(waits.count == 2 && resumed.isEmpty, "A second request while the window restores keeps the first one waiting")
        NotificationCenter.default.post(name: NSWindow.didDeminiaturizeNotification, object: main)
        check(resumed.isEmpty, "Delivery never runs inside AppKit's restore notification")
        spin(0.05)
        check(resumed == ["address", "tab"] && waits.count == 0, "One restore delivers every waiting request, in order")
        NotificationCenter.default.post(name: NSWindow.didDeminiaturizeNotification, object: main)
        spin(0.6)
        check(resumed.count == 2, "A finished wait never resumes again, from a later restore or its timeout")
        check(held == nil, "A finished wait leaves no observer holding its request")
        waits.wait(for: main) { resumed.append("timed out") }
        NotificationCenter.default.post(name: NSWindow.didDeminiaturizeNotification, object: other)
        spin(0.02)
        check(resumed.count == 2 && waits.count == 1, "Another window's restore does not count as this window's")
        spin(0.6)
        check(resumed.last == "timed out" && waits.count == 0, "A window that never restores resumes at the timeout")
        waits.wait(for: main) { resumed.append("closed") }
        NotificationCenter.default.post(name: NSWindow.willCloseNotification, object: main)
        spin(0.05)
        check(resumed.last == "closed" && resumed.count == 4, "A window closing while it restores resumes the wait")
        spin(0.6)
        check(resumed.count == 4, "The closed wait's timeout stays quiet")
        print("WindowRestoreWaits: \(checks) assertions passed")
    }
}
