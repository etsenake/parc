import Foundation
import Testing
@testable import ParcCore

struct ExternalSplitDropTests {
    @MainActor private final class Fixture {
        let root: URL
        let store: BrowserStore
        let a: UUID, b: UUID, profile: UUID, space: UUID
        let original: BrowserState
        let group: BrowserSplitLayout
        let receipt: TabCreationProvenance
        let destination = URL(string: "https://external.invalid/path?original=a+b#section")!
        let homeSpace = UUID(), homeID = UUID(), urlID = UUID()
        let now = Date(timeIntervalSince1970: 123456)

        init() throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent("parc-external-split-" + UUID().uuidString)
            let store = try BrowserStore(directory: root)
            let a = store.openResolvedURL(URL(string: "https://one.invalid")!), b = store.openResolvedURL(URL(string: "https://two.invalid")!)
            store.setSplit([a, b])
            let profile = store.activeSpace.profileID
            let original = store.state
            self.store = store
            self.a = a; self.b = b
            self.profile = profile
            space = store.activeSpaceID
            self.original = original
            group = store.activeSplitLayout!
            receipt = TabCreationProvenance(referrerID: nil, activeTabID: a, profileID: profile, state: original)
        }

        deinit { try? FileManager.default.removeItem(at: root) }

        var aIndex: Int { original.tabs.firstIndex { $0.id == a }! }
        var bIndex: Int { original.tabs.firstIndex { $0.id == b }! }
        var tray: SidebarContainerLocation { SidebarContainerLocation(spaceID: space, folderID: nil, section: .favorite, profileID: profile) }
        let pinnedFolderID = UUID(), siblingFolderID = UUID()
        var pinnedContainer: SidebarContainerLocation { SidebarContainerLocation(spaceID: space, folderID: pinnedFolderID, section: .pinned) }

        func commit(_ store: BrowserStore, id: UUID = UUID(), selection: [UUID], layout: BrowserSplitLayout?,
                    target: SplitDropTarget, orientation: SplitOrientation = .horizontal, savedHomeID: UUID? = nil,
                    documents: [UUID: SidebarDocumentReference] = [:]) throws -> Bool {
            try store.dropExternalURLIntoSplit(destination, tabID: id, spaceID: space, profileID: profile,
                expectedSelection: selection, expectedLayout: layout, target: target, orientation: orientation,
                creation: receipt, savedHomeID: savedHomeID, documents: documents)
        }

        func proposal(_ state: BrowserState, _ target: SplitDropTarget, _ selection: [UUID], _ layout: BrowserSplitLayout?,
                      _ orientation: SplitOrientation = .vertical) -> BrowserState? {
            ExternalSplitDrop.proposal(url: destination, tabID: UUID(), state: state, spaceID: space, profileID: profile,
                selection: selection, layout: layout, target: target, orientation: orientation, creation: receipt, now: Date())
        }

        func favoriteProposal(_ state: BrowserState, _ target: SplitDropTarget, _ layout: BrowserSplitLayout? = nil,
                              home: UUID? = nil, useHome: Bool = true) -> BrowserState? {
            ExternalSplitDrop.proposal(url: destination, tabID: urlID, state: state, spaceID: space, profileID: profile,
                selection: state.selectedTabIDs, layout: layout, target: target, orientation: .vertical,
                creation: receipt, now: now, savedHomeID: useHome ? (home ?? homeID) : nil)
        }

        func fourPanes() -> (BrowserState, BrowserSplitLayout) {
            var four = original
            let c = UUID(), d = UUID()
            for extra in [c, d] { var t = original.tabs[0]; t.id = extra; four.tabs.append(t) }
            four.selectedTabIDs = [a, b, c, d]
            var fourGroup = group
            fourGroup.tabIDs = four.selectedTabIDs
            fourGroup.widthFactors = [0.25, 0.25, 0.25, 0.25]
            four.splitLayouts = [fourGroup]
            return (four, fourGroup)
        }

        func favorite() -> BrowserState {
            var favorite = original
            favorite.spaces.append(BrowserSpace(id: homeSpace, name: "Home", symbol: "star", color: "123456", profileID: profile))
            favorite.splitLayouts = []
            favorite.selectedTabIDs = [a]
            favorite.tabs[aIndex].kind = .favorite
            favorite.tabs[aIndex].spaceID = homeSpace
            favorite.tabs[aIndex].savedURL = "https://home.invalid/saved"
            favorite.tabs[aIndex].savedTitle = "Saved home"
            favorite.tabs[aIndex].customTitle = "My Favorite"
            favorite.tabs[aIndex].url = "https://away.invalid/live"
            favorite.tabs[aIndex].title = "Live page"
            favorite.tabs[aIndex].referrerID = b
            favorite.tabs[bIndex].kind = .favorite
            favorite.sidebarItemOrder[tray.key] = [.tab(b), .tab(a)]
            favorite.selectionBySpace[homeSpace.uuidString] = [a]
            return favorite
        }

