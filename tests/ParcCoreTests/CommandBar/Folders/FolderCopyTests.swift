import Foundation
import Testing
@testable import ParcCore

struct FolderCopyTests {
    let profile = BrowserProfile(id: UUID(), name: "Profile")
    let space: BrowserSpace
    let away: BrowserSpace
    let folder: BrowserFolder
    let nested: BrowserFolder
    let destination: BrowserFolder
    let ordinary: BrowserTab
    let favorite: BrowserTab
    let child: BrowserTab
    let left: BrowserTab
    let right: BrowserTab
    let split: BrowserSplitLayout
    let state: BrowserState
    let source: CommandBarFolderMoveSource
    let move: CommandBarFolderMove
    let now = Date(timeIntervalSince1970: 1000)
    let destinations: [UUID: String]

    static func tab(_ name: String, kind: TabKind = .today, folderID: UUID? = nil, space: UUID, profile: UUID) -> BrowserTab {
        var tab = BrowserTab(id: UUID(), spaceID: space, profileID: profile,
            url: "https://persisted.invalid/" + name, title: "Live " + name, kind: kind, folderID: folderID,
            createdAt: Date(timeIntervalSince1970: 100), lastAccessed: Date(timeIntervalSince1970: 100),
            savedURL: "https://saved.invalid/" + name, savedTitle: "Saved " + name)
        tab.customTitle = "Custom " + name
        tab.isMuted = true
        return tab
    }

    init() {
        space = BrowserSpace(id: UUID(), name: "Source", symbol: "circle", color: "000000", profileID: profile.id)
        away = BrowserSpace(id: UUID(), name: "Destination", symbol: "circle", color: "000000", profileID: profile.id)
        folder = BrowserFolder(id: UUID(), spaceID: space.id, name: "Original", isExpanded: false)
        nested = BrowserFolder(id: UUID(), spaceID: space.id, name: "Nested", parentID: folder.id, isExpanded: false)
        destination = BrowserFolder(id: UUID(), spaceID: away.id, name: "Destination", isExpanded: false)
        ordinary = Self.tab("ordinary", space: space.id, profile: profile.id)
        favorite = Self.tab("favorite", kind: .favorite, space: space.id, profile: profile.id)
        child = Self.tab("child", kind: .pinned, folderID: folder.id, space: space.id, profile: profile.id)
        left = Self.tab("left", kind: .pinned, folderID: nested.id, space: space.id, profile: profile.id)
        right = Self.tab("right", kind: .pinned, folderID: nested.id, space: space.id, profile: profile.id)
        split = BrowserSplitLayout(sidebarAnchorID: left.id, customTitle: "Layout", spaceID: space.id,
            tabIDs: [left.id, right.id], orientation: .vertical, widthFactors: [0.2, 0.8])
        var built = BrowserState(profiles: [profile], spaces: [space, away], activeSpaceID: space.id)
        built.folders = [folder, nested, destination]
        built.tabs = [ordinary, favorite, child, left, right]
        built.splitLayouts = [split]
        built.selectedTabIDs = [ordinary.id]
        built.selectionBySpace = [space.id.uuidString: [ordinary.id]]
        state = built
        source = CommandBarFolderMoveSource(items: [.tab(ordinary.id), .tab(favorite.id), .folder(folder.id)],
            spaceID: space.id, profileID: profile.id, state: built)!
        let destinationID = destination.id
        move = CommandBarFolderMove.snapshot(source: source, state: built).first { $0.folder.folderID == destinationID }!
        destinations = Dictionary(uniqueKeysWithValues: source.tabIDs.map { ($0, "https://materialized.invalid/" + $0.uuidString) })
    }

    @MainActor private func makeCopy() -> CommandBarFolderCopy {
        CommandBarFolderCopy(move: move, destinations: destinations, state: state, now: now)!
    }

    @Test @MainActor func allOriginalRootsAreCopiedInOrder() {
        #expect(makeCopy().roots.count == 3)
    }

    @Test @MainActor func theCompleteNestedTreeAndSplitAreCopied() {
        let copy = makeCopy()
        #expect(copy.tabs.count == 5)
        #expect(copy.folders.count == 2)
        #expect(copy.groups.count == 1)
    }

    @Test @MainActor func copiesGetNewTabFolderAndSplitIdentities() {
        let copy = makeCopy()
        #expect(Set(copy.tabs.map(\.id)).isDisjoint(with: source.tabIDs))
        #expect(Set(copy.folders.map(\.id)).isDisjoint(with: state.folders.map(\.id)))
        #expect(copy.groups[0].id != split.id)
    }

    @Test @MainActor func originalValuesStayUnchanged() throws {
        let copied = try #require(makeCopy().applying(to: state))
        #expect(copied.tabs.prefix(state.tabs.count).elementsEqual(state.tabs))
        #expect(copied.folders.prefix(state.folders.count - 1).elementsEqual(state.folders.dropLast()))
        #expect(copied.splitLayouts.first == split)
    }

