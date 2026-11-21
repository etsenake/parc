import Foundation
import Testing
@testable import ParcCore

@MainActor
struct TabCreationProvenanceTests {
    struct Fixture {
        var state = BrowserState.initial()
        let space: BrowserSpace
        let profile: UUID
        let parent: BrowserTab
        let previous: BrowserTab
        let current: BrowserTab
        let child: BrowserTab

        init() {
            space = state.spaces[0]
            profile = space.profileID
            parent = Self.tab(.pinned, space: space.id, profile: profile)
            previous = Self.tab(space: space.id, profile: profile)
            current = Self.tab(space: space.id, profile: profile)
            child = Self.tab(space: space.id, profile: profile, referrer: current.id)
            state.tabs = [parent, previous, current, child]
            state.selectedTabIDs = [current.id]
            state.selectionBySpace[space.id.uuidString] = [current.id]
        }

        static func tab(_ kind: TabKind = .today, space: UUID, profile: UUID, referrer: UUID? = nil, previous: UUID? = nil) -> BrowserTab {
            BrowserTab(id: UUID(), spaceID: space, profileID: profile,
                       url: "https://example.test/", title: "Original", kind: kind,
                       createdAt: Date(timeIntervalSince1970: 1), lastAccessed: Date(timeIntervalSince1970: 1),
                       savedURL: "https://example.test/", savedTitle: "Original",
                       referrerID: referrer, activeTabBeforeCreationID: previous)
        }

        func tab(_ kind: TabKind = .today, referrer: UUID? = nil, previous: UUID? = nil) -> BrowserTab {
            Self.tab(kind, space: space.id, profile: profile, referrer: referrer, previous: previous)
        }

        func choose(_ input: BrowserState? = nil, closing: UUID? = nil, pool: Set<UUID> = [], unavailable: Set<UUID> = []) -> FolderRemovalSelection? {
            let id = closing ?? current.id
            return FolderRemovalSelection.resolve(removing: [id], spaceID: space.id, profileID: profile,
                state: input ?? state, selected: [id], focused: id, referrerPool: pool,
                available: { !unavailable.contains($0) })
        }

        func index(_ id: UUID, in state: BrowserState) -> Int { state.tabs.firstIndex { $0.id == id }! }
    }

    struct Routed {
        var f = Fixture()
        let space: BrowserSpace
        var state: BrowserState
        var sourceWindow: WindowPresentation
        var destinationWindow: WindowPresentation
        let linkReceipt: TabCreationProvenance
        let createdReceipt: TabCreationProvenance

        init() {
            space = BrowserSpace(id: UUID(), name: "Routed", symbol: "circle", color: "123456", profileID: f.profile)
            state = f.state
            state.spaces.append(space)
            sourceWindow = WindowPresentation(state: state, ready: true)
            destinationWindow = WindowPresentation(state: state, ready: true)
            linkReceipt = TabCreationProvenance(routedFrom: f.parent.id, openedLink: true, profileID: f.profile, state: state)
            createdReceipt = TabCreationProvenance(routedFrom: f.parent.id, openedLink: false, profileID: f.profile, state: state)
        }
    }

    @Test func anExplicitOriginalReferrerWinsOverTheActiveBefore() {
        let f = Fixture()
        let receipt = TabCreationProvenance(referrerID: f.parent.id, activeTabID: f.previous.id, profileID: f.profile, state: f.state)
        #expect(receipt.referrerID == f.parent.id && receipt.activeTabBeforeCreationID == f.parent.id)
    }

    @Test func ordinaryCreationCapturesTheActualPreviousActiveID() {
        let f = Fixture()
        let ordinary = TabCreationProvenance(referrerID: nil, activeTabID: f.previous.id, profileID: f.profile, state: f.state)
        #expect(ordinary.referrerID == nil && ordinary.activeTabBeforeCreationID == f.previous.id)
    }

    @Test func aTargetProfileCannotAcceptAnotherProfilesReceipt() {
        let f = Fixture()
        let receipt = TabCreationProvenance(referrerID: f.parent.id, activeTabID: f.previous.id, profileID: f.profile, state: f.state)
        #expect(receipt.validated(profileID: UUID(), state: f.state).activeTabBeforeCreationID == nil)
    }

