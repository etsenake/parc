import AppKit

@main @MainActor struct SidebarAccessibilityTests {
    static var count = 0
    static func check(_ value: @autoclosure () -> Bool, _ message: String) {
        count += 1
        guard value() else { fatalError("SidebarAccessibility: \(message)") }
    }
    static func main() {
        _ = NSApplication.shared
        //
        check(SidebarAccessibility.hideSidebar == "Hide sidebar" && SidebarAccessibility.lockSidebar == "Lock sidebar",
              "toggle labels follow the locked/floating pair")
        check(SidebarAccessibility.goBack == "Go back" && SidebarAccessibility.goForward == "Go forward"
              && SidebarAccessibility.reload == "Reload this page", "navigation labels")

        // SidebarDockItemView: Space description, name title and identifier,
        // on a Space button built the way SidebarView.render builds it.
        let space = ActionButton("Home", symbol: "house"); space.title = ""
        let defaultDescription = space.accessibilityRoleDescription()
        check(defaultDescription != "Space" && space.accessibilityTitle() != "Home"
              && space.accessibilityIdentifier() != "SidebarDockItem-Home", "unconfigured button has none of the Space values")
        SidebarAccessibility.configureSpace(space, name: "Home")
        check(space.accessibilityRoleDescription() == "Space", "Space role description replaces \(defaultDescription ?? "nil")")
        check(space.accessibilityTitle() == "Home", "Space title is its name")
        check(space.accessibilityIdentifier() == "SidebarDockItem-Home", "Space identifier")
        check(space.accessibilityLabel() == "Home", "ActionButton's label is preserved")
        // SidebarDockItemView draws no ring and is no stop: the Space button refuses focus.
        check(space.refusesFirstResponder && !space.acceptsFirstResponder && space.focusRingType == .none,
              "a Space button takes no keyboard focus and draws no ring")
        // VoiceOver reads the unignored element AppKit exposes, the cell.
        let exposed = NSAccessibility.unignoredDescendant(of: space) as? NSCell
        check(exposed != nil && exposed === space.cell, "AppKit exposes the button's cell")
        check(exposed?.accessibilityRoleDescription() == "Space" && exposed?.accessibilityTitle() == "Home"
              && exposed?.accessibilityIdentifier() == "SidebarDockItem-Home", "the exposed cell carries the Space values")
        let labelled = ActionButton("Hide sidebar", symbol: "sidebar.left")
        SidebarAccessibility.label(labelled, SidebarAccessibility.lockSidebar)
        let labelledCell = NSAccessibility.unignoredDescendant(of: labelled) as? NSCell
        check(labelledCell?.accessibilityLabel() == "Lock sidebar" && labelled.image?.accessibilityDescription == "Lock sidebar",
              "the exposed toggle cell reads the current label")
        let untitled = ActionButton("", symbol: "house")
        SidebarAccessibility.configureSpace(untitled, name: "")
        check(untitled.accessibilityTitle() == "Untitled Space"
              && untitled.accessibilityIdentifier() == "SidebarDockItem-Untitled Space", "empty name takes the nil fallback (Parc adaptation)")

        let window = NSWindow(contentRect: NSRect(x: -10_000, y: -10_000, width: 240, height: 400),
                              styleMask: [.titled], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 240, height: 400))
        window.contentView = root

        // Focus ring: HoverableButton's rounded-bounds mask shape, opt-in only.
        let plain = ActionButton("Downloads", symbol: "arrow.down.circle")
        check(plain.focusRingType == .none, "existing ActionButton users keep no ring")
        let button = ActionButton("Hide sidebar", symbol: "sidebar.left")
        button.frame = NSRect(x: 0, y: 0, width: 28, height: 28)
        button.focusRingCornerRadius = 5
        check(button.focusRingType == .exterior, "radius enables the keyboard ring")
        check(button.focusRingMaskBounds == button.bounds, "mask bounds are the button bounds")
        let bitmap = mask(button)
        check((bitmap.colorAt(x: 0, y: 0)?.alphaComponent ?? 1) < 0.1, "mask corner is rounded")
        check((bitmap.colorAt(x: 14, y: 14)?.alphaComponent ?? 0) > 0.9, "mask fills the button")
        check((bitmap.colorAt(x: 14, y: 0)?.alphaComponent ?? 0) > 0.9, "mask reaches the edge midpoint")
        button.focusRingCornerRadius = nil
        check(button.focusRingType == .none, "clearing the radius removes the ring")

