import AppKit
import Testing
@testable import Parc
@testable import ParcCore

@MainActor
struct SidebarListChromeTests {
    @MainActor private final class Listed {
        let sidebar = SidebarView(frame: NSRect(x: 0, y: 0, width: 240, height: 600))
        let window: SidebarTestWindow
        let space: BrowserSpace
        let single: BrowserTab
        let left: BrowserTab
        let right: BrowserTab
        let favorite: BrowserTab
        var state: BrowserState
        var opened = 0

        static func tab(_ name: String, _ kind: TabKind, _ space: BrowserSpace) -> BrowserTab {
            BrowserTab(id: UUID(), spaceID: space.id, profileID: space.profileID, url: "https://example.test/\(name)", title: name,
                       kind: kind, createdAt: Date(), lastAccessed: Date(), savedURL: "https://example.test/\(name)", savedTitle: name)
        }

        init() {
            SidebarApplicationActivity.set(true)
            window = sidebarTestWindow(containing: sidebar)
            window.pointer = NSPoint(x: -100, y: -100)
            let initial = BrowserState.initial()
            let active = initial.activeSpaceID
            space = initial.spaces.first { $0.id == active }!
            single = Self.tab("single", .today, space)
            left = Self.tab("left", .today, space)
            right = Self.tab("right", .today, space)
            favorite = Self.tab("favorite", .favorite, space)
            var state = initial
            state.tabs = [single, left, right, favorite]
            state.splitLayouts = [BrowserSplitLayout(sidebarAnchorID: left.id, spaceID: space.id, tabIDs: [left.id, right.id], widthFactors: [0.5, 0.5])]
            state.selectedTabIDs = [single.id]
            self.state = state
            sidebar.palette = ThemeChromePalette(theme: .singleColor(ThemeColor(hex: "3366CC")!), appearance: NSAppearance(named: .aqua)!)
            render(state, focused: single.id)
            sidebar.onNewTab = { [weak self] in self?.opened += 1 }
        }

        deinit {
            SidebarApplicationActivity.set(nil)
            MainActor.assumeIsolated { window.contentView = nil }
        }

        func render(_ state: BrowserState, focused: UUID) {
            sidebar.render(state: state, focusedTabID: focused, loading: [], canBack: false, canForward: false)
            sidebar.layoutSubtreeIfNeeded()
        }

        var row: SidebarNewTabRow { sidebarDescendants(sidebar).compactMap { $0 as? SidebarNewTabRow }.first! }
        var plate: SidebarRowBackgroundView { sidebarDescendants(row).compactMap { $0 as? SidebarRowBackgroundView }.first! }
        var title: SidebarChromeLabel { sidebarDescendants(row).compactMap { $0 as? SidebarChromeLabel }.first! }
        var icon: NSImageView { sidebarDescendants(row).compactMap { $0 as? NSImageView }.first! }

        func fill(of id: UUID) -> SidebarRowAppearance.Fill? {
            let tabRow = sidebarDescendants(sidebar).compactMap { $0 as? SidebarTabRow }.first { $0.tabID == id }!
            return sidebarDescendants(tabRow).compactMap { $0 as? SidebarRowBackgroundView }.first!.appearanceState.fill
        }

        func idle() -> Bool {
            !row.current && plate.appearanceState.fill == nil && !plate.appearanceState.showsShadow
                && title.textColor == SidebarNewTabAppearance.titleColor(dark: row.dark)
                && icon.contentTintColor == SidebarNewTabAppearance.plusColor(dark: row.dark)
        }

        func group() -> SidebarSplitGroupView { sidebarDescendants(sidebar).compactMap { $0 as? SidebarSplitGroupView }.first! }
    }

    @Test func atRestNewTabIsClearWithItsTitleAndPlusColours() {
        #expect(Listed().idle())
    }

    @Test func theSelectedTabIsTheCurrentItem() {
        let l = Listed()
        #expect(l.fill(of: l.single.id) == .current)
    }

    @Test func thePlaceholderGivesNewTabTheCurrentFillAndItsShadow() {
        let l = Listed()
        l.sidebar.newTabPlaceholderActive = true
        let current = SidebarRowAppearance.color(.current, dark: l.row.dark).cgColor
        #expect(l.row.current)
        #expect(l.plate.appearanceState.fill == .current)
        #expect(l.plate.appearanceState.showsShadow)
        #expect(l.plate.fillLayer.backgroundColor.map { CFEqual($0, current) } == true)
    }

    @Test func thePlaceholdersTitleAndPlusTakeThePalettesTitleColour() {
        let l = Listed()
        l.sidebar.newTabPlaceholderActive = true
        #expect(l.title.textColor == l.sidebar.palette?.title)
        #expect(l.icon.contentTintColor == l.sidebar.palette?.title)
    }

    @Test func thePlaceholderLookSwitchesWithoutATransition() {
        let l = Listed()
        l.sidebar.newTabPlaceholderActive = true
        #expect(l.plate.fillLayer.animationKeys() == nil)
        #expect(l.title.layer?.animationKeys() == nil)
    }

    @Test func hoveringKeepsTheCurrentFillOverTheHoverColour() {
        let l = Listed()
        l.sidebar.newTabPlaceholderActive = true
        l.row.button.mouseEntered(with: SidebarAreaEvent())
        #expect(l.plate.appearanceState.hovered)
        #expect(l.plate.appearanceState.fill == .current)
    }

    @Test func aMetadataTickDoesNotKeepRowsBuiltWithoutThePlaceholder() {
        let l = Listed()
        l.sidebar.newTabPlaceholderActive = true
        #expect(!l.sidebar.applyLivePageMetadata(state: l.state, focusedTabID: l.single.id, loading: [], canBack: false, canForward: false))
    }

