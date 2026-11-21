import Foundation
import Testing
@testable import ParcCore

struct SidebarSpaceMoveTests {
    var state = BrowserState.initial()
    let source: BrowserSpace
    let destination: BrowserSpace
    let folder: BrowserFolder
    let nested: BrowserFolder
    let a: BrowserTab, b: BrowserTab, c: BrowserTab
    let today: BrowserTab, pinned: BrowserTab, existing: BrowserTab, favorite: BrowserTab
    let group: BrowserSplitLayout
    let from: SidebarHierarchySnapshot
    let to: SidebarHierarchySnapshot
    let move: SidebarSpaceMove
    let expectedGroup: BrowserSplitLayout

    static func location(_ space: UUID, _ parent: UUID?, _ kind: TabKind = .pinned) -> SidebarContainerLocation {
        .init(spaceID: space, folderID: parent, section: kind)
    }

    func location(_ space: UUID, _ parent: UUID?, _ kind: TabKind = .pinned) -> SidebarContainerLocation {
        Self.location(space, parent, kind)
    }

    init() {
        var state = BrowserState.initial()
        let source = state.spaces[0]
        let destination = BrowserSpace(id: UUID(), name: "Work", symbol: "circle", color: "112233", profileID: source.profileID)
        state.spaces.append(destination)
        let folder = BrowserFolder(id: UUID(), spaceID: source.id, name: "Tree", parentID: nil, isExpanded: false)
        let nested = BrowserFolder(id: UUID(), spaceID: source.id, name: "Nested", parentID: folder.id, isExpanded: true)
        func tab(_ space: UUID, _ kind: TabKind, _ parent: UUID? = nil) -> BrowserTab {
            .init(id: UUID(), spaceID: space, profileID: source.profileID, url: "https://example.test/live", title: "Live",
                  kind: kind, folderID: parent, createdAt: Date(timeIntervalSince1970: 1), lastAccessed: Date(timeIntervalSince1970: 2),
                  savedURL: "https://example.test/saved", savedTitle: "Saved", isMuted: true, isUnread: true)
        }
        let a = tab(source.id, .pinned, nested.id), b = tab(source.id, .pinned, nested.id)
        let c = tab(source.id, .pinned, folder.id), today = tab(source.id, .today), pinned = tab(source.id, .pinned)
        let existing = tab(destination.id, .pinned), favorite = tab(source.id, .favorite)
        state.tabs = [a, b, c, today, pinned, existing, favorite]
        state.folders = [folder, nested]
        let group = BrowserSplitLayout(id: UUID(), sidebarAnchorID: b.id, spaceID: source.id, tabIDs: [a.id, b.id],
                                       orientation: .horizontal, widthFactors: [0.3, 0.7], stacks: nil)
        state.splitLayouts = [group]
        state.activeSpaceID = source.id
        state.selectedTabIDs = group.tabIDs
        state.selectionBySpace = [source.id.uuidString: group.tabIDs, destination.id.uuidString: [existing.id]]
        state.sidebarItemOrder[Self.location(source.id, nil).key] = [.folder(folder.id), .tab(pinned.id)]
        state.sidebarItemOrder[Self.location(source.id, folder.id).key] = [.folder(nested.id), .tab(c.id)]
        state.sidebarItemOrder[Self.location(source.id, nested.id).key] = [.tab(b.id)]
        let from = SidebarHierarchySnapshot(state: state, spaceID: source.id, profileID: source.profileID)!
        let to = SidebarHierarchySnapshot(state: state, spaceID: destination.id, profileID: source.profileID)!
        move = SidebarSpaceMove(items: [.folder(folder.id), .split(group.id), .tab(today.id)], from: from, to: to, state: state)!
        var expectedGroup = group
        expectedGroup.spaceID = destination.id
        self.expectedGroup = expectedGroup
        self.state = state
        self.source = source; self.destination = destination
        self.folder = folder; self.nested = nested
        self.a = a; self.b = b; self.c = c
        self.today = today; self.pinned = pinned; self.existing = existing; self.favorite = favorite
        self.group = group
        self.from = from; self.to = to
    }

