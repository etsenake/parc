import Foundation
import Testing
@testable import ParcCore

extension SidebarSpaceMoveTestsSupport {
    struct SidebarSpaceMoveMixedPlacementTests {
        @Test(arguments: [TabKind.pinned, .today])
        func mixedSectionsCaptureEveryOriginalChildOnce(anchorKind: TabKind) {
            let fixture = Fixture()
            let mixed = fixture.mixedSections(anchorKind)
            #expect(mixed.proposal.tabIDs == fixture.group.tabIDs)
            #expect(mixed.proposal.groupIDs == [fixture.group.id])
        }

        @Test(arguments: [TabKind.pinned, .today])
        func onlyExplicitContainerPlacementChangesInAMixedSectionMove(anchorKind: TabKind) {
            let fixture = Fixture()
            let mixed = fixture.mixedSections(anchorKind)
            for i in mixed.original.tabs.indices {
                var expected = mixed.original.tabs[i]
                if fixture.group.tabIDs.contains(expected.id) {
                    expected.spaceID = fixture.destination.id
                    expected.folderID = nil
                    expected.kind = anchorKind
                }
                #expect(mixed.result.tabs[i] == expected)
            }
        }

        @Test(arguments: [TabKind.pinned, .today])
        func aMixedSectionMoveKeepsTheGroupAndLeavesSourceFoldersAlone(anchorKind: TabKind) {
            let fixture = Fixture()
            let mixed = fixture.mixedSections(anchorKind)
            #expect(mixed.result.splitLayouts == [fixture.expectedGroup])
            #expect(mixed.result.folders == mixed.original.folders)
            #expect(SidebarHierarchySnapshot(state: mixed.result, spaceID: fixture.destination.id, profileID: fixture.source.profileID) != nil)
        }

        @Test(arguments: [TabKind.pinned, .today])
        func theAnchoredGroupAppendsInItsOwnProjectedSection(anchorKind: TabKind) {
            let fixture = Fixture()
            let mixed = fixture.mixedSections(anchorKind)
            let destinationChildren = SidebarHierarchy.children(in: fixture.location(fixture.destination.id, nil, anchorKind), state: mixed.result)
            #expect(destinationChildren.last == .split(fixture.group.id))
        }

        @Test(arguments: [TabKind.pinned, .today])
        func noDormantSourceReferencesSurviveAMixedSectionMove(anchorKind: TabKind) {
            let fixture = Fixture()
            let mixed = fixture.mixedSections(anchorKind)
            let sourceOrders = mixed.result.sidebarItemOrder.filter { $0.key.hasPrefix(fixture.source.id.uuidString + ":") }
            let sourceReferences = Set(sourceOrders.values.flatMap { $0 })
            #expect(sourceReferences.isDisjoint(with: [.tab(fixture.a.id), .tab(fixture.b.id), .split(fixture.group.id)]))
        }

        @Test(arguments: [TabKind.pinned, .today])
        func laterSeparationKeepsBothOriginalsAtTheDestination(anchorKind: TabKind) {
            let fixture = Fixture()
            var separated = fixture.mixedSections(anchorKind).result
            separated.splitLayouts = []
            let children = SidebarHierarchy.children(in: fixture.location(fixture.destination.id, nil, anchorKind), state: separated)
            #expect(children.contains(.tab(fixture.a.id)))
            #expect(children.contains(.tab(fixture.b.id)))
        }

        @Test(arguments: [TabKind.pinned, .today])
        func mixedPlacementDoesNotWeakenWholeGroupPhysicalOwnership(anchorKind: TabKind) {
            let fixture = Fixture()
            let window = UUID(), other = UUID()
            #expect(!fixture.mixedSections(anchorKind).proposal.permitsSplitOwners([fixture.a.id: window, fixture.b.id: other], in: window))
        }

        @Test(arguments: [TabKind.pinned, .today])
        func aMixedPlacementChildCannotMoveByItself(anchorKind: TabKind) {
            let fixture = Fixture()
            #expect(fixture.proposed(fixture.mixedSections(anchorKind).original, [.tab(fixture.a.id)]) == nil)
        }

        @Test(arguments: [TabKind.pinned, .today])
        func changedChildPlacementRevokesTheMoveReceipt(anchorKind: TabKind) {
            let fixture = Fixture()
            let mixed = fixture.mixedSections(anchorKind)
            var changed = mixed.original
            changed.tabs[0].folderID = fixture.folder.id
            #expect(mixed.proposal.applying(to: changed) == nil)
        }

