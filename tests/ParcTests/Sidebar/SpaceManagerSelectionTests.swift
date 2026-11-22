import AppKit
import Testing
@testable import ParcCore
@testable import ParcSidebar

@MainActor
struct SpaceManagerSelectionTests {
    @MainActor private final class Manager {
        let manager = SpaceManagerView(frame: NSRect(x: 0, y: 0, width: 900, height: 650))
        let window: SidebarTestWindow
        var state = BrowserState.initial()
        let space: BrowserSpace
        let one: BrowserTab
        let two: BrowserTab
        var available = true
        var selected: [UUID] = []
        var cancelled = 0

        func tab(_ name: String) -> BrowserTab {
            BrowserTab(id: UUID(), spaceID: space.id, profileID: space.profileID, url: "https://example.test/\(name)", title: name,
                       kind: .today, createdAt: Date(), lastAccessed: Date(), savedURL: "https://example.test/\(name)", savedTitle: name)
        }

        init() {
            window = sidebarTestWindow(containing: manager)
            space = state.spaces[0]
            let spaceID = space.id
            let profileID = space.profileID
            func make(_ name: String) -> BrowserTab {
                BrowserTab(id: UUID(), spaceID: spaceID, profileID: profileID, url: "https://example.test/\(name)", title: name,
                           kind: .today, createdAt: Date(), lastAccessed: Date(), savedURL: "https://example.test/\(name)", savedTitle: name)
            }
            one = make("one")
            two = make("two")
            state.tabs = [one, two]
            state.selectedTabIDs = []
            manager.ownerValid = { [weak self] in self?.available ?? false }
            manager.onClose = { [weak self] in self?.cancelled += 1 }
            manager.configureSidebar = { [weak self] id, sidebar in
                sidebar.prepareTabActivation = { [weak self] expected in
                    guard self?.available == true, expected.spaceID == id else { return nil }
                    return { [weak self] in
                        guard let self, available else { return false }
                        selected.append(expected.id)
                        return true
                    }
                }
                sidebar.configureManagementInteraction(ownerValid: { [weak self] in self?.available ?? false },
                                                       onCancel: { [weak self] in if self?.available == true { self?.manager.onClose?() } })
            }
            manager.reload(state)
            manager.layoutSubtreeIfNeeded()
        }

        deinit { MainActor.assumeIsolated { window.contentView = nil } }

        var sidebar: SidebarView { manager.sidebar(for: space.id)! }

        func key(_ code: UInt16, _ flags: NSEvent.ModifierFlags = []) -> NSEvent {
            NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: window.windowNumber,
                             context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: code)!
        }

        func outline() -> SidebarOutlineView {
            sidebarDescendants(sidebar).compactMap { $0 as? SidebarOutlineView }
                .first { $0.rows.contains { $0.key == AnyHashable(SidebarItemReference.tab(one.id)) } }!
        }

        func row(_ id: UUID) -> SidebarOutlineRow {
            outline().rows.first { $0.key == AnyHashable(SidebarItemReference.tab(id)) }!
        }

