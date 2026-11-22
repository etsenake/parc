import AppKit
import Testing
@testable import Parc
@testable import ParcCore
@testable import ParcKit
@testable import ParcSidebar

@MainActor
struct ParcContextMenuLayoutTests {
    final class Recorder: NSObject, NSMenuDelegate {
        var log: [String] = []
        @objc func record(_ sender: NSMenuItem) { log.append("perform " + sender.title) }
        func menuWillOpen(_ menu: NSMenu) { log.append("open " + menu.title) }
        func menuDidClose(_ menu: NSMenu) { log.append("close " + menu.title) }
    }

    @MainActor final class SidePanelToggle: NSObject, NSMenuItemValidation {
        var open = false
        private let recorder: Recorder
        init(recorder: Recorder) { self.recorder = recorder }
        @objc func toggle(_ sender: NSMenuItem) { recorder.log.append("perform " + sender.title); open.toggle() }
        func validateMenuItem(_ item: NSMenuItem) -> Bool {
            item.title = open ? "Close Side Panel" : "Open Side Panel"
            return true
        }
    }

    @MainActor final class Menus {
        let recorder = Recorder()
        lazy var toggle = SidePanelToggle(recorder: recorder)

        func item(_ title: String, state: NSControl.StateValue = .off, enabled: Bool = true) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: #selector(Recorder.record(_:)), keyEquivalent: "")
            item.target = recorder; item.state = state; item.isEnabled = enabled
            return item
        }

        func extensionMenu() -> NSMenu {
            let access = NSMenu(title: "access")
            access.autoenablesItems = false
            for (title, state) in [("Ask on Every Visit", NSControl.StateValue.off), ("Always on example.com", .on),
                                   ("Always on All Sites", .off)] { access.addItem(item(title, state: state)) }
            let menu = NSMenu(title: "root")
            menu.autoenablesItems = false
            menu.delegate = recorder
            menu.addItem(item("uBlock Origin Lite"))
            menu.addItem(.separator())
            let site = NSMenuItem(title: "This Can Read and Change Site Data", action: nil, keyEquivalent: "")
            site.submenu = access
            menu.addItem(site)
            menu.addItem(.separator())
            for title in ["Options", "Remove from Parc…", "Unpin"] { menu.addItem(item(title)) }
            menu.addItem(item("Open Side Panel", enabled: false))
            menu.items.last?.toolTip = "Extension side panels are currently unavailable."
            menu.addItem(.separator())
            for title in ["Manage Extension", "View Web Permissions"] { menu.addItem(item(title)) }
            return menu
        }

        func sidePanelMenu() -> NSMenu {
            let menu = NSMenu(title: "root")
            menu.delegate = recorder
            menu.addItem(item("Options"))
            let panel = NSMenuItem(title: "Open Side Panel", action: #selector(SidePanelToggle.toggle(_:)), keyEquivalent: "")
            panel.target = toggle
            menu.addItem(panel)
            return menu
        }
    }

    private typealias M = ParcContextMenuMetrics
    private static let tile = NSRect(x: 100, y: 500, width: 48, height: 32)
    private static let size = NSSize(width: 200, height: 300)
    private static let colors = ParcMenuColors(theme: SpaceTheme())

    @Test func theCardHangsRightOfTheTileWithItsFirstRowLevelWithIt() {
        let right = M.frame(card: Self.size, reach: Self.size.width, beside: Self.tile, right: true, regions: [NSRect(x: 0, y: 0, width: 1000, height: 800)])
        #expect(right.right)
        #expect(right.frame.minX == Self.tile.maxX + M.gap)
        #expect(right.frame.maxY == Self.tile.maxY + M.inset)
    }

    @Test func withoutRoomOnTheRightItHangsLeft() {
        let edge = M.frame(card: Self.size, reach: Self.size.width, beside: NSRect(x: 850, y: 500, width: 48, height: 32), right: true,
                           regions: [NSRect(x: 0, y: 0, width: 1000, height: 800)])
        #expect(!edge.right && edge.frame.maxX == 850 - M.gap)
    }

    @Test func nearTheBottomOfTheScreenItMovesUpOntoIt() {
        let low = M.frame(card: Self.size, reach: Self.size.width, beside: NSRect(x: 100, y: 40, width: 48, height: 32), right: true,
                          regions: [NSRect(x: 0, y: 20, width: 1000, height: 800)])
        #expect(low.frame.minY == 20)
    }

    @Test func aSubmenuKeepsItsParentsSide() {
        #expect(M.frame(card: Self.size, reach: Self.size.width, beside: Self.tile, right: false, regions: []).frame.maxX == Self.tile.minX - M.gap)
    }

    @Test func withRoomOnNeitherSideItTakesTheRoomierOneInsideTheBounds() {
        let cramped = M.frame(card: Self.size, reach: Self.size.width, beside: NSRect(x: 150, y: 500, width: 100, height: 32), right: true,
                              regions: [NSRect(x: 0, y: 0, width: 300, height: 800)])
        #expect(!cramped.right && cramped.frame.minX == 0)
    }

    @Test func aMenuWhoseSubmenuWouldNotFitOnTheRightOpensOnTheLeftWithIt() {
        let chain = M.frame(card: Self.size, reach: Self.size.width + M.gap + 180, beside: NSRect(x: 500, y: 500, width: 100, height: 32),
                            right: true, regions: [NSRect(x: 0, y: 0, width: 900, height: 800)])
        #expect(!chain.right)
    }

