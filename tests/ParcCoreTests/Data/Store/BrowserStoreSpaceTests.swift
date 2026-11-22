import Combine
import Foundation
import Testing
@testable import ParcCore

struct BrowserStoreSpaceTests {
    @Test @MainActor static func spacesShareOnlyFavoritesWithinAProfile() throws {
        try BrowserStoreTests.withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let favorite = store.open("https://favorite.example.org", kind: .favorite)
            _ = store.open("https://pinned.example.org", kind: .pinned)
            _ = store.open("https://today.example.org")
            _ = store.createSpace(name: "Second")
            #expect(store.visibleTabs.map(\.id) == [favorite], "Favorites are shared by Spaces using a profile; pinned and Today tabs are Space-local")
        }
    }

    @Test @MainActor static func switchingSpacesRestoresEachSelection() throws {
        try BrowserStoreTests.withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let firstSpace = store.activeSpaceID
            let today = store.open("https://today.example.org")
            let secondSpace = store.createSpace(name: "Second")
            let second = store.open("https://second.example.org")
            store.selectSpace(firstSpace)
            #expect(store.selectedTabID == today, "Returning to a Space must restore its own selection")
            store.selectSpace(secondSpace)
            #expect(store.selectedTabID == second, "Each Space must retain its own selection")
        }
    }

    @Test @MainActor static func assigningAProfileIsolatesFavoritesAndEngineStorage() throws {
        try BrowserStoreTests.withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let favorite = store.open("https://favorite.example.org", kind: .favorite)
            let pinned = store.open("https://pinned.example.org", kind: .pinned)
            let secondSpace = store.createSpace(name: "Second")
            let second = store.open("https://second.example.org")
            let profile = store.createProfile(name: "Independent")
            store.assignProfile(profile, toSpace: secondSpace)
            #expect(!store.visibleTabs.contains { $0.id == favorite }, "A favorite must not leak into a different profile")
            let firstTab = try BrowserStoreTests.tab(pinned, in: store)
            let secondTab = try BrowserStoreTests.tab(second, in: store)
            #expect(secondTab.profileID == profile, "Assigning a Space profile must update its ordinary tabs")
            #expect(store.profilePath(for: firstTab) != store.profilePath(for: secondTab), "Independent profiles must use separate engine storage directories")
            #expect(store.profilePath(for: secondTab).hasPrefix(directory.path + "/Profiles/"), "Engine profile storage must remain beneath the isolated application directory")
            try BrowserStoreTests.expectValidSelection(store)
        }
    }

    @Test @MainActor static func movingASelectedTabAcrossProfilesClearsTheSourceSelection() throws {
        try BrowserStoreTests.withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let firstSpace = store.activeSpaceID
            let today = store.open("https://today.example.org")
            let secondSpace = store.createSpace(name: "Second")
            let profile = store.createProfile(name: "Independent")
            store.assignProfile(profile, toSpace: secondSpace)
            store.selectSpace(firstSpace)
            store.selectTab(today)
            store.moveTab(today, toSpace: secondSpace)
            #expect(!store.state.selectedTabIDs.contains(today), "Moving the selected tab out of a Space must remove it from that Space's selection")
            #expect(try BrowserStoreTests.tab(today, in: store).profileID == profile, "A cross-Space move must adopt the destination profile")
            try BrowserStoreTests.expectValidSelection(store)
        }
    }

    @MainActor
    private static func withFreshSession(
        _ body: (BrowserStore, BrowserState, Date) throws -> Void
    ) throws {
        try BrowserStoreTests.withDirectory { directory in
            var now = Date(timeIntervalSince1970: 1_800_000_000)
            let store = try BrowserStore(directory: directory, now: { now })
            let firstSpace = store.activeSpaceID
            let pinned = store.open("https://saved.example.org", kind: .pinned)
            let folder = store.createFolder(name: "Saved work")
            store.moveTab(pinned, toSpace: firstSpace, folderID: folder)
            store.updateTab(pinned, title: "Navigated pin", url: "https://saved.example.org/other")
            let favorite = store.open("https://favorite.example.org", kind: .favorite)
            store.updateTab(favorite, title: "Navigated favorite", url: "https://favorite.example.org/other")
            _ = store.open("https://first.example.org")
            let alreadyArchived = store.open("https://archived.example.org")
            store.closeTab(alreadyArchived)
            let otherSpace = store.createSpace(name: "Work")
            let otherProfile = store.createProfile(name: "Work")
            store.assignProfile(otherProfile, toSpace: otherSpace)
            let otherToday = store.open("https://work.example.org")
            let otherPin = store.open("https://work-saved.example.org", kind: .pinned)
            store.updateTab(otherPin, title: "Work article", url: "https://work-saved.example.org/article")
            store.setSplit([otherToday, otherPin])
            store.recordDownload(["id": "existing-download", "name": "notes.pdf", "isComplete": true])
            store.updateSettings { $0.restoreSession = false; $0.onboardingComplete = true }
            try store.save()
            let saved = store.state

            now.addTimeInterval(3600)
            let reopened = try BrowserStore(directory: directory, now: { now })
            try body(reopened, saved, now)
        }
    }

    @Test @MainActor static func aFreshSessionClearsAllSelectionsAndSplitLayouts() throws {
        try withFreshSession { reopened, _, _ in
            #expect(reopened.state.selectedTabIDs.isEmpty && reopened.state.selectionBySpace.isEmpty, "Disabling session restore must start with no selected page or remembered split in any Space")
            #expect(reopened.state.splitLayouts.isEmpty, "A fresh session must discard its prior split layout")
        }
    }

    @Test @MainActor static func aFreshSessionArchivesLiveTodayTabsAndPreservesExistingArchiveEntries() throws {
        try withFreshSession { reopened, saved, now in
            let liveToday = saved.tabs.filter { $0.kind == .today && $0.archivedAt == nil }
            try #require(liveToday.count == 3)
            #expect(reopened.state.tabs.filter { $0.kind == .today && $0.archivedAt == nil }.isEmpty, "A fresh launch must archive Today tabs across all Spaces and profiles")
            let archivedAtLaunch = try liveToday.map { try BrowserStoreTests.tab($0.id, in: reopened).archivedAt }
            #expect(archivedAtLaunch == Array(repeating: now, count: liveToday.count))
            let oldArchive = try #require(saved.tabs.first { $0.archivedAt != nil })
            #expect(try BrowserStoreTests.tab(oldArchive.id, in: reopened) == oldArchive)
            #expect(Set(reopened.state.recentlyClosedIDs).count == reopened.state.recentlyClosedIDs.count, "Fresh-launch archiving must not duplicate recovery entries")
        }
    }

    @Test @MainActor static func aFreshSessionResetsSavedDestinationsWithoutRemovingThem() throws {
        try withFreshSession { reopened, saved, _ in
            let savedTabs = saved.tabs.filter { $0.kind == .pinned || $0.kind == .favorite }
            try #require(savedTabs.count == 3)
            let reopenedTabs = try savedTabs.map { try BrowserStoreTests.tab($0.id, in: reopened) }
            #expect(reopenedTabs.allSatisfy { $0.archivedAt == nil && $0.url == $0.savedURL && $0.title == $0.savedTitle })
        }
    }

    @Test @MainActor static func startingFreshPreservesSpacesProfilesHistoryAndPreferences() throws {
        try withFreshSession { reopened, saved, _ in
            #expect(reopened.state.profiles == saved.profiles && reopened.state.spaces == saved.spaces
                       && reopened.state.folders == saved.folders && reopened.activeSpaceID == saved.activeSpaceID, "A fresh launch must preserve the user's profiles, Spaces, folders, and active Space")
            #expect(reopened.state.history == saved.history && reopened.state.downloads == saved.downloads
                       && reopened.state.settings == saved.settings, "Starting fresh must not clear history, download records, or preferences")
        }
    }

    @Test @MainActor static func relaunchingAnAlreadyNormalizedSessionDoesNotRewriteIt() throws {
        try withFreshSession { reopened, _, now in
            let fresh = reopened.state
            let file = reopened.directory.appendingPathComponent("session.json")
            let data = try Data(contentsOf: file)
            let oldModificationDate = Date(timeIntervalSince1970: 1_700_000_000)
            try FileManager.default.setAttributes([.modificationDate: oldModificationDate], ofItemAtPath: file.path)

            let openedAgain = try BrowserStore(directory: reopened.directory, now: { now.addingTimeInterval(3_600) })
            #expect(openedAgain.state == fresh, "A second fresh launch must be idempotent")
            #expect(try Data(contentsOf: file) == data, "Fresh-launch normalization must be persisted before another store reads it")
            let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
            #expect(attributes[.modificationDate] as? Date == oldModificationDate, "An already normalized fresh session must not rewrite its state file")
        }
    }

    @Test @MainActor static func putBackRecoversATabArchivedAtFreshLaunch() throws {
        try withFreshSession { reopened, saved, _ in
            let otherToday = try #require(saved.tabs.first { $0.url == "https://work.example.org" }?.id)
            reopened.restoreArchivedTab(otherToday, destination: .previousSpace(fallbackSpaceID: reopened.activeSpaceID))
            #expect(try reopened.selectedTabID == otherToday && (try BrowserStoreTests.tab(otherToday, in: reopened)).archivedAt == nil, "Archive restoration recovers a tab archived by the fresh-launch preference")
            try BrowserStoreTests.expectValidSelection(reopened)
        }
    }

    @Test @MainActor static func aPinnedOriginalJoinsANewTodaySplit() throws {
        try BrowserStoreTests.withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let today = store.open("https://work.example.org")
            let pinned = store.open("https://work-saved.example.org", kind: .pinned)
            store.setSplit([today, pinned])
            #expect(try BrowserStoreTests.tab(pinned, in: store).kind == .today)
        }
    }

    @Test @MainActor static func changingRestorePreferenceDoesNotCloseCurrentTabs() throws {
        try BrowserStoreTests.withDirectory { directory in
            let date = Date(timeIntervalSince1970: 1_800_000_000)
            let store = try BrowserStore(directory: directory, now: { date })
            let tabID = store.open("https://current.example.org")
            store.updateSettings { $0.restoreSession = false }
            #expect(try store.selectedTabID == tabID && (try BrowserStoreTests.tab(tabID, in: store)).archivedAt == nil, "Changing the startup preference must not close tabs during the current session")
        }
    }

    @Test @MainActor static func reenablingRestoreKeepsCurrentTabsOnLaunch() throws {
        try BrowserStoreTests.withDirectory { directory in
            let date = Date(timeIntervalSince1970: 1_800_000_000)
            let store = try BrowserStore(directory: directory, now: { date })
            _ = store.open("https://current.example.org")
            store.updateSettings { $0.restoreSession = false }
            store.updateSettings { $0.restoreSession = true }
            try store.save()
            let expected = store.state
            let reopened = try BrowserStore(directory: directory)
            #expect(reopened.state == expected, "Re-enabling session restore before quitting must retain the current tabs on launch")
        }
    }

    @Test(arguments: [TabKind.today, .pinned, .favorite], [true, false])
    @MainActor static func autoArchiveOnlyExpiresUnselectedTodayTabs(_ kind: TabKind, _ selected: Bool) throws {
        try BrowserStoreTests.withDirectory { directory in
            var now = Date(timeIntervalSince1970: 1_800_000_000)
            let store = try BrowserStore(directory: directory, now: { now })
            store.setAutoArchiveInterval(.oneHour, for: store.activeSpace.profileID)
            store.archiveExpiredTabs()
            let candidate = store.open("https://candidate.example.org", kind: kind)
            if !selected { _ = store.open("https://active.example.org") }
            now.addTimeInterval(2 * 3600)
            store.archiveExpiredTabs()
            #expect(try BrowserStoreTests.tab(candidate, in: store).archivedAt == (kind == .today && !selected ? now : nil))
        }
    }

    @Test @MainActor static func closingAndReopeningTodayRestoresItsIdentityAndSelection() throws {
        try BrowserStoreTests.withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let selected = store.open("https://selected.example.org")
            store.closeTab(selected)
            #expect(try BrowserStoreTests.tab(selected, in: store).archivedAt != nil, "Closing Today must archive it")
            store.restoreArchivedTab(selected, destination: .previousSpace(fallbackSpaceID: store.activeSpaceID))
            #expect(try store.selectedTabID == selected && (try BrowserStoreTests.tab(selected, in: store)).archivedAt == nil, "Reopen closed tab must restore the same identity and select it")
            try BrowserStoreTests.expectValidSelection(store)
        }
    }

    @Test @MainActor static func neverDisablesAutomaticArchiving() throws {
        try BrowserStoreTests.withDirectory { directory in
            var now = Date(timeIntervalSince1970: 1_800_000_000)
            let store = try BrowserStore(directory: directory, now: { now })
            store.setAutoArchiveInterval(.never, for: store.activeSpace.profileID)
            let keep = store.open("https://never.example.org")
            _ = store.open("https://active.example.org")
            now.addTimeInterval(40 * 24 * 3600)
            store.archiveExpiredTabs()
            #expect(try BrowserStoreTests.tab(keep, in: store).archivedAt == nil, "Never must disable automatic archiving")
        }
    }

    @Test @MainActor static func formingASplitFiltersUnknownAndDuplicateMembers() throws {
        try BrowserStoreTests.withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let pinned = store.open("https://example.org/home", kind: .pinned)
            let today = store.open("https://example.org/today")
            store.setSplit([pinned, today, today, UUID()])
            #expect(store.state.selectedTabIDs == [pinned, today], "Splits must reject unknown or duplicate members")
        }
    }

    @Test @MainActor static func splittingANavigatedPinKeepsItsLivePageAndRestoresItsSavedHome() throws {
        try BrowserStoreTests.withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let pinned = store.open("https://example.org/home", kind: .pinned)
            let today = store.open("https://example.org/today")
            store.updateTab(pinned, title: "A different page", url: "https://example.org/other")
            store.setSplit([pinned, today, today, UUID()])
            let home = try BrowserStoreTests.expectHome(of: pinned, in: store, savedURL: "https://example.org/home")
            #expect(home.url == home.savedURL && home.title == home.savedTitle, "The pinned slot keeps a fresh home at its saved page and title")
            #expect(try BrowserStoreTests.tab(pinned, in: store).kind == .today && (try BrowserStoreTests.tab(pinned, in: store)).url == "https://example.org/other", "The original live page joins the Today split unchanged")
        }
    }

    @Test @MainActor static func closingASplitPaneSelectsTheSurvivingPane() throws {
        try BrowserStoreTests.withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let pinned = store.open("https://example.org/home", kind: .pinned)
            let today = store.open("https://example.org/today")
            store.setSplit([pinned, today, today, UUID()])
            store.closeTab(today)
            #expect(store.state.selectedTabIDs == [pinned], "Closing a split member must retain the surviving pane")
        }
    }

    @Test @MainActor static func closingAPreviouslyPinnedSplitPaneArchivesOnlyTheLiveOriginal() throws {
        try BrowserStoreTests.withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let pinned = store.open("https://example.org/home", kind: .pinned)
            let today = store.open("https://example.org/today")
            store.updateTab(pinned, title: "A different page", url: "https://example.org/other")
            store.setSplit([pinned, today, today, UUID()])
            let home = try BrowserStoreTests.expectHome(of: pinned, in: store, savedURL: "https://example.org/home")
            store.closeTab(today)
            store.closeTab(pinned)
            let kept = try BrowserStoreTests.tab(home.id, in: store)
            #expect(try BrowserStoreTests.tab(pinned, in: store).archivedAt != nil && kept.archivedAt == nil && kept.kind == .pinned
                       && kept.savedURL == home.savedURL && kept.folderID == home.folderID, "Closing the joined original archives it while its saved home stays pinned")
        }
    }

    @Test @MainActor static func closingASplitLayoutKeepsThePrimarySelectedAndDoesNotArchiveOtherPanes() throws {
        try BrowserStoreTests.withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let pinned = store.open("https://example.org/home", kind: .pinned)
            let today = store.open("https://example.org/today")
            store.setSplit([pinned, today])
            store.closeSplit()
            #expect(store.state.selectedTabIDs == [pinned], "Close Split must retain its primary tab")
            #expect(try BrowserStoreTests.tab(today, in: store).archivedAt == nil, "Closing a split layout must not archive its other tab")
        }
    }

    @Test @MainActor static func separatingTheFocusedPaneSelectsItWithoutArchivingItsSibling() throws {
        try BrowserStoreTests.withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let pinned = store.open("https://example.org/home", kind: .pinned)
            let today = store.open("https://example.org/today")
            store.setSplit([pinned, today])
            store.separateSplitPane(today)
            #expect(try store.state.selectedTabIDs == [today] && (try BrowserStoreTests.tab(pinned, in: store)).archivedAt == nil, "Separating the focused pane keeps that original selected and preserves its sibling")
            try BrowserStoreTests.expectValidSelection(store)
        }
    }

    @Test(arguments: [TabKind.pinned, .favorite])
    @MainActor static func closingLastSavedTabDoesNotReselectIt(kind: TabKind) throws {
        try BrowserStoreTests.withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let saved = store.open("https://saved.example.org", kind: kind)
            store.updateTab(saved, title: "Current article", url: "https://saved.example.org/article")
            store.closeTab(saved)
            #expect(store.state.selectedTabIDs.isEmpty, "Closing the only \(kind.rawValue) must leave the start view instead of selecting it again")
            #expect(store.visibleTabs.map(\.id) == [saved], "Closing a saved tab must keep its destination in the sidebar")
            let destination = try BrowserStoreTests.tab(saved, in: store)
            #expect(destination.archivedAt == nil && destination.url == destination.savedURL
                       && destination.title == destination.savedTitle, "Closing the last saved tab must reset its page without archiving or deleting it")
            store.selectTab(saved)
            #expect(store.selectedTabID == saved, "The saved destination must remain explicitly selectable after closing")
        }
    }

    @Test(arguments: [TabKind.pinned, .favorite]) @MainActor static func closingASavedTabSelectsAnAvailableNeighbor(kind: TabKind) throws {
        try BrowserStoreTests.withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let saved = store.open("https://saved.example.org", kind: kind)
            let other = store.open("https://other.example.org")
            store.selectTab(saved)
            store.closeTab(saved)
            #expect(store.selectedTabID == other, "Closing a selected saved tab must still select an available neighboring tab")
        }
    }

    @Test @MainActor static func placingATabInAFolderPinsItAndSiblingsCanBeReordered() throws {
        try BrowserStoreTests.withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let firstSpace = store.activeSpaceID
            let parent = store.createFolder(name: "Parent")
            let child = store.createFolder(name: "Child", parentID: parent)
            let first = store.open("https://one.example.org")
            let second = store.open("https://two.example.org")
            store.moveTab(first, toSpace: firstSpace, folderID: child)
            store.moveTab(second, toSpace: firstSpace, folderID: child)
            #expect(try BrowserStoreTests.tab(first, in: store).kind == .pinned, "Placing a tab in a folder must pin it")
            store.reorderTab(second, before: first)
            #expect(store.pinnedTabs.map(\.id) == [second, first], "Reordering folder siblings must preserve the requested order")
        }
    }

    @Test @MainActor static func putBackRebuildsADeletedNestedFolderUnderItsOriginalParent() throws {
        try BrowserStoreTests.withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let firstSpace = store.activeSpaceID
            let parent = store.createFolder(name: "Parent")
            let child = store.createFolder(name: "Child", parentID: parent)
            let first = store.open("https://one.example.org")
            store.moveTab(first, toSpace: firstSpace, folderID: child)
            let deletion = FolderRemovalTarget(folderID: child, spaceID: firstSpace, profileID: store.activeSpace.profileID, state: store.state)!
            var deleted = false
            store.deleteFolder(deletion, shouldCommit: { true }) { deleted = (try? $0.get()) == true }
            #expect(try deleted && (try BrowserStoreTests.tab(first, in: store)).archivedAt != nil && !store.state.folders.contains { $0.id == child }, "Deleting a nested folder archives its tabs instead of reparenting live pages")
            _ = store.restoreArchivedTab(first, profileID: store.activeSpace.profileID, destination: .previousSpace(fallbackSpaceID: firstSpace))
            #expect(try BrowserStoreTests.tab(first, in: store).folderID == child && store.state.folders.first { $0.id == child }?.parentID == parent, "Put Back rebuilds a deleted nested folder inside its surviving parent")
        }
    }

    @Test @MainActor static func putBackReturnsATabToItsSurvivingFolder() throws {
        try BrowserStoreTests.withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let firstSpace = store.activeSpaceID
            let parent = store.createFolder(name: "Parent")
            let kept = store.open("https://kept.example.org")
            store.moveTab(kept, toSpace: firstSpace, folderID: parent)
            let archiveKept = FolderRemovalTarget(items: [.tab(kept)], spaceID: firstSpace, profileID: store.activeSpace.profileID, state: store.state)!
            store.deleteFolder(archiveKept, shouldCommit: { true }) { _ in }
            #expect(try BrowserStoreTests.tab(kept, in: store).archivedAt != nil && store.state.folders.contains { $0.id == parent }, "Archiving a tab leaves its folder in place")
            _ = store.restoreArchivedTab(kept, profileID: store.activeSpace.profileID, destination: .previousSpace(fallbackSpaceID: firstSpace))
            #expect(try BrowserStoreTests.tab(kept, in: store).archivedAt == nil && (try BrowserStoreTests.tab(kept, in: store)).folderID == parent, "Put Back returns a tab archived from a folder to that folder")
        }
    }

    @Test @MainActor static func movingATabRejectsAForeignFolderButAcceptsTheDestinationSpacesFolder() throws {
        try BrowserStoreTests.withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let firstSpace = store.activeSpaceID
            let first = store.open("https://one.example.org")
            let otherSpace = store.createSpace(name: "Other")
            let foreignFolder = store.createFolder(name: "Other folder")
            let before = try BrowserStoreTests.tab(first, in: store)
            store.moveTab(first, toSpace: firstSpace, folderID: foreignFolder)
            #expect(try BrowserStoreTests.tab(first, in: store) == before, "A tab must reject a folder belonging to another Space")
            store.moveTab(first, toSpace: otherSpace, folderID: foreignFolder)
            #expect(try BrowserStoreTests.tab(first, in: store).folderID == foreignFolder, "A valid cross-Space folder move must succeed")
        }
    }

    @Test @MainActor static func aNewFolderCannotHaveAParentFromAnotherSpace() throws {
        try BrowserStoreTests.withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let parent = store.createFolder(name: "Parent")
            _ = store.createSpace(name: "Other")
            let foreignParent = store.createFolder(name: "Invalid parent", parentID: parent)
            #expect(store.folders.first { $0.id == foreignParent }?.parentID == nil, "Folder creation must not retain a parent from a different Space")
        }
    }

    @Test @MainActor static func unpinningATabDetachesItFromItsFolder() throws {
        try BrowserStoreTests.withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let firstSpace = store.activeSpaceID
            let parent = store.createFolder(name: "Parent")
            let child = store.createFolder(name: "Child", parentID: parent)
            let first = store.open("https://one.example.org")
            store.moveTab(first, toSpace: firstSpace, folderID: child)
            store.setKind(first, .today)
            #expect(try BrowserStoreTests.tab(first, in: store).folderID == nil, "Unpinning must detach the tab from its folder")
            try BrowserStoreTests.expectValidSelection(store)
        }
    }

    @Test @MainActor static func sidebarMovesPreserveMixedOrderingAndSplitMembership() throws {
        try BrowserStoreTests.withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let space = store.activeSpaceID, profile = store.activeSpace.profileID
            let root = SidebarContainerLocation(spaceID: space, folderID: nil, section: .pinned)
            let first = store.open("https://one.example.org", kind: .pinned)
            let second = store.open("https://two.example.org", kind: .pinned)
            let parent = store.createFolder(name: "Parent")
            let nested = store.createFolder(name: "Nested", parentID: parent)
            let peer = store.createFolder(name: "Peer")
            let today = store.open("https://today.example.org")
            @MainActor func snapshot() -> SidebarHierarchySnapshot { SidebarHierarchySnapshot(state: store.state, spaceID: space, profileID: profile)! }
            @MainActor func batchedMatches() -> Bool {
                let state = store.state, batched = SidebarHierarchy.childrenByContainer(spaceID: space, state: state)
                let locations = [root, SidebarContainerLocation(spaceID: space, folderID: nil, section: .today)]
                    + state.folders.filter { $0.spaceID == space }.map { SidebarContainerLocation(spaceID: space, folderID: $0.id, section: .pinned) }
                return locations.allSatisfy { (batched[$0.key] ?? []) == SidebarHierarchy.children(in: $0, state: state) }
            }
            #expect(SidebarHierarchy.children(in: root, state: store.state) == [.tab(first), .tab(second), .folder(parent), .folder(peer)], "Legacy sessions preserve their prior tab-then-folder order")
            #expect(batchedMatches(), "Every container's children match in one pass, legacy order")
            let original = store.state
            var publications = 0
            let observation = store.statePublisher.dropFirst().sink { _ in publications += 1 }
            #expect(try store.moveSidebarItem(.folder(peer), to: root, before: .tab(second), expected: snapshot()), "Folders reorder among tabs in a typed shared container")
            #expect(SidebarHierarchy.children(in: root, state: store.state) == [.tab(first), .folder(peer), .tab(second), .folder(parent)], "Mixed sibling insertion is exact")
            #expect(batchedMatches(), "Every container's children match in one pass, stored mixed order")
            #expect(publications == 1, "The complete move publishes once")
            #expect(store.state.tabs == original.tabs && store.state.selectedTabIDs == original.selectedTabIDs && store.state.history == original.history, "Reordering preserves original pages, selection and history metadata")
            let stale = snapshot()
            let inside = SidebarContainerLocation(spaceID: space, folderID: parent, section: .pinned)
            store.toggleFolder(parent)
            #expect(!(try store.moveSidebarItem(.tab(first), to: inside, before: nil, expected: stale)), "Changed hierarchy/disclosure rejects a stale capability")
            #expect(try store.moveSidebarItem(.tab(first), to: inside, before: .folder(nested), expected: snapshot()), "A tab nests before a folder without replacing either")
            #expect(store.state.folders.first { $0.id == parent }?.isExpanded == true, "A committed drop reveals its destination")
            #expect(SidebarHierarchy.children(in: inside, state: store.state) == [.tab(first), .folder(nested)], "Nested mixed order is durable")
            #expect(try store.moveSidebarItem(.tab(today), to: inside, before: .tab(first), expected: snapshot()), "Today can move into a genuine pinned folder")
            #expect(try BrowserStoreTests.tab(today, in: store).kind == .pinned && (try BrowserStoreTests.tab(today, in: store)).savedURL == "https://today.example.org", "Pinning retains the original live destination")
            #expect(try store.moveSidebarItem(.folder(nested), to: root, before: .folder(peer), expected: snapshot()), "A nested folder can move out to the root")
            #expect(store.state.folders.first { $0.id == nested }?.parentID == nil, "Outdent preserves folder identity")
            store.selectTab(first); store.selectTab(second, extendingSplit: true)
            let group = store.activeSplitLayout!
            let originalGroup = group
            let firstHome = try BrowserStoreTests.expectHome(of: first, in: store, savedURL: "https://one.example.org")
            #expect(SidebarHierarchy.children(in: inside, state: store.state) == [.tab(today), .tab(firstHome.id)], "The new Today split leaves the pinned child's fresh home in its folder slot")
            #expect(!(try store.moveSidebarItem(.tab(first), to: root, before: nil, expected: snapshot())), "A split child cannot silently detach through folder drag")
            #expect(try store.moveSidebarItem(.split(group.id), to: inside, before: .tab(today), expected: snapshot()), "The whole split is one movable sidebar item")
            #expect(store.activeSplitLayout == originalGroup && store.state.selectedTabIDs == originalGroup.tabIDs, "Moving preserves container identity, geometry and selected original pages")
            #expect(try BrowserStoreTests.tab(first, in: store).folderID == parent && (try BrowserStoreTests.tab(second, in: store)).folderID == parent, "All original split children move together")
            #expect(SidebarHierarchy.children(in: inside, state: store.state) == [.split(group.id), .tab(today), .tab(firstHome.id)], "Only the split container appears in the destination order")
            let groupState = store.state
            #expect(try store.moveSidebarItem(.folder(parent), to: .init(spaceID: space, folderID: peer, section: .pinned), before: nil, expected: snapshot()), "A folder subtree containing a split can nest")
            #expect(store.state.tabs == groupState.tabs && store.state.splitLayouts == groupState.splitLayouts, "Subtree nesting preserves every original child record")
            #expect(batchedMatches(), "Every container's children match in one pass, with stored order, nesting and a split")
            let loaded = try BrowserStore(directory: directory)
            #expect(loaded.state.sidebarItemOrder == store.state.sidebarItemOrder && loaded.state.folders == store.state.folders, "Hierarchy ordering and nesting survive reopening the model")
            observation.cancel()
        }
    }

    enum SidebarMoveDamage: CaseIterable {
        case ancestorCycle, selfParent, selfRelative, missingSibling, todayFolder, foreignSpace, missingFolder
    }


    @Test(arguments: SidebarMoveDamage.allCases) @MainActor static func invalidSidebarMovesLeaveTheHierarchyUnchanged(_ damage: SidebarMoveDamage) throws {
        try BrowserStoreTests.withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let space = store.activeSpaceID
            let parent = store.createFolder(name: "Parent")
            let child = store.createFolder(name: "Child", parentID: parent)
            let pinned = store.open("https://pin.example.org", kind: .pinned)
            let root = SidebarContainerLocation(spaceID: space, folderID: nil, section: .pinned)
            let move: (item: SidebarItemReference, destination: SidebarContainerLocation, before: SidebarItemReference?)
            switch damage {
            case .ancestorCycle:
                move = (.folder(parent), .init(spaceID: space, folderID: child, section: .pinned), nil)
            case .selfParent:
                move = (.folder(parent), .init(spaceID: space, folderID: parent, section: .pinned), nil)
            case .selfRelative:
                move = (.folder(parent), root, .folder(parent))
            case .missingSibling:
                move = (.folder(parent), root, .tab(UUID()))
            case .todayFolder:
                move = (.folder(parent), .init(spaceID: space, folderID: nil, section: .today), nil)
            case .foreignSpace:
                move = (.tab(pinned), .init(spaceID: UUID(), folderID: nil, section: .pinned), nil)
            case .missingFolder:
                move = (.tab(pinned), .init(spaceID: space, folderID: UUID(), section: .pinned), nil)
            }
            let original = store.state
            let snapshot = try #require(SidebarHierarchySnapshot(state: original, spaceID: space,
                profileID: store.activeSpace.profileID))
            #expect(!(try store.moveSidebarItem(move.item, to: move.destination, before: move.before, expected: snapshot)))
            #expect(store.state == original)
        }
    }

    @Test @MainActor static func hierarchySnapshotsRequireValidRelationshipsAndProfileOwnership() throws {
        try BrowserStoreTests.withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let space = store.activeSpaceID, profile = store.activeSpace.profileID
            let parent = store.createFolder(name: "Parent")
            var corrupted = store.state
            let index = corrupted.folders.firstIndex { $0.id == parent }!
            corrupted.folders[index].parentID = parent
            #expect(SidebarHierarchySnapshot(state: corrupted, spaceID: space, profileID: profile) == nil, "A malformed hierarchy cannot mint a capability")
            #expect(SidebarHierarchySnapshot(state: store.state, spaceID: space, profileID: UUID()) == nil, "Wrong-profile snapshots fail before preparing a move")
        }
    }

    @Test @MainActor static func aFailedSidebarMoveSaveDoesNotPublish() throws {
        try BrowserStoreTests.withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let space = store.activeSpaceID, profile = store.activeSpace.profileID
            let root = SidebarContainerLocation(spaceID: space, folderID: nil, section: .pinned)
            let parent = store.createFolder(name: "Parent")
            let nested = store.createFolder(name: "Nested", parentID: parent)
            let peer = store.createFolder(name: "Peer")
            @MainActor func snapshot() -> SidebarHierarchySnapshot { SidebarHierarchySnapshot(state: store.state, spaceID: space, profileID: profile)! }
            _ = try store.moveSidebarItem(.folder(nested), to: root, before: .folder(peer), expected: snapshot())
            let stable = store.state, snap = snapshot()
            let session = directory.appendingPathComponent("session.json"), backup = directory.appendingPathComponent("saved.json")
            try FileManager.default.moveItem(at: session, to: backup)
            try FileManager.default.createDirectory(at: session, withIntermediateDirectories: false)
            var failed = false
            do { _ = try store.moveSidebarItem(.folder(peer), to: root, before: .folder(nested), expected: snap) } catch { failed = true }
            #expect(failed && store.state == stable, "A failed disk commit cannot publish the move")
            try FileManager.default.removeItem(at: session); try FileManager.default.moveItem(at: backup, to: session)
        }
    }

    @Test @MainActor static func movingAnOrdinarySplitToTodayAppliesToEveryOriginalMember() throws {
        try BrowserStoreTests.withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let space = store.activeSpaceID, profile = store.activeSpace.profileID
            let first = store.open("https://one.example.org")
            let second = store.open("https://two.example.org")
            try BrowserStoreTests.savedSplit(store, [first, second], in: .init(spaceID: space, folderID: nil, section: .pinned))
            @MainActor func snapshot() -> SidebarHierarchySnapshot { SidebarHierarchySnapshot(state: store.state, spaceID: space, profileID: profile)! }
            let unsaved = store.open("https://split-today.example.org")
            store.selectTab(first); store.selectTab(unsaved, extendingSplit: true)
            let mixedGroup = store.activeSplitLayout!
            let originalIDs = Set(store.state.tabs.map(\.id))
            #expect(try store.moveSidebarItem(.split(mixedGroup.id),
                to: .init(spaceID: space, folderID: nil, section: .today), before: nil,
                expected: snapshot()), "A whole ordinary split moves even when its children retain different saved sections")
            #expect(store.activeSplitLayout == mixedGroup && Set(store.state.tabs.map(\.id)) == originalIDs, "Mixed-section move preserves the original group and every tab identity")
            #expect(store.state.tabs.filter { mixedGroup.tabIDs.contains($0.id) }.allSatisfy {
                $0.kind == .today && $0.folderID == nil
            }, "The explicit destination applies to every original member in one transaction")
        }
    }

    @Test @MainActor static func folderDisclosureOwnership() throws {
        try BrowserStoreTests.withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let space = store.activeSpaceID, profile = store.activeSpace.profileID
            let parent = store.createFolder(name: "Parent")
            let child = store.createFolder(name: "Child", parentID: parent)
            let saved = store.open("https://folder.example.org/selected")
            store.moveTab(saved, toSpace: space, folderID: child)
            store.toggleFolder(parent)
            let origin = store.state.folders.filter { $0.spaceID == space }
            let other = store.createSpace(name: "Other window")
            _ = store.createFolder(name: "Leave expanded")
            _ = store.open("https://other.example.org/current")
            let before = store.state
            var publications: [BrowserState] = []
            let observation = store.statePublisher.dropFirst().sink { publications.append($0) }
            #expect(try store.setFoldersExpanded(false, in: space, profileID: profile,
                                                    expectedFolders: origin), "Original Space remains an eligible disclosure owner")
            var expected = before
            for index in expected.folders.indices where expected.folders[index].spaceID == space {
                expected.folders[index].isExpanded = false
            }
            #expect(store.state == expected, "Collapse includes hidden descendants and changes no browsing state or foreign folder")
            #expect(publications == [expected], "Bulk collapse publishes only the complete folder change")
            #expect(store.activeSpaceID == other, "A folder command cannot steal another window's shared store context")
            let collapsed = store.state.folders.filter { $0.spaceID == space }
            #expect(try store.setFoldersExpanded(false, in: space, profileID: profile,
                                                    expectedFolders: collapsed), "Repeated matching disclosure is an idempotent success")
            #expect(publications.count == 1, "No-op disclosure does not publish again")
            #expect(!(try store.setFoldersExpanded(true, in: space, profileID: profile,
                                                       expectedFolders: origin)), "A stale folder snapshot cannot overwrite later disclosure")
            #expect(!(try store.setFoldersExpanded(true, in: space, profileID: UUID(),
                                                       expectedFolders: collapsed)), "Changed Profile ownership rejects before mutation")
            #expect(store.state == expected, "Rejected commands preserve the exact session")
            #expect(try store.setFoldersExpanded(true, in: space, profileID: profile,
                                                    expectedFolders: collapsed), "Expand restores all nested folder disclosure")
            for index in expected.folders.indices where expected.folders[index].spaceID == space {
                expected.folders[index].isExpanded = true
            }
            #expect(store.state == expected, "Expand leaves original tabs, selection, profiles and URL metadata unchanged")
            observation.cancel()
            let reopened = try BrowserStore(directory: directory)
            #expect(reopened.state.folders == expected.folders, "Bulk disclosure is durably saved before success")
        }
    }

    @Test @MainActor static func failedFolderDisclosureSaveLeavesEveryFolderUntouched() throws {
        try BrowserStoreTests.withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let space = store.activeSpaceID, profile = store.activeSpace.profileID
            let parent = store.createFolder(name: "Parent")
            let child = store.createFolder(name: "Child", parentID: parent)
            let saved = store.open("https://folder.example.org/selected")
            store.moveTab(saved, toSpace: space, folderID: child)
            store.toggleFolder(parent)
            let origin = store.state.folders.filter { $0.spaceID == space }
            let expected = store.state
            try store.save()
            let session = directory.appendingPathComponent("session.json")
            let backup = directory.appendingPathComponent("saved-session.json")
            try FileManager.default.moveItem(at: session, to: backup)
            try FileManager.default.createDirectory(at: session, withIntermediateDirectories: false)
            var writeFailed = false
            do {
                _ = try store.setFoldersExpanded(false, in: space, profileID: profile,
                    expectedFolders: origin)
            } catch { writeFailed = true }
            #expect(writeFailed && store.persistenceError != nil, "A refused atomic save reports the real failure")
            #expect(store.state == expected, "Failed persistence never publishes a folder change")
            try FileManager.default.removeItem(at: session)
            try FileManager.default.moveItem(at: backup, to: session)
        }
    }

    @Test @MainActor static func favoriteSelectionAfterProfileReassignment() throws {
        try BrowserStoreTests.withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let originalSpace = store.activeSpaceID
            let favorite = store.open("https://favorite.example.org", kind: .favorite)
            let sameProfileSpace = store.createSpace(name: "Same profile")
            let otherProfile = store.createProfile(name: "Other profile")
            store.assignProfile(otherProfile, toSpace: originalSpace)
            store.selectSpace(originalSpace)
            store.selectTab(favorite)
            #expect(store.activeSpaceID == sameProfileSpace, "Selecting a favorite after its origin Space changes profile must choose a Space using the favorite's profile")
            try BrowserStoreTests.expectValidSelection(store)
        }
    }

    enum RelationshipDamage: CaseIterable { case cycle, missingFolder, wrongProfile }

    @Test(arguments: RelationshipDamage.allCases)
    @MainActor static func invalidRelationshipsAreRejectedWithoutRewritingTheSession(_ damage: RelationshipDamage) throws {
        try BrowserStoreTests.withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            _ = store.open("https://example.org")
            let folder = store.createFolder(name: "Folder")
            let otherProfile = store.createProfile(name: "Other")
            var valid = store.state
            valid.settings.restoreSession = false
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let file = directory.appendingPathComponent("session.json")
            switch damage {
            case .cycle: valid.folders[0].parentID = folder
            case .missingFolder: valid.tabs[0].folderID = UUID()
            case .wrongProfile: valid.tabs[0].profileID = otherProfile
            }
            let data = try encoder.encode(valid)
            try data.write(to: file)
            #expect(throws: (any Error).self) { try BrowserStore(directory: directory) }
            #expect(try Data(contentsOf: file) == data)
        }
    }

    private static let bookmarks: [(title: String, url: String)] = [
        ("Already saved", "https://saved.example.org/start"),
        ("Research & notes", "https://new.example.org/research?q=stars#notes"),
        ("Duplicate in the same import", "https://new.example.org/research?q=stars#notes"),
        ("", "http://plain.example.org/reference"),
        ("Script", "javascript:alert(1)"),
        ("Data", "data:text/html,hello"),
        ("Local file", "file:///tmp/private.html"),
        ("Mail", "mailto:someone@example.org"),
        ("Internal", "about:blank"),
        ("Relative", "/not-an-absolute-web-address")
    ]

    @MainActor
    private static func withExistingSplit(_ body: (BrowserStore, BrowserState) throws -> Void) throws {
        try BrowserStoreTests.withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let existing = store.open("https://saved.example.org/start", kind: .pinned)
            store.updateTab(existing, title: "Current page", url: "https://saved.example.org/other")
            let current = store.open("https://current.example.org")
            store.updateTab(current, title: "Current", url: "https://current.example.org/article")
            store.setSplit([existing, current])
            try body(store, store.state)
        }
    }

    @Test @MainActor static func bookmarkImportCreatesOnlyDistinctWebDestinationsInTheActiveSpace() throws {
        try withExistingSplit { store, original in
            store.importBookmarks(bookmarks)
            let imported = store.state.tabs.filter { candidate in !original.tabs.contains { $0.id == candidate.id } }
            #expect(imported.count == 2, "Import must deduplicate saved destinations and batch duplicates, admitting only HTTP(S) bookmarks")
            #expect(imported.allSatisfy { $0.kind == .pinned && $0.archivedAt == nil && $0.folderID == nil }, "Imported bookmarks must become live saved destinations in the pinned section")
            #expect(imported.allSatisfy { $0.spaceID == store.activeSpaceID && $0.profileID == store.activeSpace.profileID }, "Imported bookmarks must belong to the active Space and its profile")
            #expect(imported.first?.savedTitle == "Research & notes"
                       && imported.first?.savedURL == "https://new.example.org/research?q=stars#notes", "Import must preserve supplied bookmark titles, query strings, and fragments")
            #expect(imported.last?.savedTitle == "plain.example.org", "An empty bookmark title must fall back to its host")
        }
    }

    @Test @MainActor static func bookmarkImportLeavesExistingTabsSelectionAndHistoryUntouched() throws {
        try withExistingSplit { store, original in
            store.importBookmarks(bookmarks)
            #expect(store.state.selectedTabIDs == original.selectedTabIDs, "Import must preserve the current tab and split selection")
            #expect(store.state.history == original.history, "Importing bookmarks must not create navigation history")
            #expect(Array(store.state.tabs.prefix(original.tabs.count)) == original.tabs, "Import must not navigate, retitle, or otherwise mutate existing tabs")
        }
    }

    @Test @MainActor static func importingTheSameBookmarksAgainIsIdempotent() throws {
        try withExistingSplit { store, original in
            store.importBookmarks(bookmarks)
            let firstImport = store.state.tabs
            store.importBookmarks(bookmarks)
            #expect(store.state.tabs == firstImport, "Importing the same bookmark file again must be idempotent")
            #expect(store.state.history == original.history && store.state.selectedTabIDs == original.selectedTabIDs, "A repeated import must also preserve history and selection")
        }
    }

    @Test @MainActor static func bookmarkImportIntoAnEmptySessionDoesNotNavigate() throws {
        try BrowserStoreTests.withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            store.importBookmarks([("First bookmark", "https://first.example.org")])
            #expect(store.state.selectedTabIDs.isEmpty, "Import into an empty session must not select or open the imported bookmark")
            #expect(store.state.history.isEmpty, "Import into an empty session must not create browsing history")
        }
    }

    @Test @MainActor static func namesColorsAndPreferencesRoundTrip() throws {
        try BrowserStoreTests.withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let originalSpace = store.activeSpaceID
            let originalProfile = store.activeSpace.profileID
            let otherProfile = store.createProfile(name: "Untouched")
            store.renameSpace(originalSpace, name: "Research — 夜空")
            store.renameProfile(originalProfile, name: "Personal research")
            store.setSpaceTheme(originalSpace, theme: .singleColor(ThemeColor(hex: "a1b2c3")!))
            #expect(store.activeSpace.theme.primaryColor?.hex == "A1B2C3", "A valid hexadecimal Space color must be normalized")
            store.renameProfile(originalProfile, name: "")
            store.renameProfile(UUID(), name: "Unknown")
            #expect(store.state.profiles.first { $0.id == originalProfile }?.name == "Personal research", "Empty or unknown profile rename requests must not erase an existing name")
            #expect(store.state.profiles.first { $0.id == otherProfile }?.name == "Untouched", "Renaming a profile must not change another profile")
            store.setAutoArchiveInterval(.twentyFourHours, for: originalProfile)
            store.updateSettings {
                $0.sidebarWidth = 265
                $0.searchEngine = "https://www.bing.com/search?q="
                $0.restoreSession = true
                $0.onboardingComplete = true
            }
            try store.save()
            let expected = store.state
            let reopened = try BrowserStore(directory: directory)
            #expect(reopened.state == expected, "Space names, profile names, colors, and preferences must survive a session restart")
            #expect(reopened.activeSpace.name == "Research — 夜空" && reopened.activeSpace.theme.primaryColor?.hex == "A1B2C3", "Unicode Space names and a valid custom color must remain intact")
        }
    }

    @Test(arguments: ["", "123", "1234567", "#112233", "GG1122", "ＡＡ0000"])
    static func invalidHexCannotEnterTheThemeModel(_ invalid: String) {
        #expect(ThemeColor(hex: invalid) == nil)
    }

    @Test(arguments: ["000000", "FFFFFF", "808080", "0123AB", "F20B85", "B9B5D4"])
    static func hslConversionPreservesTheOriginalColor(_ value: String) throws {
        let color = try #require(ThemeColor(hex: value))
        let hsl = color.hsl
        #expect(ThemeColor.hsl(hue: hsl.hue, saturation: hsl.saturation, lightness: hsl.lightness)?.hex == value)
    }

    private static func expectColor(_ actual: ThemeColor?, _ expected: (Double, Double, Double), _ message: String) throws {
        guard let actual else { throw BrowserStoreTests.Failure(description: message + " (no color)") }
        #expect(abs(actual.red - expected.0) < 1e-9 && abs(actual.green - expected.1) < 1e-9
                   && abs(actual.blue - expected.2) < 1e-9, Comment(rawValue: message))
    }

    @Test(arguments: [
        (0.0, 1.0, 0.5, [1.0, 0, 0]),
        (1.0 / 3, 1.0, 0.5, [0.0, 1, 0]),
        (-1.0 / 3, 1.0, 0.5, [0.0, 0, 1]),
        (2.0, 0.5, 0.25, [0.375, 0.125, 0.125]),
        (0.0, 0.5, 0.75, [0.875, 0.625, 0.625]),
    ])
    static func hslMatchesReferenceRGB(_ hue: Double, _ saturation: Double, _ lightness: Double, _ expected: [Double]) throws {
        try expectColor(.hsl(hue: hue, saturation: saturation, lightness: lightness),
                        (expected[0], expected[1], expected[2]), "HSL reference")
    }

    @Test
    static func nonfiniteHueIsRejected() {
        #expect(ThemeColor.hsl(hue: .nan, saturation: 1, lightness: 0.5) == nil, "Nonfinite hue is rejected")
    }

    @Test
    static func outOfRangeRGBIsRejected() {
        #expect(ThemeColor(red: 1.1, green: 0, blue: 0) == nil, "Out-of-range components are rejected")
    }

    @Test
    static func linkedPalettesKeepNearBlackCompanions() {
        let nearBlack = SpaceTheme(primaryColor: ThemeColor(red: 0.0001, green: 0, blue: 0), colorCount: 3)
        #expect(nearBlack.colors.count == 3, "Floating-point saturation at near-black must not drop linked colors")
    }

    @Test
    static func colorWheelSelectsItsCompanionHues() throws {
        var theme = SpaceTheme(primaryColor: ThemeColor(hex: "FF0000"), colorCount: 2)
        try expectColor(theme.colors.last, (0, 1, 1), "Two complementary colors are red/cyan")
        theme.colorCount = 3
        try expectColor(theme.colors[1], (0, 1, 0.5), "Three-color first companion is 150 degrees")
        try expectColor(theme.colors[2], (0, 0.5, 1), "Three-color second companion is 210 degrees")
        theme.wheel = .analogous
        try expectColor(theme.colors[1], (1, 2.0 / 3, 0), "First analogous companion is 40 degrees")
        try expectColor(theme.colors[2], (1, 0, 2.0 / 3), "Second analogous companion is minus 40 degrees")
    }

    @Test
    static func linkedPalettesPreserveTheOriginalColorSpaceAndPrecision() {
        let wide = ThemeColor(red: 0.83, green: 0.17, blue: 0.29, colorSpace: .displayP3)!
        let theme = SpaceTheme(primaryColor: wide, colorCount: 3, wheel: .analogous)
        #expect(theme.colors.first == wide && theme.colors.allSatisfy { $0.colorSpace == .displayP3 }, "Linked colors must preserve the primary color space and original component precision")
    }

    @Test(arguments: [(0.127, false, 0.15), (0.127, true, 0.127), (Double.infinity, false, 0.127), (3.0, false, 1.0)])
    static func noiseGesturesRespectQuantizationAndBounds(_ input: Double, _ rotating: Bool, _ expected: Double) {
        var theme = SpaceTheme(primaryColor: ThemeColor(hex: "FF0000"), colorCount: 3)
        theme.setNoise(0.127, rotating: true)
        theme.setNoise(input, rotating: rotating)
        #expect(theme.noise == expected)
    }

    @Test
    static func removingThemeColorsResetsModifiersOnlyAfterTheLastColor() {
        let wide = ThemeColor(red: 0.83, green: 0.17, blue: 0.29, colorSpace: .displayP3)!
        var theme = SpaceTheme(primaryColor: wide, colorCount: 3, wheel: .analogous)
        theme.setNoise(1)
        theme.appearance = .dark; theme.texture = .denim; theme.intensity = 0.2
        theme.removeColor(); theme.removeColor()
        #expect(theme.colorCount == 1 && theme.primaryColor == wide, "Removing companions retains primary color")
        theme.removeColor()
        #expect(theme.isValid && theme.colors.isEmpty && theme.noise == 0 && theme.intensity == 0.8
                   && theme.texture == .grain && theme.appearance == .dark, "Removing the final color resets modifiers but preserves appearance")
    }

    @Test @MainActor static func legacySpaceColorMigratesToTheOnlyPersistedThemeWithoutChangingIdentity() throws {
        try BrowserStoreTests.withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let originalID = store.activeSpaceID
            try store.save()
            let file = directory.appendingPathComponent("session.json")
            var object = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as! [String: Any]
            var spaces = object["spaces"] as! [[String: Any]]
            spaces[0].removeValue(forKey: "theme"); spaces[0]["color"] = "a1b2c3"
            object["spaces"] = spaces
            try JSONSerialization.data(withJSONObject: object).write(to: file)
            let migrated = try BrowserStore(directory: directory)
            #expect(migrated.activeSpaceID == originalID && migrated.activeSpace.theme.primaryColor?.hex == "A1B2C3"
                       && migrated.activeSpace.theme.colorCount == 1, "Legacy Space color migrates without changing identity or RGB values")
            try migrated.save()
            let saved = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as! [String: Any]
            let savedSpaces = saved["spaces"] as! [[String: Any]]
            #expect(savedSpaces.allSatisfy { $0["color"] == nil && $0["theme"] != nil }, "Theme is the only persisted source of color state after migration")
        }
    }

    private static let detailedTheme = SpaceTheme(primaryColor: ThemeColor(red: 0.9, green: 0.3, blue: 0.4, colorSpace: .displayP3),
        colorCount: 3, wheel: .analogous, appearance: .dark, noise: 0.35, intensity: 0.63, texture: .tweed)

    @Test @MainActor static func editingAnInactiveSpaceThemeDoesNotSwitchOrRecolorTheActiveSpace() throws {
        try BrowserStoreTests.withDirectory { directory in
            let migrated = try BrowserStore(directory: directory)
            let target = migrated.activeSpaceID
            let other = migrated.createSpace(name: "Other", color: "aabbcc")
            let untouched = migrated.activeSpace.theme
            #expect(migrated.setSpaceTheme(target, theme: detailedTheme), "Valid theme update targets the captured Space")
            #expect(migrated.activeSpaceID == other && migrated.activeSpace.theme == untouched, "Editing another Space must not switch or recolor the active Space")
        }
    }

    @Test @MainActor static func allThemeComponentsSurviveRestart() throws {
        try BrowserStoreTests.withDirectory { directory in
            let migrated = try BrowserStore(directory: directory)
            try #require(migrated.setSpaceTheme(migrated.activeSpaceID, theme: detailedTheme))
            try migrated.save()
            let reopened = try BrowserStore(directory: directory)
            #expect(reopened.state == migrated.state, "All theme components and other Space state survive restart")
        }
    }

    enum ThemeDamage: CaseIterable { case tooManyColors, nonfiniteNoise, missingPrimaryColor, unknownSpace }

    @Test(arguments: ThemeDamage.allCases) @MainActor static func invalidThemeUpdatesDoNotChangeTheSession(_ damage: ThemeDamage) throws {
        try BrowserStoreTests.withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let original = store.state
            var space = store.activeSpaceID
            var theme = detailedTheme
            switch damage {
            case .tooManyColors: theme.colorCount = 4
            case .nonfiniteNoise: theme.noise = .nan
            case .missingPrimaryColor: theme.primaryColor = nil
            case .unknownSpace: space = UUID()
            }
            #expect(!store.setSpaceTheme(space, theme: theme))
            #expect(store.state == original)
        }
    }

    @Test @MainActor static func invalidPersistedThemesAreRejectedWithoutRewritingTheFile() throws {
        try BrowserStoreTests.withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            try #require(store.setSpaceTheme(store.activeSpaceID, theme: detailedTheme))
            try store.save()
            let file = directory.appendingPathComponent("session.json")
            let saved = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as! [String: Any]
            let savedSpaces = saved["spaces"] as! [[String: Any]]
            var broken = saved, brokenSpaces = savedSpaces
            var badTheme = brokenSpaces[0]["theme"] as! [String: Any]
            badTheme["intensity"] = 1.1; brokenSpaces[0]["theme"] = badTheme
            broken["spaces"] = brokenSpaces
            let badData = try JSONSerialization.data(withJSONObject: broken)
            try badData.write(to: file)
            var rejected = false
            do { _ = try BrowserStore(directory: directory) } catch { rejected = true }
            #expect(try rejected && (try Data(contentsOf: file)) == badData, "Invalid persisted themes surface an error and preserve the original session bytes")
        }
    }

    @Test(arguments: [
        ("pending", Int64(0)), ("downloading", Int64(25)), ("paused", Int64(25)),
        ("downloading", Int64(50)), ("failed", Int64(50)), ("downloading", Int64(75)), ("completed", Int64(100)),
    ])
    @MainActor static func aDownloadSnapshotUpdatesAndPersistsItsExistingRecord(_ state: String, _ received: Int64) throws {
        let status = try #require(BrowserDownloadStatus(rawValue: state))
        try BrowserStoreTests.withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            store.recordDownload(["id": "transfer-1", "status": "pending"])
            store.recordDownload(["id": "transfer-1", "name": "notes.pdf", "path": "/isolated/notes.pdf",
                                  "receivedBytes": NSNumber(value: received), "totalBytes": 100,
                                  "status": status.rawValue])
            #expect(store.state.downloads.count == 1, "A lifecycle update must replace the existing download rather than append a duplicate")
            let item = store.state.downloads[0]
            #expect(item.status == status && item.receivedBytes == received && item.totalBytes == 100, "Download state and byte progress must track the latest native snapshot: \(status)")
            #expect(item.isComplete == (status == .completed) && !item.isCancelled, "Paused or failed downloads must never be described as completed or cancelled")
            try store.save()
            let reopened = try BrowserStore(directory: directory)
            #expect(reopened.state.downloads == store.state.downloads, "Every download lifecycle state must persist across a restart: \(status)")
        }
    }

    @Test @MainActor static func cancellationPersistsAlongsideACompletedTransferWithoutNavigating() throws {
        try BrowserStoreTests.withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let originalSelection = store.state.selectedTabIDs
            let originalHistory = store.state.history
            store.recordDownload(["id": "transfer-1", "status": "completed", "receivedBytes": 100, "totalBytes": 100])
            store.recordDownload(["id": "transfer-2", "name": "cancelled.zip", "receivedBytes": 12,
                                  "totalBytes": 200, "status": "cancelled"])
            #expect(store.state.downloads.count == 2 && store.state.downloads[1].isCancelled
                       && !store.state.downloads[1].isComplete, "A cancelled transfer must remain distinct from a successful transfer")
            #expect(store.state.selectedTabIDs == originalSelection && store.state.history == originalHistory, "Download events must not navigate or create page history")
            try store.save()
            let reopened = try BrowserStore(directory: directory)
            #expect(reopened.state.downloads == store.state.downloads, "Cancellation and the prior completed transfer must both survive relaunch")
        }
    }

    @MainActor
    private static func withNativeDownload(
        _ body: (BrowserStore, [String: Any]) throws -> Void
    ) throws {
        try BrowserStoreTests.withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let profile = store.activeSpace.profileID
            let path = store.independentEngineProfilePath(for: profile)
            let snapshot: [String: Any] = ["id": "same-guid", "profilePath": path,
                "name": "report.pdf", "path": "/isolated/report.pdf", "status": "completed",
                "sourceURL": "https://example.test/report.pdf", "startedAt": 1_700_000_000.0,
                "available": true, "itemIdentity": "incarnation-one", "canOpen": true,
                "canReveal": true, "canRemove": true, "canCopyFile": true]
            store.recordDownload(snapshot)
            try body(store, snapshot)
        }
    }

    @Test @MainActor static func nativeDownloadMetadataKeepsTheProfileAndLiveFileActions() throws {
        try withNativeDownload { store, _ in
            let profile = store.activeSpace.profileID
            let original = store.state.downloads[0]
            #expect(original.profileID == profile && original.nativeIdentity == "incarnation-one"
                       && original.canOpen && original.canReveal && original.canRemove && original.canCopyFile, "Library controls must retain the real profile and live item incarnation")
            #expect(original.sourceURL == "https://example.test/report.pdf"
                       && original.startedAt == Date(timeIntervalSince1970: 1_700_000_000), "Source URL and native start time must survive the bridge without a fabricated date")
        }
    }

    @Test @MainActor static func reopenedDownloadsKeepMetadataButNotLiveFileActions() throws {
        try withNativeDownload { store, _ in
            let original = store.state.downloads[0]
            try store.save()
            let restored = try BrowserStore(directory: store.directory).state.downloads[0]
            #expect(restored.sourceURL == original.sourceURL && restored.startedAt == original.startedAt, "Library metadata survives session persistence")
            #expect(restored.nativeIdentity == nil && !restored.canOpen && !restored.canReveal
                       && !restored.canRemove && !restored.canCopyFile, "Restored metadata never grants live file actions")
        }
    }

    @Test @MainActor static func aNewDownloadIncarnationReplacesThePreviousOneForTheSameGUID() throws {
        try withNativeDownload { store, initial in
            var snapshot = initial
            snapshot["itemIdentity"] = "incarnation-two"
            store.recordDownload(snapshot)
            #expect(store.state.downloads.count == 1 && store.state.downloads[0].nativeIdentity == "incarnation-two", "The same GUID can receive a new incarnation without making an old row current")
        }
    }

    @Test @MainActor static func retiringADownloadManagerRevokesFileActions() throws {
        try withNativeDownload { store, initial in
            var snapshot = initial
            snapshot["available"] = false
            store.recordDownload(snapshot)
            #expect(store.state.downloads[0].nativeIdentity == nil && !store.state.downloads[0].canCopyFile, "Manager retirement revokes file actions without erasing truthful completion")
        }
    }

    @Test @MainActor static func downloadsFromUnknownProfilesCannotChangeTheSession() throws {
        try withNativeDownload { store, initial in
            let selection = store.state.selectedTabIDs
            var snapshot = initial
            snapshot["profilePath"] = store.directory.appendingPathComponent("unowned").path
            snapshot["id"] = "unowned"
            store.recordDownload(snapshot)
            #expect(store.state.downloads.count == 1 && store.state.selectedTabIDs == selection, "Unknown profiles are discarded; download updates do not switch pages")
        }
    }

    @Test @MainActor static func reconcilingDownloadHistoryRemovesOnlyStaleRecordsForThatProfile() throws {
        try withNativeDownload { store, _ in
            store.recordDownload(["id": "legacy", "name": "old.pdf", "status": "completed"])
            store.reconcileDownloads(profileID: store.activeSpace.profileID, nativeIDs: [])
            #expect(store.state.downloads.map(\.id) == ["legacy"], "Ready manager history removes only stale records assigned to its original profile")
        }
    }

    @Test @MainActor static func legacyDownloadSessionMigration() throws {
        try BrowserStoreTests.withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            try store.save()
            let file = directory.appendingPathComponent("session.json")
            var session = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as! [String: Any]
            session["downloads"] = [
                ["id": "complete", "name": "complete.pdf", "path": "/isolated/complete.pdf",
                 "receivedBytes": 100, "totalBytes": 100, "isComplete": true, "isCancelled": false],
                ["id": "cancelled", "name": "cancelled.pdf", "path": "",
                 "receivedBytes": 50, "totalBytes": 100, "isComplete": false, "isCancelled": true],
                ["id": "active", "name": "active.pdf", "path": "/isolated/active.pdf",
                 "receivedBytes": 50, "totalBytes": 100, "isComplete": false, "isCancelled": false],
                ["id": "pending", "name": "pending.pdf", "path": "",
                 "receivedBytes": 0, "totalBytes": -1, "isComplete": false, "isCancelled": false]
            ]
            try JSONSerialization.data(withJSONObject: session).write(to: file)
            let migrated = try BrowserStore(directory: directory)
            #expect(migrated.state.downloads.map(\.status) == [.completed, .cancelled, .downloading, .pending], "Old sessions without status must retain completion, cancellation, and available progress information")
            #expect(migrated.state.downloads[0].path == "/isolated/complete.pdf"
                       && migrated.state.downloads[2].receivedBytes == 50
                       && migrated.state.downloads[3].totalBytes == -1, "Migration must preserve paths, byte counts, and unknown content lengths")
            try migrated.save()
            let encoded = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as! [String: Any]
            let downloads = encoded["downloads"] as! [[String: Any]]
            #expect(downloads[0]["status"] as? String == "completed"
                       && downloads[0]["isComplete"] as? Bool == true
                       && downloads[1]["isCancelled"] as? Bool == true, "Newly saved states must include precise status and retain the original compatibility flags")
            let reopened = try BrowserStore(directory: directory)
            #expect(reopened.state.downloads == migrated.state.downloads, "A migrated session must round-trip without further state changes")
        }
    }

    @Test(arguments: [
        ("isPaused", "", "paused"), ("isFailed", "", "failed"),
        ("isFailed", "downloading", "downloading"), ("isFailed", "unknown", "failed"),
    ])
    @MainActor static func explicitDownloadStatusTakesPrecedenceOverCompatibilityFlags(_ flag: String, _ status: String, _ expected: String) throws {
        try BrowserStoreTests.withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            var snapshot: [String: Any] = ["id": "transfer", flag: true, "receivedBytes": 4]
            if !status.isEmpty { snapshot["status"] = status }
            store.recordDownload(snapshot)
            #expect(store.state.downloads.map(\.status.rawValue) == [expected])
        }
    }
}
