import Foundation
import Testing
@testable import ParcCore

struct InterProfileMoveOriginalsTests {
    private typealias Fixture = InterProfileMoveTestsSupport.Fixture

    @Test func aTodayOriginalCrossesProfilesCarryingTheDestinationProfileAndSpace() throws {
        let f = Fixture()
        let moved = try #require(f.propose(f.request(f.today)))
        let live = try #require(moved.tabs.first { $0.id == f.today.id })
        #expect(live.profileID == f.q.id)
        #expect(live.spaceID == f.d.id)
        #expect(live.kind == .today)
        #expect(live.folderID == nil)
    }

    @Test func theOriginalKeepsItsIdentityAddressAndProvenance() throws {
        let f = Fixture()
        let moved = try #require(f.propose(f.request(f.today)))
        let live = try #require(moved.tabs.first { $0.id == f.today.id })
        #expect(live.url == f.today.url)
        #expect(live.title == f.today.title)
        #expect(live.referrerID == f.today.referrerID)
    }

    @Test func theDestinationGroupPublishesWithTheOriginal() throws {
        let f = Fixture()
        let moved = try #require(f.propose(f.request(f.today)))
        #expect(moved.selectedTabIDs == [f.d1.id, f.today.id])
        #expect(moved.splitLayouts.contains { $0.tabIDs == [f.d1.id, f.today.id] && $0.spaceID == f.d.id })
    }

    @Test func aTodayMoveCreatesNoCopy() throws {
        let f = Fixture()
        #expect(try #require(f.propose(f.request(f.today))).tabs.count == f.state.tabs.count)
    }

    @Test func aPinnedOriginalLeavesAFreshHomeInTheSourceProfileWithTheSavedDestination() throws {
        let f = Fixture()
        let home = UUID()
        let saved = try #require(f.propose(f.request(f.pinned, home: home)))
        let copy = try #require(saved.tabs.first { $0.id == home })
        #expect(copy.profileID == f.p.id)
        #expect(copy.spaceID == f.s.id)
        #expect(copy.kind == .pinned)
        #expect(copy.url == f.pinned.savedURL)
        #expect(copy.title == f.pinned.savedTitle)
    }

    @Test func theHomeReplacesTheExactSourceParentSlot() throws {
        let f = Fixture()
        let home = UUID()
        let saved = try #require(f.propose(f.request(f.pinned, home: home)))
        #expect(SidebarHierarchy.children(in: f.root, state: saved) == [.tab(f.sibling.id), .tab(home)])
    }

    @Test func theSourceSpaceRemembersTheHomeNotTheMovedOriginal() throws {
        let f = Fixture()
        let home = UUID()
        let saved = try #require(f.propose(f.request(f.pinned, home: home)))
        #expect(saved.selectionBySpace[f.s.id.uuidString] == [home])
    }

    @Test func theLiveOriginalBecomesDestinationToday() throws {
        let f = Fixture()
        let saved = try #require(f.propose(f.request(f.pinned)))
        #expect(saved.tabs.first { $0.id == f.pinned.id }?.kind == .today)
        #expect(saved.tabs.first { $0.id == f.pinned.id }?.profileID == f.q.id)
    }

    @Test func aCollidingHomeIdentityRefuses() {
        let f = Fixture()
        #expect(f.propose(f.request(f.pinned, home: f.sibling.id)) == nil)
    }

    @Test func aTwoMemberSourceSplitDissolvesAndTheSurvivorIsIntact() throws {
        let f = Fixture()
        let child = try #require(f.propose(f.request(f.g2)))
        #expect(!child.splitLayouts.contains { $0.id == f.group.id })
        #expect(child.tabs.first { $0.id == f.g1.id } == f.g1)
    }