    @Test @MainActor func noCopiedPageSelectionIsForgedAndTheOriginalSpaceStaysCurrent() throws {
        let copied = try #require(makeCopy().applying(to: state))
        #expect(copied.selectedTabIDs == state.selectedTabIDs)
        #expect(copied.selectionBySpace == state.selectionBySpace)
        #expect(copied.activeSpaceID == state.activeSpaceID)
    }

    @Test @MainActor func copiesLandPinnedInTheExactDestinationProfileAndSpace() {
        #expect(makeCopy().tabs.allSatisfy { $0.profileID == profile.id && $0.spaceID == away.id && $0.kind == .pinned })
    }

    @Test @MainActor func copiesGetNewCreationAndUnreadMetadata() {
        #expect(makeCopy().tabs.allSatisfy { $0.createdAt == now && $0.lastAccessed == now && $0.isUnread })
    }

    @Test @MainActor func noOriginalArchiveIdentityLeaks() {
        #expect(makeCopy().tabs.allSatisfy { $0.archivedAt == nil && $0.archiveProvenance == nil })
    }

    @Test @MainActor func theResolvedOriginalNativeURLIsRetained() {
        let copy = makeCopy()
        #expect(copy.tabs[0].savedURL == destinations[ordinary.id])
        #expect(copy.tabs[0].url == destinations[ordinary.id])
    }

    @Test @MainActor func theOriginalSavedCustomAndMutePresentationIsRetained() {
        let copy = makeCopy()
        #expect(copy.tabs[0].title == ordinary.savedTitle)
        #expect(copy.tabs[0].customTitle == ordinary.customTitle)
        #expect(copy.tabs[0].isMuted)
    }

    @Test @MainActor func aFavoriteCopyUsesTheActualResolvedDestination() {
        #expect(makeCopy().tabs[1].savedURL == destinations[favorite.id])
    }

    @Test @MainActor func splitTitleOrientationAndProportionsAreRetained() {
        let group = makeCopy().groups[0]
        #expect(group.customTitle == split.customTitle)
        #expect(group.orientation == split.orientation)
        #expect(group.widthFactors == split.widthFactors)
    }

    @Test @MainActor func groupChildrenUseTheExactNewIDsAndTheAnchorMapsToItsCopiedChild() {
        let copy = makeCopy()
        #expect(copy.groups[0].tabIDs == Array(copy.tabs.suffix(2).map(\.id)))
        #expect(copy.groups[0].sidebarAnchorID == copy.tabs[3].id)
    }

    @Test @MainActor func theNestedParentMapFollowsTheOriginalHierarchyAndDisclosure() {
        let copy = makeCopy()
        #expect(copy.folders[0].parentID == destination.id)
        #expect(copy.folders[1].parentID == copy.folders[0].id)
        #expect(copy.folders.allSatisfy { !$0.isExpanded })
    }

    @Test @MainActor func originalChildContainersAreMapped() {
        let copy = makeCopy()
        #expect(copy.tabs[2].folderID == copy.folders[0].id)
        #expect(copy.tabs[3].folderID == copy.folders[1].id)
    }

    @Test @MainActor func topLevelDirectTabsAndNestedSplitChildrenOpenEagerlyWhileAFolderChildIsSavedOnly() {
        let copy = makeCopy()
        #expect(copy.openTabIDs == [copy.tabs[0].id, copy.tabs[1].id, copy.tabs[3].id, copy.tabs[4].id])
    }

    @Test @MainActor func theOriginalRootOrderIsAppendedIntoTheTarget() throws {
        let copy = makeCopy()
        let copied = try #require(copy.applying(to: state))
        #expect(SidebarHierarchy.children(in: .init(spaceID: away.id, folderID: destination.id, section: .pinned), state: copied) == copy.roots)
    }

    @Test @MainActor func theStoredSplitAnchorNormalizesToTheExactCopiedGroup() throws {
        let copy = makeCopy()
        let copied = try #require(copy.applying(to: state))
        let location = SidebarContainerLocation(spaceID: away.id, folderID: copy.folders[1].id, section: .pinned)
        #expect(SidebarHierarchy.children(in: location, state: copied) == [.split(copy.groups[0].id)])
    }

    @Test @MainActor func oneProposalNeverDuplicatesIDsTwice() throws {
        let copy = makeCopy()
        let copied = try #require(copy.applying(to: state))
        #expect(copy.applying(to: copied) == nil)
    }

    enum BadDestination: CaseIterable { case missing, foreign, document }

