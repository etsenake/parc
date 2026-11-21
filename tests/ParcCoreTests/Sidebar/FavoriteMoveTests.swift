import Foundation
import Testing
@testable import ParcCore

struct FavoriteMoveTests {
    let profile = BrowserProfile(id: UUID(), name: "Original")
    let foreign = BrowserProfile(id: UUID(), name: "Other")
    let home: BrowserSpace, active: BrowserSpace, other: BrowserSpace
    let folder: BrowserFolder
    let first: BrowserTab, note: BrowserTab, easel: BrowserTab, today: BrowserTab, alien: BrowserTab
    let group: BrowserSplitLayout
    let state: BrowserState
    let tray: SidebarContainerLocation, homeTray: SidebarContainerLocation
    let top: SidebarContainerLocation, pinned: SidebarContainerLocation

    init() {
        let profile = self.profile, foreign = self.foreign
        home = BrowserSpace(id: UUID(), name: "Home", symbol: "circle", color: "AABBCC", profileID: profile.id)
        active = BrowserSpace(id: UUID(), name: "Active", symbol: "circle", color: "AABBCC", profileID: profile.id)
        other = BrowserSpace(id: UUID(), name: "Other", symbol: "circle", color: "AABBCC", profileID: foreign.id)
        folder = BrowserFolder(id: UUID(), spaceID: active.id, name: "Destination")
        let noteID = URL(fileURLWithPath: NSTemporaryDirectory() + "Parc Notes/" + UUID().uuidString + ".md"), easelID = UUID()
        let homeID = home.id, activeID = active.id, otherID = other.id
        func tab(_ title: String, kind: TabKind = .favorite, url: String? = nil, space: UUID? = nil, profileID: UUID? = nil) -> BrowserTab {
            let url = url ?? "https://example.invalid/" + title
            return BrowserTab(id: UUID(), spaceID: space ?? homeID, profileID: profileID ?? profile.id,
                url: url, title: title, kind: kind, createdAt: Date(timeIntervalSince1970: 1), lastAccessed: Date(timeIntervalSince1970: 2),
                savedURL: url, savedTitle: title, referrerID: UUID(), activeTabBeforeCreationID: UUID())
        }
        first = tab("First")
        note = tab("Note", url: InternalPage.note(noteID).urlString)
        easel = tab("Easel", url: InternalPage.easel(easelID).urlString)
        today = tab("Today", kind: .today, space: activeID)
        alien = tab("Alien", space: otherID, profileID: foreign.id)
        group = BrowserSplitLayout(sidebarAnchorID: note.id, customTitle: "Documents", spaceID: homeID,
            tabIDs: [note.id, easel.id], orientation: .vertical, widthFactors: [0.3, 0.7])
        var state = BrowserState(profiles: [profile, foreign], spaces: [home, active, other], activeSpaceID: activeID)
        state.tabs = [first, note, easel, today, alien]
        state.splitLayouts = [group]
        state.folders = [folder]
        self.state = state
        tray = SidebarContainerLocation(spaceID: activeID, folderID: nil, section: .favorite, profileID: profile.id)
        homeTray = SidebarContainerLocation(spaceID: homeID, folderID: nil, section: .favorite, profileID: profile.id)
        top = SidebarContainerLocation(spaceID: activeID, folderID: nil, section: .today)
        pinned = SidebarContainerLocation(spaceID: activeID, folderID: folder.id, section: .pinned)
    }

    func snapshot(_ value: BrowserState) -> SidebarHierarchySnapshot {
        SidebarHierarchySnapshot(state: value, spaceID: active.id, profileID: profile.id, includesFavorites: true)!
    }

    func makeTab(_ title: String, kind: TabKind = .favorite, space: UUID? = nil) -> BrowserTab {
        let url = "https://example.invalid/" + title
        return BrowserTab(id: UUID(), spaceID: space ?? home.id, profileID: profile.id,
            url: url, title: title, kind: kind, createdAt: Date(timeIntervalSince1970: 1), lastAccessed: Date(timeIntervalSince1970: 2),
            savedURL: url, savedTitle: title, referrerID: UUID(), activeTabBeforeCreationID: UUID())
    }

