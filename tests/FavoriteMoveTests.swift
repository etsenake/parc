import Foundation

@main @MainActor
struct FavoriteMoveTests {
    static var count = 0
    static func check(_ value: @autoclosure () throws -> Bool, _ reason: String) throws {
        count += 1; if try !value() { throw NSError(domain: reason, code: count) }
    }
    static func main() { exitOnFailure(runChecks) }
    static func runChecks() throws {
        let profile = BrowserProfile(id: UUID(), name: "Original"), foreign = BrowserProfile(id: UUID(), name: "Other")
        let home = BrowserSpace(id: UUID(), name: "Home", symbol: "circle", color: "AABBCC", profileID: profile.id)
        let active = BrowserSpace(id: UUID(), name: "Active", symbol: "circle", color: "AABBCC", profileID: profile.id)
        let other = BrowserSpace(id: UUID(), name: "Other", symbol: "circle", color: "AABBCC", profileID: foreign.id)
        let folder = BrowserFolder(id: UUID(), spaceID: active.id, name: "Destination")
        let noteID = URL(fileURLWithPath: NSTemporaryDirectory() + "Parc Notes/" + UUID().uuidString + ".md"), easelID = UUID()
        func tab(_ title: String, kind: TabKind = .favorite, url: String? = nil, space: UUID? = nil, profileID: UUID? = nil) -> BrowserTab {
            let url = url ?? "https://example.invalid/" + title
            return BrowserTab(id: UUID(), spaceID: space ?? home.id, profileID: profileID ?? profile.id,
                url: url, title: title, kind: kind, createdAt: Date(timeIntervalSince1970: 1), lastAccessed: Date(timeIntervalSince1970: 2),
                savedURL: url, savedTitle: title, referrerID: UUID(), activeTabBeforeCreationID: UUID())
        }
        let first = tab("First"), note = tab("Note", url: InternalPage.note(noteID).urlString)
        let easel = tab("Easel", url: InternalPage.easel(easelID).urlString)
        let today = tab("Today", kind: .today, space: active.id)
        let alien = tab("Alien", space: other.id, profileID: foreign.id)
        let group = BrowserSplitLayout(sidebarAnchorID: note.id, customTitle: "Documents", spaceID: home.id,
            tabIDs: [note.id,easel.id], orientation: .vertical, widthFactors: [0.3,0.7])
        var state = BrowserState(profiles: [profile,foreign], spaces: [home,active,other], activeSpaceID: active.id)
        state.tabs = [first,note,easel,today,alien]; state.splitLayouts = [group]; state.folders = [folder]
        let tray = SidebarContainerLocation(spaceID: active.id, folderID: nil, section: .favorite, profileID: profile.id)
        let homeTray = SidebarContainerLocation(spaceID: home.id, folderID: nil, section: .favorite, profileID: profile.id)
        let top = SidebarContainerLocation(spaceID: active.id, folderID: nil, section: .today)
        let pinned = SidebarContainerLocation(spaceID: active.id, folderID: folder.id, section: .pinned)
        func snapshot(_ value: BrowserState) -> SidebarHierarchySnapshot { SidebarHierarchySnapshot(state: value, spaceID: active.id, profileID: profile.id, includesFavorites: true)! }
        try check(tray.key == homeTray.key, "Favorite order belongs to Profile, not visible Space")
        try check(SidebarHierarchy.children(in: tray, state: state) == [.tab(first.id),.split(group.id)], "Whole group, no duplicate children or foreign profile")
        try check(SidebarHierarchy.children(in: homeTray, state: state) == SidebarHierarchy.children(in: tray, state: state), "Two Spaces share same original tray")
        try check(SidebarHierarchy.location(of: .tab(note.id), state: state, spaceID: active.id) == nil, "Child is not independently movable")
        let reorder = SidebarHierarchy.moving([.split(group.id)], to: tray, before: .tab(first.id), expected: snapshot(state), state: state)!
        try check(SidebarHierarchy.children(in: homeTray, state: reorder) == [.split(group.id),.tab(first.id)], "Reorder visible from original home Space")
        let keyboard = SidebarKeyboardNavigation.items(state: reorder, spaceID: active.id, selected: [], focused: nil, available: { _ in true })
        try check(keyboard.prefix(2).map(\.reference) == [.split(group.id),.tab(first.id)], "Keyboard cursor follows original tray order as whole group")
        let positions = PositionalTabNavigation.items(state: reorder, spaceID: active.id, selected: [], focused: nil, available: { _ in true })
        try check(positions.prefix(2).map(\.tabIDs) == [group.tabIDs,[first.id]], "Tab navigation follows visible tray order")
        try check(positions.first?.orientation == .vertical, "Favorite group navigation retains original orientation")
        try check(reorder.tabs == state.tabs && reorder.splitLayouts == state.splitLayouts, "Reorder preserves complete originals and geometry")
        var renamed = state; renamed.splitLayouts[0].customTitle = "Changed"
        try check(SidebarHierarchy.moving([.split(group.id)], to: tray, before: nil, expected: snapshot(state), state: renamed) == nil, "Stale group snapshot refused")
        try check(SidebarHierarchy.moving([.folder(folder.id)], to: tray, before: nil, expected: snapshot(state), state: state) == nil, "Folder cannot become a Favorite")
        try check(SidebarHierarchy.moving([.tab(alien.id)], to: tray, before: nil, expected: snapshot(state), state: state) == nil, "Foreign profile cannot enter tray")
        let wrong = SidebarContainerLocation(spaceID: active.id, folderID: nil, section: .favorite, profileID: foreign.id)
        try check(SidebarHierarchy.moving([.tab(today.id)], to: wrong, before: nil, expected: snapshot(state), state: state) == nil, "Spoofed tray profile refused")
        try check(SidebarHierarchy.moving([.tab(first.id)], to: top, before: nil,
            expected: SidebarHierarchySnapshot(state: state, spaceID: active.id, profileID: profile.id)!, state: state) == nil, "Ordinary outline snapshot does not admit Favorite")
        let moved = SidebarHierarchy.moving([.split(group.id)], to: pinned, before: nil, expected: snapshot(state), state: state)!
        try check(moved.tabs.filter { group.tabIDs.contains($0.id) }.allSatisfy { $0.kind == .pinned && $0.spaceID == active.id && $0.folderID == folder.id }, "Move out uses active destination Space for all children")
        var movedGroup = group; movedGroup.spaceID = active.id
        try check(moved.splitLayouts == [movedGroup], "Original group ID/title/order/ratios preserved")
        try check(moved.tabs.first { $0.id == note.id }?.url == note.url && moved.tabs.first { $0.id == easel.id }?.url == easel.url, "Typed document IDs retained, no clones")
        try check(moved.tabs.first { $0.id == note.id }?.referrerID == note.referrerID, "Move does not mint creation provenance")
        try check(moved.tabs.first { $0.id == first.id } == first, "Unrelated original remains exact")
        try check(SidebarHierarchy.children(in: tray, state: moved) == [.tab(first.id)], "Whole group removed from profile tray")
        try check(moved.folders[0].isExpanded, "Destination disclosed through same transaction")
        let back = SidebarHierarchy.moving([.split(group.id)], to: tray, before: nil, expected: snapshot(moved), state: moved)!
        try check(back.tabs.filter { group.tabIDs.contains($0.id) }.allSatisfy { $0.kind == .favorite && $0.folderID == nil }, "Whole group can return to tray")
        try check(SidebarHierarchy.children(in: homeTray, state: back) == [.tab(first.id),.split(group.id)], "New tray order again Profile-wide")
        let collection = SidebarWindowMove(items: [.split(group.id)], sourceSpaceID: home.id, profileID: profile.id, to: top, before: nil, state: state)!
        try check(collection.tabIDs == group.tabIDs && collection.collection.tabs == [note,easel], "Physical transfer captures complete original records")
        let transferred = collection.applying(to: state)!
        try check(transferred.splitLayouts == [movedGroup] && transferred.tabs.filter { group.tabIDs.contains($0.id) }.allSatisfy { $0.spaceID == active.id && $0.kind == .today }, "Physical move shares same complete model transaction")
        var changedURL = state; changedURL.tabs[1].url = "https://changed.invalid"
        try check(collection.applying(to: changedURL) == nil, "Physical transfer refuses changed original metadata")
        var full = state
        full.tabs += (0..<10).map { tab("extra\($0)") }
        try check(SidebarHierarchy.children(in: tray, state: full).count == 12, "Split counts as one Favorite root")
        try check(SidebarHierarchy.moving([.tab(today.id)], to: tray, before: nil, expected: snapshot(full), state: full) == nil, "Plural transaction refuses thirteenth root")
        try check(SidebarHierarchy.moving(.tab(today.id), to: tray, before: nil, expected: snapshot(full), state: full) == nil, "Direct helper also refuses thirteenth root")
        try check(SidebarHierarchy.moving([.split(group.id)], to: tray, before: .tab(first.id), expected: snapshot(full), state: full) != nil, "Reorder at cap is allowed")
        var almost = full; almost.tabs.removeLast()
        let second = tab("Second incoming", kind: .today, space: active.id); almost.tabs.append(second)
        try check(SidebarHierarchy.moving([.tab(today.id),.tab(second.id)], to: tray, before: nil, expected: snapshot(almost), state: almost) == nil, "Batch that exceeds cap does not partially publish")
        try check(SidebarWindowMove(items: [.tab(today.id)], sourceSpaceID: active.id, profileID: profile.id, to: tray, before: nil, state: full) == nil, "Physical transfer preflight also refuses cap")

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("parc-favorite-move-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let file = directory.appendingPathComponent("session.json"); try encoder.encode(state).write(to: file)
        let store = try BrowserStore(directory: directory, now: { Date(timeIntervalSince1970: 10) })
        store.selectTab(note.id)
        try check(store.state.selectedTabIDs == group.tabIDs && store.activeSpaceID == active.id, "Favorite split activation keeps current Space and exact panes")
        try check(store.activeSplitLayout == group, "Active layout resolves original home-Space group")
        var presentation = WindowPresentation(state: store.state, ready: true)
        try check(presentation.splitLayout?.id == group.id && presentation.splitLayout?.widthFactors == group.widthFactors, "Physical window remembers original ratios")
        try check(store.setWindowPresentation(spaceID: active.id, selectedTabIDs: group.tabIDs, splitLayout: presentation.splitLayout), "Projected layout accepted")
        try check(store.state.splitLayouts == [group], "Projection does not duplicate/rehome shared group")
        try check(store.setSplitLayout(orientation: .horizontal, widthFactors: [0.6,0.4]), "Resize actual shared group")
        try check(store.state.splitLayouts.count == 1 && store.state.splitLayouts[0].id == group.id && store.state.splitLayouts[0].spaceID == home.id, "Resize preserves original group owner")
        presentation.reconcile(store.state, available: { _ in true })
        try check(presentation.splitLayout?.widthFactors == [0.6,0.4], "Window consumes current group geometry")
        let before = store.state, bytes = try Data(contentsOf: file)
        let move = SidebarWindowMove(items: [.split(group.id)], sourceSpaceID: active.id, profileID: profile.id, to: top, before: nil, state: before)!
        try FileManager.default.removeItem(at: file); try FileManager.default.createDirectory(at: file, withIntermediateDirectories: false)
        do { _ = try store.commitSidebarWindowMove(move); preconditionFailure("Expected write refusal") } catch {}
        try check(store.state == before, "Failed durable publication leaves all originals unchanged")
        try FileManager.default.removeItem(at: file); try bytes.write(to: file)
        try check(try store.commitSidebarWindowMove(move), "One original collection commits")
        let reloaded = try BrowserStore(directory: directory, now: { Date(timeIntervalSince1970: 10) })
        try check(reloaded.state.tabs == store.state.tabs && reloaded.state.splitLayouts == store.state.splitLayouts && reloaded.state.sidebarItemOrder == store.state.sidebarItemOrder, "Original identities/order/layout durably reload")
        try check(try !store.commitSidebarWindowMove(move), "Completed intent cannot replay")
        print("\(count) Favorite move assertions passed")
    }
}
