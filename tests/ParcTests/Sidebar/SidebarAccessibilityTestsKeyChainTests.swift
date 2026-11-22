import AppKit
import Testing
@testable import Parc
@testable import ParcKit
@testable import ParcSidebar

@MainActor
struct SidebarAccessibilityTestsKeyChainTests {
    private typealias Support = SidebarAccessibilityTestsSupport
    private typealias FlippedView = Support.FlippedView
    private typealias ListStopView = Support.ListStopView
    private typealias Region = Support.Region

    private final class CreationLikeView: NSView {
        let name = NSTextField(string: "name")
        let icon = ActionButton("Icon")
        override var isFlipped: Bool { true }
        override init(frame: NSRect) {
            super.init(frame: frame)
            name.identifier = .init("name")
            icon.identifier = .init("icon")
            name.frame = .zero
            addSubview(name)
            addSubview(icon)
            needsLayout = true
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
        override func layout() {
            super.layout()
            icon.frame = NSRect(x: 5, y: 5, width: 26, height: 26)
            name.frame = NSRect(x: 33, y: 8, width: 100, height: 21)
        }
    }

    private func names(_ views: [NSView]) -> [String] { views.map { $0.identifier?.rawValue ?? "?" } }

    private func field(_ name: String, _ frame: NSRect, in parent: NSView) -> NSTextField {
        let field = NSTextField(string: name)
        field.frame = frame
        field.identifier = .init(name)
        parent.addSubview(field)
        return field
    }

    @Test func keyViewsRunRowsTopToBottomLeadingFirstConvertingUnflippedHostsKeepingDisabledControlsAndExcludingLabelsAndSpaces() {
        let r = Region()
        _ = field("trailing", NSRect(x: 120, y: 0, width: 40, height: 20), in: r.region)
        _ = field("leading", NSRect(x: 10, y: 2, width: 40, height: 20), in: r.region)
        r.region.addSubview(NSTextField(labelWithString: "label"))
        let disabledLabel = NSTextField(labelWithString: "disabled label")
        disabledLabel.isEnabled = false
        r.region.addSubview(disabledLabel)
        let grid = NSView(frame: NSRect(x: 0, y: 40, width: 240, height: 60))
        r.region.addSubview(grid)
        _ = field("lower", NSRect(x: 10, y: 0, width: 40, height: 20), in: grid)
        _ = field("upper", NSRect(x: 10, y: 40, width: 40, height: 20), in: grid)
        let refusing = ActionButton("Space")
        refusing.frame = NSRect(x: 0, y: 200, width: 20, height: 20)
        SidebarAccessibility.configureSpace(refusing, name: "Space")
        r.region.addSubview(refusing)
        let disabled = ActionButton("Clear")
        disabled.frame = NSRect(x: 0, y: 240, width: 40, height: 20)
        disabled.identifier = .init("disabled")
        disabled.isEnabled = false
        r.region.addSubview(disabled)
        let order = SidebarAccessibility.keyViews(in: [r.region], space: r.sidebar)
        #expect(!disabled.acceptsFirstResponder)
        #expect(names(order) == ["leading", "trailing", "upper", "lower", "disabled"])
    }

    @Test func beforeItsLayoutTheCreationViewsChildrenSortBySubviewIndex() {
        let r = Region()
        let list = ListStopView(frame: NSRect(x: 0, y: 0, width: 240, height: 360))
        r.sidebar.addSubview(list)
        let creation = CreationLikeView(frame: NSRect(x: 0, y: 100, width: 240, height: 60))
        list.addSubview(creation)
        #expect(names(SidebarAccessibility.keyViews(in: [creation], space: r.sidebar)) == ["name", "icon"])
    }

    @Test func theKeyViewChainRunsLeadingFavoritesListStopListControlsByLaidOutFramesThenTheDock() {
        let r = Region()
        let list = ListStopView(frame: NSRect(x: 0, y: 0, width: 240, height: 360))
        r.sidebar.addSubview(list)
        let header = ActionButton("Hide sidebar")
        header.identifier = .init("header")
        let dock = ActionButton("Space actions")
        dock.identifier = .init("dock")
        let favorites = FlippedView(frame: NSRect(x: 0, y: 0, width: 240, height: 30))
        list.addSubview(favorites)
        _ = field("favorite", NSRect(x: 0, y: 0, width: 40, height: 20), in: favorites)
        let rows = FlippedView(frame: NSRect(x: 0, y: 40, width: 240, height: 40))
        list.addSubview(rows)
        _ = field("row", NSRect(x: 0, y: 0, width: 40, height: 20), in: rows)
        let creation = CreationLikeView(frame: NSRect(x: 0, y: 100, width: 240, height: 60))
        list.addSubview(creation)
        list.identifier = .init("list")
        let chain = SidebarAccessibility.keyViewChain(leading: [header], favorites: favorites, list: list, regions: [rows, creation], trailing: [dock], space: r.sidebar)
        #expect(names(chain) == ["header", "favorite", "list", "row", "icon", "name", "dock"])
    }