        func favoriteGroupState() -> (BrowserState, BrowserSplitLayout) {
            var state = favorite()
            state.tabs[bIndex].spaceID = homeSpace
            state.selectedTabIDs = [a, b]
            var trayGroup = group
            trayGroup.spaceID = homeSpace
            trayGroup.customTitle = "Saved group"
            trayGroup.customIcon = .emoji("🌙")
            state.splitLayouts = [trayGroup]
            state.sidebarItemOrder[tray.key] = [.tab(a)]
            return (state, trayGroup)
        }

        func cappedFavorites(_ state: BrowserState) -> BrowserState {
            var capped = state
            let template = capped.tabs[aIndex]
            for i in 0..<11 { var tab = template; tab.id = UUID(); tab.title = "Favorite \(i)"; capped.tabs.append(tab) }
            return capped
        }

        func pinned() -> BrowserState {
            var state = favorite()
            let folder = BrowserFolder(id: pinnedFolderID, spaceID: space, name: "Original folder")
            let sibling = BrowserFolder(id: siblingFolderID, spaceID: space, name: "Sibling", parentID: pinnedFolderID)
            state.folders += [folder, sibling]
            for index in [aIndex, bIndex] {
                state.tabs[index].kind = .pinned
                state.tabs[index].spaceID = space
                state.tabs[index].folderID = pinnedFolderID
            }
            state.sidebarItemOrder[pinnedContainer.key] = [.tab(b), .tab(a), .folder(siblingFolderID)]
            return state
        }

        func session(_ state: BrowserState, _ name: String) throws -> URL {
            let path = root.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(state).write(to: path.appendingPathComponent("session.json"))
            return path
        }

