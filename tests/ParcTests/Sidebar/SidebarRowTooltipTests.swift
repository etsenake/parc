import AppKit
import Testing
@testable import Parc
@testable import ParcCore
@testable import ParcKit
@testable import ParcSidebar

@MainActor
struct SidebarRowTooltipTests {
    @MainActor private final class Rows {
        let sidebar = SidebarView(frame: NSRect(x: 0, y: 0, width: 240, height: 600))
        let window: SidebarTestWindow
        let pinned: BrowserTab
        let today: BrowserTab
        let renamed: BrowserTab
        let document: BrowserTab
        var activated: [UUID] = []
        var committed: [String] = []

        init() {
            window = sidebarTestWindow(containing: sidebar)
            window.applicationActive = true
            var state = BrowserState.initial()
            let space = state.spaces[0]
            func make(_ name: String, _ kind: TabKind) -> BrowserTab {
                BrowserTab(id: UUID(), spaceID: space.id, profileID: space.profileID, url: "https://example.test/\(name)", title: name,
                           kind: kind, createdAt: Date(), lastAccessed: Date(), savedURL: "https://example.test/\(name)", savedTitle: name)
            }
            pinned = make("pinned", .pinned)
            today = make("today", .today)
            var renamed = make("renamed", .pinned)
            renamed.customTitle = "Mine"
            self.renamed = renamed
            var document = make("document", .today)
            document.url = "parc://note/\(UUID().uuidString)"
            self.document = document
            state.tabs = [pinned, today, renamed, document]
            sidebar.prepareTabActivation = { [weak self] tab in { self?.activated.append(tab.id); return true } }
            sidebar.prepareTabRename = { [weak self] _ in { self?.committed.append($0); return true } }
            sidebar.render(state: state, focusedTabID: nil, loading: [], canBack: false, canForward: false)
            sidebar.layoutSubtreeIfNeeded()
        }

        deinit {
            MainActor.assumeIsolated { window.contentView = nil }
        }

        func row(_ tab: BrowserTab) -> SidebarTabRow {
            sidebarDescendants(sidebar).compactMap { $0 as? SidebarTabRow }.first { $0.tabID == tab.id }!
        }

        func closeButton(_ row: SidebarTabRow) -> SidebarRowActionButton {
            sidebarDescendants(row).compactMap { $0 as? SidebarRowActionButton }.first { $0.parcTooltip?.shortcut == .command("closeTab:") }!
        }

        func press(_ target: SidebarTabRow, _ type: NSEvent.EventType, clicks: Int, _ flags: NSEvent.ModifierFlags = []) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: target.convert(NSPoint(x: target.bounds.midX, y: target.bounds.midY), to: nil),
                               modifierFlags: flags, timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 0,
                               clickCount: clicks, pressure: 1)!
        }

        func click(_ target: SidebarTabRow, _ clicks: Int, _ flags: NSEvent.ModifierFlags = []) {
            target.mouseDown(with: press(target, .leftMouseDown, clicks: clicks, flags))
            target.mouseUp(with: press(target, .leftMouseUp, clicks: clicks, flags))
        }
    }

    private let hinted = TooltipConfiguration.Style.label(subtitle: SidebarTabRow.renameHint)

    @Test func anUnrenamedPinnedRowShowsItsTitleOverTheRenameHintAtThePointerAfterOneAndAHalfSeconds() {
        let rows = Rows()
        #expect(rows.row(rows.pinned).parcTooltip == TooltipConfiguration("pinned", style: hinted, anchor: .cursor, behavior: .onMouseIdle(delay: 1.5)))
    }

    @Test func anUnrenamedTodayRowShowsTheRenameHint() {
        let rows = Rows()
        #expect(rows.row(rows.today).parcTooltip?.style == hinted)
    }

    @Test func aRenamedRowShowsItsCustomTitleWithoutTheHint() {
        let rows = Rows()
        #expect(rows.row(rows.renamed).parcTooltip?.label == "Mine")
        #expect(rows.row(rows.renamed).parcTooltip?.style == .label(subtitle: nil))
    }

    @Test func aDocumentRowCannotBeRenamedAndShowsNoHint() {
        let rows = Rows()
        #expect(rows.row(rows.document).beginRename == nil)
        #expect(rows.row(rows.document).parcTooltip?.style == .label(subtitle: nil))
    }

    @Test func aSplitChildHasNoRowTooltip() {
        let rows = Rows()
        let child = SidebarTabRow(tab: rows.today, selected: false, speaker: nil, close: { nil }, reset: { nil }, separate: { nil })
        child.beginRename = { true }
        child.compactSplitChild = true
        #expect(child.parcTooltip == nil)
    }

    @Test func aPinnedRowsCloseDeselectsAndKeepsPinnedWithCloseTabsBinding() {
        let rows = Rows()
        #expect(rows.closeButton(rows.row(rows.pinned)).parcTooltip?.label == "Close and Keep Pinned")
    }

    @Test func aTodayRowsCloseArchivesWithCloseTabsBinding() {
        let rows = Rows()
        #expect(rows.closeButton(rows.row(rows.today)).parcTooltip?.label == "Archive this tab")
    }

    @Test func aSingleClickSelectsTheRowWithoutRenamingIt() {
        let rows = Rows()
        rows.click(rows.row(rows.today), 1)
        #expect(rows.activated == [rows.today.id])
        #expect(!rows.sidebar.isEditingTitle)
    }

    @Test func aModifiedDoubleClickDoesNotRename() {
        let rows = Rows()
        rows.click(rows.row(rows.today), 2, .command)
        #expect(!rows.sidebar.isEditingTitle)
    }

    @Test func aPlainDoubleClickOnTheRowBodyBeginsItsRenameInsteadOfSelectingAgain() {
        let rows = Rows()
        rows.click(rows.row(rows.today), 1)
        let selections = rows.activated.count
        rows.click(rows.row(rows.today), 2)
        #expect(rows.sidebar.isEditingTitle)
        #expect(rows.activated.count == selections)
    }

    @Test func cancellingTheDoubleClickRenameCommitsNothing() {
        let rows = Rows()
        let target = rows.row(rows.today)
        rows.click(target, 2)
        target.cancelTitleEditing()
        #expect(!rows.sidebar.isEditingTitle)
        #expect(rows.committed.isEmpty)
    }
}