    func reordered() -> BrowserState {
        SidebarHierarchy.moving([.split(group.id)], to: tray, before: .tab(first.id), expected: snapshot(state), state: state)!
    }

    func movedOut() -> BrowserState {
        SidebarHierarchy.moving([.split(group.id)], to: pinned, before: nil, expected: snapshot(state), state: state)!
    }

    @Test func favoriteOrderBelongsToTheProfileNotTheVisibleSpace() {
        #expect(tray.key == homeTray.key)
    }

    @Test func aWholeGroupHasNoDuplicateChildrenAndNoForeignProfile() {
        #expect(SidebarHierarchy.children(in: tray, state: state) == [.tab(first.id), .split(group.id)])
    }

    @Test func twoSpacesShareTheSameOriginalTray() {
        #expect(SidebarHierarchy.children(in: homeTray, state: state) == SidebarHierarchy.children(in: tray, state: state))
    }

    @Test func aChildIsNotIndependentlyMovable() {
        #expect(SidebarHierarchy.location(of: .tab(note.id), state: state, spaceID: active.id) == nil)
    }

    @Test func aReorderIsVisibleFromTheOriginalHomeSpace() {
        #expect(SidebarHierarchy.children(in: homeTray, state: reordered()) == [.split(group.id), .tab(first.id)])
    }

    @Test func theKeyboardCursorFollowsTheOriginalTrayOrderAsAWholeGroup() {
        let keyboard = SidebarKeyboardNavigation.items(state: reordered(), spaceID: active.id, selected: [], focused: nil, available: { _ in true })
        #expect(keyboard.prefix(2).map(\.reference) == [.split(group.id), .tab(first.id)])
    }

    @Test func tabNavigationFollowsTheVisibleTrayOrderAndKeepsTheGroupOrientation() {
        let positions = PositionalTabNavigation.items(state: reordered(), spaceID: active.id, selected: [], focused: nil, available: { _ in true })
        #expect(positions.prefix(2).map(\.tabIDs) == [group.tabIDs, [first.id]])
        #expect(positions.first?.orientation == .vertical)
    }

    @Test func aReorderPreservesCompleteOriginalsAndGeometry() {
        let reorder = reordered()
        #expect(reorder.tabs == state.tabs)
        #expect(reorder.splitLayouts == state.splitLayouts)
    }

    @Test func aStaleGroupSnapshotIsRefused() {
        var renamed = state
        renamed.splitLayouts[0].customTitle = "Changed"
        #expect(SidebarHierarchy.moving([.split(group.id)], to: tray, before: nil, expected: snapshot(state), state: renamed) == nil)
    }

    @Test func aFolderCannotBecomeAFavorite() {
        #expect(SidebarHierarchy.moving([.folder(folder.id)], to: tray, before: nil, expected: snapshot(state), state: state) == nil)
    }

    @Test func aForeignProfileCannotEnterTheTray() {
        #expect(SidebarHierarchy.moving([.tab(alien.id)], to: tray, before: nil, expected: snapshot(state), state: state) == nil)
    }

    @Test func aSpoofedTrayProfileIsRefused() {
        let wrong = SidebarContainerLocation(spaceID: active.id, folderID: nil, section: .favorite, profileID: foreign.id)
        #expect(SidebarHierarchy.moving([.tab(today.id)], to: wrong, before: nil, expected: snapshot(state), state: state) == nil)
    }

    @Test func anOrdinaryOutlineSnapshotDoesNotAdmitAFavorite() {
        let ordinary = SidebarHierarchySnapshot(state: state, spaceID: active.id, profileID: profile.id)!
        #expect(SidebarHierarchy.moving([.tab(first.id)], to: top, before: nil, expected: ordinary, state: state) == nil)
    }