        // NavigationControlButton (back, forward, reload): the sidebar's opt-in
        // rounded ring; other users keep the exterior default.
        let navigation = NavigationControlButton(SidebarAccessibility.goBack, symbol: "arrow.left", history: true)
        navigation.frame = NSRect(x: 0, y: 0, width: 28, height: 28)
        check(navigation.focusRingType == .exterior && navigation.focusRingCornerRadius == nil, "navigation buttons keep the exterior ring by default")
        navigation.focusRingCornerRadius = 5
        check(navigation.focusRingType == .exterior && navigation.focusRingMaskBounds == navigation.bounds,
              "the sidebar's navigation ring covers the bounds")
        let navigationMask = mask(navigation)
        check((navigationMask.colorAt(x: 0, y: 0)?.alphaComponent ?? 1) < 0.1 && (navigationMask.colorAt(x: 14, y: 14)?.alphaComponent ?? 0) > 0.9
              && (navigationMask.colorAt(x: 14, y: 0)?.alphaComponent ?? 0) > 0.9, "navigation mask is the rounded bounds")

        // Key-view order: AppKit's geometric order scoped to a region, in the
        // flipped sidebar space, through an unflipped host (the Favorites grid's).
        let sidebar = FlippedView(frame: NSRect(x: 0, y: 0, width: 240, height: 400))
        root.addSubview(sidebar)
        let region = FlippedView(frame: NSRect(x: 0, y: 40, width: 240, height: 300)); sidebar.addSubview(region)
        func field(_ name: String, _ frame: NSRect, in parent: NSView) -> NSTextField {
            let field = NSTextField(string: name); field.frame = frame; field.identifier = .init(name); parent.addSubview(field); return field
        }
        func names(_ views: [NSView]) -> [String] { views.map { $0.identifier?.rawValue ?? "?" } }
        _ = field("trailing", NSRect(x: 120, y: 0, width: 40, height: 20), in: region)
        _ = field("leading", NSRect(x: 10, y: 2, width: 40, height: 20), in: region)
        region.addSubview(NSTextField(labelWithString: "label"))
        let disabledLabel = NSTextField(labelWithString: "disabled label"); disabledLabel.isEnabled = false; region.addSubview(disabledLabel)
        let grid = NSView(frame: NSRect(x: 0, y: 40, width: 240, height: 60)); region.addSubview(grid)
        _ = field("lower", NSRect(x: 10, y: 0, width: 40, height: 20), in: grid)
        _ = field("upper", NSRect(x: 10, y: 40, width: 40, height: 20), in: grid)
        let refusing = ActionButton("Space"); refusing.frame = NSRect(x: 0, y: 200, width: 20, height: 20)
        SidebarAccessibility.configureSpace(refusing, name: "Space"); region.addSubview(refusing)
        let disabled = ActionButton("Clear"); disabled.frame = NSRect(x: 0, y: 240, width: 40, height: 20)
        disabled.identifier = .init("disabled"); disabled.isEnabled = false; region.addSubview(disabled)
        let order = SidebarAccessibility.keyViews(in: [region], space: sidebar)
        check(!disabled.acceptsFirstResponder && names(order) == ["leading", "trailing", "upper", "lower", "disabled"],
              "rows top to bottom, leading first, unflipped hosts converted, a disabled control kept, labels and Spaces excluded: \(names(order))")

