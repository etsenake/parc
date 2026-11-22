import Foundation
import Testing
@testable import ParcCore

struct BrowserStoreSpaceStartupTests {
    @MainActor
    private static func withFreshSession(
        _ body: (BrowserStore, BrowserState, Date) throws -> Void
    ) throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
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
            let archivedAtLaunch = try liveToday.map { try BrowserStoreTestsSupport.tab($0.id, in: reopened).archivedAt }
            #expect(archivedAtLaunch == Array(repeating: now, count: liveToday.count))
            let oldArchive = try #require(saved.tabs.first { $0.archivedAt != nil })
            #expect(try BrowserStoreTestsSupport.tab(oldArchive.id, in: reopened) == oldArchive)
            #expect(Set(reopened.state.recentlyClosedIDs).count == reopened.state.recentlyClosedIDs.count, "Fresh-launch archiving must not duplicate recovery entries")
        }
    }

    @Test @MainActor static func aFreshSessionResetsSavedDestinationsWithoutRemovingThem() throws {
        try withFreshSession { reopened, saved, _ in
            let savedTabs = saved.tabs.filter { $0.kind == .pinned || $0.kind == .favorite }
            try #require(savedTabs.count == 3)
            let reopenedTabs = try savedTabs.map { try BrowserStoreTestsSupport.tab($0.id, in: reopened) }
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
            #expect(try reopened.selectedTabID == otherToday && (try BrowserStoreTestsSupport.tab(otherToday, in: reopened)).archivedAt == nil, "Archive restoration recovers a tab archived by the fresh-launch preference")
            try BrowserStoreTestsSupport.expectValidSelection(reopened)
        }
    }

    @Test @MainActor static func aPinnedOriginalJoinsANewTodaySplit() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let today = store.open("https://work.example.org")
            let pinned = store.open("https://work-saved.example.org", kind: .pinned)
            store.setSplit([today, pinned])
            #expect(try BrowserStoreTestsSupport.tab(pinned, in: store).kind == .today)
        }
    }

    @Test @MainActor static func changingRestorePreferenceDoesNotCloseCurrentTabs() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let date = Date(timeIntervalSince1970: 1_800_000_000)
            let store = try BrowserStore(directory: directory, now: { date })
            let tabID = store.open("https://current.example.org")
            store.updateSettings { $0.restoreSession = false }
            #expect(try store.selectedTabID == tabID && (try BrowserStoreTestsSupport.tab(tabID, in: store)).archivedAt == nil, "Changing the startup preference must not close tabs during the current session")
        }
    }

    @Test @MainActor static func reenablingRestoreKeepsCurrentTabsOnLaunch() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
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
}