        @Test(arguments: [TabKind.pinned, .today])
        func changedGeometryRevokesTheMoveReceipt(anchorKind: TabKind) {
            let fixture = Fixture()
            let mixed = fixture.mixedSections(anchorKind)
            var changed = mixed.original
            changed.splitLayouts[0].widthFactors = [0.6, 0.4]
            #expect(mixed.proposal.applying(to: changed) == nil)
        }

        @Test(arguments: [TabKind.pinned, .today])
        func aMixedFavoriteAndOrdinaryGroupRemainsRefused(anchorKind: TabKind) {
            let fixture = Fixture()
            var changed = fixture.mixedSections(anchorKind).original
            changed.tabs[0].kind = .favorite
            changed.tabs[0].folderID = nil
            #expect(fixture.proposed(changed, [.split(fixture.group.id)]) == nil)
        }

        @Test func movingAnAnchorAncestorIncludesTheOutsideChildAsPartOfTheWholeGroup() {
            let fixture = Fixture()
            let nested = fixture.nestedMixed()
            #expect(Set(nested.move.tabIDs) == Set([fixture.a.id, fixture.b.id, fixture.c.id]))
            #expect(nested.move.groupIDs == [fixture.group.id])
        }

        @Test func theMoveDoesNotPullInTheNonAnchorChildsFormerFolder() {
            let fixture = Fixture()
            #expect(fixture.nestedMixed().move.folderIDs == [fixture.folder.id, fixture.nested.id])
        }

        @Test func theWholeGroupNestsInTheMovedOriginalAnchorFolder() {
            let fixture = Fixture()
            let mixed = fixture.nestedMixed()
            #expect(mixed.result.tabs[0].folderID == fixture.nested.id)
            #expect(mixed.result.tabs[1].folderID == fixture.nested.id)
        }

        @Test func noteAndEaselReferencesAreUnchanged() {
            let fixture = Fixture()
            let mixed = fixture.nestedMixed()
            #expect(mixed.result.tabs[0].savedURL == mixed.state.tabs[0].savedURL)
            #expect(mixed.result.tabs[1].savedURL == mixed.state.tabs[1].savedURL)
        }

        @Test func anUnselectedOutsideFolderStaysInTheOriginalSpaceAndLosesItsDormantEntry() {
            let fixture = Fixture()
            let mixed = fixture.nestedMixed()
            #expect(mixed.result.folders.last == mixed.outside)
            #expect(mixed.result.sidebarItemOrder[fixture.location(fixture.source.id, mixed.outside.id).key] == [])
        }

        @Test func theNestedGroupRetainsOneMixedOrderSlotAndSiblingOrderSurvives() {
            let fixture = Fixture()
            let mixed = fixture.nestedMixed()
            #expect(SidebarHierarchy.children(in: fixture.location(fixture.destination.id, fixture.nested.id), state: mixed.result) == [.split(fixture.group.id)])
            #expect(SidebarHierarchy.children(in: fixture.location(fixture.destination.id, fixture.folder.id), state: mixed.result) == [.folder(fixture.nested.id), .tab(fixture.c.id)])
        }

        @Test func noSourceOnlyFolderReferenceCrossesIntoTheDestination() {
            let fixture = Fixture()
            #expect(SidebarHierarchySnapshot(state: fixture.nestedMixed().result, spaceID: fixture.destination.id, profileID: fixture.source.profileID) != nil)
        }

        @Test func aFolderHoldingOnlyAHiddenNonAnchorChildCannotSplitTheGroup() {
            let fixture = Fixture()
            let mixed = fixture.nestedMixed()
            #expect(fixture.proposed(mixed.state, [.folder(mixed.outside.id)]) == nil)
        }

        @Test func explicitRootsIncludeTheGroupOnceEvenWhenAnOldChildFolderAlsoMoves() throws {
            let fixture = Fixture()
            let mixed = fixture.nestedMixed()
            let both = try #require(fixture.proposed(mixed.state, [.folder(mixed.outside.id), .split(fixture.group.id)]))
            let bothResult = try #require(both.applying(to: mixed.state))
            #expect(Set(both.tabIDs) == Set(fixture.group.tabIDs))
            #expect(both.folderIDs == [mixed.outside.id])
            #expect(bothResult.tabs[0].folderID == nil)
            #expect(bothResult.tabs[1].folderID == nil)
            #expect(SidebarHierarchy.children(in: fixture.location(fixture.destination.id, nil), state: bothResult)
                    == [.tab(fixture.existing.id), .folder(mixed.outside.id), .split(fixture.group.id)])
        }
    }
}
