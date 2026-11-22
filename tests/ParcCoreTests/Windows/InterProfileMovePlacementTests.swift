import Foundation
import Testing
@testable import ParcCore

struct InterProfileMovePlacementTests {
    private typealias Fixture = InterProfileMoveTestsSupport.Fixture

    @Test func aWholeSplitMovesToAnotherProfileAsOneContainer() throws {
        let f = Fixture()
        let from = try #require(SidebarHierarchySnapshot(state: f.state, spaceID: f.s.id, profileID: f.p.id))
        let to = try #require(SidebarHierarchySnapshot(state: f.state, spaceID: f.d.id, profileID: f.q.id))
        let move = try #require(SidebarSpaceMove(items: [.split(f.group.id)], from: from, to: to, state: f.state))
        #expect(move.crossesProfiles)
        #expect(move.tabIDs == f.group.tabIDs)
    }

    private func wholeMove(_ f: Fixture) throws -> (move: SidebarSpaceMove, applied: BrowserState, from: SidebarHierarchySnapshot, to: SidebarHierarchySnapshot) {
        let from = try #require(SidebarHierarchySnapshot(state: f.state, spaceID: f.s.id, profileID: f.p.id))
        let to = try #require(SidebarHierarchySnapshot(state: f.state, spaceID: f.d.id, profileID: f.q.id))
        let move = try #require(SidebarSpaceMove(items: [.split(f.group.id)], from: from, to: to, state: f.state))
        return (move, try #require(move.applying(to: f.state)), from, to)
    }

    @Test func everyChildCarriesTheDestinationProfile() throws {
        let f = Fixture()
        let w = try wholeMove(f)
        #expect(w.applied.tabs.filter { f.group.tabIDs.contains($0.id) }.allSatisfy { $0.profileID == f.q.id && $0.spaceID == f.d.id })
    }

    @Test func theGroupIDAnchorAppearanceAndProportionsSurvive() throws {
        let f = Fixture()
        let w = try wholeMove(f)
        var expected = f.group
        expected.spaceID = f.d.id
        #expect(w.applied.splitLayouts == [expected])
    }

    @Test func theLiveAddressIsRetainedForTheDestinationReload() throws {
        let f = Fixture()
        let w = try wholeMove(f)
        #expect(w.applied.tabs.first { $0.id == f.g1.id }?.url == f.g1.url)
    }

    @Test func movingToTheSameSpaceRefuses() throws {
        let f = Fixture()
        let w = try wholeMove(f)
        #expect(SidebarSpaceMove(items: [.split(f.group.id)], from: w.from, to: w.from, state: f.state) == nil)
    }

    @Test func aGroupWithAnEaselMovesTheEaselDocumentWithIt() throws {
        let f = Fixture()
        let easelID = UUID()
        var note = f.state
        note.tabs[3].url = InternalPage.easel(easelID).urlString
        let from = try #require(SidebarHierarchySnapshot(state: note, spaceID: f.s.id, profileID: f.p.id))
        let to = try #require(SidebarHierarchySnapshot(state: f.state, spaceID: f.d.id, profileID: f.q.id))
        let withEasel = try #require(SidebarSpaceMove(items: [.split(f.group.id)], from: from, to: to, state: note)?.applying(to: note))
        #expect(InterProfileMove.documents(moving: Set(f.group.tabIDs), after: withEasel) == [.easel(easelID)])
    }

    @Test func aRemovedDestinationProfileHasNoSnapshot() {
        let f = Fixture()
        var removing = f.state
        removing.profileRemovals = [ProfileRemovalRecord(id: UUID(), profileID: f.q.id, profileName: "Work")]
        #expect(SidebarHierarchySnapshot(state: removing, spaceID: f.d.id, profileID: f.q.id) == nil)
    }

    private func windowDrop(_ f: Fixture) throws -> (window: SidebarWindowMove, location: SidebarContainerLocation) {
        let location = SidebarContainerLocation(spaceID: f.d.id, folderID: nil, section: .today)
        return (try #require(SidebarWindowMove(items: [.split(f.group.id)], sourceSpaceID: f.s.id, profileID: f.p.id,
            destinationProfileID: f.q.id, to: location, before: .tab(f.d1.id), state: f.state)), location)
    }

    @Test func aWindowDropCrossesProfiles() throws {
        let f = Fixture()
        #expect(try windowDrop(f).window.crossesProfiles)
    }

    @Test func droppedChildrenTakeTheDestinationSectionAndProfile() throws {
        let f = Fixture()
        let dropped = try #require(try windowDrop(f).window.applying(to: f.state))
        #expect(dropped.tabs.filter { f.group.tabIDs.contains($0.id) }.allSatisfy { $0.profileID == f.q.id && $0.spaceID == f.d.id && $0.kind == .today })
    }

    @Test func theDropLandsBeforeTheRequestedDestinationItem() throws {
        let f = Fixture()
        let w = try windowDrop(f)
        let dropped = try #require(w.window.applying(to: f.state))
        #expect(SidebarHierarchy.children(in: w.location, state: dropped).first == .split(f.group.id))
    }

    private func trayDrop(_ f: Fixture) throws -> (BrowserState, SidebarContainerLocation) {
        let tray = SidebarContainerLocation(spaceID: f.d.id, folderID: nil, section: .favorite, profileID: f.q.id)
        let applied = try #require(SidebarWindowMove(items: [.split(f.group.id)], sourceSpaceID: f.s.id, profileID: f.p.id,
            destinationProfileID: f.q.id, to: tray, before: nil, state: f.state)?.applying(to: f.state))
        return (applied, tray)
    }

    @Test func aTrayDropMakesDestinationProfileFavorites() throws {
        let f = Fixture()
        let (toTray, _) = try trayDrop(f)
        #expect(toTray.tabs.filter { f.group.tabIDs.contains($0.id) }.allSatisfy { $0.kind == .favorite && $0.profileID == f.q.id && $0.folderID == nil })
    }

    @Test func theWholeGroupOccupiesOneTraySlot() throws {
        let f = Fixture()
        let (toTray, tray) = try trayDrop(f)
        #expect(SidebarHierarchy.children(in: tray, state: toTray) == [.split(f.group.id)])
    }

    private func favoriteLeaving(_ f: Fixture) throws -> (moved: BrowserState, favorite: BrowserTab, sourceTray: SidebarContainerLocation) {
        var source = f.state
        let favorite = BrowserTab(id: UUID(), spaceID: f.s.id, profileID: f.p.id, url: "https://live.invalid/fav", title: "Fav",
            kind: .favorite, folderID: nil, createdAt: .distantPast, lastAccessed: .distantPast, savedURL: "https://saved.invalid/fav", savedTitle: "Fav")
        let sourceTray = SidebarContainerLocation(spaceID: f.s.id, folderID: nil, section: .favorite, profileID: f.p.id)
        source.tabs.append(favorite)
        source.sidebarItemOrder[sourceTray.key] = [.tab(favorite.id)]
        let location = SidebarContainerLocation(spaceID: f.d.id, folderID: nil, section: .today)
        let moved = try #require(SidebarWindowMove(items: [.tab(favorite.id)], sourceSpaceID: f.s.id, profileID: f.p.id,
            destinationProfileID: f.q.id, to: location, before: nil, state: source)?.applying(to: source))
        return (moved, favorite, sourceTray)
    }

    @Test func aFavoriteBecomesADestinationTodayItem() throws {
        let f = Fixture()
        let r = try favoriteLeaving(f)
        let arrived = try #require(r.moved.tabs.first { $0.id == r.favorite.id })
        #expect(arrived.kind == .today)
        #expect(arrived.profileID == f.q.id)
        #expect(arrived.spaceID == f.d.id)
        #expect(arrived.savedURL == r.favorite.url)
    }

    @Test func theSourceTraySlotIsVacated() throws {
        let f = Fixture()
        let r = try favoriteLeaving(f)
        #expect(SidebarHierarchy.children(in: r.sourceTray, state: r.moved).isEmpty)
    }

    @Test func anImplicitSameProfileDropStillRefusesAnotherProfile() {
        let f = Fixture()
        let location = SidebarContainerLocation(spaceID: f.d.id, folderID: nil, section: .today)
        #expect(SidebarWindowMove(items: [.split(f.group.id)], sourceSpaceID: f.s.id, profileID: f.p.id, to: location, before: nil, state: f.state) == nil)
    }
}
