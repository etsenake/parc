import Foundation
import Testing
@testable import ParcCore

extension SidebarSplitCopyTestsSupport {
    @MainActor
    struct SidebarSplitCopyPlacementTests {
        @Test func theFixtureProjectsTheSplitAsOneRoot() throws {
            let f = try Fixture()
            #expect(SidebarHierarchy.children(in: f.pinned, state: f.store.state) == [.tab(f.keep.id), .split(f.split.id), .folder(f.folder.id)])
        }

        @Test(arguments: DragSource.allCases)
        func onlyAllSplitDragsAreWholeSplitCopies(_ source: DragSource) throws {
            let f = try Fixture()
            let initial = f.store.state
            func copy(_ items: [SidebarItemReference]) -> SidebarItemsCopy? {
                SidebarItemsCopy(items: items, spaceID: f.here.id, profileID: f.profile.id, state: initial)
            }
            let proposal: SidebarItemsCopy?
            switch source {
            case .split: proposal = f.target
            case .tab: proposal = copy([.tab(f.keep.id)])
            case .folder: proposal = copy([.folder(f.folder.id)])
            case .mixed: proposal = copy([.split(f.split.id), .tab(f.keep.id)])
            }
            #expect(proposal?.wholeSplits == source.wholeSplits)
        }

        @Test func aProposalAdmitsTheCopyWithoutPublishing() throws {
            let f = try Fixture()
            let initial = f.store.state
            #expect(f.store.canCopySidebarItems(f.target, to: f.pinned, before: .tab(f.keep.id), destinations: f.urls))
            #expect(f.store.state == initial)
        }

        @Test func invalidDestinationsRefuseTheCopy() throws {
            let f = try Fixture()
            let initial = f.store.state
            let foreign = SidebarContainerLocation(spaceID: f.here.id, folderID: nil, section: .favorite, profileID: UUID())
            #expect(!f.store.canCopySidebarItems(f.target, to: foreign, before: nil, destinations: f.urls))
            #expect(!f.store.canCopySidebarItems(f.target, to: f.pinned, before: .tab(f.away.id), destinations: f.urls))
            #expect(!f.store.canCopySidebarItems(f.target, to: f.pinned, before: nil, destinations: [f.left.id: f.urls[f.left.id]!]))
            #expect(try f.store.copySidebarItems(f.target, to: f.pinned, before: .tab(f.away.id), destinations: f.urls) == nil)
            #expect(f.store.state == initial)
        }

        @Test func aCopyIsOneFreshSplitRootWithFreshChildIdentitiesInOriginalOrder() throws {
            let f = try Fixture()
            let first = try #require(try f.store.copySidebarItems(f.target, to: f.pinned, before: .tab(f.keep.id), destinations: f.urls))
            let group = try f.group(first)
            guard case .split(let firstID)? = first.roots.first else { Issue.record("copy root"); return }
            #expect(first.roots.count == 1)
            #expect(firstID != f.split.id)
            #expect(Set(group.tabIDs).isDisjoint(with: f.split.tabIDs))
            #expect(group.tabIDs == first.tabIDs)
            #expect(group.orientation == f.split.orientation)
            #expect(group.widthFactors == f.split.widthFactors)
            #expect(group.customTitle == f.split.customTitle)
        }

        @Test func theCopyIsPlacedAtTheDropLocationAndTheOriginalKeepsItsSlotAndRecords() throws {
            let f = try Fixture()
            let initial = f.store.state
            let first = try #require(try f.store.copySidebarItems(f.target, to: f.pinned, before: .tab(f.keep.id), destinations: f.urls))
            let after = f.store.state
            guard case .split(let firstID)? = first.roots.first else { Issue.record("copy root"); return }
            #expect(SidebarHierarchy.children(in: f.pinned, state: after) == [.split(firstID), .tab(f.keep.id), .split(f.split.id), .folder(f.folder.id)])
            #expect(after.splitLayouts.first { $0.id == f.split.id } == f.split)
            #expect(f.split.tabIDs.allSatisfy { id in after.tabs.first { $0.id == id } == initial.tabs.first { $0.id == id } })
        }

        @Test func childrenTakeTheResolvedURLsAndThePinnedRootAndTheStoreLeavesSelectionToTheWindow() throws {
            let f = try Fixture()
            let initial = f.store.state
            let first = try #require(try f.store.copySidebarItems(f.target, to: f.pinned, before: .tab(f.keep.id), destinations: f.urls))
            let after = f.store.state
            let group = try f.group(first)
            let children = group.tabIDs.map { id in after.tabs.first { $0.id == id }! }
            #expect(children.map(\.savedURL) == [f.urls[f.left.id]!, f.urls[f.right.id]!])
            #expect(children.allSatisfy { $0.kind == .pinned && $0.folderID == nil && $0.spaceID == f.here.id })
            #expect(first.openTabIDs == group.tabIDs)
            #expect(after.selectedTabIDs == initial.selectedTabIDs)
            #expect(after.activeSpaceID == initial.activeSpaceID)
        }

