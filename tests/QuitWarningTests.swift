import AppKit
import Combine

@main @MainActor
struct QuitWarningTests {
    static var count = 0
    static func check(_ value: @autoclosure () -> Bool, _ message: String) {
        count += 1; precondition(value(), message)
    }
    static func main() throws {
        _ = NSApplication.shared
        let suite = "parc-quit-warning-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = QuitWarningPreferences(defaults: defaults)
        check(!preferences.loadError && preferences.state.isEnabled, "Fresh policy uses recovered factory registration")
        try preferences.setEnabled(true)
        check(QuitWarningPreferences(defaults: defaults).state.isEnabled, "App-wide choice survives another settings owner")
        var publications = 0
        let subscription = preferences.$state.dropFirst().sink { _ in publications += 1 }
        try preferences.setEnabled(true)
        check(publications == 0, "No-op choice does not publish a policy change")
        let look = ApplicationQuitWarning(preferences: preferences)
        let root = look.window.contentView!
        check(look.window.frame.width == 450 && look.window.accessibilityLabel() == "Quit Parc?"
              && root.subviews.compactMap { ($0 as? NSTextField)?.stringValue } == ["Quit Parc?"],
              "the 450-point dialog titled Quit Parc? with no message")
        check(look.quit.primary && look.quit.hint && look.quit.keyEquivalent == "\r"
              && !look.cancelButton.primary && look.cancelButton.hint && look.cancelButton.keyEquivalent == "\u{1b}"
              && !look.suppress.primary && !look.suppress.hint && look.suppress.keyEquivalent.isEmpty,
              "Quit takes Return, Cancel Escape, and the auxiliary button has no hotkey hint")
        check(look.suppress.frame.maxX < look.cancelButton.frame.minX && look.cancelButton.frame.maxX < look.quit.frame.minX
              && look.suppress.frame.minX >= 28 && look.quit.frame.maxX <= 450 - 27.5,
              "The auxiliary button sits left of Cancel and Quit, all inside the 28-point margins")
        func drain() { RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05)) }
        let host = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600), styleMask: [.titled], backing: .buffered, defer: false)
        host.isReleasedWhenClosed = false
        defer { host.close() }
        let escape = ApplicationQuitWarning(preferences: preferences)
        var escaped: [Bool] = []
        escape.isCurrent = { true }; escape.onDecision = { escaped.append($0) }
        escape.present(in: host); drain()
        check(host.attachedSheet === escape.window, "The warning is a sheet on its browser window")
        escape.window.cancelOperation(nil); drain()
        check(escaped == [false] && escape.finished && host.attachedSheet == nil, "Escape cancels once and ends the sheet")
        let enter = ApplicationQuitWarning(preferences: preferences)
        var entered: [Bool] = []
        enter.isCurrent = { true }; enter.onDecision = { entered.append($0) }
        enter.present(in: host); drain()
        let keypad = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                                      windowNumber: enter.window.windowNumber, context: nil, characters: "\u{3}",
                                      charactersIgnoringModifiers: "\u{3}", isARepeat: false, keyCode: 76)!
        enter.window.keyDown(with: keypad); drain()
        check(entered == [true] && host.attachedSheet == nil && preferences.state.isEnabled,
              "Keypad Enter quits once, ends the sheet and keeps the warning on")
        func blocker() -> NSWindow {
            let sheet = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 100), styleMask: [.titled], backing: .buffered, defer: false)
            sheet.isReleasedWhenClosed = false
            host.beginSheet(sheet); drain()
            return sheet
        }
        let signIn = blocker()
        let queued = ApplicationQuitWarning(preferences: preferences)
        var queuedDecisions: [Bool] = []
        queued.isCurrent = { true }; queued.onDecision = { queuedDecisions.append($0) }
        queued.present(in: host); drain()
        check(queued.isWaiting && host.attachedSheet === signIn && queuedDecisions.isEmpty,
              "The warning waits behind the open sheet without deciding")
        host.endSheet(signIn); signIn.orderOut(nil); drain()
        check(!queued.isWaiting && host.attachedSheet === queued.window, "It begins once that sheet has ended")
        queued.quit.performClick(nil); drain()
        check(queuedDecisions == [true] && host.attachedSheet == nil, "Its Quit then decides once")
        let stillOpen = blocker()
        let retired = ApplicationQuitWarning(preferences: preferences)
        var retiredDecisions: [Bool] = []
        retired.isCurrent = { true }; retired.onDecision = { retiredDecisions.append($0) }
        retired.present(in: host); drain()
        retired.cancel()
        host.endSheet(stillOpen); stillOpen.orderOut(nil); drain()
        check(retiredDecisions == [false] && host.attachedSheet == nil && !retired.isWaiting,
              "A waiting warning that is cancelled never appears afterwards")
        var decisions: [Bool] = []
        let cancel = ApplicationQuitWarning(preferences: preferences)
        cancel.isCurrent = { true }; cancel.onDecision = { decisions.append($0) }
        cancel.cancelButton.performClick(nil); cancel.quit.performClick(nil); cancel.cancel()
        check(decisions == [false] && cancel.finished, "Cancel retires the decision once; retained controls cannot later quit")
        check(preferences.state.isEnabled && publications == 0, "Cancel preserves the preference")
        let quit = ApplicationQuitWarning(preferences: preferences)
        quit.isCurrent = { true }; quit.onDecision = { decisions.append($0) }
        quit.quit.performClick(nil); quit.suppress.performClick(nil)
        check(decisions == [false, true] && quit.finished, "Ordinary approval enters the caller continuation only once")
        check(preferences.state.isEnabled, "Ordinary Quit does not disable future warnings")
        let stale = ApplicationQuitWarning(preferences: preferences)
        stale.isCurrent = { false }; stale.onDecision = { decisions.append($0) }
        stale.suppress.performClick(nil)
        check(decisions.last == false && stale.finished, "A stale original owner cancels rather than quitting")
        check(preferences.state.isEnabled && publications == 0, "A stale suppression cannot change preferences")
        let suppress = ApplicationQuitWarning(preferences: preferences)
        suppress.isCurrent = { true }
        var policyAtContinuation: Bool?
        suppress.onDecision = { approved in
            decisions.append(approved)
            policyAtContinuation = QuitWarningPreferences(defaults: defaults).state.isEnabled
        }
        suppress.suppress.performClick(nil)
        check(decisions.last == true && policyAtContinuation == false, "Suppression persists before the existing native close-consent continuation")
        check(publications == 1 && !preferences.state.isEnabled, "One successful suppression publishes once")
        suppress.cancel()
        check(!QuitWarningPreferences(defaults: defaults).state.isEnabled, "Later cancellation cannot restore the warning implicitly")
        check(suppress.onDecision == nil && !suppress.quit.isEnabled && !suppress.suppress.isEnabled,
              "Finished decision releases its callback and disables retained controls")
        let key = "parc.quitWarning.v1"
        let future = Data(#"{"version":99,"isEnabled":false,"future":"preserve"}"#.utf8)
        defaults.set(future, forKey: key)
        let unknown = QuitWarningPreferences(defaults: defaults)
        check(unknown.loadError && unknown.state.isEnabled, "Unknown policy cannot silently bypass confirmation")
        do { try unknown.setEnabled(false); preconditionFailure("Future policy overwritten") }
        catch QuitWarningPreferences.Failure.unavailable {}
        check(defaults.data(forKey: key) == future, "Future policy bytes remain exact")
        let preserved = ApplicationQuitWarning(preferences: unknown)
        preserved.isCurrent = { true }; var allowed = false
        preserved.onDecision = { allowed = $0 }
        preserved.suppress.performClick(nil)
        check(!preserved.suppress.isEnabled && !preserved.finished, "Unreadable policy disables only permanent suppression")
        preserved.quit.performClick(nil)
        check(allowed && defaults.data(forKey: key) == future, "Ordinary Quit remains available without replacing unknown policy")
        defaults.set("invalid", forKey: key)
        let invalid = QuitWarningPreferences(defaults: defaults)
        check(invalid.loadError && invalid.state.isEnabled && defaults.string(forKey: key) == "invalid", "Wrong-typed persisted policy remains untouched")
        withExtendedLifetime(subscription) {}
        print("QuitWarning: \(count) assertions passed (no displayed window)")
    }
}
