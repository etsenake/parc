import Foundation
import Testing
@testable import ParcCore

extension SpaceSharingTestsSupport {
    @MainActor
    struct SpaceSharingEaselRestrictionsTests {
        final class Blocks {
            let folder: Folder
            let state: BrowserState
            let a: BrowserSpace, b: BrowserSpace, c: BrowserSpace
            let p: BrowserProfile, q: BrowserProfile
            let page = InternalPage.easel(UUID())
            let plans: BrowserTab
            let web: BrowserTab
            var relocated: [[InternalPage]] = []

            @MainActor init() throws {
                folder = try Folder()
                var state = BrowserState.initial()
                p = state.profiles[0]
                q = BrowserProfile(id: UUID(), name: "Q")
                state.spaces[0].name = "Alpha"
                a = state.spaces[0]
                b = BrowserSpace(id: UUID(), name: "Beta", symbol: "circle", color: "B9B5D4", profileID: p.id)
                c = BrowserSpace(id: UUID(), name: "Gamma", symbol: "circle", color: "B9B5D4", profileID: q.id)
                state.profiles.append(q)
                state.spaces += [b, c]
                self.state = state
                var plans = SpaceSharingTestsSupport.tab(a, page.urlString)
                plans.title = "Plans"
                plans.savedTitle = "Plans"
                self.plans = plans
                web = SpaceSharingTestsSupport.tab(a, "https://a.example")
            }

            @MainActor func load(_ extra: [BrowserTab]) throws -> BrowserStore {
                var next = state
                next.tabs = [plans, web] + extra
                try folder.write(next)
                let store = try folder.store()
                relocated = []
                store.relocateLocalDocuments = { [unowned self] _, pages, _, _ in relocated.append(pages); return {} }
                return store
            }

            @MainActor func change(_ store: BrowserStore, _ sharing: SpaceDataSharing) throws -> SpaceSharingChange? {
                var outcome: Result<SpaceSharingChange?, Error>?
                store.changeSharing(ofSpace: a.id, to: sharing) { outcome = $0 }
                return try #require(outcome).get()
            }
        }

        func assertBlocked(_ blocks: Blocks, extra: [BrowserTab], sharing: SpaceDataSharing, title: String, places: String) throws {
            let store = try blocks.load(extra)
            let before = store.state
            let block = store.sharingDocumentBlock(forSpace: blocks.a.id, to: sharing)
            #expect(block?.title == title)
            #expect(block?.message == "The Easel “Plans” is still used elsewhere on Alpha’s current data: " + places + ".")
            #expect(try blocks.change(store, sharing) == nil)
            #expect(store.state == before)
            #expect(blocks.relocated.isEmpty)
        }

        @Test func aFavoriteExplainsWhyTheDataCannotChange() throws {
            let blocks = try Blocks()
            try assertBlocked(blocks, extra: [SpaceSharingTestsSupport.tab(blocks.a, blocks.page.urlString, kind: .favorite)], sharing: .separate,
                              title: "Can’t keep Alpha separate", places: "in Favorites")
        }

        @Test func anArchivedEntryExplainsWhyTheDataCannotChange() throws {
            let blocks = try Blocks()
            var archived = SpaceSharingTestsSupport.tab(blocks.a, blocks.page.urlString)
            archived.archivedAt = Date()
            try assertBlocked(blocks, extra: [archived], sharing: .share(withSpace: blocks.c.id),
                              title: "Can’t share Gamma’s data with Alpha", places: "in the Archive")
        }

        @Test func anEntryInASpaceSharingTheOldDataExplainsWhyTheDataCannotChange() throws {
            let blocks = try Blocks()
            try assertBlocked(blocks, extra: [SpaceSharingTestsSupport.tab(blocks.b, blocks.page.urlString)], sharing: .share(withSpace: blocks.c.id),
                              title: "Can’t share Gamma’s data with Alpha", places: "in Today in Beta")
        }

        @Test func anEaselUsedOnlyInTheChangingSpaceHasNothingToExplain() throws {
            let blocks = try Blocks()
            let store = try blocks.load([])
            #expect(store.sharingDocumentBlock(forSpace: blocks.a.id, to: .share(withSpace: blocks.c.id)) == nil)
            #expect(store.sharingDocumentBlock(forSpace: blocks.a.id, to: .separate) == nil)
        }

        @Test func aChoiceThatChangesNothingHasNothingToExplain() throws {
            let blocks = try Blocks()
            let store = try blocks.load([])
            #expect(store.sharingDocumentBlock(forSpace: blocks.b.id, to: .share(withSpace: blocks.a.id)) == nil)
            #expect(store.sharingDocumentBlock(forSpace: blocks.c.id, to: .separate) == nil)
            #expect(store.sharingDocumentBlock(forSpace: blocks.a.id, to: .share(withSpace: UUID())) == nil)
        }

        @Test func withoutBlockingEntriesTheDataWarningIsStillAsked() throws {
            let blocks = try Blocks()
            let store = try blocks.load([])
            #expect(store.sharingWarning(forSpace: blocks.a.id, to: .share(withSpace: blocks.c.id))
                    == .share(target: "Gamma", space: "Alpha", discardsOwnData: false))
        }

        @Test func aDataChangeWithNoSharedEaselsProceedsAndCarriesItsEaselAlong() throws {
            let blocks = try Blocks()
            let store = try blocks.load([])
            let joined = try blocks.change(store, .share(withSpace: blocks.c.id))
            #expect(joined == SpaceSharingChange(spaceID: blocks.a.id, profileID: blocks.q.id, previousProfileID: blocks.p.id, unusedProfile: nil))
            #expect(store.state.tabs.allSatisfy { $0.profileID == blocks.q.id })
            #expect(blocks.relocated == [[blocks.page]])
        }
    }
}