    @MainActor private final class Linked {
        let r = Region()
        let list = ListStopView(frame: NSRect(x: 0, y: 0, width: 240, height: 360))
        let outside: NSTextField
        let page: NSTextField
        let entering: NSTextField
        let first: NSTextField
        let hidden: NSTextField
        let last: NSTextField

        func field(_ name: String, _ frame: NSRect, in parent: NSView) -> NSTextField {
            let field = NSTextField(string: name)
            field.frame = frame
            field.identifier = .init(name)
            parent.addSubview(field)
            return field
        }

        init() {
            r.sidebar.addSubview(list)
            outside = NSTextField(string: "outside")
            outside.frame = NSRect(x: 0, y: 380, width: 40, height: 20)
            r.root.addSubview(outside)
            page = NSTextField(string: "page")
            page.frame = NSRect(x: 60, y: 380, width: 40, height: 20)
            r.root.addSubview(page)
            entering = NSTextField(string: "entering")
            entering.frame = NSRect(x: 120, y: 380, width: 40, height: 20)
            r.root.addSubview(entering)
            first = NSTextField(string: "first")
            first.frame = NSRect(x: 0, y: 0, width: 40, height: 20)
            list.addSubview(first)
            hidden = NSTextField(string: "hidden")
            hidden.frame = NSRect(x: 0, y: 30, width: 40, height: 20)
            hidden.isHidden = true
            list.addSubview(hidden)
            last = NSTextField(string: "last")
            last.frame = NSRect(x: 0, y: 60, width: 40, height: 20)
            list.addSubview(last)
            last.nextKeyView = outside
            entering.nextKeyView = list
        }
    }

    @Test func theChainIsLinkedInOrderAndTheLastElementKeepsTheWindowLoopsWayOn() {
        let l = Linked()
        SidebarAccessibility.link([l.first, l.hidden, l.list, l.last], within: l.list, exit: nil)
        #expect(l.first.nextKeyView === l.hidden)
        #expect(l.hidden.nextKeyView === l.list)
        #expect(l.list.nextKeyView === l.last)
        #expect(l.last.nextKeyView === l.outside)
    }

    @Test func theWindowLoopsLinkIntoTheListStopsViewEntersAtTheChainsStart() {
        let l = Linked()
        SidebarAccessibility.link([l.first, l.hidden, l.list, l.last], within: l.list, exit: nil)
        #expect(l.entering.nextKeyView === l.first)
        #expect(l.entering.nextValidKeyView === l.first)
    }

    @Test func tabSkipsAHiddenMemberAndStopsAtTheList() {
        let l = Linked()
        SidebarAccessibility.link([l.first, l.hidden, l.list, l.last], within: l.list, exit: nil)
        #expect(l.list.canBecomeKeyView)
        #expect(l.first.nextValidKeyView === l.list)
        #expect(l.list.nextValidKeyView === l.last)
    }

    @Test func relinkingANewOrderMovesTheWayOnToTheNewLastElement() {
        let l = Linked()
        SidebarAccessibility.link([l.first, l.hidden, l.list, l.last], within: l.list, exit: nil)
        SidebarAccessibility.link([l.last, l.list, l.first], within: l.list, exit: nil)
        #expect(l.last.nextKeyView === l.list)
        #expect(l.list.nextKeyView === l.first)
        #expect(l.first.nextKeyView === l.outside)
    }

    @Test func theWindowOwnersExitReplacesTheWindowLoopsLink() {
        let l = Linked()
        SidebarAccessibility.link([l.first, l.hidden, l.list, l.last], within: l.list, exit: nil)
        SidebarAccessibility.link([l.last, l.list, l.first], within: l.list, exit: l.page)
        #expect(l.first.nextKeyView === l.page)
    }

