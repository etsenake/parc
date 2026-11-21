import Foundation
import Testing
@testable import ParcCore

@MainActor
struct SidebarSplitCopyTests {
    private static func write(_ state: BrowserState, to directory: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try encoder.encode(state).write(to: directory.appendingPathComponent("session.json", isDirectory: false))
    }

    @MainActor final class Fixture {
        let root: URL
        let profile = BrowserProfile(id: UUID(), name: "Original")
        let foreignProfile = BrowserProfile(id: UUID(), name: "Other")
        let here: BrowserSpace, there: BrowserSpace, elsewhere: BrowserSpace
        let folder: BrowserFolder
        let left: BrowserTab, right: BrowserTab, keep: BrowserTab, inside: BrowserTab
        let today: BrowserTab, away: BrowserTab, favA: BrowserTab, favB: BrowserTab, foreignTab: BrowserTab
        let split: BrowserSplitLayout, favorite: BrowserSplitLayout
        let pinned: SidebarContainerLocation, inFolder: SidebarContainerLocation, todayLocation: SidebarContainerLocation
        let therePinned: SidebarContainerLocation, favorites: SidebarContainerLocation, elsewherePinned: SidebarContainerLocation
        let state: BrowserState
        let store: BrowserStore
        let target: SidebarItemsCopy
        let urls: [UUID: String]
        let favURLs: [UUID: String]

        init() throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent("parc-split-copy-" + UUID().uuidString)
            let profileID = profile.id, foreignID = foreignProfile.id
            here = BrowserSpace(id: UUID(), name: "Here", symbol: "circle", color: "ABCDEF", profileID: profileID)
            there = BrowserSpace(id: UUID(), name: "There", symbol: "circle", color: "FEDCBA", profileID: profileID)
            elsewhere = BrowserSpace(id: UUID(), name: "Elsewhere", symbol: "circle", color: "123456", profileID: foreignID)
            folder = BrowserFolder(id: UUID(), spaceID: here.id, name: "Folder")
            let hereID = here.id, thereID = there.id
            func tab(_ title: String, kind: TabKind = .pinned, space: UUID? = nil, folder: UUID? = nil) -> BrowserTab {
                let url = "https://saved.invalid/" + title
                return .init(id: UUID(), spaceID: space ?? hereID, profileID: profileID, url: url, title: title,
                             kind: kind, folderID: folder, createdAt: Date(timeIntervalSince1970: 10),
                             lastAccessed: Date(timeIntervalSince1970: 10), savedURL: url, savedTitle: title)
            }
            left = tab("Left"); right = tab("Right"); keep = tab("Keep"); inside = tab("Inside", folder: folder.id)
            today = tab("Today", kind: .today); away = tab("Away", space: thereID)
            favA = tab("FavA", kind: .favorite); favB = tab("FavB", kind: .favorite)
            foreignTab = BrowserTab(id: UUID(), spaceID: elsewhere.id, profileID: foreignID, url: "https://saved.invalid/F", title: "F",
                                    kind: .pinned, createdAt: Date(timeIntervalSince1970: 10), lastAccessed: Date(timeIntervalSince1970: 10),
                                    savedURL: "https://saved.invalid/F", savedTitle: "F")
            split = BrowserSplitLayout(sidebarAnchorID: left.id, customTitle: "Pair", spaceID: here.id,
                tabIDs: [left.id, right.id], orientation: .vertical, widthFactors: [0.4, 0.6])
            favorite = BrowserSplitLayout(sidebarAnchorID: favA.id, spaceID: here.id, tabIDs: [favA.id, favB.id], widthFactors: [0.5, 0.5])
            var state = BrowserState(profiles: [profile, foreignProfile], spaces: [here, there, elsewhere], activeSpaceID: here.id)
            state.folders = [folder]
            state.tabs = [left, right, keep, inside, today, away, favA, favB, foreignTab]
            state.splitLayouts = [split, favorite]
            pinned = SidebarContainerLocation(spaceID: here.id, folderID: nil, section: .pinned)
            inFolder = SidebarContainerLocation(spaceID: here.id, folderID: folder.id, section: .pinned)
            todayLocation = SidebarContainerLocation(spaceID: here.id, folderID: nil, section: .today)
            therePinned = SidebarContainerLocation(spaceID: there.id, folderID: nil, section: .pinned)
            favorites = SidebarContainerLocation(spaceID: here.id, folderID: nil, section: .favorite, profileID: profileID)
            state.sidebarItemOrder[pinned.key] = [.tab(keep.id), .tab(left.id), .folder(folder.id)]
            state.sidebarItemOrder[inFolder.key] = [.tab(inside.id)]
            state.sidebarItemOrder[therePinned.key] = [.tab(away.id)]
            elsewherePinned = SidebarContainerLocation(spaceID: elsewhere.id, folderID: nil, section: .pinned)
            state.sidebarItemOrder[elsewherePinned.key] = [.tab(foreignTab.id)]
            state.selectedTabIDs = split.tabIDs
            state.selectionBySpace[here.id.uuidString] = split.tabIDs
            self.state = state
            try SidebarSplitCopyTests.write(state, to: root)
            store = try BrowserStore(directory: root, now: { Date(timeIntervalSince1970: 1000) })
            target = SidebarItemsCopy(items: [.split(split.id)], spaceID: here.id, profileID: profile.id, state: store.state)!
            urls = [left.id: "https://live.invalid/left", right.id: "https://live.invalid/right"]
            favURLs = [favA.id: "https://live.invalid/a", favB.id: "https://live.invalid/b"]
        }

        deinit { try? FileManager.default.removeItem(at: root) }

        func copyOfSplit(_ id: UUID? = nil) -> SidebarItemsCopy {
            SidebarItemsCopy(items: [.split(id ?? split.id)], spaceID: here.id, profileID: profile.id, state: store.state)!
        }

        func group(_ result: SidebarDuplicateResult) throws -> BrowserSplitLayout {
            guard case .split(let id)? = result.roots.first else { throw Failure() }
            return try #require(store.state.splitLayouts.first { $0.id == id })
        }

