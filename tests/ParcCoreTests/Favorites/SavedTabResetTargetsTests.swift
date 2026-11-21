import Foundation
import Testing
@testable import ParcCore

struct SavedTabResetTargetsTests {
    let now = Date(timeIntervalSince1970: 1000)
    var state = BrowserState.initial()
    let space: UUID, profile: UUID
    let otherSpace = UUID(), otherProfile = UUID()
    let open: BrowserFolder, closed: BrowserFolder, nested: BrowserFolder
    let favorite: BrowserTab, root: BrowserTab, last: BrowserTab
    let siblingFavorite: BrowserTab, foreignFavorite: BrowserTab
    let child: BrowserTab, deep: BrowserTab, hidden: BrowserTab, splitA: BrowserTab, splitB: BrowserTab
    let today: BrowserTab, archived: BrowserTab, home: BrowserTab, equivalent: BrowserTab, local: BrowserTab, elsewhere: BrowserTab
    let split: BrowserSplitLayout
    let rootLocation: SidebarContainerLocation
    let expected: [UUID]

    init() {
        var state = BrowserState.initial()
        let space = state.activeSpaceID, profile = state.profiles[0].id
        let otherSpace = self.otherSpace, otherProfile = self.otherProfile
        let now = self.now
        state.spaces.append(.init(id: otherSpace, name: "Other", symbol: "circle", color: "AABBCC", profileID: profile))
        state.profiles.append(.init(id: otherProfile, name: "Other profile"))
        func tab(_ name: String, kind: TabKind = .pinned, folder: UUID? = nil) -> BrowserTab {
            .init(id: UUID(), spaceID: space, profileID: profile,
                  url: "https://example.test/away/" + name, title: name, kind: kind, folderID: folder,
                  createdAt: now, lastAccessed: now, savedURL: "https://example.test/home/" + name, savedTitle: name)
        }
        open = BrowserFolder(id: UUID(), spaceID: space, name: "Open", isExpanded: true)
        closed = BrowserFolder(id: UUID(), spaceID: space, name: "Closed", isExpanded: false)
        nested = BrowserFolder(id: UUID(), spaceID: space, name: "Nested", parentID: open.id, isExpanded: true)
        favorite = tab("favorite", kind: .favorite)
        root = tab("root")
        last = tab("last")
        var siblingFavorite = tab("shared", kind: .favorite)
        siblingFavorite.spaceID = otherSpace
        self.siblingFavorite = siblingFavorite
        var foreignFavorite = tab("foreign", kind: .favorite)
        foreignFavorite.profileID = otherProfile
        self.foreignFavorite = foreignFavorite
        child = tab("child", folder: open.id)
        deep = tab("deep", folder: nested.id)
        hidden = tab("hidden", folder: closed.id)
        splitA = tab("split-a")
        splitB = tab("split-b")
        today = tab("today", kind: .today)
        var archived = tab("archived")
        archived.archivedAt = now
        self.archived = archived
        var home = tab("home")
        home.url = home.savedURL
        self.home = home
        var equivalent = tab("equivalent")
        equivalent.url = "http://WWW.example.test/HOME/equivalent/?utm_source=x#part"
        self.equivalent = equivalent
        var local = tab("local")
        local.url = "parc://note/" + UUID().uuidString
        local.savedURL = local.url
        self.local = local
        var elsewhere = tab("elsewhere")
        elsewhere.spaceID = otherSpace
        self.elsewhere = elsewhere
        split = BrowserSplitLayout(sidebarAnchorID: splitA.id, spaceID: space, tabIDs: [splitB.id, splitA.id], widthFactors: [0.5, 0.5])
        state.folders = [closed, nested, open]
        state.splitLayouts = [split]
        state.tabs = [hidden, last, splitA, deep, today, siblingFavorite, root, child, favorite,
                      foreignFavorite, splitB, archived, home, equivalent, local, elsewhere]
        rootLocation = SidebarContainerLocation(spaceID: space, folderID: nil, section: .pinned)
        let openLocation = SidebarContainerLocation(spaceID: space, folderID: open.id, section: .pinned)
        state.sidebarItemOrder[rootLocation.key] = [.tab(root.id), .folder(open.id), .split(split.id), .folder(closed.id), .tab(last.id)]
        state.sidebarItemOrder[openLocation.key] = [.folder(nested.id), .tab(child.id)]
        state.selectedTabIDs = [today.id]
        expected = [siblingFavorite.id, favorite.id, root.id, deep.id, child.id, splitB.id, splitA.id, last.id]
        self.state = state
        self.space = space
        self.profile = profile
    }

    func targets(_ state: BrowserState) -> [UUID] {
        SavedTabResetTargets.collect(in: state, spaceID: space).map(\.id)
    }

    @Test func favoritesThenMixedVisiblePinnedHierarchyAndOriginalSplitOrder() {
        #expect(targets(state) == expected)
    }

    @Test func collapsedFolderDescendantsAreExcluded() {
        #expect(!targets(state).contains(hidden.id))
    }

