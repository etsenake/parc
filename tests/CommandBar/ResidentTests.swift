import AppKit

@main @MainActor struct ResidentTests {
    static var count = 0
    static func check(_ value: @autoclosure () -> Bool, _ message: String) {
        count += 1
        guard value() else { fatalError("Resident: \(message)") }
    }

    static func main() {
        NSApplication.shared.setActivationPolicy(.prohibited)
        restingAndGrowth()
        slotGeometry()
        expansionRules()
        residentLifetime()
        paletteLifetime()
        hostPassThrough()
        print("Resident command bar: \(count) assertions passed")
    }

    static func restingAndGrowth() {
        typealias Layout = CommandBarResidentLayout
        check(Layout.restHeight == 64, "the resting bar is the palette's 64-point header")
        check(Layout.height(expanded: false, rows: 0) == 64 && Layout.height(expanded: false, rows: 9) == 64,
              "a collapsed bar is only the field whatever rows exist")
        check(Layout.height(expanded: true, rows: 0) == 126, "an expanded bar with no rows keeps one row for its message")
        check(Layout.height(expanded: true, rows: 1) == 126, "one result adds the divider and one 50-point row")
        check(Layout.height(expanded: true, rows: 3) == 226, "three results grow by three rows")
        check(Layout.height(expanded: true, rows: 5) == 326, "five results reach the palette's nominal 326 points")
        for rows in [6, 8, 25, 100] {
            check(Layout.height(expanded: true, rows: rows) == 326, "\(rows) results stay capped at five visible rows")
        }
        check(Layout.height(expanded: true, rows: 2, banner: 40) == 216 && Layout.height(expanded: false, rows: 0, banner: 40) == 104,
              "the privacy banner adds its own height")
        let slot = CGRect(x: 0, y: 0, width: 765, height: 600)
        var previous: CGRect?
        for rows in [0, 1, 2, 3, 4, 5, 6, 12, 3, 0] {
            let frame = Layout.surfaceFrame(in: slot, height: Layout.height(expanded: rows > 0, rows: rows))
            check(frame.maxY == slot.maxY, "the top edge stays at the slot's top with \(rows) rows")
            check(frame.minX == 0 && frame.width == 765, "the width holds while growing")
            check(frame.height == min(326, rows == 0 ? 64 : 76 + CGFloat(rows) * 50), "\(rows) rows give the expected height")
            if let previous { check(previous.maxY == frame.maxY, "growing or shrinking never moves the top edge") }
            previous = frame
        }
    }

    static func slotGeometry() {
        typealias Layout = CommandBarResidentLayout
        check(Layout.maximumWidth == 765, "the resident bar is at most the palette's 765 points")
        let wide = Layout.surfaceFrame(in: CGRect(x: 0, y: 0, width: 1200, height: 500), height: 126)
        check(wide.width == 765 && wide.midX == 600, "a wider slot centres a 765-point bar")
        let narrow = Layout.surfaceFrame(in: CGRect(x: 0, y: 0, width: 520, height: 500), height: 126)
        check(narrow.width == 520 && narrow.minX == 0, "a narrower slot sets the bar's width")
        let offset = Layout.surfaceFrame(in: CGRect(x: 100, y: 50, width: 600, height: 400), height: 226)
        check(offset.maxY == 450 && offset.minX == 100 && offset.height == 226, "a slot's origin carries through")
        let short = Layout.surfaceFrame(in: CGRect(x: 0, y: 0, width: 765, height: 200), height: 326)
        check(short.maxY == 200 && short.height == 200, "a short slot clips growth at its bottom with the top fixed")
        let tiny = Layout.surfaceFrame(in: CGRect(x: 0, y: 0, width: 765, height: 40), height: 326)
        check(tiny.maxY == 40 && tiny.height == 64, "a slot shorter than the field never squashes it")
    }

    static func expansionRules() {
        typealias Layout = CommandBarResidentLayout
        func expands(_ rows: Int, actions: Bool = false, website: Bool = false, empty: Bool = false,
                     invalidated: Bool = false, error: Bool = false) -> Bool {
            Layout.expands(resultCount: rows, actionsScope: actions, websiteScoped: website, inputIsEmpty: empty,
                           scopeInvalidated: invalidated, hasError: error)
        }
        check(Layout.rests(query: "", scoped: false, scopeInvalidated: false), "an empty ordinary query rests")
        check(!Layout.rests(query: "a", scoped: false, scopeInvalidated: false), "typing leaves rest")
        check(!Layout.rests(query: "", scoped: true, scopeInvalidated: false), "Actions and site scopes are not at rest")
        check(!Layout.rests(query: "", scoped: false, scopeInvalidated: true), "an unavailable scope is not at rest")
        check(Layout.restingToken != CommandBarOpenResultsSkip.sidebarBrowsingToken, "resting has its own skip token")
        check(!expands(0, empty: true), "at rest only the field shows")
        check(!expands(0), "a query still waiting for its first results stays collapsed")
        check(expands(1) && expands(7), "results expand the bar")
        check(expands(0, actions: true, empty: true) && expands(12, actions: true), "Actions always lists or explains")
        check(!expands(0, website: true, empty: true), "an empty site scope stays a field")
        check(expands(0, website: true) && expands(0, website: true, empty: true, error: true) && expands(3, website: true, empty: true),
              "a site scope expands for input, an error or results")
        check(expands(0, empty: true, invalidated: true), "an unavailable scope shows its message")
        check(Layout.height(expanded: expands(0, empty: true), rows: 0) == Layout.restHeight, "resting is the resting height")
    }

