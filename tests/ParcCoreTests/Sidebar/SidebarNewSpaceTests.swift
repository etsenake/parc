import Foundation
import Testing
@testable import ParcCore

struct SidebarNewSpaceTests {
    var state = BrowserState.initial()
    let source: BrowserSpace
    let profile: UUID
    let other = BrowserProfile(id: UUID(), name: "Other")
    let following: BrowserSpace
    let folder: BrowserFolder
    let nested: BrowserFolder
    let a: BrowserTab, b: BrowserTab, c: BrowserTab
    let today: BrowserTab, retained: BrowserTab, favorite: BrowserTab
    let group: BrowserSplitLayout
    let snapshot: SidebarHierarchySnapshot

    static func container(_ space: UUID, _ parent: UUID? = nil, _ kind: TabKind = .pinned) -> SidebarContainerLocation {
        .init(spaceID: space, folderID: parent, section: kind)
    }

    func container(_ space: UUID, _ parent: UUID? = nil, _ kind: TabKind = .pinned) -> SidebarContainerLocation {
        Self.container(space, parent, kind)
    }

    let draft: SidebarNewSpaceDraft

    var expectedGroup: BrowserSplitLayout {
        var expected = group
        expected.spaceID = draft.spaceID
        return expected
    }

    init() {
        var state = BrowserState.initial()
        let source = state.spaces[0], profile = source.profileID
        state.profiles.append(other)
        let following = BrowserSpace(id: UUID(), name: "Following", symbol: "star", color: "112233", profileID: other.id)
        state.spaces.append(following)
        let folder = BrowserFolder(id: UUID(), spaceID: source.id, name: "Original", parentID: nil, isExpanded: false)
        let nested = BrowserFolder(id: UUID(), spaceID: source.id, name: "Nested", parentID: folder.id, isExpanded: true)
        func tab(_ kind: TabKind, _ folder: UUID? = nil) -> BrowserTab {
            BrowserTab(id: UUID(), spaceID: source.id, profileID: profile, url: "https://example.test/live",
                title: "Original", kind: kind, folderID: folder,
                createdAt: Date(timeIntervalSince1970: 1), lastAccessed: Date(timeIntervalSince1970: 2),
                savedURL: "https://example.test/saved", savedTitle: "Saved", isMuted: true, isUnread: true)
        }
        let a = tab(.pinned, nested.id), b = tab(.pinned, nested.id), c = tab(.pinned, folder.id)
        let today = tab(.today), retained = tab(.pinned), favorite = tab(.favorite)
        state.tabs = [a, b, c, today, retained, favorite]
        state.folders = [folder, nested]
        let group = BrowserSplitLayout(id: UUID(), sidebarAnchorID: b.id, customTitle: "Split", customIcon: .emoji("📚"),
            spaceID: source.id, tabIDs: [a.id, b.id], orientation: .vertical, widthFactors: [0.3, 0.7], stacks: nil)
        state.splitLayouts = [group]
        state.selectedTabIDs = group.tabIDs
        state.selectionBySpace = [source.id.uuidString: group.tabIDs]
        state.sidebarItemOrder[Self.container(source.id).key] = [.folder(folder.id), .tab(retained.id)]
        state.sidebarItemOrder[Self.container(source.id, folder.id).key] = [.tab(c.id), .folder(nested.id)]
        state.sidebarItemOrder[Self.container(source.id, nested.id).key] = [.tab(b.id)]
        let snapshot = SidebarHierarchySnapshot(state: state, spaceID: source.id, profileID: profile)!
        var draft = SidebarNewSpaceDraft(items: [.folder(folder.id), .split(group.id), .tab(today.id)], from: snapshot, state: state)!
        draft.name = "  Research  "
        draft.customIcon = .emoji("📚")
        draft.theme = SpaceTheme(primaryColor: ThemeColor(hex: "123456"), colorCount: 2, wheel: .analogous,
                                 appearance: .dark, noise: 0.2, intensity: 0.7)
        self.snapshot = snapshot
        self.draft = draft
        self.state = state
        self.source = source
        self.profile = profile
        self.following = following
        self.folder = folder
        self.nested = nested
        self.a = a; self.b = b; self.c = c
        self.today = today; self.retained = retained; self.favorite = favorite
        self.group = group
    }