    @Test func aWindowTooSmallForTheMenuBesideTheCardLeavesItOnTheScreen() {
        let popup = M.frame(card: Self.size, reach: Self.size.width, beside: NSRect(x: 100, y: 500, width: 232, height: 32), right: true,
                            regions: [NSRect(x: 100, y: 200, width: 300, height: 400), NSRect(x: 0, y: 0, width: 1000, height: 800)])
        #expect(popup.right && popup.frame.minX == 336)
    }

    @Test func aTileOnACardAboveItsWindowKeepsTheMenuLevelWithItOnTheScreen() {
        let above = M.frame(card: NSSize(width: 200, height: 176), reach: 200, beside: NSRect(x: 100, y: 640, width: 232, height: 32),
                            right: true, regions: [NSRect(x: 0, y: 0, width: 600, height: 360), NSRect(x: 0, y: 0, width: 1440, height: 875)])
        #expect(above.frame.maxY == 672 + M.inset)
    }

    @Test func theReachCountsEveryLevelOfSubmenus() {
        let menus = Menus()
        let deep = NSMenu(title: "deep"), middle = NSMenu(title: "middle"), top = NSMenu(title: "top")
        deep.addItem(menus.item("A Rather Long Third-Level Choice"))
        let toDeep = NSMenuItem(title: "Deeper", action: nil, keyEquivalent: ""); toDeep.submenu = deep; middle.addItem(toDeep)
        let toMiddle = NSMenuItem(title: "More", action: nil, keyEquivalent: ""); toMiddle.submenu = middle; top.addItem(toMiddle)
        let view = ParcContextMenuView(menu: top, colors: Self.colors)
        #expect(view.reach == view.card.width + 2 * M.gap + ParcContextMenuView.cardWidth([toDeep]) + ParcContextMenuView.cardWidth(deep.items))
    }

    @Test func aHiddenFirstItemTakesItsSeparatorWithIt() {
        let menu = Menus().extensionMenu()
        menu.items[0].isHidden = true
        let shown = M.shownItems(menu)
        #expect(shown.first?.title == "This Can Read and Change Site Data")
        #expect(!shown.contains { $0.isHidden })
    }

    @Test func rowsAreThirtyTwoPointsAndSeparatorsTheDockMenusSeventeen() {
        let view = ParcContextMenuView(menu: Menus().extensionMenu(), colors: Self.colors)
        #expect(view.items.indices.filter { !view.items[$0].isSeparatorItem }.allSatisfy { view.rows[$0].height == M.rowHeight })
        #expect(view.items.indices.filter { view.items[$0].isSeparatorItem }.allSatisfy { view.rows[$0].height == SidebarPlusMenuView.divider })
    }

    @Test func rowsSitInsideTheCardsInsetFromTheTop() {
        let view = ParcContextMenuView(menu: Menus().extensionMenu(), colors: Self.colors)
        #expect(view.rows[0].maxY == view.card.maxY - M.inset)
        #expect(view.rows[0].minX == view.card.minX + M.inset)
    }

    @Test func theCardFitsItsTitlesWithinBounds() {
        let view = ParcContextMenuView(menu: Menus().extensionMenu(), colors: Self.colors)
        #expect(view.card.width >= M.minimumWidth && view.card.width <= M.maximumWidth)
    }

    @Test func aSeparatorIsNotARow() {
        let view = ParcContextMenuView(menu: Menus().extensionMenu(), colors: Self.colors)
        #expect(view.row(at: NSPoint(x: view.rows[1].midX, y: view.rows[1].midY)) == nil)
    }

    @Test func voiceOverSeesEachRowAsAMenuItem() {
        let view = ParcContextMenuView(menu: Menus().extensionMenu(), colors: Self.colors)
        #expect(view.accessibilityChildren()?.count == view.items.filter { !$0.isSeparatorItem }.count)
    }

    private func label(_ view: ParcContextMenuView, _ row: Int) -> String? {
        view.accessibilityChildren()?.lazy.compactMap { $0 as? NSAccessibilityElement }
            .first { $0.accessibilityFrameInParentSpace() == view.rows[row] }?.accessibilityLabel()
    }

    @Test func checkingAnOpenMenuAgainLeavesUnchangedRowsAlone() {
        let menus = Menus()
        let live = ParcContextMenuView(menu: menus.sidePanelMenu(), colors: Self.colors)
        #expect(live.refresh().isEmpty)
        #expect(live.items[1].title == "Open Side Panel")
    }

    @Test func aRowWhoseActionChangedWhileTheMenuIsOpenTakesItsNewLabel() {
        let menus = Menus()
        let live = ParcContextMenuView(menu: menus.sidePanelMenu(), colors: Self.colors)
        menus.toggle.open = true
        #expect(live.refresh() == [1])
        #expect(live.items[1].title == "Close Side Panel")
        #expect(label(live, 1) == "Close Side Panel")
    }

    @Test func theNewLabelCountsAsSeen() {
        let menus = Menus()
        let live = ParcContextMenuView(menu: menus.sidePanelMenu(), colors: Self.colors)
        menus.toggle.open = true
        live.refresh()
        #expect(live.refresh().isEmpty)
    }
}
