import Foundation
import Testing
@testable import ParcCore

@MainActor
struct SidebarImportMergeTests {
    private static func tab(_ name: String) -> SidebarImport.Tab {
        SidebarImport.Tab(title: name, url: "https://\(name).example/")
    }

    private static func urls(_ state: BrowserState, in spaceID: UUID, kind: TabKind) -> [String] {
        let order = SidebarHierarchy.children(in: SidebarContainerLocation(spaceID: spaceID, folderID: nil,
            section: kind == .pinned ? .pinned : .today), state: state)
        return order.compactMap { item -> String? in
            guard case .tab(let id) = item else { return nil }
            return state.tabs.first { $0.id == id }?.savedURL
        }
    }

    private static func run(_ body: (BrowserStore, UUID, UUID) throws -> Void) throws {
        try DataFixtures.withTemporaryDirectory { directory in
            let store = try BrowserStore(directory: directory, now: { Date(timeIntervalSince1970: 1_793_000_000) })
            try body(store, store.state.profiles[0].id, store.activeSpace.id)
        }
    }

    private static func importing(_ sidebar: SidebarImport, into store: BrowserStore, profile: UUID, home: UUID) throws {
        _ = try store.importSidebar(sidebar, profiles: [(.standard, "Personal")], standardProfileID: profile,
                                    primary: .standard, into: profile, home: home)
    }

    @Test func importingAWindowAgainIntoTheHomeSpaceOnlyAddsTheNewTabs() throws {
        try Self.run { store, profile, home in
            let first = SidebarImport(spaces: [SidebarImport.Space(title: nil, icon: nil, theme: nil, profile: .standard,
                pinned: [], id: "firefox:abc.default:home", today: [.tab(Self.tab("a")), .tab(Self.tab("b"))],
                placement: .profileHome)])
            try Self.importing(first, into: store, profile: profile, home: home)
            let again = SidebarImport(spaces: [SidebarImport.Space(title: nil, icon: nil, theme: nil, profile: .standard,
                pinned: [], id: "firefox:abc.default:home", today: [.tab(Self.tab("b")), .tab(Self.tab("c"))],
                placement: .profileHome)])
            try Self.importing(again, into: store, profile: profile, home: home)
            #expect(Self.urls(store.state, in: home, kind: .today)
                    == ["https://a.example/", "https://b.example/", "https://c.example/"])
            #expect(store.state.spaces.count == 1)
        }
    }

    @Test func aHomeWindowWithoutAnIDSkipsTabsTheHomeSpaceAlreadyHas() throws {
        try Self.run { store, profile, home in
            let first = SidebarImport(spaces: [SidebarImport.Space(title: nil, icon: nil, theme: nil, profile: .standard,
                pinned: [], today: [.tab(Self.tab("a"))], placement: .profileHome)])
            try Self.importing(first, into: store, profile: profile, home: home)
            try Self.importing(first, into: store, profile: profile, home: home)
            #expect(Self.urls(store.state, in: home, kind: .today) == ["https://a.example/"])
        }
    }

    @Test func aRememberedSpaceTakesInNewTabsAndReusesItsSameNamedFolder() throws {
        try Self.run { store, profile, home in
            let first = SidebarImport(spaces: [SidebarImport.Space(title: "Work", icon: nil, theme: nil, profile: .standard,
                pinned: [.folder(title: "Docs", icon: nil, children: [.tab(Self.tab("a"))])], id: "zen:{1}")])
            try Self.importing(first, into: store, profile: profile, home: home)
            let again = SidebarImport(spaces: [SidebarImport.Space(title: "Work", icon: nil, theme: nil, profile: .standard,
                pinned: [.folder(title: "docs", icon: nil, children: [.tab(Self.tab("a")), .tab(Self.tab("b"))]),
                         .tab(Self.tab("c"))], id: "zen:{1}", today: [.tab(Self.tab("d"))])])
            try Self.importing(again, into: store, profile: profile, home: home)
            let state = store.state
            let work = try #require(state.spaces.first { $0.title == "Work" })
            #expect(state.spaces.filter { $0.title == "Work" }.count == 1)
            let folders = state.folders.filter { $0.spaceID == work.id }
            #expect(folders.map(\.name) == ["Docs"])
            let folder = try #require(folders.first)
            let inFolder = SidebarHierarchy.children(in: SidebarContainerLocation(spaceID: work.id, folderID: folder.id,
                section: .pinned), state: state).compactMap { item -> String? in
                    guard case .tab(let id) = item else { return nil }
                    return state.tabs.first { $0.id == id }?.savedURL
                }
            #expect(inFolder == ["https://a.example/", "https://b.example/"])
            #expect(Self.urls(state, in: work.id, kind: .pinned) == ["https://c.example/"])
            #expect(Self.urls(state, in: work.id, kind: .today) == ["https://d.example/"])
        }
    }

    @Test func aSplitWhoseOtherSideIsAlreadyThereArrivesAsASingleTab() throws {
        try Self.run { store, profile, home in
            let first = SidebarImport(spaces: [SidebarImport.Space(title: nil, icon: nil, theme: nil, profile: .standard,
                pinned: [], id: "chrome:Default:home", today: [.tab(Self.tab("a"))], placement: .profileHome)])
            try Self.importing(first, into: store, profile: profile, home: home)
            let again = SidebarImport(spaces: [SidebarImport.Space(title: nil, icon: nil, theme: nil, profile: .standard,
                pinned: [], id: "chrome:Default:home",
                today: [.split(title: nil, icon: nil, tabs: [Self.tab("a"), Self.tab("b")], orientation: .horizontal,
                               widthFactors: [0.5, 0.5])], placement: .profileHome)])
            try Self.importing(again, into: store, profile: profile, home: home)
            #expect(Self.urls(store.state, in: home, kind: .today) == ["https://a.example/", "https://b.example/"])
            #expect(store.state.splitLayouts.isEmpty)
        }
    }
}
