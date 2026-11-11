import Foundation

@main @MainActor struct SplitSeparationTests {
    static var count = 0
    static func check(_ value: @autoclosure () throws -> Bool, _ message: String) throws {
        count += 1
        if try !value() { throw NSError(domain: message, code: count) }
    }
    static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("parc-separation-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let now = Date(timeIntervalSince1970: 1_000_000)
        let store = try BrowserStore(directory: root, now: { now })
        let a = store.open("https://one.invalid", kind: .pinned)
        let b = store.open("https://two.invalid"), c = store.open("https://three.invalid")
        let folder = store.createFolder(name: "Original")
        store.moveTab(a, toSpace: store.activeSpaceID, folderID: folder)
        store.setSplit([a,b,c]); store.setSplitLayout(orientation: .vertical, widthFactors: [1,2,3])
        let space = store.activeSpaceID, profile = store.activeSpace.profileID
        let folderItems = SidebarHierarchy.children(in: .init(spaceID: space, folderID: folder, section: .pinned), state: store.state)
        try check(folderItems.count == 1 && folderItems != [.tab(a)] && store.state.tabs.first { $0.id == a }?.kind == .today,
                  "The pinned member joins the new Today split and leaves a fresh home in its folder")
        let edit = SidebarSplitTitleEdit.current(state: store.state, spaceID: space, profileID: profile, selectedTabIDs: [a,b,c])!
        try store.saveSidebarSplitTitle(edit, title: "Original group")
        let group = store.activeSplitLayout!, tabs = store.state.tabs, folders = store.state.folders
        let archive = store.state.recentlyClosedIDs, history = store.state.history
        try check(store.separateSplitPane(b), "Focused original separates through main command")
        try check(store.state.selectedTabIDs == [b] && store.state.selectionBySpace[space.uuidString] == [b], "Focused original remains sole current and remembered selection")
        let remaining = store.state.splitLayouts.first { $0.id == group.id }!
        try check(remaining.tabIDs == [a,c] && remaining.widthFactors == [0.25,0.75] && remaining.orientation == .vertical, "Original siblings retain order and normalized ratios")
        try check(remaining.customTitle == group.customTitle && remaining.sidebarAnchorID == a, "Surviving container keeps original name and anchor")
        try check(store.state.tabs == tabs && store.state.folders == folders, "No URL, page record, original placement or folder recreated")
        try check(store.state.recentlyClosedIDs == archive && store.state.history == history, "Separation is not close or navigation")
        try check(store.activeSplitLayout == nil, "Separated focused original is no longer a split")
        let loaded = try BrowserStore(directory: root, now: { now })
        try check(loaded.state.selectedTabIDs == [b] && loaded.state.splitLayouts.contains(remaining), "Selection and container persist together")
        let unchanged = store.state
        try check(!store.separateTabFromSplit(c, expected: group, focusedID: b) && store.state == unchanged, "Stale membership receipt refuses without mutation")
        try check(!store.separateTabFromSplit(c, expected: remaining, focusedID: UUID()) && store.state == unchanged, "Unselected focus cannot authorize retargeting")
        try check(store.separateTabFromSplit(c, expected: remaining, focusedID: b), "Background original group can separate")
        try check(store.state.selectedTabIDs == [b] && store.state.selectionBySpace[space.uuidString] == [b], "Background separation leaves actual selection unchanged")
        try check(!store.state.splitLayouts.contains { $0.id == remaining.id }, "Single-child container dissolves without deleting original")
        try check(store.state.tabs == tabs, "Background separation does not stamp or change other page state")
        store.setSplit([a,b,c]); let other = store.activeSplitLayout!
        try check(store.separateTabFromSplit(c, expected: other, focusedID: a), "Nonfocused displayed child separates")
        try check(store.state.selectedTabIDs == [a,b] && store.state.selectionBySpace[space.uuidString] == [a,b], "Current focus retains remaining displayed original group")
        store.setSplit([a,b,c]); let anchor = store.activeSplitLayout!
        try check(store.separateTabFromSplit(a, expected: anchor, focusedID: c), "Original anchor separates without closing")
        try check(store.state.selectedTabIDs == [b,c] && store.activeSplitLayout?.sidebarAnchorID == b, "Remaining ordered child becomes container anchor")
        try check(store.state.tabs.first { $0.id == a }?.folderID == nil && store.state.tabs.first { $0.id == a }?.kind == .today, "Separated original stays in its split's Today container")
        let todayOrder = SidebarHierarchy.children(in: .init(spaceID: space, folderID: nil, section: .today), state: store.state)
        try check(todayOrder.firstIndex(of: .split(anchor.id)).map { $0 + 1 } == todayOrder.firstIndex(of: .tab(a)),
                  "A separated child moves directly after its split")
        let pinnedIDs = [store.open("https://four.invalid"), store.open("https://five.invalid"), store.open("https://six.invalid")]
        store.selectTab(pinnedIDs[0]); store.selectTab(pinnedIDs[1], extendingSplit: true); store.selectTab(pinnedIDs[2], extendingSplit: true)
        let folderBox = SidebarContainerLocation(spaceID: space, folderID: folder, section: .pinned)
        try check(try store.moveSidebarItem(.split(store.activeSplitLayout!.id), to: folderBox, before: nil,
            expected: SidebarHierarchySnapshot(state: store.state, spaceID: space, profileID: profile)!), "A split moves whole into the folder")
        let folderSplit = store.activeSplitLayout!
        try check(store.separateTabFromSplit(pinnedIDs[1], expected: folderSplit, focusedID: pinnedIDs[0]), "Separate from the pinned folder split")
        let folderOrder = SidebarHierarchy.children(in: folderBox, state: store.state)
        try check(store.state.tabs.first { $0.id == pinnedIDs[1] }.map { $0.kind == .pinned && $0.folderID == folder } == true
                  && folderOrder.firstIndex(of: .split(folderSplit.id)).map { $0 + 1 } == folderOrder.firstIndex(of: .tab(pinnedIDs[1])),
                  "The separated child stays pinned in the folder right after its split")
        store.selectTab(b)
        let privateDirectory = root.appendingPathComponent("must-not-exist")
        let privateStore = BrowserStore(privateParentProfileID: profile, engineProfilePath: "/not-opened", directory: privateDirectory, settings: store.state.settings)
        let pa = privateStore.open("https://private-one.invalid"), pb = privateStore.open("https://private-two.invalid")
        privateStore.setSplit([pa,pb])
        try check(privateStore.separateSplitPane(pb) && privateStore.state.selectedTabIDs == [pb], "Private original split uses same focus contract")
        try check(!FileManager.default.fileExists(atPath: privateDirectory.path), "Private separation never persists")
        let notes = try NoteStore(directory: root.appendingPathComponent("notes"), diskSaveDelay: 0)
        let easels = try EaselStore(directory: root.appendingPathComponent("easels"))
        let note = try notes.create(), easel = try easels.create()
        let noteID = store.openNote(id: note.document.id, title: "Shared Note")!
        let easelID = store.openEasel(id: easel.document.id, title: "Shared Easel")!
        let originalNote = note.document, originalEasel = easel.document
        store.setSplit([a,noteID,easelID]); let localGroup = store.activeSplitLayout!
        var closeRequests = 0
        store.requestPageRetirement = { _, _, _ in closeRequests += 1 }
        try check(store.separateTabFromSplit(noteID, expected: localGroup, focusedID: noteID), "Original local Note separates through same transaction")
        try check(store.state.selectedTabIDs == [noteID] && closeRequests == 0, "Local separation never requests retirement or consent")
        try check(try notes.load(note.document.id) === note && easels.load(easel.document.id) === easel, "Original shared local sessions are not replaced")
        try check(note.document == originalNote && easel.document == originalEasel, "Shared document content and asset identity stay unchanged")
        try check(store.state.tabs.first { $0.id == easelID }?.url == InternalPage.easel(easel.document.id).urlString, "Surviving embedded-page owner retains original Easel reference")
        store.requestPageRetirement = nil
        store.setSplit([a,b,c]); let failing = store.activeSplitLayout!, failureState = store.state
        try store.save()
        try FileManager.default.removeItem(at: root); try Data().write(to: root)
        try check(!store.separateTabFromSplit(b, expected: failing, focusedID: b), "Actual failed durable commit refuses separation")
        try check(store.state == failureState && store.persistenceError != nil, "Failed save retains original selection, group and all records")
        try FileManager.default.removeItem(at: root); try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try check(store.separateTabFromSplit(b, expected: failing, focusedID: b), "Same original receipt retries after storage recovery")
        try check(store.state.selectedTabIDs == [b] && store.persistenceError == nil, "Successful retry publishes original focus once")
        print("PASS: \(count) actual Split separation persistence/ownership checks (no browser)")
    }
}
