import Foundation
import Testing
@testable import ParcCore

struct ChromiumSidebarReaderTests {
    private typealias Fixture = ChromiumSessionFixture
    private typealias Item = SidebarImport.Item
    private typealias Tab = SidebarImport.Tab

    private static let importedAt = Date(timeIntervalSince1970: 1_793_000_000)
    private static let closedAt = importedAt.addingTimeInterval(-86_400)
    private static let second = ChromiumToken(high: 5, low: 6)
    private static let pairInGroup = ChromiumToken(high: 7, low: 8)

    private static func secondWindow() -> [[UInt8]] {
        var out = [Fixture.windowType(4, 0), Fixture.windowTitle(4, "Reading"),
                   Fixture.groupMetadata(second, title: "", color: 2, collapsed: true),
                   Fixture.splitData(pairInGroup, ratio: 0.98, layout: "Horizontal")]
        out += Fixture.tabCommands(window: 4, tab: 40, visual: 0, url: "chrome://newtab/", title: "New Tab")
        out += Fixture.tabCommands(window: 4, tab: 41, visual: 1, url: "https://top.example/", title: "Top", group: second,
                                   split: pairInGroup)
        out += Fixture.tabCommands(window: 4, tab: 42, visual: 2, url: "https://bottom.example/", title: "Bottom", group: second,
                                   split: pairInGroup)
        out += Fixture.tabCommands(window: 4, tab: 43, visual: 3, url: "javascript:alert(1)", title: "Script")
        out += Fixture.tabCommands(window: 4, tab: 44, visual: 4, url: "chrome://settings/", title: "Settings")
        return out
    }

    private static func tabsFile() -> Data {
        let stamp = Fixture.windowsMicroseconds(closedAt)
        return Fixture.file(Fixture.restoreTab(id: 90, url: "https://first.example/", title: "First", closedAt: stamp)
                            + Fixture.restoreTab(id: 91, url: "chrome://newtab/", title: "New Tab", closedAt: stamp) + [Fixture.marker])
    }

    private static func profile(in directory: URL, session: Data?, tabs: Data? = nil,
                                folder: String = "Sessions") throws -> SidebarImportProfile {
        let profileDirectory = directory.appendingPathComponent("Default", isDirectory: true)
        let sessions = profileDirectory.appendingPathComponent(folder, isDirectory: true)
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        try session?.write(to: sessions.appendingPathComponent("Session_13350000000000000"))
        try tabs?.write(to: sessions.appendingPathComponent("Tabs_13350000000000000"))
        return SidebarImportProfile(key: .standard, directory: profileDirectory, name: "Personal")
    }

    private static func fullSession() -> Data {
        Fixture.file(Fixture.standard() + secondWindow())
    }

    private static func read(_ directory: URL, session: Data? = ChromiumSidebarReaderTests.fullSession(),
                             tabs: Data? = ChromiumSidebarReaderTests.tabsFile(),
                             decrypt: SidebarDecryptor? = nil) throws -> SidebarImport {
        let source = try Self.profile(in: directory, session: session, tabs: tabs)
        return try ChromiumSidebarReader.read(flavor: .chrome, root: directory, profiles: [source], decrypt: decrypt)
    }

