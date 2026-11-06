import Foundation

/// Genuine durable store and original Note/Easel sessions; every file is temporary.
@main @MainActor
struct SidebarPluralDuplicateTests {
    static var count = 0
    static func check(_ value: @autoclosure () throws -> Bool, _ message: String) throws {
        count += 1; if try !value() { throw NSError(domain: message, code: 1) }
    }
    static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("parc-plural-copy-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let profile = BrowserProfile(id: UUID(), name: "Original")
        let space = BrowserSpace(id: UUID(), name: "Here", symbol: "circle", color: "ABCDEF", profileID: profile.id)
        let first = BrowserFolder(id: UUID(), spaceID: space.id, name: "First", isExpanded: false)
        let nested = BrowserFolder(id: UUID(), spaceID: space.id, name: "Nested", parentID: first.id, isExpanded: false)
        let second = BrowserFolder(id: UUID(), spaceID: space.id, name: "Second")
        let empty = BrowserFolder(id: UUID(), spaceID: space.id, name: "Empty")
        let notes = try NoteStore.sharedStore(directory: root.appendingPathComponent("Notes"), diskSaveDelay: 0)
        let easels = try EaselStore(directory: root.appendingPathComponent("Easels"))
        let note = try notes.create(), easel = try easels.create(title: "Shared Easel")
        try note.updateTitle("Original Note", replacing: note.document.title)
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a3uoAAAAASUVORK5CYII=")!
        let asset = try easel.importPNG(png)
        try easel.perform("Image") { $0.items = [EaselItem(kind: .image, frame: .init(x: 0, y: 0, width: 100, height: 80), assetID: asset)] }
        let noteFile = notes.directory.appendingPathComponent(note.document.id.uuidString.lowercased() + ".json")
        let noteBytes = try Data(contentsOf: noteFile), assetBytes = try Data(contentsOf: easel.assetURL(asset))
        func tab(_ title: String, parent: UUID? = nil, kind: TabKind = .pinned, url: String? = nil) -> BrowserTab {
            let url = url ?? "https://saved.invalid/" + title
            return .init(id: UUID(), spaceID: space.id, profileID: profile.id, url: url, title: title,
                         kind: kind, folderID: parent, createdAt: Date(timeIntervalSince1970: 10),
                         lastAccessed: Date(timeIntervalSince1970: 10), savedURL: url, savedTitle: title)
        }
        let n = tab("Note", parent: nested.id, url: InternalPage.note(note.document.id).urlString)
        let w = tab("Web", parent: nested.id)
        let e = tab("Easel", parent: second.id, url: InternalPage.easel(easel.document.id).urlString)
        let loose = tab("Loose", parent: second.id), today = tab("Today", kind: .today), keep = tab("Keep")
        let split = BrowserSplitLayout(sidebarAnchorID: n.id, customTitle: "Mixed", spaceID: space.id,
            tabIDs: [n.id,w.id], orientation: .vertical, widthFactors: [0.3,0.7])
        var state = BrowserState(profiles: [profile], spaces: [space], activeSpaceID: space.id)
        state.folders = [first,nested,second,empty]; state.tabs = [n,w,e,loose,today,keep]; state.splitLayouts = [split]
        let pinned = SidebarContainerLocation(spaceID: space.id, folderID: nil, section: .pinned)
        let secondLocation = SidebarContainerLocation(spaceID: space.id, folderID: second.id, section: .pinned)
        state.sidebarItemOrder[pinned.key] = [.tab(keep.id),.folder(first.id),.folder(second.id),.folder(empty.id)]
        state.sidebarItemOrder[secondLocation.key] = [.tab(loose.id),.tab(e.id)]
        state.selectedTabIDs = split.tabIDs; state.selectionBySpace[space.id.uuidString] = split.tabIDs
        let sessionURL = root.appendingPathComponent("session.json")
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(state).write(to: sessionURL)
        let store = try BrowserStore(directory: root, now: { Date(timeIntervalSince1970: 1000) })
        let initial = store.state
        let proposed: [SidebarItemReference] = [.folder(first.id),.folder(nested.id),.split(split.id),.folder(empty.id),.tab(loose.id),.tab(e.id),.tab(today.id)]
        let target = SidebarDuplicateTarget(items: proposed, spaceID: space.id, profileID: profile.id, state: initial)!
        try check(target.roots == [.folder(first.id),.folder(empty.id),.tab(loose.id),.tab(e.id),.tab(today.id)], "Ancestor owns nested selected folder/split once in original input order")
        try check(target.tabs.map(\.id) == [n.id,w.id,loose.id,e.id,today.id], "Original descendant and root order captured")
        try check(target.folderIDs == [first.id,nested.id,empty.id] && target.groups == [split], "Empty folders and complete split retained")
        try check(SidebarDuplicateTarget(items: [.tab(n.id)], spaceID: space.id, profileID: profile.id, state: initial) == nil, "No partial split pane")
        try check(SidebarDuplicateTarget(items: [.folder(first.id),.folder(first.id)], spaceID: space.id, profileID: profile.id, state: initial) == nil, "Duplicate explicit roots refused")
        try check(SidebarDuplicateTarget(items: proposed, spaceID: space.id, profileID: UUID(), state: initial) == nil, "Foreign Profile refused")
        var malformed = initial; malformed.tabs[0].profileID = UUID()
        try check(SidebarDuplicateTarget(items: proposed, spaceID: space.id, profileID: profile.id, state: malformed) == nil, "Foreign nested child cannot partially copy")
        malformed = initial; malformed.tabs[0].kind = .today
        try check(SidebarDuplicateTarget(items: proposed, spaceID: space.id, profileID: profile.id, state: malformed) == nil, "Folder descendants must remain saved")
        malformed = initial; malformed.splitLayouts[0].tabIDs = [n.id,n.id]
        try check(SidebarDuplicateTarget(items: proposed, spaceID: space.id, profileID: profile.id, state: malformed) == nil, "Malformed split refused")
        malformed = initial; malformed.tabs[5].kind = .favorite
        try check(SidebarDuplicateTarget(items: [.tab(keep.id)], spaceID: space.id, profileID: profile.id, state: malformed) == nil, "Favorite context is outside this owner")
        let references = [n.id: SidebarDocumentReference(page: .note(note.document.id), profileID: profile.id) { try notes.validateReference(note.document.id) },
                          e.id: SidebarDocumentReference(page: .easel(easel.document.id), profileID: profile.id) { try easels.validateReference(easel.document.id) }]
        let urls = Dictionary(uniqueKeysWithValues: target.tabs.map { ($0.id, InternalPage(urlString: $0.savedURL) == nil ? "https://live.invalid/" + $0.id.uuidString : $0.savedURL) })
        try check(try store.duplicateSidebarItems(target, destinations: urls) == nil && store.state == initial, "Missing typed capability refuses entire mixed collection")
        var badURLs = urls; badURLs[w.id] = n.savedURL
        try check(try store.duplicateSidebarItems(target, destinations: badURLs, documents: references) == nil && store.state == initial, "No fake web-to-document URL copy")
        var badDocs = references; badDocs[n.id] = SidebarDocumentReference(page: .note(note.document.id), profileID: UUID()) {}
        try check(try store.duplicateSidebarItems(target, destinations: urls, documents: badDocs) == nil && store.state == initial, "Wrong original document Profile refuses all roots")
        var nativeCompletion: ((Bool) -> Void)?
        store.requestPageRetirement = { _,_,done in nativeCompletion = done }
        store.closeTabs([w.id]) { _ in }
        try check(try store.duplicateSidebarItems(target, destinations: urls, documents: references) == nil, "One retiring original blocks complete copy")
        nativeCompletion?(false); store.requestPageRetirement = nil
        let sessionBefore = try Data(contentsOf: sessionURL)
        try FileManager.default.removeItem(at: sessionURL)
        try FileManager.default.createDirectory(at: sessionURL, withIntermediateDirectories: false)
        do { _ = try store.duplicateSidebarItems(target, destinations: urls, documents: references); preconditionFailure("Expected actual save error") } catch {}
        try check(store.state == initial && FileManager.default.fileExists(atPath: sessionURL.path), "Real persistence failure publishes no partial roots")
        try check(try Data(contentsOf: noteFile) == noteBytes && Data(contentsOf: easel.assetURL(asset)) == assetBytes, "Failed sidebar save never writes original document data")
        try FileManager.default.removeItem(at: sessionURL); try sessionBefore.write(to: sessionURL)
        let copy = try store.duplicateSidebarItems(target, destinations: urls, documents: references)!
        let after = store.state
        try check(copy.roots.count == 5 && copy.tabIDs.count == 5, "All normalized roots commit together")
        try check(Set(copy.tabIDs).isDisjoint(with: initial.tabs.map(\.id)), "Fresh tab aliases")
        try check(after.tabs.prefix(initial.tabs.count).elementsEqual(initial.tabs) && after.folders.prefix(initial.folders.count).elementsEqual(initial.folders), "All original records unchanged")
        try check(after.splitLayouts.first == split && after.splitLayouts.count == 2, "Original split retained and copied once")
        try check(after.selectedTabIDs == initial.selectedTabIDs && after.selectionBySpace == initial.selectionBySpace && after.activeSpaceID == initial.activeSpaceID, "No selected page or Space changes")
        try check(SidebarHierarchy.children(in: pinned, state: after) == [.tab(keep.id),.folder(first.id),copy.roots[0],.folder(second.id),.folder(empty.id),copy.roots[1]], "Each root copy is adjacent in original mixed root order")
        try check(SidebarHierarchy.children(in: secondLocation, state: after) == [.tab(loose.id),copy.roots[2],.tab(e.id),copy.roots[3]], "Multiple roots sharing a parent accumulate in one order proposal")
        let copiedTabs = copy.tabIDs.map { id in after.tabs.first { $0.id == id }! }
        try check(copiedTabs.map(\.savedURL) == target.tabs.map { urls[$0.id]! }, "Exact resolved live URL or typed identity preserved")
        try check(copiedTabs.map(\.kind) == target.tabs.map(\.kind), "Today and saved kinds remain original")
        try check(copiedTabs.allSatisfy { $0.isUnread && $0.createdAt == Date(timeIntervalSince1970: 1000) }, "New copied record metadata")
        try check(copy.openTabIDs == [copy.tabIDs[1],copy.tabIDs[2],copy.tabIDs[4]], "Original recursive effect order: split child precedes later first-five roots; typed children never create pages")
        let copiedGroup = after.splitLayouts[1]
        try check(copiedGroup.id != split.id && copiedGroup.tabIDs == Array(copy.tabIDs.prefix(2)), "Whole split receives fresh mapped IDs")
        try check(copiedGroup.sidebarAnchorID == copy.tabIDs[0] && copiedGroup.widthFactors == split.widthFactors && copiedGroup.orientation == split.orientation && copiedGroup.customTitle == split.customTitle, "Original split anchor and rendered layout preserved")
        try check(try Data(contentsOf: noteFile) == noteBytes && Data(contentsOf: easel.assetURL(asset)) == png, "Original files remain identical after committed copy")
        try check(try notes.load(note.document.id) === note && easels.load(easel.document.id) === easel, "Copied aliases retain same real shared sessions")
        try note.updateTitle("Shared later edit", replacing: note.document.title)
        try check(try notes.load(InternalPage(urlString: copiedTabs[0].savedURL)!.noteID!).document.title == "Shared later edit", "Alias observes original shared draft owner")
        try check(try store.duplicateSidebarItems(target, destinations: urls, documents: references) == nil, "Original menu snapshot cannot execute again after hierarchy changed")
        let reload = try BrowserStore(directory: root)
        try check(copy.tabIDs.allSatisfy { id in reload.state.tabs.contains { $0.id == id } } && reload.state.splitLayouts.contains(copiedGroup), "All committed identities durably reload")
        // Root indexes, not descendant counts, govern the recovered first-five rule.
        var many = state; many.folders = []; many.splitLayouts = []; many.tabs = (0..<7).map { tab("root\($0)", kind: .today) }
        many.sidebarItemOrder = [:]; many.selectedTabIDs = [many.tabs[0].id]; many.selectionBySpace = [:]
        let other = root.appendingPathComponent("Many"); try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        try encoder.encode(many).write(to: other.appendingPathComponent("session.json"))
        let manyStore = try BrowserStore(directory: other)
        let manyTarget = SidebarDuplicateTarget(items: many.tabs.map { .tab($0.id) }, spaceID: space.id, profileID: profile.id, state: manyStore.state)!
        let manyCopy = try manyStore.duplicateSidebarItems(manyTarget, destinations: Dictionary(uniqueKeysWithValues: many.tabs.map { ($0.id,$0.savedURL) }))!
        try check(manyCopy.tabIDs.count == 7 && manyCopy.openTabIDs == Array(manyCopy.tabIDs.prefix(5)), "Seven roots saved, exactly first five ordinary roots request opening")
        print("\(count) plural context duplicate assertions passed")
    }
}
