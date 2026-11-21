import AppKit
import Testing
@testable import Parc

private final class HoverKeyWindow: NSWindow {
    var key = true
    override var isKeyWindow: Bool { key }
}

private final class HitCountingContentView: NSView {
    var hitTestCount = 0
    override func hitTest(_ point: NSPoint) -> NSView? {
        hitTestCount += 1
        return super.hitTest(point)
    }
}

@MainActor
struct FavoriteTileTests {
    @MainActor private final class AccessibleTile {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 100),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        let tile = FavoriteTile(title: "Original Favorite", monogram: "O", url: "https://example.test/original")
        var available = true
        var activations = 0
        var menuQueries = 0
        var actionQueries = 0

        init(attached: Bool) {
            window.isReleasedWhenClosed = false
            tile.frame = NSRect(x: 10, y: 10, width: 60, height: 47)
            tile.canActivate = { [unowned self] in available }
            tile.activate = { [unowned self] in activations += 1; return true }
            tile.makeMenu = { [unowned self] in
                menuQueries += 1
                let menu = NSMenu()
                menu.addItem(withTitle: available ? "Current" : "Unavailable", action: nil, keyEquivalent: "")
                return menu
            }
            tile.makeAccessibilityActions = { [unowned self] in
                actionQueries += 1
                return available ? [NSAccessibilityCustomAction(name: "Original Action", handler: { [unowned self] in available })] : []
            }
            if attached { window.contentView!.addSubview(tile) }
        }

        deinit { MainActor.assumeIsolated { window.close() } }

