import AppKit
import Testing
@testable import Parc
@testable import ParcCore

@MainActor
struct SplitCellMenuTests {
    private static func titles(_ menu: NSMenu) -> [String] { menu.items.map { $0.isSeparatorItem ? "—" : $0.title } }

    @MainActor private final class Recorder {
        var ran: [String] = []
        func action(_ name: String) -> () -> Bool { { self.ran.append(name); return true } }
    }

    @MainActor private struct Fixture {
        let recorder = Recorder()
        let child: NSMenu
        let childTab: NSMenu
        var bindings: [String: String] = [:]
        let menu: NSMenu

        init() {
            let recorder = recorder
            let tab = NSMenu()
            tab.addItem(NSMenuItem(title: "Separate Tab from Split View", action: nil, keyEquivalent: ""))
            tab.addItem(NSMenuItem(title: "Open in Split View", action: nil, keyEquivalent: ""))
            tab.addItem(NSMenuItem(title: "Pin tab", action: nil, keyEquivalent: ""))
            tab.addItem(.separator())
            tab.addItem(NSMenuItem(title: "Copy Link", action: nil, keyEquivalent: ""))
            tab.addItem(NSMenuItem(title: "Archive Tab", action: nil, keyEquivalent: ""))
            childTab = tab
            child = SidebarSplitCellMenu.childSubmenu(separate: recorder.action("separate child"), tabMenu: tab,
                                                      replacing: ["Separate Tab from Split View", "Open in Split View"])
            var model = SidebarSplitCellMenu(orientation: .horizontal)
            var collected: [String: String] = [:]
            model.bindShortcut = { item, id in collected[item.title] = id }
            model.separateAll = recorder.action("separate all"); model.addTab = recorder.action("add")
            model.convert = recorder.action("convert")
            model.children = [("First", child), ("Second", NSMenu())]
            model.reset = recorder.action("reset"); model.changeIcon = recorder.action("icon"); model.rename = recorder.action("rename")
            model.duplicate = recorder.action("duplicate"); model.newFolder = recorder.action("folder")
            model.moves = [NSMenuItem(title: "Move to", action: nil, keyEquivalent: "")]
            model.archive = recorder.action("archive"); model.close = recorder.action("close")
            model.archiveGroup = zip(SidebarSplitCellMenu.archiveGroupTitles, ["others", "below", "above"]).map { ($0, recorder.action($1)) }
            menu = model.makeMenu()
            bindings = collected
        }
    }

    @Test func aChildSubmenuLeadsWithSeparateAndDropsTheTabMenusSplitEntries() {
        let fixture = Fixture()
        #expect(Self.titles(fixture.child) == ["Separate from Split View", "—", "Pin tab", "—", "Copy Link", "Archive Tab"])
    }

    @Test func theChildsTabItemsMoveIntoItsSubmenu() {
        #expect(Fixture().childTab.items.isEmpty)
    }

    @Test func theWindowBindsOnlyRenameDuplicateAndNewFolderShortcuts() {
        #expect(Fixture().bindings == ["Rename…": "renameCurrentItem:", "Duplicate": "duplicateCurrentItem:",
                                       "New Folder with 1 Items": "createFolder:"])
    }

    @Test func theSplitMenuFollowsItsAppendOrder() {
        #expect(Self.titles(Fixture().menu) == ["Separate All Tabs", "Add Tab…", "Convert to Vertical Split View",
                                                "—", "Tab Options", "First", "Second",
                                                "—", "Reset Name and Icon", "Change Icon…", "Rename…",
                                                "—", "Duplicate", "Move to", "New Folder with 1 Items",
                                                "—", "Archive Item", "Archive Other Tabs", "Archive Tabs Below", "Archive Tabs Above", "Close"])
    }

    @Test func tabOptionsIsADisabledHeaderOverOneSubmenuPerChild() {
        let fixture = Fixture()
        #expect(fixture.menu.item(withTitle: "Tab Options")?.isEnabled == false)
        #expect(fixture.menu.item(withTitle: "First")?.submenu === fixture.child)
    }

    @Test func shareSplitViewIsAbsent() {
        #expect(!Fixture().menu.items.contains { $0.title.hasPrefix("Share") })
    }

    @Test func noItemShowsAnImage() {
        let fixture = Fixture()
        #expect((fixture.menu.items + fixture.child.items).allSatisfy { $0.image == nil })
    }

    @Test func eachEnabledItemRunsItsOwnPreparedActionOnce() {
        let fixture = Fixture()
        for item in fixture.menu.items where item.action != nil && item.isEnabled && item.submenu == nil {
            _ = (item.target as? NSObject)?.perform(item.action, with: item)
        }
        #expect(fixture.recorder.ran == ["separate all", "add", "convert", "reset", "icon", "rename", "duplicate", "folder",
                                         "archive", "others", "below", "above", "close"])
    }

    @Test func aStackedSplitConvertsToHorizontalWithoutChildrenOrArchiveGroupOrNewFolder() {
        var stacked = SidebarSplitCellMenu(orientation: .vertical)
        stacked.showsNewFolder = false
        #expect(Self.titles(stacked.makeMenu()) == ["Separate All Tabs", "Add Tab…", "Convert to Horizontal Split View",
                                                    "—", "Reset Name and Icon", "Change Icon…", "Rename…",
                                                    "—", "Duplicate", "—", "Archive Item", "Close"])
    }

    @Test func itemsWithoutAnActionStayVisibleAndDisabled() {
        var bare = SidebarSplitCellMenu(orientation: .vertical)
        bare.showsNewFolder = false
        #expect(bare.makeMenu().items.filter { !$0.isSeparatorItem }.allSatisfy { !$0.isEnabled })
    }

    @Test func theFolderItemCountsTheSelectedItems() {
        #expect(SidebarSplitCellMenu.newFolderTitle(count: 3) == "New Folder with 3 Items")
    }

    @Test func archiveGroupsTakeTheTodayTabsAroundTheSplitsChildren() {
        let a = UUID(), b = UUID(), c = UUID(), d = UUID(), e = UUID()
        #expect(SidebarSplitCellMenu.archiveGroupIDs(order: [a, b, c, d, e], children: [b, c]) == [[a, d, e], [d, e], [a]])
    }

    @Test func aSplitOutsideTheTodayOrderHasNoArchiveGroup() {
        #expect(SidebarSplitCellMenu.archiveGroupIDs(order: [UUID(), UUID()], children: [UUID()]) == nil)
    }
}

