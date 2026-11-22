import Foundation
import Testing
@testable import ParcCore

extension SidebarSplitCopyTestsSupport {
    @MainActor
    struct SidebarSplitCopyAdmissionTests {
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
            try SidebarSplitCopyTestsSupport.write(full, to: fullRoot)
            return (try BrowserStore(directory: fullRoot), full)
        }

        @Test func refusingTheLeavePagePromptPublishesNoCopy() throws {
            let f = try Fixture()
            let store = f.store
            var retired: Set<UUID> = []
            let consent = false
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
        }

        @Test func consentRetiresExactlyTheOriginalPagesAndPublishesTheCopy() throws {
            let f = try Fixture()
            let store = f.store
            var retired: Set<UUID> = []
            let consent = true
            store.requestPageRetirement = { ids, shouldCommit, done in
                retired = ids
                done(consent && shouldCommit())
            }
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
            try SidebarSplitCopyTestsSupport.write(withNote, to: noteRoot)
            let noteStore = try BrowserStore(directory: noteRoot, now: { Date(timeIntervalSince1970: 1000) })
            let noteCopy = try #require(SidebarItemsCopy(items: [.split(noteSplit.id)], spaceID: f.here.id, profileID: f.profile.id, state: noteStore.state))
            let noteDocs = [typedNote.id: SidebarDocumentReference(page: .note(noteID), profileID: f.profile.id) {}]
            let noteURLs = [typedNote.id: typedNote.savedURL, web.id: "https://live.invalid/web"]
            #expect(noteStore.canCopySidebarItems(noteCopy, to: f.elsewherePinned, before: nil, destinations: noteURLs, documents: noteDocs))
            #expect(noteStore.canCopySidebarItems(noteCopy, to: f.pinned, before: nil, destinations: noteURLs, documents: noteDocs))
        }

        @Test func aStaleCopyGestureUsesTheCurrentTabMetadata() throws {
            let f = try Fixture()
            let store = f.store
            let stale = f.copyOfSplit()
            store.updateTab(f.left.id, title: "Renamed while deciding", url: "https://live.invalid/moved-on")
            _ = store.open("https://unrelated.invalid/", kind: .today)
            let staleResult = try store.copySidebarItems(stale, to: f.pinned, before: nil, destinations: f.urls)
            guard case .split(let staleID)? = staleResult?.roots.first else { Issue.record("stale copy"); return }
            #expect(store.state.tabs.first { $0.id == store.state.splitLayouts.first { $0.id == staleID }!.tabIDs[0] }?.savedTitle
                    == store.state.tabs.first { $0.id == f.left.id }?.savedTitle)
        }

        @Test func aMovedChildNoLongerMatchesTheCopyGesture() throws {
            let f = try Fixture()
            let store = f.store
            let stale = f.copyOfSplit()
            store.updateTab(f.left.id, title: "Renamed while deciding", url: "https://live.invalid/moved-on")
            _ = store.open("https://unrelated.invalid/", kind: .today)
            _ = try store.copySidebarItems(stale, to: f.pinned, before: nil, destinations: f.urls)
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

        @Test func aRetiringChildRefusesASplitCopy() throws {
            let f = try Fixture()
            let store = f.store
            var pendingDone: ((Bool) -> Void)?
            store.requestPageRetirement = { _, _, done in pendingDone = done }
            store.closeTabs([f.right.id]) { _ in }
            let retiringCopy = f.copyOfSplit()
            #expect(!store.canCopySidebarItems(retiringCopy, to: f.pinned, before: nil, destinations: f.urls))
            pendingDone?(false)
            store.requestPageRetirement = nil
        }

        @Test func anEphemeralStoreRefusesASplitCopy() throws {
            let f = try Fixture()
            let retiringCopy = f.copyOfSplit()
            let ephemeral = BrowserStore(privateParentProfileID: f.profile.id, engineProfilePath: "/nonexistent", directory: f.root, settings: BrowserSettings())
            #expect(!ephemeral.canCopySidebarItems(retiringCopy, to: f.pinned, before: nil, destinations: f.urls))
        }

        @Test func anArchivedChildRefusesASplitCopy() throws {
            let f = try Fixture()
            let store = f.store
            var archived = store.state
            if let index = archived.tabs.firstIndex(where: { $0.id == f.right.id }) { archived.tabs[index].archivedAt = Date(timeIntervalSince1970: 5) }
            #expect(SidebarItemsCopy(items: [.split(f.split.id)], spaceID: f.here.id, profileID: f.profile.id, state: archived) == nil)
        }

        @Test func aRemovingProfileRefusesAnInterProfileSplitCopy() throws {
            let f = try Fixture()
            let store = f.store
            var removing = store.state
            removing.profileRemovals = [ProfileRemovalRecord(id: UUID(), profileID: f.foreignProfile.id, profileName: f.foreignProfile.name)]
            #expect(!InterProfileMove.profilesAvailable(f.profile.id, f.foreignProfile.id, in: removing))
            #expect(SidebarWindowMove(items: [.split(f.split.id)], sourceSpaceID: f.here.id, profileID: f.profile.id,
                                      destinationProfileID: f.foreignProfile.id, to: f.elsewherePinned, before: nil, state: removing) == nil)
        }

        @Test func aFullTrayRefusesASplitCopiedIntoIt() throws {
            let f = try Fixture()
            let (fullStore, full) = try fullTray(f)
            #expect(SidebarHierarchy.children(in: f.favorites, state: fullStore.state).count == 12)
            let intoFull = SidebarItemsCopy(items: [.split(f.split.id)], spaceID: f.here.id, profileID: f.profile.id, state: fullStore.state)!
            #expect(!fullStore.canCopySidebarItems(intoFull, to: f.favorites, before: nil, destinations: f.urls))
            #expect(try fullStore.copySidebarItems(intoFull, to: f.favorites, before: nil, destinations: f.urls) == nil)
            #expect(fullStore.state.tabs.count == full.tabs.count)
        }

        @Test func aFullTrayRefusesACopyWithinIt() throws {
            let f = try Fixture()
            let (fullStore, _) = try fullTray(f)
            let withinFull = SidebarItemsCopy(items: [.split(f.favorite.id)], spaceID: f.here.id, profileID: f.profile.id, state: fullStore.state)!
            #expect(!fullStore.canCopySidebarItems(withinFull, to: f.favorites, before: nil, destinations: f.favURLs))
        }

        @Test func aFullTrayAllowsAFavoriteSplitToBeCopiedOut() throws {
            let f = try Fixture()
            let (fullStore, _) = try fullTray(f)
            let withinFull = SidebarItemsCopy(items: [.split(f.favorite.id)], spaceID: f.here.id, profileID: f.profile.id, state: fullStore.state)!
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
            try SidebarSplitCopyTestsSupport.write(multi, to: multiRoot)
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

        enum CopyDestination: CaseIterable {
            case pinned, favorites
        }

        @Test(arguments: CopyDestination.allCases)
        func everyPlacedCopyReloadsDurably(_ destination: CopyDestination) throws {
            let f = try Fixture()
            let first = try #require(try f.store.copySidebarItems(f.target, to: f.pinned, before: .tab(f.keep.id), destinations: f.urls))
            let tray = try #require(try f.store.copySidebarItems(f.copyOfSplit(), to: f.favorites, before: nil, destinations: f.urls))
            let reload = try BrowserStore(directory: f.root)
            let result = destination == .pinned ? first : tray
            guard case .split(let id)? = result.roots.first else { Issue.record("root"); return }
            #expect(reload.state.splitLayouts.contains { $0.id == id })
        }
    }
}