    private func threeMemberSource(_ f: Fixture) -> (BrowserState, UUID) {
        var three = f.state
        let g3 = BrowserTab(id: UUID(), spaceID: f.s.id, profileID: f.p.id, url: "https://live.invalid/g3", title: "g3", kind: .today,
                            folderID: nil, createdAt: .distantPast, lastAccessed: .distantPast, savedURL: "https://live.invalid/g3", savedTitle: "g3")
        three.tabs.append(g3)
        three.splitLayouts[0].tabIDs = [f.g1.id, f.g2.id, g3.id]
        three.splitLayouts[0].widthFactors = [0.2, 0.3, 0.5]
        return (three, g3.id)
    }

    @Test func theSurvivingSourceGroupKeepsItsIdentityAppearanceAndReanchors() throws {
        let f = Fixture()
        let (three, g3) = threeMemberSource(f)
        let moved = try #require(f.propose(f.request(f.g1), three))
        let kept = try #require(moved.splitLayouts.first { $0.id == f.group.id })
        #expect(kept.tabIDs == [f.g2.id, g3])
        #expect(kept.sidebarAnchorID == f.g2.id)
        #expect(kept.customTitle == "Pair")
        #expect(kept.orientation == .vertical)
    }

    @Test func theSurvivingProportionsRenormalize() throws {
        let f = Fixture()
        let (three, _) = threeMemberSource(f)
        let moved = try #require(f.propose(f.request(f.g1), three))
        let kept = try #require(moved.splitLayouts.first { $0.id == f.group.id })
        #expect(abs(kept.widthFactors.reduce(0, +) - 1) < 0.0001)
    }

    @Test func aDropCanJoinAnExistingDestinationGroupKeepingItsIdentity() throws {
        let f = Fixture()
        let (grouped, layout) = f.groupedDestination()
        let joined = try #require(f.propose(f.request(f.today, target: .insert(2), selection: layout.tabIDs, layout: layout), grouped))
        #expect(joined.splitLayouts.first { $0.id == layout.id }?.tabIDs == [f.d1.id, f.d2.id, f.today.id])
    }

    @Test func centerReplacementKeepsTheDisplacedPage() throws {
        let f = Fixture()
        let replaced = try #require(f.propose(f.request(f.today, target: .replace(0))))
        #expect(replaced.selectedTabIDs == [f.today.id])
        #expect(replaced.tabs.contains { $0.id == f.d1.id && $0.archivedAt == nil })
    }

    @Test func aTodayEaselCrossesProfilesAndItsDocumentMovesToTheDestinationStore() throws {
        let f = Fixture()
        let easelID = UUID()
        let easelState = f.setting(0, url: InternalPage.easel(easelID).urlString)
        let moved = try #require(f.propose(f.request(easelState.tabs[0]), easelState))
        #expect(InterProfileMove.documents(moving: [f.today.id], after: moved) == [.easel(easelID)])
    }

    @Test func anEaselWaitingAheadOfThePageMovesWithIt() throws {
        let f = Fixture()
        let easelID = UUID()
        var ahead = f.state
        ahead.tabs[0].openDocumentVisit(.easel(easelID), title: "Board")
        _ = ahead.tabs[0].stepBackFromNote()
        let moved = try #require(f.propose(f.request(ahead.tabs[0]), ahead))
        #expect(InterProfileMove.documents(moving: [f.today.id], after: moved) == [.easel(easelID)])
    }

    @Test func everyEaselInTheTabsHistoryMovesWithItBehindAndAheadOfTheShownNote() throws {
        let f = Fixture()
        let easelID = UUID(), laterEasel = UUID()
        var stacked = f.state
        stacked.tabs[0].openDocumentVisit(.easel(easelID), title: "Board")
        stacked.tabs[0].openDocumentVisit(.note(URL(fileURLWithPath: "/tmp/Parc Notes/Plan.md")), title: "Plan")
        stacked.tabs[0].openDocumentVisit(.easel(laterEasel), title: "Later")
        _ = stacked.tabs[0].stepNoteVisit(by: -1)
        let moved = try #require(f.propose(f.request(stacked.tabs[0]), stacked))
        #expect(InterProfileMove.documents(moving: [f.today.id], after: moved) == [.easel(easelID), .easel(laterEasel)])
    }