    @Test func theFirstWindowFillsTheProfileHomeWithPinsGroupsSplitsAndToday() throws {
        try DataFixtures.withTemporaryDirectory { directory in
            let sidebar = try Self.read(directory)
            let home = try #require(sidebar.spaces.first)
            #expect(home.placement == .profileHome && home.id == "chrome:Default:home" && home.title == nil
                    && home.profile == .standard)
            #expect(home.pinned == [
                .tab(Tab(title: "Pinned", url: "https://pinned.example/")),
                .folder(title: "Work", icon: nil, children: [.tab(Tab(title: "Group A", url: "https://a.example/")),
                                                             .tab(Tab(title: "Group B", url: "https://b.example/"))],
                        isExpanded: true),
            ])
            #expect(home.today == [
                .split(title: nil, icon: nil, tabs: [Tab(title: "Split Left", url: "https://left.example/"),
                                                     Tab(title: "Split Right", url: "https://right.example/")],
                       orientation: .horizontal, widthFactors: [0.6, 1 - 0.6]),
                .tab(Tab(title: "Plain", url: "https://plain.example/")),
            ])
        }
    }

    @Test func aFurtherWindowBecomesANamedSpaceWithItsSplitInsideACollapsedUnnamedGroup() throws {
        try DataFixtures.withTemporaryDirectory { directory in
            let sidebar = try Self.read(directory)
            #expect(sidebar.spaces.count == 2)
            let reading = sidebar.spaces[1]
            #expect(reading.placement == .new && reading.title == "Reading" && reading.id == "chrome:Default:window:1")
            #expect(reading.pinned == [
                .folder(title: "Tab Group", icon: nil, children: [
                    .split(title: nil, icon: nil, tabs: [Tab(title: "Top", url: "https://top.example/"),
                                                         Tab(title: "Bottom", url: "https://bottom.example/")],
                           orientation: .vertical, widthFactors: [0.9, 1 - 0.9]),
                ], isExpanded: false),
            ])
            let settings = try #require(Tab.web(url: "chrome://settings/", title: "Settings"))
            #expect(reading.today == [.tab(settings)])
            #expect(sidebar.skippedItemCount == 1)
        }
    }

    @Test func closedTabsBecomeManualArchiveEntries() throws {
        try DataFixtures.withTemporaryDirectory { directory in
            let sidebar = try Self.read(directory)
            #expect(sidebar.archive.count == 1)
            let entry = try #require(sidebar.archive.first)
            #expect(entry.tab == Tab(title: "First", url: "https://first.example/") && entry.reason == .manual
                    && entry.profile == .standard && entry.spaceID == nil)
            #expect(abs(entry.archivedAt.timeIntervalSince(Self.closedAt)) < 0.001)
        }
    }

    @Test func aMissingSessionGivesAnEmptyImport() throws {
        try DataFixtures.withTemporaryDirectory { directory in
            let sidebar = try Self.read(directory, session: nil, tabs: nil)
            #expect(sidebar.spaces.isEmpty && sidebar.archive.isEmpty && sidebar.warnings.isEmpty)
        }
    }

    @Test func anEncryptedSessionWithoutADecryptorWarnsInsteadOfFailing() throws {
        try DataFixtures.withTemporaryDirectory { directory in
            let source = try Self.profile(in: directory, session: Data([0x53, 0x4E, 0x53, 0x53, 5, 0, 0, 0]),
                                           folder: "Sessions_Encrypted")
            let sidebar = try ChromiumSidebarReader.read(flavor: .edge, root: directory, profiles: [source], decrypt: nil)
            #expect(sidebar.spaces.isEmpty)
            #expect(sidebar.warnings == ["Microsoft Edge keeps the tabs in Personal encrypted, so they stayed behind."])
        }
    }

    @Test func anEncryptedSessionIsReadThroughTheDecryptor() throws {
        try DataFixtures.withTemporaryDirectory { directory in
            let source = try Self.profile(in: directory, session: Data([0x53, 0x4E, 0x53, 0x53, 5, 0, 0, 0]),
                                           folder: "Sessions_Encrypted")
            let plain = Fixture.file(Fixture.standard())
            let sidebar = try ChromiumSidebarReader.read(flavor: .chrome, root: directory, profiles: [source]) { _, _ in plain }
            #expect(sidebar.spaces.count == 1 && sidebar.spaces[0].today.count == 2 && sidebar.warnings.isEmpty)
        }
    }

    @Test func savedGroupsThatAreNotOpenBecomeCollapsedFoldersByPosition() {
        var session = ChromiumSession()
        session.groups[Fixture.group] = ChromiumSession.Group(title: "Work", color: 1, collapsed: false,
                                                              savedGUID: "AAAAAAAA-0000-4000-8000-000000000001")
        let groups = [
            ChromiumSavedTabGroup(guid: "aaaaaaaa-0000-4000-8000-000000000001", title: "Open already", color: 1, position: 0,
                                  tabs: [.init(url: "https://open.example/", title: "Open", position: 0)]),
            ChromiumSavedTabGroup(guid: "bbbbbbbb-0000-4000-8000-000000000002", title: "", color: 2, position: 5,
                                  tabs: [.init(url: "https://late.example/", title: "Late", position: 0)]),
            ChromiumSavedTabGroup(guid: "cccccccc-0000-4000-8000-000000000003", title: "Trip", color: 3, position: 1,
                                  tabs: [.init(url: "https://hotel.example/", title: "Hotel", position: 2),
                                         .init(url: "chrome://newtab/", title: "New Tab", position: 0),
                                         .init(url: "https://flight.example/", title: "Flight", position: 1)]),
            ChromiumSavedTabGroup(guid: "dddddddd-0000-4000-8000-000000000004", title: "Empty", color: 0, position: 2,
                                  tabs: [.init(url: "about:blank", title: "", position: 0)]),
        ]
        #expect(ChromiumSidebarReader.savedGroupFolders(groups, session: session) == [
            .folder(title: "Trip", icon: nil, children: [.tab(Tab(title: "Flight", url: "https://flight.example/")),
                                                         .tab(Tab(title: "Hotel", url: "https://hotel.example/"))],
                    isExpanded: false),
            .folder(title: "Tab Group", icon: nil, children: [.tab(Tab(title: "Late", url: "https://late.example/"))],
                    isExpanded: false),
        ])
    }

    @Test func flavorSpacesKeepTheirFieldsAndTakeOnlyTheirTabsWithCustomTitles() throws {
        var session = try #require(ChromiumSessionParser.session(Self.fullSession(), flavor: .chrome))
        session.windows[0].tabs[5].extraData["vivaldi.fixedTitle"] = "My plain"
        let work = SidebarImport.Space(title: "Work", icon: .emoji("W"), theme: nil, profile: .standard, pinned: [],
                                       id: "vivaldi:Default:7", pinnedCollapsed: true)
        let home = SidebarImport.Space(title: nil, icon: nil, theme: nil, profile: .standard, pinned: [],
                                       id: "vivaldi:Default:default", placement: .profileHome)
        var builder = ChromiumSidebarReader.Builder(session: session)
        let spaces = ChromiumSidebarReader.filled([(home, [1: [10, 15]]), (work, [1: [11, 12, 13, 14], 4: [44]])],
                                                  session: session, builder: &builder)
        #expect(spaces.map(\.id) == ["vivaldi:Default:default", "vivaldi:Default:7"])
        #expect(spaces[0].placement == .profileHome && spaces[1].placement == .new)
        #expect(spaces[1].title == "Work" && spaces[1].icon == .emoji("W") && spaces[1].pinnedCollapsed)
        #expect(spaces[0].pinned == [.tab(Tab(title: "Pinned", url: "https://pinned.example/"))])
        #expect(spaces[0].today == [.tab(Tab(title: "Plain", url: "https://plain.example/", customTitle: "My plain"))])
        #expect(spaces[1].pinned.count == 1 && spaces[1].today.count == 2)
        #expect(spaces[1].today.first?.splitTabs?.map(\.url) == ["https://left.example/", "https://right.example/"])
    }

    @MainActor @Test func importingIntoAFreshStoreFillsTheHomeSpaceAndAddsTheSecondWindow() throws {
        try DataFixtures.withTemporaryDirectory { directory in
            let sidebar = try Self.read(directory.appendingPathComponent("source", isDirectory: true))
            let store = try BrowserStore(directory: directory.appendingPathComponent("parc", isDirectory: true),
                                         now: { Self.importedAt })
            let standardID = store.state.profiles[0].id
            let homeID = store.activeSpace.id
            let spacesBefore = store.state.spaces.count
            let result = try store.importSidebar(sidebar, profiles: [(.standard, "Personal")], standardProfileID: standardID,
                                                 home: homeID)
            let state = store.state
            #expect(result[.standard] == BrowserImportDestination(spaceID: homeID, profileID: standardID))
            #expect(state.spaces.count == spacesBefore + 1)
            let reading = try #require(state.spaces.last)
            #expect(reading.title == "Reading")

            let pinned = SidebarHierarchy.children(in: .init(spaceID: homeID, folderID: nil, section: .pinned), state: state)
            let pinnedTab = try #require(state.tabs.first { $0.spaceID == homeID && $0.savedURL == "https://pinned.example/" })
            let work = try #require(state.folders.first { $0.spaceID == homeID && $0.name == "Work" })
            #expect(pinned == [.tab(pinnedTab.id), .folder(work.id)] && pinnedTab.kind == .pinned && work.isExpanded)
            let grouped = state.tabs.filter { $0.folderID == work.id }.map(\.savedURL).sorted()
            #expect(grouped == ["https://a.example/", "https://b.example/"])

            let layout = try #require(state.splitLayouts.first { $0.spaceID == homeID })
            #expect(layout.orientation == .horizontal && layout.widthFactors == [0.6, 1 - 0.6])
            #expect(layout.tabIDs.compactMap { id in state.tabs.first { $0.id == id }?.savedURL }
                    == ["https://left.example/", "https://right.example/"])
            let plain = try #require(state.tabs.first { $0.spaceID == homeID && $0.savedURL == "https://plain.example/" })
            let today = SidebarHierarchy.children(in: .init(spaceID: homeID, folderID: nil, section: .today), state: state)
            #expect(today == [.split(layout.id), .tab(plain.id)] && plain.kind == .today)

            let stackedFolder = try #require(state.folders.first { $0.spaceID == reading.id })
            #expect(stackedFolder.name == "Tab Group" && !stackedFolder.isExpanded)
            #expect(state.splitLayouts.first { $0.spaceID == reading.id }?.orientation == .vertical)

            let archived = try #require(state.tabs.first { $0.savedURL == "https://first.example/" })
            #expect(archived.archivedAt != nil && archived.archiveProvenance?.reason == .manual && archived.spaceID == homeID)
        }
    }
}
