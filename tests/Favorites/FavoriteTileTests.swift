import AppKit

/// Key state the test sets so hover resolution can run without activating a real window.
private final class HoverKeyWindow: NSWindow {
    var key = true
    override var isKeyWindow: Bool { key }
}

/// Counts contentView hitTest calls so the mouseMoved no-op skip is observable.
private final class HitCountingContentView: NSView {
    var hitTestCount = 0
    override func hitTest(_ point: NSPoint) -> NSView? {
        hitTestCount += 1
        return super.hitTest(point)
    }
}

@main struct FavoriteTileTests {
    @MainActor static func main() {
        _ = NSApplication.shared
        GeometryWrites.install()
        var checks = 0
        func check(_ condition: @autoclosure () -> Bool, _ message: String) {
            precondition(condition(), message); checks += 1
        }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 100),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let tile = FavoriteTile(title: "Original Favorite", monogram: "O", url: "https://example.test/original")
        tile.frame = NSRect(x: 10, y: 10, width: 60, height: 47)
        var available = true, activations = 0, menuQueries = 0, actionQueries = 0
        tile.canActivate = { available }
        tile.activate = { activations += 1; return true }
        tile.makeMenu = {
            menuQueries += 1
            let menu = NSMenu(); menu.addItem(withTitle: available ? "Current" : "Unavailable", action: nil, keyEquivalent: "")
            return menu
        }
        tile.makeAccessibilityActions = {
            actionQueries += 1
            return available ? [NSAccessibilityCustomAction(name: "Original Action", handler: { available })] : []
        }
        check(tile.accessibilityTitle() == "Original Favorite", "Full title, not monogram, is spoken")
        check(tile.accessibilityLabel()?.isEmpty != false, "Title is not repeated as a description")
        check(tile.cell?.accessibilityRole() == .button && tile.accessibilityRoleDescription() == "Favorite",
              "Recovered button role and Favorite description")
        check(FavoriteAccessibilityTitle.text(["Mail"]) == "Mail", "Single Favorite speaks its title")
        check(FavoriteAccessibilityTitle.text(["Docs", "Calendar"]) == "Docs, Calendar",
              "Untitled split speaks each page joined by a comma")
        check(FavoriteAccessibilityTitle.text([]) == "Favorite item", "Empty list uses the recovered placeholder")
        tile.update(title: FavoriteAccessibilityTitle.text(["Docs", "Calendar"]), monogram: "D",
                    url: "https://example.test/original",
                    owner: .init(tabID: UUID(), profileID: UUID(), spaceID: UUID(), createdAt: Date()))
        check(tile.accessibilityTitle() == "Docs, Calendar", "Retained tile refreshes its spoken title")
        check(tile.accessibilityHelp() == "https://example.test/original", "Exact URL help")
        check(!tile.accessibilityPerformPress(), "Detached tile must not activate")
        check(tile.accessibilityCustomActions()?.isEmpty == true, "Detached actions unavailable")
        check(menuQueries == 0 && actionQueries == 0, "Detached queries do not touch original owner")
        window.contentView!.addSubview(tile)
        check(tile.isAccessibilityEnabled(), "Attached original available")
        check(tile.accessibilityPerformPress(), "AX press reaches real activation callback")
        check(activations == 1, "One AX press dispatch")
        tile.selected = true
        check(tile.isAccessibilitySelected(), "Selection is reported independently")
        check(activations == 1, "Selection presentation does not activate")
        let actions = tile.accessibilityCustomActions()!
        check(actions.count == 1 && actionQueries == 1, "Fresh action factory")
        available = false
        check(!tile.isAccessibilityEnabled(), "Unavailable owner reflected")
        check(!tile.accessibilityPerformPress() && activations == 1, "Stale owner cannot activate")
        check(tile.accessibilityCustomActions()?.isEmpty == true && actionQueries == 2, "Actions refresh on query")
        check(actions[0].handler?() == false, "Previously returned native action still revalidates")
        available = true
        let event = NSEvent.mouseEvent(with: .rightMouseDown, location: .zero, modifierFlags: [], timestamp: 0,
                                      windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 0)!
        check(tile.menu(for: event)?.items.first?.title == "Current" && menuQueries == 1, "Context resolves current owner")
        available = false
        check(tile.menu(for: event)?.items.first?.title == "Unavailable" && menuQueries == 2, "Menu not cached across state changes")
        tile.removeFromSuperview()
        check(tile.menu(for: event) == nil && menuQueries == 2, "Removed tile cannot request a menu")
        check(!tile.accessibilityPerformPress(), "Removed tile cannot dispatch")
        window.close()

