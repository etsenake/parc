import Foundation
import Testing
@testable import ParcCore

extension SidebarSplitCopyTestsSupport {
    @MainActor
    struct SidebarSplitCopyItemPlacementTests {
        @Test(arguments: DragSource.allCases)
        func optionDragClassifiesOnlyAnAllSplitSelectionAsWholeSplits(_ source: DragSource) throws {
            let i = try Items()
            let items: [SidebarItemReference]
            switch source {
            case .split: items = [.split(i.rootSplit.id)]
            case .tab: items = [.tab(i.loose.id)]
            case .folder: items = [.folder(i.outer.id)]
            case .mixed: items = [.tab(i.loose.id), .folder(i.outer.id), .split(i.rootSplit.id)]
            }
            #expect(i.copy(items)?.wholeSplits == source.wholeSplits)
        }

        @Test func aSingleSplitChildIsNeverCopiedOutOfItsSplit() throws {
            let i = try Items()
            #expect(i.copy([.tab(i.pairA.id)]) == nil)
        }

        @Test func aTabCopiedOntoTodayLandsWhereItWasDroppedAsAFreshTodayTabAndOpensInTheBackground() throws {
            let i = try Items()
            let looseCopy = try i.place([.tab(i.loose.id)], i.todayLocation, before: .tab(i.today.id))
            guard case .tab(let todayCopy)? = looseCopy.roots.first else { Issue.record("tab copy root"); return }
            #expect(i.children(i.todayLocation) == [.tab(todayCopy), .tab(i.today.id)])
            #expect(i.store.state.tab(todayCopy).map { $0.kind == .today && $0.savedURL == i.loose.savedURL && $0.id != i.loose.id } == true)
            #expect(i.store.state.tab(i.loose.id) == i.initial.tab(i.loose.id))
            #expect(SidebarHierarchy.children(in: i.pinned, state: i.store.state) == SidebarHierarchy.children(in: i.pinned, state: i.initial))
            #expect(looseCopy.openTabIDs == [todayCopy])
        }

        @Test func theSpaceHeaderDropsTheCopyAtTheTopOfPinnedAboveItsOriginal() throws {
            let i = try Items()
            let headerCopy = try i.place([.tab(i.loose.id)], i.pinned, before: .tab(i.loose.id))
            #expect(Array(i.children(i.pinned).prefix(2)) == [headerCopy.roots[0], .tab(i.loose.id)])
        }

        @Test func aFolderCopiedOntoAnotherFolderNestsInsideItWithTheSameNameAndKeepsTheOriginalContents() throws {
            let i = try Items()
            let folderCopy = try i.place([.folder(i.outer.id)], i.targetLocation)
            guard case .folder(let outerCopy)? = folderCopy.roots.first, let copiedOuter = i.store.state.folders.first(where: { $0.id == outerCopy }) else {
                Issue.record("folder copy root")
                return
            }
            #expect(i.children(i.targetLocation) == [.folder(outerCopy)])
            #expect(copiedOuter.parentID == i.target.id)
            #expect(copiedOuter.name == i.outer.name)
            #expect(SidebarHierarchy.children(in: i.outerLocation, state: i.store.state) == SidebarHierarchy.children(in: i.outerLocation, state: i.initial))
            #expect(i.store.state.folders.first { $0.id == i.outer.id } == i.outer)
            #expect(folderCopy.tabIDs.count == 4)
            #expect(folderCopy.openTabIDs.isEmpty)
        }

        @Test func nestedFoldersTabsAndSplitsAreFreshCopiesThatKeepOrderAndDisclosure() throws {
            let i = try Items()
            let folderCopy = try i.place([.folder(i.outer.id)], i.targetLocation)
            guard case .folder(let outerCopy)? = folderCopy.roots.first else { Issue.record("folder copy root"); return }
            let outerChildren = i.children(i.folderLocation(outerCopy))
            guard outerChildren.count == 2, case .folder(let nestedCopy) = outerChildren[0], case .tab(let inOuterCopy) = outerChildren[1] else {
                Issue.record("nested copy")
                return
            }
            #expect(nestedCopy != i.nested.id)
            #expect(inOuterCopy != i.inOuter.id)
            #expect(i.store.state.folders.first { $0.id == nestedCopy }?.isExpanded == false)
            let nestedChildren = i.children(i.folderLocation(nestedCopy))
            guard nestedChildren.count == 2, case .split(let nestedSplitCopy) = nestedChildren[1],
                  let copiedSplit = i.store.state.splitLayouts.first(where: { $0.id == nestedSplitCopy }) else { Issue.record("nested split copy"); return }
            #expect(copiedSplit.tabIDs.allSatisfy { id in i.store.state.tab(id)?.folderID == nestedCopy })
            #expect(Set(copiedSplit.tabIDs).isDisjoint(with: i.nestedSplit.tabIDs))
        }

