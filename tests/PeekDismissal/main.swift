import Foundation

@main
@MainActor
struct PeekDismissalChecks {
    static var checks = 0
    static func expect(_ value: @autoclosure () -> Bool, _ message: String) {
        checks += 1
        precondition(value(), message)
    }
    static func pump(_ duration: TimeInterval) {
        let deadline = Date().addingTimeInterval(duration)
        while Date() < deadline {
            RunLoop.main.run(until: min(deadline, Date().addingTimeInterval(0.02)))
        }
    }
    static func waitUntil(_ predicate: () -> Bool, timeout: TimeInterval) {
        let deadline = Date().addingTimeInterval(timeout)
        while !predicate() && Date() < deadline { pump(0.02) }
        expect(predicate(), "real main-queue timer did not complete")
    }
    static func main() { exitOnFailure(runChecks) }
    static func runChecks() {
        typealias Owner = PeekDismissalConfirmation
        typealias Reason = Owner.Reason
        let contexts: [(Reason?, Bool)] = [
            (nil, false), (nil, true), (.escape, false), (.escape, true),
            (.mediaInput, false), (.mediaInput, true)
        ]
        let cases: [(Owner.Dismissal, [Reason?])] = [
            (.escape(prefersConfirmation: false), [nil, nil, nil, nil, nil, nil]),
            (.escape(prefersConfirmation: true), [.escape, .escape, nil, nil, nil, nil]),
            (.closeButton, [nil, .mediaInput, nil, nil, nil, nil]),
            (.exit, [nil, .mediaInput, nil, nil, nil, nil]),
            (.background, [nil, .mediaInput, nil, nil, .mediaInput, .mediaInput]),
            (.closeShortcut, [nil, .mediaInput, nil, nil, nil, nil]),
            (.swipe, [nil, .mediaInput, nil, nil, .mediaInput, .mediaInput])
        ]
        for (mechanism, expected) in cases {
            for (index, context) in contexts.enumerated() {
                expect(Owner.requiredReason(for: mechanism, awaiting: context.0, mediaInput: context.1) == expected[index],
                       "original dismissal reason matrix: \(mechanism), context \(index)")
            }
        }

        let prompt = PeekDismissalConfirmation()
        expect(prompt.reason == nil, "new owner has no confirmation")
        expect(prompt.attempts == 0, "new owner has no attempt")
        var rejectedExpiry = 0
        expect(prompt.request(.background, mediaInput: true) { rejectedExpiry += 1 } == .mediaInput,
               "background while capturing starts Hang up")
        expect(prompt.attempts == 1, "first request is attempt one")
        expect(prompt.request(.swipe, mediaInput: false) { rejectedExpiry += 1 } == .mediaInput,
               "swipe retains pending Hang up even if capture has just stopped")
        expect(prompt.attempts == 2, "repeated swipe increments the same pending confirmation")
        expect(prompt.request(.background, mediaInput: false) { rejectedExpiry += 1 } == .mediaInput,
               "repeated background does not become consent")
        expect(prompt.attempts == 3, "repeated background increments attempts")
        expect(prompt.request(.escape(prefersConfirmation: true), mediaInput: true) { rejectedExpiry += 1 } == nil,
               "explicit Escape confirms pending Hang up")
        expect(prompt.reason == nil && prompt.attempts == 0, "accepted dismissal clears pending state")
        expect(prompt.request(.escape(prefersConfirmation: true), mediaInput: true) { rejectedExpiry += 1 } == .escape,
               "fresh Escape uses its reason before inspecting capture")
        expect(prompt.attempts == 1, "fresh request does not inherit previous attempts")
        expect(prompt.request(.closeShortcut, mediaInput: true) { rejectedExpiry += 1 } == nil,
               "Close Tab confirms the pending Escape prompt")
        expect(prompt.request(.escape(prefersConfirmation: false), mediaInput: true) { rejectedExpiry += 1 } == nil,
               "native unconfirmed Escape decision can pass through without creating a timer")
        expect(PeekDismissalConfirmation.Reason.escape.duration == 1, "Escape reference duration")
        expect(PeekDismissalConfirmation.Reason.mediaInput.duration == 10, "media reference duration")
        var expirations = 0
        let first = ProcessInfo.processInfo.systemUptime
        prompt.arm(.escape) {
            expect(prompt.reason == nil, "expiry clears state before notifying the view")
            expect(prompt.attempts == 0, "failed confirmation resets attempts before notifying the view")
            expirations += 1
        }
        expect(prompt.reason == .escape, "prompt armed synchronously")
        pump(0.2)
        expect(expirations == 0, "prompt does not expire immediately")
        waitUntil({ expirations == 1 }, timeout: 5)
        expect(ProcessInfo.processInfo.systemUptime - first >= 0.99, "Escape expiry is not early")
        pump(0.1)
        expect(expirations == 1, "expiry is delivered once")
        expect(rejectedExpiry == 0, "consent cancels every replaced pending callback")

        var stale = 0
        prompt.arm(.escape) { stale += 1 }
        pump(0.2)
        let mediaStart = ProcessInfo.processInfo.systemUptime
        prompt.arm(.mediaInput) { expirations += 1 }
        pump(1.1)
        expect(stale == 0, "replaced work item is cancelled")
        expect(prompt.reason == .mediaInput, "media prompt survives the previous Escape deadline")
        expect(expirations == 1, "media expiry has not used the short duration")
        waitUntil({ expirations == 2 }, timeout: 15)
        expect(ProcessInfo.processInfo.systemUptime - mediaStart >= 9.99, "media expiry is not early")
        expect(prompt.reason == nil, "media expiry clears confirmation")

        prompt.arm(.escape) { stale += 1 }
        prompt.cancel()
        prompt.cancel()
        expect(prompt.reason == nil, "cancel is immediate and idempotent")
        expect(prompt.attempts == 0, "cancel also clears attempts")
        pump(1.1)
        expect(stale == 0, "cancelled owner gets no later expiry")

        prompt.arm(.escape) { prompt.arm(.mediaInput) { stale += 1 } }
        waitUntil({ prompt.reason == .mediaInput }, timeout: 5)
        expect(prompt.reason == .mediaInput, "new generation survives callback reentrancy")
        prompt.cancel()

        var retiring: PeekDismissalConfirmation? = PeekDismissalConfirmation()
        weak let released = retiring
        retiring?.arm(.escape) { stale += 1 }
        retiring = nil
        expect(released == nil, "scheduler does not retain retired owner")
        pump(1.1)
        expect(stale == 0, "teardown cancels callback")
        print("PASS: \(checks) Peek confirmation lifecycle assertions (no browser)")
    }
}