    func proposed(_ original: BrowserState, _ roots: [SidebarItemReference]) -> SidebarSpaceMove? {
        guard let from = SidebarHierarchySnapshot(state: original, spaceID: source.id, profileID: source.profileID),
              let to = SidebarHierarchySnapshot(state: original, spaceID: destination.id, profileID: source.profileID) else { return nil }
        return SidebarSpaceMove(items: roots, from: from, to: to, state: original)
    }

    func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    func directory(writing state: BrowserState) throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("parc-space-move-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try encoder().encode(state).write(to: directory.appendingPathComponent("session.json"))
        return directory
    }

    var moved: BrowserState { move.applying(to: state)! }

    @Test func anAncestorAbsorbsSelectedDescendants() {
        #expect(move.roots == [.folder(folder.id), .tab(today.id)])
    }

    @Test func theWholeTreeAndSplitChildrenAreRetained() {
        #expect(Set(move.tabIDs) == Set([a.id, b.id, c.id, today.id]))
    }

    @Test func movingMakesNoCopiesAndDeletesNothing() {
        let moved = moved
        #expect(moved.tabs.count == state.tabs.count)
        #expect(moved.folders.count == state.folders.count)
    }

    @Test func allOriginalNavigationSavedKindAndLifetimeMetadataIsRetained() {
        let moved = moved
        for original in state.tabs {
            var expected = original
            if move.tabIDs.contains(original.id) { expected.spaceID = destination.id }
            #expect(moved.tabs.first { $0.id == original.id } == expected)
        }
    }

    @Test func theOriginalGroupIdentityAnchorOrientationAndWeightsSurvive() {
        #expect(moved.splitLayouts == [expectedGroup])
    }

    @Test func nestedParentsAndCollapsedStateSurvive() {
        let moved = moved
        #expect(moved.folders.first { $0.id == nested.id }?.parentID == folder.id)
        #expect(moved.folders.first { $0.id == folder.id }?.isExpanded == false)
    }

    @Test func movedRootsAppendToTheDestinationSiblingOrder() {
        #expect(SidebarHierarchy.children(in: location(destination.id, nil), state: moved) == [.tab(existing.id), .folder(folder.id)])
    }

    @Test func mixedFolderOrderMigrates() {
        #expect(SidebarHierarchy.children(in: location(destination.id, folder.id), state: moved) == [.folder(nested.id), .tab(c.id)])
    }

    @Test func aSplitAnchorProjectsToTheWholeGroup() {
        #expect(SidebarHierarchy.children(in: location(destination.id, nested.id), state: moved) == [.split(group.id)])
    }

    @Test func theOldNestedOrderKeyIsRemoved() {
        #expect(moved.sidebarItemOrder[location(source.id, nested.id).key] == nil)
    }

    @Test func theSourceCannotSelectMovedItems() {
        let moved = moved
        #expect(moved.selectedTabIDs.isEmpty)
        #expect(moved.selectionBySpace[source.id.uuidString] == [])
    }

    @Test func aMoveCannotStealTheDestinationsCurrentSelection() {
        #expect(moved.selectionBySpace[destination.id.uuidString] == [existing.id])
    }

    @Test func oneSnapshotCannotMoveTwice() {
        #expect(move.applying(to: moved) == nil)
    }

    @Test func aChangedOriginalTreeRefusesAStaleMenu() {
        var stale = state
        stale.folders[0].name = "Changed"
        #expect(move.applying(to: stale) == nil)
    }

    @Test func aChangedDestinationOrderRefusesAStaleMenu() {
        var stale = state
        stale.sidebarItemOrder[location(destination.id, nil).key] = [.tab(existing.id)]
        #expect(move.applying(to: stale) == nil)
    }

    @Test func liveNavigationMetadataIsNotOverwritten() {
        var stale = state
        stale.tabs[0].title = "New page title"
        #expect(move.applying(to: stale)?.tabs[0].title == "New page title")
    }