    @Test func aHomeAliasLeftInTheSourceProfileKeepsTheEaselThere() throws {
        let f = Fixture()
        var pinnedEasel = f.state
        let url = InternalPage.easel(UUID()).urlString
        pinnedEasel.tabs[1].url = url
        pinnedEasel.tabs[1].savedURL = url
        let split = try #require(f.propose(f.request(pinnedEasel.tabs[1]), pinnedEasel))
        #expect(InterProfileMove.documents(moving: [f.pinned.id], after: split) == nil)
    }

    private func noteURL() -> URL { URL(fileURLWithPath: NSTemporaryDirectory() + "Parc Notes/" + UUID().uuidString + ".md") }

    @Test func aNoteFileBelongsToNoProfileSoNothingRelocates() throws {
        let f = Fixture()
        let note = f.setting(0, url: InternalPage.note(noteURL()).urlString)
        let moved = try #require(f.propose(f.request(note.tabs[0]), note))
        #expect(InterProfileMove.documents(moving: [f.today.id], after: moved) == [])
    }

    @Test func aNoteAliasLeftBehindNeverBlocksTheMove() throws {
        let f = Fixture()
        var pinnedNote = f.state
        let url = InternalPage.note(noteURL()).urlString
        pinnedNote.tabs[1].url = url
        pinnedNote.tabs[1].savedURL = url
        let noteSplit = try #require(f.propose(f.request(pinnedNote.tabs[1]), pinnedNote))
        #expect(InterProfileMove.documents(moving: [f.pinned.id], after: noteSplit) == [])
        #expect(InterProfileDocumentBlock(moving: [f.pinned.id], before: pinnedNote, after: noteSplit) == nil)
    }

    @Test func aProfileWideFavoriteRefuses() {
        let f = Fixture()
        var favorite = f.state
        favorite.tabs[0].kind = .favorite
        #expect(f.propose(f.request(favorite.tabs[0]), favorite) == nil)
    }

    @Test func theCurrentLiveAddressIsWhatTheDestinationReloads() throws {
        let f = Fixture()
        var navigated = f.state
        navigated.tabs[0].url = "https://live.invalid/next"
        navigated.tabs[0].title = "Next"
        navigated.tabs[0].savedURL = navigated.tabs[0].url
        navigated.tabs[0].savedTitle = navigated.tabs[0].title
        navigated.tabs[0].lastAccessed = Date()
        navigated.tabs[0].isUnread = true
        let reloaded = try #require(f.propose(f.request(f.today), navigated))
        #expect(reloaded.tabs.first { $0.id == f.today.id }?.url == "https://live.invalid/next")
    }

    @Test func changedSavedMetadataRefusesAStaleGesture() {
        let f = Fixture()
        var changed = f.state
        changed.tabs[0].customTitle = "Renamed"
        #expect(f.propose(f.request(f.today), changed) == nil)
    }

    @Test func aChangedParentRefusesAStaleGesture() {
        let f = Fixture()
        var changed = f.state
        changed.tabs[1].folderID = UUID()
        #expect(f.propose(f.request(f.pinned), changed) == nil)
    }

    @Test func aPendingProfileRemovalRefuses() {
        let f = Fixture()
        var removal = f.state
        removal.profileRemovals = [ProfileRemovalRecord(id: UUID(), profileID: f.q.id, profileName: "Work")]
        #expect(f.propose(f.request(f.today), removal) == nil)
    }

    @Test func aSameSpaceSameProfileDropResolvesThroughTheOrdinaryDrop() {
        let f = Fixture()
        var sameProfile = f.state
        sameProfile.tabs[0].profileID = f.q.id
        sameProfile.tabs[0].spaceID = f.d.id
        #expect(f.propose(f.request(sameProfile.tabs[0]), sameProfile)?.tabs.first { $0.id == f.today.id }?.profileID == f.q.id)
    }
}