    @Test func movingOutUsesTheActiveDestinationSpaceForAllChildren() {
        let moved = movedOut()
        #expect(moved.tabs.filter { group.tabIDs.contains($0.id) }
            .allSatisfy { $0.kind == .pinned && $0.spaceID == active.id && $0.folderID == folder.id })
    }

    @Test func movingOutPreservesTheOriginalGroupIdentityTitleOrderAndRatios() {
        var movedGroup = group
        movedGroup.spaceID = active.id
        #expect(movedOut().splitLayouts == [movedGroup])
    }

    @Test func movingOutRetainsTypedDocumentIDsWithoutClones() {
        let moved = movedOut()
        #expect(moved.tabs.first { $0.id == note.id }?.url == note.url)
        #expect(moved.tabs.first { $0.id == easel.id }?.url == easel.url)
    }

    @Test func movingOutDoesNotMintCreationProvenanceAndLeavesUnrelatedOriginalsExact() {
        let moved = movedOut()
        #expect(moved.tabs.first { $0.id == note.id }?.referrerID == note.referrerID)
        #expect(moved.tabs.first { $0.id == first.id } == first)
    }

    @Test func movingOutRemovesTheWholeGroupFromTheProfileTrayAndDisclosesTheDestination() {
        let moved = movedOut()
        #expect(SidebarHierarchy.children(in: tray, state: moved) == [.tab(first.id)])
        #expect(moved.folders[0].isExpanded)
    }

    @Test func aWholeGroupCanReturnToTheTrayAndTheNewOrderIsProfileWide() {
        let moved = movedOut()
        let back = SidebarHierarchy.moving([.split(group.id)], to: tray, before: nil, expected: snapshot(moved), state: moved)!
        #expect(back.tabs.filter { group.tabIDs.contains($0.id) }.allSatisfy { $0.kind == .favorite && $0.folderID == nil })
        #expect(SidebarHierarchy.children(in: homeTray, state: back) == [.tab(first.id), .split(group.id)])
    }

    @Test func aPhysicalTransferCapturesCompleteOriginalRecords() throws {
        let collection = try #require(SidebarWindowMove(items: [.split(group.id)], sourceSpaceID: home.id, profileID: profile.id,
                                                        to: top, before: nil, state: state))
        #expect(collection.tabIDs == group.tabIDs)
        #expect(collection.collection.tabs == [note, easel])
    }

    @Test func aPhysicalMoveSharesTheSameCompleteModelTransaction() throws {
        let collection = try #require(SidebarWindowMove(items: [.split(group.id)], sourceSpaceID: home.id, profileID: profile.id,
                                                        to: top, before: nil, state: state))
        let transferred = try #require(collection.applying(to: state))
        var movedGroup = group
        movedGroup.spaceID = active.id
        #expect(transferred.splitLayouts == [movedGroup])
        #expect(transferred.tabs.filter { group.tabIDs.contains($0.id) }.allSatisfy { $0.spaceID == active.id && $0.kind == .today })
    }

    @Test func aPhysicalTransferRefusesChangedOriginalMetadata() throws {
        let collection = try #require(SidebarWindowMove(items: [.split(group.id)], sourceSpaceID: home.id, profileID: profile.id,
                                                        to: top, before: nil, state: state))
        var changedURL = state
        changedURL.tabs[1].url = "https://changed.invalid"
        #expect(collection.applying(to: changedURL) == nil)
    }

    func fullState() -> BrowserState {
        var full = state
        full.tabs += (0..<10).map { makeTab("extra\($0)") }
        return full
    }

    @Test func aSplitCountsAsOneFavoriteRoot() {
        #expect(SidebarHierarchy.children(in: tray, state: fullState()).count == 12)
    }

    @Test func aThirteenthRootIsRefusedByThePluralAndDirectTransactions() {
        let full = fullState()
        #expect(SidebarHierarchy.moving([.tab(today.id)], to: tray, before: nil, expected: snapshot(full), state: full) == nil)
        #expect(SidebarHierarchy.moving(.tab(today.id), to: tray, before: nil, expected: snapshot(full), state: full) == nil)
    }

    @Test func aReorderAtTheCapIsAllowed() {
        let full = fullState()
        #expect(SidebarHierarchy.moving([.split(group.id)], to: tray, before: .tab(first.id), expected: snapshot(full), state: full) != nil)
    }

    @Test func aBatchThatExceedsTheCapDoesNotPartiallyPublish() {
        var almost = fullState()
        almost.tabs.removeLast()
        let second = makeTab("Second incoming", kind: .today, space: active.id)
        almost.tabs.append(second)
        #expect(SidebarHierarchy.moving([.tab(today.id), .tab(second.id)], to: tray, before: nil, expected: snapshot(almost), state: almost) == nil)
    }

    @Test func aPhysicalTransferPreflightAlsoRefusesTheCap() {
        let full = fullState()
        #expect(SidebarWindowMove(items: [.tab(today.id)], sourceSpaceID: active.id, profileID: profile.id, to: tray, before: nil, state: full) == nil)
    }

    final class Persisted {
        let directory: URL
        let file: URL
        let store: BrowserStore

        @MainActor init(state: BrowserState) throws {
            directory = FileManager.default.temporaryDirectory.appendingPathComponent("parc-favorite-move-" + UUID().uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            file = directory.appendingPathComponent("session.json")
            try encoder.encode(state).write(to: file)
            store = try BrowserStore(directory: directory, now: { Date(timeIntervalSince1970: 10) })
        }

        deinit { try? FileManager.default.removeItem(at: directory) }
    }

    @MainActor @Test func favoriteSplitActivationKeepsTheCurrentSpaceAndExactPanes() throws {
        let persisted = try Persisted(state: state)
        persisted.store.selectTab(note.id)
        #expect(persisted.store.state.selectedTabIDs == group.tabIDs)
        #expect(persisted.store.activeSpaceID == active.id)
        #expect(persisted.store.activeSplitLayout == group)
    }

    @MainActor @Test func theWindowRemembersOriginalRatiosAndAcceptsTheProjectedLayoutWithoutRehoming() throws {
        let persisted = try Persisted(state: state)
        let store = persisted.store
        store.selectTab(note.id)
        let presentation = WindowPresentation(state: store.state, ready: true)
        #expect(presentation.splitLayout?.id == group.id)
        #expect(presentation.splitLayout?.widthFactors == group.widthFactors)
        #expect(store.setWindowPresentation(spaceID: active.id, selectedTabIDs: group.tabIDs, splitLayout: presentation.splitLayout))
        #expect(store.state.splitLayouts == [group])
    }

    @MainActor @Test func resizingTheSharedGroupPreservesItsOriginalOwnerAndTheWindowConsumesTheGeometry() throws {
        let persisted = try Persisted(state: state)
        let store = persisted.store
        store.selectTab(note.id)
        var presentation = WindowPresentation(state: store.state, ready: true)
        _ = store.setWindowPresentation(spaceID: active.id, selectedTabIDs: group.tabIDs, splitLayout: presentation.splitLayout)
        #expect(store.setSplitLayout(orientation: .horizontal, widthFactors: [0.6, 0.4]))
        #expect(store.state.splitLayouts.count == 1)
        #expect(store.state.splitLayouts[0].id == group.id)
        #expect(store.state.splitLayouts[0].spaceID == home.id)
        presentation.reconcile(store.state, available: { _ in true })
        #expect(presentation.splitLayout?.widthFactors == [0.6, 0.4])
    }

    @MainActor @Test func aFailedDurablePublicationLeavesAllOriginalsUnchanged() throws {
        let persisted = try Persisted(state: state)
        let store = persisted.store
        let before = store.state
        let move = try #require(SidebarWindowMove(items: [.split(group.id)], sourceSpaceID: active.id, profileID: profile.id,
                                                   to: top, before: nil, state: before))
        try FileManager.default.removeItem(at: persisted.file)
        try FileManager.default.createDirectory(at: persisted.file, withIntermediateDirectories: false)
        #expect(throws: (any Error).self) { try store.commitSidebarWindowMove(move) }
        #expect(store.state == before)
    }

    @MainActor @Test func oneOriginalCollectionCommitsReloadsDurablyAndCannotReplay() throws {
        let persisted = try Persisted(state: state)
        let store = persisted.store
        let move = try #require(SidebarWindowMove(items: [.split(group.id)], sourceSpaceID: active.id, profileID: profile.id,
                                                  to: top, before: nil, state: store.state))
        #expect(try store.commitSidebarWindowMove(move))
        let reloaded = try BrowserStore(directory: persisted.directory, now: { Date(timeIntervalSince1970: 10) })
        #expect(reloaded.state.tabs == store.state.tabs)
        #expect(reloaded.state.splitLayouts == store.state.splitLayouts)
        #expect(reloaded.state.sidebarItemOrder == store.state.sidebarItemOrder)
        #expect(try !store.commitSidebarWindowMove(move))
    }
}