    @Test func aRemovedSourceIsNotResurrectedAtInsertion() {
        let f = Fixture()
        let receipt = TabCreationProvenance(referrerID: f.parent.id, activeTabID: f.previous.id, profileID: f.profile, state: f.state)
        var gone = f.state
        gone.tabs.removeAll { $0.id == f.parent.id }
        #expect(receipt.validated(profileID: f.profile, state: gone).referrerID == nil)
    }

    @Test func aMatchedLinkRecordsItsSourceOnlyAsTheCreatingWindowsActiveItem() {
        let r = Routed()
        #expect(r.linkReceipt.referrerID == nil && r.linkReceipt.activeTabBeforeCreationID == r.f.parent.id)
    }

    @Test func routedCreatedContentsKeepTheirSourceAsReferrer() {
        let r = Routed()
        #expect(r.createdReceipt.referrerID == r.f.parent.id && r.createdReceipt.activeTabBeforeCreationID == r.f.parent.id)
    }

    @Test func theDestinationReplacesItsPoolWithTheSourceAndChildWithoutTouchingTheSourceWindow() {
        var r = Routed()
        var routed = r.f.tab(referrer: r.linkReceipt.referrerID, previous: r.linkReceipt.activeTabBeforeCreationID)
        routed.spaceID = r.space.id
        r.state.tabs.append(routed)
        r.destinationWindow.recordCreation(routed.id, state: r.state)
        #expect(r.destinationWindow.referrerPool == [r.f.parent.id, routed.id])
        #expect(r.sourceWindow.referrerPool.isEmpty)
        #expect(r.sourceWindow.selectedTabIDs == [r.f.current.id])
    }

    @Test func sourceSelectionChangesDoNotOverwriteTheDestinationsAcceptedReceipt() {
        var r = Routed()
        var routed = r.f.tab(referrer: r.linkReceipt.referrerID, previous: r.linkReceipt.activeTabBeforeCreationID)
        routed.spaceID = r.space.id
        r.state.tabs.append(routed)
        r.destinationWindow.recordCreation(routed.id, state: r.state)
        r.sourceWindow.recordSelectionForReturn(r.f.previous.id, state: r.state)
        #expect(r.destinationWindow.referrerPool == [r.f.parent.id, routed.id])
    }

    @Test func crossProfileAdoptionNeverImportsEitherSourceIdentity() {
        let r = Routed()
        let foreign = r.createdReceipt.validated(profileID: UUID(), state: r.state)
        #expect(foreign.referrerID == nil && foreign.activeTabBeforeCreationID == nil)
    }

    @Test func aSourceRetiredBeforeAdoptionCannotProduceANewRelationship() {
        var r = Routed()
        r.state.tabs[r.f.index(r.f.parent.id, in: r.state)].archivedAt = Date()
        #expect(r.linkReceipt.validated(profileID: r.f.profile, state: r.state).activeTabBeforeCreationID == nil)
    }

    @Test func aSourceProfileChangeInvalidatesBothStoredIdentities() {
        var r = Routed()
        r.state.tabs[r.f.index(r.f.parent.id, in: r.state)].profileID = UUID()
        #expect(r.createdReceipt.validated(profileID: r.f.profile, state: r.state).activeTabBeforeCreationID == nil)
    }

    @Test func aRoutedPageWithoutASameProfileSourceBorrowsNoDestinationSelection() {
        let r = Routed()
        let unsourced = TabCreationProvenance(routedFrom: nil, openedLink: false, profileID: r.f.profile, state: r.state)
        #expect(unsourced.referrerID == nil && unsourced.activeTabBeforeCreationID == nil)
    }

    @Test func urlOnlyNewWindowCreationDoesNotAdoptAnUnrelatedCurrentSelection() {
        let r = Routed()
        let windowOnly = TabCreationProvenance(referrerID: nil, activeTabID: nil, profileID: r.f.profile, state: r.state)
        #expect(windowOnly.referrerID == nil && windowOnly.activeTabBeforeCreationID == nil)
    }