        struct Failure: Error {}
    }

    @Test func theFixtureProjectsTheSplitAsOneRoot() throws {
        let f = try Fixture()
        #expect(SidebarHierarchy.children(in: f.pinned, state: f.store.state) == [.tab(f.keep.id), .split(f.split.id), .folder(f.folder.id)])
    }

    @Test func onlyAllSplitDragsAreWholeSplitCopies() throws {
        let f = try Fixture()
        let initial = f.store.state
        func copy(_ items: [SidebarItemReference]) -> SidebarItemsCopy? {
            SidebarItemsCopy(items: items, spaceID: f.here.id, profileID: f.profile.id, state: initial)
        }
        #expect(f.target.wholeSplits)
        #expect(copy([.tab(f.keep.id)])?.wholeSplits == false)
        #expect(copy([.folder(f.folder.id)])?.wholeSplits == false)
        #expect(copy([.split(f.split.id), .tab(f.keep.id)])?.wholeSplits == false)
    }

    @Test func aProposalAdmitsTheCopyWithoutPublishing() throws {
        let f = try Fixture()
        let initial = f.store.state
        #expect(f.store.canCopySidebarItems(f.target, to: f.pinned, before: .tab(f.keep.id), destinations: f.urls))
        #expect(f.store.state == initial)
    }

    @Test func invalidDestinationsRefuseTheCopy() throws {
        let f = try Fixture()
        let initial = f.store.state
        let foreign = SidebarContainerLocation(spaceID: f.here.id, folderID: nil, section: .favorite, profileID: UUID())
        #expect(!f.store.canCopySidebarItems(f.target, to: foreign, before: nil, destinations: f.urls))
        #expect(!f.store.canCopySidebarItems(f.target, to: f.pinned, before: .tab(f.away.id), destinations: f.urls))
        #expect(!f.store.canCopySidebarItems(f.target, to: f.pinned, before: nil, destinations: [f.left.id: f.urls[f.left.id]!]))
        #expect(try f.store.copySidebarItems(f.target, to: f.pinned, before: .tab(f.away.id), destinations: f.urls) == nil)
        #expect(f.store.state == initial)
    }

    @Test func aCopyIsOneFreshSplitRootWithFreshChildIdentitiesInOriginalOrder() throws {
        let f = try Fixture()
        let first = try #require(try f.store.copySidebarItems(f.target, to: f.pinned, before: .tab(f.keep.id), destinations: f.urls))
        let group = try f.group(first)
        guard case .split(let firstID)? = first.roots.first else { Issue.record("copy root"); return }
        #expect(first.roots.count == 1)
        #expect(firstID != f.split.id)
        #expect(Set(group.tabIDs).isDisjoint(with: f.split.tabIDs))
        #expect(group.tabIDs == first.tabIDs)
        #expect(group.orientation == f.split.orientation)
        #expect(group.widthFactors == f.split.widthFactors)
        #expect(group.customTitle == f.split.customTitle)
    }

    @Test func theCopyIsPlacedAtTheDropLocationAndTheOriginalKeepsItsSlotAndRecords() throws {
        let f = try Fixture()
        let initial = f.store.state
        let first = try #require(try f.store.copySidebarItems(f.target, to: f.pinned, before: .tab(f.keep.id), destinations: f.urls))
        let after = f.store.state
        guard case .split(let firstID)? = first.roots.first else { Issue.record("copy root"); return }
        #expect(SidebarHierarchy.children(in: f.pinned, state: after) == [.split(firstID), .tab(f.keep.id), .split(f.split.id), .folder(f.folder.id)])
        #expect(after.splitLayouts.first { $0.id == f.split.id } == f.split)
        #expect(f.split.tabIDs.allSatisfy { id in after.tabs.first { $0.id == id } == initial.tabs.first { $0.id == id } })
    }

    @Test func childrenTakeTheResolvedURLsAndThePinnedRootAndTheStoreLeavesSelectionToTheWindow() throws {
        let f = try Fixture()
        let initial = f.store.state
        let first = try #require(try f.store.copySidebarItems(f.target, to: f.pinned, before: .tab(f.keep.id), destinations: f.urls))
        let after = f.store.state
        let group = try f.group(first)
        let children = group.tabIDs.map { id in after.tabs.first { $0.id == id }! }
        #expect(children.map(\.savedURL) == [f.urls[f.left.id]!, f.urls[f.right.id]!])
        #expect(children.allSatisfy { $0.kind == .pinned && $0.folderID == nil && $0.spaceID == f.here.id })
        #expect(first.openTabIDs == group.tabIDs)
        #expect(after.selectedTabIDs == initial.selectedTabIDs)
        #expect(after.activeSpaceID == initial.activeSpaceID)
    }

    @Test func aFolderDropAppendsTheCopyInsideItAndTheChildrenCarryTheFolder() throws {
        let f = try Fixture()
        let foldered = try #require(try f.store.copySidebarItems(f.target, to: f.inFolder, before: nil, destinations: f.urls))
        let group = try f.group(foldered)
        guard case .split(let folderedID)? = foldered.roots.first else { Issue.record("folder copy"); return }
        #expect(SidebarHierarchy.children(in: f.inFolder, state: f.store.state) == [.tab(f.inside.id), .split(folderedID)])
        #expect(group.tabIDs.allSatisfy { id in f.store.state.tabs.first { $0.id == id }?.folderID == f.folder.id })
    }

    @Test func aTodayDropPlacesTheCopyBeforeItsTargetAsTodayItems() throws {
        let f = try Fixture()
        let unpinned = try #require(try f.store.copySidebarItems(f.target, to: f.todayLocation, before: .tab(f.today.id), destinations: f.urls))
        let group = try f.group(unpinned)
        #expect(SidebarHierarchy.children(in: f.todayLocation, state: f.store.state).first == .split(group.id))
        #expect(group.tabIDs.allSatisfy { id in f.store.state.tabs.first { $0.id == id }?.kind == .today })
    }

    @Test func anotherSpacesWindowPlacesTheCopyInItsOwnSpaceAndTheSourceKeepsTheOriginal() throws {
        let f = try Fixture()
        let moved = try #require(try f.store.copySidebarItems(f.target, to: f.therePinned, before: .tab(f.away.id), destinations: f.urls))
        let group = try f.group(moved)
        let after = f.store.state
        #expect(SidebarHierarchy.children(in: f.therePinned, state: after) == [.split(group.id), .tab(f.away.id)])
        #expect(group.spaceID == f.there.id)
        #expect(group.tabIDs.allSatisfy { id in after.tabs.first { $0.id == id }?.spaceID == f.there.id })
        #expect(SidebarHierarchy.children(in: f.pinned, state: after).contains(.split(f.split.id)))
        #expect(after.splitLayouts.first { $0.id == f.split.id }?.spaceID == f.here.id)
    }

    @Test func anAppTrayDropMakesTheCopyAFavoriteRootWithFavoriteChildren() throws {
        let f = try Fixture()
        let tray = try #require(try f.store.copySidebarItems(f.target, to: f.favorites, before: nil, destinations: f.urls))
        let group = try f.group(tray)
        let after = f.store.state
        #expect(SidebarHierarchy.children(in: f.favorites, state: after).contains(.split(group.id)))
        #expect(group.tabIDs.allSatisfy { id in after.tabs.first { $0.id == id }?.kind == .favorite })
        #expect(after.splitLayouts.first { $0.id == f.split.id } == f.split)
    }

    @Test func aFavoriteSplitsCopyLandsAtTheDropLocationWithPinnedChildrenAndTheOriginalStaysInTheTray() throws {
        let f = try Fixture()
        let favoriteCopy = f.copyOfSplit(f.favorite.id)
        let outOfTray = try #require(try f.store.copySidebarItems(favoriteCopy, to: f.pinned, before: nil, destinations: f.favURLs))
        let group = try f.group(outOfTray)
        let after = f.store.state
        #expect(SidebarHierarchy.children(in: f.pinned, state: after).last == .split(group.id))
        #expect(group.tabIDs.allSatisfy { id in after.tabs.first { $0.id == id }.map { $0.kind == .pinned && $0.spaceID == f.here.id } == true })
        #expect(SidebarHierarchy.children(in: f.favorites, state: after).contains(.split(f.favorite.id)))
        #expect(after.splitLayouts.contains(f.favorite))
        #expect(outOfTray.openTabIDs == group.tabIDs)
    }

    @Test func aCopyWithinTheTrayLandsBeforeItsTarget() throws {
        let f = try Fixture()
        let favoriteAgain = f.copyOfSplit(f.favorite.id)
        let inTray = try #require(try f.store.copySidebarItems(favoriteAgain, to: f.favorites, before: .split(f.favorite.id), destinations: f.favURLs))
        guard case .split(let inTrayID)? = inTray.roots.first else { Issue.record("tray reorder copy"); return }
        let trayOrder = SidebarHierarchy.children(in: f.favorites, state: f.store.state)
        #expect(trayOrder.firstIndex(of: .split(inTrayID)).map { $0 + 1 == trayOrder.firstIndex(of: .split(f.favorite.id)) } == true)
    }

    @Test func aCrossProfileCopyLandsInTheOtherProfilesSpaceAndTheOriginalsKeepTheirProfile() throws {
        let f = try Fixture()
        let crossed = try #require(try f.store.copySidebarItems(f.target, to: f.elsewherePinned, before: .tab(f.foreignTab.id), destinations: f.urls))
        let group = try f.group(crossed)
        let after = f.store.state
        #expect(SidebarHierarchy.children(in: f.elsewherePinned, state: after) == [.split(group.id), .tab(f.foreignTab.id)])
        #expect(group.spaceID == f.elsewhere.id)
        #expect(group.tabIDs.allSatisfy { id in
            after.tabs.first { $0.id == id }.map { $0.profileID == f.foreignProfile.id && $0.spaceID == f.elsewhere.id } == true
        })
        #expect(f.split.tabIDs.allSatisfy { id in after.tabs.first { $0.id == id }?.profileID == f.profile.id })
        #expect(after.splitLayouts.contains(f.split))
    }

    @Test func aRefusedLeavePagePromptPublishesNoCopyAndConsentRetiresExactlyTheOriginalsPages() throws {
        let f = try Fixture()
        let store = f.store
        var retired: Set<UUID> = []
        var consent = false
        store.requestPageRetirement = { ids, shouldCommit, done in
            retired = ids
            done(consent && shouldCommit())
        }
        let before = store.state
        var refused: Result<SidebarDuplicateResult?, Error>?
        store.copySidebarSplitsReloadingOriginals(f.target, to: f.elsewherePinned, before: nil, destinations: f.urls) { refused = $0 }
        guard case .success(nil)? = refused else { Issue.record("refused reload"); return }
        #expect(retired == Set(f.split.tabIDs))
        #expect(store.state == before)
        consent = true
        var reloaded: Result<SidebarDuplicateResult?, Error>?
        store.copySidebarSplitsReloadingOriginals(f.target, to: f.elsewherePinned, before: nil, destinations: f.urls) { reloaded = $0 }
        guard case .success(let made?)? = reloaded, case .split(let reloadedID)? = made.roots.first else { Issue.record("reload copy"); return }
        let after = store.state
        #expect(retired == Set(f.split.tabIDs))
        #expect(SidebarHierarchy.children(in: f.elsewherePinned, state: after).last == .split(reloadedID))
        #expect(after.splitLayouts.contains(f.split))
        #expect(f.split.tabIDs.allSatisfy { id in after.tabs.first { $0.id == id }?.profileID == f.profile.id })
    }

    @Test func aSplitWithANoteChildCopiesIntoAnotherProfileAndWithinItsProfileAsAnAlias() throws {
        let f = try Fixture()
        let note = BrowserTab(id: UUID(), spaceID: f.here.id, profileID: f.profile.id, url: "https://saved.invalid/Note", title: "Note",
            kind: .pinned, createdAt: Date(timeIntervalSince1970: 10), lastAccessed: Date(timeIntervalSince1970: 10),
            savedURL: "https://saved.invalid/Note", savedTitle: "Note")
        let web = BrowserTab(id: UUID(), spaceID: f.here.id, profileID: f.profile.id, url: "https://saved.invalid/Web", title: "Web",
            kind: .pinned, createdAt: Date(timeIntervalSince1970: 10), lastAccessed: Date(timeIntervalSince1970: 10),
            savedURL: "https://saved.invalid/Web", savedTitle: "Web")
        var withNote = f.state
        let noteSplit = BrowserSplitLayout(sidebarAnchorID: note.id, spaceID: f.here.id, tabIDs: [note.id, web.id], widthFactors: [0.5, 0.5])
        var typedNote = note
        let noteID = URL(fileURLWithPath: NSTemporaryDirectory() + "Parc Notes/" + UUID().uuidString + ".md")
        typedNote.url = InternalPage.note(noteID).urlString
        typedNote.savedURL = typedNote.url
        withNote.tabs += [typedNote, web]
        withNote.splitLayouts.append(noteSplit)
        let noteRoot = f.root.appendingPathComponent("Notes-" + UUID().uuidString)
        try Self.write(withNote, to: noteRoot)
        let noteStore = try BrowserStore(directory: noteRoot, now: { Date(timeIntervalSince1970: 1000) })
        let noteCopy = try #require(SidebarItemsCopy(items: [.split(noteSplit.id)], spaceID: f.here.id, profileID: f.profile.id, state: noteStore.state))
        let noteDocs = [typedNote.id: SidebarDocumentReference(page: .note(noteID), profileID: f.profile.id) {}]
        let noteURLs = [typedNote.id: typedNote.savedURL, web.id: "https://live.invalid/web"]
        #expect(noteStore.canCopySidebarItems(noteCopy, to: f.elsewherePinned, before: nil, destinations: noteURLs, documents: noteDocs))
        #expect(noteStore.canCopySidebarItems(noteCopy, to: f.pinned, before: nil, destinations: noteURLs, documents: noteDocs))
    }

    @Test func aStaleGestureCopiesTheCurrentRecordsAndAChangedFolderNoLongerMatchesTheGesture() throws {
        let f = try Fixture()
        let store = f.store
        let stale = f.copyOfSplit()
        store.updateTab(f.left.id, title: "Renamed while deciding", url: "https://live.invalid/moved-on")
        _ = store.open("https://unrelated.invalid/", kind: .today)
        let staleResult = try store.copySidebarItems(stale, to: f.pinned, before: nil, destinations: f.urls)
        guard case .split(let staleID)? = staleResult?.roots.first else { Issue.record("stale copy"); return }
        #expect(store.state.tabs.first { $0.id == store.state.splitLayouts.first { $0.id == staleID }!.tabIDs[0] }?.savedTitle
                == store.state.tabs.first { $0.id == f.left.id }?.savedTitle)
        var refoldered = store.state
        if let index = refoldered.tabs.firstIndex(where: { $0.id == f.right.id }) { refoldered.tabs[index].folderID = f.folder.id }
        #expect(SidebarItemsCopy(items: [.split(f.split.id)], spaceID: f.here.id, profileID: f.profile.id, state: refoldered)?.matchesPlacement(of: stale) != true)
    }

    @Test func aFailedSaveThrowsAndChangesNeitherStateNorDisk() throws {
        let f = try Fixture()
        let store = f.store
        let sessionURL = f.root.appendingPathComponent("session.json")
        let beforeFailure = store.state, savedBytes = try Data(contentsOf: sessionURL)
        try FileManager.default.removeItem(at: sessionURL)
        try FileManager.default.createDirectory(at: sessionURL, withIntermediateDirectories: false)
        let failing = f.copyOfSplit()
        #expect(throws: (any Error).self) { try store.copySidebarItems(failing, to: f.pinned, before: nil, destinations: f.urls) }
        try FileManager.default.removeItem(at: sessionURL)
        try savedBytes.write(to: sessionURL)
        #expect(store.state == beforeFailure)
        #expect(try Data(contentsOf: sessionURL) == savedBytes)
    }

    @Test func aRetiringChildAnEphemeralStoreAnArchivedChildAndARemovingProfileRefuseTheCopy() throws {
        let f = try Fixture()
        let store = f.store
        var pendingDone: ((Bool) -> Void)?
        store.requestPageRetirement = { _, _, done in pendingDone = done }
        store.closeTabs([f.right.id]) { _ in }
        let retiringCopy = f.copyOfSplit()
        #expect(!store.canCopySidebarItems(retiringCopy, to: f.pinned, before: nil, destinations: f.urls))
        pendingDone?(false)
        store.requestPageRetirement = nil
        let ephemeral = BrowserStore(privateParentProfileID: f.profile.id, engineProfilePath: "/nonexistent", directory: f.root, settings: BrowserSettings())
        #expect(!ephemeral.canCopySidebarItems(retiringCopy, to: f.pinned, before: nil, destinations: f.urls))
        var archived = store.state
        if let index = archived.tabs.firstIndex(where: { $0.id == f.right.id }) { archived.tabs[index].archivedAt = Date(timeIntervalSince1970: 5) }
        #expect(SidebarItemsCopy(items: [.split(f.split.id)], spaceID: f.here.id, profileID: f.profile.id, state: archived) == nil)
        var removing = store.state
        removing.profileRemovals = [ProfileRemovalRecord(id: UUID(), profileID: f.foreignProfile.id, profileName: f.foreignProfile.name)]
        #expect(!InterProfileMove.profilesAvailable(f.profile.id, f.foreignProfile.id, in: removing))
        #expect(SidebarWindowMove(items: [.split(f.split.id)], sourceSpaceID: f.here.id, profileID: f.profile.id,
                                  destinationProfileID: f.foreignProfile.id, to: f.elsewherePinned, before: nil, state: removing) == nil)
    }

    func fullTray(_ f: Fixture) throws -> (BrowserStore, BrowserState) {
        var full = f.store.state
        let count = 12 - SidebarHierarchy.children(in: f.favorites, state: full).count
        let fillers = (0..<count).map { index in
            BrowserTab(id: UUID(), spaceID: f.here.id, profileID: f.profile.id, url: "https://saved.invalid/Filler\(index)", title: "Filler\(index)",
                kind: .favorite, createdAt: Date(timeIntervalSince1970: 10), lastAccessed: Date(timeIntervalSince1970: 10),
                savedURL: "https://saved.invalid/Filler\(index)", savedTitle: "Filler\(index)")
        }
        full.tabs += fillers
        let fullRoot = f.root.appendingPathComponent("Full-" + UUID().uuidString)
        try Self.write(full, to: fullRoot)
        return (try BrowserStore(directory: fullRoot), full)
    }

    @Test func aFullTrayRefusesASplitCopiedInAndAFavoriteSplitCopiedWithinButStillCopiesOut() throws {
        let f = try Fixture()
        let (fullStore, full) = try fullTray(f)
        #expect(SidebarHierarchy.children(in: f.favorites, state: fullStore.state).count == 12)
        let intoFull = SidebarItemsCopy(items: [.split(f.split.id)], spaceID: f.here.id, profileID: f.profile.id, state: fullStore.state)!
        let withinFull = SidebarItemsCopy(items: [.split(f.favorite.id)], spaceID: f.here.id, profileID: f.profile.id, state: fullStore.state)!
        #expect(!fullStore.canCopySidebarItems(intoFull, to: f.favorites, before: nil, destinations: f.urls))
        #expect(try fullStore.copySidebarItems(intoFull, to: f.favorites, before: nil, destinations: f.urls) == nil)
        #expect(fullStore.state.tabs.count == full.tabs.count)
        #expect(!fullStore.canCopySidebarItems(withinFull, to: f.favorites, before: nil, destinations: f.favURLs))
        #expect(fullStore.canCopySidebarItems(withinFull, to: f.pinned, before: nil, destinations: f.favURLs))
    }

    @Test func severalSplitsLandTogetherInTheirOriginalOrderAndEveryChildRequestsAPage() throws {
        let f = try Fixture()
        var multi = f.store.state
        func tab(_ title: String) -> BrowserTab {
            BrowserTab(id: UUID(), spaceID: f.here.id, profileID: f.profile.id, url: "https://saved.invalid/" + title, title: title,
                kind: .pinned, createdAt: Date(timeIntervalSince1970: 10), lastAccessed: Date(timeIntervalSince1970: 10),
                savedURL: "https://saved.invalid/" + title, savedTitle: title)
        }
        let m1 = tab("M1"), m2 = tab("M2")
        let second = BrowserSplitLayout(sidebarAnchorID: m1.id, spaceID: f.here.id, tabIDs: [m1.id, m2.id], widthFactors: [0.5, 0.5])
        multi.tabs += [m1, m2]
        multi.splitLayouts.append(second)
        multi.sidebarItemOrder[f.pinned.key] = (multi.sidebarItemOrder[f.pinned.key] ?? []) + [.tab(m1.id)]
        let multiRoot = f.root.appendingPathComponent("Multi-" + UUID().uuidString)
        try Self.write(multi, to: multiRoot)
        let multiStore = try BrowserStore(directory: multiRoot)
        let both = SidebarItemsCopy(items: [.split(f.split.id), .split(second.id)], spaceID: f.here.id, profileID: f.profile.id, state: multiStore.state)!
        var bothURLs = f.urls
        bothURLs[m1.id] = "https://live.invalid/m1"
        bothURLs[m2.id] = "https://live.invalid/m2"
        let pair = try #require(try multiStore.copySidebarItems(both, to: f.todayLocation, before: nil, destinations: bothURLs))
        #expect(pair.roots.count == 2)
        #expect(Array(SidebarHierarchy.children(in: f.todayLocation, state: multiStore.state).suffix(2)) == pair.roots)
        #expect(pair.openTabIDs.count == 4)
    }

    @Test func everyPlacedCopyReloadsDurably() throws {
        let f = try Fixture()
        let first = try #require(try f.store.copySidebarItems(f.target, to: f.pinned, before: .tab(f.keep.id), destinations: f.urls))
        let tray = try #require(try f.store.copySidebarItems(f.copyOfSplit(), to: f.favorites, before: nil, destinations: f.urls))
        let reload = try BrowserStore(directory: f.root)
        for result in [first, tray] {
            guard case .split(let id)? = result.roots.first else { Issue.record("root"); continue }
            #expect(reload.state.splitLayouts.contains { $0.id == id })
        }
    }

    @MainActor final class Items {
        let root: URL
        let profile = BrowserProfile(id: UUID(), name: "Original")
        let foreignProfile = BrowserProfile(id: UUID(), name: "Other")
        let here: BrowserSpace, there: BrowserSpace, elsewhere: BrowserSpace
        let outer: BrowserFolder, nested: BrowserFolder, target: BrowserFolder
        let loose: BrowserTab, today: BrowserTab, favorite: BrowserTab, inOuter: BrowserTab, inNested: BrowserTab
        let pairA: BrowserTab, pairB: BrowserTab, rootA: BrowserTab, rootB: BrowserTab, note: BrowserTab
        let nestedSplit: BrowserSplitLayout, rootSplit: BrowserSplitLayout
        let noteID: URL
        let pinned: SidebarContainerLocation, todayLocation: SidebarContainerLocation, outerLocation: SidebarContainerLocation
        let targetLocation: SidebarContainerLocation, therePinned: SidebarContainerLocation
        let elsewherePinned: SidebarContainerLocation, favorites: SidebarContainerLocation
        let store: BrowserStore
        let initial: BrowserState
        let noteDocs: [UUID: SidebarDocumentReference]

        init() throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent("parc-split-copy-" + UUID().uuidString)
            let profileID = profile.id, foreignID = foreignProfile.id
            here = BrowserSpace(id: UUID(), name: "Here", symbol: "circle", color: "ABCDEF", profileID: profileID)
            there = BrowserSpace(id: UUID(), name: "There", symbol: "circle", color: "FEDCBA", profileID: profileID)
            elsewhere = BrowserSpace(id: UUID(), name: "Elsewhere", symbol: "circle", color: "123456", profileID: foreignID)
            outer = BrowserFolder(id: UUID(), spaceID: here.id, name: "Outer")
            nested = BrowserFolder(id: UUID(), spaceID: here.id, name: "Nested", parentID: outer.id, isExpanded: false)
            target = BrowserFolder(id: UUID(), spaceID: here.id, name: "Target")
            let hereID = here.id
            func tab(_ title: String, kind: TabKind = .pinned, folder: UUID? = nil, url: String? = nil) -> BrowserTab {
                let url = url ?? "https://saved.invalid/" + title
                return .init(id: UUID(), spaceID: hereID, profileID: profileID, url: url, title: title, kind: kind, folderID: folder,
                             createdAt: Date(timeIntervalSince1970: 10), lastAccessed: Date(timeIntervalSince1970: 10), savedURL: url, savedTitle: title)
            }
            noteID = URL(fileURLWithPath: NSTemporaryDirectory() + "Parc Notes/" + UUID().uuidString + ".md")
            loose = tab("Loose"); today = tab("Today", kind: .today); favorite = tab("Favorite", kind: .favorite)
            inOuter = tab("InOuter", folder: outer.id); inNested = tab("InNested", folder: nested.id)
            pairA = tab("PairA", folder: nested.id); pairB = tab("PairB", folder: nested.id)
            rootA = tab("RootA"); rootB = tab("RootB"); note = tab("Note", url: InternalPage.note(noteID).urlString)
            nestedSplit = BrowserSplitLayout(sidebarAnchorID: pairA.id, spaceID: here.id, tabIDs: [pairA.id, pairB.id], widthFactors: [0.5, 0.5])
            rootSplit = BrowserSplitLayout(sidebarAnchorID: rootA.id, customTitle: "Root pair", spaceID: here.id,
                                           tabIDs: [rootA.id, rootB.id], widthFactors: [0.3, 0.7])
            var state = BrowserState(profiles: [profile, foreignProfile], spaces: [here, there, elsewhere], activeSpaceID: here.id)
            state.folders = [outer, nested, target]
            state.tabs = [loose, today, favorite, inOuter, inNested, pairA, pairB, rootA, rootB, note]
            state.splitLayouts = [nestedSplit, rootSplit]
            pinned = SidebarContainerLocation(spaceID: here.id, folderID: nil, section: .pinned)
            todayLocation = SidebarContainerLocation(spaceID: here.id, folderID: nil, section: .today)
            outerLocation = SidebarContainerLocation(spaceID: here.id, folderID: outer.id, section: .pinned)
            let nestedLocation = SidebarContainerLocation(spaceID: here.id, folderID: nested.id, section: .pinned)
            targetLocation = SidebarContainerLocation(spaceID: here.id, folderID: target.id, section: .pinned)
            therePinned = SidebarContainerLocation(spaceID: there.id, folderID: nil, section: .pinned)
            elsewherePinned = SidebarContainerLocation(spaceID: elsewhere.id, folderID: nil, section: .pinned)
            favorites = SidebarContainerLocation(spaceID: here.id, folderID: nil, section: .favorite, profileID: profile.id)
            state.sidebarItemOrder[pinned.key] = [.tab(loose.id), .folder(outer.id), .tab(rootA.id), .tab(note.id), .folder(target.id)]
            state.sidebarItemOrder[outerLocation.key] = [.folder(nested.id), .tab(inOuter.id)]
            state.sidebarItemOrder[nestedLocation.key] = [.tab(inNested.id), .tab(pairA.id)]
            try SidebarSplitCopyTests.write(state, to: root)
            store = try BrowserStore(directory: root, now: { Date(timeIntervalSince1970: 1000) })
            initial = store.state
            noteDocs = [note.id: SidebarDocumentReference(page: .note(noteID), profileID: profile.id) {}]
        }

        deinit { try? FileManager.default.removeItem(at: root) }

        func copy(_ items: [SidebarItemReference]) -> SidebarItemsCopy? {
            SidebarItemsCopy(items: items, spaceID: here.id, profileID: profile.id, state: store.state)
        }

        func sources(_ copy: SidebarItemsCopy) -> [UUID: String] { Dictionary(uniqueKeysWithValues: copy.tabs.map { ($0.id, $0.savedURL) }) }

        func documents(_ copy: SidebarItemsCopy) -> [UUID: SidebarDocumentReference] { copy.tabs.contains { $0.id == note.id } ? noteDocs : [:] }

        func can(_ items: [SidebarItemReference], _ destination: SidebarContainerLocation, before: SidebarItemReference? = nil) -> Bool {
            guard let made = copy(items) else { return false }
            return store.canCopySidebarItems(made, to: destination, before: before, destinations: sources(made), documents: documents(made))
        }

        func place(_ items: [SidebarItemReference], _ destination: SidebarContainerLocation,
                   before: SidebarItemReference? = nil) throws -> SidebarDuplicateResult {
            let made = try #require(copy(items))
            return try #require(try store.copySidebarItems(made, to: destination, before: before, destinations: sources(made), documents: documents(made)))
        }

        func children(_ location: SidebarContainerLocation) -> [SidebarItemReference] { SidebarHierarchy.children(in: location, state: store.state) }

        func folderLocation(_ id: UUID, space: UUID? = nil) -> SidebarContainerLocation {
            .init(spaceID: space ?? here.id, folderID: id, section: .pinned)
        }
    }

    @Test func optionDragCopiesTabsFoldersAndMixedSelectionsButOnlyAllSplitDragsAreWholeSplits() throws {
        let i = try Items()
        #expect(i.copy([.tab(i.loose.id)])?.wholeSplits == false)
        #expect(i.copy([.folder(i.outer.id)])?.wholeSplits == false)
        #expect(i.copy([.tab(i.loose.id), .folder(i.outer.id), .split(i.rootSplit.id)])?.wholeSplits == false)
        #expect(i.copy([.split(i.rootSplit.id)])?.wholeSplits == true)
    }

    @Test func aSingleSplitChildIsNeverCopiedOutOfItsSplit() throws {
        let i = try Items()
        #expect(i.copy([.tab(i.pairA.id)]) == nil)
    }

    @Test func aTabCopiedOntoTodayLandsWhereItWasDroppedAsAFreshTodayTabAndOpensInTheBackground() throws {
        let i = try Items()
        let looseCopy = try i.place([.tab(i.loose.id)], i.todayLocation, before: .tab(i.today.id))
        guard case .tab(let todayCopy)? = looseCopy.roots.first else { Issue.record("tab copy root"); return }
        #expect(i.children(i.todayLocation) == [.tab(todayCopy), .tab(i.today.id)])
        #expect(i.store.state.tab(todayCopy).map { $0.kind == .today && $0.savedURL == i.loose.savedURL && $0.id != i.loose.id } == true)
        #expect(i.store.state.tab(i.loose.id) == i.initial.tab(i.loose.id))
        #expect(SidebarHierarchy.children(in: i.pinned, state: i.store.state) == SidebarHierarchy.children(in: i.pinned, state: i.initial))
        #expect(looseCopy.openTabIDs == [todayCopy])
    }

    @Test func theSpaceHeaderDropsTheCopyAtTheTopOfPinnedAboveItsOriginal() throws {
        let i = try Items()
        let headerCopy = try i.place([.tab(i.loose.id)], i.pinned, before: .tab(i.loose.id))
        #expect(Array(i.children(i.pinned).prefix(2)) == [headerCopy.roots[0], .tab(i.loose.id)])
    }

    @Test func aFolderCopiedOntoAnotherFolderNestsInsideItWithTheSameNameAndKeepsTheOriginalContents() throws {
        let i = try Items()
        let folderCopy = try i.place([.folder(i.outer.id)], i.targetLocation)
        guard case .folder(let outerCopy)? = folderCopy.roots.first, let copiedOuter = i.store.state.folders.first(where: { $0.id == outerCopy }) else {
            Issue.record("folder copy root")
            return
        }
        #expect(i.children(i.targetLocation) == [.folder(outerCopy)])
        #expect(copiedOuter.parentID == i.target.id)
        #expect(copiedOuter.name == i.outer.name)
        #expect(SidebarHierarchy.children(in: i.outerLocation, state: i.store.state) == SidebarHierarchy.children(in: i.outerLocation, state: i.initial))
        #expect(i.store.state.folders.first { $0.id == i.outer.id } == i.outer)
        #expect(folderCopy.tabIDs.count == 4)
        #expect(folderCopy.openTabIDs.isEmpty)
    }

    @Test func nestedFoldersTabsAndSplitsAreFreshCopiesThatKeepOrderAndDisclosure() throws {
        let i = try Items()
        let folderCopy = try i.place([.folder(i.outer.id)], i.targetLocation)
        guard case .folder(let outerCopy)? = folderCopy.roots.first else { Issue.record("folder copy root"); return }
        let outerChildren = i.children(i.folderLocation(outerCopy))
        guard outerChildren.count == 2, case .folder(let nestedCopy) = outerChildren[0], case .tab(let inOuterCopy) = outerChildren[1] else {
            Issue.record("nested copy")
            return
        }
        #expect(nestedCopy != i.nested.id)
        #expect(inOuterCopy != i.inOuter.id)
        #expect(i.store.state.folders.first { $0.id == nestedCopy }?.isExpanded == false)
        let nestedChildren = i.children(i.folderLocation(nestedCopy))
        guard nestedChildren.count == 2, case .split(let nestedSplitCopy) = nestedChildren[1],
              let copiedSplit = i.store.state.splitLayouts.first(where: { $0.id == nestedSplitCopy }) else { Issue.record("nested split copy"); return }
        #expect(copiedSplit.tabIDs.allSatisfy { id in i.store.state.tab(id)?.folderID == nestedCopy })
        #expect(Set(copiedSplit.tabIDs).isDisjoint(with: i.nestedSplit.tabIDs))
    }

    @Test func foldersCannotBeCopiedIntoTodayOrTheFavoritesTray() throws {
        let i = try Items()
        #expect(!i.can([.folder(i.outer.id)], i.todayLocation))
        #expect(!i.can([.folder(i.outer.id)], i.favorites))
    }

    @Test func aMixedSelectionLandsTogetherInOriginalOrderKeepingItsSplitAndOpeningOnlyTopLevelPages() throws {
        let i = try Items()
        let mixed = try i.place([.tab(i.loose.id), .folder(i.outer.id), .split(i.rootSplit.id)], i.targetLocation)
        #expect(mixed.roots.count == 3)
        #expect(Array(i.children(i.targetLocation).suffix(3)) == mixed.roots)
        guard case .split(let mixedSplit) = mixed.roots[2], let mixedGroup = i.store.state.splitLayouts.first(where: { $0.id == mixedSplit }) else {
            Issue.record("mixed split")
            return
        }
        #expect(mixedGroup.customTitle == i.rootSplit.customTitle)
        #expect(mixedGroup.widthFactors == i.rootSplit.widthFactors)
        #expect(mixed.openTabIDs.count == 3)
        #expect(mixed.openTabIDs.allSatisfy(mixed.tabIDs.contains))
    }

    @Test func aFavoriteTileCopiesIntoPinnedAndStaysInTheTray() throws {
        let i = try Items()
        let outOfTray = try i.place([.tab(i.favorite.id)], i.pinned)
        guard case .tab(let favoriteCopy)? = outOfTray.roots.first else { Issue.record("favorite copy"); return }
        #expect(i.store.state.tab(favoriteCopy).map { $0.kind == .pinned && $0.spaceID == i.here.id } == true)
        #expect(i.children(i.favorites) == [.tab(i.favorite.id)])
    }

    @Test func aTabCopiedOntoTheTrayBecomesAFavoriteBeforeItsTargetAndAFavoriteCopiedWithinAddsATile() throws {
        let i = try Items()
        let intoTray = try i.place([.tab(i.loose.id)], i.favorites, before: .tab(i.favorite.id))
        #expect(i.children(i.favorites) == [intoTray.roots[0], .tab(i.favorite.id)])
        #expect(i.store.state.tab(intoTray.tabIDs[0])?.kind == .favorite)
        let withinTray = try i.place([.tab(i.favorite.id)], i.favorites)
        #expect(i.children(i.favorites).last == withinTray.roots[0])
        #expect(i.children(i.favorites).count == 3)
    }

    @Test func aDockDropCopiesIntoAnotherSpaceThatSharesDataFoldersAndAll() throws {
        let i = try Items()
        let away = try i.place([.tab(i.loose.id), .folder(i.outer.id)], i.therePinned)
        guard case .folder(let awayFolder) = away.roots[1] else { Issue.record("space copy"); return }
        #expect(Array(i.children(i.therePinned).suffix(2)) == away.roots)
        #expect(away.tabIDs.allSatisfy { i.store.state.tab($0)?.spaceID == i.there.id })
        #expect(i.store.state.folders.filter { $0.spaceID == i.there.id }.count == 2)
        #expect(i.store.state.folders.first { $0.id == awayFolder }?.spaceID == i.there.id)
        #expect(i.children(i.pinned).contains(.tab(i.loose.id)))
        #expect(i.children(i.pinned).contains(.folder(i.outer.id)))
    }

    @Test func tabsFoldersAndMixedSelectionsNeverCopyIntoASpaceThatKeepsSeparateDataButWholeWebSplitsDo() throws {
        let i = try Items()
        #expect(!i.can([.tab(i.loose.id)], i.elsewherePinned))
        #expect(!i.can([.folder(i.outer.id)], i.elsewherePinned))
        #expect(!i.can([.tab(i.loose.id), .split(i.rootSplit.id)], i.elsewherePinned))
        #expect(i.can([.split(i.rootSplit.id)], i.elsewherePinned))
    }

    @Test func aCopiedNoteIsANewEntryForTheSameDocumentAndNeedsItsValidatedDocument() throws {
        let i = try Items()
        let noteCopy = try i.place([.tab(i.note.id)], i.targetLocation)
        #expect(i.store.state.tab(noteCopy.tabIDs[0]).map { $0.savedURL == i.note.savedURL && $0.id != i.note.id } == true)
        #expect(noteCopy.openTabIDs.isEmpty)
        let noteOnly = try #require(i.copy([.tab(i.note.id)]))
        #expect(!i.store.canCopySidebarItems(noteOnly, to: i.targetLocation, before: nil, destinations: i.sources(noteOnly), documents: [:]))
    }

    @Test func aFolderThatMovedDuringTheDragNoLongerMatchesTheGesture() throws {
        let i = try Items()
        let nestedOnly = try #require(i.copy([.folder(i.nested.id)]))
        var reparented = i.store.state
        reparented.folders[reparented.folders.firstIndex { $0.id == i.nested.id }!].parentID = i.target.id
        reparented.sidebarItemOrder[i.outerLocation.key] = [.tab(i.inOuter.id)]
        #expect(SidebarItemsCopy(items: [.folder(i.nested.id)], spaceID: i.here.id, profileID: i.profile.id, state: reparented)?.matchesPlacement(of: nestedOnly) == false)
    }

    @Test func aFolderWhosePageIsClosingRefusesTheCopy() throws {
        let i = try Items()
        var pending: ((Bool) -> Void)?
        i.store.requestPageRetirement = { _, _, done in pending = done }
        i.store.closeTabs([i.inOuter.id]) { _ in }
        #expect(!i.can([.folder(i.outer.id)], i.targetLocation))
        pending?(false)
        i.store.requestPageRetirement = nil
    }

    @Test func aBigCopyOpensOnlyTheFirstFiveItemsAndStaysSaved() throws {
        let i = try Items()
        var bulk = i.initial
        var bulkRoots: [SidebarItemReference] = []
        func tab(_ title: String) -> BrowserTab {
            BrowserTab(id: UUID(), spaceID: i.here.id, profileID: i.profile.id, url: "https://saved.invalid/" + title, title: title,
                kind: .pinned, createdAt: Date(timeIntervalSince1970: 10), lastAccessed: Date(timeIntervalSince1970: 10),
                savedURL: "https://saved.invalid/" + title, savedTitle: title)
        }
        for index in 0..<6 {
            let a = tab("SplitA\(index)"), b = tab("SplitB\(index)")
            bulk.tabs += [a, b]
            bulk.splitLayouts.append(BrowserSplitLayout(sidebarAnchorID: a.id, spaceID: i.here.id, tabIDs: [a.id, b.id], widthFactors: [0.5, 0.5]))
            bulkRoots.append(.split(bulk.splitLayouts.last!.id))
        }
        for index in 0..<3 {
            let extra = tab("Extra\(index)")
            bulk.tabs.append(extra)
            bulkRoots.append(.tab(extra.id))
        }
        let bulkRoot = i.root.appendingPathComponent("Bulk-" + UUID().uuidString)
        try Self.write(bulk, to: bulkRoot)
        let bulkStore = try BrowserStore(directory: bulkRoot)
        let many = try #require(SidebarItemsCopy(items: bulkRoots, spaceID: i.here.id, profileID: i.profile.id, state: bulkStore.state))
        let result = try #require(try bulkStore.copySidebarItems(many, to: i.todayLocation, before: nil, destinations: i.sources(many)))
        #expect(result.tabIDs.count == 15)
        #expect(result.openTabIDs.count == 10)
    }

    @Test func everyOptionDragCopyIsSaved() throws {
        let i = try Items()
        let looseCopy = try i.place([.tab(i.loose.id)], i.todayLocation, before: .tab(i.today.id))
        let folderCopy = try i.place([.folder(i.outer.id)], i.targetLocation)
        let mixed = try i.place([.tab(i.loose.id), .folder(i.outer.id), .split(i.rootSplit.id)], i.targetLocation)
        let away = try i.place([.tab(i.loose.id), .folder(i.outer.id)], i.therePinned)
        let noteCopy = try i.place([.tab(i.note.id)], i.targetLocation)
        let reload = try BrowserStore(directory: i.root)
        #expect((looseCopy.tabIDs + folderCopy.tabIDs + mixed.tabIDs + away.tabIDs + noteCopy.tabIDs).allSatisfy { reload.state.tab($0) != nil })
    }
}