    @Test func crossProfileRelocationCarriesTheDestinationProfile() {
        var foreign = state
        let other = BrowserProfile(id: UUID(), name: "Other")
        foreign.profiles.append(other)
        foreign.spaces[1].profileID = other.id
        foreign.tabs[5].profileID = other.id
        let foreignTo = SidebarHierarchySnapshot(state: foreign, spaceID: destination.id, profileID: other.id)!
        let crossProfile = SidebarSpaceMove(items: [.folder(folder.id)], from: from, to: foreignTo, state: foreign)
        #expect(crossProfile?.crossesProfiles == true)
        #expect(crossProfile?.applying(to: foreign)?.tabs.first { $0.id == c.id }?.profileID == other.id)
    }

    @Test func aProfileWideFavoriteIsNotASpaceItem() {
        #expect(SidebarSpaceMove(items: [.tab(favorite.id)], from: from, to: to, state: state) == nil)
    }

    @Test func oneSplitChildCannotBeSilentlyDetached() {
        #expect(SidebarSpaceMove(items: [.tab(a.id)], from: from, to: to, state: state) == nil)
    }

    @Test func aFolderHoldingOnlyANonAnchorSplitChildRefusesPartialGroupMovement() {
        var mixed = state
        mixed.tabs[1].folderID = nil
        let mixedFrom = SidebarHierarchySnapshot(state: mixed, spaceID: source.id, profileID: source.profileID)!
        #expect(SidebarSpaceMove(items: [.folder(folder.id)], from: mixedFrom, to: to, state: mixed) == nil)
    }

    @Test func aStandaloneNestedTabBecomesADestinationRoot() throws {
        let single = try #require(SidebarSpaceMove(items: [.tab(c.id)], from: from, to: to, state: state)?.applying(to: state))
        #expect(single.tabs.first { $0.id == c.id }?.folderID == nil)
    }