    @Test func creationIDsRoundTripWithTheSavedRecord() throws {
        let f = Fixture()
        let encoded = try JSONEncoder().encode(f.child)
        #expect(try JSONDecoder().decode(BrowserTab.self, from: encoded) == f.child)
    }

    @Test func oldRecordsDecodeWithoutInventingProvenance() throws {
        let f = Fixture()
        let encoded = try JSONEncoder().encode(f.child)
        var old = try #require(try JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        old.removeValue(forKey: "referrerID")
        old.removeValue(forKey: "activeTabBeforeCreationID")
        let decoded = try JSONDecoder().decode(BrowserTab.self, from: JSONSerialization.data(withJSONObject: old))
        #expect(decoded.referrerID == nil && decoded.activeTabBeforeCreationID == nil)
    }

    @Test func theWindowPoolIsNotSynthesizedFromPersistedSelection() {
        let f = Fixture()
        var window = WindowPresentation(state: f.state, ready: true)
        window.recordSelectionForReturn(f.current.id, state: f.state)
        #expect(window.referrerPool.isEmpty)
    }

    @Test func creationWithoutAReferrerReplacesThePoolAndExplicitReferrersUnionIt() {
        let f = Fixture()
        var window = WindowPresentation(state: f.state, ready: true)
        var creationState = f.state
        let first = f.tab(previous: f.current.id), second = f.tab(referrer: f.current.id, previous: f.current.id)
        creationState.tabs += [first, second]
        window.recordCreation(first.id, state: creationState)
        #expect(window.referrerPool == [f.current.id, first.id])
        window.recordCreation(second.id, state: creationState)
        #expect(window.referrerPool == [f.current.id, first.id, second.id])
    }

    @Test func refreshingFocusAndSelectingPooledTodayRetainTheChain() {
        let f = Fixture()
        var window = WindowPresentation(state: f.state, ready: true)
        var creationState = f.state
        let first = f.tab(previous: f.current.id), second = f.tab(referrer: f.current.id, previous: f.current.id)
        creationState.tabs += [first, second]
        window.recordCreation(first.id, state: creationState)
        window.recordCreation(second.id, state: creationState)
        window.recordSelectionForReturn(f.current.id, state: creationState)
        #expect(window.referrerPool.count == 3)
        window.recordSelectionForReturn(second.id, state: creationState)
        #expect(window.referrerPool.count == 3)
        window.recordCreation(f.parent.id, state: creationState)
        #expect(window.referrerPool.count == 3)
    }

    @Test func selectingPooledPinnedContextKeepsOnlyThatItemAndAnUnrelatedSelectionClearsThePool() {
        let f = Fixture()
        var window = WindowPresentation(state: f.state, ready: true)
        var creationState = f.state
        let pinnedChild = f.tab(.pinned, referrer: f.current.id, previous: f.current.id)
        creationState.tabs.append(pinnedChild)
        window.recordCreation(pinnedChild.id, state: creationState)
        window.recordSelectionForReturn(pinnedChild.id, state: creationState)
        #expect(window.referrerPool == [pinnedChild.id])
        window.recordSelectionForReturn(f.previous.id, state: creationState)
        #expect(window.referrerPool.isEmpty)
    }

    @Test func anotherPhysicalWindowNeverReceivesTheChain() {
        let f = Fixture()
        var window = WindowPresentation(state: f.state, ready: true)
        let peer = WindowPresentation(state: f.state, ready: true)
        let first = f.tab(previous: f.current.id)
        var creationState = f.state
        creationState.tabs.append(first)
        window.recordCreation(first.id, state: creationState)
        #expect(peer.referrerPool.isEmpty)
    }

    @Test func anAdjacentGenuineChildWinsOverTheOrdinaryPreviousItem() {
        let f = Fixture()
        #expect(f.choose()?.tabIDs == [f.child.id])
    }

    @Test func aPooledSubsequentSiblingWinsOverTheOrdinaryNeighborButOnlyWithTheRealPool() {
        let f = Fixture()
        var siblings = f.state
        siblings.tabs.removeAll { $0.id == f.child.id }
        let sibling = f.tab(referrer: f.parent.id), unrelated = f.tab()
        siblings.tabs[f.index(f.current.id, in: siblings)].referrerID = f.parent.id
        siblings.tabs += [unrelated, sibling]
        #expect(f.choose(siblings, pool: [f.current.id, sibling.id])?.tabIDs == [sibling.id])
        #expect(f.choose(siblings)?.tabIDs == [f.previous.id])
        #expect(f.choose(siblings, pool: [sibling.id])?.tabIDs == [f.previous.id])
    }

