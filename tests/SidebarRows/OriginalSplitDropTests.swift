import Foundation

@main @MainActor struct OriginalSplitDropTests {
    static var count = 0
    static func check(_ value: @autoclosure () throws -> Bool, _ reason: String) throws {
        count += 1; if try !value() { throw NSError(domain: reason, code: count) }
    }
    static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("parc-original-split-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try BrowserStore(directory: root)
        let a = store.open("https://saved.invalid", kind: .pinned), b = store.open("https://ordinary.invalid")
        let c = store.open("https://sibling.invalid", kind: .pinned)
        store.selectTab(a)
        let original = store.state, profile = store.activeSpace.profileID, space = store.activeSpaceID
        let home = UUID(), now = Date(timeIntervalSince1970: 1234)
        func propose(_ state: BrowserState, source: UUID = b, target: SplitDropTarget = .insert(1),
                     layout: BrowserSplitLayout? = nil, homes: [UUID: UUID] = [a: home]) -> BrowserState? {
            OriginalSplitDrop.proposal(source: source, state: state, selection: state.selectedTabIDs,
                layout: layout, target: target, orientation: .horizontal, spaceID: space,
                profileID: profile, now: now, savedHomeIDs: homes,
                creation: TabCreationProvenance(referrerID: nil, activeTabID: a, profileID: profile, state: state))
        }
        var pinned = original
        let ai = pinned.tabs.firstIndex { $0.id == a }!, bi = pinned.tabs.firstIndex { $0.id == b }!
        pinned.tabs[ai].url = "https://live.invalid/form"; pinned.tabs[ai].title = "Live"
        pinned.tabs[ai].customTitle = "Authored"; pinned.tabs[ai].referrerID = b
        let location = SidebarContainerLocation(spaceID: space, folderID: nil, section: .pinned)
        pinned.sidebarItemOrder[location.key] = [.tab(c), .tab(a)]
        let p = propose(pinned)!, live = p.tabs.first { $0.id == a }!, copy = p.tabs.first { $0.id == home }!
        try check(p.selectedTabIDs == [a,b] && p.splitLayouts.count == 1, "actual original identities form group")
        try check(live.url == pinned.tabs[ai].url && live.title == "Live" && live.referrerID == b && live.kind == .today, "live request/provenance retained")
        try check(copy.url == pinned.tabs[ai].savedURL && copy.title == pinned.tabs[ai].savedTitle && copy.customTitle == "Authored", "home uses actual saved destination and title")
        try check(copy.referrerID == nil && copy.activeTabBeforeCreationID == a && copy.createdAt == now, "fresh home owns actual creation receipt")
        try check(SidebarHierarchy.children(in: location, state: p) == [.tab(c),.tab(home)], "saved home replaces exact original mixed parent slot")
        try check(p.splitLayouts[0].sidebarAnchorID == b && p.tabs[bi].url == pinned.tabs[bi].url, "existing ordinary parent anchors the new group")
        try check(propose(pinned, homes: [:]) == nil && propose(pinned, homes: [a:a]) == nil, "missing or colliding home refuses")
        let replaced = propose(pinned, target: .replace(0), homes: [:])!
        try check(replaced.selectedTabIDs == [b] && replaced.tabs.first { $0.id == a } == pinned.tabs[ai] && replaced.tabs.count == pinned.tabs.count && replaced.splitLayouts.isEmpty, "center replacement leaves saved item intact")
        var both = pinned; both.tabs[bi].kind = .pinned
        let bHome = UUID(), paired = propose(both, homes: [a:home,b:bHome])!
        try check(paired.tabs.count == both.tabs.count + 2 && paired.tabs.filter { [a,b].contains($0.id) }.allSatisfy { $0.kind == .today }, "both newly grouped saved items retain homes")
        try check(propose(both, homes: [a:home,b:home]) == nil, "two homes cannot share identity")
        var sourceGroup = original
        sourceGroup.selectedTabIDs = [b]
        var old = BrowserSplitLayout(spaceID: space, tabIDs: [a,c], orientation: .vertical, widthFactors: [0.3,0.7])
        old.customTitle = "Original"; old.customIcon = .emoji("🌙"); old.sidebarAnchorID = a
        sourceGroup.splitLayouts = [old]; sourceGroup.sidebarItemOrder[location.key] = [.tab(a)]
        let moved = propose(sourceGroup, source: a)!
        let kept = moved.splitLayouts.first { $0.id == old.id }!
        try check(kept.tabIDs == [home,c] && kept.sidebarAnchorID == home, "source container replaces exact saved child with home")
        try check(kept.widthFactors == old.widthFactors && kept.orientation == old.orientation && kept.customTitle == old.customTitle && kept.customIcon == old.customIcon, "source container metadata and sibling geometry preserved")
        try check(moved.splitLayouts.first { $0.id != old.id }?.tabIDs == [b,a], "original child enters destination without clone")
        try check(SidebarHierarchy.children(in: location, state: moved) == [.split(old.id)], "source group keeps exact parent slot")
        let layout = p.splitLayouts[0]
        try check(propose(p, source: b, target: .insert(0), layout: layout, homes: [:]) == nil,
                  "a member is not its own drop source; members reorder through pane Move")
        var invalid = pinned; invalid.tabs[bi].profileID = UUID()
        try check(propose(invalid) == nil, "cross-profile original refuses")
        invalid = pinned; invalid.tabs[ai].folderID = UUID()
        try check(propose(invalid) == nil, "missing saved parent refuses")
        invalid = pinned; invalid.tabs[bi].archivedAt = now
        try check(propose(invalid) == nil, "archived source refuses")
        try check(propose(pinned, target: .insert(5)) == nil, "stale index refuses")
        var favoriteTarget = original
        favoriteTarget.tabs[ai].kind = .favorite
        let tray = SidebarContainerLocation(spaceID: space, folderID: nil, section: .favorite, profileID: profile)
        favoriteTarget.sidebarItemOrder[tray.key] = [.tab(a)]
        let favoriteMoved = propose(favoriteTarget)!
        try check(favoriteMoved.tabs.first { $0.id == a }?.kind == .today
            && favoriteMoved.tabs.first { $0.id == home }?.kind == .favorite, "standalone Favorite retains original tray home and live Today owner")
        try check(SidebarHierarchy.children(in: tray, state: favoriteMoved) == [.tab(home)], "Favorite home keeps its exact Profile tray slot")
        var favoriteContainer = favoriteTarget
        favoriteContainer.tabs[favoriteContainer.tabs.firstIndex { $0.id == c }!].kind = .favorite
        let favoriteLayout = BrowserSplitLayout(spaceID: space, tabIDs: [a,c], orientation: .horizontal, widthFactors: [0.4,0.6])
        favoriteContainer.splitLayouts = [favoriteLayout]; favoriteContainer.selectedTabIDs = [a,c]
        let favoriteInserted = propose(favoriteContainer, layout: favoriteLayout, homes: [:])!
        try check(favoriteInserted.splitLayouts[0].id == favoriteLayout.id && favoriteInserted.selectedTabIDs == [a,b,c], "whole Favorite destination retains original group and ordered children")
        try check(favoriteInserted.tabs.count == favoriteContainer.tabs.count && favoriteInserted.tabs[bi].kind == .favorite, "whole Favorite destination admits original child without replacing existing homes")
        let favoriteReplacement = propose(favoriteContainer, target: .replace(0), layout: favoriteLayout, homes: [:])!
        try check(favoriteReplacement.selectedTabIDs == [b,c] && favoriteReplacement.tabs[ai] == favoriteContainer.tabs[ai], "Favorite replacement retains displaced original record")
        var maximum = favoriteContainer
        for _ in 0..<11 { var extra = favoriteTarget.tabs[ai]; extra.id = UUID(); maximum.tabs.append(extra) }
        try check(propose(maximum, target: .replace(0), layout: favoriteLayout, homes: [:]) == nil, "Favorite replacement cannot exceed genuine tray-root limit")
        var legacyTray = pinned
        for _ in 0..<13 { var extra = favoriteTarget.tabs[ai]; extra.id = UUID(); legacyTray.tabs.append(extra) }
        try check(propose(legacyTray) != nil, "unrelated legacy tray size cannot block ordinary original-tab movement")
        try check(store.dropTabIntoSplit(b, expectedSelection: [a], expectedLayout: nil,
            target: .insert(1), orientation: .horizontal, savedHomeIDs: [a:home]), "actual saved split transaction commits")
        let disk = try BrowserStore(directory: root)
        try check(disk.state.tabs.contains { $0.id == home } && disk.state.selectedTabIDs == [a,b], "home and group persisted together")
        let before = store.state, current = store.activeSplitLayout!
        let file = root.appendingPathComponent("session.json"), saved = try Data(contentsOf: file)
        try FileManager.default.removeItem(at: file); try FileManager.default.createDirectory(at: file, withIntermediateDirectories: false)
        try check(!store.dropTabIntoSplit(c, expectedSelection: [a,b], expectedLayout: current,
            target: .insert(2), orientation: .horizontal, savedHomeIDs: [c:bHome]), "real rename failure refuses commit")
        try check(store.state == before && store.persistenceError != nil, "failure retains original records and selection")
        try FileManager.default.removeItem(at: file); try saved.write(to: file)
        try check(store.dropTabIntoSplit(c, expectedSelection: [a,b], expectedLayout: current,
            target: .insert(2), orientation: .horizontal, savedHomeIDs: [c:bHome]), "same original receipt may retry after save failure")
        try check(store.state.tabs.filter { $0.id == bHome }.count == 1, "retry produces exactly one home")
        let notes = try NoteStore(directory: root.appendingPathComponent("notes"), diskSaveDelay: 0), note = try notes.create()
        let easels = try EaselStore(directory: root.appendingPathComponent("easels")), easel = try easels.create()
        let references = [SidebarDocumentReference(page: .note(note.document.id), profileID: profile) { try notes.validateReference(note.document.id) },
                          SidebarDocumentReference(page: .easel(easel.document.id), profileID: profile) { try easels.validateReference(easel.document.id) }]
        let addresses = ["parc://note/" + note.document.id.uuidString, "parc://easel/" + easel.document.id.uuidString]
        for index in references.indices {
            let directory = root.appendingPathComponent("alias-\(index)")
            var typed = pinned; typed.tabs[ai].url = addresses[index]; typed.tabs[ai].savedURL = addresses[index]
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(typed).write(to: directory.appendingPathComponent("session.json"))
            let model = try BrowserStore(directory: directory), initial = model.state
            try check(!model.dropTabIntoSplit(b, expectedSelection: [a], expectedLayout: nil,
                target: .insert(1), orientation: .horizontal, savedHomeIDs: [a:home]), "typed original requires original document validation")
            try check(model.state == initial, "missing document receipt publishes no alias")
            try check(model.dropTabIntoSplit(b, expectedSelection: [a], expectedLayout: nil,
                target: .insert(1), orientation: .horizontal, savedHomeIDs: [a:home], documents: [a:references[index]]), "actual typed original validates and commits")
            try check(model.state.tabs.first { $0.id == home }?.url == addresses[index] && model.state.tabs.first { $0.id == a }?.url == addresses[index], "original and home share exact authored document")
        }
        try check(try notes.load(note.document.id) === note && easels.load(easel.document.id) === easel, "original shared sessions never recreated")
        print("PASS: \(count) original split placement/store/alias assertions")
    }
}