    @Test func todayIsExcludedEvenWithADifferentSavedURL() {
        #expect(!targets(state).contains(today.id))
    }

    @Test func aForeignProfileFavoriteIsExcluded() {
        #expect(!targets(state).contains(foreignFavorite.id))
    }

    @Test func anotherSpacesPinnedTabIsExcluded() {
        #expect(!targets(state).contains(elsewhere.id))
    }

    @Test func anArchivedSavedTabIsExcluded() {
        #expect(!targets(state).contains(archived.id))
    }

    @Test func fullURLEquivalenceFiltersUnchangedTargets() {
        let ids = targets(state)
        #expect(!ids.contains(home.id))
        #expect(!ids.contains(equivalent.id))
    }

    @Test func localDocumentsAreNotResetNavigationTargets() {
        #expect(!targets(state).contains(local.id))
    }

    @Test func aMissingSpaceCannotRedirectToTheActiveSpace() {
        #expect(SavedTabResetTargets.collect(in: state, spaceID: UUID()).isEmpty)
    }

    @Test func theActualSavedDestinationRemainsUnchangedAndCollectionDoesNotSelect() {
        let captured = SavedTabResetTargets.collect(in: state, spaceID: space)
        #expect(captured.map(\.savedURL) == expected.map { id in state.tabs.first { $0.id == id }!.savedURL })
        #expect(state.selectedTabIDs == [today.id])
    }

    @Test func disclosureInsertsChildrenAtTheOriginalSiblingSlot() {
        var edited = state
        edited.folders[0].isExpanded = true
        #expect(targets(edited) == Array(expected.dropLast()) + [hidden.id, last.id])
    }

    @Test func aCollapsedAncestorHidesExpandedDescendants() {
        var edited = state
        edited.folders[2].isExpanded = false
        #expect(targets(edited) == expected.filter { $0 != child.id && $0 != deep.id })
    }

    @Test func nestedDisclosureIsIndependent() {
        var edited = state
        edited.folders[1].isExpanded = false
        #expect(targets(edited) == expected.filter { $0 != deep.id })
    }

    @Test func mixedSiblingReorderingChangesDispatchOrder() {
        var edited = state
        edited.sidebarItemOrder[rootLocation.key] = [.tab(last.id), .tab(root.id), .folder(open.id), .split(split.id)]
        #expect(targets(edited) == [siblingFavorite.id, favorite.id, last.id, root.id, deep.id, child.id, splitB.id, splitA.id])
    }

    @Test func paneOrderBelongsToTheOriginalWholeSplit() {
        var edited = state
        edited.splitLayouts[0].tabIDs.reverse()
        #expect(targets(edited) == [siblingFavorite.id, favorite.id, root.id, deep.id, child.id, splitA.id, splitB.id, last.id])
    }

    @Test func stagedProfileRetirementInvalidatesTheBatch() {
        var edited = state
        edited.profileRemovals = [.init(id: UUID(), profileID: profile, profileName: "Default")]
        #expect(targets(edited).isEmpty)
    }

    @Test func aRemovedProfileCannotBeRecreated() {
        var edited = state
        edited.profiles.removeAll { $0.id == profile }
        #expect(targets(edited).isEmpty)
    }

    @Test func spaceProfileReplacementNeverLeaksOldProfileTargets() {
        var edited = state
        edited.spaces[0].profileID = otherProfile
        #expect(targets(edited) == [foreignFavorite.id])
    }

    @Test func aStaleStoredSiblingIdentityIsIgnored() {
        var edited = state
        edited.tabs.removeAll { $0.id == root.id }
        #expect(targets(edited) == expected.filter { $0 != root.id })
    }

    @Test func anAdmittedSnapshotIsAValueNotALateEnumeration() {
        let captured = SavedTabResetTargets.collect(in: state, spaceID: space)
        var edited = state
        edited.tabs[0].url += "/new"
        #expect(captured.map(\.id) == expected)
        #expect(captured.first?.url == siblingFavorite.url)
    }

    @Test func aGroupedFavoriteUsesTheVisibleSplitPositionAndDispatchesOnce() {
        var edited = state
        edited.splitLayouts = [.init(sidebarAnchorID: root.id, spaceID: space, tabIDs: [root.id, favorite.id], widthFactors: [0.5, 0.5])]
        let grouped = targets(edited)
        #expect(grouped.first == siblingFavorite.id)
        #expect(grouped.prefix(3) == [siblingFavorite.id, root.id, favorite.id])
        #expect(grouped.filter { $0 == favorite.id }.count == 1)
    }

    @Test func aFavoriteMovedIntoATodaySplitIsNotAVisibleSavedRoot() {
        var edited = state
        edited.splitLayouts = [.init(sidebarAnchorID: today.id, spaceID: space, tabIDs: [today.id, favorite.id], widthFactors: [0.5, 0.5])]
        #expect(!targets(edited).contains(favorite.id))
    }
}