    func activeBeforeState(_ f: Fixture) -> BrowserState {
        var active = f.state
        active.tabs.removeAll { $0.id == f.child.id }
        active.tabs[f.index(f.current.id, in: active)].activeTabBeforeCreationID = f.parent.id
        return active
    }

    @Test func theOriginalActiveBeforeWinsOverAnUnrelatedAdjacentItemUnlessUnavailable() {
        let f = Fixture()
        let active = activeBeforeState(f)
        #expect(f.choose(active, pool: [f.parent.id])?.tabIDs == [f.parent.id])
        #expect(f.choose(active, pool: [f.parent.id], unavailable: [f.parent.id])?.tabIDs == [f.previous.id])
    }

    @Test func aPinnedReturnCannotCrossItsOriginalSpaceButAFavoriteMay() {
        let f = Fixture()
        var active = activeBeforeState(f)
        let otherSpace = BrowserSpace(id: UUID(), name: "Other", symbol: "circle", color: "123456", profileID: f.profile)
        active.spaces.append(otherSpace)
        active.tabs[f.index(f.parent.id, in: active)].spaceID = otherSpace.id
        #expect(f.choose(active, pool: [f.parent.id])?.tabIDs == [f.previous.id])
        active.tabs[f.index(f.parent.id, in: active)].kind = .favorite
        #expect(f.choose(active, pool: [f.parent.id])?.tabIDs == [f.parent.id])
        active.tabs[f.index(f.parent.id, in: active)].profileID = UUID()
        #expect(f.choose(active, pool: [f.parent.id])?.tabIDs == [f.previous.id])
    }

    @Test func aReturnPreservesTheOriginalCompleteSplitUnlessAPaneIsUnavailable() {
        let f = Fixture()
        var splitState = activeBeforeState(f)
        let partner = f.tab(.pinned)
        splitState.tabs.append(partner)
        splitState.splitLayouts = [BrowserSplitLayout(spaceID: f.space.id, tabIDs: [f.parent.id, partner.id],
                                                      orientation: .vertical, widthFactors: [0.4, 0.6])]
        #expect(f.choose(splitState, pool: [f.parent.id])?.tabIDs == [f.parent.id, partner.id])
        #expect(f.choose(splitState, pool: [f.parent.id], unavailable: [partner.id])?.tabIDs == [f.previous.id])
    }

