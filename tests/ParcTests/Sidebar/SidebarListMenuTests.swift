import AppKit
import Testing
@testable import Parc
@testable import ParcCore
@testable import ParcKit
@testable import ParcSidebar

@MainActor
struct SidebarListMenuTests {
    final class Surface: SidebarSpaceMenuSurface {
        var received: [NSEvent] = []
        override func rightMouseDown(with event: NSEvent) { received.append(event) }
    }

    final class Host: NSView {
        var clicks: [NSEvent] = []
        override func mouseDown(with event: NSEvent) { clicks.append(event) }
        override func rightMouseDown(with event: NSEvent) {}
    }

    final class Row: NSView {
        let ownMenu = NSMenu(title: "row")
        var opened = 0
        override func menu(for event: NSEvent) -> NSMenu? { ownMenu }
        override func rightMouseDown(with event: NSEvent) { opened += 1 }
        override func mouseDown(with event: NSEvent) {
            if event.modifierFlags.contains(.control) { rightMouseDown(with: event) }
        }
    }

    static func space(_ name: String, icon: SidebarGroupIcon? = nil) -> BrowserSpace {
        var space = BrowserSpace(id: UUID(), name: name, symbol: "circle.fill", color: "B9B5D4", profileID: UUID())
        space.customIcon = icon
        if name.hasPrefix("Space "), Int(name.dropFirst(6)) != nil { space.title = nil }
        return space
    }

    static let base = ["Rename Space…", "Edit Theme Color…", "New Folder"]

