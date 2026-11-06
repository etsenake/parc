import Foundation

@main
struct TabCreationProvenanceTests {
    @MainActor static func main() throws {
        var count = 0
        func expect(_ value: @autoclosure () -> Bool, _ message: String) {
            count += 1; precondition(value(), message)
        }
        var state = BrowserState.initial()
        let space = state.spaces[0], profile = space.profileID
        func tab(_ kind: TabKind = .today, referrer: UUID? = nil, previous: UUID? = nil) -> BrowserTab {
            BrowserTab(id: UUID(), spaceID: space.id, profileID: profile,
                url: "https://example.test/", title: "Original", kind: kind,
                createdAt: Date(timeIntervalSince1970: 1), lastAccessed: Date(timeIntervalSince1970: 1),
                savedURL: "https://example.test/", savedTitle: "Original",
                referrerID: referrer, activeTabBeforeCreationID: previous)
        }
        let parent = tab(.pinned), previous = tab(), current = tab(), child = tab(referrer: current.id)
        state.tabs = [parent, previous, current, child]
        state.selectedTabIDs = [current.id]
        state.selectionBySpace[space.id.uuidString] = [current.id]
        let receipt = TabCreationProvenance(referrerID: parent.id, activeTabID: previous.id, profileID: profile, state: state)
        expect(receipt.referrerID == parent.id && receipt.activeTabBeforeCreationID == parent.id, "Explicit original referrer wins over active-before")
        let ordinary = TabCreationProvenance(referrerID: nil, activeTabID: previous.id, profileID: profile, state: state)
        expect(ordinary.referrerID == nil && ordinary.activeTabBeforeCreationID == previous.id, "Ordinary creation captures actual previous active ID")
        expect(receipt.validated(profileID: UUID(), state: state).activeTabBeforeCreationID == nil, "Target profile cannot accept another profile's receipt")
        var gone = state; gone.tabs.removeAll { $0.id == parent.id }
        expect(receipt.validated(profileID: profile, state: gone).referrerID == nil, "A removed source is not resurrected at insertion")
        // A same-Profile routed tab can retain an exact source owned by a
        //
        //
        // source only as active-before. Created contents keep the referrer.
        let routedSpace = BrowserSpace(id: UUID(), name: "Routed", symbol: "circle", color: "123456", profileID: profile)
        var routedState = state; routedState.spaces.append(routedSpace)
        var sourceWindow = WindowPresentation(state: routedState, ready: true)
        var destinationWindow = WindowPresentation(state: routedState, ready: true)
        let routedReceipt = TabCreationProvenance(routedFrom: parent.id, openedLink: true,
            profileID: profile, state: routedState)
        expect(routedReceipt.referrerID == nil && routedReceipt.activeTabBeforeCreationID == parent.id,
               "A matched link records its source only as the creating window's active item")
        let createdReceipt = TabCreationProvenance(routedFrom: parent.id, openedLink: false,
            profileID: profile, state: routedState)
        expect(createdReceipt.referrerID == parent.id && createdReceipt.activeTabBeforeCreationID == parent.id,
               "Routed created contents keep their source as referrer")
        var routed = tab(referrer: routedReceipt.referrerID, previous: routedReceipt.activeTabBeforeCreationID)
        routed.spaceID = routedSpace.id; routedState.tabs.append(routed)
        destinationWindow.recordCreation(routed.id, state: routedState)
        expect(destinationWindow.referrerPool == [parent.id, routed.id], "Destination replaces its pool with the source and child")
        expect(sourceWindow.referrerPool.isEmpty, "Destination creation never modifies the source window's pool")
        expect(sourceWindow.selectedTabIDs == [current.id], "Destination adoption cannot select the source window")
        let foreignReceipt = createdReceipt.validated(profileID: UUID(), state: routedState)
        expect(foreignReceipt.referrerID == nil && foreignReceipt.activeTabBeforeCreationID == nil,
               "Cross-Profile adoption never imports either source identity")
        var retiredSource = routedState
        retiredSource.tabs[retiredSource.tabs.firstIndex { $0.id == parent.id }!].archivedAt = Date()
        expect(routedReceipt.validated(profileID: profile, state: retiredSource).activeTabBeforeCreationID == nil,
               "A source retired before adoption cannot produce a new relationship")
        var changedProfile = routedState
        changedProfile.tabs[changedProfile.tabs.firstIndex { $0.id == parent.id }!].profileID = UUID()
        expect(createdReceipt.validated(profileID: profile, state: changedProfile).activeTabBeforeCreationID == nil,
               "Source Profile changes invalidate both stored identities")
        //
        // creator would capture the source window's tab, which no return
        // consumer accepts across Profiles, so neither identity is recorded.
        let unsourced = TabCreationProvenance(routedFrom: nil, openedLink: false, profileID: profile, state: routedState)
        expect(unsourced.referrerID == nil && unsourced.activeTabBeforeCreationID == nil,
               "A routed page without a same-Profile source borrows no destination selection")
        let windowOnly = TabCreationProvenance(referrerID: nil, activeTabID: nil, profileID: profile, state: routedState)
        expect(windowOnly.referrerID == nil && windowOnly.activeTabBeforeCreationID == nil,
               "URL-only new-window creation does not adopt an unrelated current selection")
        sourceWindow.recordSelectionForReturn(previous.id, state: routedState)
        expect(destinationWindow.referrerPool == [parent.id, routed.id], "Source selection changes do not overwrite the destination's accepted receipt")
        let encoder = JSONEncoder(), decoder = JSONDecoder()
        let encoded = try encoder.encode(child)
        let roundTrip = try decoder.decode(BrowserTab.self, from: encoded)
        expect(roundTrip == child, "Creation IDs round trip with the saved record")
        var old = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
        old.removeValue(forKey: "referrerID"); old.removeValue(forKey: "activeTabBeforeCreationID")
        let decoded = try decoder.decode(BrowserTab.self, from: JSONSerialization.data(withJSONObject: old))
        expect(decoded.referrerID == nil && decoded.activeTabBeforeCreationID == nil, "Old records decode without inventing provenance")

        var window = WindowPresentation(state: state, ready: true)
        window.recordSelectionForReturn(current.id, state: state)
        expect(window.referrerPool.isEmpty, "Window pool is not synthesized from persisted selection")
        var creationState = state
        let first = tab(previous: current.id), second = tab(referrer: current.id, previous: current.id)
        creationState.tabs += [first, second]
        window.recordCreation(first.id, state: creationState)
        expect(window.referrerPool == [current.id, first.id], "No-referrer creation replaces pool with active and new")
        window.recordCreation(second.id, state: creationState)
        expect(window.referrerPool == [current.id, first.id, second.id], "Explicit-referrer creation unions actual IDs")
        window.recordSelectionForReturn(current.id, state: creationState)
        expect(window.referrerPool.count == 3, "A refresh of unchanged focus does not erase background creation")
        window.recordSelectionForReturn(second.id, state: creationState)
        expect(window.referrerPool.count == 3, "Selecting pooled Today retains the chain")
        window.recordCreation(parent.id, state: creationState)
        expect(window.referrerPool.count == 3, "Creation without either ID leaves the pool alone")
        let pinnedChild = tab(.pinned, referrer: current.id, previous: current.id)
        creationState.tabs.append(pinnedChild); window.recordCreation(pinnedChild.id, state: creationState)
        window.recordSelectionForReturn(pinnedChild.id, state: creationState)
        expect(window.referrerPool == [pinnedChild.id], "Selecting pooled pinned context keeps only that item")
        window.recordSelectionForReturn(previous.id, state: creationState)
        expect(window.referrerPool.isEmpty, "An unrelated actual selection clears the pool")
        var peer = WindowPresentation(state: creationState, ready: true)
        expect(peer.referrerPool.isEmpty, "Another physical window never receives this chain")

        func choose(_ input: BrowserState, closing: UUID = current.id, pool: Set<UUID> = [], unavailable: Set<UUID> = []) -> FolderRemovalSelection? {
            FolderRemovalSelection.resolve(removing: [closing], spaceID: space.id, profileID: profile,
                state: input, selected: [closing], focused: closing, referrerPool: pool,
                available: { !unavailable.contains($0) })
        }
        expect(choose(state)?.tabIDs == [child.id], "Adjacent genuine child wins over ordinary previous item")
        var siblings = state
        siblings.tabs.removeAll { $0.id == child.id }
        let sibling = tab(referrer: parent.id), unrelated = tab()
        siblings.tabs[siblings.tabs.firstIndex { $0.id == current.id }!].referrerID = parent.id
        siblings.tabs += [unrelated, sibling]
        expect(choose(siblings, pool: [current.id, sibling.id])?.tabIDs == [sibling.id], "Pooled subsequent sibling wins over ordinary neighbor")
        expect(choose(siblings)?.tabIDs == [previous.id], "Available items are not a substitute for the actual pool")
        expect(choose(siblings, pool: [sibling.id])?.tabIDs == [previous.id], "Closing item must also belong to sibling chain")
        var active = state; active.tabs.removeAll { $0.id == child.id }
        active.tabs[active.tabs.firstIndex { $0.id == current.id }!].activeTabBeforeCreationID = parent.id
        expect(choose(active, pool: [parent.id])?.tabIDs == [parent.id], "Original active-before wins over unrelated adjacent item")
        expect(choose(active, pool: [parent.id], unavailable: [parent.id])?.tabIDs == [previous.id], "Unavailable owner cannot be reclaimed by provenance")
        let otherSpace = BrowserSpace(id: UUID(), name: "Other", symbol: "circle", color: "123456", profileID: profile)
        active.spaces.append(otherSpace)
        active.tabs[active.tabs.firstIndex { $0.id == parent.id }!].spaceID = otherSpace.id
        expect(choose(active, pool: [parent.id])?.tabIDs == [previous.id], "Pinned return cannot cross original Space")
        active.tabs[active.tabs.firstIndex { $0.id == parent.id }!].kind = .favorite
        expect(choose(active, pool: [parent.id])?.tabIDs == [parent.id], "Original profile's Favorite may return across Spaces")
        active.tabs[active.tabs.firstIndex { $0.id == parent.id }!].profileID = UUID()
        expect(choose(active, pool: [parent.id])?.tabIDs == [previous.id], "A foreign profile never becomes a return target")
        var splitState = state; splitState.tabs.removeAll { $0.id == child.id }
        let partner = tab(.pinned); splitState.tabs.append(partner)
        splitState.splitLayouts = [BrowserSplitLayout(spaceID: space.id, tabIDs: [parent.id, partner.id], orientation: .vertical, widthFactors: [0.4, 0.6])]
        splitState.tabs[splitState.tabs.firstIndex { $0.id == current.id }!].activeTabBeforeCreationID = parent.id
        expect(choose(splitState, pool: [parent.id])?.tabIDs == [parent.id, partner.id], "Return preserves the original complete split")
        expect(choose(splitState, pool: [parent.id], unavailable: [partner.id])?.tabIDs == [previous.id], "One unavailable split pane refuses that whole return target")
        let background = FolderRemovalSelection.resolve(removing: [parent.id], spaceID: space.id, profileID: profile,
            state: state, selected: [current.id], focused: current.id, referrerPool: [parent.id], available: { _ in true })!
        expect(background.tabIDs == [current.id], "Closing background items preserves exact active selection")
        expect(FolderRemovalSelection.resolve(removing: [current.id], spaceID: space.id, profileID: profile,
            state: state, selected: [current.id, previous.id], focused: current.id, available: { _ in true })?.tabIDs == [previous.id], "Surviving original pane precedes return candidates")

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try BrowserStore(directory: directory)
        let original = store.open("https://original.example", kind: .pinned)
        let adjacent = store.open("https://adjacent.example")
        let created = store.open("https://new.example", creation: TabCreationProvenance(referrerID: original,
            activeTabID: adjacent, profileID: store.activeSpace.profileID, state: store.state))
        expect(store.state.tabs.first { $0.id == created }?.referrerID == original, "Actual creation writes its source receipt")
        var origin = WindowPresentation(state: store.state, ready: true)
        origin.recordCreation(created, state: store.state)
        let decision = FolderRemovalSelection.resolve(removing: [created], spaceID: store.activeSpaceID,
            profileID: store.activeSpace.profileID, state: store.state, selected: [created], focused: created,
            referrerPool: origin.referrerPool, available: { _ in true })!
        expect(decision.tabIDs == [original], "Actual store can return to original pinned source")
        var validator: (() -> Bool)?, finish: ((Bool) -> Void)?, closed: Bool?
        store.requestPageRetirement = { _, validate, complete in validator = validate; finish = complete }
        store.closeTabs([created], selection: decision, shouldCommit: { true }) { closed = $0 }
        expect(store.state.selectedTabIDs == [created] && closed == nil, "Pending beforeunload neither changes selection nor archives")
        expect(validator?() == true, "Exact original decision is revalidated before unload")
        finish?(false)
        expect(closed == false && store.state.tabs.first { $0.id == created }?.archivedAt == nil, "Refusal preserves original record and selection")
        store.closeTabs([created], selection: decision, shouldCommit: { true }) { closed = $0 }
        expect(validator?() == true, "Retry retains original owner validation")
        finish?(true)
        expect(closed == true && store.state.selectedTabIDs == [original], "Approved close publishes archive and source return together")
        expect(store.state.tabs.first { $0.id == created }?.archivedAt != nil, "Closed Today record remains genuine archive data")
        origin.reconcile(store.state) { _ in true }
        peer = WindowPresentation(state: store.state, ready: false)
        expect(origin.finishFolderRemoval(decision, state: store.state, available: { _ in true }), "Origin alone consumes its completed focus receipt")
        expect(origin.selectedTabIDs == [original] && !peer.isReady, "No other window is activated by replacement")
        try store.save()
        let reload = try BrowserStore(directory: directory)
        expect(reload.state.tabs.first { $0.id == created }?.activeTabBeforeCreationID == original, "Durable archive retains creation metadata without reviving a page")
        expect(reload.state.selectedTabIDs == [original], "Durable selection agrees with original close result")

        var savedState = state
        savedState.tabs[savedState.tabs.firstIndex { $0.id == current.id }!].kind = .pinned
        let savedDecision = choose(savedState)!
        var savedWindow = WindowPresentation(state: savedState, ready: true)
        savedWindow.remove(current.id)
        expect(savedWindow.finishFolderRemoval(savedDecision, state: savedState, available: { _ in true }), "Saved close can consume replacement even though bookmark remains live in model")
        expect(savedState.tabs.contains { $0.id == current.id && $0.archivedAt == nil }, "Saved return does not delete original bookmark")
        var newer = WindowPresentation(state: savedState, ready: true)
        _ = newer.selectExistingTab(parent.id, state: savedState, available: { _ in true })
        expect(!newer.finishFolderRemoval(savedDecision, state: savedState, available: { _ in true }), "Later user selection wins over delayed close focus")
        store.requestPageRetirement = nil
        let source = store.open("https://copy-source.example", creation: TabCreationProvenance(referrerID: adjacent,
            activeTabID: adjacent, profileID: store.activeSpace.profileID, state: store.state))
        store.selectTab(original)
        let copyReceipt = TabCreationProvenance(referrerID: nil, activeTabID: original,
            profileID: store.activeSpace.profileID, state: store.state)
        let target = SidebarDuplicateTarget(items: [.tab(source)], spaceID: store.activeSpaceID,
            profileID: store.activeSpace.profileID, state: store.state)!
        let result = try store.duplicateSidebarItems(target, destinations: [source: "https://copy-source.example"],
            creation: copyReceipt)!
        let copiedTab = store.state.tabs.first { $0.id == result.tabIDs[0] }!
        expect(copiedTab.referrerID == nil, "Duplicate does not inherit source's referrer")
        expect(copiedTab.activeTabBeforeCreationID == original, "Duplicate captures exact origin's active item")
        expect(store.state.selectedTabIDs == [original], "Duplicate background ownership preserves original selection")
        expect(store.state.tabs.first { $0.id == source }?.referrerID == adjacent, "Copy leaves original chain unchanged")
        let folder = store.createFolder(name: "Target")
        let copySource = CommandBarFolderMoveSource(items: [.tab(source)], spaceID: store.activeSpaceID,
            profileID: store.activeSpace.profileID, state: store.state)!
        let move = CommandBarFolderMove.snapshot(source: copySource, state: store.state).first { $0.folder.folderID == folder }!
        let copyResult = try store.copyCommandBarItemsToFolder(move, destinations: [source: "https://copy-source.example"],
            creation: copyReceipt)!
        expect(copyResult.tabs.allSatisfy { $0.referrerID == nil && $0.activeTabBeforeCreationID == original },
            "Contextual copy uses fresh origin receipt for every original root")
        let freshTarget = SidebarDuplicateTarget(items: [.tab(source)], spaceID: store.activeSpaceID,
            profileID: store.activeSpace.profileID, state: store.state)!
        let ownerless = try store.duplicateSidebarItems(freshTarget, destinations: [source: "https://copy-source.example"])!
        expect(ownerless.tabIDs.allSatisfy { id in store.state.tabs.contains { $0.id == id
            && $0.referrerID == nil && $0.activeTabBeforeCreationID == nil } }, "A caller without a window cannot invent copied provenance")

        //
        // top placement of a created page routed outside the current Space.
        let placementDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: placementDirectory) }
        let placing = try BrowserStore(directory: placementDirectory)
        let placingProfile = placing.activeSpace.profileID, placingSpace = placing.activeSpaceID
        let todayList = SidebarContainerLocation(spaceID: placingSpace, folderID: nil, section: .today)
        func today(_ state: BrowserState? = nil) -> [SidebarItemReference] {
            SidebarHierarchy.children(in: todayList, state: state ?? placing.state)
        }
        func creationFrom(_ referrer: UUID?) -> TabCreationProvenance {
            TabCreationProvenance(referrerID: referrer, activeTabID: placing.state.selectedTabIDs.first,
                profileID: placingProfile, state: placing.state)
        }
        func linked(_ id: UUID, referrer: UUID, spaceID: UUID? = nil) -> BrowserTab {
            BrowserTab(id: id, spaceID: spaceID ?? placingSpace, profileID: placingProfile,
                url: "https://linked.example/", title: "Linked", kind: .today, createdAt: Date(), lastAccessed: Date(),
                savedURL: "https://linked.example/", savedTitle: "Linked", referrerID: referrer, activeTabBeforeCreationID: referrer)
        }
        let olderTab = placing.open("https://older.example")
        let newerTab = placing.open("https://newer.example")
        expect(today() == [.tab(newerTab), .tab(olderTab)], "A tab without a referrer enters at the top of Today")
        let childA = placing.open("https://child-a.example", creation: creationFrom(newerTab))
        let childB = placing.open("https://child-b.example", creation: creationFrom(newerTab))
        expect(today() == [.tab(newerTab), .tab(childA), .tab(childB), .tab(olderTab)],
               "Linked tabs follow their referrer and its earlier opened run in creation order")
        let grandchild = placing.open("https://grandchild.example", creation: creationFrom(childA))
        expect(today() == [.tab(newerTab), .tab(childA), .tab(grandchild), .tab(childB), .tab(olderTab)],
               "A different referrer's run does not absorb the new tab")
        let pinnedSource = placing.open("https://pinned-source.example", kind: .pinned)
        expect(!today().contains(.tab(pinnedSource)), "Pinned creation keeps its saved section")
        let fromPinnedA = placing.open("https://from-pinned-a.example", creation: creationFrom(pinnedSource))
        let fromPinnedB = placing.open("https://from-pinned-b.example", creation: creationFrom(pinnedSource))
        expect(Array(today().prefix(3)) == [.tab(fromPinnedA), .tab(fromPinnedB), .tab(newerTab)],
               "A pinned referrer starts the scan at the top of Today, after its earlier children")
        var spaced = placing.state
        let elsewhere = BrowserSpace(id: UUID(), name: "Elsewhere", symbol: "circle", color: "123456", profileID: placingProfile)
        spaced.spaces.append(elsewhere)
        let otherTab = UUID(), foreignSpaceChild = UUID()
        spaced.tabs.append(linked(otherTab, referrer: newerTab, spaceID: elsewhere.id))
        spaced.tabs.append(linked(foreignSpaceChild, referrer: otherTab))
        SidebarHierarchy.placingCreatedTab(foreignSpaceChild, insertion: .automatic, in: &spaced)
        expect(today(spaced).first == .tab(foreignSpaceChild),
               "A referrer outside this Today list does not move the tab below unrelated items")
        // A referrer inside a split starts at that whole item; another split
        // ends a run because it is not a tab opened from the same referrer.
        let splitLayout = BrowserSplitLayout(sidebarAnchorID: childB, spaceID: placingSpace, tabIDs: [childB, olderTab],
            orientation: .vertical, widthFactors: [0.5, 0.5])
        spaced.splitLayouts = [splitLayout]
        let fromSplit = UUID(), beforeSplit = UUID()
        spaced.tabs.append(linked(fromSplit, referrer: olderTab))
        SidebarHierarchy.placingCreatedTab(fromSplit, insertion: .automatic, in: &spaced)
        expect(today(spaced).firstIndex(of: .tab(fromSplit)) == today(spaced).firstIndex(of: .split(splitLayout.id)).map { $0 + 1 },
               "A split pane referrer places the tab after its whole split item")
        spaced.tabs.append(linked(beforeSplit, referrer: grandchild))
        SidebarHierarchy.placingCreatedTab(beforeSplit, insertion: .automatic, in: &spaced)
        expect(today(spaced).firstIndex(of: .tab(beforeSplit)) == today(spaced).firstIndex(of: .tab(grandchild)).map { $0 + 1 },
               "The scan stops at the first item not opened from the referrer")
        let enginePath = placing.independentEngineProfilePath(for: placingProfile)
        let selectionBeforeAdoption = placing.state.selectedTabIDs
        let routedTop = placing.adoptNativePage(url: URL(string: "https://routed.example"), title: "Routed",
            profilePath: enginePath, preferredSpaceID: placingSpace, select: false,
            creation: creationFrom(newerTab), insertion: .top)!
        expect(today().first == .tab(routedTop) && placing.state.tabs.first { $0.id == routedTop }?.referrerID == newerTab,
               "Explicit top placement keeps provenance but ignores the referrer run")
        let adopted = placing.adoptNativePage(url: URL(string: "https://adopted.example"), title: "Adopted",
            profilePath: enginePath, preferredSpaceID: placingSpace, select: false, creation: creationFrom(childB))!
        expect(today().firstIndex(of: .tab(adopted)) == today().firstIndex(of: .tab(childB)).map { $0 + 1 },
               "Native background adoption uses the same referrer placement")
        expect(placing.state.selectedTabIDs == selectionBeforeAdoption, "Background placement does not change selection")
        // A modal (Peek) source supplies its parent as referrer. Closing the
        // linked tab returns through that receipt, not its placed neighbour.
        var placingWindow = WindowPresentation(state: placing.state, ready: true)
        placing.selectTab(childA)
        let fromModal = placing.open("https://from-modal.example", creation: creationFrom(pinnedSource))
        placingWindow.recordCreation(fromModal, state: placing.state)
        expect(placingWindow.referrerPool == [pinnedSource, fromModal], "Modal-source creation joins the window's chain")
        let returnDecision = FolderRemovalSelection.resolve(removing: [fromModal], spaceID: placingSpace,
            profileID: placingProfile, state: placing.state, selected: [fromModal], focused: fromModal,
            referrerPool: placingWindow.referrerPool, available: { _ in true })
        expect(returnDecision?.tabIDs == [pinnedSource], "Closing the linked tab returns to its source, not its Today neighbour")
        // A cross-Profile route enters this Profile's Space at the top with no
        // receipt, so this window's current item gains no creation return.
        placing.selectTab(childA)
        let destinationCurrent = childA
        let crossProfile = placing.adoptNativePage(url: URL(string: "https://cross-profile.example"), title: "Routed",
            profilePath: enginePath, preferredSpaceID: placingSpace, select: false,
            creation: TabCreationProvenance(routedFrom: nil, openedLink: true, profileID: placingProfile,
                state: placing.state), insertion: .top)!
        let crossTab = placing.state.tabs.first { $0.id == crossProfile }!
        expect(today().first == .tab(crossProfile) && crossTab.referrerID == nil && crossTab.activeTabBeforeCreationID == nil,
               "A cross-Profile routed page takes the top without either identity")
        var destination = WindowPresentation(state: placing.state, ready: true)
        destination.recordSelectionForReturn(destinationCurrent, state: placing.state)
        destination.recordCreation(crossProfile, state: placing.state)
        destination.recordSelectionForReturn(crossProfile, state: placing.state)
        expect(destination.referrerPool.isEmpty, "Selecting the unsourced routed page leaves no creation chain")
        let crossReturn = FolderRemovalSelection.resolve(removing: [crossProfile], spaceID: placingSpace,
            profileID: placingProfile, state: placing.state, selected: [crossProfile], focused: crossProfile,
            referrerPool: destination.referrerPool, available: { _ in true })
        expect(crossReturn?.tabIDs == [pinnedSource] && crossReturn?.tabIDs != [destinationCurrent],
               "Without a remembered item, closing it reaches its neighbour, not the destination's prior current item")
        // A same-Profile matched link also takes the top and records its
        // source only as active-before, so it does not join the source's run.
        let openedLink = placing.adoptNativePage(url: URL(string: "https://opened-link.example"), title: "Linked",
            profilePath: enginePath, preferredSpaceID: placingSpace, select: false,
            creation: TabCreationProvenance(routedFrom: fromPinnedA, openedLink: true, profileID: placingProfile,
                state: placing.state), insertion: .top)!
        let openedTab = placing.state.tabs.first { $0.id == openedLink }!
        expect(today().first == .tab(openedLink) && openedTab.referrerID == nil
                && openedTab.activeTabBeforeCreationID == fromPinnedA,
               "A matched link takes the top and records only its active-before source")
        try placing.save()
        let reloadedPlacement = try BrowserStore(directory: placementDirectory)
        expect(today(reloadedPlacement.state) == today(), "Creation placement is part of the durable Today order")
        print("Tab creation provenance: \(count) assertions passed")
    }
}
