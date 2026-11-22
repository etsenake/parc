import Foundation
import Testing
@testable import ParcCore

struct InterProfileMoveDataChangesTests {
    private typealias Fixture = InterProfileMoveTestsSupport.Fixture

    @MainActor private final class DataChange {
        let f = Fixture()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("parc-data-change-block-" + UUID().uuidString)
        let note = InternalPage.easel(UUID()).urlString
        let easel = InternalPage.easel(UUID()).urlString
        let work: BrowserSpace
        let state: BrowserState

        init() throws {
            let f = f
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            work = BrowserSpace(id: UUID(), name: "Work", symbol: "circle", color: "AABBCC", profileID: f.p.id)
            var state = f.state
            state.spaces.append(work)
            let index = state.tabs.firstIndex { $0.id == f.today.id }!
            state.tabs[index].url = note
            state.tabs[index].savedURL = note
            state.tabs[index].title = "Plans"
            state.tabs[index].savedTitle = "Plans"
            self.state = state
        }

        deinit { try? FileManager.default.removeItem(at: directory) }

        func alias(_ url: String, _ space: BrowserSpace, _ kind: TabKind, archived: Bool = false) -> BrowserTab {
            BrowserTab(id: UUID(), spaceID: space.id, profileID: space.profileID, url: url, title: "Alias", kind: kind,
                       createdAt: Date(timeIntervalSince1970: 3), lastAccessed: Date(timeIntervalSince1970: 4),
                       archivedAt: archived ? Date(timeIntervalSince1970: 5) : nil, savedURL: url, savedTitle: "Alias")
        }

        func stored(_ state: BrowserState) throws -> BrowserStore {
            try InterProfileMoveTestsSupport.encoder.encode(state).write(to: directory.appendingPathComponent("session.json"))
            return try BrowserStore(directory: directory)
        }

        func refused(_ store: BrowserStore) -> Bool {
            guard let assignment = store.profileAssignment(f.q.id, toSpace: f.s.id), let after = assignment.proposal(store.state) else { return false }
            return InterProfileMove.documents(moving: assignment.tabIDs, after: after) == nil
        }

        var spread: BrowserState {
            var spread = state
            spread.tabs.append(alias(note, work, .today))
            return spread
        }

        var kept: BrowserState {
            var kept = state
            kept.tabs += [alias(note, f.s, .favorite), alias(note, f.s, .today, archived: true)]
            return kept
        }
    }

    @MainActor @Test func anEaselUsedOnlyInTheChangingSpaceHasNothingToExplain() throws {
        let c = try DataChange()
        let quiet = try c.stored(c.state)
        #expect(quiet.sharingDocumentBlock(forSpace: c.f.s.id, to: .separate) == nil)
        #expect(quiet.sharingDocumentBlock(forSpace: c.f.s.id, to: .share(withSpace: c.f.d.id)) == nil)
        #expect(!c.refused(quiet))
    }

    @MainActor @Test func anEaselOpenInAnotherSpaceOnTheOldDataBlocksKeepSeparate() throws {
        let c = try DataChange()
        let separate = try #require(try c.stored(c.spread).sharingDocumentBlock(forSpace: c.f.s.id, to: .separate))
        #expect(separate.change == .keepSeparate)
        #expect(separate.title == "Can’t keep Home separate")
    }

    @MainActor @Test func anEntryInASpaceSharingTheOldDataIsNamedWithItsSpace() throws {
        let c = try DataChange()
        let separate = try #require(try c.stored(c.spread).sharingDocumentBlock(forSpace: c.f.s.id, to: .separate))
        #expect(separate.message == "The Easel “Plans” is still used elsewhere on Home’s current data: in Today in Work.")
    }

    @MainActor @Test func aFavoriteAndAnArchivedEntryBlockSharingOtherData() throws {
        let c = try DataChange()
        let store = try c.stored(c.kept)
        #expect(store.sharingDocumentBlock(forSpace: c.f.s.id, to: .share(withSpace: c.f.d.id)) != nil)
        #expect(c.refused(store))
    }

    @MainActor @Test func sharingNamesBothSpacesAndKeepsFavoritesAndTheArchiveWithTheOldData() throws {
        let c = try DataChange()
        let share = try #require(try c.stored(c.kept).sharingDocumentBlock(forSpace: c.f.s.id, to: .share(withSpace: c.f.d.id)))
        #expect(share.change == .share(target: "Office"))
        #expect(share.title == "Can’t share Office’s data with Home")
        #expect(share.message == "The Easel “Plans” is still used elsewhere on Home’s current data: in Favorites and in the Archive.")
    }

    @MainActor @Test func aDataChangeExplainsTheFirstDocumentAndCountsTheRest() throws {
        let c = try DataChange()
        var pair = c.spread
        let index = pair.tabs.firstIndex { $0.id == c.f.g1.id }!
        pair.tabs[index].url = c.easel
        pair.tabs[index].savedURL = c.easel
        pair.tabs[index].title = "Board"
        pair.tabs[index].savedTitle = "Board"
        pair.tabs.append(c.alias(c.easel, c.f.s, .today, archived: true))
        #expect(try c.stored(pair).sharingDocumentBlock(forSpace: c.f.s.id, to: .separate)?.message
                == "The Easel “Plans” is still used elsewhere on Home’s current data: in Today in Work. 1 more Easel is too.")
    }

    @MainActor private func loneEasel(_ c: DataChange) -> (kept: BrowserState, after: BrowserState) {
        let kept = c.kept
        var after = kept
        after.tabs[after.tabs.firstIndex { $0.id == c.f.today.id }!].profileID = UUID()
        return (kept, after)
    }

    @MainActor @Test func aLoneEaselStillBlocksADataChangeAndIsNamed() throws {
        let c = try DataChange()
        let (kept, after) = loneEasel(c)
        let lone = try #require(InterProfileDocumentBlock(moving: [c.f.today.id], before: kept, after: after, sharing: .separate))
        #expect(lone.subject == "The Easel “Plans”")
    }

    @MainActor @Test func moveWordingIsUnchangedWhenNoDataChangeIsGiven() throws {
        let c = try DataChange()
        let (kept, after) = loneEasel(c)
        let moved = try #require(InterProfileDocumentBlock(moving: [c.f.today.id], before: kept, after: after))
        #expect(moved.change == .move)
        #expect(moved.subject == "This Easel")
        #expect(moved.title == "Can’t move to Home")
        #expect(moved.message == "This Easel is still used elsewhere in Home: in Favorites and in the Archive.")
    }
}
