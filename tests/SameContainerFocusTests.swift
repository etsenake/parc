import Foundation

@main
struct SameContainerFocusTests {
    @MainActor static func main() throws {
        var count = 0
        func expect(_ value: @autoclosure () -> Bool, _ message: String) {
            count += 1; precondition(value(), message)
        }
        var state = BrowserState.initial()
        let space = state.spaces[0], profile = space.profileID
        let other = BrowserSpace(id: UUID(), name: "Other", symbol: "circle", color: "123456", profileID: profile)
        state.spaces.append(other)
        func tab(_ kind: TabKind = .today, spaceID: UUID? = nil, folder: UUID? = nil) -> BrowserTab {
            BrowserTab(id: UUID(), spaceID: spaceID ?? space.id, profileID: profile,
                url: "https://example.test/", title: "Original", kind: kind, folderID: folder,
                createdAt: Date(timeIntervalSince1970: 1), lastAccessed: Date(timeIntervalSince1970: 1),
                savedURL: "https://example.test/", savedTitle: "Original")
        }
        let previous = tab(), neighbor = tab(), current = tab(), next = tab()
        state.tabs = [previous, neighbor, current, next]
        state.selectedTabIDs = [current.id]
        state.selectionBySpace[space.id.uuidString] = [current.id]
        func choose(_ input: BrowserState, remembered: UUID? = previous.id,
                    closing: UUID = current.id, removed: Set<UUID>? = nil,
                    pool: Set<UUID> = [], unavailable: Set<UUID> = []) -> FolderRemovalSelection? {
            FolderRemovalSelection.resolve(removing: removed ?? [closing], spaceID: space.id,
                profileID: profile, state: input, selected: [closing], focused: closing,
                referrerPool: pool, previouslySelectedItemID: remembered,
                available: { !unavailable.contains($0) })
        }
        var origin = WindowPresentation(state: state, ready: true)
        expect(origin.previouslySelectedItemID == nil, "Restoration does not fabricate the previous item")
        origin.recordSelectionForReturn(previous.id, state: state)
        expect(origin.previouslySelectedItemID == current.id, "A real selection records the original outgoing item")
        origin.recordSelectionForReturn(previous.id, state: state)
        expect(origin.previouslySelectedItemID == current.id, "Refresh does not overwrite previous selection")
        origin.recordSelectionForReturn(UUID(), state: state)
        expect(origin.previouslySelectedItemID == current.id, "Unresolved incoming item does not change the previous-item producer")
        origin.recordSelectionForReturn(nil, state: state)
        expect(origin.previouslySelectedItemID == current.id, "Nil selection leaves the remembered value alone")
        origin.recordSelectionForReturn(next.id, state: state)
        expect(origin.previouslySelectedItemID == nil, "Selection with no original outgoing item clears previous")
        let peer = WindowPresentation(state: state, ready: true)
        expect(peer.previouslySelectedItemID == nil, "Another physical window does not acquire selection history")
        expect(choose(state)?.tabIDs == [previous.id], "Actual previous item precedes the adjacent fallback")
        func closeSplitPane(_ closing: BrowserTab) -> FolderRemovalSelection? {
            FolderRemovalSelection.resolve(removing: [closing.id], spaceID: space.id, profileID: profile, state: state,
                selected: [previous.id, neighbor.id, current.id], focused: closing.id, available: { _ in true })
        }
        expect(closeSplitPane(current)?.tabIDs == [previous.id, neighbor.id] && closeSplitPane(current)?.focusedTabID == neighbor.id,
               "Closing the focused last pane focuses the new last pane")
        expect(closeSplitPane(neighbor)?.tabIDs == [previous.id, current.id] && closeSplitPane(neighbor)?.focusedTabID == current.id,
               "Closing the focused middle pane focuses the pane that takes its place")
        expect(choose(state)?.replacementSpaceID == space.id, "Same Space return retains its Space")
        expect(choose(state, remembered: nil)?.tabIDs == [neighbor.id], "No remembered item keeps the original previous-neighbor fallback")
        expect(choose(state, remembered: UUID())?.tabIDs == [neighbor.id], "Missing item does not resurrect")
        expect(choose(state, remembered: current.id)?.tabIDs == [neighbor.id], "Closing item cannot become its own replacement")
        expect(choose(state, unavailable: [previous.id])?.tabIDs == [neighbor.id], "Another owner's page is not reclaimed")
        expect(choose(state, removed: [previous.id, current.id])?.tabIDs == [neighbor.id], "Whole closing set excludes remembered items")
        var archived = state; archived.tabs[0].archivedAt = Date()
        expect(choose(archived)?.tabIDs == [neighbor.id], "Archived item cannot be selected")
        var foreign = state; foreign.tabs[0].profileID = UUID()
        expect(choose(foreign)?.tabIDs == [neighbor.id], "Profile isolation applies before any return")
        var across = state; across.tabs[0].spaceID = other.id
        expect(choose(across)?.tabIDs == [neighbor.id], "Two normal Space containers must have the same Space ID")
        var folders = state
        let firstFolder = BrowserFolder(id: UUID(), spaceID: space.id, name: "First")
        let secondFolder = BrowserFolder(id: UUID(), spaceID: space.id, name: "Nested", parentID: firstFolder.id)
        folders.folders = [firstFolder, secondFolder]
        folders.tabs[0].kind = .pinned; folders.tabs[0].folderID = secondFolder.id
        expect(choose(folders)?.tabIDs == [previous.id], "Different nested folders and Today belong to the same outer Space")
        var child = state; child.tabs[1].referrerID = current.id
        expect(choose(child)?.tabIDs == [neighbor.id], "Genuine adjacent child precedes previous-selected fallback")
        var creation = state; creation.tabs[2].activeTabBeforeCreationID = next.id
        expect(choose(creation, pool: [next.id])?.tabIDs == [next.id], "Creation-active pool branch still wins")
        var favorites = across; favorites.tabs[2].kind = .favorite
        let cross = choose(favorites)!
        expect(cross.tabIDs == [previous.id] && cross.replacementSpaceID == other.id,
               "Favorite can return to prior original tab in another Space of the same Profile")
        expect(cross.spaceID == space.id && cross.original == [current.id], "Admission retains original Space and selection")
        var normalToFavorite = across; normalToFavorite.tabs[0].kind = .favorite
        expect(choose(normalToFavorite)?.tabIDs == [previous.id] && choose(normalToFavorite)?.replacementSpaceID == space.id,
               "Returning to a profile-wide Favorite preserves the current Space")
        var bothFavorite = favorites; bothFavorite.tabs[0].kind = .favorite
        expect(choose(bothFavorite)?.replacementSpaceID == space.id, "Two Favorites compare Profile and retain current Space")
        var missingSpace = favorites; missingSpace.spaces.removeAll { $0.id == other.id }
        expect(choose(missingSpace)?.tabIDs != [previous.id], "Removed destination Space invalidates the remembered item")
        var split = favorites
        let partner = tab(spaceID: other.id); split.tabs.append(partner)
        let group = BrowserSplitLayout(spaceID: other.id, tabIDs: [partner.id, previous.id], orientation: .vertical, widthFactors: [0.3, 0.7])
        split.splitLayouts = [group]
        let splitDecision = choose(split)!
        expect(splitDecision.tabIDs == group.tabIDs && splitDecision.focusedTabID == previous.id,
               "Previous pane returns the original whole split with original focused child")
        expect(choose(split, unavailable: [partner.id])?.tabIDs != group.tabIDs, "One unavailable pane excludes the whole split")
        var invalidSplit = split; invalidSplit.splitLayouts[0].widthFactors = [0, 0]
        expect(choose(invalidSplit)?.tabIDs != group.tabIDs, "Malformed original split is not repaired by close focus")
        var splitWindow = WindowPresentation(state: split, ready: true)
        splitWindow.remove(current.id)
        expect(splitWindow.finishFolderRemoval(splitDecision, state: split, available: { _ in true }), "Original window applies complete cross-Space split receipt")
        expect(splitWindow.previouslySelectedItemID == current.id, "Approved close records its original outgoing item once")
        expect(splitWindow.activeSpaceID == other.id && splitWindow.selectedTabIDs == group.tabIDs, "Window switches Space and original pages together")
        expect(splitWindow.preferredFocusedTabID == previous.id && splitWindow.splitLayout?.widthFactors == [0.3, 0.7],
               "Original pane focus and geometry survive the return")
        var changedWindow = WindowPresentation(state: favorites, ready: true)
        _ = changedWindow.selectExistingTab(neighbor.id, state: favorites, available: { _ in true })
        expect(!changedWindow.finishFolderRemoval(cross, state: favorites, available: { _ in true }), "Newer selection wins over delayed close completion")
        var unavailableWindow = WindowPresentation(state: favorites, ready: true)
        expect(!unavailableWindow.finishFolderRemoval(cross, state: favorites, available: { $0 != previous.id }), "Replacement ownership is rechecked after unload")

        var lastState = state; lastState.tabs = [current]
        var lastWindow = WindowPresentation(state: lastState, ready: true)
        let empty = choose(lastState, remembered: nil)!
        lastWindow.remove(current.id)
        expect(lastWindow.finishFolderRemoval(empty, state: lastState, available: { _ in true }) && lastWindow.selectedTabIDs.isEmpty,
               "Closing the final item commits the genuine empty selection")
        lastWindow.recordSelectionForReturn(next.id, state: state)
        expect(lastWindow.previouslySelectedItemID == nil, "Selection after committed Start cannot inherit the retired outgoing item")

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try BrowserStore(directory: directory)
        let originalSpace = store.activeSpaceID
        let favorite = store.open("https://favorite.example", kind: .favorite)
        let destination = store.createSpace(name: "Destination")
        let actualPrevious = store.open("https://previous.example")
        store.selectSpace(originalSpace); store.selectTab(favorite)
        let receipt = FolderRemovalSelection.resolve(removing: [favorite], spaceID: originalSpace,
            profileID: store.activeSpace.profileID, state: store.state, selected: [favorite], focused: favorite,
            previouslySelectedItemID: actualPrevious, available: { _ in true })!
        var window = WindowPresentation(state: store.state, ready: true)
        var validate: (() -> Bool)?, finish: ((Bool) -> Void)?, result: Bool?
        store.requestPageRetirement = { _, gate, done in validate = gate; finish = done }
        store.closeTabs([favorite], selection: receipt, shouldCommit: { true }) { result = $0 }
        expect(result == nil && store.activeSpaceID == originalSpace && store.state.selectedTabIDs == [favorite],
               "Beforeunload does not switch Space or selection early")
        expect(validate?() == true, "Live exact destination passes pre-unload validation")
        finish?(false)
        expect(result == false && store.activeSpaceID == originalSpace, "Refusal preserves original physical context")
        store.closeTabs([favorite], selection: receipt, shouldCommit: { true }) { result = $0 }
        expect(validate?() == true, "Retry retains exact original/destination binding")
        finish?(true)
        expect(result == true && store.activeSpaceID == destination && store.state.selectedTabIDs == [actualPrevious],
               "Actual approved close publishes destination Space and original item atomically")
        expect(store.state.tabs.contains { $0.id == favorite && $0.archivedAt == nil }, "Favorite close retains its genuine saved record")
        window.remove(favorite)
        expect(window.finishFolderRemoval(receipt, state: store.state, available: { _ in true }), "Original physical window consumes approved destination")
        expect(window.activeSpaceID == destination && window.selectedTabIDs == [actualPrevious], "Physical presentation matches the approved result")
        try store.save()
        let loaded = try BrowserStore(directory: directory)
        expect(loaded.activeSpaceID == destination && loaded.state.selectedTabIDs == [actualPrevious], "Durable session retains returned Space/selection without fabricating pages")
        store.selectSpace(originalSpace); store.selectTab(favorite)
        let retry = FolderRemovalSelection.resolve(removing: [favorite], spaceID: originalSpace,
            profileID: store.activeSpace.profileID, state: store.state, selected: [favorite], focused: favorite,
            previouslySelectedItemID: actualPrevious, available: { _ in true })!
        store.closeTabs([favorite], selection: retry, shouldCommit: { true }) { result = $0 }
        store.requestPageRetirement = nil
        store.closeTab(actualPrevious)
        expect(validate?() == false, "A destination archived during native consent revokes the receipt")
        finish?(true)
        expect(result == false && store.activeSpaceID == originalSpace, "Even a late close callback cannot publish a stale destination")
        let keptFolder = store.createFolder(name: "Keep")
        let kept = store.open("https://kept.example", kind: .pinned)
        store.moveTab(kept, toSpace: originalSpace, folderID: keptFolder)
        let deletedFolder = store.createFolder(name: "Delete")
        let doomed = store.open("https://doomed.example", kind: .pinned)
        store.moveTab(doomed, toSpace: originalSpace, folderID: deletedFolder)
        let target = FolderRemovalTarget(folderID: deletedFolder, spaceID: originalSpace,
            profileID: store.activeSpace.profileID, state: store.state)!
        let folderChoice = FolderRemovalSelection.resolve(target: target, state: store.state,
            selected: [doomed], focused: doomed, previouslySelectedItemID: kept, available: { _ in true })!
        expect(folderChoice.tabIDs == [kept], "Folder Delete uses the same recovered outer-container return")
        var deletion: Result<Bool, Error>?
        store.requestPageRetirement = { _, gate, done in validate = gate; finish = done }
        store.deleteFolder(target, selection: folderChoice, shouldCommit: { true }) { deletion = $0 }
        expect(validate?() == true && store.state.selectedTabIDs == [doomed], "Folder admission carries the actual remembered ID without early focus")
        finish?(true)
        let deleted = (try? deletion?.get()) == true
        expect(deleted && store.state.selectedTabIDs == [kept] && !store.state.folders.contains { $0.id == deletedFolder },
               "Durable folder deletion publishes exact other-folder return")
        let folderReload = try BrowserStore(directory: directory)
        expect(folderReload.state.selectedTabIDs == [kept] && folderReload.state.tabs.contains { $0.id == doomed && $0.archivedAt != nil },
               "Folder archive and original replacement survive the actual saved session")
        print("Same-container focus: \(count) assertions passed")
    }
}
