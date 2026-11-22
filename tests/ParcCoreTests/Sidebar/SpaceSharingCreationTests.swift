import Foundation
import Testing
@testable import ParcCore

extension SpaceSharingTestsSupport {
    @MainActor
    struct SpaceSharingCreationTests {
        struct Draft {
            let folder: Folder
            let store: BrowserStore
            let home: BrowserSpace
            let away: BrowserSpace
            let other: BrowserProfile
            let moving: BrowserTab
            let sharing: BrowserTab
            let source: SidebarHierarchySnapshot

            @MainActor init() throws {
                folder = try Folder()
                var state = BrowserState.initial()
                home = state.spaces[0]
                other = BrowserProfile(id: UUID(), name: "Other")
                var away = BrowserSpace(id: UUID(), name: "Away", symbol: "circle", color: "B9B5D4", profileID: other.id)
                away.autoArchiveHours = other.autoArchiveHours
                self.away = away
                state.profiles.append(other)
                state.spaces.append(away)
                moving = SpaceSharingTestsSupport.tab(home, "https://move.example")
                sharing = SpaceSharingTestsSupport.tab(home, "https://share.example")
                state.tabs = [moving, sharing]
                try folder.write(state)
                store = try folder.store()
                source = SidebarHierarchySnapshot(state: store.state, spaceID: home.id, profileID: home.profileID)!
            }
        }

        @Test func keepSeparateCreatesASpaceOnANewProfileNamedAfterIt() throws {
            let folder = try Folder()
            try folder.write(.initial())
            let store = try folder.store()
            let home = store.activeSpace
            let work = try store.createSpace(name: " Work ", sharing: .separate)
            let space = try #require(store.state.spaces.first { $0.id == work })
            #expect(space.profileID != home.profileID)
            #expect(store.state.profiles.count == 2)
            #expect(store.state.profiles.last?.name == "Work")
            #expect(space.name == "Work")
            #expect(store.activeSpaceID == work)
        }

        @Test func shareDataReusesTheSpacesProfileAndCreationPersists() throws {
            let folder = try Folder()
            try folder.write(.initial())
            let store = try folder.store()
            let home = store.activeSpace
            _ = try store.createSpace(name: "Work", sharing: .separate)
            let shared = try store.createSpace(name: "Play", sharing: .share(withSpace: home.id))
            #expect(store.state.spaces.first { $0.id == shared }?.profileID == home.profileID)
            #expect(store.state.profiles.count == 2)
            #expect(try folder.store().state.profiles.count == 2)
        }

        @Test func aFailedSaveCreatesNeitherSpaceNorProfile() throws {
            let folder = try Folder()
            try folder.write(.initial())
            let store = try folder.store()
            let before = store.state
            try FileManager.default.removeItem(at: folder.url)
            try Data().write(to: folder.url)
            #expect((try? store.createSpace(name: "Broken", sharing: .separate)) == nil)
            #expect(store.state == before)
            try FileManager.default.removeItem(at: folder.url)
        }

        @Test func choosingKeepSeparateCreatesNothingBeforeCommit() throws {
            let draft = try Draft()
            var empty = try #require(SidebarNewSpaceDraft(from: draft.source, state: draft.store.state))
            empty.name = "Solo"
            empty.keepSeparate()
            let untouched = draft.store.state
            #expect(empty.keepsSeparate)
            #expect(empty.applying(to: draft.store.state) != nil)
            #expect(draft.store.state == untouched)
        }

        @Test func commitAddsTheSpaceAndItsProfileTogether() throws {
            let draft = try Draft()
            var empty = try #require(SidebarNewSpaceDraft(from: draft.source, state: draft.store.state))
            empty.name = "Solo"
            empty.keepSeparate()
            var result: Result<UUID?, Error>?
            draft.store.createSpace(empty) { result = $0 }
            let solo = try result?.get()
            let soloSpace = draft.store.state.spaces.first { $0.id == solo }
            #expect(soloSpace != nil)
            #expect(soloSpace?.profileID == empty.profileID)
            #expect(draft.store.state.profiles.first { $0.id == empty.profileID }?.name == "Solo")
        }

        @Test func movedTabsCrossIntoTheNewSeparateProfile() throws {
            let draft = try Draft()
            var moved = try #require(SidebarNewSpaceDraft(items: [.tab(draft.moving.id)], from: draft.source, state: draft.store.state))
            moved.name = "Moved"
            moved.keepSeparate()
            #expect(moved.movesItemsAcrossProfiles)
            #expect(try draft.store.createSpaceAndMoveSidebarItems(moved) == nil)
            var result: Result<UUID?, Error>?
            draft.store.createSpace(moved) { result = $0 }
            let movedTab = draft.store.state.tabs.first { $0.id == draft.moving.id }
            #expect(try result?.get() == moved.spaceID)
            #expect(movedTab?.spaceID == moved.spaceID)
            #expect(movedTab?.profileID == moved.profileID)
        }

        @Test func sharingMovesTabsOntoTheSharedProfileWithoutANewOne() throws {
            let draft = try Draft()
            var joined = try #require(SidebarNewSpaceDraft(items: [.tab(draft.sharing.id)], from: draft.source, state: draft.store.state))
            joined.name = "Joined"
            let sharesData = joined.shareData(withSpace: draft.away.id, in: draft.store.state)
            #expect(sharesData)
            #expect(!joined.keepsSeparate)
            let profiles = draft.store.state.profiles.count
            var result: Result<UUID?, Error>?
            draft.store.createSpace(joined) { result = $0 }
            #expect(try result?.get() == joined.spaceID)
            #expect(draft.store.state.tabs.first { $0.id == draft.sharing.id }?.profileID == draft.other.id)
            #expect(draft.store.state.profiles.count == profiles)
        }
    }
}