    @Test func closingBackgroundItemsPreservesTheExactActiveSelection() throws {
        let f = Fixture()
        let background = try #require(FolderRemovalSelection.resolve(removing: [f.parent.id], spaceID: f.space.id,
            profileID: f.profile, state: f.state, selected: [f.current.id], focused: f.current.id,
            referrerPool: [f.parent.id], available: { _ in true }))
        #expect(background.tabIDs == [f.current.id])
    }

    @Test func aSurvivingOriginalPanePrecedesReturnCandidates() {
        let f = Fixture()
        let surviving = FolderRemovalSelection.resolve(removing: [f.current.id], spaceID: f.space.id, profileID: f.profile,
            state: f.state, selected: [f.current.id, f.previous.id], focused: f.current.id, available: { _ in true })
        #expect(surviving?.tabIDs == [f.previous.id])
    }

    @Test func aSavedCloseCanConsumeItsReplacementWithoutDeletingTheBookmarkAndALaterSelectionWins() throws {
        let f = Fixture()
        var savedState = f.state
        savedState.tabs[f.index(f.current.id, in: savedState)].kind = .pinned
        let decision = try #require(f.choose(savedState))
        var savedWindow = WindowPresentation(state: savedState, ready: true)
        savedWindow.remove(f.current.id)
        let finished = savedWindow.finishFolderRemoval(decision, state: savedState, available: { _ in true })
        #expect(finished)
        #expect(savedState.tabs.contains { $0.id == f.current.id && $0.archivedAt == nil })
        var newer = WindowPresentation(state: savedState, ready: true)
        _ = newer.selectExistingTab(f.parent.id, state: savedState, available: { _ in true })
        let lateFinish = newer.finishFolderRemoval(decision, state: savedState, available: { _ in true })
        #expect(!lateFinish)
    }

    @MainActor final class StoreFixture {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store: BrowserStore
        let original: UUID
        let adjacent: UUID

        init() throws {
            store = try BrowserStore(directory: directory)
            original = store.open("https://original.example", kind: .pinned)
            adjacent = store.open("https://adjacent.example")
        }

        deinit { try? FileManager.default.removeItem(at: directory) }

        var profile: UUID { store.activeSpace.profileID }
    }

    @Test func actualCreationWritesItsSourceReceipt() throws {
        let s = try StoreFixture()
        let created = s.store.open("https://new.example", creation: TabCreationProvenance(referrerID: s.original,
            activeTabID: s.adjacent, profileID: s.profile, state: s.store.state))
        #expect(s.store.state.tabs.first { $0.id == created }?.referrerID == s.original)
    }

    @Test func aRefusedBeforeunloadKeepsTheRecordAndASecondAttemptReturnsToTheOriginalSource() throws {
        let s = try StoreFixture()
        let created = s.store.open("https://new.example", creation: TabCreationProvenance(referrerID: s.original,
            activeTabID: s.adjacent, profileID: s.profile, state: s.store.state))
        var origin = WindowPresentation(state: s.store.state, ready: true)
        origin.recordCreation(created, state: s.store.state)
        let decision = try #require(FolderRemovalSelection.resolve(removing: [created], spaceID: s.store.activeSpaceID,
            profileID: s.profile, state: s.store.state, selected: [created], focused: created,
            referrerPool: origin.referrerPool, available: { _ in true }))
        #expect(decision.tabIDs == [s.original])
        var validator: (() -> Bool)?, finish: ((Bool) -> Void)?, closed: Bool?
        s.store.requestPageRetirement = { _, validate, complete in validator = validate; finish = complete }
        s.store.closeTabs([created], selection: decision, shouldCommit: { true }) { closed = $0 }
        #expect(s.store.state.selectedTabIDs == [created] && closed == nil)
        #expect(validator?() == true)
        finish?(false)
        #expect(closed == false && s.store.state.tabs.first { $0.id == created }?.archivedAt == nil)
        s.store.closeTabs([created], selection: decision, shouldCommit: { true }) { closed = $0 }
        #expect(validator?() == true)
        finish?(true)
        #expect(closed == true && s.store.state.selectedTabIDs == [s.original])
        #expect(s.store.state.tabs.first { $0.id == created }?.archivedAt != nil)
        origin.reconcile(s.store.state) { _ in true }
        let peer = WindowPresentation(state: s.store.state, ready: false)
        let consumed = origin.finishFolderRemoval(decision, state: s.store.state, available: { _ in true })
        #expect(consumed)
        #expect(origin.selectedTabIDs == [s.original] && !peer.isReady)
        try s.store.save()
        let reload = try BrowserStore(directory: s.directory)
        #expect(reload.state.tabs.first { $0.id == created }?.activeTabBeforeCreationID == s.original)
        #expect(reload.state.selectedTabIDs == [s.original])
    }

    @Test func duplicatesCaptureTheExactOriginsActiveItemWithoutInheritingTheSourcesReferrer() throws {
        let s = try StoreFixture()
        let source = s.store.open("https://copy-source.example", creation: TabCreationProvenance(referrerID: s.adjacent,
            activeTabID: s.adjacent, profileID: s.profile, state: s.store.state))
        s.store.selectTab(s.original)
        let copyReceipt = TabCreationProvenance(referrerID: nil, activeTabID: s.original, profileID: s.profile, state: s.store.state)
        let target = try #require(SidebarDuplicateTarget(items: [.tab(source)], spaceID: s.store.activeSpaceID,
            profileID: s.profile, state: s.store.state))
        let result = try #require(try s.store.duplicateSidebarItems(target, destinations: [source: "https://copy-source.example"],
            creation: copyReceipt))
        let copied = try #require(s.store.state.tabs.first { $0.id == result.tabIDs[0] })
        #expect(copied.referrerID == nil)
        #expect(copied.activeTabBeforeCreationID == s.original)
        #expect(s.store.state.selectedTabIDs == [s.original])
        #expect(s.store.state.tabs.first { $0.id == source }?.referrerID == s.adjacent)
    }

    @Test func aContextualCopyUsesAFreshOriginReceiptForEveryOriginalRoot() throws {
        let s = try StoreFixture()
        let source = s.store.open("https://copy-source.example")
        s.store.selectTab(s.original)
        let copyReceipt = TabCreationProvenance(referrerID: nil, activeTabID: s.original, profileID: s.profile, state: s.store.state)
        let folder = s.store.createFolder(name: "Target")
        let copySource = try #require(CommandBarFolderMoveSource(items: [.tab(source)], spaceID: s.store.activeSpaceID,
            profileID: s.profile, state: s.store.state))
        let move = try #require(CommandBarFolderMove.snapshot(source: copySource, state: s.store.state).first { $0.folder.folderID == folder })
        let copyResult = try #require(try s.store.copyCommandBarItemsToFolder(move, destinations: [source: "https://copy-source.example"],
            creation: copyReceipt))
        #expect(copyResult.tabs.allSatisfy { $0.referrerID == nil && $0.activeTabBeforeCreationID == s.original })
    }

    @Test func aCallerWithoutAWindowCannotInventCopiedProvenance() throws {
        let s = try StoreFixture()
        let source = s.store.open("https://copy-source.example", creation: TabCreationProvenance(referrerID: s.adjacent,
            activeTabID: s.adjacent, profileID: s.profile, state: s.store.state))
        let target = try #require(SidebarDuplicateTarget(items: [.tab(source)], spaceID: s.store.activeSpaceID,
            profileID: s.profile, state: s.store.state))
        let ownerless = try #require(try s.store.duplicateSidebarItems(target, destinations: [source: "https://copy-source.example"]))
        #expect(ownerless.tabIDs.allSatisfy { id in s.store.state.tabs.contains {
            $0.id == id && $0.referrerID == nil && $0.activeTabBeforeCreationID == nil } })
    }

    @MainActor final class Placement {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store: BrowserStore
        let profile: UUID
        let space: UUID
        let older: UUID
        let newer: UUID

        init() throws {
            store = try BrowserStore(directory: directory)
            profile = store.activeSpace.profileID
            space = store.activeSpaceID
            older = store.open("https://older.example")
            newer = store.open("https://newer.example")
        }

        deinit { try? FileManager.default.removeItem(at: directory) }

        func today(_ state: BrowserState? = nil) -> [SidebarItemReference] {
            SidebarHierarchy.children(in: SidebarContainerLocation(spaceID: space, folderID: nil, section: .today),
                                      state: state ?? store.state)
        }

        func creationFrom(_ referrer: UUID?) -> TabCreationProvenance {
            TabCreationProvenance(referrerID: referrer, activeTabID: store.state.selectedTabIDs.first,
                                  profileID: profile, state: store.state)
        }

        func linked(_ id: UUID, referrer: UUID, spaceID: UUID? = nil) -> BrowserTab {
            BrowserTab(id: id, spaceID: spaceID ?? space, profileID: profile,
                       url: "https://linked.example/", title: "Linked", kind: .today, createdAt: Date(), lastAccessed: Date(),
                       savedURL: "https://linked.example/", savedTitle: "Linked", referrerID: referrer, activeTabBeforeCreationID: referrer)
        }

        func adopt(_ url: String, creation: TabCreationProvenance, insertion: TodayInsertion? = nil) -> UUID {
            let path = store.independentEngineProfilePath(for: profile)
            if let insertion {
                return store.adoptNativePage(url: URL(string: url), title: "Routed", profilePath: path, preferredSpaceID: space,
                                             select: false, creation: creation, insertion: insertion)!
            }
            return store.adoptNativePage(url: URL(string: url), title: "Adopted", profilePath: path, preferredSpaceID: space,
                                         select: false, creation: creation)!
        }
    }

    @Test func aTabWithoutAReferrerEntersAtTheTopOfToday() throws {
        let p = try Placement()
        #expect(p.today() == [.tab(p.newer), .tab(p.older)])
    }

    @Test func linkedTabsFollowTheirReferrerAndItsEarlierRunInCreationOrder() throws {
        let p = try Placement()
        let childA = p.store.open("https://child-a.example", creation: p.creationFrom(p.newer))
        let childB = p.store.open("https://child-b.example", creation: p.creationFrom(p.newer))
        #expect(p.today() == [.tab(p.newer), .tab(childA), .tab(childB), .tab(p.older)])
        let grandchild = p.store.open("https://grandchild.example", creation: p.creationFrom(childA))
        #expect(p.today() == [.tab(p.newer), .tab(childA), .tab(grandchild), .tab(childB), .tab(p.older)])
    }

    @Test func aPinnedReferrerStartsTheScanAtTheTopOfTodayAfterItsEarlierChildren() throws {
        let p = try Placement()
        let pinnedSource = p.store.open("https://pinned-source.example", kind: .pinned)
        #expect(!p.today().contains(.tab(pinnedSource)))
        let a = p.store.open("https://from-pinned-a.example", creation: p.creationFrom(pinnedSource))
        let b = p.store.open("https://from-pinned-b.example", creation: p.creationFrom(pinnedSource))
        #expect(Array(p.today().prefix(3)) == [.tab(a), .tab(b), .tab(p.newer)])
    }

    @Test func aReferrerOutsideThisTodayListDoesNotMoveTheTabBelowUnrelatedItems() throws {
        let p = try Placement()
        var spaced = p.store.state
        let elsewhere = BrowserSpace(id: UUID(), name: "Elsewhere", symbol: "circle", color: "123456", profileID: p.profile)
        spaced.spaces.append(elsewhere)
        let otherTab = UUID(), foreignSpaceChild = UUID()
        spaced.tabs.append(p.linked(otherTab, referrer: p.newer, spaceID: elsewhere.id))
        spaced.tabs.append(p.linked(foreignSpaceChild, referrer: otherTab))
        SidebarHierarchy.placingCreatedTab(foreignSpaceChild, insertion: .automatic, in: &spaced)
        #expect(p.today(spaced).first == .tab(foreignSpaceChild))
    }

    @Test func aSplitPaneReferrerPlacesTheTabAfterItsWholeSplitItem() throws {
        let p = try Placement()
        var spaced = p.store.state
        let splitLayout = BrowserSplitLayout(sidebarAnchorID: p.newer, spaceID: p.space, tabIDs: [p.newer, p.older],
                                             orientation: .vertical, widthFactors: [0.5, 0.5])
        spaced.splitLayouts = [splitLayout]
        let fromSplit = UUID()
        spaced.tabs.append(p.linked(fromSplit, referrer: p.older))
        SidebarHierarchy.placingCreatedTab(fromSplit, insertion: .automatic, in: &spaced)
        let order = p.today(spaced)
        #expect(order.firstIndex(of: .tab(fromSplit)) == order.firstIndex(of: .split(splitLayout.id)).map { $0 + 1 })
    }

    @Test func theScanStopsAtTheFirstItemNotOpenedFromTheReferrer() throws {
        let p = try Placement()
        let childA = p.store.open("https://child-a.example", creation: p.creationFrom(p.newer))
        let grandchild = p.store.open("https://grandchild.example", creation: p.creationFrom(childA))
        var spaced = p.store.state
        let beforeSplit = UUID()
        spaced.tabs.append(p.linked(beforeSplit, referrer: grandchild))
        SidebarHierarchy.placingCreatedTab(beforeSplit, insertion: .automatic, in: &spaced)
        let order = p.today(spaced)
        #expect(order.firstIndex(of: .tab(beforeSplit)) == order.firstIndex(of: .tab(grandchild)).map { $0 + 1 })
    }

    @Test func explicitTopPlacementKeepsProvenanceButIgnoresTheReferrerRun() throws {
        let p = try Placement()
        let routedTop = p.adopt("https://routed.example", creation: p.creationFrom(p.newer), insertion: .top)
        #expect(p.today().first == .tab(routedTop))
        #expect(p.store.state.tabs.first { $0.id == routedTop }?.referrerID == p.newer)
    }

    @Test func nativeBackgroundAdoptionUsesTheSameReferrerPlacementWithoutChangingSelection() throws {
        let p = try Placement()
        let childB = p.store.open("https://child-b.example", creation: p.creationFrom(p.newer))
        let selection = p.store.state.selectedTabIDs
        let adopted = p.adopt("https://adopted.example", creation: p.creationFrom(childB))
        #expect(p.today().firstIndex(of: .tab(adopted)) == p.today().firstIndex(of: .tab(childB)).map { $0 + 1 })
        #expect(p.store.state.selectedTabIDs == selection)
    }

    @Test func closingAModalSourcedTabReturnsToItsSourceNotItsTodayNeighbour() throws {
        let p = try Placement()
        let pinnedSource = p.store.open("https://pinned-source.example", kind: .pinned)
        let childA = p.store.open("https://child-a.example", creation: p.creationFrom(p.newer))
        var window = WindowPresentation(state: p.store.state, ready: true)
        p.store.selectTab(childA)
        let fromModal = p.store.open("https://from-modal.example", creation: p.creationFrom(pinnedSource))
        window.recordCreation(fromModal, state: p.store.state)
        #expect(window.referrerPool == [pinnedSource, fromModal])
        let decision = FolderRemovalSelection.resolve(removing: [fromModal], spaceID: p.space, profileID: p.profile,
            state: p.store.state, selected: [fromModal], focused: fromModal, referrerPool: window.referrerPool,
            available: { _ in true })
        #expect(decision?.tabIDs == [pinnedSource])
    }

    @Test func aCrossProfileRoutedPageTakesTheTopWithoutEitherIdentityAndLeavesNoCreationChain() throws {
        let p = try Placement()
        let childA = p.store.open("https://child-a.example", creation: p.creationFrom(p.newer))
        p.store.selectTab(childA)
        let receipt = TabCreationProvenance(routedFrom: nil, openedLink: true, profileID: p.profile, state: p.store.state)
        let crossProfile = p.adopt("https://cross-profile.example", creation: receipt, insertion: .top)
        let crossTab = try #require(p.store.state.tabs.first { $0.id == crossProfile })
        #expect(p.today().first == .tab(crossProfile) && crossTab.referrerID == nil && crossTab.activeTabBeforeCreationID == nil)
        var destination = WindowPresentation(state: p.store.state, ready: true)
        destination.recordSelectionForReturn(childA, state: p.store.state)
        destination.recordCreation(crossProfile, state: p.store.state)
        destination.recordSelectionForReturn(crossProfile, state: p.store.state)
        #expect(destination.referrerPool.isEmpty)
        let crossReturn = FolderRemovalSelection.resolve(removing: [crossProfile], spaceID: p.space, profileID: p.profile,
            state: p.store.state, selected: [crossProfile], focused: crossProfile, referrerPool: destination.referrerPool,
            available: { _ in true })
        #expect(crossReturn?.tabIDs != [childA])
    }

    @Test func aMatchedLinkTakesTheTopAndRecordsOnlyItsActiveBeforeSource() throws {
        let p = try Placement()
        let source = p.store.open("https://from-pinned-a.example")
        let receipt = TabCreationProvenance(routedFrom: source, openedLink: true, profileID: p.profile, state: p.store.state)
        let openedLink = p.adopt("https://opened-link.example", creation: receipt, insertion: .top)
        let tab = try #require(p.store.state.tabs.first { $0.id == openedLink })
        #expect(p.today().first == .tab(openedLink) && tab.referrerID == nil && tab.activeTabBeforeCreationID == source)
    }

    @Test func creationPlacementIsPartOfTheDurableTodayOrder() throws {
        let p = try Placement()
        _ = p.store.open("https://child-a.example", creation: p.creationFrom(p.newer))
        _ = p.adopt("https://routed.example", creation: p.creationFrom(p.newer), insertion: .top)
        try p.store.save()
        let reloaded = try BrowserStore(directory: p.directory)
        #expect(p.today(reloaded.state) == p.today())
    }
}
