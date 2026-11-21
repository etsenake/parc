import Foundation
import Testing
@testable import ParcCore

@MainActor struct SplitSeparationTests {
    @Test static func scenario() throws {
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
        #expect(folderItems.count == 1 && folderItems != [.tab(a)] && store.state.tabs.first { $0.id == a }?.kind == .today,
                  "The pinned member joins the new Today split and leaves a fresh home in its folder")
        let edit = SidebarSplitTitleEdit.current(state: store.state, spaceID: space, profileID: profile, selectedTabIDs: [a,b,c])!
        try store.saveSidebarSplitTitle(edit, title: "Original group")
        let group = store.activeSplitLayout!, tabs = store.state.tabs, folders = store.state.folders
        let archive = store.state.recentlyClosedIDs, history = store.state.history
        #expect(store.separateSplitPane(b), "Focused original separates through main command")
        #expect(store.state.selectedTabIDs == [b] && store.state.selectionBySpace[space.uuidString] == [b], "Focused original remains sole current and remembered selection")
        let remaining = store.state.splitLayouts.first { $0.id == group.id }!
        #expect(remaining.tabIDs == [a,c] && remaining.widthFactors == [0.25,0.75] && remaining.orientation == .vertical, "Original siblings retain order and normalized ratios")
        #expect(remaining.customTitle == group.customTitle && remaining.sidebarAnchorID == a, "Surviving container keeps original name and anchor")
        #expect(store.state.tabs == tabs && store.state.folders == folders, "No URL, page record, original placement or folder recreated")
        #expect(store.state.recentlyClosedIDs == archive && store.state.history == history, "Separation is not close or navigation")
        #expect(store.activeSplitLayout == nil, "Separated focused original is no longer a split")
        let loaded = try BrowserStore(directory: root, now: { now })
        #expect(loaded.state.selectedTabIDs == [b] && loaded.state.splitLayouts.contains(remaining), "Selection and container persist together")
        let unchanged = store.state
        #expect(!store.separateTabFromSplit(c, expected: group, focusedID: b) && store.state == unchanged, "Stale membership receipt refuses without mutation")
        #expect(!store.separateTabFromSplit(c, expected: remaining, focusedID: UUID()) && store.state == unchanged, "Unselected focus cannot authorize retargeting")
        #expect(store.separateTabFromSplit(c, expected: remaining, focusedID: b), "Background original group can separate")
        #expect(store.state.selectedTabIDs == [b] && store.state.selectionBySpace[space.uuidString] == [b], "Background separation leaves actual selection unchanged")
        #expect(!store.state.splitLayouts.contains { $0.id == remaining.id }, "Single-child container dissolves without deleting original")
        #expect(store.state.tabs == tabs, "Background separation does not stamp or change other page state")
        store.setSplit([a,b,c]); let other = store.activeSplitLayout!
        #expect(store.separateTabFromSplit(c, expected: other, focusedID: a), "Nonfocused displayed child separates")
        #expect(store.state.selectedTabIDs == [a,b] && store.state.selectionBySpace[space.uuidString] == [a,b], "Current focus retains remaining displayed original group")
        store.setSplit([a,b,c]); let anchor = store.activeSplitLayout!
        #expect(store.separateTabFromSplit(a, expected: anchor, focusedID: c), "Original anchor separates without closing")
        #expect(store.state.selectedTabIDs == [b,c] && store.activeSplitLayout?.sidebarAnchorID == b, "Remaining ordered child becomes container anchor")
        #expect(store.state.tabs.first { $0.id == a }?.folderID == nil && store.state.tabs.first { $0.id == a }?.kind == .today, "Separated original stays in its split's Today container")
        let todayOrder = SidebarHierarchy.children(in: .init(spaceID: space, folderID: nil, section: .today), state: store.state)
        #expect(todayOrder.firstIndex(of: .split(anchor.id)).map { $0 + 1 } == todayOrder.firstIndex(of: .tab(a)),
                  "A separated child moves directly after its split")
        let pinnedIDs = [store.open("https://four.invalid"), store.open("https://five.invalid"), store.open("https://six.invalid")]
        store.selectTab(pinnedIDs[0]); store.selectTab(pinnedIDs[1], extendingSplit: true); store.selectTab(pinnedIDs[2], extendingSplit: true)
        let folderBox = SidebarContainerLocation(spaceID: space, folderID: folder, section: .pinned)
        #expect(try store.moveSidebarItem(.split(store.activeSplitLayout!.id), to: folderBox, before: nil,
            expected: SidebarHierarchySnapshot(state: store.state, spaceID: space, profileID: profile)!), "A split moves whole into the folder")
        let folderSplit = store.activeSplitLayout!
        #expect(store.separateTabFromSplit(pinnedIDs[1], expected: folderSplit, focusedID: pinnedIDs[0]), "Separate from the pinned folder split")
        let folderOrder = SidebarHierarchy.children(in: folderBox, state: store.state)
        #expect(store.state.tabs.first { $0.id == pinnedIDs[1] }.map { $0.kind == .pinned && $0.folderID == folder } == true
                  && folderOrder.firstIndex(of: .split(folderSplit.id)).map { $0 + 1 } == folderOrder.firstIndex(of: .tab(pinnedIDs[1])),
                  "The separated child stays pinned in the folder right after its split")
        store.selectTab(b)
        let privateDirectory = root.appendingPathComponent("must-not-exist")
        let privateStore = BrowserStore(privateParentProfileID: profile, engineProfilePath: "/not-opened", directory: privateDirectory, settings: store.state.settings)
        let pa = privateStore.open("https://private-one.invalid"), pb = privateStore.open("https://private-two.invalid")
        privateStore.setSplit([pa,pb])
        #expect(privateStore.separateSplitPane(pb) && privateStore.state.selectedTabIDs == [pb], "Private original split uses same focus contract")
        #expect(!FileManager.default.fileExists(atPath: privateDirectory.path), "Private separation never persists")
        let noteFile = root.appendingPathComponent("Shared Note.md"), originalNote = Data("Shared\n".utf8)
        try originalNote.write(to: noteFile)
        let easels = try EaselStore(directory: root.appendingPathComponent("easels"))
        let easel = try easels.create()
        let noteID = store.openNote(url: noteFile, title: "Shared Note")!
        let easelID = store.openEasel(id: easel.document.id, title: "Shared Easel")!
        let originalEasel = easel.document
        store.setSplit([a,noteID,easelID]); let localGroup = store.activeSplitLayout!
        var closeRequests = 0
        store.requestPageRetirement = { _, _, _ in closeRequests += 1 }
        #expect(store.separateTabFromSplit(noteID, expected: localGroup, focusedID: noteID), "Original local Note separates through same transaction")
        #expect(store.state.selectedTabIDs == [noteID] && closeRequests == 0, "Local separation never requests retirement or consent")
        #expect(try easels.load(easel.document.id) === easel, "Original shared local sessions are not replaced")
        #expect(try Data(contentsOf: noteFile) == originalNote && easel.document == originalEasel, "Shared document content and asset identity stay unchanged")
        #expect(store.state.tabs.first { $0.id == easelID }?.url == InternalPage.easel(easel.document.id).urlString, "Surviving embedded-page owner retains original Easel reference")
        store.requestPageRetirement = nil
        store.setSplit([a,b,c]); let failing = store.activeSplitLayout!, failureState = store.state
        try store.save()
        try FileManager.default.removeItem(at: root); try Data().write(to: root)
        #expect(!store.separateTabFromSplit(b, expected: failing, focusedID: b), "Actual failed durable commit refuses separation")
        #expect(store.state == failureState && store.persistenceError != nil, "Failed save retains original selection, group and all records")
        try FileManager.default.removeItem(at: root); try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        #expect(store.separateTabFromSplit(b, expected: failing, focusedID: b), "Same original receipt retries after storage recovery")
        #expect(store.state.selectedTabIDs == [b] && store.persistenceError == nil, "Successful retry publishes original focus once")
    }
}
