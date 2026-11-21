import Foundation
import Testing
@testable import ParcCore

@MainActor
struct PeekReferrerPoolTests {
    @MainActor final class Fixture {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store: BrowserStore
        let source: UUID
        let other: UUID
        let profile: UUID
        let space: UUID
        let path: String
        let receipt: TabCreationProvenance
        var window: WindowPresentation

        init() throws {
            store = try BrowserStore(directory: directory)
            source = store.open("https://source.example", kind: .pinned)
            other = store.open("https://unrelated.example")
            profile = store.activeSpace.profileID
            space = store.activeSpaceID
            path = store.independentEngineProfilePath(for: profile)
            receipt = TabCreationProvenance(referrerID: source, activeTabID: other, profileID: profile, state: store.state)
            window = WindowPresentation(state: store.state, ready: true)
        }

        deinit { try? FileManager.default.removeItem(at: directory) }

        func adopt(_ url: String, _ title: String, creation: TabCreationProvenance? = nil, space: UUID? = nil) -> UUID {
            store.adoptNativePage(url: URL(string: url), title: title, profilePath: path,
                                  preferredSpaceID: space ?? self.space, select: false, creation: creation)!
        }

        func recordsPromotion(_ id: UUID, state: BrowserState? = nil) -> Bool {
            window.recordPeekPromotion(id, state: state ?? store.state)
        }

        func finishes(_ selection: FolderRemovalSelection) -> Bool {
            window.finishFolderRemoval(selection, state: store.state, available: { _ in true })
        }

        func promote() -> UUID {
            let promoted = adopt("https://peek.example/result", "Original Peek", creation: receipt)
            _ = window.recordPeekPromotion(promoted, state: store.state)
            return promoted
        }

        func returnSelection(removing promoted: UUID, selected: [UUID]? = nil, available: @escaping (UUID) -> Bool = { _ in true })
            -> FolderRemovalSelection? {
            FolderRemovalSelection.resolve(removing: [promoted], spaceID: space, profileID: profile, state: store.state,
                                           selected: selected ?? [promoted], focused: promoted,
                                           referrerPool: window.referrerPool, available: available)
        }
    }

    @Test func ordinaryCreationSeedsTheOriginalChainAndExplicitReferrersStillUnion() throws {
        let f = try Fixture()
        let ordinary = f.store.open("https://ordinary.example", creation: f.receipt)
        f.window.recordCreation(ordinary, state: f.store.state)
        #expect(f.window.referrerPool == [f.source, ordinary])
        let next = f.store.open("https://next.example", creation: f.receipt)
        f.window.recordCreation(next, state: f.store.state)
        #expect(f.window.referrerPool == [f.source, ordinary, next])
    }

    @Test func anAdoptedPageRecordsTheOriginalModalSourceForBothIdentities() throws {
        let f = try Fixture()
        let promoted = f.adopt("https://peek.example/result", "Original Peek", creation: f.receipt)
        let tab = try #require(f.store.state.tabs.first { $0.id == promoted })
        #expect(tab.referrerID == f.source && tab.activeTabBeforeCreationID == f.source)
    }

    @Test func adoptionRecordsTheActualPageMetadataWithoutAnotherNavigation() throws {
        let f = try Fixture()
        let promoted = f.adopt("https://peek.example/result", "Original Peek", creation: f.receipt)
        let tab = try #require(f.store.state.tabs.first { $0.id == promoted })
        #expect(tab.url == "https://peek.example/result" && tab.title == "Original Peek")
    }

    @Test func aProvisionalModelRecordIsNotAnAcceptedPromotion() throws {
        let f = try Fixture()
        let ordinary = f.store.open("https://ordinary.example", creation: f.receipt)
        f.window.recordCreation(ordinary, state: f.store.state)
        let selection = f.window.selectedTabIDs
        _ = f.adopt("https://peek.example/result", "Original Peek", creation: f.receipt)
        #expect(f.window.referrerPool == [f.source, ordinary])
        #expect(f.window.selectedTabIDs == selection)
    }

    @Test func anAcceptedPromotionReplacesTheOldChainWithTheExactPairAndOtherWindowsNeverSeeIt() throws {
        let f = try Fixture()
        let peer = WindowPresentation(state: f.store.state, ready: true)
        let ordinary = f.store.open("https://ordinary.example", creation: f.receipt)
        f.window.recordCreation(ordinary, state: f.store.state)
        let promoted = f.adopt("https://peek.example/result", "Original Peek", creation: f.receipt)
        #expect(f.recordsPromotion(promoted, state: f.store.state))
        #expect(f.window.referrerPool == [f.source, promoted])
        #expect(peer.referrerPool.isEmpty)
    }

    @Test func selectingThePromotedTodayItemPreservesTheModalPair() throws {
        let f = try Fixture()
        let promoted = f.promote()
        f.window.adopt(promoted, state: f.store.state, foreground: true)
        f.window.recordSelectionForReturn(promoted, state: f.store.state)
        #expect(f.window.referrerPool == [f.source, promoted])
    }

