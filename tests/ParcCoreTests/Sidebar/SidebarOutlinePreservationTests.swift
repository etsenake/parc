import Foundation
import Testing
@testable import ParcCore

struct SidebarOutlinePreservationTests {
    let previous: BrowserState
    let tab: BrowserTab

    init() {
        var state = BrowserState.initial()
        let space = state.spaces[0]
        tab = BrowserTab(id: UUID(), spaceID: space.id, profileID: space.profileID, url: "https://example.test/", title: "Example",
                         kind: .today, createdAt: Date(timeIntervalSince1970: 1), lastAccessed: Date(timeIntervalSince1970: 2),
                         savedURL: "https://example.test/", savedTitle: "Example")
        state.tabs = [tab]
        previous = state
    }

    @Test func anIdenticalStatePreservesTheOutlineAndTheChromeLayout() {
        #expect(previous.preservesSidebarOutline(relativeTo: previous))
        #expect(previous.preservesChromeLayout(relativeTo: previous))
    }

    @Test func aLivePageTitleOrAddressChangePreservesTheOutline() {
        var next = previous
        next.tabs[0].title = "Renamed"
        next.tabs[0].url = "https://example.test/next"
        #expect(next.preservesSidebarOutline(relativeTo: previous))
    }

    @Test func aDownloadOrCustomTitleTickPreservesTheOutlineButNotTheChromeLayout() {
        var renamed = previous
        renamed.tabs[0].customTitle = "Mine"
        #expect(renamed.preservesSidebarOutline(relativeTo: previous))
        #expect(!renamed.preservesChromeLayout(relativeTo: previous))
    }

    @Test func aChangedMembershipOrPlacementDoesNotPreserveTheOutline() {
        var added = previous
        added.tabs.append(tab)
        #expect(!added.preservesSidebarOutline(relativeTo: previous))
        var moved = previous
        moved.tabs[0].kind = .pinned
        #expect(!moved.preservesSidebarOutline(relativeTo: previous))
        var archived = previous
        archived.tabs[0].archivedAt = Date(timeIntervalSince1970: 5)
        #expect(!archived.preservesSidebarOutline(relativeTo: previous))
        var foldered = previous
        foldered.tabs[0].folderID = UUID()
        #expect(!foldered.preservesSidebarOutline(relativeTo: previous))
    }

    @Test func aChangedSelectionOrActiveSpaceDoesNotPreserveTheOutline() {
        var selected = previous
        selected.selectedTabIDs = [tab.id]
        #expect(!selected.preservesSidebarOutline(relativeTo: previous))
        var switched = previous
        switched.activeSpaceID = UUID()
        #expect(!switched.preservesSidebarOutline(relativeTo: previous))
    }

    @Test func aTabThatBecomesAnInternalPageOrBlankDoesNotPreserveTheOutline() {
        var settings = previous
        settings.tabs[0].url = InternalPage.easel(UUID()).urlString
        #expect(!settings.preservesSidebarOutline(relativeTo: previous))
        var blank = previous
        blank.tabs[0].url = "about:blank"
        #expect(!blank.preservesSidebarOutline(relativeTo: previous))
    }
}