    @Test func revealOpensTheActualFolder() throws {
        let folderReveal = try #require(SidebarItemReveal(item: .folder(folder.id), spaceID: destination.id,
                                                          profileID: source.profileID, state: moved))
        #expect(folderReveal.expandedFolderIDs == [folder.id])
    }

    @Test func anEmptyTargetRevealsItsAncestorsWithoutAnExpansionEffect() throws {
        var withEmpty = moved
        let empty = BrowserFolder(id: UUID(), spaceID: destination.id, name: "Empty", parentID: folder.id, isExpanded: false)
        withEmpty.folders.append(empty)
        let emptyReveal = try #require(SidebarItemReveal(item: .folder(empty.id), spaceID: destination.id,
                                                         profileID: source.profileID, state: withEmpty))
        #expect(emptyReveal.expandedFolderIDs == [folder.id])
        #expect(emptyReveal.applying(to: withEmpty)?.folders.last?.isExpanded == false)
    }

    @Test func aWholeSplitRevealExpandsTheExactAncestors() throws {
        let reveal = try #require(SidebarItemReveal(item: .split(group.id), spaceID: destination.id,
                                                    profileID: source.profileID, state: moved))
        #expect(reveal.expandedFolderIDs == [folder.id, nested.id])
        let revealed = try #require(reveal.applying(to: moved))
        #expect(revealed.folders.filter { reveal.expandedFolderIDs.contains($0.id) }.allSatisfy { $0.isExpanded })
    }

    @Test func revealCannotAlterPageOrSplitRecordsAndIsDistinctFromActivation() throws {
        let moved = moved
        let reveal = try #require(SidebarItemReveal(item: .split(group.id), spaceID: destination.id,
                                                    profileID: source.profileID, state: moved))
        let revealed = try #require(reveal.applying(to: moved))
        #expect(revealed.tabs == moved.tabs)
        #expect(revealed.splitLayouts == moved.splitLayouts)
        #expect(revealed.selectedTabIDs == moved.selectedTabIDs)
        #expect(revealed.selectionBySpace == moved.selectionBySpace)
    }

    @Test func aStaleSourceSpaceCannotRevealAMovedItem() {
        #expect(SidebarItemReveal(item: .folder(folder.id), spaceID: source.id, profileID: source.profileID, state: moved) == nil)
    }

    @Test func aFavoriteIsNotAMovedSpaceItemForReveal() {
        #expect(SidebarItemReveal(item: .tab(favorite.id), spaceID: destination.id, profileID: source.profileID, state: moved) == nil)
    }

    @Test func changedRevealAncestryRefusesAStaleTransaction() throws {
        let moved = moved
        let reveal = try #require(SidebarItemReveal(item: .split(group.id), spaceID: destination.id,
                                                    profileID: source.profileID, state: moved))
        var changedParent = moved
        changedParent.folders[1].parentID = nil
        #expect(reveal.applying(to: changedParent) == nil)
    }

    @Test func anUnmaterializedWholeSplitCanMove() {
        #expect(move.permitsSplitOwners([:], in: UUID()))
    }

    @Test func theOriginalPhysicalOwnerRetainsTheWholeSplit() {
        let window = UUID()
        #expect(move.permitsSplitOwners([a.id: window, b.id: window], in: window))
    }

    @Test func aForeignPhysicalSplitOwnerIsRefused() {
        let window = UUID(), other = UUID()
        #expect(!move.permitsSplitOwners([a.id: other, b.id: other], in: window))
    }

    @Test func mixedPhysicalSplitOwnersAreRefusedAsAWhole() {
        let window = UUID(), other = UUID()
        #expect(!move.permitsSplitOwners([a.id: window, b.id: other], in: window))
    }

    @MainActor @Test func spaceNavigationAfterTheMoveRestoresTheWholeSplitAndFocus() {
        let owner = NativePageOwnership(), originalWindow = UUID()
        #expect(owner.claim(a.id, owner: originalWindow, page: "original-a"))
        #expect(owner.claim(b.id, owner: originalWindow, page: "original-b"))
        let claim = owner.claimSnapshot(a.id)
        let moved = moved
        var presentation = WindowPresentation(state: state, ready: true)
        presentation.reconcile(moved) { owner.canUse($0, owner: originalWindow) }
        #expect(presentation.selectedTabIDs.isEmpty)
        presentation.selectSpace(destination.id, state: moved) { owner.canUse($0, owner: originalWindow) }
        let selected = presentation.selectExistingTab(b.id, state: moved, available: { owner.canUse($0, owner: originalWindow) })
        #expect(selected)
        presentation.recordFocusedTab(b.id)
        #expect(presentation.selectedTabIDs == group.tabIDs)
        #expect(presentation.preferredFocusedTabID == b.id)
        #expect(owner.claimSnapshot(a.id) == claim)
    }

    @MainActor @Test func aMoveDoesNotSilentlyAdoptAnotherPhysicalOwnersPage() {
        let owner = NativePageOwnership(), originalWindow = UUID(), otherWindow = UUID()
        #expect(owner.claim(a.id, owner: originalWindow, page: "original-a"))
        #expect(!owner.canUse(a.id, owner: otherWindow))
    }

    @MainActor @Test func anInProgressTransferInvalidatesTheOwnerSnapshotAndACancelledOneKeepsTheOwner() throws {
        let owner = NativePageOwnership(), originalWindow = UUID(), otherWindow = UUID()
        #expect(owner.claim(a.id, owner: originalWindow, page: "original-a"))
        let transfer = try #require(owner.reserveTransfer(a.id, page: "original-a", from: originalWindow, to: otherWindow))
        #expect(owner.claimSnapshot(a.id).transfer == transfer)
        #expect(owner.finishTransfer(transfer, moved: false))
    }

    @MainActor @Test func theAtomicStoreMoveCommitsAndPersists() throws {
        let directory = try directory(writing: state)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try BrowserStore(directory: directory)
        #expect(try store.moveSidebarItemsAcrossSpaces(move))
        let reopened = try BrowserStore(directory: directory)
        #expect(reopened.state.tabs.first { $0.id == a.id }?.spaceID == destination.id)
        #expect(reopened.state.splitLayouts.contains(expectedGroup))
    }

    @MainActor @Test func theActualRevealPersistsDisclosureWithoutSelectingAMovedPage() throws {
        let directory = try directory(writing: state)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try BrowserStore(directory: directory)
        _ = try store.moveSidebarItemsAcrossSpaces(move)
        let reopened = try BrowserStore(directory: directory)
        let reveal = try #require(SidebarItemReveal(item: .split(group.id), spaceID: destination.id,
                                                    profileID: source.profileID, state: moved))
        let selectionBeforeReveal = reopened.state.selectedTabIDs
        #expect(try reopened.revealSidebarItem(reveal))
        #expect(reopened.state.folders.first { $0.id == folder.id }?.isExpanded == true)
        #expect(reopened.state.selectedTabIDs == selectionBeforeReveal)
    }

    @MainActor @Test func aFailedWriteCannotPublishAPartialHierarchy() throws {
        let directory = try directory(writing: state)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("session.json")
        let failing = try BrowserStore(directory: directory)
        let prior = failing.state
        try FileManager.default.removeItem(at: file)
        try FileManager.default.createDirectory(at: file, withIntermediateDirectories: false)
        #expect(throws: (any Error).self) { try failing.moveSidebarItemsAcrossSpaces(move) }
        #expect(failing.state == prior)
    }

    struct MixedSections {
        let original: BrowserState
        let proposal: SidebarSpaceMove
        let result: BrowserState
        let kind: TabKind
    }

    func mixedSections(_ anchorKind: TabKind) -> MixedSections {
        var original = state
        original.tabs[0].kind = anchorKind == .pinned ? .today : .pinned
        original.tabs[0].folderID = anchorKind == .pinned ? nil : nested.id
        original.tabs[1].kind = anchorKind
        original.tabs[1].folderID = nil
        original.sidebarItemOrder[location(source.id, nil, .today).key] = [.tab(a.id), .tab(b.id), .tab(today.id)]
        original.sidebarItemOrder[location(source.id, nested.id).key] = [.tab(a.id), .tab(b.id)]
        original.sidebarItemOrder[location(source.id, nil).key] = [.folder(folder.id), .tab(b.id), .tab(pinned.id)]
        let proposal = proposed(original, [.split(group.id)])!
        return MixedSections(original: original, proposal: proposal, result: proposal.applying(to: original)!, kind: anchorKind)
    }

    @Test(arguments: [TabKind.pinned, .today])
    func mixedSectionsCaptureEveryOriginalChildOnce(anchorKind: TabKind) {
        let mixed = mixedSections(anchorKind)
        #expect(mixed.proposal.tabIDs == group.tabIDs)
        #expect(mixed.proposal.groupIDs == [group.id])
    }

    @Test(arguments: [TabKind.pinned, .today])
    func onlyExplicitContainerPlacementChangesInAMixedSectionMove(anchorKind: TabKind) {
        let mixed = mixedSections(anchorKind)
        for i in mixed.original.tabs.indices {
            var expected = mixed.original.tabs[i]
            if group.tabIDs.contains(expected.id) {
                expected.spaceID = destination.id
                expected.folderID = nil
                expected.kind = anchorKind
            }
            #expect(mixed.result.tabs[i] == expected)
        }
    }

    @Test(arguments: [TabKind.pinned, .today])
    func aMixedSectionMoveKeepsTheGroupAndLeavesSourceFoldersAlone(anchorKind: TabKind) {
        let mixed = mixedSections(anchorKind)
        #expect(mixed.result.splitLayouts == [expectedGroup])
        #expect(mixed.result.folders == mixed.original.folders)
        #expect(SidebarHierarchySnapshot(state: mixed.result, spaceID: destination.id, profileID: source.profileID) != nil)
    }

    @Test(arguments: [TabKind.pinned, .today])
    func theAnchoredGroupAppendsInItsOwnProjectedSection(anchorKind: TabKind) {
        let mixed = mixedSections(anchorKind)
        let destinationChildren = SidebarHierarchy.children(in: location(destination.id, nil, anchorKind), state: mixed.result)
        #expect(destinationChildren.last == .split(group.id))
    }

    @Test(arguments: [TabKind.pinned, .today])
    func noDormantSourceReferencesSurviveAMixedSectionMove(anchorKind: TabKind) {
        let mixed = mixedSections(anchorKind)
        let sourceOrders = mixed.result.sidebarItemOrder.filter { $0.key.hasPrefix(source.id.uuidString + ":") }
        let sourceReferences = Set(sourceOrders.values.flatMap { $0 })
        #expect(sourceReferences.isDisjoint(with: [.tab(a.id), .tab(b.id), .split(group.id)]))
    }

    @Test(arguments: [TabKind.pinned, .today])
    func laterSeparationKeepsBothOriginalsAtTheDestination(anchorKind: TabKind) {
        var separated = mixedSections(anchorKind).result
        separated.splitLayouts = []
        let children = SidebarHierarchy.children(in: location(destination.id, nil, anchorKind), state: separated)
        #expect(children.contains(.tab(a.id)))
        #expect(children.contains(.tab(b.id)))
    }

    @Test(arguments: [TabKind.pinned, .today])
    func mixedPlacementDoesNotWeakenWholeGroupPhysicalOwnership(anchorKind: TabKind) {
        let window = UUID(), other = UUID()
        #expect(!mixedSections(anchorKind).proposal.permitsSplitOwners([a.id: window, b.id: other], in: window))
    }

    @Test(arguments: [TabKind.pinned, .today])
    func aMixedPlacementChildCannotMoveByItself(anchorKind: TabKind) {
        #expect(proposed(mixedSections(anchorKind).original, [.tab(a.id)]) == nil)
    }

    @Test(arguments: [TabKind.pinned, .today])
    func changedChildPlacementOrGeometryRevokesTheReceipt(anchorKind: TabKind) {
        let mixed = mixedSections(anchorKind)
        var changed = mixed.original
        changed.tabs[0].folderID = folder.id
        #expect(mixed.proposal.applying(to: changed) == nil)
        changed = mixed.original
        changed.splitLayouts[0].widthFactors = [0.6, 0.4]
        #expect(mixed.proposal.applying(to: changed) == nil)
    }

    @Test(arguments: [TabKind.pinned, .today])
    func aMixedFavoriteAndOrdinaryGroupRemainsRefused(anchorKind: TabKind) {
        var changed = mixedSections(anchorKind).original
        changed.tabs[0].kind = .favorite
        changed.tabs[0].folderID = nil
        #expect(proposed(changed, [.split(group.id)]) == nil)
    }

    struct NestedMixed {
        let state: BrowserState
        let outside: BrowserFolder
        let move: SidebarSpaceMove
        let result: BrowserState
    }

    func nestedMixed() -> NestedMixed {
        var nestedMixed = state
        let outside = BrowserFolder(id: UUID(), spaceID: source.id, name: "Stays", parentID: nil, isExpanded: false)
        nestedMixed.folders.append(outside)
        nestedMixed.tabs[0].folderID = outside.id
        nestedMixed.tabs[0].url = InternalPage.note(URL(fileURLWithPath: NSTemporaryDirectory() + "Parc Notes/" + UUID().uuidString + ".md")).urlString
        nestedMixed.tabs[0].savedURL = nestedMixed.tabs[0].url
        nestedMixed.tabs[1].url = InternalPage.easel(UUID()).urlString
        nestedMixed.tabs[1].savedURL = nestedMixed.tabs[1].url
        nestedMixed.sidebarItemOrder[location(source.id, outside.id).key] = [.tab(a.id)]
        nestedMixed.sidebarItemOrder[location(source.id, nested.id).key] = [.tab(b.id)]
        let nestedMove = proposed(nestedMixed, [.folder(folder.id)])!
        return NestedMixed(state: nestedMixed, outside: outside, move: nestedMove, result: nestedMove.applying(to: nestedMixed)!)
    }

    @Test func movingAnAnchorAncestorIncludesTheOutsideChildAsPartOfTheWholeGroup() {
        let nested = nestedMixed()
        #expect(Set(nested.move.tabIDs) == Set([a.id, b.id, c.id]))
        #expect(nested.move.groupIDs == [group.id])
    }

    @Test func theMoveDoesNotPullInTheNonAnchorChildsFormerFolder() {
        #expect(nestedMixed().move.folderIDs == [folder.id, nested.id])
    }

    @Test func theWholeGroupNestsInTheMovedOriginalAnchorFolder() {
        let mixed = nestedMixed()
        #expect(mixed.result.tabs[0].folderID == nested.id)
        #expect(mixed.result.tabs[1].folderID == nested.id)
    }

    @Test func noteAndEaselReferencesAreUnchanged() {
        let mixed = nestedMixed()
        #expect(mixed.result.tabs[0].savedURL == mixed.state.tabs[0].savedURL)
        #expect(mixed.result.tabs[1].savedURL == mixed.state.tabs[1].savedURL)
    }

    @Test func anUnselectedOutsideFolderStaysInTheOriginalSpaceAndLosesItsDormantEntry() {
        let mixed = nestedMixed()
        #expect(mixed.result.folders.last == mixed.outside)
        #expect(mixed.result.sidebarItemOrder[location(source.id, mixed.outside.id).key] == [])
    }

    @Test func theNestedGroupRetainsOneMixedOrderSlotAndSiblingOrderSurvives() {
        let mixed = nestedMixed()
        #expect(SidebarHierarchy.children(in: location(destination.id, nested.id), state: mixed.result) == [.split(group.id)])
        #expect(SidebarHierarchy.children(in: location(destination.id, folder.id), state: mixed.result) == [.folder(nested.id), .tab(c.id)])
    }

    @Test func noSourceOnlyFolderReferenceCrossesIntoTheDestination() {
        #expect(SidebarHierarchySnapshot(state: nestedMixed().result, spaceID: destination.id, profileID: source.profileID) != nil)
    }

    @Test func aFolderHoldingOnlyAHiddenNonAnchorChildCannotSplitTheGroup() {
        let mixed = nestedMixed()
        #expect(proposed(mixed.state, [.folder(mixed.outside.id)]) == nil)
    }

    @Test func explicitRootsIncludeTheGroupOnceEvenWhenAnOldChildFolderAlsoMoves() throws {
        let mixed = nestedMixed()
        let both = try #require(proposed(mixed.state, [.folder(mixed.outside.id), .split(group.id)]))
        let bothResult = try #require(both.applying(to: mixed.state))
        #expect(Set(both.tabIDs) == Set(group.tabIDs))
        #expect(both.folderIDs == [mixed.outside.id])
        #expect(bothResult.tabs[0].folderID == nil)
        #expect(bothResult.tabs[1].folderID == nil)
        #expect(SidebarHierarchy.children(in: location(destination.id, nil), state: bothResult)
                == [.tab(existing.id), .folder(mixed.outside.id), .split(group.id)])
    }

    @Test func aNewSpaceDraftSuppliesAllOriginalChildrenToTheSameWindowOwnerGates() throws {
        let mixed = nestedMixed()
        let nestedFrom = SidebarHierarchySnapshot(state: mixed.state, spaceID: source.id, profileID: source.profileID)!
        var draft = try #require(SidebarNewSpaceDraft(items: [.folder(folder.id)], from: nestedFrom, state: mixed.state))
        draft.name = "Original group"
        #expect(Set(draft.tabIDs) == Set(mixed.move.tabIDs))
        #expect(draft.groupIDs == mixed.move.groupIDs)
    }

    @Test func aNewSpaceConsumesTheCompleteNestedGroupMoveAndKeepsSplitIdentityAndInsertion() throws {
        let mixed = nestedMixed()
        let nestedFrom = SidebarHierarchySnapshot(state: mixed.state, spaceID: source.id, profileID: source.profileID)!
        var draft = try #require(SidebarNewSpaceDraft(items: [.folder(folder.id)], from: nestedFrom, state: mixed.state))
        draft.name = "Original group"
        let result = try #require(draft.applying(to: mixed.state))
        #expect(result.tabs[0].spaceID == draft.spaceID)
        #expect(result.tabs[0].folderID == nested.id)
        #expect(result.splitLayouts[0].id == group.id)
        #expect(result.splitLayouts[0].spaceID == draft.spaceID)
        #expect(result.spaces.firstIndex { $0.id == draft.spaceID } == result.spaces.firstIndex { $0.id == source.id }! + 1)
    }

    @Test func aRefusedDraftCannotPersistAnEmptySpace() throws {
        let mixed = nestedMixed()
        let nestedFrom = SidebarHierarchySnapshot(state: mixed.state, spaceID: source.id, profileID: source.profileID)!
        var cancelled = try #require(SidebarNewSpaceDraft(items: [.folder(folder.id)], from: nestedFrom, state: mixed.state))
        cancelled.name = ""
        #expect(cancelled.applying(to: mixed.state) == nil)
        #expect(mixed.state.spaces.count == state.spaces.count)
    }

    @MainActor @Test func theActualStoreAcceptsTheCompleteMixedGroupTransactionAndReloadsNormalizedPlacement() throws {
        let mixed = nestedMixed()
        let directory = try directory(writing: mixed.state)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try BrowserStore(directory: directory)
        let actualMove = try #require(proposed(store.state, [.folder(folder.id)]))
        #expect(try store.moveSidebarItemsAcrossSpaces(actualMove))
        let persisted = try BrowserStore(directory: directory)
        #expect(persisted.state.tabs[0].folderID == nested.id)
        #expect(persisted.state.tabs[0].spaceID == destination.id)
        #expect(persisted.state.tabs[0].savedURL == mixed.state.tabs[0].savedURL)
    }

    @MainActor @Test func theActualNewSpaceCommandCommitsTheMixedGroupWithoutRecreatingIt() throws {
        let mixed = nestedMixed()
        let directory = try directory(writing: mixed.state)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try BrowserStore(directory: directory)
        let storeFrom = SidebarHierarchySnapshot(state: store.state, spaceID: source.id, profileID: source.profileID)!
        var storeDraft = try #require(SidebarNewSpaceDraft(items: [.split(group.id)], from: storeFrom, state: store.state))
        storeDraft.name = "One transaction"
        let created = try store.createSpaceAndMoveSidebarItems(storeDraft)
        #expect(created == storeDraft.spaceID)
        let persisted = try BrowserStore(directory: directory)
        #expect(persisted.state.tabs[0].spaceID == created)
        #expect(persisted.state.tabs[0].folderID == nil)
        #expect(persisted.state.splitLayouts[0].id == group.id)
    }

    @MainActor @Test func failedNewSpaceAndMoveSavesPublishNothing() throws {
        let mixed = nestedMixed()
        let directory = try directory(writing: mixed.state)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("session.json")
        let failed = try BrowserStore(directory: directory)
        let before = failed.state
        let failureSource = SidebarHierarchySnapshot(state: before, spaceID: source.id, profileID: source.profileID)!
        var failureDraft = try #require(SidebarNewSpaceDraft(items: [.folder(folder.id)], from: failureSource, state: before))
        failureDraft.name = "Failure"
        try FileManager.default.removeItem(at: file)
        try FileManager.default.createDirectory(at: file, withIntermediateDirectories: false)
        #expect(throws: (any Error).self) { try failed.createSpaceAndMoveSidebarItems(failureDraft) }
        #expect(failed.state == before)
        let actualMove = try #require(proposed(before, [.folder(folder.id)]))
        #expect(throws: (any Error).self) { try failed.moveSidebarItemsAcrossSpaces(actualMove) }
        #expect(failed.state == before)
    }
}