    @Test func closingThePromotedItemReturnsToItsOriginalPinnedSource() throws {
        let f = try Fixture()
        let promoted = f.promote()
        f.window.adopt(promoted, state: f.store.state, foreground: true)
        f.window.recordSelectionForReturn(promoted, state: f.store.state)
        let selected = try #require(f.returnSelection(removing: promoted))
        #expect(selected.tabIDs == [f.source])
    }

    @Test func aSourceUnavailableToThisWindowCannotBeReclaimed() throws {
        let f = try Fixture()
        let promoted = f.promote()
        f.window.adopt(promoted, state: f.store.state, foreground: true)
        let source = f.source
        let unavailable = try #require(f.returnSelection(removing: promoted, available: { $0 != source }))
        #expect(unavailable.tabIDs != [f.source])
    }

    @Test func selectingTheOriginalSavedSourceUsesTheSingletonTransition() throws {
        let f = try Fixture()
        _ = f.promote()
        f.window.recordSelectionForReturn(f.source, state: f.store.state)
        #expect(f.window.referrerPool == [f.source])
    }

    @Test func aSplitPromotionKeepsBothOriginalItemsAndTheNewModalPair() throws {
        let f = try Fixture()
        let promoted = f.promote()
        f.window.recordSelectionForReturn(f.source, state: f.store.state)
        #expect(f.recordsPromotion(promoted, state: f.store.state))
        f.store.setSplit([f.source, promoted])
        f.window.captureCommand(f.store.state) { _ in true }
        f.window.recordSelectionForReturn(promoted, state: f.store.state)
        #expect(f.window.selectedTabIDs == [f.source, promoted])
        #expect(f.window.referrerPool == [f.source, promoted])
    }

    @Test func theSurvivingOriginalSplitPanePrecedesOtherReturnCandidates() throws {
        let f = try Fixture()
        let promoted = f.promote()
        f.store.setSplit([f.source, promoted])
        f.window.captureCommand(f.store.state) { _ in true }
        f.window.recordSelectionForReturn(promoted, state: f.store.state)
        let surviving = try #require(f.returnSelection(removing: promoted, selected: [f.source, promoted]))
        #expect(surviving.tabIDs == [f.source])
    }

    @Test func promotionIsRefusedForAnUnknownItem() throws {
        let f = try Fixture()
        _ = f.promote()
        #expect(!f.recordsPromotion(UUID()))
    }

    @Test func promotionIsRefusedWhenTheStateIsInvalid() throws {
        let f = try Fixture()
        let promoted = f.promote()
        let valid = f.store.state
        let pair = f.window.referrerPool
        func index(_ id: UUID, in state: BrowserState) -> Int { state.tabs.firstIndex { $0.id == id }! }

        var closed = valid
        closed.tabs[index(promoted, in: closed)].archivedAt = Date()
        #expect(!f.recordsPromotion(promoted, state: closed))

        var missing = valid
        missing.tabs.removeAll { $0.id == f.source }
        #expect(!f.recordsPromotion(promoted, state: missing))

        var archivedSource = valid
        archivedSource.tabs[index(f.source, in: archivedSource)].archivedAt = Date()
        #expect(!f.recordsPromotion(promoted, state: archivedSource))

        var foreignSource = valid
        foreignSource.tabs[index(f.source, in: foreignSource)].profileID = UUID()
        #expect(!f.recordsPromotion(promoted, state: foreignSource))

        var foreignItem = valid
        foreignItem.tabs[index(promoted, in: foreignItem)].profileID = UUID()
        #expect(!f.recordsPromotion(promoted, state: foreignItem))

        var selfSource = valid
        selfSource.tabs[index(promoted, in: selfSource)].referrerID = promoted
        #expect(!f.recordsPromotion(promoted, state: selfSource))

        #expect(f.window.referrerPool == pair)
    }

    @Test func aWindowSourceModalProducesExactlyASingleton() throws {
        let f = try Fixture()
        _ = f.promote()
        let ownerless = f.adopt("https://window.example", "Window source")
        #expect(f.recordsPromotion(ownerless, state: f.store.state))
        #expect(f.window.referrerPool == [ownerless])
    }

    @Test func aRolledBackNativeOwnershipLeavesNoPromotionTransition() throws {
        let f = try Fixture()
        let promoted = f.promote()
        let pair = f.window.referrerPool
        let discarded = f.adopt("https://refused.example", "Refused", creation: f.receipt)
        f.store.removeTab(discarded)
        #expect(f.window.referrerPool == pair)
        #expect(!f.recordsPromotion(discarded, state: f.store.state))
        #expect(f.window.referrerPool == pair)
        #expect(f.store.state.tabs.contains { $0.id == promoted })
    }

    @Test func restorationNeverManufacturesAPoolFromDurableProvenance() throws {
        let f = try Fixture()
        _ = f.promote()
        #expect(WindowPresentation(state: f.store.state, ready: true).referrerPool.isEmpty)
    }