        // The chain: leading controls, Favorites, the list stop, the regions laid
        // out first (a creation view placing its own children), then the dock.
        let list = ListStopView(frame: NSRect(x: 0, y: 0, width: 240, height: 360)); sidebar.addSubview(list)
        let header = ActionButton("Hide sidebar"); header.identifier = .init("header")
        let dock = ActionButton("Space actions"); dock.identifier = .init("dock")
        let favorites = FlippedView(frame: NSRect(x: 0, y: 0, width: 240, height: 30)); list.addSubview(favorites)
        _ = field("favorite", NSRect(x: 0, y: 0, width: 40, height: 20), in: favorites)
        let rows = FlippedView(frame: NSRect(x: 0, y: 40, width: 240, height: 40)); list.addSubview(rows)
        _ = field("row", NSRect(x: 0, y: 0, width: 40, height: 20), in: rows)
        let creation = CreationLikeView(frame: NSRect(x: 0, y: 100, width: 240, height: 60)); list.addSubview(creation)
        check(names(SidebarAccessibility.keyViews(in: [creation], space: sidebar)) == ["name", "icon"],
              "before its layout the creation view's children sort by subview index")
        list.identifier = .init("list")
        let chain = SidebarAccessibility.keyViewChain(leading: [header], favorites: favorites, list: list, regions: [rows, creation],
                                                      trailing: [dock], space: sidebar)
        check(names(chain) == ["header", "favorite", "list", "row", "icon", "name", "dock"],
              "leading, Favorites, list stop, list controls by laid-out frames, dock: \(names(chain))")

        // Linking: the list stop is one stop; an explicit exit wins; without one
        // the window loop's way on stays; a removed member is never the exit;
        // the window loop's way in to the list stop's view moves to the start.
        let outside = field("outside", NSRect(x: 0, y: 380, width: 40, height: 20), in: root)
        let page = field("page", NSRect(x: 60, y: 380, width: 40, height: 20), in: root)
        let entering = field("entering", NSRect(x: 120, y: 380, width: 40, height: 20), in: root)
        let first = field("first", NSRect(x: 0, y: 0, width: 40, height: 20), in: list)
        let hidden = field("hidden", NSRect(x: 0, y: 30, width: 40, height: 20), in: list); hidden.isHidden = true
        let last = field("last", NSRect(x: 0, y: 60, width: 40, height: 20), in: list)
        last.nextKeyView = outside
        // AppKit's computed loop links a container before its children.
        entering.nextKeyView = list
        SidebarAccessibility.link([first, hidden, list, last], within: list, exit: nil)
        check(first.nextKeyView === hidden && hidden.nextKeyView === list && list.nextKeyView === last && last.nextKeyView === outside,
              "the chain is linked in order and the last element keeps the window loop's way on")
        check(entering.nextKeyView === first && entering.nextValidKeyView === first,
              "the window loop's link into the list stop's view enters at the chain's start")
        check(list.canBecomeKeyView && first.nextValidKeyView === list && list.nextValidKeyView === last,
              "Tab skips a hidden member and stops at the list")
        SidebarAccessibility.link([last, list, first], within: list, exit: nil)
        check(last.nextKeyView === list && list.nextKeyView === first && first.nextKeyView === outside,
              "relinking a new order moves the way on to the new last element")
        SidebarAccessibility.link([last, list, first], within: list, exit: page)
        check(first.nextKeyView === page, "the window owner's exit replaces the window loop's link")
        let removed = field("removed", NSRect(x: 0, y: 90, width: 40, height: 20), in: list)
        let tail = field("tail", NSRect(x: 0, y: 120, width: 40, height: 20), in: list)
        SidebarAccessibility.link([first, removed, last, tail], within: list, exit: nil)
        tail.nextKeyView = nil
        removed.removeFromSuperview()
        SidebarAccessibility.link([first, last, tail], within: list, exit: nil)
        check(tail.nextKeyView == nil && first.nextKeyView === last, "a removed former member is not taken as the way out")
        SidebarAccessibility.link([first, last, tail], within: list, exit: page)
        check(tail.nextKeyView === page && first.nextValidKeyView === last, "an exit set later is used on the next link")
        // A narrow row moves the toggle after Back and Forward: the window
        // owner's link into the former entry moves to the new start.
        let formerEntry = field("formerEntry", NSRect(x: 0, y: 150, width: 40, height: 20), in: list)
        SidebarAccessibility.link([formerEntry, first, last, tail], within: list, exit: page)
        entering.nextKeyView = formerEntry
        SidebarAccessibility.link([first, formerEntry, last, tail], within: list, exit: page)
        check(entering.nextKeyView === first && first.previousKeyView === entering && first.nextKeyView === formerEntry
              && formerEntry.nextKeyView === last, "an outside link into a former first member moves to the new start")
        list.isHidden = true
        check(!first.canBecomeKeyView && !last.canBecomeKeyView && !list.canBecomeKeyView, "a hidden sidebar's controls are no key views")
        list.isHidden = false