        // Hover: enter/exit still set and clear; mouseMoved inside an already
        // hovered tile skips contentView.hitTest (true no-op).
        let hoverWindow = HoverKeyWindow(contentRect: NSRect(x: -10000, y: -10000, width: 200, height: 100),
                                         styleMask: [.borderless], backing: .buffered, defer: false)
        hoverWindow.isReleasedWhenClosed = false
        let content = HitCountingContentView(frame: NSRect(x: 0, y: 0, width: 200, height: 100))
        hoverWindow.contentView = content
        let hoverTile = FavoriteTile(title: "Hover Favorite", monogram: "H", url: "https://example.test/hover")
        hoverTile.frame = NSRect(x: 20, y: 20, width: 60, height: 47)
        hoverTile.applyPalette(isDark: false, glyphColor: .labelColor)
        content.addSubview(hoverTile)
        hoverTile.layoutSubtreeIfNeeded()
        func crossing(_ type: NSEvent.EventType, _ point: NSPoint) -> NSEvent {
            NSEvent.enterExitEvent(with: type, location: point, modifierFlags: [], timestamp: 0,
                                   windowNumber: hoverWindow.windowNumber, context: nil, eventNumber: 1,
                                   trackingNumber: 0, userData: nil)!
        }
        func moved(_ point: NSPoint) -> NSEvent {
            NSEvent.mouseEvent(with: .mouseMoved, location: point, modifierFlags: [], timestamp: 0,
                               windowNumber: hoverWindow.windowNumber, context: nil, eventNumber: 1,
                               clickCount: 0, pressure: 0)!
        }
        let inside = NSPoint(x: 50, y: 40)
        let insideAgain = NSPoint(x: 55, y: 42)
        let outside = NSPoint(x: 150, y: 80)
        check(!hoverTile.isPointerHovered, "Detached path starts unhovered")
        content.hitTestCount = 0
        hoverTile.mouseEntered(with: crossing(.mouseEntered, inside))
        check(hoverTile.isPointerHovered && content.hitTestCount >= 1, "Enter hit-tests and sets hover")
        let afterEnter = content.hitTestCount
        hoverTile.mouseMoved(with: moved(inside))
        hoverTile.mouseMoved(with: moved(insideAgain))
        check(content.hitTestCount == afterEnter, "mouseMoved inside an already hovered tile skips hitTest")
        check(hoverTile.isPointerHovered, "Hover bit stays set while the pointer remains inside the tile")
        hoverTile.mouseMoved(with: moved(outside))
        check(content.hitTestCount > afterEnter, "Leaving tile bounds hit-tests again")
        check(!hoverTile.isPointerHovered, "Pointer outside the tile clears hover")
        content.hitTestCount = 0
        hoverTile.mouseEntered(with: crossing(.mouseEntered, inside))
        check(hoverTile.isPointerHovered && content.hitTestCount >= 1, "Re-enter sets hover again")
        hoverTile.mouseExited(with: crossing(.mouseExited, outside))
        check(!hoverTile.isPointerHovered, "mouseExited clears hover without requiring another hitTest")
        hoverWindow.key = false
        hoverTile.mouseEntered(with: crossing(.mouseEntered, inside))
        check(!hoverTile.isPointerHovered, "Non-key window does not hover")
        hoverWindow.close()

        // N4: identical-frame layout skips CATransaction layer writes; bounds,
        // orientation, and cell-count changes still rewrite; wash stays reachable.
        let layoutWindow = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 200, height: 100),
                                    styleMask: [.borderless], backing: .buffered, defer: false)
        layoutWindow.isReleasedWhenClosed = false
        let layoutTile = FavoriteTile(title: "Layout Favorite", monogram: "L", url: "https://example.test/layout")
        layoutTile.frame = NSRect(x: 10, y: 10, width: 60, height: 47)
        layoutWindow.contentView!.addSubview(layoutTile)
        func layoutWrites() -> Int { GeometryWrites.layerWrites(by: layoutTile) { layoutTile.layout() }.count }
        check(layoutWrites() > 0, "first FavoriteTile layout writes its layers")
        check(layoutWrites() == 0, "no-op FavoriteTile layout skips CATransaction rewrite")
        layoutTile.setFrameSize(NSSize(width: 80, height: 47))
        check(layoutWrites() > 0, "a FavoriteTile bounds change still rewrites layers")
        check(layoutWrites() == 0, "follow-up FavoriteTile layout at the new size remains a no-op")
        layoutTile.setPages(["A", "B"], orientation: .horizontal)
        check(layoutWrites() > 0, "cell-count change still rewrites child frames and outline")
        check(layoutWrites() == 0, "follow-up layout after split pages remains a no-op")
        layoutTile.setPages(["A", "B"], orientation: .vertical)
        check(layoutWrites() > 0, "orientation change still rewrites child frames and outline")
        layoutTile.selected = true
        layoutTile.setOverlays(FavoriteTileOverlayState(badge: FavoriteTileBadge(favicon: nil)))
        let badge = layoutTile.overlays.badgeView!.layer!
        // AppKit can reset a new backing layer's anchor at its first display.
        badge.anchorPoint = .zero
        check(layoutWrites() == 0, "selected no-op layout still skips frame rewrites")
        check(badge.anchorPoint == CGPoint(x: 0.5, y: 0.5),
              "overlays.layout still runs on the FavoriteTile layout skip path")
        layoutTile.removeFromSuperview()
        layoutWindow.close()

        print("\(checks) Favorite control assertions passed (no browser or Apple Event execution)")
    }
}
