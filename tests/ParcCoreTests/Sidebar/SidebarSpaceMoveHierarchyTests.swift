import Foundation
import Testing
@testable import ParcCore

extension SidebarSpaceMoveTestsSupport {
    struct SidebarSpaceMoveHierarchyTests {
        @Test func anAncestorAbsorbsSelectedDescendants() {
            let fixture = Fixture()
            #expect(fixture.move.roots == [.folder(fixture.folder.id), .tab(fixture.today.id)])
        }

        @Test func theWholeTreeAndSplitChildrenAreRetained() {
            let fixture = Fixture()
            #expect(Set(fixture.move.tabIDs) == Set([fixture.a.id, fixture.b.id, fixture.c.id, fixture.today.id]))
        }

        @Test func movingMakesNoCopiesAndDeletesNothing() {
            let fixture = Fixture()
            let moved = fixture.moved
            #expect(moved.tabs.count == fixture.state.tabs.count)
            #expect(moved.folders.count == fixture.state.folders.count)
        }

        @Test func allOriginalNavigationSavedKindAndLifetimeMetadataIsRetained() {
            let fixture = Fixture()
            let moved = fixture.moved
            for original in fixture.state.tabs {
                var expected = original
                if fixture.move.tabIDs.contains(original.id) { expected.spaceID = fixture.destination.id }
                #expect(moved.tabs.first { $0.id == original.id } == expected)
            }
        }

        @Test func theOriginalGroupIdentityAnchorOrientationAndWeightsSurvive() {
            let fixture = Fixture()
            #expect(fixture.moved.splitLayouts == [fixture.expectedGroup])
        }

        @Test func nestedParentsAndCollapsedStateSurvive() {
            let fixture = Fixture()
            let moved = fixture.moved
            #expect(moved.folders.first { $0.id == fixture.nested.id }?.parentID == fixture.folder.id)
            #expect(moved.folders.first { $0.id == fixture.folder.id }?.isExpanded == false)
        }

        @Test func movedRootsAppendToTheDestinationSiblingOrder() {
            let fixture = Fixture()
            #expect(SidebarHierarchy.children(in: fixture.location(fixture.destination.id, nil), state: fixture.moved) == [.tab(fixture.existing.id), .folder(fixture.folder.id)])
        }

        @Test func mixedFolderOrderMigrates() {
            let fixture = Fixture()
            #expect(SidebarHierarchy.children(in: fixture.location(fixture.destination.id, fixture.folder.id), state: fixture.moved) == [.folder(fixture.nested.id), .tab(fixture.c.id)])
        }

        @Test func aSplitAnchorProjectsToTheWholeGroup() {
            let fixture = Fixture()
            #expect(SidebarHierarchy.children(in: fixture.location(fixture.destination.id, fixture.nested.id), state: fixture.moved) == [.split(fixture.group.id)])
        }

        @Test func theOldNestedOrderKeyIsRemoved() {
            let fixture = Fixture()
            #expect(fixture.moved.sidebarItemOrder[fixture.location(fixture.source.id, fixture.nested.id).key] == nil)
        }

        @Test func theSourceCannotSelectMovedItems() {
            let fixture = Fixture()
            let moved = fixture.moved
            #expect(moved.selectedTabIDs.isEmpty)
            #expect(moved.selectionBySpace[fixture.source.id.uuidString] == [])
        }

        @Test func aMoveCannotStealTheDestinationsCurrentSelection() {
            let fixture = Fixture()
            #expect(fixture.moved.selectionBySpace[fixture.destination.id.uuidString] == [fixture.existing.id])
        }

        @Test func oneSnapshotCannotMoveTwice() {
            let fixture = Fixture()
            #expect(fixture.move.applying(to: fixture.moved) == nil)
        }

        @Test func aChangedOriginalTreeRefusesAStaleMenu() {
            let fixture = Fixture()
            var stale = fixture.state
            stale.folders[0].name = "Changed"
            #expect(fixture.move.applying(to: stale) == nil)
        }

        @Test func aChangedDestinationOrderRefusesAStaleMenu() {
            let fixture = Fixture()
            var stale = fixture.state
            stale.sidebarItemOrder[fixture.location(fixture.destination.id, nil).key] = [.tab(fixture.existing.id)]
            #expect(fixture.move.applying(to: stale) == nil)
        }

        @Test func liveNavigationMetadataIsNotOverwritten() {
            let fixture = Fixture()
            var stale = fixture.state
            stale.tabs[0].title = "New page title"
            #expect(fixture.move.applying(to: stale)?.tabs[0].title == "New page title")
        }

        @Test func crossProfileRelocationCarriesTheDestinationProfile() {
            let fixture = Fixture()
            var foreign = fixture.state
            let other = BrowserProfile(id: UUID(), name: "Other")
            foreign.profiles.append(other)
            foreign.spaces[1].profileID = other.id
            foreign.tabs[5].profileID = other.id
            let foreignTo = SidebarHierarchySnapshot(state: foreign, spaceID: fixture.destination.id, profileID: other.id)!
            let crossProfile = SidebarSpaceMove(items: [.folder(fixture.folder.id)], from: fixture.from, to: foreignTo, state: foreign)
            #expect(crossProfile?.crossesProfiles == true)
            #expect(crossProfile?.applying(to: foreign)?.tabs.first { $0.id == fixture.c.id }?.profileID == other.id)
        }

        @Test func aProfileWideFavoriteIsNotASpaceItem() {
            let fixture = Fixture()
            #expect(SidebarSpaceMove(items: [.tab(fixture.favorite.id)], from: fixture.from, to: fixture.to, state: fixture.state) == nil)
        }

        @Test func oneSplitChildCannotBeSilentlyDetached() {
            let fixture = Fixture()
            #expect(SidebarSpaceMove(items: [.tab(fixture.a.id)], from: fixture.from, to: fixture.to, state: fixture.state) == nil)
        }

        @Test func aFolderHoldingOnlyANonAnchorSplitChildRefusesPartialGroupMovement() {
            let fixture = Fixture()
            var mixed = fixture.state
            mixed.tabs[1].folderID = nil
            let mixedFrom = SidebarHierarchySnapshot(state: mixed, spaceID: fixture.source.id, profileID: fixture.source.profileID)!
            #expect(SidebarSpaceMove(items: [.folder(fixture.folder.id)], from: mixedFrom, to: fixture.to, state: mixed) == nil)
        }

        @Test func aStandaloneNestedTabBecomesADestinationRoot() throws {
            let fixture = Fixture()
            let single = try #require(SidebarSpaceMove(items: [.tab(fixture.c.id)], from: fixture.from, to: fixture.to, state: fixture.state)?.applying(to: fixture.state))
            #expect(single.tabs.first { $0.id == fixture.c.id }?.folderID == nil)
        }
    }
}
