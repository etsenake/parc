import Foundation
import Testing
@testable import ParcCore

extension SidebarSpaceMoveTestsSupport {
    struct SidebarSpaceMoveRevealAndOwnershipTests {
        @Test func revealOpensTheActualFolder() throws {
            let fixture = Fixture()
            let folderReveal = try #require(SidebarItemReveal(item: .folder(fixture.folder.id), spaceID: fixture.destination.id,
                                                              profileID: fixture.source.profileID, state: fixture.moved))
            #expect(folderReveal.expandedFolderIDs == [fixture.folder.id])
        }

        @Test func anEmptyTargetRevealsItsAncestorsWithoutAnExpansionEffect() throws {
            let fixture = Fixture()
            var withEmpty = fixture.moved
            let empty = BrowserFolder(id: UUID(), spaceID: fixture.destination.id, name: "Empty", parentID: fixture.folder.id, isExpanded: false)
            withEmpty.folders.append(empty)
            let emptyReveal = try #require(SidebarItemReveal(item: .folder(empty.id), spaceID: fixture.destination.id,
                                                             profileID: fixture.source.profileID, state: withEmpty))
            #expect(emptyReveal.expandedFolderIDs == [fixture.folder.id])
            #expect(emptyReveal.applying(to: withEmpty)?.folders.last?.isExpanded == false)
        }

        @Test func aWholeSplitRevealExpandsTheExactAncestors() throws {
            let fixture = Fixture()
            let reveal = try #require(SidebarItemReveal(item: .split(fixture.group.id), spaceID: fixture.destination.id,
                                                        profileID: fixture.source.profileID, state: fixture.moved))
            #expect(reveal.expandedFolderIDs == [fixture.folder.id, fixture.nested.id])
            let revealed = try #require(reveal.applying(to: fixture.moved))
            #expect(revealed.folders.filter { reveal.expandedFolderIDs.contains($0.id) }.allSatisfy { $0.isExpanded })
        }

        @Test func revealCannotAlterPageOrSplitRecordsAndIsDistinctFromActivation() throws {
            let fixture = Fixture()
            let moved = fixture.moved
            let reveal = try #require(SidebarItemReveal(item: .split(fixture.group.id), spaceID: fixture.destination.id,
                                                        profileID: fixture.source.profileID, state: moved))
            let revealed = try #require(reveal.applying(to: moved))
            #expect(revealed.tabs == moved.tabs)
            #expect(revealed.splitLayouts == moved.splitLayouts)
            #expect(revealed.selectedTabIDs == moved.selectedTabIDs)
            #expect(revealed.selectionBySpace == moved.selectionBySpace)
        }

        @Test func aStaleSourceSpaceCannotRevealAMovedItem() {
            let fixture = Fixture()
            #expect(SidebarItemReveal(item: .folder(fixture.folder.id), spaceID: fixture.source.id, profileID: fixture.source.profileID, state: fixture.moved) == nil)
        }

        @Test func aFavoriteIsNotAMovedSpaceItemForReveal() {
            let fixture = Fixture()
            #expect(SidebarItemReveal(item: .tab(fixture.favorite.id), spaceID: fixture.destination.id, profileID: fixture.source.profileID, state: fixture.moved) == nil)
        }

        @Test func changedRevealAncestryRefusesAStaleTransaction() throws {
            let fixture = Fixture()
            let moved = fixture.moved
            let reveal = try #require(SidebarItemReveal(item: .split(fixture.group.id), spaceID: fixture.destination.id,
                                                        profileID: fixture.source.profileID, state: moved))
            var changedParent = moved
            changedParent.folders[1].parentID = nil
            #expect(reveal.applying(to: changedParent) == nil)
        }

        @Test func anUnmaterializedWholeSplitCanMove() {
            let fixture = Fixture()
            #expect(fixture.move.permitsSplitOwners([:], in: UUID()))
        }

        @Test func theOriginalPhysicalOwnerRetainsTheWholeSplit() {
            let fixture = Fixture()
            let window = UUID()
            #expect(fixture.move.permitsSplitOwners([fixture.a.id: window, fixture.b.id: window], in: window))
        }

        @Test func aForeignPhysicalSplitOwnerIsRefused() {
            let fixture = Fixture()
            let window = UUID(), other = UUID()
            #expect(!fixture.move.permitsSplitOwners([fixture.a.id: other, fixture.b.id: other], in: window))
        }

        @Test func mixedPhysicalSplitOwnersAreRefusedAsAWhole() {
            let fixture = Fixture()
            let window = UUID(), other = UUID()
            #expect(!fixture.move.permitsSplitOwners([fixture.a.id: window, fixture.b.id: other], in: window))
        }

        @MainActor @Test func spaceNavigationAfterTheMoveRestoresTheWholeSplitAndFocus() {
            let fixture = Fixture()
            let owner = NativePageOwnership(), originalWindow = UUID()
            #expect(owner.claim(fixture.a.id, owner: originalWindow, page: "original-a"))
            #expect(owner.claim(fixture.b.id, owner: originalWindow, page: "original-b"))
            let claim = owner.claimSnapshot(fixture.a.id)
            let moved = fixture.moved
            var presentation = WindowPresentation(state: fixture.state, ready: true)
            presentation.reconcile(moved) { owner.canUse($0, owner: originalWindow) }
            #expect(presentation.selectedTabIDs.isEmpty)
            presentation.selectSpace(fixture.destination.id, state: moved) { owner.canUse($0, owner: originalWindow) }
            let selected = presentation.selectExistingTab(fixture.b.id, state: moved, available: { owner.canUse($0, owner: originalWindow) })
            #expect(selected)
            presentation.recordFocusedTab(fixture.b.id)
            #expect(presentation.selectedTabIDs == fixture.group.tabIDs)
            #expect(presentation.preferredFocusedTabID == fixture.b.id)
            #expect(owner.claimSnapshot(fixture.a.id) == claim)
        }

        @MainActor @Test func aMoveDoesNotSilentlyAdoptAnotherPhysicalOwnersPage() {
            let fixture = Fixture()
            let owner = NativePageOwnership(), originalWindow = UUID(), otherWindow = UUID()
            #expect(owner.claim(fixture.a.id, owner: originalWindow, page: "original-a"))
            #expect(!owner.canUse(fixture.a.id, owner: otherWindow))
        }

        @MainActor @Test func anInProgressTransferAppearsInTheOwnerSnapshot() throws {
            let fixture = Fixture()
            let owner = NativePageOwnership(), originalWindow = UUID(), otherWindow = UUID()
            #expect(owner.claim(fixture.a.id, owner: originalWindow, page: "original-a"))
            let transfer = try #require(owner.reserveTransfer(fixture.a.id, page: "original-a", from: originalWindow, to: otherWindow))
            #expect(owner.claimSnapshot(fixture.a.id).transfer == transfer)
        }

        @MainActor @Test func anInProgressTransferCanBeCancelled() throws {
            let fixture = Fixture()
            let owner = NativePageOwnership(), originalWindow = UUID(), otherWindow = UUID()
            _ = owner.claim(fixture.a.id, owner: originalWindow, page: "original-a")
            let transfer = try #require(owner.reserveTransfer(fixture.a.id, page: "original-a", from: originalWindow, to: otherWindow))
            #expect(owner.finishTransfer(transfer, moved: false))
        }
    }
}