    func makeEmptyDraft() -> SidebarNewSpaceDraft {
        var empty = SidebarNewSpaceDraft(from: snapshot, state: state)!
        empty.name = "Empty"
        empty.profileID = other.id
        return empty
    }

    func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ParcNewSpace-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    @Test func aDraftStartsInTheOriginalProfileAndTheme() {
        let draft = SidebarNewSpaceDraft(items: [.folder(folder.id), .split(group.id), .tab(today.id)], from: snapshot, state: state)!
        #expect(draft.name.isEmpty)
        #expect(draft.profileID == profile)
        #expect(draft.theme == source.theme)
    }

    @Test func aSelectedAncestorOwnsItsDescendants() {
        #expect(draft.roots == [.folder(folder.id), .tab(today.id)])
    }

    @Test func aDraftExposesTheExactOrderedIdentitiesForNativeOwnerClaims() {
        let draft = draft
        #expect(draft.tabIDs == [c.id, a.id, b.id, today.id])
        #expect(draft.folderIDs == [folder.id, nested.id])
        #expect(draft.groupIDs == [group.id])
    }

    @Test func aBlankEditingDraftDoesNotCreateASpace() {
        let blank = SidebarNewSpaceDraft(items: [.folder(folder.id), .split(group.id), .tab(today.id)], from: snapshot, state: state)!
        #expect(blank.applying(to: state) == nil)
    }

    @Test func creationResolvesAfterTheOriginalSpaceRatherThanAppending() throws {
        let draft = draft
        let next = try #require(draft.applying(to: state))
        #expect(next.spaces.map(\.id) == [source.id, draft.spaceID, following.id])
    }

    @Test func theAuthoredNameStyleAndProfileCommitTogether() throws {
        let draft = draft
        let created = try #require(draft.applying(to: state)).spaces[1]
        #expect(created.name == draft.name)
        #expect(created.profileID == profile)
        #expect(created.customIcon == draft.customIcon)
        #expect(created.theme == draft.theme)
    }

    @Test func movingNeverCopiesOrRecreatesOriginalItems() throws {
        let next = try #require(draft.applying(to: state))
        #expect(next.tabs.count == state.tabs.count)
        #expect(next.folders.count == state.folders.count)
    }

    @Test func originalSavedAndLiveNavigationAndIdentitySurvive() throws {
        let draft = draft
        let next = try #require(draft.applying(to: state))
        for original in state.tabs {
            var expected = original
            if draft.tabIDs.contains(original.id) { expected.spaceID = draft.spaceID }
            #expect(next.tabs.first { $0.id == original.id } == expected)
        }
    }

    @Test func theWholeSplitKeepsItsIdentityNameIconAndGeometry() throws {
        let next = try #require(draft.applying(to: state))
        #expect(next.splitLayouts == [expectedGroup])
    }

    @Test func nestedHierarchyAndACollapsedParentAreRetained() throws {
        let next = try #require(draft.applying(to: state))
        #expect(next.folders.first { $0.id == nested.id }?.parentID == folder.id)
        #expect(next.folders.first { $0.id == folder.id }?.isExpanded == false)
    }

    @Test func mixedChildOrderIsPreserved() throws {
        let draft = draft
        let next = try #require(draft.applying(to: state))
        #expect(SidebarHierarchy.children(in: container(draft.spaceID, folder.id), state: next) == [.tab(c.id), .folder(nested.id)])
        #expect(SidebarHierarchy.children(in: container(draft.spaceID, nested.id), state: next) == [.split(group.id)])
    }

    @Test func theOriginalNestedOrderKeyIsRemovedAtomically() throws {
        let next = try #require(draft.applying(to: state))
        #expect(next.sidebarItemOrder[container(source.id, nested.id).key] == nil)
    }

