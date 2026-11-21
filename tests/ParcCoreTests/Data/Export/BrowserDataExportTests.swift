import Foundation
import Testing
@testable import ParcCore

@MainActor
struct BrowserDataExportTests {
    let profile = BrowserProfile(id: UUID(), name: "Primary")
    let otherProfile = BrowserProfile(id: UUID(), name: "Other")
    let space: BrowserSpace
    let second: BrowserSpace
    let third: BrowserSpace
    let folder: BrowserFolder
    let empty: BrowserFolder
    let pinned: BrowserTab
    let state: BrowserState

    static let expected = """
    # Work Today

    ## Favorites
    - https://favorite.example/
    - https://pane-two.example/
    - https://pane-one.example/
    - https://saved.example/
    - https://today.example/

    ## Reading List
    - https://nested.example/

    ## Empty

    # Space 2

    ## Favorites
    - https://favorite.example/

    # Other

    ## Favorites
    - https://other-profile.example/

    """

    static func tab(_ saved: String, kind: TabKind = .pinned, owner: BrowserSpace, folderID: UUID? = nil) -> BrowserTab {
        BrowserTab(id: UUID(), spaceID: owner.id, profileID: owner.profileID, url: saved, title: "Not a Markdown title",
                   kind: kind, folderID: folderID, createdAt: Date(timeIntervalSince1970: 1),
                   lastAccessed: Date(timeIntervalSince1970: 2), savedURL: saved, savedTitle: "Saved label")
    }

    init() {
        space = BrowserSpace(id: UUID(), name: "Work\r\nToday", symbol: "circle", color: "B9B5D4", profileID: profile.id)
        second = BrowserSpace(id: UUID(), name: "", symbol: "circle", color: "B9B5D4", profileID: profile.id)
        third = BrowserSpace(id: UUID(), name: "Other", symbol: "circle", color: "B9B5D4", profileID: otherProfile.id)
        folder = BrowserFolder(id: UUID(), spaceID: space.id, name: "Reading\n\nList", isExpanded: false)
        empty = BrowserFolder(id: UUID(), spaceID: space.id, name: "Empty")
        let space = space
        let favorite = Self.tab("https://favorite.example/", kind: .favorite, owner: space)
        var pinned = Self.tab("https://saved.example/", owner: space)
        pinned.url = "https://live.example/"
        pinned.customTitle = "Custom label"
        self.pinned = pinned
        let today = Self.tab("https://today.example/", kind: .today, owner: space)
        let nested = Self.tab("https://nested.example/", owner: space, folderID: folder.id)
        let pane1 = Self.tab("https://pane-one.example/", owner: space)
        let pane2 = Self.tab("https://pane-two.example/", owner: space)
        let note = Self.tab(InternalPage.note(URL(fileURLWithPath: NSTemporaryDirectory() + "Parc Notes/" + UUID().uuidString + ".md")).urlString, owner: space)
        let easel = Self.tab(InternalPage.easel(UUID()).urlString, owner: space)
        var archived = Self.tab("https://archived.example/", owner: space)
        archived.archivedAt = Date()
        let foreign = Self.tab("https://other-profile.example/", kind: .favorite, owner: third)
        var state = BrowserState(profiles: [profile, otherProfile], spaces: [space, second, third], activeSpaceID: space.id)
        for index in state.spaces.indices { state.spaces[index].updateDisplayName(position: index) }
        state.tabs = [favorite, pinned, today, nested, pane1, pane2, note, easel, archived, foreign]
        state.folders = [folder, empty]
        state.splitLayouts = [.init(sidebarAnchorID: pane1.id, spaceID: space.id, tabIDs: [pane2.id, pane1.id], widthFactors: [0.5, 0.5])]
        state.sidebarItemOrder[SidebarContainerLocation(spaceID: space.id, folderID: nil, section: .pinned).key] =
            [.folder(folder.id), .tab(pane1.id), .folder(empty.id), .tab(pinned.id)]
        self.state = state
    }

    @Test func exportRecoversSpacesFoldersSavedDestinationsAndSplitOrder() {
        #expect(BrowserDataExport(state: state).markdown == Self.expected)
    }

    @Test func exportDoesNotResetALiveTab() {
        _ = BrowserDataExport(state: state)
        #expect(state.tabs.first(where: { $0.id == pinned.id })?.url == pinned.url)
    }

    @Test func customSidebarTitlesDoNotReplaceSavedURLs() {
        #expect(!BrowserDataExport(state: state).markdown.contains("Custom label"))
    }

    @Test func archivedItemsAreNotCurrentSidebarChildren() {
        #expect(!BrowserDataExport(state: state).markdown.contains("archived.example"))
    }

    @Test func nativeDocumentsAreNotTabLinks() {
        let markdown = BrowserDataExport(state: state).markdown
        #expect(!markdown.contains("parc://note") && !markdown.contains("parc://easel"))
    }

    @Test func theSnapshotSurvivesLaterRemoval() {
        var state = state
        let snapshot = BrowserDataExport(state: state)
        state.tabs.removeAll()
        state.spaces.removeAll()
        state.folders.removeAll()
        #expect(snapshot.markdown == Self.expected)
        #expect(BrowserDataExport(state: state).markdown.isEmpty)
    }

    @Test func headingDepthCapsAtSixWithoutDroppingDescendants() {
        var state = state
        state.spaces = [space]
        state.folders = []
        var parent: UUID?
        for depth in 0..<8 {
            let child = BrowserFolder(id: UUID(), spaceID: space.id, name: "Level \(depth)", parentID: parent)
            state.folders.append(child)
            parent = child.id
        }
        state.tabs = [Self.tab("https://deep.example/", owner: space, folderID: parent)]
        let deep = BrowserDataExport(state: state).markdown
        #expect(deep.contains("###### Level 7\n- https://deep.example/"))
        #expect(!deep.contains("#######"))
    }

    @Test func headingNormalizationUsesActualUnicodeNewlineCharacters() {
        var state = state
        state.spaces = [space]
        state.spaces[0].name = "\n\u{000B}One\u{0085}Two\u{2028}Three\u{2029}\r\n"
        #expect(BrowserDataExport(state: state).markdown.hasPrefix("# One Two Three\n"))
    }

    @Test func atomicExportReplacesTheDestinationWithExactUTF8AndLeavesNoTemporaryOutput() throws {
        try DataFixtures.withTemporaryDirectory { root in
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
            let target = root.appendingPathComponent("Parc Data Export.md")
            try Data("previous".utf8).write(to: target)
            try BrowserDataExport(state: state).write(to: target)
            let actual = try String(contentsOf: target, encoding: .utf8)
            #expect(actual == Self.expected)
            let files = try FileManager.default.contentsOfDirectory(atPath: root.path)
            #expect(files == ["Parc Data Export.md"])
        }
    }

    @Test func aFailedExportPropagatesAndPreservesExistingFiles() throws {
        try DataFixtures.withTemporaryDirectory { root in
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
            let snapshot = BrowserDataExport(state: state)
            let target = root.appendingPathComponent("Parc Data Export.md")
            try snapshot.write(to: target)
            #expect(throws: (any Error).self) { try snapshot.write(to: root.appendingPathComponent("absent/failed.md")) }
            let actual = try String(contentsOf: target, encoding: .utf8)
            #expect(actual == Self.expected)
        }
    }

    @Test func onlyLocalSaveDestinationsAreSupported() {
        #expect(throws: (any Error).self) {
            try BrowserDataExport(state: state).write(to: URL(string: "https://example.com/no-upload")!)
        }
    }
}
