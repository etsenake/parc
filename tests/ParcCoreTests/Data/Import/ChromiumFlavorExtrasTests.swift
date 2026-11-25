import Foundation
import Testing
@testable import ParcCore

struct ChromiumFlavorExtrasTests {
    private typealias Tab = ChromiumSession.Tab

    private func withProfile<T>(preferences: String? = nil, _ body: (URL) throws -> T) throws -> T {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("flavor-extras-\(UUID().uuidString)")
        let profile = root.appendingPathComponent("Default")
        try FileManager.default.createDirectory(at: profile, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        if let preferences { try Data(preferences.utf8).write(to: profile.appendingPathComponent("Preferences")) }
        return try body(profile)
    }

    private func session(_ windows: [[Tab]]) -> ChromiumSession {
        ChromiumSession(windows: windows.enumerated().map { ChromiumSession.Window(id: Int32($0.offset + 1), tabs: $0.element) })
    }

    private func urls(_ session: ChromiumSession, window: Int = 0) -> [String] {
        session.windows[window].tabs.map(\.url)
    }

    private func importProfile(_ directory: URL) -> SidebarImportProfile {
        SidebarImportProfile(key: .standard, directory: directory, name: "Default")
    }

    @Test func heliumPinsUseTheirHomeAddressAndRepeatAcrossWindowsOnce() throws {
        func pin(_ id: Int32, _ url: String, home: String, pinID: String) -> Tab {
            Tab(id: id, url: url, title: "", pinned: true,
                extraData: ["helium.pinned_tab_url": home, "helium.pinned_tab_id": pinID])
        }
        let input = session([
            [pin(1, "https://mail.example.com/inbox", home: "https://mail.example.com/", pinID: "a"),
             pin(2, "https://wiki.example.com/", home: "https://wiki.example.com/", pinID: "b"),
             Tab(id: 3, url: "https://plain.example.com/", title: "")],
            [pin(4, "https://mail.example.com/other", home: "https://mail.example.com/", pinID: "a"),
             pin(5, "https://chat.example.com/", home: "https://chat.example.com/", pinID: "c"),
             Tab(id: 6, url: "https://plain.example.com/two", title: "")]
        ])
        try withProfile { profile in
            let result = ChromiumFlavorExtras.adjusted(input, flavor: .helium, profileDirectory: profile)
            #expect(urls(result) == ["https://mail.example.com/", "https://wiki.example.com/", "https://plain.example.com/"])
            #expect(urls(result, window: 1) == ["https://chat.example.com/", "https://plain.example.com/two"])
        }
    }

    @Test func heliumPinsWithoutExtraDataStayAsTheyAre() throws {
        let input = session([[Tab(id: 1, url: "https://a.example.com/", title: "", pinned: true),
                              Tab(id: 2, url: "https://a.example.com/", title: "", pinned: true)]])
        try withProfile { profile in
            #expect(ChromiumFlavorExtras.adjusted(input, flavor: .helium, profileDirectory: profile) == input)
        }
    }

    @Test func otherFlavorsComeBackUntouched() throws {
        let input = session([[Tab(id: 1, url: "containers+abc:https://a.example.com/", title: "", pinned: true,
                                  extraData: ["helium.pinned_tab_url": "https://x.example.com/"])]])
        try withProfile(preferences: #"{"brave":{"tabs":{"shared_pinned_tab":true}}}"#) { profile in
            for flavor in [ChromiumFlavor.chrome, .chromium, .edge, .opera, .operaGX, .comet] {
                #expect(ChromiumFlavorExtras.adjusted(input, flavor: flavor, profileDirectory: profile) == input)
            }
        }
    }

    private let bravePreferences = """
    {"brave":{"tabs":{"shared_pinned_tab":true},"sidebar":{"sidebar_items":[
      {"type":0,"built_in_item_type":3},
      {"type":0,"built_in_item_type":5},
      {"type":1,"built_in_item_type":0,"url":"https://mail.example.com/","title":"Mail","open_in_panel":false},
      {"type":1,"built_in_item_type":0,"url":"https://chat.example.com/","title":"Chat","open_in_panel":true}
    ]}}}
    """

    @Test func braveContainerPrefixesAreStrippedFromEveryAddress() throws {
        let container = "containers+0b1e2f3a-aaaa-4bbb-8ccc-000000000001:"
        var input = session([[Tab(id: 1, url: container + "https://wiki.example.com/", title: "Wiki"),
                              Tab(id: 2, url: "https://plain.example.com/", title: "Plain"),
                              Tab(id: 3, url: "brave://settings", title: "Settings")]])
        input.closedTabs = [ChromiumSession.ClosedTab(url: container + "https://old.example.com/", title: "Old", closedAt: nil)]
        try withProfile { profile in
            let result = ChromiumFlavorExtras.adjusted(input, flavor: .brave, profileDirectory: profile)
            #expect(urls(result) == ["https://wiki.example.com/", "https://plain.example.com/", "brave://settings"])
            #expect(result.closedTabs.map(\.url) == ["https://old.example.com/"])
        }
    }

    @Test func braveSharedPinnedTabsRepeatedInLaterWindowsAreDropped() throws {
        let input = session([
            [Tab(id: 1, url: "https://mail.example.com/", title: "", pinned: true), Tab(id: 2, url: "https://a.example.com/", title: "")],
            [Tab(id: 3, url: "https://mail.example.com/", title: "", pinned: true), Tab(id: 4, url: "https://mail.example.com/", title: "")]
        ])
        try withProfile(preferences: #"{"brave":{"tabs":{"shared_pinned_tab":true}}}"#) { profile in
            let result = ChromiumFlavorExtras.adjusted(input, flavor: .brave, profileDirectory: profile)
            #expect(result.windows[0].tabs.map(\.id) == [1, 2])
            #expect(result.windows[1].tabs.map(\.id) == [4])
        }
    }

    @Test func braveKeepsRepeatedPinsWhenSharingIsOff() throws {
        let input = session([
            [Tab(id: 1, url: "https://mail.example.com/", title: "", pinned: true)],
            [Tab(id: 3, url: "https://mail.example.com/", title: "", pinned: true)]
        ])
        try withProfile(preferences: #"{"brave":{"tabs":{"shared_pinned_tab":false}}}"#) { profile in
            #expect(ChromiumFlavorExtras.adjusted(input, flavor: .brave, profileDirectory: profile) == input)
        }
        try withProfile { profile in
            #expect(ChromiumFlavorExtras.adjusted(input, flavor: .brave, profileDirectory: profile) == input)
        }
    }

    @Test func bravePinnedTabsBehindSidebarPanelsAreDropped() throws {
        let input = session([[Tab(id: 1, url: "https://chat.example.com/", title: "", pinned: true),
                              Tab(id: 2, url: "https://mail.example.com/", title: "", pinned: true),
                              Tab(id: 3, url: "https://chat.example.com/", title: "")]])
        try withProfile(preferences: bravePreferences) { profile in
            let result = ChromiumFlavorExtras.adjusted(input, flavor: .brave, profileDirectory: profile)
            #expect(result.windows[0].tabs.map(\.id) == [2, 3])
        }
    }

    @Test func droppingTabsBeforeTheSelectionKeepsTheSelectedTabSelected() throws {
        var input = session([[Tab(id: 1, url: "https://chat.example.com/", title: "", pinned: true),
                              Tab(id: 2, url: "https://a.example.com/", title: ""),
                              Tab(id: 3, url: "https://b.example.com/", title: "")]])
        input.windows[0].selectedIndex = 2
        try withProfile(preferences: bravePreferences) { profile in
            let result = ChromiumFlavorExtras.adjusted(input, flavor: .brave, profileDirectory: profile)
            #expect(result.windows[0].tabs[result.windows[0].selectedIndex].id == 3)
        }
    }

    @Test func braveFavoritesAreTheTabOpeningWebItemsInOrder() throws {
        try withProfile(preferences: bravePreferences) { profile in
            let favorites = ChromiumFlavorExtras.favorites(flavor: .brave, profileDirectory: profile)
            let expected = try #require(SidebarImport.Tab.web(url: "https://mail.example.com/", title: "Mail"))
            #expect(favorites == [.tab(expected)])
            #expect(ChromiumFlavorExtras.favorites(flavor: .chrome, profileDirectory: profile).isEmpty)
            #expect(ChromiumFlavorExtras.favorites(flavor: .vivaldi, profileDirectory: profile).isEmpty)
        }
    }

    @Test func braveFavoritesStopAtTwelveAndSkipUnusableItems() throws {
        let items = (1...15).map {
            #"{"type":1,"url":"https://site\#($0).example.com/","title":"Site \#($0)","open_in_panel":false}"#
        } + [#"{"type":1,"url":"not a url","title":"Broken"}"#]
        try withProfile(preferences: #"{"brave":{"sidebar":{"sidebar_items":[\#(items.joined(separator: ","))]}}}"#) { profile in
            let favorites = ChromiumFlavorExtras.favorites(flavor: .brave, profileDirectory: profile)
            #expect(favorites.count == 12)
            guard case .tab(let first) = favorites[0], case .tab(let last) = favorites[11] else { Issue.record("not tabs"); return }
            #expect(first.url == "https://site1.example.com/" && last.url == "https://site12.example.com/")
        }
    }

    @Test func missingOrBrokenPreferencesMeanNoExtras() throws {
        try withProfile { profile in
            #expect(ChromiumFlavorExtras.favorites(flavor: .brave, profileDirectory: profile).isEmpty)
        }
        try withProfile(preferences: "{not json") { profile in
            #expect(ChromiumFlavorExtras.favorites(flavor: .brave, profileDirectory: profile).isEmpty)
        }
        try withProfile(preferences: "[1,2]") { profile in
            #expect(ChromiumFlavorExtras.favorites(flavor: .brave, profileDirectory: profile).isEmpty)
        }
    }

    private let vivaldiPreferences = """
    {"vivaldi":{"workspaces":{"list":[
      {"id":1682089802242,"name":"Work","icon":"<svg/>","emoji":"\u{1F4BC}"},
      {"id":1682089900001,"name":"Home","icon":"<svg/>"},
      {"id":1.7123456789e+12,"name":"Float form id","icon":"<svg/>","emoji":""},
      {"id":"bad","name":"Broken"}
    ]},"tabs":{"stacking":{"open_accordions":["11111111-1111-4111-8111-111111111111"]}}}}
    """

    private func vivaldiTab(_ id: Int32, _ url: String, pinned: Bool = false, ext: String) -> Tab {
        Tab(id: id, url: url, title: "", pinned: pinned, extraData: ["vivaldi.ext": ext])
    }

    private func vivaldiSession() -> ChromiumSession {
        let docs = "11111111-1111-4111-8111-111111111111"
        let unnamed = "22222222-2222-4222-8222-222222222222"
        return session([[
            vivaldiTab(1, "https://mail.example.com/", pinned: true,
                       ext: #"{"ext_id":"a1","workspaceId":1682089802242.0,"fixedTitle":"Inbox"}"#),
            vivaldiTab(2, "https://wiki.example.com/", pinned: true,
                       ext: #"{"workspaceId":1682089802242,"group":"\#(docs)","fixedGroupTitle":"Docs","groupColor":"blue"}"#),
            vivaldiTab(3, "https://api.example.com/", pinned: true,
                       ext: #"{"workspaceId":1682089802242.0,"group":"\#(docs)","fixedGroupTitle":"Docs"}"#),
            vivaldiTab(4, "https://news.example.com/", ext: #"{"workspaceId":1682089802242.0}"#),
            vivaldiTab(5, "https://docs.example.com/left",
                       ext: #"{"workspaceId":1682089802242.0,"tiling":{"id":"t-1","index":1,"layout":"column","type":"selection"}}"#),
            vivaldiTab(6, "https://docs.example.com/right",
                       ext: #"{"workspaceId":1682089802242.0,"tiling":{"id":"t-1","index":0,"layout":"column","type":"selection"}}"#),
            vivaldiTab(7, "https://photos.example.com/", ext: #"{"workspaceId":1682089900001.0,"group":"\#(unnamed)","fixedGroupTitle":null}"#),
            vivaldiTab(8, "https://video.example.com/", ext: #"{"workspaceId":1682089900001.0,"group":"\#(unnamed)"}"#),
            vivaldiTab(9, "https://loose.example.com/", ext: #"{"ext_id":"a9"}"#),
            vivaldiTab(10, "https://panel.example.com/", ext: #"{"panelId":"panel-1"}"#),
            vivaldiTab(11, "https://quarantined.example.com/", ext: #"{"workspaceId":1682089802242.0,"flag":1}"#),
            vivaldiTab(12, "https://unknown-space.example.com/", ext: #"{"workspaceId":1999999999999.0}"#),
            vivaldiTab(13, "https://mailtab.example.com/", ext: #"{"purpose":"mail","workspaceId":1682089802242.0}"#),
            Tab(id: 14, url: "https://noext.example.com/", title: "")
        ]])
    }

    @Test func vivaldiDropsPanelsMailAndQuarantinedTabs() throws {
        try withProfile(preferences: vivaldiPreferences) { profile in
            let result = ChromiumFlavorExtras.adjusted(vivaldiSession(), flavor: .vivaldi, profileDirectory: profile)
            #expect(result.windows[0].tabs.map(\.id) == [1, 2, 3, 4, 6, 5, 7, 8, 9, 12, 14])
        }
    }

    @Test func vivaldiKeepsCustomTitlesForTheMapping() throws {
        try withProfile(preferences: vivaldiPreferences) { profile in
            let result = ChromiumFlavorExtras.adjusted(vivaldiSession(), flavor: .vivaldi, profileDirectory: profile)
            let titled = result.windows[0].tabs.filter { $0.extraData["vivaldi.fixedTitle"] != nil }
            #expect(titled.map(\.id) == [1] && titled.first?.extraData["vivaldi.fixedTitle"] == "Inbox")
        }
    }

    @Test func vivaldiPinnedStacksBecomeNamedGroupsAndUnpinnedStacksFlatten() throws {
        try withProfile(preferences: vivaldiPreferences) { profile in
            let result = ChromiumFlavorExtras.adjusted(vivaldiSession(), flavor: .vivaldi, profileDirectory: profile)
            let tabs = result.windows[0].tabs
            let docs = try #require(tabs.first { $0.id == 2 }?.group)
            #expect(tabs.first { $0.id == 3 }?.group == docs)
            #expect(result.groups[docs]?.title == "Docs" && result.groups[docs]?.collapsed == false)
            #expect(result.groups.count == 1)
            #expect(tabs.filter { $0.group != nil }.map(\.id) == [2, 3])
        }
    }

    @Test func vivaldiStacksStayCollapsedUnlessListedAsOpen() throws {
        try withProfile(preferences: #"{"vivaldi":{"workspaces":{"list":[]}}}"#) { profile in
            let result = ChromiumFlavorExtras.adjusted(vivaldiSession(), flavor: .vivaldi, profileDirectory: profile)
            let docs = try #require(result.windows[0].tabs.first { $0.id == 2 }?.group)
            #expect(result.groups[docs]?.collapsed == true)
        }
    }

    @Test func vivaldiStockGroupAndSplitDataIsReplacedByTheExtData() throws {
        var input = vivaldiSession()
        let stock = ChromiumToken(high: 1, low: 2)
        input.windows[0].tabs[3].group = stock
        input.windows[0].tabs[3].split = stock
        input.groups[stock] = ChromiumSession.Group(title: "Stock", color: 1, collapsed: false)
        input.splits[stock] = ChromiumSession.Split(ratio: 0.3, sideBySide: true)
        try withProfile(preferences: vivaldiPreferences) { profile in
            let result = ChromiumFlavorExtras.adjusted(input, flavor: .vivaldi, profileDirectory: profile)
            let tab = try #require(result.windows[0].tabs.first { $0.id == 4 })
            #expect(tab.group == nil && tab.split == nil)
            #expect(result.groups[stock] == nil && result.splits[stock] == nil)
        }
    }

    @Test func vivaldiTilesBecomeEqualSplitsOrderedByTheirTileIndex() throws {
        try withProfile(preferences: vivaldiPreferences) { profile in
            let result = ChromiumFlavorExtras.adjusted(vivaldiSession(), flavor: .vivaldi, profileDirectory: profile)
            let tabs = result.windows[0].tabs
            let tiled = tabs.filter { $0.split != nil }
            #expect(tiled.map(\.id) == [6, 5])
            let token = try #require(tiled.first?.split)
            #expect(tiled.allSatisfy { $0.split == token })
            #expect(result.splits[token] == ChromiumSession.Split(ratio: 0.5, sideBySide: false))
        }
    }

    @Test func vivaldiRowTilesSitSideBySideAndLargeTilesKeepFourTabs() throws {
        let tabs = (1...6).map { index in
            vivaldiTab(Int32(index), "https://t\(index).example.com/",
                       ext: #"{"tiling":{"id":"big","index":\#(index),"layout":"row"}}"#)
        } + [vivaldiTab(7, "https://solo.example.com/", ext: #"{"tiling":{"id":"solo","index":0,"layout":"row"}}"#)]
        try withProfile { profile in
            let result = ChromiumFlavorExtras.adjusted(session([tabs]), flavor: .vivaldi, profileDirectory: profile)
            let tiled = result.windows[0].tabs.filter { $0.split != nil }
            #expect(tiled.map(\.id) == [1, 2, 3, 4])
            #expect(result.splits.values.map(\.sideBySide) == [true])
            #expect(result.windows[0].tabs.filter { $0.split == nil }.map(\.id) == [5, 6, 7])
        }
    }

    @Test func vivaldiSpacesFollowTheWorkspaceListAndKeepEveryTab() throws {
        try withProfile(preferences: vivaldiPreferences) { profile in
            let spaces = try #require(ChromiumFlavorExtras.spaces(vivaldiSession(), flavor: .vivaldi, profile: importProfile(profile)))
            let folder = profile.lastPathComponent
            #expect(spaces.map(\.space.id) == ["vivaldi:\(folder):default", "vivaldi:\(folder):1682089802242",
                                               "vivaldi:\(folder):1682089900001", "vivaldi:\(folder):1712345678900"])
            #expect(spaces.map(\.space.title) == [nil, "Work", "Home", "Float form id"])
            #expect(spaces.map(\.space.icon) == [nil, .emoji("\u{1F4BC}"), nil, nil])
            #expect(spaces.map(\.space.placement) == [.profileHome, .new, .new, .new])
            #expect(spaces[0].windowTabs == [1: [9, 12, 14]])
            #expect(spaces[1].windowTabs == [1: [1, 2, 3, 4, 5, 6]])
            #expect(spaces[2].windowTabs == [1: [7, 8]])
            #expect(spaces[3].windowTabs.isEmpty)
        }
    }

    @Test func vivaldiSessionsWithoutUnassignedTabsHaveNoHomeSpace() throws {
        let input = session([[vivaldiTab(1, "https://a.example.com/", ext: #"{"workspaceId":1682089900001.0}"#)]])
        try withProfile(preferences: vivaldiPreferences) { profile in
            let spaces = try #require(ChromiumFlavorExtras.spaces(input, flavor: .vivaldi, profile: importProfile(profile)))
            #expect(spaces.map(\.space.title) == ["Work", "Home", "Float form id"])
        }
    }

    @Test func vivaldiWithoutWorkspacesLeavesSpacesToTheGenericMapping() throws {
        try withProfile(preferences: #"{"vivaldi":{"workspaces":{"list":[]}}}"#) { profile in
            #expect(ChromiumFlavorExtras.spaces(vivaldiSession(), flavor: .vivaldi, profile: importProfile(profile)) == nil)
        }
        try withProfile(preferences: #"{"vivaldi":{"workspaces":{"enabled":false,"list":[{"id":1,"name":"Off"}]}}}"#) { profile in
            #expect(ChromiumFlavorExtras.spaces(vivaldiSession(), flavor: .vivaldi, profile: importProfile(profile)) == nil)
        }
        try withProfile { profile in
            #expect(ChromiumFlavorExtras.spaces(vivaldiSession(), flavor: .vivaldi, profile: importProfile(profile)) == nil)
        }
    }

    @Test func otherFlavorsBuildNoSpaces() throws {
        try withProfile(preferences: vivaldiPreferences) { profile in
            for flavor in [ChromiumFlavor.chrome, .brave, .helium, .edge] {
                #expect(ChromiumFlavorExtras.spaces(vivaldiSession(), flavor: flavor, profile: importProfile(profile)) == nil)
            }
        }
    }

    private let operaPreferences = """
    {"ui":{"workspaces":{"config":{
      "enabled":true,"next_id":3,"order":[1,0,2],
      "names":{"0":"Workspace 1","1":"Work","2":"Gaming"},
      "icons":{"0":"star-icon","1":"work-icon","2":"add-custom-icon"},
      "emoji_icons":{"2":"\u{1F3AE}"},
      "visible_in_ui":{"0":true,"1":true,"2":false}
    }}}}
    """

    private func operaTab(_ id: Int32, _ state: String?) -> Tab {
        Tab(id: id, url: "https://t\(id).example.com/", title: "", extraData: state.map { ["workspaces_state": $0] } ?? [:])
    }

    @Test func operaSpacesFollowTheConfiguredOrderAndSortTabsByWorkspace() throws {
        let input = session([[operaTab(1, "1"), operaTab(2, "0"), operaTab(3, "2"), operaTab(4, "1")], [operaTab(5, "0"), operaTab(6, "2")]])
        try withProfile(preferences: operaPreferences) { profile in
            for flavor in [ChromiumFlavor.opera, .operaGX] {
                let spaces = try #require(ChromiumFlavorExtras.spaces(input, flavor: flavor, profile: importProfile(profile)))
                let folder = profile.lastPathComponent
                #expect(spaces.map(\.space.id) == ["opera:\(folder):1", "opera:\(folder):0", "opera:\(folder):2"])
                #expect(spaces.map(\.space.title) == ["Work", "Workspace 1", "Gaming"])
                #expect(spaces.map(\.space.icon) == [nil, nil, .emoji("\u{1F3AE}")])
                #expect(spaces[0].windowTabs == [1: [1, 4]])
                #expect(spaces[1].windowTabs == [1: [2], 2: [5]])
                #expect(spaces[2].windowTabs == [1: [3], 2: [6]])
            }
        }
    }

    @Test func operaTabsWithoutAKnownWorkspaceGoToTheFirstWorkspaceInOrder() throws {
        let input = session([[operaTab(1, nil), operaTab(2, "9"), operaTab(3, "junk"), operaTab(4, "2")]])
        try withProfile(preferences: operaPreferences) { profile in
            let spaces = try #require(ChromiumFlavorExtras.spaces(input, flavor: .opera, profile: importProfile(profile)))
            #expect(spaces.map(\.space.title) == ["Work", "Gaming"])
            #expect(spaces[0].windowTabs == [1: [1, 2, 3]])
            #expect(spaces[1].windowTabs == [1: [4]])
        }
    }

    @Test func operaHiddenWorkspacesComeOverOnlyWhenTheyHoldTabs() throws {
        try withProfile(preferences: operaPreferences) { profile in
            let none = try #require(ChromiumFlavorExtras.spaces(session([[operaTab(1, "1")]]), flavor: .opera, profile: importProfile(profile)))
            #expect(none.map(\.space.title) == ["Work", "Workspace 1"])
            let some = try #require(ChromiumFlavorExtras.spaces(session([[operaTab(1, "2")]]), flavor: .opera, profile: importProfile(profile)))
            #expect(some.map(\.space.title) == ["Work", "Workspace 1", "Gaming"])
        }
    }

    @Test func operaEmojiNeedsTheCustomIconMarker() throws {
        let prefs = #"{"ui":{"workspaces":{"config":{"order":[0],"names":{"0":"Solo"},"icons":{"0":"star-icon"},"emoji_icons":{"0":"X"}}}}}"#
        try withProfile(preferences: prefs) { profile in
            let spaces = try #require(ChromiumFlavorExtras.spaces(session([[operaTab(1, "0")]]), flavor: .opera, profile: importProfile(profile)))
            #expect(spaces.map(\.space.icon) == [nil])
        }
    }

    @Test func operaConfigsAreReadDefensively() throws {
        let listForm = #"{"ui":{"workspaces":{"config":{"names":["A","B"],"order":["1"]}}}}"#
        try withProfile(preferences: listForm) { profile in
            let spaces = try #require(ChromiumFlavorExtras.spaces(session([[operaTab(1, "0")]]), flavor: .opera, profile: importProfile(profile)))
            #expect(spaces.map(\.space.title) == ["B", "A"])
            #expect(spaces[1].windowTabs == [1: [1]])
        }
    }

    @Test func operaWithoutAUsableWorkspaceConfigBuildsNoSpaces() throws {
        let input = session([[operaTab(1, "0")]])
        try withProfile { profile in
            #expect(ChromiumFlavorExtras.spaces(input, flavor: .opera, profile: importProfile(profile)) == nil)
        }
        try withProfile(preferences: #"{"ui":{"workspaces":{"config":{"enabled":false,"names":{"0":"Off"},"order":[0]}}}}"#) { profile in
            #expect(ChromiumFlavorExtras.spaces(input, flavor: .opera, profile: importProfile(profile)) == nil)
        }
        try withProfile(preferences: #"{"ui":{"workspaces":{"config":{}}}}"#) { profile in
            #expect(ChromiumFlavorExtras.spaces(input, flavor: .operaGX, profile: importProfile(profile)) == nil)
        }
    }

    @Test func operaWorkspacesDoNotChangeTheSessionItself() throws {
        let input = session([[operaTab(1, "1"), operaTab(2, "0")]])
        try withProfile(preferences: operaPreferences) { profile in
            #expect(ChromiumFlavorExtras.adjusted(input, flavor: .opera, profileDirectory: profile) == input)
        }
    }
}