    static func residentLifetime() {
        typealias Lifetime = CommandBarLifetime
        let windowEvents: [Lifetime.Event] = [.resignedKey(ownAlert: false), .resignedKey(ownAlert: true), .focusMoved,
                                              .miniaturizing, .appDeactivated, .resized, .moved, .ownerInvalid,
                                              .sheetBegan(ownAlert: false), .sheetBegan(ownAlert: true), .securityChanged]
        for event in windowEvents {
            let response = Lifetime.response(to: event, resident: true)
            check(response != .dismiss && response != .dismissRestoringFocus, "the resident bar never dismisses itself on \(event)")
        }
        check(Lifetime.response(to: .resignedKey(ownAlert: false), resident: true) == .keep, "losing key keeps the bar")
        check(Lifetime.response(to: .focusMoved, resident: true) == .keep, "focus moving elsewhere keeps the bar")
        check(Lifetime.response(to: .appDeactivated, resident: true) == .keep, "app deactivation keeps the bar")
        check(Lifetime.response(to: .miniaturizing, resident: true) == .keep, "miniaturizing keeps the bar")
        check(Lifetime.response(to: .resized, resident: true) == .reposition && Lifetime.response(to: .moved, resident: true) == .reposition,
              "resizing and moving only reposition")
        check(Lifetime.response(to: .ownerInvalid, resident: true) == .keep, "an invalid owner waits for the owner's dismissal")
        check(Lifetime.response(to: .sheetBegan(ownAlert: false), resident: true) == .retireScopeMenu,
              "an unrelated sheet closes only the bar's own scope menu")
        check(Lifetime.response(to: .sheetBegan(ownAlert: true), resident: true) == .keep, "the bar's own scope sheet keeps it")
        check(Lifetime.response(to: .securityChanged, resident: true) == .retireScopeMenu,
              "a security prompt closes only the bar's own scope menu")
        check(Lifetime.response(to: .closing, resident: true) == .dismiss, "a closing window tears the bar down")
        check(Lifetime.response(to: .escape(scoped: false), resident: true) == .reset, "Escape clears and collapses")
        check(Lifetime.response(to: .escape(scoped: true), resident: true) == .leaveScope, "Escape first leaves a scope")
        check(Lifetime.response(to: .scopeExitFailed, resident: true) == .reset, "a failed scope exit resets instead of dismissing")
        check(Lifetime.response(to: .submitted, resident: true) == .resetForAction, "a submission resets the bar")
    }

    static func paletteLifetime() {
        typealias Lifetime = CommandBarLifetime
        let expected: [(Lifetime.Event, Lifetime.Response)] = [
            (.resignedKey(ownAlert: false), .dismiss), (.resignedKey(ownAlert: true), .keep), (.focusMoved, .dismiss),
            (.closing, .dismiss), (.miniaturizing, .dismiss), (.sheetBegan(ownAlert: false), .dismiss),
            (.sheetBegan(ownAlert: true), .keep), (.securityChanged, .dismiss), (.appDeactivated, .dismiss),
            (.resized, .reposition), (.moved, .reposition), (.ownerInvalid, .dismiss),
            (.escape(scoped: true), .leaveScope), (.escape(scoped: false), .dismissRestoringFocus),
            (.scopeExitFailed, .dismissRestoringFocus), (.submitted, .dismissRestoringFocus),
        ]
        for (event, response) in expected {
            check(Lifetime.response(to: event, resident: false) == response, "the palette still answers \(event) with \(response)")
        }
    }

    static func hostPassThrough() {
        let window = NSWindow(contentRect: NSRect(x: -30000, y: -30000, width: 1000, height: 700),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 1000, height: 700))
        window.contentView = content
        let slot = NSView(frame: NSRect(x: 117, y: 0, width: 765, height: 420))
        content.addSubview(slot)
        let host = CommandBarHost(), bar = NSView()
        host.frame = slot.bounds; host.autoresizingMask = [.width, .height]
        host.addSubview(bar); host.bar = bar
        var changes = 0
        host.onGeometryChange = { changes += 1 }
        slot.addSubview(host)
        check(changes == 1, "joining the window repositions the bar")
        bar.frame = CommandBarResidentLayout.surfaceFrame(in: host.bounds, height: CommandBarResidentLayout.restHeight)
        check(host.hitTest(NSPoint(x: 380, y: 400)) === bar, "the card takes the mouse")
        check(host.hitTest(NSPoint(x: 380, y: 200)) == nil, "the slot below the card passes the mouse through")
        check(host.hitTest(NSPoint(x: 380, y: 340)) == nil, "the gap just under the resting card passes through")
        bar.frame = CommandBarResidentLayout.surfaceFrame(in: host.bounds, height: CommandBarResidentLayout.height(expanded: true, rows: 5))
        check(host.hitTest(NSPoint(x: 380, y: 140)) === bar && host.hitTest(NSPoint(x: 380, y: 60)) == nil,
              "grown results take the mouse only where they are drawn")
        slot.setFrameSize(NSSize(width: 600, height: 300))
        check(changes >= 2 && host.frame.size == NSSize(width: 600, height: 300), "resizing the slot repositions the bar")
        host.removeFromSuperview()
        window.contentView = nil
    }
}