    @Test func aRemovedFormerMemberIsNotTakenAsTheWayOut() {
        let l = Linked()
        let removed = l.field("removed", NSRect(x: 0, y: 90, width: 40, height: 20), in: l.list)
        let tail = l.field("tail", NSRect(x: 0, y: 120, width: 40, height: 20), in: l.list)
        SidebarAccessibility.link([l.first, removed, l.last, tail], within: l.list, exit: nil)
        tail.nextKeyView = nil
        removed.removeFromSuperview()
        SidebarAccessibility.link([l.first, l.last, tail], within: l.list, exit: nil)
        #expect(tail.nextKeyView == nil)
        #expect(l.first.nextKeyView === l.last)
    }

    @Test func anExitSetLaterIsUsedOnTheNextLink() {
        let l = Linked()
        let tail = l.field("tail", NSRect(x: 0, y: 120, width: 40, height: 20), in: l.list)
        SidebarAccessibility.link([l.first, l.last, tail], within: l.list, exit: nil)
        SidebarAccessibility.link([l.first, l.last, tail], within: l.list, exit: l.page)
        #expect(tail.nextKeyView === l.page)
        #expect(l.first.nextValidKeyView === l.last)
    }

    @Test func anOutsideLinkIntoAFormerFirstMemberMovesToTheNewStart() {
        let l = Linked()
        let tail = l.field("tail", NSRect(x: 0, y: 120, width: 40, height: 20), in: l.list)
        let formerEntry = l.field("formerEntry", NSRect(x: 0, y: 150, width: 40, height: 20), in: l.list)
        SidebarAccessibility.link([formerEntry, l.first, l.last, tail], within: l.list, exit: l.page)
        l.entering.nextKeyView = formerEntry
        SidebarAccessibility.link([l.first, formerEntry, l.last, tail], within: l.list, exit: l.page)
        #expect(l.entering.nextKeyView === l.first)
        #expect(l.first.previousKeyView === l.entering)
        #expect(l.first.nextKeyView === formerEntry)
        #expect(formerEntry.nextKeyView === l.last)
    }

    @Test func aHiddenSidebarsControlsAreNoKeyViews() {
        let l = Linked()
        l.list.isHidden = true
        #expect(!l.first.canBecomeKeyView)
        #expect(!l.last.canBecomeKeyView)
        #expect(!l.list.canBecomeKeyView)
    }

    @Test func theWayOutSkipsAHiddenPreparedListsLinks() {
        let l = Linked()
        let owner = FlippedView(frame: NSRect(x: 0, y: 200, width: 240, height: 120))
        l.r.root.addSubview(owner)
        let start = l.field("start", NSRect(x: 0, y: 0, width: 40, height: 20), in: owner)
        let end = l.field("end", NSRect(x: 50, y: 0, width: 40, height: 20), in: owner)
        let prepared = FlippedView(frame: NSRect(x: 0, y: 30, width: 240, height: 40))
        owner.addSubview(prepared)
        prepared.isHidden = true
        l.field("prepared", NSRect(x: 0, y: 0, width: 40, height: 20), in: prepared).nextKeyView = l.outside
        l.field("shown", NSRect(x: 0, y: 80, width: 40, height: 20), in: owner).nextKeyView = l.page
        SidebarAccessibility.link([start, end], within: owner, exit: nil, skipping: { $0.isHidden })
        #expect(start.nextKeyView === end)
        #expect(end.nextKeyView === l.page)
    }

    @Test func withoutSkippingTheHiddenListsLinkWouldBeTheWayOut() {
        let l = Linked()
        let owner = FlippedView(frame: NSRect(x: 0, y: 200, width: 240, height: 120))
        l.r.root.addSubview(owner)
        let start = l.field("start", NSRect(x: 0, y: 0, width: 40, height: 20), in: owner)
        let end = l.field("end", NSRect(x: 50, y: 0, width: 40, height: 20), in: owner)
        let prepared = FlippedView(frame: NSRect(x: 0, y: 30, width: 240, height: 40))
        owner.addSubview(prepared)
        prepared.isHidden = true
        l.field("prepared", NSRect(x: 0, y: 0, width: 40, height: 20), in: prepared).nextKeyView = l.outside
        SidebarAccessibility.link([start, end], within: owner, exit: nil)
        #expect(end.nextKeyView === l.outside)
    }
}
