import Foundation

@main
struct BrowserDataExportTests {
    static var assertions = 0
    static func expect(_ value: @autoclosure () -> Bool, _ message: String) {
        assertions += 1
        precondition(value(), message)
    }
    @MainActor static func main() { exitOnFailure(runChecks) }
    @MainActor static func runChecks() throws {
        let profile = BrowserProfile(id: UUID(), name: "Primary")
        let otherProfile = BrowserProfile(id: UUID(), name: "Other")
        let space = BrowserSpace(id: UUID(), name: "Work\r\nToday", symbol: "circle", color: "B9B5D4", profileID: profile.id)
        let second = BrowserSpace(id: UUID(), name: "", symbol: "circle", color: "B9B5D4", profileID: profile.id)
        let third = BrowserSpace(id: UUID(), name: "Other", symbol: "circle", color: "B9B5D4", profileID: otherProfile.id)
        let folder = BrowserFolder(id: UUID(), spaceID: space.id, name: "Reading\n\nList", isExpanded: false)
        let empty = BrowserFolder(id: UUID(), spaceID: space.id, name: "Empty")
        func tab(_ saved: String, kind: TabKind = .pinned, owner: BrowserSpace? = nil, folderID: UUID? = nil) -> BrowserTab {
            let s = owner ?? space
            return BrowserTab(id: UUID(), spaceID: s.id, profileID: s.profileID, url: saved, title: "Not a Markdown title",
                              kind: kind, folderID: folderID, createdAt: Date(timeIntervalSince1970: 1),
                              lastAccessed: Date(timeIntervalSince1970: 2), savedURL: saved, savedTitle: "Saved label")
        }
        let favorite = tab("https://favorite.example/", kind: .favorite)
        var pinned = tab("https://saved.example/")
        pinned.url = "https://live.example/"; pinned.customTitle = "Custom label"
        let today = tab("https://today.example/", kind: .today)
        let nested = tab("https://nested.example/", folderID: folder.id)
        let pane1 = tab("https://pane-one.example/"), pane2 = tab("https://pane-two.example/")
        let note = tab(InternalPage.note(UUID()).urlString)
        let easel = tab(InternalPage.easel(UUID()).urlString)
        var archived = tab("https://archived.example/"); archived.archivedAt = Date()
        let foreign = tab("https://other-profile.example/", kind: .favorite, owner: third)
        var state = BrowserState(profiles: [profile, otherProfile], spaces: [space, second, third], activeSpaceID: space.id)
        for index in state.spaces.indices { state.spaces[index].updateDisplayName(position: index) }
        state.tabs = [favorite, pinned, today, nested, pane1, pane2, note, easel, archived, foreign]
        state.folders = [folder, empty]
        state.splitLayouts = [.init(sidebarAnchorID: pane1.id, spaceID: space.id, tabIDs: [pane2.id, pane1.id], widthFactors: [0.5, 0.5])]
        state.sidebarItemOrder[SidebarContainerLocation(spaceID: space.id, folderID: nil, section: .pinned).key] = [.folder(folder.id), .tab(pane1.id), .folder(empty.id), .tab(pinned.id)]
        let snapshot = BrowserDataExport(state: state)
        let expected = """
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
        expect(snapshot.markdown == expected, "Recovered Markdown structure, saved destination, split order and folder passes")
        expect(state.tabs.first(where: { $0.id == pinned.id })?.url == pinned.url, "Export does not reset a live tab")
        expect(!snapshot.markdown.contains("Custom label"), "Custom sidebar titles do not replace saved URLs")
        expect(!snapshot.markdown.contains("archived.example"), "Archived items are not current sidebar children")
        expect(!snapshot.markdown.contains("parc://note") && !snapshot.markdown.contains("parc://easel"), "Native documents are not tab links")
        state.tabs.removeAll(); state.spaces.removeAll(); state.folders.removeAll()
        expect(snapshot.markdown == expected, "The sheet snapshot survives later navigation/removal/reordering")
        expect(BrowserDataExport(state: state).markdown.isEmpty, "Empty state exports empty data")

        state.spaces = [space]; state.folders = []
        var parent: UUID?
        for depth in 0..<8 {
            let child = BrowserFolder(id: UUID(), spaceID: space.id, name: "Level \(depth)", parentID: parent)
            state.folders.append(child); parent = child.id
        }
        state.tabs = [tab("https://deep.example/", folderID: parent)]
        let deep = BrowserDataExport(state: state).markdown
        expect(deep.contains("###### Level 7\n- https://deep.example/"), "Heading depth caps at six without dropping descendants")
        expect(!deep.contains("#######"), "No invalid deeper Markdown headings")
        state.spaces[0].name = "\n\u{000B}One\u{0085}Two\u{2028}Three\u{2029}\r\n"
        expect(BrowserDataExport(state: state).markdown.hasPrefix("# One Two Three\n"), "Heading normalization uses actual Unicode newline characters")

        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ParcDataExport-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let target = root.appendingPathComponent("Parc Data Export.md")
        try Data("previous".utf8).write(to: target)
        try snapshot.write(to: target)
        let saved = try String(contentsOf: target, encoding: .utf8)
        expect(saved == expected, "Atomic export replaces the destination with exact UTF-8")
        let files = try FileManager.default.contentsOfDirectory(atPath: root.path)
        expect(files == ["Parc Data Export.md"], "Atomic save leaves no temporary output")
        do {
            try snapshot.write(to: root.appendingPathComponent("absent/failed.md"))
            preconditionFailure("Missing destination parent must fail")
        } catch { expect(true, "Real disk failure propagates to the native error presenter") }
        let retained = try String(contentsOf: target, encoding: .utf8)
        expect(retained == expected, "A failed export preserves existing files")
        do {
            try snapshot.write(to: URL(string: "https://example.com/no-upload")!)
            preconditionFailure("Remote export must fail")
        } catch { expect(true, "Only native local save destinations are supported") }
        print("BrowserDataExport: \(assertions) assertions passed")
    }
}
