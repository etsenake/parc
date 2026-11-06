import Foundation
import Combine

try MainActor.assumeIsolated {
var checks = 0
func check(_ value: @autoclosure () -> Bool, _ reason: String) {
    checks += 1; precondition(value(), reason)
}
let suite = "Parc.SharedQuotes.Checks.\(UUID().uuidString)"
let defaults = UserDefaults(suiteName: suite)!
defer { defaults.removePersistentDomain(forName: suite) }
let key = "parc.sharedQuotes.v1"
let preferences = SharedQuotePreferences(defaults: defaults)
check(preferences.state.isEnabled && !preferences.loadError, "absent fallback")
check(defaults.object(forKey: key) == nil, "read does not create storage")
try preferences.setEnabled(false)
check(!SharedQuotePreferences(defaults: defaults).state.isEnabled, "disabled persistence")
let saved = defaults.data(forKey: key)!
try preferences.setEnabled(false)
check(defaults.data(forKey: key) == saved, "idempotent commit")
try preferences.setEnabled(true)
check(SharedQuotePreferences(defaults: defaults).state.isEnabled, "enabled persistence")
for malformed: Any in ["bad", Data("{\"version\":99,\"isEnabled\":false}".utf8), Data("{}".utf8)] {
    defaults.set(malformed, forKey: key)
    let before = defaults.object(forKey: key) as! NSObject
    let unreadable = SharedQuotePreferences(defaults: defaults)
    check(unreadable.loadError, "unreadable/future record reported")
    do { try unreadable.setEnabled(false); fatalError("overwrote preserved preferences") }
    catch { check((defaults.object(forKey: key) as! NSObject).isEqual(before), "preserve unreadable bytes") }
}
final class Token { var valid = true }
var pending: [@MainActor @Sendable () -> Void] = []
var displayed: Token?
let session = SharedQuoteSession<Token>(valid: { $0.valid }, schedule: { pending.append($0) }, display: { displayed = $0 })
@MainActor func drain() { let work = pending; pending.removeAll(); for item in work { item() } }
let a = Token(), b = Token()
session.setEnabled(true)
session.receive(a, reset: false); drain()
check(displayed == nil, "unsolicited/keyboard-only selection before tracking is not shown")
session.pointer(down: true, tracksSelection: false); session.receive(a, reset: false)
session.pointer(down: false, tracksSelection: false); drain()
check(displayed == nil, "single click does not invent selection tracking")
session.pointer(down: true, tracksSelection: true); session.receive(a, reset: false); drain()
check(displayed == nil && !session.canPerform(a), "dragging holds publication")
session.pointer(down: false, tracksSelection: false)
check(displayed == nil && pending.count == 1 && !session.canPerform(a), "release schedules debounce without accepting an undisplayed action")
drain(); check(displayed === a && session.canPerform(a), "released current token is offered")
session.receive(b, reset: false)
check(displayed == nil && !session.canPerform(a), "old selection revoked immediately")
a.valid = false; drain(); check(displayed === b, "new selection wins")
session.receive(a, reset: false); drain()
check(displayed == nil, "native-invalid token never published")
session.receive(b, reset: false); session.setEnabled(false); drain()
check(displayed == nil && !session.canPerform(b), "disable cancels queued output")
session.setEnabled(true); drain()
check(displayed === b, "reenable can display retained valid selection")
session.receive(a, reset: false); session.receive(b, reset: false); session.reset(); drain()
check(displayed == nil && !session.canPerform(b), "owner reset cancels every queued revision")
session.receive(b, reset: false); drain()
check(displayed == nil, "new owner needs its own selection gesture")
session.pointer(down: true, tracksSelection: true); session.receive(b, reset: false)
session.pointer(down: false, tracksSelection: false); b.valid = false; drain()
check(displayed == nil, "document/selection invalidation during delay is respected")
b.valid = true
session.receive(b, reset: false); session.receive(nil, reset: true); drain()
check(displayed == nil && session.selection == nil, "native lifetime reset clears retained selection")
session.receive(b, reset: false); drain()
check(displayed == nil, "native reset also clears tracked gesture")
session.pointer(down: true, tracksSelection: true); session.receive(a, reset: false)
session.receive(nil, reset: false); session.receive(b, reset: false)
session.pointer(down: false, tracksSelection: false); drain()
check(displayed === b, "coalesced selection invalidation preserves active drag tracking")
print("\(checks) Shared Quote preference and lifecycle assertions passed")
}