        func breakWrites(in directory: URL) throws {
            let file = directory.appendingPathComponent("session.json")
            try FileManager.default.removeItem(at: file)
            try FileManager.default.createDirectory(at: file, withIntermediateDirectories: false)
        }
    }

    @MainActor @Test func replacingAPanePutsTheNewTabInThatPane() throws {
        let f = try Fixture()
        let id = UUID()
        #expect(try f.commit(f.store, id: id, selection: [f.a, f.b], layout: f.group, target: .replace(1), orientation: .horizontal))
        #expect(f.store.state.selectedTabIDs == [f.a, id])
    }

    @MainActor @Test func replacingAPaneLeavesTheDisplacedPageUntouched() throws {
        let f = try Fixture()
        #expect(try f.commit(f.store, selection: [f.a, f.b], layout: f.group, target: .replace(1), orientation: .horizontal))
        #expect(f.store.state.tabs.first { $0.id == f.b } == f.original.tabs.first { $0.id == f.b })
    }

    @MainActor @Test func theDroppedLinkBecomesANewTodayTabWithTheLiteralAddress() throws {
        let f = try Fixture()
        let id = UUID()
        #expect(try f.commit(f.store, id: id, selection: [f.a, f.b], layout: f.group, target: .replace(1), orientation: .horizontal))
        let new = try #require(f.store.state.tabs.first { $0.id == id })
        #expect(new.url == f.destination.absoluteString)
        #expect(new.savedURL == new.url)
        #expect(new.kind == .today)
    }

    @MainActor @Test func theDroppedLinkRemembersWhichTabWasActive() throws {
        let f = try Fixture()
        let id = UUID()
        #expect(try f.commit(f.store, id: id, selection: [f.a, f.b], layout: f.group, target: .replace(1), orientation: .horizontal))
        let new = try #require(f.store.state.tabs.first { $0.id == id })
        #expect(new.referrerID == nil)
        #expect(new.activeTabBeforeCreationID == f.a)
        #expect(new.profileID == f.profile)
    }

    @MainActor @Test func replacingAPaneKeepsTheGroupIdentityAndWidths() throws {
        let f = try Fixture()
        #expect(try f.commit(f.store, selection: [f.a, f.b], layout: f.group, target: .replace(1), orientation: .horizontal))
        #expect(f.store.activeSplitLayout?.id == f.group.id)
        #expect(f.store.activeSplitLayout?.widthFactors == f.group.widthFactors)
    }

    @MainActor @Test func theNewTabAndItsPaneSurviveAReload() throws {
        let f = try Fixture()
        let id = UUID()
        #expect(try f.commit(f.store, id: id, selection: [f.a, f.b], layout: f.group, target: .replace(1), orientation: .horizontal))
        let reopened = try BrowserStore(directory: f.root)
        #expect(reopened.state.tabs.contains { $0.id == id })
        #expect(reopened.activeSplitLayout?.tabIDs == [f.a, id])
    }

    @MainActor private func staleFixture() throws -> Fixture {
        let f = try Fixture()
        _ = try f.commit(f.store, selection: [f.a, f.b], layout: f.group, target: .replace(1), orientation: .horizontal)
        return f
    }

    @MainActor @Test func aStaleSelectionRefusesTheDrop() throws {
        let f = try staleFixture()
        #expect(try !f.commit(f.store, selection: [f.a, f.b], layout: f.group, target: .insert(1), orientation: .horizontal))
    }

    @MainActor @Test func aRefusedDropPublishesNothing() throws {
        let f = try staleFixture()
        let before = f.store.state
        _ = try f.commit(f.store, selection: [f.a, f.b], layout: f.group, target: .insert(1), orientation: .horizontal)
        #expect(f.store.state == before)
    }

    @Test(arguments: ["javascript:alert(1)", "parc://note/one", "file:///tmp/example", "data:text/plain,hello", "relative",
                      "https://user:secret@example.invalid", " https://example.invalid", "https://example.invalid\n"])
    func unownedSchemesAndCredentialsAreNotLinks(_ payload: String) {
        #expect(ExternalSplitDrop.url(payload) == nil)
    }

    @Test func aLiteralWebAddressIsAccepted() {
        let url = URL(string: "https://external.invalid/path?original=a+b#section")!
        #expect(ExternalSplitDrop.url(url.absoluteString) == url)
    }

    @MainActor @Test func insertingKeepsTheOriginalPairAroundTheNewPane() throws {
        let f = try Fixture()
        let inserted = try #require(f.proposal(f.original, .insert(1), [f.a, f.b], f.group))
        #expect(inserted.selectedTabIDs.count == 3)
        #expect(inserted.selectedTabIDs.first == f.a)
        #expect(inserted.selectedTabIDs.last == f.b)
    }

    @MainActor @Test func insertingUsesTheRequestedOrientation() throws {
        let f = try Fixture()
        let inserted = try #require(f.proposal(f.original, .insert(1), [f.a, f.b], f.group))
        #expect(inserted.splitLayouts.first?.orientation == .vertical)
    }

    @MainActor @Test func aLinkOnTheBottomBandOfASideBySidePaneStacksBelowIt() throws {
        let f = try Fixture()
        let stacked = try #require(f.proposal(f.original, .stack(0, after: true), [f.a, f.b], f.group, .horizontal))
        #expect(stacked.selectedTabIDs.count == 3)
        #expect(stacked.selectedTabIDs.first == f.a)
        #expect(stacked.selectedTabIDs.last == f.b)
        #expect(stacked.splitLayouts.first?.id == f.group.id)
        #expect(stacked.splitLayouts.first?.orientation == .horizontal)
        #expect(stacked.splitLayouts.first?.stacks?.slotSizes == [2, 1])
    }

    @MainActor @Test func insertingIntoAFullSplitIsRefused() throws {
        let f = try Fixture()
        let (four, fourGroup) = f.fourPanes()
        #expect(f.proposal(four, .insert(1), four.selectedTabIDs, fourGroup) == nil)
    }

    @MainActor @Test func replacingAtCapacityIsStillAvailable() throws {
        let f = try Fixture()
        let (four, fourGroup) = f.fourPanes()
        #expect(f.proposal(four, .replace(2), four.selectedTabIDs, fourGroup)?.selectedTabIDs.count == 4)
    }

    @MainActor @Test func stackingAtFourPanesIsRefused() throws {
        let f = try Fixture()
        let (four, fourGroup) = f.fourPanes()
        #expect(f.proposal(four, .stack(2, after: true), four.selectedTabIDs, fourGroup, .horizontal) == nil)
    }

    @MainActor @Test func aStandaloneFavoriteFormsASplitInTheCurrentSpaceKeepingItsID() throws {
        let f = try Fixture()
        let split = try #require(f.favoriteProposal(f.favorite(), .insert(1)))
        #expect(split.selectedTabIDs == [f.a, f.urlID])
        #expect(split.splitLayouts.first?.spaceID == f.space)
    }

    @MainActor @Test func theFavoriteLivePageKeepsItsAddressTitleAndReferrer() throws {
        let f = try Fixture()
        let favorite = f.favorite()
        let original = favorite.tabs[f.aIndex]
        let split = try #require(f.favoriteProposal(favorite, .insert(1)))
        let live = try #require(split.tabs.first { $0.id == f.a })
        #expect(live.kind == .today)
        #expect(live.spaceID == f.space)
        #expect(live.url == original.url)
        #expect(live.title == original.title)
        #expect(live.referrerID == f.b)
    }

    @MainActor @Test func theFavoriteSavedHomeKeepsItsProfileSpaceAndSavedPage() throws {
        let f = try Fixture()
        let favorite = f.favorite()
        let original = favorite.tabs[f.aIndex]
        let split = try #require(f.favoriteProposal(favorite, .insert(1)))
        let home = try #require(split.tabs.first { $0.id == f.homeID })
        #expect(home.kind == .favorite)
        #expect(home.spaceID == f.homeSpace)
        #expect(home.profileID == f.profile)
        #expect(home.url == original.savedURL)
        #expect(home.title == original.savedTitle)
    }

    @MainActor @Test func theFavoriteSavedHomeKeepsItsTitleOverrideAndFreshCreationReceipt() throws {
        let f = try Fixture()
        let favorite = f.favorite()
        let original = favorite.tabs[f.aIndex]
        let split = try #require(f.favoriteProposal(favorite, .insert(1)))
        let home = try #require(split.tabs.first { $0.id == f.homeID })
        #expect(home.customTitle == original.customTitle)
        #expect(home.savedURL == original.savedURL)
        #expect(home.referrerID == nil)
        #expect(home.activeTabBeforeCreationID == f.a)
    }

    @MainActor @Test func theSavedHomeTakesTheFavoriteTraySlot() throws {
        let f = try Fixture()
        let split = try #require(f.favoriteProposal(f.favorite(), .insert(1)))
        #expect(SidebarHierarchy.children(in: f.tray, state: split) == [.tab(f.b), .tab(f.homeID)])
    }

    @MainActor @Test func returningToTheHomeSpaceFollowsTheSavedHome() throws {
        let f = try Fixture()
        let split = try #require(f.favoriteProposal(f.favorite(), .insert(1)))
        #expect(split.selectionBySpace[f.homeSpace.uuidString] == [f.homeID])
    }

    @MainActor @Test func retryingAFavoriteDropKeepsTheFixedIdentities() throws {
        let f = try Fixture()
        let favorite = f.favorite()
        let first = try #require(f.favoriteProposal(favorite, .insert(1)))
        #expect(f.favoriteProposal(favorite, .insert(1))?.tabs == first.tabs)
    }

    @MainActor @Test(arguments: ["missing", "original", "new"])
    func aMissingOrCollidingHomeIdentityRefusesTheDrop(_ kind: String) throws {
        let f = try Fixture()
        let proposal: BrowserState?
        switch kind {
        case "missing": proposal = f.favoriteProposal(f.favorite(), .insert(1), useHome: false)
        case "original": proposal = f.favoriteProposal(f.favorite(), .insert(1), home: f.a)
        default: proposal = f.favoriteProposal(f.favorite(), .insert(1), home: f.urlID)
        }
        #expect(proposal == nil)
    }

    @MainActor @Test func replacingASingleFavoriteLeavesItUntouchedWithoutACopy() throws {
        let f = try Fixture()
        let favorite = f.favorite()
        let center = try #require(f.favoriteProposal(favorite, .replace(0), useHome: false))
        #expect(center.tabs.first { $0.id == f.a } == favorite.tabs[f.aIndex])
        #expect(!center.tabs.contains { $0.id == f.homeID })
    }

    @MainActor @Test func replacingASingleFavoriteChoosesOnlyTheNewPage() throws {
        let f = try Fixture()
        let center = try #require(f.favoriteProposal(f.favorite(), .replace(0), useHome: false))
        #expect(center.selectedTabIDs == [f.urlID])
        #expect(center.splitLayouts.isEmpty)
    }

    @MainActor @Test func aFavoriteGroupTakesAFavoriteChildInTheHomeSpace() throws {
        let f = try Fixture()
        let (state, trayGroup) = f.favoriteGroupState()
        let added = try #require(f.favoriteProposal(state, .insert(1), trayGroup))
        let child = added.tabs.first { $0.id == f.urlID }
        #expect(child?.kind == .favorite)
        #expect(child?.spaceID == f.homeSpace)
    }

    @MainActor @Test func aFavoriteGroupKeepsItsIdentityAppearanceAndChildOrder() throws {
        let f = try Fixture()
        let (state, trayGroup) = f.favoriteGroupState()
        let added = try #require(f.favoriteProposal(state, .insert(1), trayGroup))
        #expect(added.splitLayouts[0].id == trayGroup.id)
        #expect(added.splitLayouts[0].customTitle == trayGroup.customTitle)
        #expect(added.splitLayouts[0].customIcon == trayGroup.customIcon)
        #expect(added.splitLayouts[0].tabIDs == [f.a, f.urlID, f.b])
    }

    @MainActor @Test func aFavoriteGroupNeverDuplicatesItsOriginalChildren() throws {
        let f = try Fixture()
        let (state, trayGroup) = f.favoriteGroupState()
        let added = try #require(f.favoriteProposal(state, .insert(1), trayGroup))
        #expect(!added.tabs.contains { $0.id == f.homeID })
        #expect(SidebarHierarchy.children(in: f.tray, state: added) == [.split(trayGroup.id)])
    }

    @MainActor @Test func replacingInAFavoriteGroupKeepsTheDisplacedFavoriteAndGeometry() throws {
        let f = try Fixture()
        let (state, trayGroup) = f.favoriteGroupState()
        let replaced = try #require(f.favoriteProposal(state, .replace(0), trayGroup))
        #expect(replaced.tabs.first { $0.id == f.a } == state.tabs[f.aIndex])
        #expect(replaced.splitLayouts[0].widthFactors == trayGroup.widthFactors)
    }

    @MainActor @Test func theReplacedAnchorKeepsTheGroupTraySlotBeforeTheDisplacedFavorite() throws {
        let f = try Fixture()
        let (state, trayGroup) = f.favoriteGroupState()
        let replaced = try #require(f.favoriteProposal(state, .replace(0), trayGroup))
        #expect(SidebarHierarchy.children(in: f.tray, state: replaced) == [.split(trayGroup.id), .tab(f.a)])
    }

    @MainActor @Test func aThirteenthFavoriteRootIsRefused() throws {
        let f = try Fixture()
        let (state, trayGroup) = f.favoriteGroupState()
        let capped = f.cappedFavorites(state)
        #expect(SidebarHierarchy.children(in: f.tray, state: capped).count == 12)
        #expect(f.favoriteProposal(capped, .replace(0), trayGroup) == nil)
    }

    @MainActor @Test func insertingIntoAFavoriteGroupDoesNotConsumeATrayRoot() throws {
        let f = try Fixture()
        let (state, trayGroup) = f.favoriteGroupState()
        #expect(f.favoriteProposal(f.cappedFavorites(state), .insert(1), trayGroup) != nil)
    }

    @MainActor @Test func aMixedFavoriteAndTodayGroupRefusesWithoutConversion() throws {
        let f = try Fixture()
        let (state, trayGroup) = f.favoriteGroupState()
        var mixed = state
        mixed.tabs[f.bIndex].kind = .today
        mixed.tabs[f.bIndex].spaceID = f.space
        #expect(f.favoriteProposal(mixed, .insert(1), trayGroup) == nil)
    }

    @MainActor @Test func aPinnedEdgeDropKeepsTheRequestedPaneOrderWithTheOriginalLiveID() throws {
        let f = try Fixture()
        let split = try #require(f.favoriteProposal(f.pinned(), .insert(0)))
        #expect(split.selectedTabIDs == [f.urlID, f.a])
        #expect(split.splitLayouts[0].tabIDs == [f.urlID, f.a])
    }

    @MainActor @Test func aPinnedLivePageMovesToTodayWithoutLosingItsAddressOrReferrer() throws {
        let f = try Fixture()
        let pinned = f.pinned()
        let original = pinned.tabs[f.aIndex]
        let split = try #require(f.favoriteProposal(pinned, .insert(0)))
        let live = try #require(split.tabs.first { $0.id == f.a })
        #expect(live.kind == .today)
        #expect(live.folderID == nil)
        #expect(live.url == original.url)
        #expect(live.referrerID == original.referrerID)
    }

    @MainActor @Test func aPinnedSavedHomeKeepsItsFolderAndSavedMetadata() throws {
        let f = try Fixture()
        let pinned = f.pinned()
        let original = pinned.tabs[f.aIndex]
        let split = try #require(f.favoriteProposal(pinned, .insert(0)))
        let home = try #require(split.tabs.first { $0.id == f.homeID })
        #expect(home.kind == .pinned)
        #expect(home.folderID == f.pinnedFolderID)
        #expect(home.spaceID == f.space)
        #expect(home.url == original.savedURL)
        #expect(home.customTitle == original.customTitle)
    }

    @MainActor @Test func aPinnedSavedHomeTakesTheExactSiblingSlot() throws {
        let f = try Fixture()
        let split = try #require(f.favoriteProposal(f.pinned(), .insert(0)))
        #expect(SidebarHierarchy.children(in: f.pinnedContainer, state: split) == [.tab(f.b), .tab(f.homeID), .folder(f.siblingFolderID)])
    }

    @MainActor @Test func aPinnedDropLeavesUnrelatedSiblingsAndFoldersIntact() throws {
        let f = try Fixture()
        let pinned = f.pinned()
        let split = try #require(f.favoriteProposal(pinned, .insert(0)))
        #expect(split.tabs.first { $0.id == f.b } == pinned.tabs[f.bIndex])
        #expect(split.folders == pinned.folders)
    }

    @MainActor @Test func replacingAPinnedPaneLeavesTheSavedItemIntact() throws {
        let f = try Fixture()
        let pinned = f.pinned()
        #expect(f.favoriteProposal(pinned, .replace(0), useHome: false)?.tabs.first { $0.id == f.a } == pinned.tabs[f.aIndex])
    }

    @MainActor @Test func aPinnedEdgeDropNeedsItsFixedSavedHomeIdentity() throws {
        let f = try Fixture()
        #expect(f.favoriteProposal(f.pinned(), .insert(0), useHome: false) == nil)
    }

    @MainActor @Test func anExistingPinnedGroupTakesTheLinkWithoutSavedHomeCopies() throws {
        let f = try Fixture()
        var state = f.pinned()
        state.selectedTabIDs = [f.a, f.b]
        state.splitLayouts = [f.group]
        let within = try #require(f.favoriteProposal(state, .insert(1), f.group))
        #expect(!within.tabs.contains { $0.id == f.homeID })
        #expect(within.splitLayouts[0].id == f.group.id)
    }

    @MainActor @Test func aMissingPinnedFolderRefusesTheWholeCreation() throws {
        let f = try Fixture()
        var state = f.pinned()
        state.folders.removeAll { $0.id == f.pinnedFolderID }
        #expect(f.favoriteProposal(state, .insert(0)) == nil)
    }

    @MainActor @Test func aFavoriteFromAnotherProfileRefuses() throws {
        let f = try Fixture()
        var state = f.favorite()
        state.tabs[f.aIndex].profileID = UUID()
        #expect(f.favoriteProposal(state, .insert(1)) == nil)
    }

    @MainActor @Test func aMissingSavedHomeSpaceRefuses() throws {
        let f = try Fixture()
        var state = f.favorite()
        state.spaces.removeAll { $0.id == f.homeSpace }
        #expect(f.favoriteProposal(state, .insert(1)) == nil)
    }

    @MainActor @Test func aFavoriteSplitCommitsAtomicallyThroughTheStore() throws {
        let f = try Fixture()
        let store = try BrowserStore(directory: f.session(f.favorite(), "favorite"))
        #expect(try f.commit(store, id: f.urlID, selection: [f.a], layout: nil, target: .insert(1), orientation: .vertical, savedHomeID: f.homeID))
    }

    @MainActor @Test func theSavedHomeAndLivePlacementSurviveAReload() throws {
        let f = try Fixture()
        let directory = try f.session(f.favorite(), "favorite")
        let original = f.favorite().tabs[f.aIndex]
        let store = try BrowserStore(directory: directory)
        _ = try f.commit(store, id: f.urlID, selection: [f.a], layout: nil, target: .insert(1), orientation: .vertical, savedHomeID: f.homeID)
        let loaded = try BrowserStore(directory: directory)
        #expect(loaded.state.tabs.contains { $0.id == f.homeID && $0.url == original.savedURL })
        #expect(loaded.state.tabs.contains { $0.id == f.a && $0.kind == .today })
    }

    @MainActor @Test func aFailedFavoriteCommitKeepsTheOriginalStateExactly() throws {
        let f = try Fixture()
        let directory = try f.session(f.favorite(), "favorite-failure")
        let store = try BrowserStore(directory: directory)
        let before = store.state
        try f.breakWrites(in: directory)
        #expect(throws: (any Error).self) {
            _ = try f.commit(store, id: f.urlID, selection: [f.a], layout: nil, target: .insert(1), orientation: .vertical, savedHomeID: f.homeID)
        }
        #expect(store.state == before)
        #expect(store.persistenceError != nil)
    }

    @MainActor @Test func aPinnedSplitCommitReopensWithHomeOrderAndLiveSelectionTogether() throws {
        let f = try Fixture()
        let directory = try f.session(f.pinned(), "pinned")
        let store = try BrowserStore(directory: directory)
        #expect(try f.commit(store, id: f.urlID, selection: [f.a], layout: nil, target: .insert(0), orientation: .vertical, savedHomeID: f.homeID))
        let reloaded = try BrowserStore(directory: directory)
        #expect(SidebarHierarchy.children(in: f.pinnedContainer, state: reloaded.state) == [.tab(f.b), .tab(f.homeID), .folder(f.siblingFolderID)])
        #expect(reloaded.state.selectedTabIDs == [f.urlID, f.a])
    }

    @MainActor @Test func aFlatSplitReopensAsAFlatSplit() throws {
        let f = try Fixture()
        let store = try BrowserStore(directory: f.session(f.original, "stack"))
        #expect(store.activeSplitLayout?.id == f.group.id)
        #expect(store.activeSplitLayout?.stacks == nil)
    }

    @MainActor @Test func aLinkOnTheTopBandOfAFlatSplitCommitsAStack() throws {
        let f = try Fixture()
        let store = try BrowserStore(directory: f.session(f.original, "stack"))
        #expect(try f.commit(store, selection: [f.a, f.b], layout: store.activeSplitLayout, target: .stack(1, after: false)))
    }

    @MainActor @Test func theStackedTabAndItsStackReopenTogether() throws {
        let f = try Fixture()
        let directory = try f.session(f.original, "stack")
        let store = try BrowserStore(directory: directory)
        let id = UUID()
        _ = try f.commit(store, id: id, selection: [f.a, f.b], layout: store.activeSplitLayout, target: .stack(1, after: false))
        let reloaded = try BrowserStore(directory: directory)
        #expect(reloaded.state.selectedTabIDs == [f.a, id, f.b])
        #expect(reloaded.activeSplitLayout?.id == f.group.id)
        #expect(reloaded.activeSplitLayout?.orientation == .horizontal)
        #expect(reloaded.activeSplitLayout?.stacks?.slotSizes == [1, 2])
        #expect(reloaded.state.tabs.first { $0.id == id }?.url == f.destination.absoluteString)
    }

    @MainActor @Test func aLinkJoinsAnExistingStackBelowTheStackedPane() throws {
        let f = try Fixture()
        let store = try BrowserStore(directory: f.session(f.original, "stack"))
        let stackID = UUID(), joinID = UUID()
        _ = try f.commit(store, id: stackID, selection: [f.a, f.b], layout: store.activeSplitLayout, target: .stack(1, after: false))
        #expect(try f.commit(store, id: joinID, selection: [f.a, stackID, f.b], layout: store.activeSplitLayout, target: .stack(2, after: true)))
        #expect(store.state.selectedTabIDs == [f.a, stackID, f.b, joinID])
        #expect(store.activeSplitLayout?.stacks?.slotSizes == [1, 3])
        #expect(store.activeSplitLayout?.id == f.group.id)
    }

    @MainActor @Test func aFullStackedSplitRefusesAnotherLink() throws {
        let f = try Fixture()
        let store = try BrowserStore(directory: f.session(f.original, "stack"))
        _ = try f.commit(store, selection: [f.a, f.b], layout: store.activeSplitLayout, target: .stack(1, after: false))
        let second = UUID()
        _ = try f.commit(store, id: second, selection: store.state.selectedTabIDs, layout: store.activeSplitLayout, target: .stack(2, after: true))
        let full = store.state
        #expect(try !f.commit(store, selection: full.selectedTabIDs, layout: store.activeSplitLayout, target: .stack(0, after: false)))
        #expect(store.state == full)
    }

    struct DocumentCase: Sendable, CustomTestStringConvertible {
        let isNote: Bool
        let isFavorite: Bool
        var testDescription: String { (isNote ? "note " : "easel ") + (isFavorite ? "favorite" : "pinned") }
        static let all = [DocumentCase(isNote: true, isFavorite: true), DocumentCase(isNote: true, isFavorite: false),
                          DocumentCase(isNote: false, isFavorite: true), DocumentCase(isNote: false, isFavorite: false)]
    }

    @MainActor private struct SharedDocument {
        let reference: SidebarDocumentReference
        let address: String

        init(_ f: Fixture, note: Bool) throws {
            if note {
                let file = f.root.appendingPathComponent("Shared Note.md")
                try FileManager.default.createDirectory(at: f.root, withIntermediateDirectories: true)
                try Data().write(to: file)
                reference = SidebarDocumentReference(page: .note(file), profileID: f.profile) {
                    guard FileManager.default.fileExists(atPath: file.path) else { throw CocoaError(.fileNoSuchFile) }
                }
                address = InternalPage.note(file).urlString
            } else {
                let easels = try EaselStore(directory: f.root.appendingPathComponent("easels"))
                let easel = try easels.create()
                reference = SidebarDocumentReference(page: .easel(easel.document.id), profileID: f.profile) { try easels.validateReference(easel.document.id) }
                address = "parc://easel/" + easel.document.id.uuidString
            }
        }
    }

    @MainActor private func documentStore(_ f: Fixture, _ item: DocumentCase) throws -> (BrowserStore, SharedDocument) {
        let document = try SharedDocument(f, note: item.isNote)
        var state = item.isFavorite ? f.favorite() : f.pinned()
        state.tabs[f.aIndex].url = document.address
        state.tabs[f.aIndex].savedURL = document.address
        let directory = try f.session(state, item.testDescription.replacingOccurrences(of: " ", with: "-"))
        return (try BrowserStore(directory: directory), document)
    }

    @MainActor @Test(arguments: DocumentCase.all)
    func aTypedSavedHomeNeedsTheOriginalDocumentToBeValidated(_ item: DocumentCase) throws {
        let f = try Fixture()
        let (store, _) = try documentStore(f, item)
        #expect(try !f.commit(store, id: f.urlID, selection: [f.a], layout: nil, target: .insert(1), orientation: .vertical, savedHomeID: f.homeID))
    }

    @MainActor @Test(arguments: DocumentCase.all)
    func anUnvalidatedDocumentAliasPublishesNothing(_ item: DocumentCase) throws {
        let f = try Fixture()
        let (store, _) = try documentStore(f, item)
        let before = store.state
        _ = try f.commit(store, id: f.urlID, selection: [f.a], layout: nil, target: .insert(1), orientation: .vertical, savedHomeID: f.homeID)
        #expect(store.state == before)
    }

    @MainActor @Test(arguments: DocumentCase.all)
    func aValidatedTypedSavedHomeCommits(_ item: DocumentCase) throws {
        let f = try Fixture()
        let (store, document) = try documentStore(f, item)
        #expect(try f.commit(store, id: f.urlID, selection: [f.a], layout: nil, target: .insert(1), orientation: .vertical,
                             savedHomeID: f.homeID, documents: [f.a: document.reference]))
    }

    @MainActor @Test(arguments: DocumentCase.all)
    func theTypedOriginalAndItsHomeShareTheSameDocument(_ item: DocumentCase) throws {
        let f = try Fixture()
        let (store, document) = try documentStore(f, item)
        _ = try f.commit(store, id: f.urlID, selection: [f.a], layout: nil, target: .insert(1), orientation: .vertical,
                         savedHomeID: f.homeID, documents: [f.a: document.reference])
        #expect(store.state.tabs.first { $0.id == f.homeID }?.url == document.address)
        #expect(store.state.tabs.first { $0.id == f.a }?.url == document.address)
    }

    @MainActor @Test func aSplitKeepsItsCustomTitleAndIconWhenAURLReplacesAPane() throws {
        let f = try Fixture()
        var decorated = f.original
        var decoratedGroup = f.group
        decoratedGroup.customTitle = "Original group"
        decoratedGroup.customIcon = .emoji("🌙")
        decorated.splitLayouts = [decoratedGroup]
        let preserved = try #require(f.proposal(decorated, .replace(0), [f.a, f.b], decoratedGroup))
        #expect(preserved.splitLayouts.first?.customTitle == decoratedGroup.customTitle)
        #expect(preserved.splitLayouts.first?.customIcon == decoratedGroup.customIcon)
    }

    @MainActor @Test func replacingAPaneLeavesLocalDocumentReferencesUntouched() throws {
        let f = try Fixture()
        var documents = f.original
        documents.tabs[0].url = "parc://note/" + UUID().uuidString
        documents.tabs[0].savedURL = documents.tabs[0].url
        documents.tabs[1].url = "parc://easel/" + UUID().uuidString
        documents.tabs[1].savedURL = documents.tabs[1].url
        let replacement = try #require(f.proposal(documents, .replace(1), [f.a, f.b], f.group))
        #expect(replacement.tabs.first { $0.id == f.b } == documents.tabs.first { $0.id == f.b })
        #expect(replacement.tabs.first { $0.id == f.a }?.url == documents.tabs.first { $0.id == f.a }?.url)
    }

    @MainActor @Test func anOriginalFromAnotherProfileRefuses() throws {
        let f = try Fixture()
        var moved = f.original
        moved.tabs[0].profileID = UUID()
        #expect(f.proposal(moved, .insert(1), [f.a, f.b], f.group) == nil)
    }

    @MainActor @Test func anArchivedOriginalRefuses() throws {
        let f = try Fixture()
        var archived = f.original
        archived.tabs[0].archivedAt = Date()
        #expect(f.proposal(archived, .insert(1), [f.a, f.b], f.group) == nil)
    }

    @MainActor @Test(arguments: [true, false])
    func anOutOfRangeTargetRefuses(_ insertion: Bool) throws {
        let f = try Fixture()
        let target = insertion ? SplitDropTarget.insert(8) : .replace(-1)
        #expect(f.proposal(f.original, target, [f.a, f.b], f.group) == nil)
    }

    @MainActor @Test func aFailedWriteKeepsTheOriginalStateAndReportsTheError() throws {
        let f = try Fixture()
        let current = f.store.state, currentGroup = try #require(f.store.activeSplitLayout)
        try f.breakWrites(in: f.root)
        #expect(throws: (any Error).self) {
            _ = try f.commit(f.store, selection: current.selectedTabIDs, layout: currentGroup, target: .insert(0))
        }
        #expect(f.store.state == current)
        #expect(f.store.persistenceError != nil)
    }
}
