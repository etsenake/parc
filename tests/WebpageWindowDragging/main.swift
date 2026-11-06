import AppKit
import Combine

try MainActor.assumeIsolated {
var checks = 0
func check(_ value: @autoclosure () -> Bool, _ reason: String) {
    checks += 1; precondition(value(), reason)
}
let suite = "Parc.WindowDragging.Checks.\(UUID().uuidString)"
let defaults = UserDefaults(suiteName: suite)!
defer { defaults.removePersistentDomain(forName: suite) }
let key = "parc.webpageWindowDragging.v1"
let preferences = WebpageWindowDraggingPreferences(defaults: defaults)
check(preferences.state.isEnabled && !preferences.loadError, "explicit absent fallback")
check(defaults.object(forKey: key) == nil, "reading does not materialize preference")
try preferences.setEnabled(false)
let saved = defaults.data(forKey: key)!
check(!WebpageWindowDraggingPreferences(defaults: defaults).state.isEnabled, "persist disabled")
try preferences.setEnabled(false)
check(defaults.data(forKey: key) == saved, "idempotent write")
try preferences.setEnabled(true)
check(WebpageWindowDraggingPreferences(defaults: defaults).state.isEnabled, "persist enabled")
for malformed: Any in ["bad", Data("{\"version\":99,\"isEnabled\":false}".utf8), Data("{}".utf8)] {
    defaults.set(malformed, forKey: key)
    let before = defaults.object(forKey: key) as! NSObject
    let unreadable = WebpageWindowDraggingPreferences(defaults: defaults)
    check(unreadable.loadError, "unreadable record reported")
    do { try unreadable.setEnabled(false); fatalError("overwrote unreadable data") }
    catch { check((defaults.object(forKey: key) as! NSObject).isEqual(before), "preserve malformed/future bytes") }
}
let rect = NSRect(x: 0, y: 0, width: 900, height: 600)
check(WebpageWindowDragState.region(in: rect, topStripHeight: 0) == NSRect(x: 0, y: 0, width: 886, height: 60), "plain page geometry")
check(WebpageWindowDragState.region(in: rect, topStripHeight: 40) == NSRect(x: 0, y: 40, width: 886, height: 20), "toolbar reduces band")
check(WebpageWindowDragState.region(in: rect, topStripHeight: 31).height == 29, "split header is excluded")
check(WebpageWindowDragState.region(in: rect, topStripHeight: 64).isEmpty, "strip consumes drag area")
check(WebpageWindowDragState.region(in: NSRect(x: 0, y: 0, width: 8, height: 12), topStripHeight: 0).isEmpty, "tiny view cannot create negative region")
check(WebpageWindowDragState.permitsModifiers([]), "plain input")
check(WebpageWindowDragState.permitsModifiers(.option), "Option input")
for flags: NSEvent.ModifierFlags in [.command, .shift, .control, .capsLock, [.option, .shift]] {
    check(!WebpageWindowDragState.permitsModifiers(flags), "other modifiers preserve webpage interaction")
}
var state = WebpageWindowDragState()
check(!state.consume(.leftMouseUp, deltaX: 0, deltaY: 0), "inactive up passes")
state.begin(eligible: true)
check(state.phase == .began && !state.consume(.leftMouseDragged, deltaX: 5, deltaY: 0), "uncommitted drag is not swallowed")
state.commit()
check(state.consume(.leftMouseDragged, deltaX: 0.6, deltaY: 0.8), "committed drag is consumed")
check(!state.consume(.leftMouseUp, deltaX: 0, deltaY: 0), "exactly one point permits up")
check(state.phase == .inactive, "up completes sequence")
state.commit()
check(state.consume(.leftMouseDragged, deltaX: -1, deltaY: 0), "negative delta")
check(state.consume(.leftMouseDragged, deltaX: 1, deltaY: 0), "reversal accumulates absolute movement")
check(state.consume(.leftMouseUp, deltaX: 0, deltaY: 0), "movement over one point consumes up")
state.commit()
check(!state.consume(.rightMouseUp, deltaX: 40, deltaY: 0), "other buttons unaffected")
state.cancel();check(state.phase == .inactive, "cancel terminates accounting")

// A real hidden AppKit view/window hierarchy; no Apple Events, browser object,
// NSApplication input dispatch or AppKit drag loop is used: the check supplies
// NSApplication's current event and NSCursor's cursor, and takes
// NSWindow.performDrag itself. Chromium's source-owned per-event hit test is
// exercised by explicitly asking this tree.
_ = NSApplication.shared
DispatchOverrides.install()
let window = NSWindow(contentRect: rect, styleMask: [], backing: .buffered, defer: false)
let otherWindow = NSWindow(contentRect: rect, styleMask: [], backing: .buffered, defer: false)
final class Flipped: NSView { override var isFlipped: Bool { true } }
let root = Flipped(frame: rect); window.contentView = root
let page = NSView(frame: rect); root.addSubview(page)
var event: NSEvent? { didSet { DispatchOverrides.currentEvent = event } }
var arrow = true { didSet { DispatchOverrides.cursor = arrow ? .arrow : .iBeam } }
DispatchOverrides.cursor = .arrow
var eligible = true, current = true
var currentProbes = 0, eligibilityProbes = 0
var drags: [NSEvent] = []
var duringDrag: (() -> Void)?
DispatchOverrides.windowDrag = { target, event in
    check(target === window, "original physical window")
    drags.append(event); duringDrag?()
}
let grabber = WebpageWindowGrabber()
root.addSubview(grabber); grabber.frame = WebpageWindowDragState.region(in: rect, topStripHeight: 0)
let owner = NSObject()
@MainActor func configure(_ object: NSObject? = owner, _ revision: UInt = 1) {
    grabber.configure(owner: object, revision: revision, isCurrent: {
        currentProbes += 1; return current
    }, eligibility: { _ in
        eligibilityProbes += 1; return eligible
    })
}
func make(_ type: NSEvent.EventType, _ target: NSWindow = window) -> NSEvent {
    NSEvent.mouseEvent(with: type, location: NSPoint(x: 30, y: 570), modifierFlags: [], timestamp: 1,
                       windowNumber: target.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 0)!
}
func hit(_ type: NSEvent.EventType) -> NSView? { event = make(type); return root.hitTest(NSPoint(x: 30, y: 570)) }
configure()
check(hit(.leftMouseDown) === page, "original down passes into page")
check(grabber.drag.phase == .began, "eligible down arms original owner")
check(hit(.leftMouseDragged) === grabber, "native re-hit-test commits dragging")
check(drags.count == 1 && drags.last === event, "same NSEvent, no synthetic replay")
check(hit(.leftMouseDragged) === grabber && drags.count == 1, "committed hit does not start a second drag")
let foreign = make(.leftMouseUp, otherWindow)
check(grabber.filterCommittedEvent(foreign) === foreign, "other window up is untouched")
let up = make(.leftMouseUp)
check(grabber.filterCommittedEvent(up) === up, "zero movement up passes")
check(grabber.drag.phase == .inactive, "monitor up clears state")
arrow = false
check(hit(.leftMouseDown) === page && grabber.drag.phase == .inactive, "text/link cursors do not arm")
arrow = true;eligible = false
check(hit(.leftMouseDown) === page && grabber.drag.phase == .inactive, "capture/modal/ownership refusal passes down")
eligible = true
_ = hit(.leftMouseDown);arrow = false
check(hit(.leftMouseDragged) === page && grabber.drag.phase == .inactive, "changed cursor cancels before commit")
arrow = true
_ = hit(.leftMouseDown);current = false
check(hit(.leftMouseDragged) === page && grabber.drag.phase == .inactive, "lost document/page owner cannot commit")
current = true
_ = hit(.leftMouseDown);configure(owner, 2)
check(grabber.drag.phase == .inactive, "document revision cancels armed sequence")
_ = hit(.leftMouseDown);grabber.frame.size.width -= 1
check(grabber.drag.phase == .inactive, "geometry invalidation")
_ = hit(.leftMouseDown);configure(NSObject(), 2)
check(grabber.drag.phase == .inactive, "page replacement")
configure()
_ = hit(.leftMouseDown);grabber.isHidden = true
check(grabber.drag.phase == .inactive, "hidden owner cancels")
configure();duringDrag = { grabber.configure(owner: nil, revision: 0, isCurrent: nil, eligibility: nil) }
_ = hit(.leftMouseDown)
check(hit(.leftMouseDragged) === page && grabber.drag.phase == .inactive, "synchronous native drag invalidation cannot resurrect owner")
duringDrag = nil;configure()
_ = hit(.leftMouseDown);_ = hit(.leftMouseDragged)
current = false
check(grabber.filterCommittedEvent(up) === up && grabber.drag.phase == .inactive, "committed owner loss releases monitor")
current = true;configure()
_ = hit(.leftMouseDown);grabber.removeFromSuperview()
check(grabber.drag.phase == .inactive, "window detach cancels")
root.addSubview(grabber); grabber.frame = WebpageWindowDragState.region(in: rect, topStripHeight: 0)
configure()

// True no-op: inactive left-drags in the strip never arm/commit/take the click,
// so owner/current/hidden/arrow/eligibility probes are skipped. Left-down and
// armed/committed drag still probe so eligibility flips keep identical outcomes.
func resetProbes() { DispatchOverrides.cursorReads = 0; currentProbes = 0; eligibilityProbes = 0 }
func probed() -> Bool { DispatchOverrides.cursorReads + currentProbes + eligibilityProbes > 0 }
resetProbes()
check(hit(.leftMouseDragged) === page && !probed() && grabber.drag.phase == .inactive,
      "inactive left-drag skips eligibility/cursor probes")
check(hit(.leftMouseDragged) === page && !probed(), "repeated inactive left-drag stays a no-op skip")
arrow = false; eligible = false; current = false
check(hit(.leftMouseDragged) === page && !probed() && grabber.drag.phase == .inactive,
      "inactive left-drag skip ignores flipped eligibility inputs")
arrow = true; eligible = true; current = true
resetProbes()
check(hit(.leftMouseDown) === page && probed() && grabber.drag.phase == .began,
      "eligible left-down still probes and arms")
let afterArm = (DispatchOverrides.cursorReads, currentProbes, eligibilityProbes)
eligible = false
check(hit(.leftMouseDragged) === page && grabber.drag.phase == .inactive,
      "armed drag still probes eligibility before commit")
check(DispatchOverrides.cursorReads > afterArm.0 && currentProbes > afterArm.1 && eligibilityProbes > afterArm.2,
      "began left-drag evaluates eligibility/cursor")
eligible = true; resetProbes()
_ = hit(.leftMouseDown)
check(grabber.drag.phase == .began && probed(), "re-arm probes on left-down")
resetProbes()
let dragsBeforeCommit = drags.count
check(hit(.leftMouseDragged) === grabber && drags.count == dragsBeforeCommit + 1, "armed drag still commits")
check(probed(), "commit-path left-drag evaluates eligibility before performDrag")
resetProbes()
check(hit(.leftMouseDragged) === grabber && probed(), "committed left-drag still re-checks eligibility")
grabber.cancel()
DispatchOverrides.currentEvent = nil; DispatchOverrides.cursor = nil; DispatchOverrides.windowDrag = nil

check(!window.isVisible && !otherWindow.isVisible, "components did not show windows")
print("\(checks) webpage-window-dragging component assertions passed; no browser or native window grabber executed")

}