    @Test(arguments: BadDestination.allCases)
    @MainActor func theProposalNeedsExactlyTheOriginalWebDestinations(problem: BadDestination) {
        var wrong = destinations
        switch problem {
        case .missing: wrong.removeValue(forKey: ordinary.id)
        case .foreign: wrong[UUID()] = "https://extra.invalid/"
        case .document: wrong[ordinary.id] = "parc://note/" + UUID().uuidString
        }
        #expect(CommandBarFolderCopy(move: move, destinations: wrong, state: state, now: now) == nil)
    }

    @Test @MainActor func aReplacedOriginalExpiresTheProposal() {
        var changed = state
        changed.tabs[0].createdAt.addTimeInterval(1)
        #expect(makeCopy().applying(to: changed) == nil)
    }

    @Test @MainActor func unrelatedLiveNavigationIsNotAnIdentityReplacement() {
        var changed = state
        changed.tabs[0].url = "https://new-live.invalid/"
        #expect(makeCopy().applying(to: changed) != nil)
    }

    @Test @MainActor func aRemovedOriginalDestinationExpiresTheProposal() {
        var changed = state
        changed.folders.removeLast()
        #expect(makeCopy().applying(to: changed) == nil)
    }

    @Test @MainActor func aMixedTypedSubtreeRefusesAtomicallyEvenWithASuppliedURL() throws {
        var changed = state
        changed.tabs[2].savedURL = "parc://easel/" + UUID().uuidString
        let typedSource = try #require(CommandBarFolderMoveSource(items: [.folder(folder.id)], spaceID: space.id,
                                                                  profileID: profile.id, state: changed))
        let typedMove = try #require(CommandBarFolderMove.snapshot(source: typedSource, state: changed).first { $0.folder.folderID == destination.id })
        let typedURLs = Dictionary(uniqueKeysWithValues: typedSource.tabIDs.map { ($0, "https://unrelated.invalid") })
        #expect(CommandBarFolderCopy(move: typedMove, destinations: typedURLs, state: changed, now: now) == nil)
    }

    @Test @MainActor func theIndexedFirstFivePolicyDoesNotCapDurableCopies() throws {
        var many = state
        many.tabs = (0..<7).map { Self.tab("root\($0)", space: space.id, profile: profile.id) }
        many.splitLayouts = []
        let manySource = try #require(CommandBarFolderMoveSource(items: many.tabs.map { .tab($0.id) }, spaceID: space.id,
                                                                 profileID: profile.id, state: many))
        let manyMove = try #require(CommandBarFolderMove.snapshot(source: manySource, state: many).first { $0.folder.folderID == destination.id })
        let manyURLs = Dictionary(uniqueKeysWithValues: many.tabs.map { ($0.id, $0.savedURL) })
        let manyCopy = try #require(CommandBarFolderCopy(move: manyMove, destinations: manyURLs, state: many, now: now))
        #expect(manyCopy.tabs.count == 7)
        #expect(manyCopy.openTabIDs == Array(manyCopy.tabs.prefix(5).map(\.id)))
    }

    @MainActor func persistedStore(in directory: URL) throws -> BrowserStore {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(state).write(to: directory.appendingPathComponent("session.json"))
        return try BrowserStore(directory: directory, now: { now })
    }

    @MainActor func storedMove(_ store: BrowserStore) throws -> CommandBarFolderMove {
        let storedSource = try #require(CommandBarFolderMoveSource(items: source.roots, spaceID: space.id,
                                                                   profileID: profile.id, state: store.state))
        return try #require(CommandBarFolderMove.snapshot(source: storedSource, state: store.state).first { $0.folder.folderID == destination.id })
    }

    @Test @MainActor func copiedTabsFoldersAndSplitsDurablyReloadAndOriginalsSurviveUnchanged() throws {
        let directory = CommandBarFixtures.temporaryDirectory("folder-copy")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try persistedStore(in: directory)
        let saved = try #require(try store.copyCommandBarItemsToFolder(try storedMove(store), destinations: destinations))
        let reopened = try BrowserStore(directory: directory)
        #expect(saved.tabs.allSatisfy { tab in reopened.state.tabs.contains(tab) })
        #expect(saved.folders.allSatisfy { folder in reopened.state.folders.contains(folder) })
        #expect(saved.groups.allSatisfy { group in reopened.state.splitLayouts.contains(group) })
        #expect(reopened.state.tabs.filter { source.tabIDs.contains($0.id) } == state.tabs)
    }

    @Test @MainActor func aFailedWritePublishesNoNewOriginalOrCopiedIdentity() throws {
        let directory = CommandBarFixtures.temporaryDirectory("folder-copy")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try persistedStore(in: directory)
        let retry = try storedMove(store)
        let before = store.state
        try FileManager.default.removeItem(at: directory)
        try Data("not-directory".utf8).write(to: directory)
        var threw = false
        do { _ = try store.copyCommandBarItemsToFolder(retry, destinations: destinations) } catch { threw = true }
        #expect(threw)
        #expect(store.state == before)
    }
}