        func rightMouseDown() -> NSEvent {
            NSEvent.mouseEvent(with: .rightMouseDown, location: .zero, modifierFlags: [], timestamp: 0,
                               windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 0)!
        }
    }

    @Test func theFullTitleNotTheMonogramIsSpoken() {
        let fixture = AccessibleTile(attached: false)
        #expect(fixture.tile.accessibilityTitle() == "Original Favorite")
    }

    @Test func theTitleIsNotRepeatedAsADescription() {
        let fixture = AccessibleTile(attached: false)
        #expect(fixture.tile.accessibilityLabel()?.isEmpty != false)
    }

    @Test func aTileIsAButtonDescribedAsAFavorite() {
        let fixture = AccessibleTile(attached: false)
        let tile = fixture.tile
        #expect(tile.cell?.accessibilityRole() == .button)
        #expect(tile.accessibilityRoleDescription() == "Favorite")
    }

    @Test(arguments: [(["Mail"], "Mail"), (["Docs", "Calendar"], "Docs, Calendar"), ([String](), "Favorite item")])
    func theSpokenTitleJoinsEachPageOrFallsBackToAPlaceholder(titles: [String], expected: String) {
        #expect(FavoriteAccessibilityTitle.text(titles) == expected)
    }

    @Test func aRetainedTileRefreshesItsSpokenTitle() {
        let fixture = AccessibleTile(attached: false)
        let tile = fixture.tile
        tile.update(title: FavoriteAccessibilityTitle.text(["Docs", "Calendar"]), monogram: "D", url: "https://example.test/original",
                    owner: .init(tabID: UUID(), profileID: UUID(), spaceID: UUID(), createdAt: Date()))
        #expect(tile.accessibilityTitle() == "Docs, Calendar")
    }

    @Test func theHelpIsTheExactURL() {
        let fixture = AccessibleTile(attached: false)
        #expect(fixture.tile.accessibilityHelp() == "https://example.test/original")
    }

    @Test func aDetachedTileCannotActivate() {
        let fixture = AccessibleTile(attached: false)
        #expect(!fixture.tile.accessibilityPerformPress())
    }

    @Test func aDetachedTileOffersNoActions() {
        let fixture = AccessibleTile(attached: false)
        #expect(fixture.tile.accessibilityCustomActions()?.isEmpty == true)
    }

    @Test func detachedQueriesDoNotTouchTheOriginalOwner() {
        let fixture = AccessibleTile(attached: false)
        _ = fixture.tile.accessibilityPerformPress()
        _ = fixture.tile.accessibilityCustomActions()
        #expect(fixture.menuQueries == 0)
        #expect(fixture.actionQueries == 0)
    }

    @Test func anAttachedTileIsAvailable() {
        let fixture = AccessibleTile(attached: true)
        #expect(fixture.tile.isAccessibilityEnabled())
    }

    @Test func anAccessibilityPressReachesTheRealActivationCallbackOnce() {
        let fixture = AccessibleTile(attached: true)
        #expect(fixture.tile.accessibilityPerformPress())
        #expect(fixture.activations == 1)
    }

    @Test func selectionIsReportedIndependentlyAndDoesNotActivate() {
        let fixture = AccessibleTile(attached: true)
        fixture.tile.selected = true
        #expect(fixture.tile.isAccessibilitySelected())
        #expect(fixture.activations == 0)
    }

    @Test func eachActionsQueryUsesAFreshFactory() {
        let fixture = AccessibleTile(attached: true)
        let actions = fixture.tile.accessibilityCustomActions()
        #expect(actions?.count == 1)
        #expect(fixture.actionQueries == 1)
    }

    @Test func anUnavailableOwnerIsReflected() {
        let fixture = AccessibleTile(attached: true)
        fixture.available = false
        #expect(!fixture.tile.isAccessibilityEnabled())
    }

    @Test func aStaleOwnerCannotActivate() {
        let fixture = AccessibleTile(attached: true)
        fixture.available = false
        #expect(!fixture.tile.accessibilityPerformPress())
        #expect(fixture.activations == 0)
    }

    @Test func actionsRefreshOnEveryQuery() {
        let fixture = AccessibleTile(attached: true)
        _ = fixture.tile.accessibilityCustomActions()
        fixture.available = false
        #expect(fixture.tile.accessibilityCustomActions()?.isEmpty == true)
        #expect(fixture.actionQueries == 2)
    }

    @Test func aPreviouslyReturnedActionStillRevalidates() throws {
        let fixture = AccessibleTile(attached: true)
        let actions = try #require(fixture.tile.accessibilityCustomActions())
        fixture.available = false
        #expect(actions[0].handler?() == false)
    }

    @Test func theContextMenuResolvesTheCurrentOwner() {
        let fixture = AccessibleTile(attached: true)
        #expect(fixture.tile.menu(for: fixture.rightMouseDown())?.items.first?.title == "Current")
        #expect(fixture.menuQueries == 1)
    }

    @Test func theMenuIsNotCachedAcrossStateChanges() {
        let fixture = AccessibleTile(attached: true)
        _ = fixture.tile.menu(for: fixture.rightMouseDown())
        fixture.available = false
        #expect(fixture.tile.menu(for: fixture.rightMouseDown())?.items.first?.title == "Unavailable")
        #expect(fixture.menuQueries == 2)
    }

    @Test func aRemovedTileCannotRequestAMenu() {
        let fixture = AccessibleTile(attached: true)
        fixture.tile.removeFromSuperview()
        #expect(fixture.tile.menu(for: fixture.rightMouseDown()) == nil)
        #expect(fixture.menuQueries == 0)
    }

    @Test func aRemovedTileCannotDispatch() {
        let fixture = AccessibleTile(attached: true)
        fixture.tile.removeFromSuperview()
        #expect(!fixture.tile.accessibilityPerformPress())
    }

    @MainActor private final class Hover {
        let window = HoverKeyWindow(contentRect: NSRect(x: -10000, y: -10000, width: 200, height: 100),
                                    styleMask: [.borderless], backing: .buffered, defer: false)
        let content = HitCountingContentView(frame: NSRect(x: 0, y: 0, width: 200, height: 100))
        let tile = FavoriteTile(title: "Hover Favorite", monogram: "H", url: "https://example.test/hover")
        let inside = NSPoint(x: 50, y: 40)
        let insideAgain = NSPoint(x: 55, y: 42)
        let outside = NSPoint(x: 150, y: 80)

        init(attached: Bool = true) {
            window.isReleasedWhenClosed = false
            window.contentView = content
            tile.frame = NSRect(x: 20, y: 20, width: 60, height: 47)
            tile.applyPalette(isDark: false, glyphColor: .labelColor)
            if attached {
                content.addSubview(tile)
                tile.layoutSubtreeIfNeeded()
            }
        }

        deinit { MainActor.assumeIsolated { window.close() } }

        func crossing(_ type: NSEvent.EventType, _ point: NSPoint) -> NSEvent {
            NSEvent.enterExitEvent(with: type, location: point, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
                                   context: nil, eventNumber: 1, trackingNumber: 0, userData: nil)!
        }

        func moved(_ point: NSPoint) -> NSEvent {
            NSEvent.mouseEvent(with: .mouseMoved, location: point, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
                               context: nil, eventNumber: 1, clickCount: 0, pressure: 0)!
        }

        func enter() {
            content.hitTestCount = 0
            tile.mouseEntered(with: crossing(.mouseEntered, inside))
        }
    }

    @Test func aTileStartsUnhovered() {
        let hover = Hover(attached: false)
        #expect(!hover.tile.isPointerHovered)
    }

    @Test func enteringHitTestsAndSetsHover() {
        let hover = Hover()
        hover.enter()
        #expect(hover.tile.isPointerHovered)
        #expect(hover.content.hitTestCount >= 1)
    }

    @Test func movingInsideAnAlreadyHoveredTileSkipsTheHitTest() {
        let hover = Hover()
        hover.enter()
        let afterEnter = hover.content.hitTestCount
        hover.tile.mouseMoved(with: hover.moved(hover.inside))
        hover.tile.mouseMoved(with: hover.moved(hover.insideAgain))
        #expect(hover.content.hitTestCount == afterEnter)
    }

    @Test func theHoverBitStaysSetWhileThePointerRemainsInside() {
        let hover = Hover()
        hover.enter()
        hover.tile.mouseMoved(with: hover.moved(hover.insideAgain))
        #expect(hover.tile.isPointerHovered)
    }

    @Test func leavingTheTileBoundsHitTestsAgain() {
        let hover = Hover()
        hover.enter()
        let afterEnter = hover.content.hitTestCount
        hover.tile.mouseMoved(with: hover.moved(hover.outside))
        #expect(hover.content.hitTestCount > afterEnter)
    }

    @Test func thePointerOutsideTheTileClearsHover() {
        let hover = Hover()
        hover.enter()
        hover.tile.mouseMoved(with: hover.moved(hover.outside))
        #expect(!hover.tile.isPointerHovered)
    }

    @Test func reEnteringSetsHoverAgain() {
        let hover = Hover()
        hover.enter()
        hover.tile.mouseMoved(with: hover.moved(hover.outside))
        hover.enter()
        #expect(hover.tile.isPointerHovered)
        #expect(hover.content.hitTestCount >= 1)
    }

    @Test func exitingClearsHoverWithoutAnotherHitTest() {
        let hover = Hover()
        hover.enter()
        let afterEnter = hover.content.hitTestCount
        hover.tile.mouseExited(with: hover.crossing(.mouseExited, hover.outside))
        #expect(!hover.tile.isPointerHovered)
        #expect(hover.content.hitTestCount == afterEnter)
    }

    @Test func aNonKeyWindowDoesNotHover() {
        let hover = Hover()
        hover.window.key = false
        hover.enter()
        #expect(!hover.tile.isPointerHovered)
    }

    @MainActor private final class Layout {
        let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 200, height: 100),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        let tile = FavoriteTile(title: "Layout Favorite", monogram: "L", url: "https://example.test/layout")

        init() {
            window.isReleasedWhenClosed = false
            tile.frame = NSRect(x: 10, y: 10, width: 60, height: 47)
            window.contentView!.addSubview(tile)
        }

        deinit { MainActor.assumeIsolated { window.close() } }

        func layoutWrites() -> Int { SidebarLayerWrites.count(byLayersOf: tile) { tile.layout() } }

        func settled() -> Layout {
            _ = layoutWrites()
            return self
        }
    }

    @Test func theFirstLayoutWritesItsLayers() {
        let layout = Layout()
        #expect(layout.layoutWrites() > 0)
    }

    @Test func aNoOpLayoutSkipsTheTransactionRewrite() {
        let layout = Layout().settled()
        #expect(layout.layoutWrites() == 0)
    }

    @Test func aBoundsChangeStillRewritesLayers() {
        let layout = Layout().settled()
        layout.tile.setFrameSize(NSSize(width: 80, height: 47))
        #expect(layout.layoutWrites() > 0)
    }

    @Test func aFollowUpLayoutAtTheNewSizeIsANoOp() {
        let layout = Layout().settled()
        layout.tile.setFrameSize(NSSize(width: 80, height: 47))
        _ = layout.layoutWrites()
        #expect(layout.layoutWrites() == 0)
    }

    @Test func aCellCountChangeStillRewritesChildFramesAndTheOutline() {
        let layout = Layout().settled()
        layout.tile.setPages(["A", "B"], orientation: .horizontal)
        #expect(layout.layoutWrites() > 0)
    }

    @Test func aFollowUpLayoutAfterSplitPagesIsANoOp() {
        let layout = Layout().settled()
        layout.tile.setPages(["A", "B"], orientation: .horizontal)
        _ = layout.layoutWrites()
        #expect(layout.layoutWrites() == 0)
    }

    @Test func anOrientationChangeStillRewritesChildFramesAndTheOutline() {
        let layout = Layout().settled()
        layout.tile.setPages(["A", "B"], orientation: .horizontal)
        _ = layout.layoutWrites()
        layout.tile.setPages(["A", "B"], orientation: .vertical)
        #expect(layout.layoutWrites() > 0)
    }

    private func selectedLayoutWithBadge() -> (Layout, CALayer) {
        let layout = Layout().settled()
        layout.tile.selected = true
        layout.tile.setOverlays(FavoriteTileOverlayState(badge: FavoriteTileBadge(favicon: nil)))
        let badge = layout.tile.overlays.badgeView!.layer!
        badge.anchorPoint = .zero
        return (layout, badge)
    }

    @Test func aSelectedNoOpLayoutStillSkipsFrameRewrites() {
        let (layout, _) = selectedLayoutWithBadge()
        _ = layout.layoutWrites()
        #expect(layout.layoutWrites() == 0)
    }

    @Test func theOverlaysLayoutStillRunsOnTheSkipPath() {
        let (layout, badge) = selectedLayoutWithBadge()
        _ = layout.layoutWrites()
        #expect(badge.anchorPoint == CGPoint(x: 0.5, y: 0.5))
    }
}