    @Test func coreDoesNotImpersonateOriginatingWindowFocus() throws {
        let next = try #require(draft.applying(to: state))
        #expect(next.activeSpaceID == source.id)
        #expect(next.selectedTabIDs.isEmpty)
    }

    @Test func aFixedCreationIdentityPreventsReplay() throws {
        let draft = draft
        let next = try #require(draft.applying(to: state))
        #expect(draft.applying(to: next) == nil)
    }

    @Test func theOriginalSplitOwnerMayRetainTheOriginalPages() throws {
        let move = try #require(draft.move(in: state))
        let window = UUID()
        #expect(move.permitsSplitOwners([a.id: window, b.id: window], in: window))
    }

    @Test func mixedPhysicalOwnershipRefusesTheWholeMove() throws {
        let move = try #require(draft.move(in: state))
        let window = UUID(), foreignWindow = UUID()
        #expect(!move.permitsSplitOwners([a.id: window, b.id: foreignWindow], in: window))
    }

    @Test func liveNavigationMetadataIsNotOverwrittenByTheDraft() {
        var changed = state
        changed.tabs[0].url = "https://example.test/latest"
        changed.tabs[0].title = "Changed live title"
        #expect(draft.applying(to: changed)?.tabs[0].url == changed.tabs[0].url)
    }

    @Test func aChangedOriginalHierarchyRefusesAStaleDraft() {
        var changed = state
        changed.folders[0].name = "Changed hierarchy"
        #expect(draft.applying(to: changed) == nil)
    }

    @Test func aReassignedSourceSpaceRefusesOriginalOwnership() {
        var changed = state
        changed.spaces[0].profileID = other.id
        #expect(draft.applying(to: changed) == nil)
    }

    @Test func aMissingOriginalAnchorCannotChooseASubstituteSpace() {
        var changed = state
        changed.spaces.removeFirst()
        #expect(draft.applying(to: changed) == nil)
    }

    @Test func aRetiringSourceProfileRefusesTheMove() {
        var changed = state
        changed.profileRemovals = [.init(id: UUID(), profileID: profile, profileName: source.name)]
        #expect(draft.applying(to: changed) == nil)
    }

    @Test func aNonemptyCrossProfileRelocationIsUnavailable() {
        #expect(!draft.canUseProfile(other.id, in: state))
    }

    @Test func aProgrammaticProfileChangeCannotTransplantLivePages() {
        var invalid = draft
        invalid.profileID = other.id
        #expect(invalid.applying(to: state) == nil)
    }

    @Test func aWhitespaceOnlyTitleCannotSubmit() {
        var invalid = draft
        invalid.name = " \n\t"
        #expect(invalid.applying(to: state) == nil)
    }

    @Test func anUnsupportedIconCannotEnterDurableState() {
        var invalid = draft
        invalid.customIcon = .symbol("invalid")
        #expect(invalid.applying(to: state) == nil)
    }

    @Test func anInvalidThemeCannotEnterDurableState() {
        var invalid = draft
        invalid.theme.noise = .nan
        #expect(invalid.applying(to: state) == nil)
    }

    @Test func aPartialSplitMoveIsRefused() {
        #expect(SidebarNewSpaceDraft(items: [.tab(a.id)], from: snapshot, state: state) == nil)
    }

    @Test func aProfileFavoriteIsNotSilentlyMadeASpaceItem() {
        #expect(SidebarNewSpaceDraft(items: [.tab(favorite.id)], from: snapshot, state: state) == nil)
    }

    @Test func aDuplicateSelectedRootCannotCommitTwice() {
        #expect(SidebarNewSpaceDraft(items: [.tab(today.id), .tab(today.id)], from: snapshot, state: state) == nil)
    }

    @Test func anExistingSpaceIDCannotBeReused() {
        #expect(SidebarNewSpaceDraft(from: snapshot, state: state, spaceID: following.id) == nil)
    }