        //
        let container = NSView(frame: root.bounds)
        container.setAccessibilityElement(true); container.setAccessibilityRole(.group)
        let strip = SidebarResizeRegionView(frame: SidebarResizeRegionView.frame(trailing: NSRect(x: 0, y: 0, width: 228, height: 400), in: root.bounds))
        let toggle = NSButton(title: "Hide sidebar", target: nil, action: nil)
        container.addSubview(strip); container.addSubview(toggle); root.addSubview(container)
        check(!strip.isAccessibilityElement() && [nil, .unknown].contains(strip.accessibilityRole()), "resize strip is not an element")
        let children = container.accessibilityChildren() as? [NSObject] ?? []
        check(!children.contains { $0 === strip } && children.contains { $0 === toggle || $0 === toggle.cell }, "resize strip is absent from the tree")
        check(strip.accessibilityHitTest(NSPoint(x: strip.frame.midX, y: strip.frame.midY)).map { $0 as AnyObject !== strip } ?? true,
              "AX hit testing never lands on the strip")
        window.close()

        do {
            //
            // toggle, Back, Forward and Reload, then the address and the list.
            // SidebarView keeps its subview order (header above the content
            // surface) and reorders only its accessibility children.
            let browser = NSWindow(contentRect: NSRect(x: -10_000, y: -10_000, width: 900, height: 600),
                                   styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                                   backing: .buffered, defer: false)
            browser.isReleasedWhenClosed = false
            let sidebar = NSView(frame: NSRect(x: 0, y: 0, width: 228, height: 600))
            let surface = NSView(frame: sidebar.bounds)
            let address = ActionButton("Address", symbol: "magnifyingglass")
            surface.addSubview(address)
            let lights = WindowStandardButtons()
            let back = ActionButton(SidebarAccessibility.goBack, symbol: "arrow.left")
            let forward = ActionButton(SidebarAccessibility.goForward, symbol: "arrow.right")
            let reload = ActionButton(SidebarAccessibility.reload, symbol: "arrow.clockwise")
            let footer = ActionButton("Space actions", symbol: "ellipsis")
            let headerToggle = ActionButton(SidebarAccessibility.hideSidebar, symbol: "sidebar.left")
            sidebar.addSubview(surface)
            for view in [lights, back, forward, reload, footer, headerToggle] { sidebar.addSubview(view) }
            browser.contentView?.addSubview(sidebar)
            func owner(_ element: Any) -> NSView? { (element as? NSView) ?? (element as? NSCell)?.controlView }
            let header: [NSView] = [lights, headerToggle, back, forward, reload]
            let natural = sidebar.accessibilityChildren() ?? []
            check(natural.first.flatMap(owner) === address, "AppKit alone lists the content surface first")
            let ordered = SidebarAccessibility.headerFirst(natural, header: header)
            check(lights.buttons.count == 3 && ordered.count == natural.count, "reordering keeps every element")
            check(ordered.compactMap(owner) == lights.buttons + [headerToggle, back, forward, reload, address, footer],
                  "lights, toggle, Back, Forward, Reload, then the rest in subview order")
            let leading = ordered.prefix(2).compactMap { $0 as? NSCell }.map { $0.accessibilitySubrole() }
            check(leading == [.closeButton, .minimizeButton], "the tree opens with AXCloseButton and AXMinimizeButton")
            // First in the tree but no Tab stop: AppKit makes its window widgets
            // refusing first responder, so the chain starts at the toggle.
            check(lights.buttons.allSatisfy { $0.refusesFirstResponder && !$0.acceptsFirstResponder && !$0.canBecomeKeyView }
                  && SidebarAccessibility.keyViews(in: [lights], space: sidebar).isEmpty, "the traffic lights are no keyboard stops")
            lights.isHidden = true
            let fullScreen = SidebarAccessibility.headerFirst(sidebar.accessibilityChildren() ?? [], header: header)
            check(fullScreen.first.flatMap(owner) === headerToggle, "without its lights the header leads with the toggle")
            //
            // Forward and Reload hides: the header follows the frames.
            lights.isHidden = false
            back.frame.origin.x = 70; forward.frame.origin.x = 104; headerToggle.frame.origin.x = 138; reload.isHidden = true
            let narrow = SidebarAccessibility.laidOut([headerToggle, back, forward, reload])
            check(narrow == [back, forward, headerToggle], "a narrow header orders its visible controls by frame")
            let narrowTree = SidebarAccessibility.headerFirst(sidebar.accessibilityChildren() ?? [], header: [lights] + narrow)
            check(Array(narrowTree.compactMap(owner).prefix(6)) == lights.buttons + [back, forward, headerToggle],
                  "a narrow header's tree follows the frames")
            browser.close()
        }

