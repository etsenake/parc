import Foundation

@main
@MainActor
struct SidebarSpaceMoveTests {
    static var count = 0
    static func check(_ value: @autoclosure () -> Bool, _ message: String) { count += 1; precondition(value(), message) }
    static func main() throws {
        var state = BrowserState.initial()
        let source = state.spaces[0]
        let destination = BrowserSpace(id: UUID(), name: "Work", symbol: "circle", color: "112233", profileID: source.profileID)
        state.spaces.append(destination)
        let folder = BrowserFolder(id: UUID(), spaceID: source.id, name: "Tree", parentID: nil, isExpanded: false)
        let nested = BrowserFolder(id: UUID(), spaceID: source.id, name: "Nested", parentID: folder.id, isExpanded: true)
        func tab(_ space: UUID, _ kind: TabKind, _ parent: UUID? = nil) -> BrowserTab {
            .init(id: UUID(), spaceID: space, profileID: source.profileID, url: "https://example.test/live", title: "Live",
                  kind: kind, folderID: parent, createdAt: Date(timeIntervalSince1970: 1), lastAccessed: Date(timeIntervalSince1970: 2),
                  savedURL: "https://example.test/saved", savedTitle: "Saved", isMuted: true, isUnread: true)
        }
        let a = tab(source.id, .pinned, nested.id), b = tab(source.id, .pinned, nested.id)
        let c = tab(source.id, .pinned, folder.id), today = tab(source.id, .today), pinned = tab(source.id, .pinned)
        let existing = tab(destination.id, .pinned), favorite = tab(source.id, .favorite)
        state.tabs = [a, b, c, today, pinned, existing, favorite]; state.folders = [folder, nested]
        let group = BrowserSplitLayout(id: UUID(), sidebarAnchorID: b.id, spaceID: source.id, tabIDs: [a.id, b.id], orientation: .horizontal, widthFactors: [0.3, 0.7])
        state.splitLayouts = [group]; state.activeSpaceID = source.id; state.selectedTabIDs = group.tabIDs
        state.selectionBySpace = [source.id.uuidString: group.tabIDs, destination.id.uuidString: [existing.id]]
        func location(_ space: UUID, _ parent: UUID?, _ kind: TabKind = .pinned) -> SidebarContainerLocation { .init(spaceID: space, folderID: parent, section: kind) }
        state.sidebarItemOrder[location(source.id, nil).key] = [.folder(folder.id), .tab(pinned.id)]
        state.sidebarItemOrder[location(source.id, folder.id).key] = [.folder(nested.id), .tab(c.id)]
        state.sidebarItemOrder[location(source.id, nested.id).key] = [.tab(b.id)]
        let from = SidebarHierarchySnapshot(state: state, spaceID: source.id, profileID: source.profileID)!
        let to = SidebarHierarchySnapshot(state: state, spaceID: destination.id, profileID: source.profileID)!
        let move = SidebarSpaceMove(items: [.folder(folder.id), .split(group.id), .tab(today.id)], from: from, to: to, state: state)!
        check(move.roots == [.folder(folder.id), .tab(today.id)], "Ancestor absorbs selected descendants")
        check(Set(move.tabIDs) == Set([a.id, b.id, c.id, today.id]), "Whole tree and split children retained")
        let moved = move.applying(to: state)!
        check(moved.tabs.count == state.tabs.count && moved.folders.count == state.folders.count, "No copies or deletions")
        for original in state.tabs {
            var expected = original
            if move.tabIDs.contains(original.id) { expected.spaceID = destination.id }
            check(moved.tabs.first { $0.id == original.id } == expected, "All original navigation/saved/kind/lifetime metadata retained")
        }
        var expectedGroup = group; expectedGroup.spaceID = destination.id
        check(moved.splitLayouts == [expectedGroup], "Original group ID, anchor, orientation and weights survive")
        check(moved.folders.first { $0.id == nested.id }?.parentID == folder.id, "Nested parent survives")
        check(moved.folders.first { $0.id == folder.id }?.isExpanded == false, "Collapsed state survives")
        check(SidebarHierarchy.children(in: location(destination.id, nil), state: moved) == [.tab(existing.id), .folder(folder.id)], "Destination sibling order appends moved roots")
        check(SidebarHierarchy.children(in: location(destination.id, folder.id), state: moved) == [.folder(nested.id), .tab(c.id)], "Mixed folder order migrates")
        check(SidebarHierarchy.children(in: location(destination.id, nested.id), state: moved) == [.split(group.id)], "Split anchor projects to whole group")
        check(moved.sidebarItemOrder[location(source.id, nested.id).key] == nil, "Old nested order key removed")
        check(moved.selectedTabIDs.isEmpty && moved.selectionBySpace[source.id.uuidString] == [], "Source cannot select moved items")
        check(moved.selectionBySpace[destination.id.uuidString] == [existing.id], "Move cannot steal destination's current selection")
        check(move.applying(to: moved) == nil, "One snapshot cannot move twice")
        var stale = state; stale.folders[0].name = "Changed"
        check(move.applying(to: stale) == nil, "Changed original tree refuses stale menu")
        stale = state; stale.sidebarItemOrder[location(destination.id, nil).key] = [.tab(existing.id)]
        check(move.applying(to: stale) == nil, "Changed destination order refuses stale menu")
        stale = state; stale.tabs[0].title = "New page title"
        check(move.applying(to: stale)?.tabs[0].title == "New page title", "Live navigation metadata is not overwritten")
        var foreign = state; let other = BrowserProfile(id: UUID(), name: "Other"); foreign.profiles.append(other); foreign.spaces[1].profileID = other.id; foreign.tabs[5].profileID = other.id
        let foreignTo = SidebarHierarchySnapshot(state: foreign, spaceID: destination.id, profileID: other.id)!
        let crossProfile = SidebarSpaceMove(items: [.folder(folder.id)], from: from, to: foreignTo, state: foreign)
        check(crossProfile?.crossesProfiles == true
            && crossProfile?.applying(to: foreign)?.tabs.first { $0.id == c.id }?.profileID == other.id, "Cross-profile relocation carries the destination Profile")
        check(SidebarSpaceMove(items: [.tab(favorite.id)], from: from, to: to, state: state) == nil, "Profile-wide Favorite is not a Space item")
        check(SidebarSpaceMove(items: [.tab(a.id)], from: from, to: to, state: state) == nil, "Cannot silently detach one split child")
        var mixed = state; mixed.tabs[1].folderID = nil
        let mixedFrom = SidebarHierarchySnapshot(state: mixed, spaceID: source.id, profileID: source.profileID)!
        check(SidebarSpaceMove(items: [.folder(folder.id)], from: mixedFrom, to: to, state: mixed) == nil, "Folder containing only a non-anchor split child refuses partial group movement")
        let single = SidebarSpaceMove(items: [.tab(c.id)], from: from, to: to, state: state)!.applying(to: state)!
        check(single.tabs.first { $0.id == c.id }?.folderID == nil, "Standalone nested tab becomes a destination root")
        let folderReveal = SidebarItemReveal(item: .folder(folder.id), spaceID: destination.id, profileID: source.profileID, state: moved)!
        check(folderReveal.expandedFolderIDs == [folder.id], "Reveal opens the actual folder")
        var withEmpty = moved
        let empty = BrowserFolder(id: UUID(), spaceID: destination.id, name: "Empty", parentID: folder.id, isExpanded: false)
        withEmpty.folders.append(empty)
        let emptyReveal = SidebarItemReveal(item: .folder(empty.id), spaceID: destination.id, profileID: source.profileID, state: withEmpty)!
        check(emptyReveal.expandedFolderIDs == [folder.id], "Empty target reveals its ancestors without an expansion effect")
        check(emptyReveal.applying(to: withEmpty)?.folders.last?.isExpanded == false, "Empty target keeps its disclosure state")
        let reveal = SidebarItemReveal(item: .split(group.id), spaceID: destination.id, profileID: source.profileID, state: moved)!
        check(reveal.expandedFolderIDs == [folder.id, nested.id], "Whole split reveal expands exact ancestors")
        let revealed = reveal.applying(to: moved)!
        check(revealed.folders.filter { reveal.expandedFolderIDs.contains($0.id) }.allSatisfy(\.isExpanded), "Reveal expands all collapsed ancestors")
        check(revealed.tabs == moved.tabs && revealed.splitLayouts == moved.splitLayouts, "Reveal cannot alter page or split records")
        check(revealed.selectedTabIDs == moved.selectedTabIDs && revealed.selectionBySpace == moved.selectionBySpace, "Reveal is distinct from page activation")
        check(SidebarItemReveal(item: .folder(folder.id), spaceID: source.id, profileID: source.profileID, state: moved) == nil, "Stale source Space cannot reveal moved item")
        check(SidebarItemReveal(item: .tab(favorite.id), spaceID: destination.id, profileID: source.profileID, state: moved) == nil, "Profile-wide Favorite is not a moved Space item")
        var changedParent = moved; changedParent.folders[1].parentID = nil
        check(reveal.applying(to: changedParent) == nil, "Changed reveal ancestry refuses stale transaction")
        let owner = NativePageOwnership(), originalWindow = UUID(), otherWindow = UUID()
        check(owner.claim(a.id, owner: originalWindow, page: "original-a"), "Claim original page A")
        check(owner.claim(b.id, owner: originalWindow, page: "original-b"), "Claim original page B")
        let claim = owner.claimSnapshot(a.id)
        check(move.permitsSplitOwners([:], in: originalWindow), "Unmaterialized whole split can move")
        check(move.permitsSplitOwners([a.id: originalWindow, b.id: originalWindow], in: originalWindow), "Original physical owner retains whole split")
        check(!move.permitsSplitOwners([a.id: otherWindow, b.id: otherWindow], in: originalWindow), "Foreign physical split owner is refused")
        check(!move.permitsSplitOwners([a.id: originalWindow, b.id: otherWindow], in: originalWindow), "Mixed physical split owners are refused as a whole")
        var presentation = WindowPresentation(state: state, ready: true)
        presentation.reconcile(moved) { owner.canUse($0, owner: originalWindow) }
        check(presentation.selectedTabIDs.isEmpty, "Original source presentation drops moved selection")
        presentation.selectSpace(destination.id, state: moved) { owner.canUse($0, owner: originalWindow) }
        check(presentation.selectExistingTab(b.id, state: moved, available: { owner.canUse($0, owner: originalWindow) }), "Original owner can select moved split")
        presentation.recordFocusedTab(b.id)
        check(presentation.selectedTabIDs == group.tabIDs && presentation.preferredFocusedTabID == b.id, "Whole split and requested focus restore")
        check(owner.claimSnapshot(a.id) == claim, "Space navigation retains exact native claim")
        check(!owner.canUse(a.id, owner: otherWindow), "Move does not silently adopt another physical owner's page")
        let transfer = owner.reserveTransfer(a.id, page: "original-a", from: originalWindow, to: otherWindow)!
        check(owner.claimSnapshot(a.id).transfer == transfer, "In-progress transfer invalidates owner snapshot")
        check(owner.finishTransfer(transfer, moved: false), "Cancelled transfer keeps original owner")
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("parc-space-move-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let file = directory.appendingPathComponent("session.json")
        try encoder.encode(state).write(to: file)
        let store = try BrowserStore(directory: directory)
        let committed = try store.moveSidebarItemsAcrossSpaces(move)
        check(committed, "Atomic store move commits")
        let reopened = try BrowserStore(directory: directory)
        check(reopened.state.tabs.first { $0.id == a.id }?.spaceID == destination.id, "Committed move persists")
        check(reopened.state.splitLayouts.contains(expectedGroup), "Committed geometry persists")
        let selectionBeforeReveal = reopened.state.selectedTabIDs
        let didReveal = try reopened.revealSidebarItem(reveal)
        check(didReveal && reopened.state.folders.first { $0.id == folder.id }?.isExpanded == true, "Actual reveal persists disclosure")
        check(reopened.state.selectedTabIDs == selectionBeforeReveal, "Actual reveal does not select a moved page")
        try encoder.encode(state).write(to: file)
        let failing = try BrowserStore(directory: directory)
        let prior = failing.state
        try FileManager.default.removeItem(at: file); try FileManager.default.createDirectory(at: file, withIntermediateDirectories: false)
        do { _ = try failing.moveSidebarItemsAcrossSpaces(move); preconditionFailure("Expected rename refusal") } catch {}
        check(failing.state == prior, "Failed write cannot publish a partial hierarchy")

        func proposed(_ original: BrowserState, _ roots: [SidebarItemReference]) -> SidebarSpaceMove? {
            guard let from = SidebarHierarchySnapshot(state: original, spaceID: source.id, profileID: source.profileID),
                  let to = SidebarHierarchySnapshot(state: original, spaceID: destination.id, profileID: source.profileID) else { return nil }
            return SidebarSpaceMove(items: roots, from: from, to: to, state: original)
        }
        for anchorKind in [TabKind.pinned, .today] {
            var original = state
            original.tabs[0].kind = anchorKind == .pinned ? .today : .pinned
            original.tabs[0].folderID = anchorKind == .pinned ? nil : nested.id
            original.tabs[1].kind = anchorKind
            original.tabs[1].folderID = nil
            original.sidebarItemOrder[location(source.id, nil, .today).key] = [.tab(a.id), .tab(b.id), .tab(today.id)]
            original.sidebarItemOrder[location(source.id, nested.id).key] = [.tab(a.id), .tab(b.id)]
            original.sidebarItemOrder[location(source.id, nil).key] = [.folder(folder.id), .tab(b.id), .tab(pinned.id)]
            let proposal = proposed(original, [.split(group.id)])!
            check(proposal.tabIDs == group.tabIDs && proposal.groupIDs == [group.id], "Mixed sections capture every original child once")
            let result = proposal.applying(to: original)!
            for i in original.tabs.indices {
                var expected = original.tabs[i]
                if group.tabIDs.contains(expected.id) {
                    expected.spaceID = destination.id; expected.folderID = nil; expected.kind = anchorKind
                }
                check(result.tabs[i] == expected, "Only explicit container placement changes; saved/navigation/provenance survives")
            }
            check(result.splitLayouts == [expectedGroup], "Mixed-section move keeps group/anchor/order/orientation/proportions")
            check(result.folders == original.folders, "Unselected source folders remain unchanged")
            check(SidebarHierarchySnapshot(state: result, spaceID: destination.id, profileID: source.profileID) != nil, "Destination hierarchy is valid")
            let destinationChildren = SidebarHierarchy.children(in: location(destination.id, nil, anchorKind), state: result)
            check(destinationChildren.last == .split(group.id), "Original anchored group appends in its own projected section")
            let sourceOrders = result.sidebarItemOrder.filter { $0.key.hasPrefix(source.id.uuidString + ":") }
            let sourceReferences = Set(sourceOrders.values.flatMap { $0 })
            check(sourceReferences.isDisjoint(with: [.tab(a.id), .tab(b.id), .split(group.id)]), "No dormant source child/group references survive")
            var separated = result; separated.splitLayouts = []
            check(SidebarHierarchy.children(in: location(destination.id, nil, anchorKind), state: separated).contains(.tab(a.id))
                && SidebarHierarchy.children(in: location(destination.id, nil, anchorKind), state: separated).contains(.tab(b.id)), "Later separation keeps both originals at the destination")
            check(!proposal.permitsSplitOwners([a.id: originalWindow, b.id: otherWindow], in: originalWindow), "Mixed placement does not weaken whole-group physical ownership")
            check(proposed(original, [.tab(a.id)]) == nil, "Mixed-placement child cannot move by itself")
            var changed = original; changed.tabs[0].folderID = folder.id
            check(proposal.applying(to: changed) == nil, "Changed original child placement revokes the complete receipt")
            changed = original; changed.splitLayouts[0].widthFactors = [0.6, 0.4]
            check(proposal.applying(to: changed) == nil, "Changed original geometry revokes the receipt")
            changed = original; changed.tabs[0].kind = .favorite; changed.tabs[0].folderID = nil
            check(proposed(changed, [.split(group.id)]) == nil, "Mixed Favorite and ordinary group remains refused")
        }
        var nestedMixed = state
        let outside = BrowserFolder(id: UUID(), spaceID: source.id, name: "Stays", parentID: nil, isExpanded: false)
        nestedMixed.folders.append(outside)
        nestedMixed.tabs[0].folderID = outside.id
        nestedMixed.tabs[0].url = InternalPage.note(UUID()).urlString
        nestedMixed.tabs[0].savedURL = nestedMixed.tabs[0].url
        nestedMixed.tabs[1].url = InternalPage.easel(UUID()).urlString
        nestedMixed.tabs[1].savedURL = nestedMixed.tabs[1].url
        nestedMixed.sidebarItemOrder[location(source.id, outside.id).key] = [.tab(a.id)]
        nestedMixed.sidebarItemOrder[location(source.id, nested.id).key] = [.tab(b.id)]
        let nestedMove = proposed(nestedMixed, [.folder(folder.id)])!
        let nestedResult = nestedMove.applying(to: nestedMixed)!
        check(Set(nestedMove.tabIDs) == Set([a.id, b.id, c.id]) && nestedMove.groupIDs == [group.id], "Moving anchor ancestor includes original outside child as part of whole group")
        check(nestedMove.folderIDs == [folder.id, nested.id], "Move does not pull in the non-anchor child's former folder")
        check(nestedResult.tabs[0].folderID == nested.id && nestedResult.tabs[1].folderID == nested.id, "Whole group is nested in the moved original anchor folder")
        check(nestedResult.tabs[0].savedURL == nestedMixed.tabs[0].savedURL && nestedResult.tabs[1].savedURL == nestedMixed.tabs[1].savedURL, "Note and Easel references are unchanged")
        check(nestedResult.folders.last == outside, "Unselected outside folder stays in original Space")
        check(nestedResult.sidebarItemOrder[location(source.id, outside.id).key] == [], "Outside source folder loses its dormant split-child entry")
        check(SidebarHierarchy.children(in: location(destination.id, nested.id), state: nestedResult) == [.split(group.id)], "Nested group retains one original mixed-order slot")
        check(SidebarHierarchy.children(in: location(destination.id, folder.id), state: nestedResult) == [.folder(nested.id), .tab(c.id)], "Nested mixed sibling order survives relocation")
        check(SidebarHierarchySnapshot(state: nestedResult, spaceID: destination.id, profileID: source.profileID) != nil, "No source-only folder reference crosses into destination")
        check(proposed(nestedMixed, [.folder(outside.id)]) == nil, "A folder containing only a hidden non-anchor child cannot split the group")
        let both = proposed(nestedMixed, [.folder(outside.id), .split(group.id)])!
        let bothResult = both.applying(to: nestedMixed)!
        check(Set(both.tabIDs) == Set(group.tabIDs) && both.folderIDs == [outside.id], "Explicit roots include group once even when an old child folder also moves")
        check(bothResult.tabs[0].folderID == nil && bothResult.tabs[1].folderID == nil, "Explicit root group cannot remain in a separately moved old child folder")
        check(SidebarHierarchy.children(in: location(destination.id, nil), state: bothResult) == [.tab(existing.id), .folder(outside.id), .split(group.id)], "Explicit mixed roots retain their captured order")
        let nestedFrom = SidebarHierarchySnapshot(state: nestedMixed, spaceID: source.id, profileID: source.profileID)!
        var draft = SidebarNewSpaceDraft(items: [.folder(folder.id)], from: nestedFrom, state: nestedMixed)!
        draft.name = "Original group"
        check(Set(draft.tabIDs) == Set(nestedMove.tabIDs) && draft.groupIDs == nestedMove.groupIDs, "New Space draft supplies all original children to the same window-owner gates")
        let newSpaceResult = draft.applying(to: nestedMixed)!
        check(newSpaceResult.tabs[0].spaceID == draft.spaceID && newSpaceResult.tabs[0].folderID == nested.id, "New Space consumes the complete nested-group move")
        check(newSpaceResult.splitLayouts[0].id == group.id && newSpaceResult.splitLayouts[0].spaceID == draft.spaceID, "New Space retains original split identity")
        check(newSpaceResult.spaces.firstIndex { $0.id == draft.spaceID } == newSpaceResult.spaces.firstIndex { $0.id == source.id }! + 1, "New Space retains recovered source-relative insertion")
        var cancelled = draft; cancelled.name = ""
        check(cancelled.applying(to: nestedMixed) == nil && nestedMixed.spaces.count == state.spaces.count, "Refused draft cannot persist an empty Space")
        let mixedDirectory = directory.appendingPathComponent("mixed")
        try FileManager.default.createDirectory(at: mixedDirectory, withIntermediateDirectories: true)
        let mixedFile = mixedDirectory.appendingPathComponent("session.json")
        try encoder.encode(nestedMixed).write(to: mixedFile)
        let mixedStore = try BrowserStore(directory: mixedDirectory)
        let actualMove = proposed(mixedStore.state, [.folder(folder.id)])!
        let committedMixed = try mixedStore.moveSidebarItemsAcrossSpaces(actualMove)
        check(committedMixed, "Actual store accepts the complete mixed-group transaction")
        let persistedMixed = try BrowserStore(directory: mixedDirectory)
        check(persistedMixed.state.tabs[0].folderID == nested.id && persistedMixed.state.tabs[0].spaceID == destination.id, "Actual storage reload retains normalized child placement")
        check(persistedMixed.state.tabs[0].savedURL == nestedMixed.tabs[0].savedURL, "Local document identity survives durable move")
        try encoder.encode(nestedMixed).write(to: mixedFile)
        let newSpaceStore = try BrowserStore(directory: mixedDirectory)
        let storeFrom = SidebarHierarchySnapshot(state: newSpaceStore.state, spaceID: source.id, profileID: source.profileID)!
        var storeDraft = SidebarNewSpaceDraft(items: [.split(group.id)], from: storeFrom, state: newSpaceStore.state)!
        storeDraft.name = "One transaction"
        let created = try newSpaceStore.createSpaceAndMoveSidebarItems(storeDraft)
        check(created == storeDraft.spaceID, "Actual New Space command commits the mixed group")
        let persistedNew = try BrowserStore(directory: mixedDirectory)
        check(persistedNew.state.tabs[0].spaceID == created && persistedNew.state.tabs[0].folderID == nil, "New Space stores root group without foreign folder IDs")
        check(persistedNew.state.splitLayouts[0].id == group.id, "New Space does not recreate original group")
        try encoder.encode(nestedMixed).write(to: mixedFile)
        let failedNew = try BrowserStore(directory: mixedDirectory)
        let beforeFailedNew = failedNew.state
        let failureSource = SidebarHierarchySnapshot(state: beforeFailedNew, spaceID: source.id, profileID: source.profileID)!
        var failureDraft = SidebarNewSpaceDraft(items: [.folder(folder.id)], from: failureSource, state: beforeFailedNew)!
        failureDraft.name = "Failure"
        try FileManager.default.removeItem(at: mixedFile)
        try FileManager.default.createDirectory(at: mixedFile, withIntermediateDirectories: false)
        do { _ = try failedNew.createSpaceAndMoveSidebarItems(failureDraft); preconditionFailure("Expected failed atomic New Space save") } catch {}
        check(failedNew.state == beforeFailedNew, "Failed New Space save keeps all original mixed placement and no empty Space")
        do { _ = try failedNew.moveSidebarItemsAcrossSpaces(proposed(beforeFailedNew, [.folder(folder.id)])!); preconditionFailure("Expected failed atomic move save") } catch {}
        check(failedNew.state == beforeFailedNew, "Failed existing-Space move also publishes nothing")

        print("SidebarSpaceMoveTests: \(count) assertions passed")
    }
}