    @MainActor final class List {
        let directory: URL
        let store: BrowserStore
        var fixture: (spaces: [BrowserSpace], active: UUID?)?
        var creating = false, privateWindow = false
        var calls: [String] = []
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 228, height: 700), styleMask: [.borderless], backing: .buffered, defer: true)
        let host = Host(frame: NSRect(x: 0, y: 0, width: 228, height: 700))
        let sidebar: Surface
        let scroll = NSScrollView(frame: NSRect(x: 8, y: 40, width: 212, height: 600))
        let list = SidebarOutlineView(frame: .zero)
        let pinned = [Row(), Row()], today = [Row(), Row()]
        let clear = ActionButton("↓ Clear"), newTab = ActionButton("New Tab", symbol: "plus")

        var spaces: [BrowserSpace] { fixture?.spaces ?? store.state.spaces }
        var active: UUID? { fixture == nil ? store.state.activeSpaceID : fixture?.active }

        init() throws {
            directory = FileManager.default.temporaryDirectory.appendingPathComponent("parc-list-menu-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
            store = try BrowserStore(directory: directory)
            sidebar = Surface(frame: host.bounds)
            window.isReleasedWhenClosed = false
            window.contentView = host
            host.addSubview(sidebar)
            sidebar.spaceMenu = { [weak self] in self?.menu() }
            scroll.drawsBackground = false; scroll.adoptTablistScroller(); scroll.horizontalScrollElasticity = .none
            scroll.documentView = list
            sidebar.addSubview(scroll)
            let divider = NSView(); divider.addSubview(clear)
            var pinnedRows = pinned.makeIterator(), todayRows = today.makeIterator()
            var entries: [SidebarOutlineEntry] = []
            for slot in SidebarChromeLayout.tablistSlots(pinnedItems: 2, todayItems: 2, isPrivate: false) {
                switch slot {
                case .pinnedHeader: entries.append(.init(key: "header", content: nil, row: slot.row))
                case .pinnedItem: entries.append(.item(.tab(UUID()), content: pinnedRows.next()!, depth: 0, in: nil))
                case .sectionDivider: entries.append(.init(key: "divider", content: divider, row: slot.row))
                case .newTab: entries.append(.init(key: "newTab", content: newTab, row: slot.row))
                case .todayItem: entries.append(.item(.tab(UUID()), content: todayRows.next()!, depth: 0, in: nil))
                case .privateHeading, .pinnedSectionHeader: break
                }
            }
            list.reload(entries)
            list.frame = NSRect(x: 0, y: 0, width: scroll.contentSize.width, height: max(0, list.fittingSize.height))
            sidebar.layoutSubtreeIfNeeded(); list.layoutSubtreeIfNeeded()
            clear.frame = NSRect(x: divider.bounds.maxX - 60, y: 2, width: 60, height: 20)
        }

        deinit {
            try? FileManager.default.removeItem(at: directory)
            MainActor.assumeIsolated { window.contentView = nil }
        }

        func menu() -> SidebarSpaceMenu? {
            SidebarSpaceMenu.sidebar(spaces: spaces, activeSpaceID: active, creatingSpace: creating, privateWindow: privateWindow,
                                     showOnSingleUnnamedSpace: store.state.settings.showSpaceHeaderOnSingleUnnamedSpaces ?? false,
                                     rename: { [weak self] id in guard let self else { return }; calls.append("rename " + (spaces.first { $0.id == id }?.name ?? "?")) },
                                     editTheme: { [weak self] in guard let self else { return }; calls.append("theme") },
                                     newFolder: { [weak self] in guard let self else { return }; calls.append("folder") },
                                     toggleHeader: { [weak self] in guard let self else { return }; store.toggleSpaceHeaderOnSingleUnnamedSpaces() })
        }

        func point(_ view: NSView, _ local: NSPoint) -> NSPoint { view.convert(local, to: nil) }
        func centre(_ view: NSView) -> NSPoint { point(view, NSPoint(x: view.bounds.midX, y: view.bounds.midY)) }
        func event(_ type: NSEvent.EventType, _ location: NSPoint, _ flags: NSEvent.ModifierFlags = []) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: location, modifierFlags: flags, timestamp: 0, windowNumber: window.windowNumber,
                               context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        }
        @discardableResult
        func deliver(_ type: NSEvent.EventType, at location: NSPoint, _ flags: NSEvent.ModifierFlags = []) -> NSView? {
            guard let hit = sidebar.hitTest(location) else { return nil }
            let delivered = event(type, location, flags)
            if type == .rightMouseDown { hit.rightMouseDown(with: delivered) } else { hit.mouseDown(with: delivered) }
            return hit
        }
        var lastRow: SidebarOutlineRow { list.rows.last! }
        var inset: NSPoint { point(list, NSPoint(x: list.bounds.midX, y: lastRow.frame.maxY + SidebarChromeLayout.tablistBottomInset / 2)) }
        var titles: [String]? { sidebar.menu(for: event(.rightMouseDown, .zero))?.items.map(\.title) }
        var opened: NSMenu? { sidebar.menu(for: event(.rightMouseDown, inset)) }

        func place(_ place: Place) -> (NSPoint, (NSView?) -> Bool) {
            switch place {
            case .bottomInset: return (inset, { [list] in $0 === list })
            case .belowTheOutline:
                return (point(scroll.contentView, NSPoint(x: scroll.contentView.bounds.midX, y: list.frame.maxY + 40)), { [scroll] in $0 === scroll.contentView })
            case .intercellGap:
                let firstToday = list.rows[list.rows.count - 2]
                return (point(firstToday, NSPoint(x: firstToday.bounds.midX, y: firstToday.bounds.maxY - 0.5)), { $0 is SidebarOutlineRow })
            case .cellMargin: return (point(lastRow, NSPoint(x: lastRow.bounds.midX, y: 0.5)), { $0 is SidebarOutlineCell })
            case .pinnedHeader: return (centre(list.rows[0]), { $0 is SidebarOutlineCell })
            case .newTab: return (centre(newTab), { [newTab] in $0 === newTab })
            case .clear: return (centre(clear), { [clear] in $0 === clear })
            }
        }
    }

    enum Place: CaseIterable {
        case bottomInset, belowTheOutline, intercellGap, cellMargin, pinnedHeader, newTab, clear
        static let empty: [Place] = [.bottomInset, .belowTheOutline, .intercellGap, .cellMargin, .pinnedHeader]
    }

    @Test func theListHasSevenRowsTheLastATodayItem() throws {
        let list = try List()
        #expect(list.list.rows.count == 7 && list.lastRow.cell.content === list.today[1])
    }

    @Test func theOutlineEndsWithTheBottomInsetShorterThanItsScrollView() throws {
        let list = try List()
        #expect(abs(list.list.frame.height - (list.lastRow.frame.maxY + SidebarChromeLayout.tablistBottomInset)) < 0.5)
        #expect(list.list.frame.height < list.scroll.contentSize.height)
    }

    @Test(arguments: Place.allCases)
    func aRightClickLandsOnItsOwnViewAndPassesUpTheResponderChainToTheSidebar(_ place: Place) throws {
        let list = try List()
        let (location, isTarget) = list.place(place)
        let hit = list.deliver(.rightMouseDown, at: location)
        #expect(isTarget(hit))
        #expect(list.sidebar.received.count == 1 && list.sidebar.received.first?.type == .rightMouseDown)
    }

    @Test(arguments: Place.empty)
    func aControlClickInTheEmptyAreaReachesTheSidebarsMouseDownWhichOpensItsMenu(_ place: Place) throws {
        let list = try List()
        list.deliver(.leftMouseDown, at: list.place(place).0, .control)
        #expect(list.sidebar.received.count == 1 && list.sidebar.received.first?.type == .leftMouseDown && list.host.clicks.isEmpty)
    }

    @Test(arguments: Place.empty)
    func aPlainClickInTheEmptyAreaOpensNoMenuAndPassesOnToSuper(_ place: Place) throws {
        let list = try List()
        list.deliver(.leftMouseDown, at: list.place(place).0)
        #expect(list.sidebar.received.isEmpty && list.host.clicks.count == 1)
    }

    @Test func noRowOpensItsMenuForTheEmptyArea() throws {
        let list = try List()
        for place in Place.allCases {
            let location = list.place(place).0
            list.deliver(.rightMouseDown, at: location)
            if Place.empty.contains(place) { list.deliver(.leftMouseDown, at: location, .control) }
        }
        #expect((list.pinned + list.today).allSatisfy { $0.opened == 0 })
    }

    @Test(arguments: 0..<4)
    func aRowOpensItsOwnMenuForARightClickAndAControlClick(_ index: Int) throws {
        let list = try List()
        let row = (list.pinned + list.today)[index], centre = list.centre(row)
        #expect(list.sidebar.hitTest(centre) === row && row.menu(for: list.event(.rightMouseDown, centre)) === row.ownMenu)
        list.deliver(.rightMouseDown, at: centre); list.deliver(.leftMouseDown, at: centre, .control)
        #expect(row.opened == 2)
        #expect(list.sidebar.received.isEmpty)
    }

    @Test func aNewSessionHasOneUntitledSpaceAndTheSettingOff() throws {
        let list = try List()
        #expect(list.store.state.spaces.count == 1 && list.store.state.spaces[0].name == "Space 1")
        #expect(list.store.state.settings.showSpaceHeaderOnSingleUnnamedSpaces == nil)
    }

    @Test func oneUntitledIconlessSpaceOffersTheSpaceItemsThenShowSpaceHeaderAllEnabled() throws {
        let list = try List()
        #expect(list.opened?.items.map(\.title) == Self.base + ["Show Space Header"])
        #expect(list.opened?.items.allSatisfy(\.isEnabled) == true)
    }

    @Test func showSpaceHeaderTurnsTheSettingOnAndTheNextMenuOffersHide() throws {
        let list = try List()
        list.opened?.performActionForItem(at: 3)
        #expect(list.store.state.settings.showSpaceHeaderOnSingleUnnamedSpaces == true)
        #expect(list.opened?.items.last?.title == "Hide Space Header" && list.opened?.items.count == 4)
    }

    @Test func hideSpaceHeaderTurnsItOffAndTheMenuOffersShowAgain() throws {
        let list = try List()
        list.opened?.performActionForItem(at: 3)
        list.opened?.performActionForItem(at: 3)
        #expect(list.store.state.settings.showSpaceHeaderOnSingleUnnamedSpaces == false && list.titles?.last == "Show Space Header")
    }

    @Test func theMenuRenamesEditsTheThemeOfAndAddsAFolderToTheActiveSpace() throws {
        let list = try List()
        for index in 0..<3 { list.opened?.performActionForItem(at: index) }
        #expect(list.calls == ["rename Space 1", "theme", "folder"])
    }

    @Test func twoSpacesOfferTheSpaceItemsForTheActiveSpaceAllEnabledWithoutToggle() throws {
        let list = try List()
        let secondID = list.store.createSpace(name: "Work")
        #expect(list.store.state.activeSpaceID == secondID && list.titles == Self.base)
        #expect(list.opened?.items.allSatisfy(\.isEnabled) == true)
    }

    @Test func renameNamesWhicheverSpaceIsActiveAndTheMenuSwitchesNoSpace() throws {
        let list = try List()
        let first = list.store.state.spaces[0]
        _ = list.store.createSpace(name: "Work")
        list.opened?.performActionForItem(at: 0)
        list.store.selectSpace(first.id)
        list.opened?.performActionForItem(at: 0)
        #expect(list.calls == ["rename Work", "rename Space 1"])
        #expect(list.store.state.activeSpaceID == first.id)
    }

    @Test func theSettingAddsNoToggleWhileTheWindowHasTwoSpaces() throws {
        let list = try List()
        _ = list.store.createSpace(name: "Work")
        list.store.toggleSpaceHeaderOnSingleUnnamedSpaces()
        #expect(list.titles == Self.base)
    }

    @Test(arguments: [("Space 1", false, true), ("Trips", false, false), ("Space 1", true, false), ("", false, true)])
    func aLoneSpaceOffersTheToggleOnlyWhenUntitledAndIconless(_ name: String, _ starred: Bool, _ toggles: Bool) throws {
        let list = try List()
        let fixture = Self.space(name, icon: starred ? .symbol("star") : nil)
        list.fixture = ([fixture], fixture.id)
        #expect(list.titles == Self.base + (toggles ? ["Show Space Header"] : []))
    }

    @Test func theActiveSpacesToggleCountsTheWindowsSpaces() throws {
        let list = try List()
        let lone = Self.space("Space 1")
        list.fixture = ([Self.space("Trips"), lone], lone.id)
        #expect(list.titles == Self.base)
    }

    @Test func thereIsNoMenuWithoutAnActiveSpaceOrForASpaceTheWindowDoesNotHave() throws {
        let list = try List()
        let lone = Self.space("Space 1")
        list.fixture = ([lone], nil)
        #expect(list.opened == nil)
        list.fixture = ([lone], UUID())
        #expect(list.opened == nil)
    }

    @Test func thereIsNoMenuWhileASpaceIsCreatedOrInAPrivateWindow() throws {
        let list = try List()
        list.creating = true
        #expect(list.opened == nil)
        list.creating = false; list.privateWindow = true
        #expect(list.opened == nil)
        list.privateWindow = false
        #expect(list.titles == Self.base + ["Show Space Header"])
    }
}