        do {
            //
            //
            // SidebarPresentationFrame.hidden). AppKit keeps that subtree in the
            // window's accessibility children, VoiceOver's navigation order and
            // the key-view loop; only hiding the container removes it. Parc keeps
            // the accessibility exposure and links the hidden chain bypassed.
            let browser = NSWindow(contentRect: NSRect(x: -10_000, y: -10_000, width: 900, height: 600),
                                   styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            browser.isReleasedWhenClosed = false
            let content = NSView(frame: NSRect(x: 0, y: 0, width: 900, height: 600)); browser.contentView = content
            let page = NSTextField(string: "page"); page.frame = NSRect(x: 300, y: 300, width: 200, height: 22); content.addSubview(page)
            let pageEnd = NSTextField(string: "end"); pageEnd.frame = NSRect(x: 300, y: 200, width: 200, height: 22); content.addSubview(pageEnd)
            let container = NSView(frame: SidebarPresentationFrame.locked.rect(width: 228, in: content.bounds))
            content.addSubview(container)
            let sidebar = ListStopView(frame: container.bounds); container.addSubview(sidebar)
            let headerToggle = ActionButton(SidebarAccessibility.hideSidebar, symbol: "sidebar.left")
            headerToggle.frame = NSRect(x: 76, y: 7, width: 32, height: 32)
            let address = NSTextField(string: "address"); address.frame = NSRect(x: 8, y: 46, width: 212, height: 36)
            sidebar.addSubview(headerToggle); sidebar.addSubview(address)
            func exposed(_ view: NSView) -> AnyObject? { NSAccessibility.unignoredDescendant(of: view) as AnyObject? }
            func listed(_ elements: [Any]?, _ view: NSView) -> Bool {
                NSAccessibility.unignoredChildren(from: elements ?? []).contains { $0 as AnyObject === exposed(view) }
            }
            // Pointer and accessibility hit tests at a point in window coordinates.
            func hits(_ point: NSPoint) -> (view: Bool, element: Bool) {
                let view = content.hitTest(content.superview?.convert(point, from: nil) ?? point)
                let element = browser.accessibilityHitTest(browser.convertPoint(toScreen: point)) as AnyObject?
                return (view.map { $0 === address || $0.isDescendant(of: address) } == true, element != nil && element === exposed(address))
            }
            let lockedPoint = address.convert(NSPoint(x: address.bounds.midX, y: address.bounds.midY), to: nil)
            let locked = hits(lockedPoint)
            check(locked.view && locked.element, "locked, pointer and accessibility hit tests reach the address")
            container.frame = SidebarPresentationFrame.hidden.rect(width: 228, in: content.bounds)
            check(!container.isHidden && container.frame.maxX < 0 && address.convert(address.bounds, to: nil).maxX < 0,
                  "the hidden sidebar is unhidden and wholly outside the content")
            check(listed(browser.accessibilityChildren(), headerToggle) && listed(browser.accessibilityChildren(), address),
                  "its controls stay in the window's accessibility children")
            // Untyped: the Swift overlay's [NSAccessibilityElement] traps on AppKit's cell proxies.
            let navigation = browser.perform(#selector(NSWindow.accessibilityChildrenInNavigationOrder))?.takeUnretainedValue() as? [Any]
            check(listed(navigation, address), "and in VoiceOver's navigation order")
            let element = exposed(address) as? NSAccessibilityElementProtocol
            check((element?.accessibilityFrame().maxX ?? .infinity) <= browser.frame.minX, "their accessibility frames lie left of the window")
            let hiddenPoint = address.convert(NSPoint(x: address.bounds.midX, y: address.bounds.midY), to: nil)
            let (formerPlace, offScreen) = (hits(lockedPoint), hits(hiddenPoint))
            check(!formerPlace.view && !formerPlace.element && !offScreen.view && !offScreen.element,
                  "hidden, neither hit test reaches them where they were or where they are")
            // On this OS a non-clipping view's visibleRect is its clipping
            // ancestors' region, not its own bounds, so an off-screen field still
            // reports one; a view that clips itself keeps its bounds.
            check(!address.visibleRect.isEmpty && !address.bounds.contains(address.visibleRect), "an off-screen field's visibleRect is not empty")
            if #available(macOS 14, *) {
                let clipping = NSView(frame: NSRect(x: 600, y: 100, width: 100, height: 28)); clipping.clipsToBounds = true
                content.addSubview(clipping)
                check(clipping.visibleRect == clipping.bounds, "a self-clipping view's visibleRect is its bounds")
                clipping.removeFromSuperview()
            }
            //
            // stop, through AppKit's computed loop and explicit links. (Focusing
            // a view first computes the window's loop, so it comes first.)
            check(browser.makeFirstResponder(address) && browser.firstResponder is NSTextView, "an off-screen field takes focus")
            _ = browser.makeFirstResponder(nil)
            browser.recalculateKeyViewLoop()
            func forward(from view: NSView) -> [NSView] { Array(sequence(first: view) { $0.nextValidKeyView }.prefix(8).dropFirst()) }
            func backward(from view: NSView) -> [NSView] { Array(sequence(first: view) { $0.previousValidKeyView }.prefix(8).dropFirst()) }
            let loop = forward(from: page)
            check(loop.contains { $0 === address }, "AppKit's computed loop includes the off-screen field")
            // SidebarView's chain: a gate that never takes focus, the header, the
            // list stop. Its first link moves the computed loop's way in to the
            // gate; the window owner's link from the page side's end joins it.
            let gate = NSView(); sidebar.addSubview(gate)
            let chain: [NSView] = [gate, headerToggle, address, sidebar]
            SidebarAccessibility.link(chain, within: sidebar, exit: nil)
            check(forward(from: page).contains { $0 === address } && !gate.canBecomeKeyView,
                  "unbypassed, Tab reaches the off-screen chain past its gate")
            // Parc's window owner sets no exit. The computed loop leaves the
            // sidebar from its last descendant (on this OS the field's own
            // hosting subview, no chain member), and the chain's end takes it.
            func inside(_ views: [NSView]) -> Bool { views.contains { $0.isDescendant(of: container) } }
            check(sidebar.nextKeyView.map { !$0.isDescendant(of: container) } == true && sidebar.nextValidKeyView != nil,
                  "without an exit the chain's end keeps the computed loop's way on")
            sidebar.presented = false
            SidebarAccessibility.link(chain, within: sidebar, exit: nil, bypassed: true)
            check(!inside(forward(from: page) + backward(from: page) + forward(from: pageEnd) + backward(from: pageEnd)),
                  "bypassed without an exit, Tab and Shift-Tab pass the hidden chain")
            sidebar.presented = true
            SidebarAccessibility.link(chain, within: sidebar, exit: nil)
            pageEnd.nextKeyView = gate
            SidebarAccessibility.link(chain, within: sidebar, exit: page)
            check([headerToggle, address].contains { $0 === pageEnd.nextValidKeyView } && sidebar.nextValidKeyView === page
                  && page.previousValidKeyView === sidebar, "the window owner's way in and out")
            // Parc: bypassed, the gate leads straight out, so Tab and Shift-Tab
            // pass the hidden chain from every way in.
            sidebar.presented = false
            SidebarAccessibility.link(chain, within: sidebar, exit: page, bypassed: true)
            check(pageEnd.nextValidKeyView === page && page.previousValidKeyView === pageEnd
                  && !inside(forward(from: page) + backward(from: page) + forward(from: pageEnd)),
                  "bypassed, Tab and Shift-Tab pass the hidden chain")
            SidebarAccessibility.link(chain, within: sidebar, exit: page, bypassed: true)
            check(pageEnd.nextValidKeyView === page && page.previousValidKeyView === pageEnd, "relinking a bypassed chain keeps the bypass")
            sidebar.presented = true
            SidebarAccessibility.link(chain, within: sidebar, exit: page)
            check([headerToggle, address].contains { $0 === pageEnd.nextValidKeyView } && page.previousValidKeyView === sidebar
                  && address.nextKeyView === sidebar && sidebar.previousKeyView === address,
                  "presenting it again restores the chain behind its way in and the way back to its end")
            // A key view's back pointer keeps only the last view linked to it,
            // and keeps it after that view links elsewhere [C].
            let (first, second, member, elsewhere) = (NSView(), NSView(), NSView(), NSView())
            first.nextKeyView = member; second.nextKeyView = member
            check(member.previousKeyView === second, "a back pointer records the last view linked")
            second.nextKeyView = elsewhere
            check(member.previousKeyView === second && first.nextKeyView === member,
                  "and is not cleared when that view links elsewhere")
            // Focus survives the move off-screen; only hiding the container gave
            // it to the window, so the window owner now does that itself.
            check(browser.makeFirstResponder(address) && (browser.firstResponder as? NSText)?.delegate === address,
                  "an off-screen field keeps focus")
            sidebar.presented = false
            // makeFirstResponder ignores acceptsFirstResponder; a view whose
            // becomeFirstResponder refuses leaves the window first responder,
            // though makeFirstResponder still reports success [C].
            _ = browser.makeFirstResponder(sidebar)
            check(browser.firstResponder === browser, "hidden, the list takes no focus")
            // SavedFocus, the one test every saved-focus restore asks: focus may
            // return into a presented sidebar, off-screen while it slides, but
            // not into one that is not presented, at any depth, its field
            // editor included; the page and other windows are unaffected.
            sidebar.presented = true
            check(SavedFocus.mayReturn(to: address, in: browser) && SavedFocus.mayReturn(to: sidebar, in: browser),
                  "a presented sidebar's views may take restored focus")
            check(browser.makeFirstResponder(address), "the field edits again")
            let editor = browser.firstResponder as? NSTextView
            sidebar.presented = false
            check(!SavedFocus.mayReturn(to: address, in: browser) && !SavedFocus.mayReturn(to: headerToggle, in: browser)
                  && !SavedFocus.mayReturn(to: sidebar, in: browser),
                  "a sidebar that is not presented takes no restored focus")
            check(editor.map { $0.isDescendant(of: address) && !SavedFocus.mayReturn(to: $0, in: browser) } == true,
                  "nor does its field editor")
            check(SavedFocus.mayReturn(to: page, in: browser) && !SavedFocus.mayReturn(to: page, in: nil)
                  && !SavedFocus.mayReturn(to: page, in: NSWindow()), "the page may; no other window may")
            sidebar.presented = true
            container.isHidden = true
            check(browser.firstResponder === browser, "hiding the container gives its focus to the window")
            check(!SavedFocus.mayReturn(to: address, in: browser), "a hidden container takes no restored focus")
            check(!listed(browser.accessibilityChildren(), address) && !address.canBecomeKeyView
                  && !loop.contains { $0.canBecomeKeyView && $0.isDescendant(of: container) }, "a hidden container leaves both")
            container.isHidden = false; sidebar.presented = false
            // A row's selection action (SidebarView.focusSelectionList): the
            // list stop takes focus only while presented, so a hidden one
            // leaves the page's focus where it is, not to the window.
            check(browser.makeFirstResponder(page) && (browser.firstResponder as? NSText)?.delegate === page, "the page has focus")
            sidebar.focusIfPresented()
            check((browser.firstResponder as? NSText)?.delegate === page, "hidden, the selection action leaves the page's focus")
            sidebar.presented = true
            sidebar.focusIfPresented()
            check(browser.firstResponder === sidebar, "presented, the list stop takes focus")
            // A row's Rename (SidebarView.beginTitleEditing): only in a key
            // window, the owner's reveal runs whatever the presentation, as a
            // hide in motion still reports presented, and the edit begins only
            // once the sidebar is presented.
            var reveals = 0
            check(sidebar.presentsForEditing(reveal: { reveals += 1 }) && reveals == 0, "a window that is not key reveals nothing")
            sidebar.presented = false
            check(!sidebar.presentsForEditing(reveal: { reveals += 1 }) && reveals == 0, "nor edits while hidden")
            let keyLike = KeyLikeWindow(contentRect: NSRect(x: -10_000, y: -10_000, width: 300, height: 300),
                                        styleMask: [.titled], backing: .buffered, defer: false)
            keyLike.isReleasedWhenClosed = false
            let renamed = ListStopView(frame: NSRect(x: 0, y: 0, width: 228, height: 300)); keyLike.contentView?.addSubview(renamed)
            check(renamed.presentsForEditing(reveal: { reveals += 1 }) && reveals == 1,
                  "in motion and still presented, the owner's reveal runs and settles it first")
            renamed.presented = false
            check(renamed.presentsForEditing(reveal: { reveals += 1; renamed.presented = true }) && reveals == 2,
                  "hidden, the owner floats it in and the edit begins")
            renamed.presented = false
            check(!renamed.presentsForEditing(reveal: { reveals += 1 }) && reveals == 3,
                  "an owner that cannot reveal it refuses the edit")
            check(!renamed.presentsForEditing(reveal: nil), "and without an owner it stays refused")
            keyLike.close()
            browser.close()
        }
        print("Sidebar accessibility component checks: \(count) passed")
    }
}