        @Test func foldersCannotBeCopiedIntoTodayOrTheFavoritesTray() throws {
            let i = try Items()
            #expect(!i.can([.folder(i.outer.id)], i.todayLocation))
            #expect(!i.can([.folder(i.outer.id)], i.favorites))
        }

        @Test func aMixedSelectionLandsTogetherInOriginalOrderKeepingItsSplitAndOpeningOnlyTopLevelPages() throws {
            let i = try Items()
            let mixed = try i.place([.tab(i.loose.id), .folder(i.outer.id), .split(i.rootSplit.id)], i.targetLocation)
            #expect(mixed.roots.count == 3)
            #expect(Array(i.children(i.targetLocation).suffix(3)) == mixed.roots)
            guard case .split(let mixedSplit) = mixed.roots[2], let mixedGroup = i.store.state.splitLayouts.first(where: { $0.id == mixedSplit }) else {
                Issue.record("mixed split")
                return
            }
            #expect(mixedGroup.customTitle == i.rootSplit.customTitle)
            #expect(mixedGroup.widthFactors == i.rootSplit.widthFactors)
            #expect(mixed.openTabIDs.count == 3)
            #expect(mixed.openTabIDs.allSatisfy(mixed.tabIDs.contains))
        }

        @Test func aFavoriteTileCopiesIntoPinnedAndStaysInTheTray() throws {
            let i = try Items()
            let outOfTray = try i.place([.tab(i.favorite.id)], i.pinned)
            guard case .tab(let favoriteCopy)? = outOfTray.roots.first else { Issue.record("favorite copy"); return }
            #expect(i.store.state.tab(favoriteCopy).map { $0.kind == .pinned && $0.spaceID == i.here.id } == true)
            #expect(i.children(i.favorites) == [.tab(i.favorite.id)])
        }

        @Test func aTabCopiedOntoTheTrayBecomesAFavoriteBeforeItsTarget() throws {
            let i = try Items()
            let intoTray = try i.place([.tab(i.loose.id)], i.favorites, before: .tab(i.favorite.id))
            #expect(i.children(i.favorites) == [intoTray.roots[0], .tab(i.favorite.id)])
            #expect(i.store.state.tab(intoTray.tabIDs[0])?.kind == .favorite)
        }

        @Test func copyingAnExistingFavoriteWithinTheTrayAddsATile() throws {
            let i = try Items()
            _ = try i.place([.tab(i.loose.id)], i.favorites, before: .tab(i.favorite.id))
            let withinTray = try i.place([.tab(i.favorite.id)], i.favorites)
            #expect(i.children(i.favorites).last == withinTray.roots[0])
            #expect(i.children(i.favorites).count == 3)
        }

        @Test func aDockDropCopiesIntoAnotherSpaceThatSharesDataFoldersAndAll() throws {
            let i = try Items()
            let away = try i.place([.tab(i.loose.id), .folder(i.outer.id)], i.therePinned)
            guard case .folder(let awayFolder) = away.roots[1] else { Issue.record("space copy"); return }
            #expect(Array(i.children(i.therePinned).suffix(2)) == away.roots)
            #expect(away.tabIDs.allSatisfy { i.store.state.tab($0)?.spaceID == i.there.id })
            #expect(i.store.state.folders.filter { $0.spaceID == i.there.id }.count == 2)
            #expect(i.store.state.folders.first { $0.id == awayFolder }?.spaceID == i.there.id)
            #expect(i.children(i.pinned).contains(.tab(i.loose.id)))
            #expect(i.children(i.pinned).contains(.folder(i.outer.id)))
        }

        @Test func tabsFoldersAndMixedSelectionsNeverCopyIntoASpaceThatKeepsSeparateDataButWholeWebSplitsDo() throws {
            let i = try Items()
            #expect(!i.can([.tab(i.loose.id)], i.elsewherePinned))
            #expect(!i.can([.folder(i.outer.id)], i.elsewherePinned))
            #expect(!i.can([.tab(i.loose.id), .split(i.rootSplit.id)], i.elsewherePinned))
            #expect(i.can([.split(i.rootSplit.id)], i.elsewherePinned))
        }
    }
}
