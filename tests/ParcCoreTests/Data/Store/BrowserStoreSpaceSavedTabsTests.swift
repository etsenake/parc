import Foundation
import Testing
@testable import ParcCore

struct BrowserStoreSpaceSavedTabsTests {
    @Test(arguments: [TabKind.today, .pinned, .favorite], [true, false])
    @MainActor static func autoArchiveOnlyExpiresUnselectedTodayTabs(_ kind: TabKind, _ selected: Bool) throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            var now = Date(timeIntervalSince1970: 1_800_000_000)
            let store = try BrowserStore(directory: directory, now: { now })
            store.setAutoArchiveInterval(.oneHour, for: store.activeSpace.profileID)
            store.archiveExpiredTabs()
            let candidate = store.open("https://candidate.example.org", kind: kind)
            if !selected { _ = store.open("https://active.example.org") }
            now.addTimeInterval(2 * 3600)
            store.archiveExpiredTabs()
            #expect(try BrowserStoreTestsSupport.tab(candidate, in: store).archivedAt == (kind == .today && !selected ? now : nil))
        }
    }

    @Test @MainActor static func closingAndReopeningTodayRestoresItsIdentityAndSelection() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let selected = store.open("https://selected.example.org")
            store.closeTab(selected)
            #expect(try BrowserStoreTestsSupport.tab(selected, in: store).archivedAt != nil, "Closing Today must archive it")
            store.restoreArchivedTab(selected, destination: .previousSpace(fallbackSpaceID: store.activeSpaceID))
            #expect(try store.selectedTabID == selected && (try BrowserStoreTestsSupport.tab(selected, in: store)).archivedAt == nil, "Reopen closed tab must restore the same identity and select it")
            try BrowserStoreTestsSupport.expectValidSelection(store)
        }
    }

    @Test @MainActor static func neverDisablesAutomaticArchiving() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            var now = Date(timeIntervalSince1970: 1_800_000_000)
            let store = try BrowserStore(directory: directory, now: { now })
            store.setAutoArchiveInterval(.never, for: store.activeSpace.profileID)
            let keep = store.open("https://never.example.org")
            _ = store.open("https://active.example.org")
            now.addTimeInterval(40 * 24 * 3600)
            store.archiveExpiredTabs()
            #expect(try BrowserStoreTestsSupport.tab(keep, in: store).archivedAt == nil, "Never must disable automatic archiving")
        }
    }

    @Test @MainActor static func formingASplitFiltersUnknownAndDuplicateMembers() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let pinned = store.open("https://example.org/home", kind: .pinned)
            let today = store.open("https://example.org/today")
            store.setSplit([pinned, today, today, UUID()])
            #expect(store.state.selectedTabIDs == [pinned, today], "Splits must reject unknown or duplicate members")
        }
    }

    @Test @MainActor static func splittingANavigatedPinKeepsItsLivePageAndRestoresItsSavedHome() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let pinned = store.open("https://example.org/home", kind: .pinned)
            let today = store.open("https://example.org/today")
            store.updateTab(pinned, title: "A different page", url: "https://example.org/other")
            store.setSplit([pinned, today, today, UUID()])
            let home = try BrowserStoreTestsSupport.expectHome(of: pinned, in: store, savedURL: "https://example.org/home")
            #expect(home.url == home.savedURL && home.title == home.savedTitle, "The pinned slot keeps a fresh home at its saved page and title")
            #expect(try BrowserStoreTestsSupport.tab(pinned, in: store).kind == .today && (try BrowserStoreTestsSupport.tab(pinned, in: store)).url == "https://example.org/other", "The original live page joins the Today split unchanged")
        }
    }

    @Test @MainActor static func closingASplitPaneSelectsTheSurvivingPane() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let pinned = store.open("https://example.org/home", kind: .pinned)
            let today = store.open("https://example.org/today")
            store.setSplit([pinned, today, today, UUID()])
            store.closeTab(today)
            #expect(store.state.selectedTabIDs == [pinned], "Closing a split member must retain the surviving pane")
        }
    }

    @Test @MainActor static func closingAPreviouslyPinnedSplitPaneArchivesOnlyTheLiveOriginal() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let pinned = store.open("https://example.org/home", kind: .pinned)
            let today = store.open("https://example.org/today")
            store.updateTab(pinned, title: "A different page", url: "https://example.org/other")
            store.setSplit([pinned, today, today, UUID()])
            let home = try BrowserStoreTestsSupport.expectHome(of: pinned, in: store, savedURL: "https://example.org/home")
            store.closeTab(today)
            store.closeTab(pinned)
            let kept = try BrowserStoreTestsSupport.tab(home.id, in: store)
            #expect(try BrowserStoreTestsSupport.tab(pinned, in: store).archivedAt != nil && kept.archivedAt == nil && kept.kind == .pinned
                       && kept.savedURL == home.savedURL && kept.folderID == home.folderID, "Closing the joined original archives it while its saved home stays pinned")
        }
    }

    @Test @MainActor static func closingASplitLayoutKeepsThePrimarySelectedAndDoesNotArchiveOtherPanes() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let pinned = store.open("https://example.org/home", kind: .pinned)
            let today = store.open("https://example.org/today")
            store.setSplit([pinned, today])
            store.closeSplit()
            #expect(store.state.selectedTabIDs == [pinned], "Close Split must retain its primary tab")
            #expect(try BrowserStoreTestsSupport.tab(today, in: store).archivedAt == nil, "Closing a split layout must not archive its other tab")
        }
    }

    @Test @MainActor static func separatingTheFocusedPaneSelectsItWithoutArchivingItsSibling() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let pinned = store.open("https://example.org/home", kind: .pinned)
            let today = store.open("https://example.org/today")
            store.setSplit([pinned, today])
            store.separateSplitPane(today)
            #expect(try store.state.selectedTabIDs == [today] && (try BrowserStoreTestsSupport.tab(pinned, in: store)).archivedAt == nil, "Separating the focused pane keeps that original selected and preserves its sibling")
            try BrowserStoreTestsSupport.expectValidSelection(store)
        }
    }

    @Test(arguments: [TabKind.pinned, .favorite])
    @MainActor static func closingLastSavedTabDoesNotReselectIt(kind: TabKind) throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let saved = store.open("https://saved.example.org", kind: kind)
            store.updateTab(saved, title: "Current article", url: "https://saved.example.org/article")
            store.closeTab(saved)
            #expect(store.state.selectedTabIDs.isEmpty, "Closing the only \(kind.rawValue) must leave the start view instead of selecting it again")
            #expect(store.visibleTabs.map(\.id) == [saved], "Closing a saved tab must keep its destination in the sidebar")
            let destination = try BrowserStoreTestsSupport.tab(saved, in: store)
            #expect(destination.archivedAt == nil && destination.url == destination.savedURL
                       && destination.title == destination.savedTitle, "Closing the last saved tab must reset its page without archiving or deleting it")
            store.selectTab(saved)
            #expect(store.selectedTabID == saved, "The saved destination must remain explicitly selectable after closing")
        }
    }

    @Test(arguments: [TabKind.pinned, .favorite]) @MainActor static func closingASavedTabSelectsAnAvailableNeighbor(kind: TabKind) throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let saved = store.open("https://saved.example.org", kind: kind)
            let other = store.open("https://other.example.org")
            store.selectTab(saved)
            store.closeTab(saved)
            #expect(store.selectedTabID == other, "Closing a selected saved tab must still select an available neighboring tab")
        }
    }
}