/// A 28-point focus-ring mask drawn into a bitmap.
@MainActor private func mask(_ view: NSView) -> NSBitmapImageRep {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 28, pixelsHigh: 28, bitsPerSample: 8,
                                  samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                  bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    NSColor.black.setFill(); view.drawFocusRingMask()
    NSGraphicsContext.restoreGraphicsState()
    return bitmap
}

private final class FlippedView: NSView { override var isFlipped: Bool { true } }
/// Answers key without ever being ordered in or made key.
private final class KeyLikeWindow: NSWindow { override var isKeyWindow: Bool { true } }
/// The sidebar view: the list's keyboard stop (SidebarView.canBecomeKeyView).
private final class ListStopView: NSView, OffscreenPresenting {
    /// SidebarView.isPresented: a hidden sidebar's list is no stop and takes no focus.
    var presented = true
    var isPresented: Bool { presented }
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func becomeFirstResponder() -> Bool { presented && super.becomeFirstResponder() }
    override var canBecomeKeyView: Bool { super.canBecomeKeyView && presented }
}
/// Places its children only in layout, as SpaceCreationView does: the name field
/// is added first, but the icon button leads it.
private final class CreationLikeView: NSView {
    let name = NSTextField(string: "name"), icon = ActionButton("Icon")
    override var isFlipped: Bool { true }
    override init(frame: NSRect) {
        super.init(frame: frame)
        name.identifier = .init("name"); icon.identifier = .init("icon")
        name.frame = .zero; addSubview(name); addSubview(icon); needsLayout = true
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func layout() {
        super.layout()
        icon.frame = NSRect(x: 5, y: 5, width: 26, height: 26)
        name.frame = NSRect(x: 33, y: 8, width: 100, height: 21)
    }
}
