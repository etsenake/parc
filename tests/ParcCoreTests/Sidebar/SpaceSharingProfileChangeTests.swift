import Foundation
import Testing
@testable import ParcCore

extension SpaceSharingTestsSupport {
    @MainActor
    struct SpaceSharingProfileChangeTests {
        struct Change {
            let folder: Folder
            let store: BrowserStore
            let a: BrowserSpace, b: BrowserSpace, c: BrowserSpace
            let p: BrowserProfile, q: BrowserProfile
            let page: BrowserTab
            var outcome: Result<SpaceSharingChange?, Error>?

            @MainActor init() throws {
                folder = try Folder()
                var state = BrowserState.initial()
                a = state.spaces[0]
                p = state.profiles[0]
                state.settings.defaultProfileID = p.id
                q = BrowserProfile(id: UUID(), name: "Q")
                b = BrowserSpace(id: UUID(), name: "B", symbol: "circle", color: "B9B5D4", profileID: p.id)
                c = BrowserSpace(id: UUID(), name: "C", symbol: "circle", color: "B9B5D4", profileID: q.id)
                state.profiles.append(q)
                state.spaces += [b, c]
                page = SpaceSharingTestsSupport.tab(c, "https://c.example", kind: .pinned)
                state.tabs = [page]
                try folder.write(state)
                store = try folder.store()
            }

            @MainActor func change(_ space: UUID, _ sharing: SpaceDataSharing) throws -> SpaceSharingChange? {
                var outcome: Result<SpaceSharingChange?, Error>?
                store.changeSharing(ofSpace: space, to: sharing) { outcome = $0 }
                return try #require(outcome).get()
            }
        }

        @Test func joiningAwayFromASoleProfileReportsIt() throws {
            let change = try Change()
            #expect(change.store.wouldOrphanProfile(ifSpace: change.c.id, joins: .share(withSpace: change.a.id)))
            #expect(change.store.unusedProfile(ifSpace: change.c.id, joins: .share(withSpace: change.a.id)) == UnusedProfile(id: change.q.id, name: "Q"))
        }

        @Test func aProfileStillUsedElsewhereIsNotReported() throws {
            let change = try Change()
            #expect(!change.store.wouldOrphanProfile(ifSpace: change.a.id, joins: .share(withSpace: change.c.id)))
        }

        @Test func keepSeparateNeverLeavesAProfileUnused() throws {
            let change = try Change()
            #expect(!change.store.wouldOrphanProfile(ifSpace: change.c.id, joins: .separate))
        }

        @Test func movingToASharedProfileReportsNothingUnused() throws {
            let change = try Change()
            let joined = try change.change(change.a.id, .share(withSpace: change.c.id))
            #expect(joined == SpaceSharingChange(spaceID: change.a.id, profileID: change.q.id, previousProfileID: change.p.id, unusedProfile: nil))
        }

        @Test func keepSeparateMovesTheSpaceToANewProfileNamedAfterItWithItsTabs() throws {
            let change = try Change()
            _ = try change.change(change.a.id, .share(withSpace: change.c.id))
            let profiles = change.store.state.profiles.count
            let split = try change.change(change.c.id, .separate)
            let fresh = try #require(change.store.state.spaces.first { $0.id == change.c.id }).profileID
            #expect(split?.previousProfileID == change.q.id)
            #expect(split?.unusedProfile == nil)
            #expect(fresh != change.q.id)
            #expect(change.store.state.profiles.count == profiles + 1)
            #expect(change.store.state.profiles.last?.name == "C")
            #expect(change.store.state.tabs.first { $0.id == change.page.id }?.profileID == fresh)
            #expect(try change.folder.store().state.spaces.first { $0.id == change.c.id }?.profileID == fresh)
        }

        @Test func aSpaceThatAlreadyKeepsSeparateIsLeftAlone() throws {
            let change = try Change()
            _ = try change.change(change.a.id, .share(withSpace: change.c.id))
            _ = try change.change(change.c.id, .separate)
            let profiles = change.store.state.profiles.count
            #expect(try change.change(change.b.id, .separate) == nil)
            #expect(change.store.state.profiles.count == profiles)
        }

        @Test func leavingAProfileEmptyReportsItAndItsRemovalStages() throws {
            let change = try Change()
            _ = try change.change(change.a.id, .share(withSpace: change.c.id))
            _ = try change.change(change.c.id, .separate)
            let left = try change.change(change.a.id, .share(withSpace: change.c.id))
            let unused = try #require(left?.unusedProfile)
            #expect(unused == UnusedProfile(id: change.q.id, name: "Q"))
            let record = try change.store.stageRemoval(of: unused)
            #expect(record.profileID == change.q.id)
            #expect(change.store.isProfileRemovalPending(change.q.id))
        }

        @Test func removingTheDefaultProfileHandsDefaultToASurvivingProfileInTheSameSave() throws {
            let change = try Change()
            _ = try change.change(change.a.id, .share(withSpace: change.c.id))
            let last = try change.change(change.b.id, .share(withSpace: change.c.id))
            #expect(last?.unusedProfile == UnusedProfile(id: change.p.id, name: change.p.name))
            let fallback = try #require(change.store.state.spaces.first { $0.id == change.c.id }).profileID
            let defaultRecord = try change.store.stageRemoval(of: try #require(last?.unusedProfile))
            #expect(change.store.isProfileRemovalPending(change.p.id))
            #expect(defaultRecord.fallbackProfileID == fallback)
            #expect(change.store.defaultProfileID == fallback)
        }
    }
}