@MainActor
struct SplitMarginHandleTests {
    @MainActor private struct Fixture {
        let window: NSWindow
        let root: NSView
        let handle: SplitMarginHandleView
        let split: ParcSplitView
        let page = NSView()

        init() {
            _ = NSApplication.shared
            window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300), styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            root = NSView(frame: window.contentLayoutRect)
            window.contentView = root
            handle = SplitMarginHandleView(frame: NSRect(x: 390, y: 10, width: 10, height: 280))
            root.addSubview(handle)
            split = ParcSplitView(frame: NSRect(x: 10, y: 10, width: 380, height: 280))
            root.addSubview(split)
            split.marginHandle = handle
            split.addArrangedSubview(page)
            split.configure(orientation: .horizontal, factors: [1])
        }

        func admit() { handle.windowAllows = true }
    }

    @Test func nothingShowsUntilTheWindowAndSplitBothAdmitIt() {
        let fixture = Fixture()
        #expect(!fixture.handle.isShown)
        #expect(fixture.handle.region.isEmpty)
    }

    @Test func onePageOutsideASplitShowsTheMarginGrip() {
        let fixture = Fixture()
        fixture.admit()
        #expect(fixture.handle.isShown)
    }

    @Test func theDraggableBandIsTheHandlesWidthFortyFourPointsCentredVertically() {
        let fixture = Fixture()
        fixture.admit()
        #expect(fixture.handle.region == NSRect(x: 0, y: 140 - 22, width: 10, height: 44))
    }

    @Test func theTwoByTwentyFourGripIsCentredOnTheHandle() {
        let fixture = Fixture()
        fixture.admit()
        let grip = fixture.handle.layer?.sublayers?.first { $0.name == "Split margin grip" }
        #expect(grip?.frame == NSRect(x: 4, y: 128, width: 2, height: 24))
        #expect(grip?.isHidden == false)
    }

    @Test func theHandleTakesNoMouseEvents() {
        let fixture = Fixture()
        fixture.admit()
        #expect(fixture.handle.hitTest(NSPoint(x: 395, y: 150)) == nil)
    }

    @Test func hoverAndTheResizePointerTrackTheBand() {
        let fixture = Fixture()
        fixture.admit()
        let areas = fixture.handle.trackingAreas
        #expect(areas.count == 1)
        #expect(areas[0].rect == fixture.handle.region)
        #expect(areas[0].options == [.mouseEnteredAndExited, .mouseMoved, .cursorUpdate, .activeInKeyWindow, .enabledDuringMouseDrag])
    }

    @Test func theUncoveredBandShowsTheResizePointer() {
        let fixture = Fixture()
        fixture.admit()
        let point = fixture.handle.convert(NSPoint(x: 5, y: 140), to: nil)
        #expect(fixture.handle.bandCursor(atWindowPoint: point) != nil)
    }

    @Test func aCommandSurfaceOverTheBandKeepsTheResizePointerOffIt() {
        let fixture = Fixture()
        fixture.admit()
        let point = fixture.handle.convert(NSPoint(x: 5, y: 140), to: nil)
        fixture.root.addSubview(NSView(frame: NSRect(x: 380, y: 100, width: 20, height: 100)))
        #expect(fixture.handle.bandCursor(atWindowPoint: point) == nil)
    }

    @Test func aSecondPaneHidesTheGripAndEmptiesTheBand() {
        let fixture = Fixture()
        fixture.admit()
        let grip = fixture.handle.layer?.sublayers?.first { $0.name == "Split margin grip" }
        fixture.split.addArrangedSubview(NSView())
        fixture.split.configure(orientation: .horizontal, factors: [1, 1])
        #expect(!fixture.handle.isShown)
        #expect(fixture.handle.region.isEmpty)
        #expect(fixture.handle.trackingAreas.isEmpty)
        #expect(grip?.isHidden == true)
    }

    @Test func returningToOnePageShowsTheGripAgain() {
        let fixture = Fixture()
        fixture.admit()
        let other = NSView()
        fixture.split.addArrangedSubview(other)
        fixture.split.configure(orientation: .horizontal, factors: [1, 1])
        fixture.split.removeArrangedSubview(other)
        fixture.split.configure(orientation: .horizontal, factors: [1])
        #expect(fixture.handle.isShown)
    }

    @Test func aWindowThatDisallowsItHidesTheGrip() {
        let fixture = Fixture()
        fixture.admit()
        fixture.handle.windowAllows = false
        #expect(!fixture.handle.isShown)
        #expect(fixture.handle.trackingAreas.isEmpty)
    }

    @Test func noMarginHidesTheGrip() {
        let fixture = Fixture()
        fixture.admit()
        fixture.handle.frame = .zero
        #expect(!fixture.handle.isShown)
    }
}