    @Test func aRefusedCloseKeepsThePromotedItemAndARetryRevalidates() throws {
        let f = try Fixture()
        let promoted = f.promote()
        f.window.adopt(promoted, state: f.store.state, foreground: true)
        let surviving = try #require(f.returnSelection(removing: promoted))
        var validator: (() -> Bool)?, completion: ((Bool) -> Void)?, closed: Bool?
        f.store.requestPageRetirement = { _, validate, complete in validator = validate; completion = complete }
        f.store.closeTabs([promoted], selection: surviving, shouldCommit: { true }) { closed = $0 }
        #expect(validator?() == true && closed == nil)
        completion?(false)
        #expect(closed == false && f.store.state.tabs.first { $0.id == promoted }?.archivedAt == nil)
        f.store.closeTabs([promoted], selection: surviving, shouldCommit: { true }) { closed = $0 }
        #expect(validator?() == true)
    }

    @Test func anAcceptedCloseArchivesOnlyThePromotedItemAndReturnsToTheOriginalSource() throws {
        let f = try Fixture()
        let promoted = f.promote()
        f.window.adopt(promoted, state: f.store.state, foreground: true)
        f.window.recordSelectionForReturn(promoted, state: f.store.state)
        f.window.recordSelectionForReturn(f.source, state: f.store.state)
        #expect(f.recordsPromotion(promoted))
        f.store.setSplit([f.source, promoted])
        f.window.captureCommand(f.store.state) { _ in true }
        f.window.recordSelectionForReturn(promoted, state: f.store.state)
        let surviving = try #require(f.returnSelection(removing: promoted, selected: [f.source, promoted]))
        var validator: (() -> Bool)?, completion: ((Bool) -> Void)?, closed: Bool?
        f.store.requestPageRetirement = { _, validate, complete in validator = validate; completion = complete }
        f.store.closeTabs([promoted], selection: surviving, shouldCommit: { true }) { closed = $0 }
        #expect(validator?() == true)
        completion?(true)
        #expect(closed == true)
        #expect(f.store.state.tabs.first { $0.id == promoted }?.archivedAt != nil)
        #expect(f.finishes(surviving))
        #expect(f.store.state.tabs.first { $0.id == f.source }?.kind == .today)
        #expect(f.window.selectedTabIDs == [f.source] && f.window.referrerPool == [f.source, promoted])
    }

    @Test func promotionFromAPinnedSourceReturnsToThatSourceOnClose() throws {
        let f = try Fixture()
        let savedSource = f.store.open("https://saved-source.example", kind: .pinned)
        let savedReceipt = TabCreationProvenance(referrerID: savedSource, activeTabID: savedSource,
                                                 profileID: f.profile, state: f.store.state)
        let modal = f.adopt("https://modal.example/result", "Modal", creation: savedReceipt)
        var savedWindow = WindowPresentation(state: f.store.state, ready: true)
        savedWindow.recordSelectionForReturn(savedSource, state: f.store.state)
        let recorded = savedWindow.recordPeekPromotion(modal, state: f.store.state)
        #expect(recorded)
        savedWindow.adopt(modal, state: f.store.state, foreground: true)
        savedWindow.recordSelectionForReturn(modal, state: f.store.state)
        let modalReturn = try #require(FolderRemovalSelection.resolve(
            removing: [modal], spaceID: f.space, profileID: f.profile, state: f.store.state, selected: [modal],
            focused: modal, referrerPool: savedWindow.referrerPool, available: { _ in true }))
        #expect(modalReturn.tabIDs == [savedSource])
        var validator: (() -> Bool)?, completion: ((Bool) -> Void)?, closed: Bool?
        f.store.requestPageRetirement = { _, validate, complete in validator = validate; completion = complete }
        f.store.closeTabs([modal], selection: modalReturn, shouldCommit: { true }) { closed = $0 }
        #expect(validator?() == true)
        completion?(true)
        #expect(closed == true)
        let finished = savedWindow.finishFolderRemoval(modalReturn, state: f.store.state, available: { _ in true })
        #expect(finished)
        #expect(savedWindow.selectedTabIDs == [savedSource] && savedWindow.referrerPool == [savedSource])
    }

    @Test func aGlobalFavoritesPromotedPageEntersTheCurrentSpaceKeepingItsProfileAndReferrer() throws {
        let f = try Fixture()
        let favorite = f.store.open("https://global-favorite.example", kind: .favorite)
        let favoriteSpace = try #require(f.store.state.tabs.first { $0.id == favorite }).spaceID
        let destination = f.store.createSpace(name: "Current Window Space")
        let favoriteReceipt = TabCreationProvenance(referrerID: favorite, activeTabID: nil,
                                                    profileID: f.profile, state: f.store.state)
        let modal = f.adopt("https://peek.example/original-document", "Original", creation: favoriteReceipt, space: destination)
        let tab = try #require(f.store.state.tabs.first { $0.id == modal })
        #expect(destination != favoriteSpace && tab.spaceID == destination)
        #expect(tab.profileID == f.profile && tab.referrerID == favorite)
        var favoriteWindow = WindowPresentation(state: f.store.state, ready: true)
        let recorded = favoriteWindow.recordPeekPromotion(modal, state: f.store.state)
        #expect(recorded)
    }
}
