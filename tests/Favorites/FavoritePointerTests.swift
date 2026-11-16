import AppKit

private final class ComponentWindow: NSWindow {
    var keyForComponent = true
    override var isKeyWindow: Bool { keyForComponent }
}

@main struct FavoritePointerTests {
    @MainActor static func main() { exitOnFailure(runChecks) }
    @MainActor static func runChecks() {
        _ = NSApplication.shared
        var count = 0
        func check(_ value: @autoclosure () -> Bool, _ message: String) {
            precondition(value(), message); count += 1
        }
        func policy(_ modifiers: NSEvent.ModifierFlags = [], _ clicks: Int = 1, _ key: Bool = true) -> FavoritePointerAction? {
            FavoritePointerPolicy.mouseDown(modifiers: modifiers, clickCount: clicks, isKey: key)
        }
        check(policy() == .activate, "Primary selection is a down event")
        check(policy(.shift) == .activate, "Shift does not introduce AppTray range selection")
        check(policy(.command) == .resetAndSelect, "Exact Command first down resets the original")
        check(policy([.command, .shift]) == .activate, "Combined modifiers do not accidentally reset")
        check(policy([.command, .capsLock]) == .activate, "Complete normalized flags govern Command reset")
        check(policy(.control) == nil, "Control belongs to context provider")
        check(policy(.option) == nil && policy([.option, .command]) == nil, "Option has a separate release path")
        check(policy([], 2) == .resetIfNeeded && policy([], 3) == .resetIfNeeded, "Repeated down uses reset eligibility")
        check(policy(.option, 2) == .resetIfNeeded, "Double-down path precedes first-click Option gate")
        check(policy([], 1, false) == nil, "Inactive-window down does not select")
        check(policy([], 2, false) == .resetIfNeeded && policy(.command, 2, false) == .resetIfNeeded,
              "Repeated down takes the double-click branch whatever the key state")
        check(policy(.command, 1, false) == nil, "Command reset requires a first-down selection")
        check(policy([], 0) == nil, "No synthetic zero-click activation")
        func release(_ modifiers: NSEvent.ModifierFlags = [], _ clicks: Int = 1, _ key: Bool = true) -> FavoritePointerAction? {
            FavoritePointerPolicy.mouseUp(modifiers: modifiers, clickCount: clicks, isKey: key)
        }
        check(release() == nil && release(.command) == nil && release(.shift) == nil,
              "A first down that selected is not replayed on release")
        check(release([], 1, false) == .activate && release(.command, 1, false) == .activate,
              "A non-key first click resolves on release with ordinary selection")
        check(release(.option, 1, false) == .openInSplit, "Option release keeps its route in a non-key window")
        check(release([], 2, false) == nil && release([], 0, false) == nil, "Only a single click resolves on release")

        let window = ComponentWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 120),
                                     styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let tile = FavoriteTile(title: "Original", monogram: "O", url: "https://example.test/home")
        tile.frame = NSRect(x: 10, y: 10, width: 60, height: 48)
        window.contentView!.addSubview(tile)
        let owner = FavoritePointerOwner(tabID: UUID(), profileID: UUID(), spaceID: UUID(), createdAt: Date())
        tile.update(title: "Original", monogram: "O", url: "https://example.test/home", owner: owner)
        var available = true, events: [FavoritePointerAction] = [], prepared = 0
        tile.canActivate = { available }
        tile.preparePointerAction = { intent in
            prepared += 1
            var consumed = false
            return {
                guard available, !consumed else { return false }
                consumed = true; events.append(intent); return true
            }
        }
        func event(_ type: NSEvent.EventType, _ flags: NSEvent.ModifierFlags = [], _ clicks: Int = 1,
                   _ point: NSPoint = NSPoint(x: 20, y: 20)) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: point, modifierFlags: flags, timestamp: 1,
                              windowNumber: window.windowNumber, context: nil, eventNumber: 12,
                              clickCount: clicks, pressure: 1)!
        }
        tile.mouseDown(with: event(.leftMouseDown))
        check(events == [.activate], "Actual tile selects before release")
        tile.selected = true
        tile.update(title: "Updated title", monogram: "U", url: "https://example.test/current", owner: owner)
        tile.mouseUp(with: event(.leftMouseUp))
        check(events == [.activate], "Same-item redraw does not replay activation")
        check(tile.accessibilityTitle() == "Updated title" && tile.isAccessibilitySelected(), "Retained tile refreshes title/selection")
        tile.mouseDown(with: event(.leftMouseDown, .command)); tile.mouseUp(with: event(.leftMouseUp, .command))
        check(events.last == .resetAndSelect && events.count == 2, "One original Command reset request")
        tile.mouseDown(with: event(.leftMouseDown, [], 2)); tile.mouseUp(with: event(.leftMouseUp, [], 2))
        check(events.last == .resetIfNeeded && events.count == 3, "Double down requests reset, never Rename or release activation")
        available = false
        tile.mouseDown(with: event(.leftMouseDown)); tile.mouseUp(with: event(.leftMouseUp))
        check(events.count == 3, "Unavailable target is not dispatched")
        available = true
        tile.mouseDown(with: event(.leftMouseDown, .option))
        check(events.count == 3, "Existing deferred route does not act on down")
        available = false; tile.mouseUp(with: event(.leftMouseUp, .option)); available = true
        check(events.count == 3, "Captured original release lease revalidates")
        tile.mouseDown(with: event(.leftMouseDown, .option)); tile.mouseDragged(with: event(.leftMouseDragged, .option))
        tile.mouseUp(with: event(.leftMouseUp, .option))
        check(events.count == 3, "Drag revokes deferred activation")
        tile.mouseDown(with: event(.leftMouseDown, .option))
        tile.mouseUp(with: event(.leftMouseUp, .option, 1, NSPoint(x: 150, y: 90)))
        check(events.count == 3, "Outside release refuses")
        tile.mouseDown(with: event(.leftMouseDown, .option)); tile.isHidden = true; tile.isHidden = false
        tile.mouseUp(with: event(.leftMouseUp, .option))
        check(events.count == 3, "Hidden round trip cannot revive old intent")
        tile.mouseDown(with: event(.leftMouseDown, .option)); tile.isEnabled = false; tile.isEnabled = true
        tile.mouseUp(with: event(.leftMouseUp, .option))
        check(events.count == 3, "Disabled round trip cannot revive old intent")
        tile.mouseDown(with: event(.leftMouseDown, .option))
        NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: window)
        tile.mouseUp(with: event(.leftMouseUp, .option))
        check(events.count == 3, "Deactivation cancels exact pending phase")
        tile.mouseDown(with: event(.leftMouseDown, .option))
        let next = FavoritePointerOwner(tabID: owner.tabID, profileID: owner.profileID, spaceID: UUID(), createdAt: owner.createdAt)
        tile.update(title: "Other Space", monogram: "O", url: "https://example.test/home", owner: next)
        tile.mouseUp(with: event(.leftMouseUp, .option))
        check(events.count == 3, "Same Favorite in another Space cannot inherit pending input")
        tile.mouseDown(with: event(.leftMouseDown, .option)); tile.removeFromSuperview()
        window.contentView!.addSubview(tile); tile.mouseUp(with: event(.leftMouseUp, .option))
        check(events.count == 3, "Detach/reattach cancels original pointer owner")
        tile.mouseDown(with: event(.leftMouseDown, .option))
        tile.update(title: "Refreshed", monogram: "R", url: "https://example.test/home", owner: next)
        tile.mouseUp(with: event(.leftMouseUp, .option)); tile.mouseUp(with: event(.leftMouseUp, .option))
        check(events.count == 4 && events.last == .openInSplit, "Option release consumes its original split lease")
        let prior = events.count
        tile.mouseDown(with: event(.leftMouseDown, [.option, .command]))
        tile.mouseUp(with: event(.leftMouseUp, [.option, .command]))
        check(events.count == prior, "The excluded mini browser window route never substitutes activation")
        tile.mouseDown(with: event(.leftMouseDown, .option))
        tile.mouseUp(with: event(.leftMouseUp))
        check(events.count == prior, "Removing Option before release does not replay down selection")
        tile.mouseDown(with: event(.leftMouseDown, .option))
        tile.mouseUp(with: event(.leftMouseUp, [.option, .shift]))
        check(events.count == prior + 1 && events.last == .activate, "Release modifiers choose ordinary fallback")
        tile.mouseDown(with: event(.leftMouseDown))
        tile.mouseUp(with: event(.leftMouseUp, .option))
        check(events.suffix(2) == [.activate, .openInSplit], "Option added after down uses resulting original selection")
        check(FavoritePointerPolicy.mouseUp(modifiers: [.option, .capsLock, .numericPad], clickCount: 1, isKey: true) == .openInSplit,
              "Release ignores non-low-four modifiers")
        check(FavoritePointerPolicy.mouseUp(modifiers: .option, clickCount: 2, isKey: true) == nil,
              "Repeated release cannot duplicate double-down reset")
        check(prepared > events.count, "Refused pending intentions were actually prepared")
        check(!tile.acceptsFirstMouse(for: event(.leftMouseDown)),
              "The click that activates an inactive window never reaches the tile")
        let beforeInactive = events.count
        window.keyForComponent = false
        tile.mouseDown(with: event(.leftMouseDown))
        check(events.count == beforeInactive, "A delivered non-key down does not select")
        tile.mouseUp(with: event(.leftMouseUp))
        check(events.count == beforeInactive + 1 && events.last == .activate,
              "Its release performs the one ordinary selection lease")
        window.keyForComponent = true
        var proposals = 0, commits = 0, captured: SidebarMoveSession?
        tile.beginMove = {
            proposals += 1
            let original = SidebarMoveSession(items: [.tab(owner.tabID)], window: window,
                validate: { available }, propose: { _, _ in available }, commit: { _, _ in commits += 1; return true })
            captured = original; return original
        }
        tile.mouseDown(with: event(.leftMouseDown))
        let original = captured!
        check(proposals == 1 && original.isValid, "Drag captures original owner after down activation")
        tile.beginMove = { preconditionFailure("A later producer cannot replace original down owner") }
        available = false
        tile.mouseDragged(with: event(.leftMouseDragged, [], 1, NSPoint(x: 50, y: 20)))
        check(original.ended && tile.sidebarDrag == nil && commits == 0, "Stale drag cancels its original lease without a new query")
        available = true
        tile.beginMove = {
            let value = SidebarMoveSession(items: [.tab(owner.tabID)], window: window,
                validate: { true }, propose: { _, _ in true }, commit: { _, _ in commits += 1; return true })
            captured = value; return value
        }
        tile.mouseDown(with: event(.leftMouseDown, .option))
        let option = captured!
        tile.mouseDragged(with: event(.leftMouseDragged, .option, 1, NSPoint(x: 50, y: 20)))
        check(option.ended && tile.sidebarDrag == nil && commits == 0, "Unsupported Option-copy never becomes move")
        tile.mouseDown(with: event(.leftMouseDown)); let released = captured!
        tile.mouseUp(with: event(.leftMouseUp))
        check(released.ended && commits == 0, "Ordinary click ends unused move lease")
        tile.mouseDown(with: event(.leftMouseDown)); let detached = captured!
        tile.removeFromSuperview()
        check(detached.ended && commits == 0, "Detachment cancels the captured drag owner")
        let target = SidebarContainerLocation(spaceID: owner.spaceID, folderID: nil, section: .favorite, profileID: owner.profileID)
        let oneShot = SidebarMoveSession(items: [.tab(owner.tabID)], window: window,
            validate: { true }, propose: { _, _ in true }, commit: { _, _ in commits += 1; return true })
        check(oneShot.move(to: target, before: nil) && !oneShot.move(to: target, before: nil) && commits == 1, "One transaction cannot replay")
        window.close()
        print("\(count) Favorite pointer policy/lifecycle assertions passed (no browser or Apple Events)")
    }
}