        func liveRow(_ id: UUID) -> SidebarOutlineRow? {
            sidebarDescendants(manager.sidebar(for: space.id)!).compactMap { $0 as? SidebarOutlineView }
                .lazy.compactMap { $0.rows.first { $0.key == AnyHashable(SidebarItemReference.tab(id)) } }.first
        }
    }

    @Test func theActualManagerCardInstallsItsInputOwner() {
        let manager = Manager()
        #expect(manager.sidebar.isSpaceManagement)
        #expect(manager.sidebar.canSelectItems?() == true)
    }

    @Test func theInertListResponderAcceptsFocus() {
        let manager = Manager()
        #expect(manager.window.makeFirstResponder(manager.sidebar))
    }

    @Test func downReachesTheActualSecondOriginalTabActivation() {
        let manager = Manager()
        _ = manager.window.makeFirstResponder(manager.sidebar)
        manager.sidebar.keyDown(with: manager.key(125))
        #expect(manager.selected == [manager.two.id])
    }

    @Test func upReachesTheActualFirstOriginalTabActivation() {
        let manager = Manager()
        _ = manager.window.makeFirstResponder(manager.sidebar)
        manager.sidebar.keyDown(with: manager.key(125))
        manager.sidebar.keyDown(with: manager.key(126))
        #expect(manager.selected.last == manager.one.id)
    }

    @Test func shiftSingletonSelectionUsesTheSamePreparedActivation() {
        let manager = Manager()
        _ = manager.window.makeFirstResponder(manager.sidebar)
        manager.sidebar.keyDown(with: manager.key(125))
        manager.sidebar.keyDown(with: manager.key(126))
        manager.sidebar.keyDown(with: manager.key(125, [.shift]))
        #expect(manager.selected.last == manager.two.id)
        #expect(manager.selected.count == 3)
    }

    @Test func anExpiredManagerOwnerCannotActivateByKeyboard() {
        let manager = Manager()
        _ = manager.window.makeFirstResponder(manager.sidebar)
        manager.available = false
        manager.sidebar.keyDown(with: manager.key(125))
        #expect(manager.selected.isEmpty)
    }

    @Test func escapeOnTheUnselectedListReachesManagerClose() {
        let manager = Manager()
        _ = manager.window.makeFirstResponder(manager.sidebar)
        manager.sidebar.keyDown(with: manager.key(53))
        #expect(manager.cancelled == 1)
    }

    @Test func theRealListTakesAccessibilitySelectionOnItemRowsOnly() {
        let manager = Manager()
        _ = manager.window.makeFirstResponder(nil)
        let rowTwo = manager.row(manager.two.id)
        #expect(!rowTwo.isAccessibilitySelected())
        #expect(rowTwo.isAccessibilitySelectorAllowed(#selector(NSView.setAccessibilitySelected(_:))))
        #expect(!manager.outline().rows.contains { !($0.key.base is SidebarItemReference) && $0.isAccessibilitySelectorAllowed(#selector(NSView.setAccessibilitySelected(_:))) })
    }

    @Test func selectingOneRowThroughAccessibilitySelectsItWithoutActivating() {
        let manager = Manager()
        let rowTwo = manager.row(manager.two.id)
        rowTwo.setAccessibilitySelected(true)
        #expect(manager.selected.isEmpty)
        #expect(rowTwo.isAccessibilitySelected())
        let selectedRows = manager.outline().accessibilitySelectedRows()
        #expect(selectedRows?.count == 1)
    }

    @Test func anAccessibilityMultiSelectionNeverActivates() {
        let manager = Manager()
        manager.outline().setAccessibilitySelectedRows([manager.row(manager.one.id), manager.row(manager.two.id)])
        #expect(manager.selected.isEmpty)
        #expect(manager.row(manager.one.id).isAccessibilitySelected())
        #expect(manager.row(manager.two.id).isAccessibilitySelected())
    }

    @Test func deselectingDownToOneRowLeavesItSelectedWithoutActivatingIt() {
        let manager = Manager()
        manager.outline().setAccessibilitySelectedRows([manager.row(manager.one.id), manager.row(manager.two.id)])
        manager.row(manager.one.id).setAccessibilitySelected(false)
        #expect(manager.selected.isEmpty)
        #expect(!manager.row(manager.one.id).isAccessibilitySelected())
        #expect(manager.row(manager.two.id).isAccessibilitySelected())
    }

    @Test func addOrRemoveFromSelectionTogglesARowWithoutActivatingAnything() {
        let manager = Manager()
        let tabRow = sidebarDescendants(manager.sidebar).compactMap { $0 as? SidebarTabRow }.first { $0.tabID == manager.one.id }
        let toggle = tabRow?.accessibilityCustomActions()?.first { $0.name == "Add or Remove from Selection" }
        #expect(toggle?.handler?() == true)
        #expect(manager.row(manager.one.id).isAccessibilitySelected())
        #expect(toggle?.handler?() == true)
        #expect(!manager.row(manager.one.id).isAccessibilitySelected())
        #expect(manager.selected.isEmpty)
    }

    @Test func accessibilitySelectionLeavesKeyboardFocusWhereItWas() {
        let manager = Manager()
        let tabRow = sidebarDescendants(manager.sidebar).compactMap { $0 as? SidebarTabRow }.first { $0.tabID == manager.one.id }
        _ = tabRow?.accessibilityCustomActions()?.first { $0.name == "Add or Remove from Selection" }?.handler?()
        #expect(manager.window.firstResponder === manager.window)
    }

    @Test func aTabArrivingInTheBackgroundKeepsTheAccessibilityMultiSelection() {
        let manager = Manager()
        manager.outline().setAccessibilitySelectedRows([manager.row(manager.one.id), manager.row(manager.two.id)])
        var grown = manager.state
        let three = manager.tab("three")
        grown.tabs.append(three)
        manager.manager.reload(grown)
        manager.manager.layoutSubtreeIfNeeded()
        #expect(manager.liveRow(three.id) != nil)
        #expect(manager.liveRow(manager.one.id)?.isAccessibilitySelected() == true)
        #expect(manager.liveRow(manager.two.id)?.isAccessibilitySelected() == true)
        #expect(manager.liveRow(three.id)?.isAccessibilitySelected() == false)
        #expect(manager.selected.isEmpty)
    }

    @Test func anEmptyAccessibilitySelectionClearsTheRealListsSelection() {
        let manager = Manager()
        manager.outline().setAccessibilitySelectedRows([manager.row(manager.one.id), manager.row(manager.two.id)])
        manager.manager.reload(manager.state)
        manager.manager.layoutSubtreeIfNeeded()
        let live = sidebarDescendants(manager.manager.sidebar(for: manager.space.id)!).compactMap { $0 as? SidebarOutlineView }
            .first { $0.rows.contains { $0.key == AnyHashable(SidebarItemReference.tab(manager.one.id)) } }
        live?.setAccessibilitySelectedRows([])
        let selectedRows = live?.accessibilitySelectedRows()
        #expect(selectedRows?.isEmpty ?? true)
        #expect(manager.liveRow(manager.one.id)?.isAccessibilitySelected() == false)
        #expect(manager.liveRow(manager.two.id)?.isAccessibilitySelected() == false)
    }

    private func withFoldersAndSplit(_ manager: Manager) -> [NSView] {
        _ = manager.window.makeFirstResponder(manager.sidebar)
        let first = BrowserFolder(id: UUID(), spaceID: manager.space.id, name: "A")
        let second = BrowserFolder(id: UUID(), spaceID: manager.space.id, name: "B")
        manager.state.folders = [first, second]
        manager.state.splitLayouts = [BrowserSplitLayout(sidebarAnchorID: manager.one.id, spaceID: manager.space.id,
                                                         tabIDs: [manager.one.id, manager.two.id], widthFactors: [0.5, 0.5])]
        manager.manager.reload(manager.state)
        manager.manager.layoutSubtreeIfNeeded()
        manager.window.layoutIfNeeded()
        manager.window.displayIfNeeded()
        return sidebarDescendants(manager.sidebar).filter { $0 is SidebarFolderRow || $0 is SidebarSplitGroupView }
    }

    @Test func theRealCardIncludesBothFoldersAndItsSplitRow() {
        let manager = Manager()
        #expect(withFoldersAndSplit(manager).count == 3)
    }

    @Test func managerAccessibilityExposesNoUnownedSelectionOrSplitRenameActions() {
        let manager = Manager()
        let rows = withFoldersAndSplit(manager)
        let names = rows.flatMap { ($0.accessibilityCustomActions() ?? []).map(\.name) }
        #expect(names.contains("Add or Remove from Selection"))
        #expect(!names.contains("Duplicate Selection"))
        #expect(!names.contains("Close Tabs in Selection"))
        #expect(!names.contains("Delete or Archive Selection"))
        #expect(!names.contains("Rename Split View"))
    }

    @Test func theActualFolderAccessibilitySelectionIsImplemented() {
        let manager = Manager()
        let rows = withFoldersAndSplit(manager)
        let folders = rows.compactMap { $0 as? SidebarFolderRow }
        #expect(folders[0].accessibilityCustomActions()?.first(where: { $0.name == "Add or Remove from Selection" })?.handler?() == true)
    }

    @Test func theFirstEscapeClearsTheExistingSelectionAndTheNextLeavesTheManager() {
        let manager = Manager()
        let tabRow = sidebarDescendants(manager.sidebar).compactMap { $0 as? SidebarTabRow }.first { $0.tabID == manager.one.id }
        _ = tabRow?.accessibilityCustomActions()?.first { $0.name == "Add or Remove from Selection" }?.handler?()
        _ = manager.window.makeFirstResponder(manager.sidebar)
        manager.sidebar.keyDown(with: manager.key(53))
        #expect(manager.cancelled == 0)
        manager.sidebar.keyDown(with: manager.key(53))
        #expect(manager.cancelled == 1)
    }

    @Test func anExpiredOwnerCannotCancelAReplacementContext() {
        let manager = Manager()
        manager.available = false
        manager.sidebar.cancelOperation(nil)
        #expect(manager.cancelled == 0)
    }
}