        @Test func aFolderDropAppendsTheCopyInsideItAndTheChildrenCarryTheFolder() throws {
            let f = try Fixture()
            let foldered = try #require(try f.store.copySidebarItems(f.target, to: f.inFolder, before: nil, destinations: f.urls))
            let group = try f.group(foldered)
            guard case .split(let folderedID)? = foldered.roots.first else { Issue.record("folder copy"); return }
            #expect(SidebarHierarchy.children(in: f.inFolder, state: f.store.state) == [.tab(f.inside.id), .split(folderedID)])
            #expect(group.tabIDs.allSatisfy { id in f.store.state.tabs.first { $0.id == id }?.folderID == f.folder.id })
        }

        @Test func aTodayDropPlacesTheCopyBeforeItsTargetAsTodayItems() throws {
            let f = try Fixture()
            let unpinned = try #require(try f.store.copySidebarItems(f.target, to: f.todayLocation, before: .tab(f.today.id), destinations: f.urls))
            let group = try f.group(unpinned)
            #expect(SidebarHierarchy.children(in: f.todayLocation, state: f.store.state).first == .split(group.id))
            #expect(group.tabIDs.allSatisfy { id in f.store.state.tabs.first { $0.id == id }?.kind == .today })
        }

        @Test func anotherSpacesWindowPlacesTheCopyInItsOwnSpaceAndTheSourceKeepsTheOriginal() throws {
            let f = try Fixture()
            let moved = try #require(try f.store.copySidebarItems(f.target, to: f.therePinned, before: .tab(f.away.id), destinations: f.urls))
            let group = try f.group(moved)
            let after = f.store.state
            #expect(SidebarHierarchy.children(in: f.therePinned, state: after) == [.split(group.id), .tab(f.away.id)])
            #expect(group.spaceID == f.there.id)
            #expect(group.tabIDs.allSatisfy { id in after.tabs.first { $0.id == id }?.spaceID == f.there.id })
            #expect(SidebarHierarchy.children(in: f.pinned, state: after).contains(.split(f.split.id)))
            #expect(after.splitLayouts.first { $0.id == f.split.id }?.spaceID == f.here.id)
        }

        @Test func anAppTrayDropMakesTheCopyAFavoriteRootWithFavoriteChildren() throws {
            let f = try Fixture()
            let tray = try #require(try f.store.copySidebarItems(f.target, to: f.favorites, before: nil, destinations: f.urls))
            let group = try f.group(tray)
            let after = f.store.state
            #expect(SidebarHierarchy.children(in: f.favorites, state: after).contains(.split(group.id)))
            #expect(group.tabIDs.allSatisfy { id in after.tabs.first { $0.id == id }?.kind == .favorite })
            #expect(after.splitLayouts.first { $0.id == f.split.id } == f.split)
        }

        @Test func aFavoriteSplitsCopyLandsAtTheDropLocationWithPinnedChildrenAndTheOriginalStaysInTheTray() throws {
            let f = try Fixture()
            let favoriteCopy = f.copyOfSplit(f.favorite.id)
            let outOfTray = try #require(try f.store.copySidebarItems(favoriteCopy, to: f.pinned, before: nil, destinations: f.favURLs))
            let group = try f.group(outOfTray)
            let after = f.store.state
            #expect(SidebarHierarchy.children(in: f.pinned, state: after).last == .split(group.id))
            #expect(group.tabIDs.allSatisfy { id in after.tabs.first { $0.id == id }.map { $0.kind == .pinned && $0.spaceID == f.here.id } == true })
            #expect(SidebarHierarchy.children(in: f.favorites, state: after).contains(.split(f.favorite.id)))
            #expect(after.splitLayouts.contains(f.favorite))
            #expect(outOfTray.openTabIDs == group.tabIDs)
        }

        @Test func aCopyWithinTheTrayLandsBeforeItsTarget() throws {
            let f = try Fixture()
            let favoriteAgain = f.copyOfSplit(f.favorite.id)
            let inTray = try #require(try f.store.copySidebarItems(favoriteAgain, to: f.favorites, before: .split(f.favorite.id), destinations: f.favURLs))
            guard case .split(let inTrayID)? = inTray.roots.first else { Issue.record("tray reorder copy"); return }
            let trayOrder = SidebarHierarchy.children(in: f.favorites, state: f.store.state)
            #expect(trayOrder.firstIndex(of: .split(inTrayID)).map { $0 + 1 == trayOrder.firstIndex(of: .split(f.favorite.id)) } == true)
        }

        @Test func aCrossProfileCopyLandsInTheOtherProfilesSpaceAndTheOriginalsKeepTheirProfile() throws {
            let f = try Fixture()
            let crossed = try #require(try f.store.copySidebarItems(f.target, to: f.elsewherePinned, before: .tab(f.foreignTab.id), destinations: f.urls))
            let group = try f.group(crossed)
            let after = f.store.state
            #expect(SidebarHierarchy.children(in: f.elsewherePinned, state: after) == [.split(group.id), .tab(f.foreignTab.id)])
            #expect(group.spaceID == f.elsewhere.id)
            #expect(group.tabIDs.allSatisfy { id in
                after.tabs.first { $0.id == id }.map { $0.profileID == f.foreignProfile.id && $0.spaceID == f.elsewhere.id } == true
            })
            #expect(f.split.tabIDs.allSatisfy { id in after.tabs.first { $0.id == id }?.profileID == f.profile.id })
            #expect(after.splitLayouts.contains(f.split))
        }
    }
}