    @Test func whileThePlaceholderHoldsTheSelectedTabIsNotCurrent() {
        let l = Listed()
        l.sidebar.newTabPlaceholderActive = true
        l.render(l.state, focused: l.single.id)
        #expect(l.row.current)
        #expect(l.fill(of: l.single.id) == nil)
    }

    @Test func onceARenderHasUsedItMetadataTicksTakeTheLivePathAgain() {
        let l = Listed()
        l.sidebar.newTabPlaceholderActive = true
        l.render(l.state, focused: l.single.id)
        #expect(l.sidebar.applyLivePageMetadata(state: l.state, focusedTabID: l.single.id, loading: [], canBack: false, canForward: false))
    }

    private func splitSelected(_ l: Listed) -> BrowserState {
        var state = l.state
        state.selectedTabIDs = [l.left.id, l.right.id]
        return state
    }

    @Test func aSelectedSplitIsNotCurrentWhilePlaceholderHoldsAndItsChildrenLoseTheGroupPlate() {
        let l = Listed()
        l.sidebar.newTabPlaceholderActive = true
        l.render(splitSelected(l), focused: l.left.id)
        #expect(!l.group().selected)
        #expect(l.group().rows.allSatisfy { !$0.splitGroupSelected })
    }

    @Test func withoutThePlaceholderTheSelectedSplitIsCurrentAgain() {
        let l = Listed()
        l.sidebar.newTabPlaceholderActive = true
        l.render(splitSelected(l), focused: l.left.id)
        l.sidebar.newTabPlaceholderActive = false
        l.render(splitSelected(l), focused: l.left.id)
        #expect(l.group().selected)
        #expect(l.group().rows.allSatisfy { $0.splitGroupSelected })
    }

    @Test func aSelectedFavoriteKeepsItsLook() {
        let l = Listed()
        var state = l.state
        state.selectedTabIDs = [l.favorite.id]
        l.sidebar.newTabPlaceholderActive = true
        l.render(state, focused: l.favorite.id)
        #expect(sidebarDescendants(l.sidebar).compactMap { $0 as? FavoriteTile }.first?.selected == true)
    }

    @Test func closingTheBarRestoresNewTabAtOnce() {
        let l = Listed()
        l.sidebar.newTabPlaceholderActive = true
        l.sidebar.newTabPlaceholderActive = false
        #expect(l.idle())
    }

    @Test func theNextRenderMakesTheSelectedTabCurrentAgain() {
        let l = Listed()
        l.sidebar.newTabPlaceholderActive = true
        l.render(l.state, focused: l.single.id)
        l.sidebar.newTabPlaceholderActive = false
        l.render(l.state, focused: l.single.id)
        #expect(l.fill(of: l.single.id) == .current)
    }

    @MainActor private struct Background {
        let l = Listed()
        var list: SidebarOutlineView { sidebarDescendants(l.sidebar).compactMap { $0 as? SidebarOutlineView }.first! }
        var below: NSPoint { NSPoint(x: 100, y: list.convert(list.rows.last!.bounds, from: list.rows.last!).maxY + 30) }
        var onRow: NSPoint { NSPoint(x: 100, y: list.convert(list.rows[0].bounds, from: list.rows[0]).midY) }

        func mouse(_ type: NSEvent.EventType, at point: NSPoint, clicks: Int, flags: NSEvent.ModifierFlags = []) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: list.convert(point, to: nil), modifierFlags: flags, timestamp: 0,
                               windowNumber: l.window.windowNumber, context: nil, eventNumber: 0, clickCount: clicks, pressure: 1)!
        }
    }

    @Test func theListHasRowsToSitBelow() {
        #expect(!Background().list.rows.isEmpty)
    }

    @Test func aDoubleClicksSecondPressWaitsForItsRelease() {
        let b = Background()
        b.l.sidebar.mouseDown(with: b.mouse(.leftMouseDown, at: b.below, clicks: 2))
        #expect(b.l.opened == 0)
    }

    @Test func aDoubleClickReleasedBelowTheLastRowOpensTheNewTabBar() {
        let b = Background()
        b.l.sidebar.mouseDown(with: b.mouse(.leftMouseDown, at: b.below, clicks: 2))
        b.l.sidebar.mouseUp(with: b.mouse(.leftMouseUp, at: b.below, clicks: 2))
        #expect(b.l.opened == 1)
    }

    @Test func aSingleClickAControlDoubleClickAndARowsDoubleClickDoNot() {
        let b = Background()
        b.l.sidebar.mouseUp(with: b.mouse(.leftMouseUp, at: b.below, clicks: 1))
        b.l.sidebar.mouseUp(with: b.mouse(.leftMouseUp, at: b.below, clicks: 2, flags: .control))
        b.l.sidebar.mouseUp(with: b.mouse(.leftMouseUp, at: b.onRow, clicks: 2))
        #expect(b.l.opened == 0)
    }

    @Test func theListsEmptyAreaReleaseReachesTheSidebarThroughTheResponderChain() {
        let b = Background()
        let clip = b.list.enclosingScrollView!.contentView
        clip.mouseUp(with: b.mouse(.leftMouseUp, at: b.below, clicks: 2))
        #expect(b.l.opened == 1)
    }

    @Test func aLibrarySpaceCardsListIsNotTheWindowBackground() {
        let b = Background()
        b.l.sidebar.isSpaceManagement = true
        b.l.sidebar.mouseUp(with: b.mouse(.leftMouseUp, at: b.below, clicks: 2))
        #expect(b.l.opened == 0)
    }
}