    @Test func ordinaryCreationHasNoFabricatedMoveIdentities() {
        let empty = makeEmptyDraft()
        #expect(empty.roots.isEmpty)
        #expect(empty.tabIDs.isEmpty)
        #expect(empty.folderIDs.isEmpty)
        #expect(empty.groupIDs.isEmpty)
    }

    @Test func ordinaryCreationCanChooseAnotherExistingProfileWithoutAMove() {
        let empty = makeEmptyDraft()
        #expect(empty.canUseProfile(other.id, in: state))
        #expect(empty.move(in: state) == nil)
    }

    @Test func emptyCreationPreservesAllSourceContents() throws {
        let next = try #require(makeEmptyDraft().applying(to: state))
        #expect(next.spaces[1].profileID == other.id)
        #expect(next.tabs == state.tabs)
        #expect(next.folders == state.folders)
    }

    @Test func emptyCreationDoesNotClearTheOriginalSelection() throws {
        let next = try #require(makeEmptyDraft().applying(to: state))
        #expect(next.selectedTabIDs == state.selectedTabIDs)
        #expect(next.selectionBySpace == state.selectionBySpace)
    }

    @Test func aDraftWithNoRootsDoesNotBindUnrelatedHierarchyEdits() {
        var changed = state
        changed.folders[0].name = "Unrelated edit"
        #expect(makeEmptyDraft().applying(to: changed) != nil)
    }

    @Test func aRemovedDestinationProfileCannotFallBackToDefault() {
        var changed = state
        changed.profiles.removeAll { $0.id == other.id }
        #expect(makeEmptyDraft().applying(to: changed) == nil)
    }

    @Test func aRetiringDestinationProfileRefusesEvenEmptyCreation() {
        var changed = state
        changed.profileRemovals = [.init(id: UUID(), profileID: other.id, profileName: other.name)]
        #expect(makeEmptyDraft().applying(to: changed) == nil)
    }

    @Test func anExplicitAbsoluteInsertionIsHonored() {
        var first = SidebarNewSpaceDraft(from: snapshot, state: state, insertion: .absolute(0))!
        first.name = "First"
        #expect(first.applying(to: state)?.spaces.first?.id == first.spaceID)
    }

    @Test func invalidInsertionTargetsAreRefused() {
        #expect(SidebarNewSpaceDraft(from: snapshot, state: state, insertion: .absolute(-1)) == nil)
        #expect(SidebarNewSpaceDraft(from: snapshot, state: state, insertion: .absolute(3)) == nil)
        #expect(SidebarNewSpaceDraft(from: snapshot, state: state, insertion: .after(UUID())) == nil)
    }

    @Test func relativeInsertionFollowsTheOriginalAnchorAfterAReorder() {
        var reordered = state
        reordered.spaces.swapAt(0, 1)
        let draft = draft
        #expect(draft.applying(to: reordered)?.spaces.map(\.id) == [following.id, source.id, draft.spaceID])
    }

    @Test func aCustomIconAndThemeRoundTrip() throws {
        let created = try #require(draft.applying(to: state)).spaces[1]
        let roundTrip = try decoder().decode(BrowserSpace.self, from: encoder().encode(created))
        #expect(roundTrip == created)
    }

    @Test func legacySymbolAndColorMigrationRemainsCompatible() throws {
        var legacy = try #require(JSONSerialization.jsonObject(with: encoder().encode(source)) as? [String: Any])
        legacy.removeValue(forKey: "customIcon")
        legacy.removeValue(forKey: "theme")
        legacy["color"] = "123456"
        let migrated = try decoder().decode(BrowserSpace.self, from: JSONSerialization.data(withJSONObject: legacy))
        #expect(migrated.customIcon == nil)
        #expect(migrated.symbol == source.symbol)
        #expect(migrated.theme == .singleColor(ThemeColor(hex: "123456")!))
    }

