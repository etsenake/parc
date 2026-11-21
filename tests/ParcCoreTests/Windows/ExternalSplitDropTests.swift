import Foundation
import Testing
@testable import ParcCore

@MainActor struct ExternalSplitDropTests {
    @Test static func scenario() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("parc-external-split-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try BrowserStore(directory: root)
        let a = store.openResolvedURL(URL(string: "https://one.invalid")!), b = store.openResolvedURL(URL(string: "https://two.invalid")!)
        store.setSplit([a,b]); let p = store.activeSpace.profileID, space = store.activeSpaceID
        let original = store.state, group = store.activeSplitLayout!
        let destination = URL(string: "https://external.invalid/path?original=a+b#section")!
        let id = UUID(), receipt = TabCreationProvenance(referrerID: nil, activeTabID: a, profileID: p, state: original)
        #expect(try store.dropExternalURLIntoSplit(destination, tabID: id, spaceID: space, profileID: p,
            expectedSelection: [a,b], expectedLayout: group, target: .replace(1), orientation: .horizontal, creation: receipt), "actual replacement commit")
        #expect(store.state.selectedTabIDs == [a,id], "new original ID occupies requested pane")
        #expect(store.state.tabs.first { $0.id == b } == original.tabs.first { $0.id == b }, "displaced page metadata retained without archive or URL mutation")
        let new = store.state.tabs.first { $0.id == id }!
        #expect(new.url == destination.absoluteString && new.savedURL == new.url && new.kind == .today, "literal external URL becomes new Today request")
        #expect(new.referrerID == nil && new.activeTabBeforeCreationID == a && new.profileID == p, "captured creation owner")
        #expect(store.activeSplitLayout?.id == group.id && store.activeSplitLayout?.widthFactors == group.widthFactors, "original group identity and replacement geometry")
        let reopened = try BrowserStore(directory: root)
        #expect(reopened.state.tabs.contains { $0.id == id } && reopened.activeSplitLayout?.tabIDs == [a,id], "creation and arrangement durable together")
        let beforeRefusal = store.state
        #expect(try !store.dropExternalURLIntoSplit(destination, tabID: UUID(), spaceID: space, profileID: p,
            expectedSelection: [a,b], expectedLayout: group, target: .insert(1), orientation: .horizontal, creation: receipt), "stale original selection refused")
        #expect(store.state == beforeRefusal, "refusal publishes nothing")
        for invalid in ["javascript:alert(1)", "parc://note/one", "file:///tmp/example", "data:text/plain,hello", "relative", "https://user:secret@example.invalid", " https://example.invalid", "https://example.invalid\n"] {
            #expect(ExternalSplitDrop.url(invalid) == nil, "unowned scheme/credential/relative payload refused")
        }
        #expect(ExternalSplitDrop.url(destination.absoluteString) == destination, "literal URL accepted")
        func proposal(_ state: BrowserState, _ target: SplitDropTarget, _ selection: [UUID], _ layout: BrowserSplitLayout?,
                      _ orientation: SplitOrientation = .vertical) -> BrowserState? {
            ExternalSplitDrop.proposal(url: destination, tabID: UUID(), state: state, spaceID: space, profileID: p,
                selection: selection, layout: layout, target: target, orientation: orientation, creation: receipt, now: Date())
        }
        let inserted = proposal(original, .insert(1), [a,b], group)!
        #expect(inserted.selectedTabIDs.count == 3 && inserted.selectedTabIDs.first == a && inserted.selectedTabIDs.last == b, "insertion order preserves original pair")
        #expect(inserted.splitLayouts.first?.orientation == .vertical, "actual requested orientation")
        let stacked = proposal(original, .stack(0, after: true), [a,b], group, .horizontal)
        #expect(stacked?.selectedTabIDs.count == 3 && stacked?.selectedTabIDs.first == a && stacked?.selectedTabIDs.last == b
            && stacked?.splitLayouts.first?.id == group.id && stacked?.splitLayouts.first?.orientation == .horizontal
            && stacked?.splitLayouts.first?.stacks?.slotSizes == [2, 1], "a link on a side-by-side pane's bottom band stacks below it")
        var four = original
        let c = UUID(), d = UUID(); for extra in [c,d] { var t = original.tabs[0]; t.id = extra; four.tabs.append(t) }
        four.selectedTabIDs = [a,b,c,d]; var fourGroup = group; fourGroup.tabIDs = four.selectedTabIDs; fourGroup.widthFactors = [0.25,0.25,0.25,0.25]; four.splitLayouts = [fourGroup]
        #expect(proposal(four, .insert(1), four.selectedTabIDs, fourGroup) == nil, "capacity refusal is atomic")
        #expect(proposal(four, .replace(2), four.selectedTabIDs, fourGroup)?.selectedTabIDs.count == 4, "replacement at capacity remains available")
        #expect(proposal(four, .stack(2, after: true), four.selectedTabIDs, fourGroup, .horizontal) == nil, "a stack drop refuses at four panes")
        var favorite = original
        let homeSpace = UUID(), homeID = UUID(), urlID = UUID(), now = Date(timeIntervalSince1970: 123456)
        favorite.spaces.append(BrowserSpace(id: homeSpace, name: "Home", symbol: "star", color: "123456", profileID: p))
        favorite.splitLayouts = []; favorite.selectedTabIDs = [a]
        let ai = favorite.tabs.firstIndex { $0.id == a }!, bi = favorite.tabs.firstIndex { $0.id == b }!
        favorite.tabs[ai].kind = .favorite; favorite.tabs[ai].spaceID = homeSpace
        favorite.tabs[ai].savedURL = "https://home.invalid/saved"
        favorite.tabs[ai].savedTitle = "Saved home"; favorite.tabs[ai].customTitle = "My Favorite"
        favorite.tabs[ai].url = "https://away.invalid/live"; favorite.tabs[ai].title = "Live page"
        favorite.tabs[ai].referrerID = b
        favorite.tabs[bi].kind = .favorite
        let tray = SidebarContainerLocation(spaceID: space, folderID: nil, section: .favorite, profileID: p)
        favorite.sidebarItemOrder[tray.key] = [.tab(b), .tab(a)]
        favorite.selectionBySpace[homeSpace.uuidString] = [a]
        func favoriteProposal(_ state: BrowserState, _ target: SplitDropTarget, _ layout: BrowserSplitLayout? = nil,
                              home: UUID? = homeID) -> BrowserState? {
            ExternalSplitDrop.proposal(url: destination, tabID: urlID, state: state, spaceID: space, profileID: p,
                selection: state.selectedTabIDs, layout: layout, target: target, orientation: .vertical,
                creation: receipt, now: now, savedHomeID: home)
        }
        let favoriteOriginal = favorite.tabs[ai]
        let splitFavorite = favoriteProposal(favorite, .insert(1))!
        let live = splitFavorite.tabs.first { $0.id == a }!, savedHome = splitFavorite.tabs.first { $0.id == homeID }!
        #expect(splitFavorite.selectedTabIDs == [a,urlID] && splitFavorite.splitLayouts.first?.spaceID == space, "standalone Favorite forms current-Space split with original ID")
        #expect(live.kind == .today && live.spaceID == space && live.url == favoriteOriginal.url && live.title == favoriteOriginal.title && live.referrerID == b, "live page identity URL title and provenance retained")
        #expect(savedHome.kind == .favorite && savedHome.spaceID == homeSpace && savedHome.profileID == p && savedHome.url == favoriteOriginal.savedURL && savedHome.title == favoriteOriginal.savedTitle, "fresh home reference retains original Profile and home Space")
        #expect(savedHome.customTitle == favoriteOriginal.customTitle && savedHome.savedURL == favoriteOriginal.savedURL && savedHome.referrerID == nil && savedHome.activeTabBeforeCreationID == a, "saved title override and fresh creation receipt")
        #expect(SidebarHierarchy.children(in: tray, state: splitFavorite) == [.tab(b),.tab(homeID)], "exact Profile-wide tray position")
        #expect(splitFavorite.selectionBySpace[homeSpace.uuidString] == [homeID], "other Space return follows saved-home alias")
        #expect(favoriteProposal(favorite, .insert(1))?.tabs == splitFavorite.tabs, "retry keeps fixed original and new identities")
        #expect(favoriteProposal(favorite, .insert(1), home: nil) == nil && favoriteProposal(favorite, .insert(1), home: a) == nil && favoriteProposal(favorite, .insert(1), home: urlID) == nil, "missing/colliding home identity refused")
        let center = favoriteProposal(favorite, .replace(0), home: nil)!
        #expect(center.tabs.first { $0.id == a } == favoriteOriginal && !center.tabs.contains { $0.id == homeID }, "single-pane replacement preserves original Favorite without copy")
        #expect(center.selectedTabIDs == [urlID] && center.splitLayouts.isEmpty, "center chooses only new ordinary page")
        var favoriteGroup = favorite
        favoriteGroup.tabs[bi].spaceID = homeSpace; favoriteGroup.selectedTabIDs = [a,b]
        var trayGroup = group; trayGroup.spaceID = homeSpace; trayGroup.customTitle = "Saved group"; trayGroup.customIcon = .emoji("🌙")
        favoriteGroup.splitLayouts = [trayGroup]; favoriteGroup.sidebarItemOrder[tray.key] = [.tab(a)]
        let added = favoriteProposal(favoriteGroup, .insert(1), trayGroup)!
        #expect(added.tabs.first { $0.id == urlID }?.kind == .favorite && added.tabs.first { $0.id == urlID }?.spaceID == homeSpace, "existing Favorite group admits a Favorite child in actual home Space")
        #expect(added.splitLayouts[0].id == trayGroup.id && added.splitLayouts[0].customTitle == trayGroup.customTitle && added.splitLayouts[0].customIcon == trayGroup.customIcon && added.splitLayouts[0].tabIDs == [a,urlID,b], "whole-group identity appearance and requested child order retained")
        #expect(!added.tabs.contains { $0.id == homeID } && SidebarHierarchy.children(in: tray, state: added) == [.split(trayGroup.id)], "existing Favorite group never duplicates original children")
        let replaced = favoriteProposal(favoriteGroup, .replace(0), trayGroup)!
        #expect(replaced.tabs.first { $0.id == a } == favoriteOriginal && replaced.splitLayouts[0].widthFactors == trayGroup.widthFactors, "Favorite replacement leaves displaced original and geometry intact")
        #expect(SidebarHierarchy.children(in: tray, state: replaced) == [.split(trayGroup.id),.tab(a)], "replaced anchor preserves group tray slot before displaced root")
        var capped = favoriteGroup
        for i in 0..<11 { var tab = favoriteOriginal; tab.id = UUID(); tab.title = "Favorite \(i)"; capped.tabs.append(tab) }
        #expect(SidebarHierarchy.children(in: tray, state: capped).count == 12, "twelve actual Favorite roots")
        #expect(favoriteProposal(capped, .replace(0), trayGroup) == nil, "thirteenth displaced root refused atomically")
        #expect(favoriteProposal(capped, .insert(1), trayGroup) != nil, "existing Favorite group insertion does not consume a tray root")
        var mixed = favoriteGroup; mixed.tabs[bi].kind = .today; mixed.tabs[bi].spaceID = space
        #expect(favoriteProposal(mixed, .insert(1), trayGroup) == nil, "unrecovered mixed Favorite/Today group refuses without conversion")
        var pinned = favorite
        let pinnedFolder = BrowserFolder(id: UUID(), spaceID: space, name: "Original folder")
        let siblingFolder = BrowserFolder(id: UUID(), spaceID: space, name: "Sibling", parentID: pinnedFolder.id)
        pinned.folders += [pinnedFolder, siblingFolder]
        pinned.tabs[ai].kind = .pinned; pinned.tabs[ai].spaceID = space; pinned.tabs[ai].folderID = pinnedFolder.id
        pinned.tabs[bi].kind = .pinned; pinned.tabs[bi].spaceID = space; pinned.tabs[bi].folderID = pinnedFolder.id
        let pinnedContainer = SidebarContainerLocation(spaceID: space, folderID: pinnedFolder.id, section: .pinned)
        pinned.sidebarItemOrder[pinnedContainer.key] = [.tab(b), .tab(a), .folder(siblingFolder.id)]
        let pinnedOriginal = pinned.tabs[ai]
        let pinnedSplit = favoriteProposal(pinned, .insert(0))!
        let pinnedHome = pinnedSplit.tabs.first { $0.id == homeID }!, pinnedLive = pinnedSplit.tabs.first { $0.id == a }!
        #expect(pinnedSplit.selectedTabIDs == [urlID,a] && pinnedSplit.splitLayouts[0].tabIDs == [urlID,a], "pinned edge drop keeps requested pane order with original live ID")
        #expect(pinnedLive.kind == .today && pinnedLive.folderID == nil && pinnedLive.url == pinnedOriginal.url && pinnedLive.referrerID == pinnedOriginal.referrerID, "pinned live page moves to Today without URL or provenance reconstruction")
        #expect(pinnedHome.kind == .pinned && pinnedHome.folderID == pinnedFolder.id && pinnedHome.spaceID == space && pinnedHome.url == pinnedOriginal.savedURL && pinnedHome.customTitle == pinnedOriginal.customTitle, "pinned saved home preserves original folder and saved metadata")
        #expect(SidebarHierarchy.children(in: pinnedContainer, state: pinnedSplit) == [.tab(b), .tab(homeID), .folder(siblingFolder.id)], "pinned saved home replaces the exact mixed sibling slot")
        #expect(pinnedSplit.tabs.first { $0.id == b } == pinned.tabs[bi] && pinnedSplit.folders == pinned.folders, "unrelated sibling and folder records remain intact")
        #expect(favoriteProposal(pinned, .replace(0), home: nil)?.tabs.first { $0.id == a } == pinnedOriginal, "pinned center replacement leaves original saved item intact")
        #expect(favoriteProposal(pinned, .insert(0), home: nil) == nil, "pinned edge drop requires its fixed saved-home identity")
        var pinnedGroup = pinned; pinnedGroup.selectedTabIDs = [a,b]; pinnedGroup.splitLayouts = [group]
        let withinPinnedGroup = favoriteProposal(pinnedGroup, .insert(1), group)!
        #expect(!withinPinnedGroup.tabs.contains { $0.id == homeID } && withinPinnedGroup.splitLayouts[0].id == group.id, "existing pinned container retains its children without creating saved-home copies")
        var absentPinnedFolder = pinned; absentPinnedFolder.folders.removeAll { $0.id == pinnedFolder.id }
        #expect(favoriteProposal(absentPinnedFolder, .insert(0)) == nil, "a missing pinned source container refuses the complete creation")
        var changedProfile = favorite; changedProfile.tabs[ai].profileID = UUID()
        #expect(favoriteProposal(changedProfile, .insert(1)) == nil, "foreign Favorite refuses")
        var absentHome = favorite; absentHome.spaces.removeAll { $0.id == homeSpace }
        #expect(favoriteProposal(absentHome, .insert(1)) == nil, "missing saved home Space refuses")
        let favoriteRoot = root.appendingPathComponent("favorite")
        try FileManager.default.createDirectory(at: favoriteRoot, withIntermediateDirectories: true)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted,.sortedKeys]; encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(favorite).write(to: favoriteRoot.appendingPathComponent("session.json"))
        let favoriteStore = try BrowserStore(directory: favoriteRoot)
        #expect(try favoriteStore.dropExternalURLIntoSplit(destination, tabID: urlID, spaceID: space, profileID: p,
            expectedSelection: [a], expectedLayout: nil, target: .insert(1), orientation: .vertical, creation: receipt, savedHomeID: homeID), "actual Favorite atomic store commit")
        let loadedFavorite = try BrowserStore(directory: favoriteRoot)
        #expect(loadedFavorite.state.tabs.contains { $0.id == homeID && $0.url == favoriteOriginal.savedURL } && loadedFavorite.state.tabs.contains { $0.id == a && $0.kind == .today }, "saved home and live placement survive reload")
        let failedRoot = root.appendingPathComponent("favorite-failure")
        try FileManager.default.createDirectory(at: failedRoot, withIntermediateDirectories: true)
        let failedFile = failedRoot.appendingPathComponent("session.json")
        try encoder.encode(favorite).write(to: failedFile)
        let failedStore = try BrowserStore(directory: failedRoot), failedBefore = failedStore.state
        try FileManager.default.removeItem(at: failedFile); try FileManager.default.createDirectory(at: failedFile, withIntermediateDirectories: false)
        do {
            _ = try failedStore.dropExternalURLIntoSplit(destination, tabID: urlID, spaceID: space, profileID: p,
                expectedSelection: [a], expectedLayout: nil, target: .insert(1), orientation: .vertical, creation: receipt, savedHomeID: homeID)
            throw NSError(domain: "expected saved-home persistence failure", code: 99)
        } catch { #expect(failedStore.state == failedBefore && failedStore.persistenceError != nil, "failed Favorite commit retains original exact state without copy") }
        let pinnedRoot = root.appendingPathComponent("pinned")
        try FileManager.default.createDirectory(at: pinnedRoot, withIntermediateDirectories: true)
        try encoder.encode(pinned).write(to: pinnedRoot.appendingPathComponent("session.json"))
        let pinnedStore = try BrowserStore(directory: pinnedRoot)
        #expect(try pinnedStore.dropExternalURLIntoSplit(destination, tabID: urlID, spaceID: space, profileID: p,
            expectedSelection: [a], expectedLayout: nil, target: .insert(0), orientation: .vertical,
            creation: receipt, savedHomeID: homeID), "actual pinned saved-home and split commit is atomic")
        let pinnedReload = try BrowserStore(directory: pinnedRoot)
        #expect(SidebarHierarchy.children(in: pinnedContainer, state: pinnedReload.state) == [.tab(b), .tab(homeID), .folder(siblingFolder.id)] && pinnedReload.state.selectedTabIDs == [urlID,a], "pinned home order and live original selection durably reopen together")
        let stackRoot = root.appendingPathComponent("stack"), stackID = UUID()
        try FileManager.default.createDirectory(at: stackRoot, withIntermediateDirectories: true)
        try encoder.encode(original).write(to: stackRoot.appendingPathComponent("session.json"))
        let stackStore = try BrowserStore(directory: stackRoot), flat = stackStore.activeSplitLayout
        #expect(flat?.id == group.id && flat?.stacks == nil, "the flat pair reopens as a flat split")
        #expect(try stackStore.dropExternalURLIntoSplit(destination, tabID: stackID, spaceID: space, profileID: p,
            expectedSelection: [a,b], expectedLayout: flat, target: .stack(1, after: false), orientation: .horizontal, creation: receipt),
            "a link on a flat split's top band commits a stack")
        let stackReload = try BrowserStore(directory: stackRoot)
        #expect(stackReload.state.selectedTabIDs == [a,stackID,b] && stackReload.activeSplitLayout?.id == group.id
            && stackReload.activeSplitLayout?.orientation == .horizontal && stackReload.activeSplitLayout?.stacks?.slotSizes == [1, 2]
            && stackReload.state.tabs.first { $0.id == stackID }?.url == destination.absoluteString, "the new tab and its stack reopen together")
        let joinID = UUID()
        #expect(try stackStore.dropExternalURLIntoSplit(destination, tabID: joinID, spaceID: space, profileID: p,
            expectedSelection: [a,stackID,b], expectedLayout: stackStore.activeSplitLayout, target: .stack(2, after: true),
            orientation: .horizontal, creation: receipt), "a link joins an existing stack")
        #expect(stackStore.state.selectedTabIDs == [a,stackID,b,joinID] && stackStore.activeSplitLayout?.stacks?.slotSizes == [1, 3]
            && stackStore.activeSplitLayout?.id == group.id, "the link lands below the stacked pane")
        let fullStack = stackStore.state
        #expect(!(try stackStore.dropExternalURLIntoSplit(destination, tabID: UUID(), spaceID: space, profileID: p,
            expectedSelection: fullStack.selectedTabIDs, expectedLayout: stackStore.activeSplitLayout, target: .stack(0, after: false),
            orientation: .horizontal, creation: receipt)) && stackStore.state == fullStack, "a full stacked split refuses another link stack")
        let noteFile = root.appendingPathComponent("Shared Note.md"); try Data().write(to: noteFile)
        let easels = try EaselStore(directory: root.appendingPathComponent("easels"))
        let easel = try easels.create()
        let noteRef = SidebarDocumentReference(page: .note(noteFile), profileID: p) { guard FileManager.default.fileExists(atPath: noteFile.path) else { throw CocoaError(.fileNoSuchFile) } }
        let easelRef = SidebarDocumentReference(page: .easel(easel.document.id), profileID: p) { try easels.validateReference(easel.document.id) }
        for (name, reference, address) in [("note", noteRef, InternalPage.note(noteFile).urlString),
                                            ("easel", easelRef, "parc://easel/" + easel.document.id.uuidString)] {
            for savedKind in [TabKind.favorite, .pinned] {
            var documentState = savedKind == .favorite ? favorite : pinned
            documentState.tabs[ai].url = address; documentState.tabs[ai].savedURL = address
            let path = root.appendingPathComponent(name + "-" + savedKind.rawValue)
            try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
            try encoder.encode(documentState).write(to: path.appendingPathComponent("session.json"))
            let documentStore = try BrowserStore(directory: path), beforeDocument = documentStore.state
            #expect(try !documentStore.dropExternalURLIntoSplit(destination, tabID: urlID, spaceID: space, profileID: p,
                expectedSelection: [a], expectedLayout: nil, target: .insert(1), orientation: .vertical, creation: receipt,
                savedHomeID: homeID), "typed saved home needs actual original document validation")
            #expect(documentStore.state == beforeDocument, "unvalidated alias publishes nothing")
            #expect(try documentStore.dropExternalURLIntoSplit(destination, tabID: urlID, spaceID: space, profileID: p,
                expectedSelection: [a], expectedLayout: nil, target: .insert(1), orientation: .vertical, creation: receipt,
                savedHomeID: homeID, documents: [a: reference]), "validated typed saved home commits")
            #expect(documentStore.state.tabs.first { $0.id == homeID }?.url == address && documentStore.state.tabs.first { $0.id == a }?.url == address,
                      "typed original and home share exact existing document identity")
            }
        }
        #expect(try FileManager.default.fileExists(atPath: noteFile.path) && (try easels.load(easel.document.id) === easel), "original shared documents remain exact")
        var decorated = original; var decoratedGroup = group
        decoratedGroup.customTitle = "Original group"; decoratedGroup.customIcon = .emoji("🌙")
        decorated.splitLayouts = [decoratedGroup]
        let preserved = proposal(decorated, .replace(0), [a,b], decoratedGroup)!
        #expect(preserved.splitLayouts.first?.customTitle == decoratedGroup.customTitle && preserved.splitLayouts.first?.customIcon == decoratedGroup.customIcon, "original group appearance survives URL creation")
        var documents = original
        documents.tabs[0].url = "parc://note/" + UUID().uuidString; documents.tabs[0].savedURL = documents.tabs[0].url
        documents.tabs[1].url = "parc://easel/" + UUID().uuidString; documents.tabs[1].savedURL = documents.tabs[1].url
        let documentReplacement = proposal(documents, .replace(1), [a,b], group)!
        #expect(documentReplacement.tabs.first { $0.id == b } == documents.tabs.first { $0.id == b }, "displaced local reference/document untouched")
        #expect(documentReplacement.tabs.first { $0.id == a }?.url == documents.tabs.first { $0.id == a }?.url, "retained local pane identity untouched")
        var moved = original; moved.tabs[0].profileID = UUID()
        #expect(proposal(moved, .insert(1), [a,b], group) == nil, "original profile refusal")
        var archived = original; archived.tabs[0].archivedAt = Date()
        #expect(proposal(archived, .insert(1), [a,b], group) == nil, "archived original refusal")
        #expect(proposal(original, .insert(8), [a,b], group) == nil && proposal(original, .replace(-1), [a,b], group) == nil, "invalid target refused")
        let current = store.state, currentGroup = store.activeSplitLayout!
        let stateFile = root.appendingPathComponent("session.json"), saved = try Data(contentsOf: stateFile)
        try FileManager.default.removeItem(at: stateFile); try FileManager.default.createDirectory(at: stateFile, withIntermediateDirectories: false)
        do {
            _ = try store.dropExternalURLIntoSplit(destination, tabID: UUID(), spaceID: space, profileID: p,
                expectedSelection: current.selectedTabIDs, expectedLayout: currentGroup, target: .insert(0), orientation: .horizontal, creation: receipt)
            throw NSError(domain: "expected persistence error", code: 99)
        } catch { #expect(store.state == current && store.persistenceError != nil, "failed write retains exact original state") }
        try FileManager.default.removeItem(at: stateFile); try saved.write(to: stateFile)
    }
}
