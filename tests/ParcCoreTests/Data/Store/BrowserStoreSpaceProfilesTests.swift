import Foundation
import Testing
@testable import ParcCore

struct BrowserStoreSpaceProfilesTests {
    @Test @MainActor static func spacesShareOnlyFavoritesWithinAProfile() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let favorite = store.open("https://favorite.example.org", kind: .favorite)
            _ = store.open("https://pinned.example.org", kind: .pinned)
            _ = store.open("https://today.example.org")
            _ = store.createSpace(name: "Second")
            #expect(store.visibleTabs.map(\.id) == [favorite], "Favorites are shared by Spaces using a profile; pinned and Today tabs are Space-local")
        }
    }

    @Test @MainActor static func switchingSpacesRestoresEachSelection() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
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
        try BrowserStoreTestsSupport.withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let favorite = store.open("https://favorite.example.org", kind: .favorite)
            let pinned = store.open("https://pinned.example.org", kind: .pinned)
            let secondSpace = store.createSpace(name: "Second")
            let second = store.open("https://second.example.org")
            let profile = store.createProfile(name: "Independent")
            store.assignProfile(profile, toSpace: secondSpace)
            #expect(!store.visibleTabs.contains { $0.id == favorite }, "A favorite must not leak into a different profile")
            let firstTab = try BrowserStoreTestsSupport.tab(pinned, in: store)
            let secondTab = try BrowserStoreTestsSupport.tab(second, in: store)
            #expect(secondTab.profileID == profile, "Assigning a Space profile must update its ordinary tabs")
            #expect(store.profilePath(for: firstTab) != store.profilePath(for: secondTab), "Independent profiles must use separate engine storage directories")
            #expect(store.profilePath(for: secondTab).hasPrefix(directory.path + "/Profiles/"), "Engine profile storage must remain beneath the isolated application directory")
            try BrowserStoreTestsSupport.expectValidSelection(store)
        }
    }

    @Test @MainActor static func movingASelectedTabAcrossProfilesClearsTheSourceSelection() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
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
            #expect(try BrowserStoreTestsSupport.tab(today, in: store).profileID == profile, "A cross-Space move must adopt the destination profile")
            try BrowserStoreTestsSupport.expectValidSelection(store)
        }
    }
}