    @Test func anInvalidOptionalIconRecoversTheOrdinarySymbolFallback() throws {
        var invalidIcon = try #require(draft.applying(to: state)).spaces[1]
        invalidIcon.customIcon = .emoji("not an emoji")
        let recovered = try decoder().decode(BrowserSpace.self, from: encoder().encode(invalidIcon))
        #expect(recovered.customIcon == nil)
    }

    @MainActor @Test func editingAndDiscardingADraftHasNoDurableOrModelEffect() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("session.json")
        try encoder().encode(state).write(to: file)
        let store = try BrowserStore(directory: directory)
        let diskBefore = try Data(contentsOf: file), before = store.state
        var abandoned = draft
        abandoned.name = "Cancelled"
        abandoned.profileID = other.id
        _ = abandoned.canUseProfile(other.id, in: store.state)
        #expect(store.state == before)
        #expect(try Data(contentsOf: file) == diskBefore)
    }

    @MainActor @Test func theAtomicStoreOperationReturnsTheFixedIdentityAndPersistsSpaceAndSplitTogether() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try encoder().encode(state).write(to: directory.appendingPathComponent("session.json"))
        let store = try BrowserStore(directory: directory)
        let draft = draft
        let created = try #require(draft.applying(to: state)).spaces[1]
        #expect(try store.createSpaceAndMoveSidebarItems(draft) == draft.spaceID)
        let reopened = try BrowserStore(directory: directory)
        #expect(reopened.state.spaces.contains(created))
        #expect(reopened.state.splitLayouts == [expectedGroup])
    }

    @MainActor @Test func anAlreadyCommittedDraftCannotReplay() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try encoder().encode(state).write(to: directory.appendingPathComponent("session.json"))
        let store = try BrowserStore(directory: directory)
        let draft = draft
        _ = try store.createSpaceAndMoveSidebarItems(draft)
        #expect(try store.createSpaceAndMoveSidebarItems(draft) == nil)
    }

    @MainActor @Test func aWriteFailurePublishesNeitherAnEmptySpaceNorAPartialMoveAndRetryKeepsTheIdentity() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("session.json")
        try encoder().encode(state).write(to: file)
        let failing = try BrowserStore(directory: directory), original = failing.state
        let draft = draft
        try FileManager.default.removeItem(at: file)
        try FileManager.default.createDirectory(at: file, withIntermediateDirectories: false)
        #expect(throws: (any Error).self) { try failing.createSpaceAndMoveSidebarItems(draft) }
        #expect(failing.state == original)
        #expect(failing.persistenceError != nil)
        try FileManager.default.removeItem(at: file)
        #expect(try failing.createSpaceAndMoveSidebarItems(draft) == draft.spaceID)
    }

    @MainActor @Test func aPendingRetirementCannotBeStolenByCreationAndARefusedCloseReleasesTheMove() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try encoder().encode(state).write(to: directory.appendingPathComponent("session.json"))
        let retiring = try BrowserStore(directory: directory)
        var release: ((Bool) -> Void)?
        retiring.requestPageRetirement = { _, _, completion in release = completion }
        retiring.closeTabs([today.id])
        #expect(retiring.retiringTabIDs.contains(today.id))
        let draft = draft
        #expect(try retiring.createSpaceAndMoveSidebarItems(draft) == nil)
        release?(false)
        #expect(try retiring.createSpaceAndMoveSidebarItems(draft) == draft.spaceID)
    }

    @MainActor @Test func anEphemeralBrowserCannotPublishANormalSpace() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let ephemeral = BrowserStore(privateParentProfileID: profile, engineProfilePath: "unused", directory: directory, settings: state.settings)
        let privateSnapshot = SidebarHierarchySnapshot(state: ephemeral.state, spaceID: ephemeral.activeSpaceID,
                                                       profileID: ephemeral.activeSpace.profileID)!
        var privateDraft = SidebarNewSpaceDraft(from: privateSnapshot, state: ephemeral.state)!
        privateDraft.name = "Private"
        #expect(try ephemeral.createSpaceAndMoveSidebarItems(privateDraft) == nil)
    }
}
