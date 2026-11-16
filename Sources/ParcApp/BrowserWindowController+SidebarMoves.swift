import AppKit
import Combine

extension BrowserWindowController {
    func moveFavoriteToPinned(_ id: UUID) -> Bool {
        let group = SidebarSplitItems.groups(in: store.state, spaceID: activeSpaceID).first { $0.tabIDs.contains(id) }
        let item = group.map { SidebarItemReference.split($0.id) } ?? .tab(id)
        return prepareSidebarMove(item)?.move(to: .init(spaceID: activeSpaceID, folderID: nil, section: .pinned), before: nil) == true
    }
    func prepareSeparateSplitTab(_ id: UUID) -> (() -> Bool)? {
        guard let group = SidebarSplitItems.groups(in: store.state, spaceID: activeSpaceID).first(where: { $0.tabIDs.contains(id) }) else { return nil }
        return prepareSplitSeparation(group) { [weak self] focus in
            self?.separateSplitTab(id, group: group, originalFocus: focus) ?? false
        }
    }

    func prepareSplitCellCommand(_ id: UUID, _ command: SplitCellMenuCommand) -> (() -> Bool)? {
        switch command {
        case .separateAll:
            guard let group = SidebarSplitItems.groups(in: store.state, spaceID: activeSpaceID).first(where: { $0.id == id }) else { return nil }
            return prepareSplitSeparation(group) { [weak self] focus in
                self?.separateAllSplitTabs(group, originalFocus: focus) ?? false
            }
        case .addTab:
            guard splitInsertion == nil, let target = splitCommandTarget(.addNew) else { return nil }
            return { guard target.isAvailable else { return false }; target.perform(); return true }
        case .convertOrientation:
            return prepareSplitOrientationFlip(id)
        case .newFolder:
            return prepareFolderFromItems([.split(id)])
        }
    }

    func prepareFolderFromItems(_ items: [SidebarItemReference]) -> (() -> Bool)? {
        guard !isPrivateBrowsing, folderUndoContextAvailable, !folderUndo.isBusy, let window,
              let lease = prepareSidebarMoves(items),
              let expected = SidebarHierarchySnapshot(state: store.state, spaceID: activeSpaceID,
                  profileID: activeProfileID, includesFavorites: true) else { return nil }
        var consumed = false
        return { [weak self, weak window] in
            guard !consumed, let self, let window, self.window === window, lease.isValid,
                  !self.folderUndo.isBusy else { return false }
            consumed = true; lease.end()
            do {
                guard let receipt = try self.store.createFolder(containing: items, folderID: UUID(), expected: expected) else { return false }
                self.registerFolderCreationUndo(receipt)
                self.render(self.store.state)
                self.sidebar.scrollItemToVisible(.folder(receipt.folderID))
                let spaceID = receipt.spaceID
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self, weak window] in
                    guard let self, let window, self.window === window, window.isKeyWindow, window.attachedSheet == nil,
                          self.activeSpaceID == spaceID,
                          self.store.state.folders.contains(where: { $0.id == receipt.folderID }) else { return }
                    if !self.sidebar.beginFolderTitleEditing(receipt.folderID, untitled: true) { self.renameFolder(receipt.folderID) }
                }
                return true
            } catch {
                showError(error); return false
            }
        }
    }

    private func registerFolderCreationUndo(_ receipt: SidebarFolderFromItems) {
        var receipt = receipt
        _ = folderUndo.append(.init(name: SidebarFolderFromItems.undoName, isValid: { [weak self] direction in
            guard let self else { return false }
            return receipt.reverting(self.store.state, undo: direction == .undo) != nil
        }, isAvailable: { [weak self] _ in
            guard let self else { return false }
            return self.folderUndoContextAvailable && self.activeSpaceID == receipt.spaceID
                && self.activeProfileID == receipt.profileID
        }, perform: { [weak self] direction, done in
            guard let self else { done(false); return }
            do {
                let updated = try self.store.revertFolderCreation(receipt, undo: direction == .undo)
                if let updated { receipt = updated }
                done(updated != nil); self.render(self.store.state)
            }
            catch { showError(error); done(false) }
        }))
    }

    private func prepareSplitOrientationFlip(_ id: UUID) -> (() -> Bool)? {
        guard splitCommandsAvailable, let window,
              let group = SidebarSplitItems.groups(in: store.state, spaceID: activeSpaceID).first(where: { $0.id == id }),
              group.tabIDs.allSatisfy({ !store.retiringTabIDs.contains($0) }) else { return nil }
        let spaceID = activeSpaceID, profileID = activeProfileID
        var consumed = false
        return { [weak self, weak window] in
            guard !consumed, let self, let window, self.window === window, self.splitCommandsAvailable,
                  self.activeSpaceID == spaceID, self.activeProfileID == profileID,
                  self.store.state.splitLayouts.contains(group) else { return false }
            consumed = true
            var committed = false
            self.performWindowCommand(selectNativePage: false) {
                committed = self.store.flipSplitOrientation(expected: group)
            }
            return committed
        }
    }

    private func prepareSplitSeparation(_ group: BrowserSplitLayout, perform: @escaping (UUID?) -> Bool) -> (() -> Bool)? {
        guard splitCommandsAvailable, let window,
              group.tabIDs.allSatisfy({ switcherCanUse($0) }) else { return nil }
        let spaceID = activeSpaceID, profileID = activeProfileID
        let selection = selectedTabIDs, focus = currentTabID
        let ids = group.tabIDs
        let claims = Dictionary(uniqueKeysWithValues: ids.map { ($0, ownership.claimSnapshot($0)) })
        let wrappers = Dictionary(uniqueKeysWithValues: ids.compactMap { id in browsers[id].map { (id, ObjectIdentifier($0)) } })
        let pages = Dictionary(uniqueKeysWithValues: ids.compactMap { id in browsers[id]?.nativePage.map { (id, ObjectIdentifier($0)) } })
        let notes = Dictionary(uniqueKeysWithValues: ids.compactMap { id in noteEditors[id].map { (id, ObjectIdentifier($0.editor)) } })
        let easels = Dictionary(uniqueKeysWithValues: ids.compactMap { id in easelEditors[id].map { (id, ObjectIdentifier($0.editor)) } })
        var consumed = false
        return { [weak self, weak window] in
            guard !consumed, let self, let window, self.window === window,
                  self.splitCommandsAvailable, self.activeSpaceID == spaceID,
                  self.activeProfileID == profileID, self.selectedTabIDs == selection, self.currentTabID == focus,
                  self.store.state.splitLayouts.contains(group),
                  PCNativeBrowserApplication.canPresentTabSwitcher(in: window),
                  ids.allSatisfy({ self.switcherCanUse($0) && self.ownership.claimSnapshot($0) == claims[$0] }),
                  Dictionary(uniqueKeysWithValues: ids.compactMap { id in self.browsers[id].map { (id, ObjectIdentifier($0)) } }) == wrappers,
                  Dictionary(uniqueKeysWithValues: ids.compactMap { id in self.browsers[id]?.nativePage.map { (id, ObjectIdentifier($0)) } }) == pages,
                  Dictionary(uniqueKeysWithValues: ids.compactMap { id in self.noteEditors[id].map { (id, ObjectIdentifier($0.editor)) } }) == notes,
                  Dictionary(uniqueKeysWithValues: ids.compactMap { id in self.easelEditors[id].map { (id, ObjectIdentifier($0.editor)) } }) == easels else { return false }
            consumed = true
            return perform(focus)
        }
    }

    func presentationSetMediaRemoval(
        capturing candidates: [UUID],
        remaining: @escaping () -> Set<UUID>,
        gate: (() -> Bool)? = nil
    ) -> (() -> Void)? {
        guard let window, let binding = nativeBinding, !candidates.isEmpty else { return nil }
        let originals = Array(Set(candidates)).compactMap { id -> (UUID, PCBrowserView, PCNativePage, NSObject, UUID)? in
            guard let view = browsers[id], view.window === window,
                  let page = view.nativePage, !page.isClosed,
                  attachedPageIDs.contains(page.identifier),
                  PCNativeBrowserApplication.owner(of: page) === binding,
                  let sourceProfile = browserProfiles[id],
                  liveTabModels[id]?.profileID == sourceProfile,
                  page.responds(to: #selector(PCNativePage.captureMediaPresentationLease)),
                  page.responds(to: #selector(PCNativePage.mediaPresentationDidRemove(_:))),
                  let lease = page.captureMediaPresentationLease() else { return nil }
            return (id, view, page, lease, sourceProfile)
        }
        guard !originals.isEmpty else { return nil }
        let claims = Dictionary(uniqueKeysWithValues: originals.map { ($0.0, ownership.claimSnapshot($0.0)) })
        return { [weak self, weak window, weak binding] in
            guard let self, let window, let binding else { return }
            let isCurrent = {
                self.window === window && self.nativeBinding === binding && (gate?() ?? true)
            }
            guard isCurrent() else { return }
            let kept = remaining()
            for (id, view, page, lease, sourceProfile) in originals where !kept.contains(id) {
                guard isCurrent() else { return }
                guard self.ownership.claimSnapshot(id) == claims[id],
                      self.browsers[id] === view, view.nativePage === page, view.window === window,
                      self.attachedPageIDs.contains(page.identifier),
                      !page.isClosed, self.browserProfiles[id] == sourceProfile,
                      self.liveTabModels[id]?.profileID == sourceProfile,
                      PCNativeBrowserApplication.owner(of: page) === binding else { continue }
                page.mediaPresentationDidRemove(lease)
            }
        }
    }

    private func splitMediaRemoval(_ group: BrowserSplitLayout, expectedSelection: [UUID]) -> (() -> Void)? {
        guard splitCommandsAvailable, nativeFullscreenTabID == nil,
              selectedTabIDs == group.tabIDs, renderedPaneIDs == group.tabIDs,
              let window, let binding = nativeBinding else { return nil }
        let space = activeSpaceID, profile = activeProfileID
        let originals = group.tabIDs.compactMap { id -> (UUID, PCBrowserView, PCNativePage, NSObject, UUID, BrowserPane)? in
            guard switcherCanUse(id), let view = browsers[id], view.window === window,
                  let pane = panes[id], pane.superview === splitView, !pane.isHiddenOrHasHiddenAncestor,
                  let page = view.nativePage, !page.isClosed, attachedPageIDs.contains(page.identifier),
                  PCNativeBrowserApplication.owner(of: page) === binding,
                  let sourceProfile = browserProfiles[id], liveTabModels[id]?.profileID == sourceProfile,
                  page.responds(to: #selector(PCNativePage.captureMediaPresentationLease)),
                  page.responds(to: #selector(PCNativePage.mediaPresentationDidRemove(_:))),
                  let lease = page.captureMediaPresentationLease() else { return nil }
            return (id, view, page, lease, sourceProfile, pane)
        }
        let claims = Dictionary(uniqueKeysWithValues: group.tabIDs.map { ($0, ownership.claimSnapshot($0)) })
        return { [weak self, weak window, weak binding] in
            guard let self, let window, let binding else { return }
            let isCurrent = {
                self.window === window && self.nativeBinding === binding && self.splitCommandsAvailable
                    && self.nativeFullscreenTabID == nil && self.activeSpaceID == space
                    && self.activeProfileID == profile && self.renderedPaneIDs == group.tabIDs
                    && self.selectedTabIDs == expectedSelection && self.store.state.selectedTabIDs == expectedSelection
            }
            guard isCurrent() else { return }
            let remaining = Set(expectedSelection)
            for (id, view, page, lease, sourceProfile, originalPane) in originals where !remaining.contains(id) {
                guard isCurrent() else { return }
                guard self.switcherCanUse(id), self.ownership.claimSnapshot(id) == claims[id],
                      self.browsers[id] === view, view.nativePage === page, view.window === window,
                      let pane = self.panes[id], pane === originalPane,
                      pane.superview === self.splitView, !pane.isHiddenOrHasHiddenAncestor,
                      self.attachedPageIDs.contains(page.identifier),
                      !page.isClosed, self.browserProfiles[id] == sourceProfile,
                      self.liveTabModels[id]?.profileID == sourceProfile,
                      PCNativeBrowserApplication.owner(of: page) === binding else { continue }
                page.mediaPresentationDidRemove(lease)
            }
        }
    }

    @discardableResult
    private func separateAllSplitTabs(_ group: BrowserSplitLayout, originalFocus: UUID?) -> Bool {
        var committed = false
        let kept = originalFocus.flatMap { group.tabIDs.contains($0) ? $0 : nil } ?? group.tabIDs.first
        let removal = kept.flatMap { splitMediaRemoval(group, expectedSelection: [$0]) }
        performWindowCommand(selectNativePage: false, afterCapture: { if committed { removal?() } }) {
            committed = store.separateAllTabsFromSplit(expected: group, focusedID: originalFocus)
        }
        guard committed else { return false }
        requestNativeSelection()
        reclaimFocusAfterSplitPresentation()
        return true
    }

    @discardableResult
    func separateSplitTab(_ id: UUID, group: BrowserSplitLayout, originalFocus: UUID?) -> Bool {
        var committed = false
        let expected = originalFocus == id ? [id] : group.tabIDs.filter { $0 != id }
        let removal = splitMediaRemoval(group, expectedSelection: expected)
        performWindowCommand(selectNativePage: false, afterCapture: { if committed { removal?() } }) {
            committed = store.separateTabFromSplit(id, expected: group, focusedID: originalFocus)
        }
        guard committed else { return false }
        requestNativeSelection()
        reclaimFocusAfterSplitPresentation()
        return true
    }

    func prepareSidebarMove(_ item: SidebarItemReference) -> SidebarMoveSession? {
        prepareSidebarMoves([item])
    }

    func prepareSidebarMoves(_ items: [SidebarItemReference]) -> SidebarMoveSession? {
        guard spaceCommandsAvailable, commandBar == nil, let window,
              var expected = SidebarHierarchySnapshot(state: store.state, spaceID: activeSpaceID, profileID: activeProfileID, includesFavorites: true),
              let collection = SidebarMoveCollection(items: items, spaceID: activeSpaceID, profileID: activeProfileID, state: store.state) else { return nil }
        func undisclosed(_ state: BrowserState) -> SidebarHierarchySnapshot? {
            var state = state
            for index in state.folders.indices { state.folders[index].isExpanded = false }
            return SidebarHierarchySnapshot(state: state, spaceID: expected.spaceID, profileID: expected.profileID, includesFavorites: true)
        }
        let structure = undisclosed(store.state)
        let ids = collection.tabIDs
        guard ids.allSatisfy({ switcherCanUse($0) }) else { return nil }
        let selection = selectedTabIDs, focus = focusedTabID
        let owners = Dictionary(uniqueKeysWithValues: ids.map { id in
            (id, SplitPaneIdentity(pane: panes[id].map(ObjectIdentifier.init) ?? ObjectIdentifier(self),
                                  browser: browsers[id].map(ObjectIdentifier.init), page: browsers[id]?.nativePage?.identifier))
        })
        let valid: () -> Bool = { [weak self, weak window] in
            guard let self, let window, self.window === window, self.sidebarWindowMoveAvailable,
                  self.commandBar == nil, self.activeSpaceID == expected.spaceID,
                  self.activeProfileID == expected.profileID,
                  self.selectedTabIDs == selection, self.focusedTabID == focus,
                  let current = SidebarHierarchySnapshot(state: self.store.state, spaceID: expected.spaceID, profileID: expected.profileID, includesFavorites: true) else { return false }
            if current != expected {
                guard structure != nil, undisclosed(self.store.state) == structure else { return false }
                expected = current
            }
            return ids.allSatisfy { id in
                guard self.switcherCanUse(id), self.browsers[id]?.nativePage?.isClosed != true else { return false }
                let actual = SplitPaneIdentity(pane: self.panes[id].map(ObjectIdentifier.init) ?? ObjectIdentifier(self),
                    browser: self.browsers[id].map(ObjectIdentifier.init), page: self.browsers[id]?.nativePage?.identifier)
                return owners[id] == actual
            }
        }
        let wholeSplits = items.allSatisfy { if case .split = $0 { return true } else { return false } }
        let session = SidebarMoveSession(items: items, window: window,
            validate: { [weak self] in self?.spaceCommandsAvailable == true && valid() },
            validateTransfer: valid, allowsCopy: wholeSplits || folderDuplicateContextAvailable, propose: { [weak self] location, before in
                guard valid(), let self, self.spaceCommandsAvailable else { return false }
                return SidebarHierarchy.moving(items, to: location, before: before, expected: expected, state: self.store.state) != nil
            }, commit: { [weak self] location, before in
                guard valid(), let self, self.spaceCommandsAvailable else { return false }
                do {
                    return try self.store.moveSidebarItems(items, to: location, before: before, expected: expected)
                } catch {
                    showError(error)
                    return false
                }
            })
        session.owner = self
        return session
    }

    var sidebarWindowMoveAvailable: Bool {
        sidebarWindowMoveEnvironment && collectionTransfer == nil && transferringTabIDs.isEmpty
    }

    var sidebarWindowMoveEnvironment: Bool {
        !isPopupWindow && !isPrivateBrowsing && !store.isEphemeral && presentation.isReady
            && !isClosing && !wholeWindowClose && !windowClosePending && !windowCloseApproved
            && nativeFullscreenTabID == nil && activePeek == nil && commandBar == nil
            && tabSwitcher == nil && themePopover == nil && !siteControlCenterDefers
            && closingTabIDs.isEmpty && modelRetirementIDs.isEmpty && peekRetirementParents.isEmpty
            && resolvingTransfers.isEmpty && !store.isProfileRemovalPending(activeProfileID)
            && nativeBinding?.canParticipateInPageTransfer == true
    }

    func prepareSidebarWindowDrop(_ session: SidebarMoveSession, to location: SidebarContainerLocation,
                                          before: SidebarItemReference?) -> (() -> Bool)? {
        if let source = session.owner, source !== self, source.activeProfileID != activeProfileID {
            return prepareInterProfileWindowDrop(session, from: source, to: location, before: before)
        }
        guard session.isValidForWindowTransfer, let source = session.owner, source !== self,
              source.store === store, source.ownership === ownership,
              source.window === session.window, source.sidebarWindowMoveAvailable, sidebarWindowMoveAvailable,
              source.activeProfileID == activeProfileID, location.spaceID == activeSpaceID,
              let move = SidebarWindowMove(items: session.items, sourceSpaceID: source.activeSpaceID,
                  profileID: activeProfileID, to: location, before: before, state: store.state),
              let transaction = SidebarWindowTransfer(source: source, destination: self, move: move) else { return nil }
        return { transaction.begin() }
    }

    private func prepareInterProfileWindowDrop(_ session: SidebarMoveSession, from source: BrowserWindowController,
                                               to location: SidebarContainerLocation,
                                               before: SidebarItemReference?) -> (() -> Bool)? {
        guard session.isValidForWindowTransfer, source.store === store, source.ownership === ownership,
              source.window === session.window, source.sidebarWindowMoveAvailable, sidebarWindowMoveAvailable,
              location.spaceID == activeSpaceID,
              let move = SidebarWindowMove(items: session.items, sourceSpaceID: source.activeSpaceID,
                  profileID: source.activeProfileID, destinationProfileID: activeProfileID,
                  to: location, before: before, state: store.state), move.crossesProfiles,
              Set(move.tabIDs).isDisjoint(with: store.retiringTabIDs) else { return nil }
        let selection = selectedTabIDs, spaceID = activeSpaceID, profileID = activeProfileID
        let placement: (BrowserState) -> BrowserState? = { state in
            guard SidebarHierarchySnapshot(state: state, spaceID: move.source.spaceID, profileID: move.source.profileID,
                                           includesFavorites: true) == move.source,
                  SidebarHierarchySnapshot(state: state, spaceID: move.destination.spaceID,
                                           profileID: move.destination.profileID, includesFavorites: true) == move.destination,
                  let current = SidebarWindowMove(items: move.roots, sourceSpaceID: move.source.spaceID,
                      profileID: move.source.profileID, destinationProfileID: move.destination.profileID,
                      to: move.location, before: move.before, state: state),
                  current.tabIDs == move.tabIDs else { return nil }
            return current.applying(to: state)
        }
        return { [weak self, weak source] in
            guard let self, let source, session.isValidForWindowTransfer,
                  source.sidebarWindowMoveAvailable, self.sidebarWindowMoveAvailable,
                  self.activeSpaceID == spaceID, self.activeProfileID == profileID,
                  placement(self.store.state) != nil else { return false }
            return self.confirmInterProfileMove(tabCount: move.tabIDs.count,
                                                sourceProfiles: move.tabIDs.isEmpty ? [] : [move.source.profileID],
                                                destinationSpaceID: spaceID, moving: Set(move.tabIDs), proposal: placement) { [weak self] in
                guard let self, self.activeSpaceID == spaceID, self.activeProfileID == profileID else { return }
                let moved = Set(move.tabIDs)
                self.store.moveAcrossProfiles(moved, proposal: placement) { [weak self] result in
                    guard let self else { return }
                    switch result {
                    case .success(true):
                        self.onInterProfileMoveCommitted?(moved)
                        if selection.isEmpty, self.selectedTabIDs.isEmpty, let first = move.tabIDs.first {
                            self.finishInterProfileArrival(first)
                        } else { self.render(self.store.state) }
                    case .success(false): self.explainRefusedInterProfileMove(moved, proposal: placement)
                    case .failure(let error): showError(error)
                    }
                }
            }
        }
    }

    func prepareSidebarCopyDrop(_ session: SidebarMoveSession, items: [SidebarItemReference],
                                        to location: SidebarContainerLocation, before: SidebarItemReference?) -> (() -> Bool)? {
        let key = ([session.identifier.uuidString, location.key, before.map { "\($0)" } ?? ""] + items.map { "\($0)" })
            .joined(separator: "|")
        if let cached = copyDropCache, cached.key == key, cached.revision == store.stateRevision { return cached.action }
        let action = makeSidebarCopyDrop(session, items: items, to: location, before: before)
        copyDropCache = (key, store.stateRevision, action)
        return action
    }

    private func makeSidebarCopyDrop(_ session: SidebarMoveSession, items: [SidebarItemReference],
                                     to location: SidebarContainerLocation, before: SidebarItemReference?) -> (() -> Bool)? {
        guard session.allowsCopy, session.isValidForWindowTransfer, let window,
              let source = session.owner, source.store === store, source.window === session.window,
              folderDuplicateContextAvailable, source.folderDuplicateContextAvailable,
              sidebarWindowMoveEnvironment, source.sidebarWindowMoveEnvironment,
              let destinationProfile = store.state.spaces.first(where: { $0.id == location.spaceID })?.profileID,
              location.profileID == nil || location.profileID == destinationProfile,
              destinationProfile == source.activeProfileID
                || InterProfileMove.profilesAvailable(source.activeProfileID, destinationProfile, in: store.state),
              let copy = SidebarItemsCopy(items: items, spaceID: source.activeSpaceID,
                  profileID: source.activeProfileID, state: store.state),
              copy.wholeSplits || (source === self && destinationProfile == source.activeProfileID) else { return nil }
        let sourceProfile = source.activeProfileID, spaceID = activeSpaceID, profileID = activeProfileID
        let focus = source.focusedTabID
        let lastSplit = copy.roots.last.flatMap { root -> BrowserSplitLayout? in
            guard copy.wholeSplits, case .split(let id) = root else { return nil }
            return copy.groups.first { $0.id == id }
        }
        let focusIndex = lastSplit.flatMap { group in focus.flatMap { group.tabIDs.firstIndex(of: $0) } } ?? 0
        let current: () -> (copy: SidebarItemsCopy, sources: SidebarCopySources)? = { [weak self] in
            guard let self, self.folderDuplicateContextAvailable,
                  let now = SidebarItemsCopy(items: copy.roots, spaceID: copy.source.spaceID,
                      profileID: copy.source.profileID, state: self.store.state), now.matchesPlacement(of: copy),
                  let resolved = self.resolveSidebarCopyDestinations?(now.tabs), resolved.validates(now.tabs) else { return nil }
            return (now, resolved)
        }
        guard let proposed = current(),
              store.canCopySidebarItems(proposed.copy, to: location, before: before,
                  destinations: proposed.sources.destinations, documents: proposed.sources.documents) else { return nil }
        let sourceShown = source.selectedTabIDs.filter { id in copy.tabs.contains { $0.id == id } }
        let sourceFocus = source.focusedTabID.flatMap { sourceShown.contains($0) ? $0 : nil } ?? sourceShown.first
        let sourceSpace = source.activeSpaceID
        let arrive: (SidebarDuplicateResult, SidebarCopySources) -> Void = { [weak self, weak window] result, urls in
            guard let self, let window, self.window === window else { return }
            self.registerSidebarCopyUndo(SidebarCopyUndo.dragCopyName, roots: result.roots, spaceID: location.spaceID,
                profileID: destinationProfile, sources: urls, openTabIDs: result.openTabIDs,
                originatingSpaceID: location.spaceID, window: window)
            if location.spaceID != self.activeSpaceID {
                if !window.isKeyWindow { window.makeKeyAndOrderFront(nil) }
                guard self.selectSpaceFromUser(location.spaceID, profileID: destinationProfile) else { self.render(self.store.state); return }
            }
            guard self.activeSpaceID == location.spaceID, self.activeProfileID == destinationProfile else { self.render(self.store.state); return }
            self.openDuplicatedChildren(result.openTabIDs, spaceID: location.spaceID, profileID: destinationProfile, window: window)
            if copy.wholeSplits, case .split(let id)? = result.roots.last,
               let copied = self.store.state.splitLayouts.first(where: { $0.id == id }), !copied.tabIDs.isEmpty {
                _ = self.selectTab(copied.tabIDs[min(focusIndex, copied.tabIDs.count - 1)])
            } else { self.render(self.store.state) }
        }
        let perform: () -> Bool = { [weak self, weak window, weak source] in
            guard let self, let window, self.window === window, self.sidebarWindowMoveEnvironment,
                  self.activeSpaceID == spaceID, self.activeProfileID == profileID,
                  let resolved = current() else { return false }
            let now = resolved.copy, urls = resolved.sources
            let creation = self.creationProvenance(activeTabID: self.currentTabID)
            guard destinationProfile != sourceProfile else {
                do {
                    guard let result = try self.store.copySidebarItems(now, to: location, before: before,
                        destinations: urls.destinations, documents: urls.documents, creation: creation) else { return false }
                    arrive(result, urls); return true
                } catch {
                    showError(error); return false
                }
            }
            self.store.copySidebarSplitsReloadingOriginals(now, to: location, before: before,
                destinations: urls.destinations, documents: urls.documents, creation: creation) { [weak self] outcome in
                guard let self else { return }
                switch outcome {
                case .success(let result?):
                    if let source, source !== self, source.activeSpaceID == sourceSpace, let shown = sourceFocus {
                        _ = source.selectTab(shown)
                    }
                    arrive(result, urls)
                case .success(nil): NSSound.beep()
                case .failure(let error): showError(error)
                }
            }
            return true
        }
        var consumed = false
        return { [weak self] in
            guard !consumed, let self else { return false }
            consumed = true
            guard destinationProfile != sourceProfile else { return perform() }
            var deciding = true
            var immediate: Bool?
            let began = self.confirmInterProfileMove(tabCount: copy.tabs.count, sourceProfiles: [sourceProfile],
                                                     destinationSpaceID: location.spaceID) {
                let done = perform()
                if deciding { immediate = done } else if !done { NSSound.beep() }
            }
            deciding = false
            return immediate ?? began
        }
    }

    func prepareSidebarDockDrop(_ session: SidebarMoveSession, items: [SidebarItemReference],
                                        to location: SidebarContainerLocation, before: SidebarItemReference?) -> (() -> Bool)? {
        guard !items.isEmpty, session.isValidForWindowTransfer, let window,
              let source = session.owner, source.store === store, source.window === session.window,
              let space = store.state.spaces.first(where: { $0.id == location.spaceID }),
              location.profileID == nil else { return nil }
        let crosses = space.profileID != source.activeProfileID
        guard !crosses || InterProfileMove.profilesAvailable(source.activeProfileID, space.profileID, in: store.state),
              let move = SidebarWindowMove(items: items, sourceSpaceID: source.activeSpaceID, profileID: source.activeProfileID,
                  destinationProfileID: space.profileID, to: location, before: before, state: store.state) else { return nil }
        if source !== self {
            guard items == session.items, sidebarWindowMoveAvailable, source.sidebarWindowMoveAvailable else { return nil }
            return { [weak self, weak window] in
                guard let self, let window, self.window === window else { return false }
                if location.spaceID != self.activeSpaceID {
                    if !window.isKeyWindow { window.makeKeyAndOrderFront(nil) }
                    guard self.selectSpaceFromUser(location.spaceID, profileID: space.profileID) else { return false }
                }
                let top = SidebarHierarchy.children(in: location, state: self.store.state).first { !items.contains($0) }
                guard let begin = self.prepareSidebarWindowDrop(session, to: location, before: top) else { return false }
                return begin()
            }
        }
        guard sidebarWindowMoveAvailable, let validateOwners = prepareSidebarSpaceMoveOwners?(Set(move.tabIDs)) else { return nil }
        let claims = Dictionary(uniqueKeysWithValues: move.tabIDs.map { ($0, ownership.claimSnapshot($0)) })
        let splitChildren = Set(move.collection.roots.flatMap { root -> [UUID] in
            guard case .split(let id) = root else { return [] }
            return move.source.groups.first { $0.id == id }?.tabIDs ?? []
        })
        guard claims.values.allSatisfy({ $0.transfer == nil }),
              splitChildren.allSatisfy({ claims[$0]?.owner == nil || claims[$0]?.owner == presentationID }) else { return nil }
        let selection = selectedTabIDs, focus = focusedTabID, spaceID = activeSpaceID, profileID = activeProfileID
        let current: (BrowserState) -> SidebarWindowMove? = { state in
            guard let now = SidebarWindowMove(items: move.roots, sourceSpaceID: move.source.spaceID, profileID: move.source.profileID,
                      destinationProfileID: move.destination.profileID, to: move.location, before: move.before, state: state),
                  now.tabIDs == move.tabIDs else { return nil }
            return now
        }
        let arrive: () -> Void = { [weak self, weak window] in
            guard let self, let window else { return }
            self.render(self.store.state); self.requestNativeSelection()
            guard location.spaceID != self.activeSpaceID else { return }
            if !window.isKeyWindow { window.makeKeyAndOrderFront(nil) }
            _ = self.selectSpaceFromUser(location.spaceID, profileID: space.profileID)
        }
        return { [weak self] in
            guard let self, self.sidebarWindowMoveAvailable, self.activeSpaceID == spaceID, self.activeProfileID == profileID,
                  self.selectedTabIDs == selection, self.focusedTabID == focus, validateOwners(),
                  move.tabIDs.allSatisfy({ self.ownership.claimSnapshot($0) == claims[$0] }),
                  let now = current(self.store.state) else { return false }
            guard crosses else {
                do {
                    guard try self.store.commitSidebarWindowMove(now) else { return false }
                    arrive(); return true
                } catch {
                    showError(error); return false
                }
            }
            return self.confirmInterProfileMove(tabCount: move.tabIDs.count,
                                                sourceProfiles: move.tabIDs.isEmpty ? [] : [profileID],
                                                destinationSpaceID: location.spaceID, moving: Set(move.tabIDs),
                                                proposal: { current($0)?.applying(to: $0) }) { [weak self] in
                guard let self else { return }
                let moved = Set(move.tabIDs)
                self.store.moveAcrossProfiles(moved, proposal: { current($0)?.applying(to: $0) }) { [weak self] result in
                    guard let self else { return }
                    switch result {
                    case .success(true): self.onInterProfileMoveCommitted?(moved); arrive()
                    case .success(false): self.explainRefusedInterProfileMove(moved) { current($0)?.applying(to: $0) }
                    case .failure(let error): showError(error)
                    }
                }
            }
        }
    }

    func prepareSidebarSpaceRelocationOwnership(_ ids: Set<UUID>) -> (() -> Bool)? {
        guard ids.contains(where: { ownership.claimSnapshot($0).owner == presentationID || browsers[$0] != nil || easelEditors[$0] != nil || noteEditors[$0] != nil }) else { return { true } }
        guard !store.isEphemeral, !isPrivateBrowsing, !isClosing, !wholeWindowClose,
              !windowClosePending, !windowCloseApproved, let window, window.attachedSheet == nil,
              transferringTabIDs.isDisjoint(with: ids), resolvingTransfers.isDisjoint(with: ids),
              Set(transferRecoveries.keys).isDisjoint(with: ids), closingTabIDs.isDisjoint(with: ids),
              !hasPendingNativePage(in: ids), nativeFullscreenTabID.map({ !ids.contains($0) }) ?? true,
              peekPagesForRelocation(ids).isEmpty else { return nil }
        let wrappers = ids.compactMap { id -> (UUID, PCBrowserView, PCNativePage?)? in
            browsers[id].map { (id, $0, $0.nativePage) }
        }
        let embedded = ids.flatMap { embeddedEaselPages(forTabID: $0) }
        let editors = Dictionary(uniqueKeysWithValues: ids.compactMap { id in easelEditors[id].map { (id, ObjectIdentifier($0.editor)) } })
        let notes = Dictionary(uniqueKeysWithValues: ids.compactMap { id in noteEditors[id].map { (id, ObjectIdentifier($0.editor)) } })
        let valid: () -> Bool = { [weak self, weak window] in
            guard let self, let window, self.window === window,
                  !self.isClosing, !self.wholeWindowClose, !self.windowClosePending, !self.windowCloseApproved,
                  window.attachedSheet == nil, !self.hasPendingNativePage(in: ids),
                  self.transferringTabIDs.isDisjoint(with: ids), self.resolvingTransfers.isDisjoint(with: ids),
                  Set(self.transferRecoveries.keys).isDisjoint(with: ids), self.closingTabIDs.isDisjoint(with: ids),
                  self.nativeFullscreenTabID.map({ !ids.contains($0) }) ?? true,
                  self.peekPagesForRelocation(ids).isEmpty,
                  ids.compactMap({ self.browsers[$0] }).count == wrappers.count,
                  Dictionary(uniqueKeysWithValues: ids.compactMap { id in self.easelEditors[id].map { (id, ObjectIdentifier($0.editor)) } }) == editors,
                  Dictionary(uniqueKeysWithValues: ids.compactMap { id in self.noteEditors[id].map { (id, ObjectIdentifier($0.editor)) } }) == notes,
                  Set(ids.flatMap { self.embeddedEaselPages(forTabID: $0) }.map(ObjectIdentifier.init)) == Set(embedded.map(ObjectIdentifier.init)) else { return false }
            for (id, browser, page) in wrappers {
                guard self.browsers[id] === browser, browser.nativePage === page else { return false }
                if let page {
                    guard !page.isClosed, PCNativeBrowserApplication.owner(of: page) === self.nativeBinding,
                          browser.window === window, let tab = self.store.state.tab(id),
                          tab.profileID == self.browserProfiles[id],
                          page.profilePath == self.store.independentEngineProfilePath(for: tab.profileID) else { return false }
                }
            }
            return embedded.allSatisfy { !$0.isClosed && $0.embeddedOwnerValid && PCNativeBrowserApplication.owner(of: $0) === self.nativeBinding }
        }
        return valid() ? valid : nil
    }

    func peekPagesForRelocation(_ ids: Set<UUID>) -> [PCNativePage] {
        ids.flatMap { peekPages(forTabID: $0) }
    }

    func prepareSidebarSpaceMove(_ items: [SidebarItemReference], to destinationID: UUID,
                                         pinsToday: Bool = false) -> (() -> Bool)? {
        if let destination = store.state.spaces.first(where: { $0.id == destinationID }), destination.profileID != activeProfileID {
            return prepareInterProfileSpaceMove(items, to: destination, pinsToday: pinsToday)
        }
        guard !store.isEphemeral, !isPrivateBrowsing, spaceCommandsAvailable, commandBar == nil,
              let expected = SidebarHierarchySnapshot(state: store.state, spaceID: activeSpaceID, profileID: activeProfileID),
              let target = SidebarHierarchySnapshot(state: store.state, spaceID: destinationID, profileID: activeProfileID),
              var move = SidebarSpaceMove(items: items, from: expected, to: target, state: store.state),
              let validateOwners = prepareSidebarSpaceMoveOwners?(Set(move.tabIDs)) else { return nil }
        move.pinsToday = pinsToday
        let claims = Dictionary(uniqueKeysWithValues: move.tabIDs.map { ($0, ownership.claimSnapshot($0)) })
        guard claims.values.allSatisfy({ $0.transfer == nil }),
              move.permitsSplitOwners(claims.compactMapValues(\.owner), in: presentationID) else { return nil }
        let selection = selectedTabIDs, focus = focusedTabID
        var consumed = false
        return { [weak self] in
            guard let self, !consumed, self.spaceCommandsAvailable, self.commandBar == nil,
                  self.activeSpaceID == expected.spaceID, self.activeProfileID == expected.profileID,
                  self.selectedTabIDs == selection, self.focusedTabID == focus, validateOwners(),
                  move.tabIDs.allSatisfy({ self.ownership.claimSnapshot($0) == claims[$0] }),
                  move.applying(to: self.store.state) != nil else { return false }
            consumed = true
            do {
                guard try self.store.moveSidebarItemsAcrossSpaces(move) else { return false }
                self.render(self.store.state); self.requestNativeSelection()
                if let item = move.roots.first {
                    self.showSidebarMoveNotice(item: item, space: destinationID, profile: expected.profileID)
                }
                return true
            } catch {
                showError(error); return false
            }
        }
    }

    private func prepareInterProfileSpaceMove(_ items: [SidebarItemReference], to destination: BrowserSpace,
                                              pinsToday: Bool = false) -> (() -> Bool)? {
        guard !store.isEphemeral, !isPrivateBrowsing, spaceCommandsAvailable, commandBar == nil,
              let expected = SidebarHierarchySnapshot(state: store.state, spaceID: activeSpaceID, profileID: activeProfileID),
              let target = SidebarHierarchySnapshot(state: store.state, spaceID: destination.id, profileID: destination.profileID),
              var move = SidebarSpaceMove(items: items, from: expected, to: target, state: store.state), move.crossesProfiles,
              Set(move.tabIDs).isDisjoint(with: store.retiringTabIDs) else { return nil }
        move.pinsToday = pinsToday
        let selection = selectedTabIDs, focus = focusedTabID
        var consumed = false
        return { [weak self] in
            guard let self, !consumed, self.spaceCommandsAvailable, self.commandBar == nil,
                  self.activeSpaceID == expected.spaceID, self.activeProfileID == expected.profileID,
                  self.selectedTabIDs == selection, self.focusedTabID == focus,
                  move.applying(to: self.store.state) != nil else { return false }
            consumed = true
            let moved = Set(move.tabIDs)
            let proposal: (BrowserState) -> BrowserState? = { move.applying(to: $0) }
            return self.confirmInterProfileMove(tabCount: move.tabIDs.count,
                                                sourceProfiles: move.tabIDs.isEmpty ? [] : [expected.profileID],
                                                destinationSpaceID: destination.id, moving: moved, proposal: proposal) { [weak self] in
                guard let self else { return }
                self.store.moveAcrossProfiles(moved, proposal: proposal) { [weak self] result in
                    guard let self else { return }
                    switch result {
                    case .success(true):
                        self.onInterProfileMoveCommitted?(moved)
                        self.render(self.store.state); self.requestNativeSelection()
                        if let item = move.roots.first {
                            self.showSidebarMoveNotice(item: item, space: destination.id, profile: destination.profileID)
                        }
                    case .success(false): self.explainRefusedInterProfileMove(moved, proposal: proposal)
                    case .failure(let error): showError(error)
                    }
                }
            }
        }
    }

    func dismissSidebarMoveNotice() {
        sidebarMoveToast?.dismiss(animated: false); sidebarMoveToast = nil
    }

    func showSidebarMoveNotice(item: SidebarItemReference, space: UUID, profile: UUID, message: String? = nil) {
        dismissSidebarMoveNotice()
        let toast = showToast(.standard(message ?? "Tab moved! Click to go there."), at: .window, onTap: { [weak self] in
            _ = self?.revealSidebarItem(item, spaceID: space, profileID: profile)
        }, onRetire: { [weak self] in
            guard let self, self.sidebarMoveToast?.isRetiring != false else { return }
            self.sidebarMoveToast = nil
        })
        sidebarMoveToast = toast
    }

    @discardableResult
    func revealSidebarItem(_ item: SidebarItemReference, spaceID: UUID, profileID: UUID) -> Bool {
        guard !store.isEphemeral, !isPrivateBrowsing, activeProfileID == profileID,
              commandBar == nil, activePeek == nil, canSelectSpace(spaceID, profileID: profileID),
              let window, PCNativeBrowserApplication.canPresentTabSwitcher(in: window),
              let target = SidebarItemReveal(item: item, spaceID: spaceID, profileID: profileID, state: store.state) else { return false }
        do {
            guard try store.revealSidebarItem(target), selectSpaceFromUser(spaceID, profileID: profileID) else { return false }
            closeLibrary(restoreFocus: false)
            render(store.state)
            if sidebarPresentation == .hidden { setSidebarPresentation(.floating) }
            rootView.layoutSubtreeIfNeeded()
            sidebar.revealItem(item)
            return true
        } catch { showError(error); return false }
    }

    var folderDuplicateContextAvailable: Bool {
        guard !store.isEphemeral, nativeWindowRequest?.isOffTheRecord != true,
              let binding = nativeBinding, !binding.isPrivateBrowsing else { return false }
        switch binding.browsingContextKind {
        case .regular, .unavailable: return true
        case .offTheRecord, .mixed: return false
        @unknown default: return false
        }
    }

    func prepareFolderDuplicate(_ folderID: UUID) -> (() -> Bool)? {
        prepareSidebarDuplicate([.folder(folderID)])
    }

    func prepareSidebarDuplicate(_ items: [SidebarItemReference]) -> (() -> Bool)? {
        guard folderDuplicateContextAvailable, let window, let lease = prepareSidebarMoves(items),
              let target = SidebarDuplicateTarget(items: items, spaceID: activeSpaceID,
                  profileID: activeProfileID, state: store.state) else { return nil }
        let selectionIsCurrent: () -> Bool
        if items.count > 1 {
            guard let validator = sidebar.itemSelectionValidator(items) else { return nil }
            selectionIsCurrent = validator
        } else { selectionIsCurrent = { true } }
        let destinations: () -> SidebarCopySources? = { [weak self] in
            guard let self, selectionIsCurrent(), lease.isValid, self.folderDuplicateContextAvailable,
                  let sources = self.resolveSidebarCopyDestinations?(target.tabs),
                  sources.validates(target.tabs) else { return nil }
            return sources
        }
        guard destinations() != nil else { return nil }
        var consumed = false
        return { [weak self, weak window] in
            guard !consumed, let self, let window, self.window === window,
                  let urls = destinations() else { return false }
            consumed = true; lease.end()
            do {
                guard let result = try self.store.duplicateSidebarItems(target, destinations: urls.destinations, documents: urls.documents,
                    creation: self.creationProvenance(activeTabID: self.currentTabID)) else { return false }
                self.registerSidebarCopyUndo(SidebarCopyUndo.duplicateName, roots: result.roots,
                    spaceID: target.hierarchy.spaceID, profileID: target.hierarchy.profileID, sources: urls,
                    openTabIDs: result.openTabIDs, originatingSpaceID: target.hierarchy.spaceID, window: window)
                self.openDuplicatedChildren(result.openTabIDs, spaceID: target.hierarchy.spaceID,
                    profileID: target.hierarchy.profileID, window: window)
                return true
            } catch {
                showError(error); return false
            }
        }
    }

    func prepareFolderDeletion(_ folderID: UUID) -> (() -> Bool)? {
        prepareSidebarDeletion([.folder(folderID)])
    }

    func prepareSidebarRootsClose(_ items: [SidebarItemReference], archive: Bool, requiresConfirmation: Bool,
                                          isSelectionCommand: Bool, selectionIsCurrent current: @escaping () -> Bool,
                                          declined: @escaping () -> Void = {}) -> (() -> Bool)? {
        guard let target = SidebarKeyboardCloseTarget(items: items, spaceID: activeSpaceID,
                  profileID: activeProfileID, state: store.state) else { return nil }
        let ids = Set(target.items.tabs.map(\.id))
        let expected = target.items.hierarchy
        let elsewhere = target.items.tabs.map(\.id).filter { !switcherCanUse($0) }
        if !elsewhere.isEmpty {
            let valid: () -> Bool = { [weak self] in
                guard let self, current(), self.sidebarRootsCloseAvailable(ids),
                      self.activeSpaceID == expected.spaceID, self.activeProfileID == expected.profileID else { return false }
                return SidebarHierarchySnapshot(state: self.store.state, spaceID: expected.spaceID, profileID: expected.profileID) == expected
            }
            guard valid() else { return nil }
            var consumed = false
            return { [weak self] in
                guard !consumed, let self, valid() else { return false }
                let origins = self.closeOrigins(elsewhere)
                guard !elsewhere.contains(where: { origins[$0]?()?.prepareNotesToClose([$0]) == false }) else {
                    self.reportRefusedClose(ids, unsavedNotes: true); return false
                }
                consumed = true
                return self.moveRootsHere(elsewhere[...], moved: []) { [weak self] moved in
                    let giveBack = { [weak self] in self?.returnMovedRoots(moved); declined() }
                    guard let self, ids.allSatisfy(self.switcherCanUse),
                          let close = self.prepareSidebarRootsClose(items, archive: archive, requiresConfirmation: requiresConfirmation,
                              isSelectionCommand: isSelectionCommand, selectionIsCurrent: current, declined: giveBack),
                          close() else {
                        self?.handBackRefusedClose(moved[...], origins: origins); declined()
                        self?.reportRefusedClose(ids, unsavedNotes: false); return false
                    }
                    return true
                }
            }
        }
        if !isPrivateBrowsing, archive {
            return prepareSidebarDeletion(items, isSelectionCommand: isSelectionCommand,
                requiresConfirmation: requiresConfirmation, recordsKeyboardReopen: true, selectionIsCurrent: current,
                declined: declined)
        }
        guard current(), let window else { return nil }
        let selection = selectedTabIDs, focus = focusedTabID
        let valid: () -> Bool = { [weak self, weak window] in
            guard let self, let window, self.window === window, current(),
                  self.sidebarRootsCloseAvailable(ids, movingHere: false),
                  self.activeSpaceID == expected.spaceID, self.activeProfileID == expected.profileID,
                  self.selectedTabIDs == selection, self.focusedTabID == focus else { return false }
            return SidebarHierarchySnapshot(state: self.store.state, spaceID: expected.spaceID, profileID: expected.profileID) == expected
        }
        guard valid() else { return nil }
        var consumed = false
        return { [weak self] in
            guard !consumed, let self, valid(),
                  let releaseSelection = isSelectionCommand ? self.sidebar.retainItemSelectionForSheet(items) : {} else { return false }
            consumed = true
            self.prepareStoreContext()
            self.closeTabsWithReopen(ids, shouldCommit: { [weak self] in
                guard let self, !self.isClosing, !self.wholeWindowClose, current(),
                      self.activeSpaceID == expected.spaceID, self.activeProfileID == expected.profileID,
                      self.selectedTabIDs == selection, self.focusedTabID == focus else { return false }
                return SidebarHierarchySnapshot(state: self.store.state, spaceID: expected.spaceID, profileID: expected.profileID) == expected
            }) { [weak self] allowed in
                releaseSelection()
                guard let self, allowed else { declined(); return }
                for id in ids { self.presentation.remove(id) }
                self.render(self.store.state); self.requestNativeSelection()
            }
            return true
        }
    }

    func splitCellCloseAvailable(_ id: UUID) -> Bool {
        guard let group = SidebarSplitItems.groups(in: store.state, spaceID: activeSpaceID).first(where: { $0.id == id }) else { return false }
        return sidebarRootsCloseAvailable(Set(group.tabIDs))
    }

    func splitCellCloseAction(_ id: UUID) -> SidebarSplitCellLayout.CloseAction? {
        guard let group = SidebarSplitItems.groups(in: store.state, spaceID: activeSpaceID).first(where: { $0.id == id }),
              let location = SidebarHierarchy.location(of: .split(id), state: store.state, spaceID: activeSpaceID) else { return nil }
        return SidebarSplitCellLayout.closeAction(today: location.section == .today,
            anyChildPresented: group.tabIDs.contains { hasPresentedContent($0) })
    }

    func hasPresentedContent(_ id: UUID) -> Bool {
        browsers[id] != nil || noteEditors[id] != nil || easelEditors[id] != nil
    }

    func prepareSidebarDeletion(_ items: [SidebarItemReference], isSelectionCommand: Bool = false,
                                        requiresConfirmation: Bool = true, recordsKeyboardReopen: Bool = false,
                                        selectionIsCurrent: @escaping () -> Bool = { true },
                                        declined: @escaping () -> Void = {}) -> (() -> Bool)? {
        guard !folderUndo.isBusy, folderDuplicateContextAvailable, let window,
              selectionIsCurrent(), let lease = prepareSidebarMoves(items),
              let target = FolderRemovalTarget(items: items, spaceID: activeSpaceID,
                  profileID: activeProfileID, state: store.state) else { return nil }
        let typed = target.tabs.filter { InternalPage(urlString: $0.savedURL) != nil }
        guard let documents = typed.isEmpty ? [:] : resolveSidebarCopyDestinations?(typed)?.documents,
              SidebarDocumentReference.validates(target.tabs, references: documents) else { return nil }
        let ids = Set(target.tabs.map(\.id))
        guard retirementUnavailableReason?(ids) == nil else { return nil }
        let selection = selectedTabIDs, focus = focusedTabID
        let reopen = recordsKeyboardReopen ? ClosedItemIntent(
            ids: Set(target.tabs.filter { $0.kind == .today }.map(\.id)), state: store.state,
            spaceID: activeSpaceID, profileID: activeProfileID, focusedTabID: currentTabID) : nil
        guard let nextSelection = FolderRemovalSelection.resolve(target: target, state: store.state,
            selected: selection, focused: focus, referrerPool: self.presentation.referrerPool,
            previouslySelectedItemID: self.presentation.previouslySelectedItemID,
            available: { self.switcherCanUse($0) }) else { return nil }
        var consumed = false
        return { [weak self, weak window] in
            guard !consumed, let self, let window, self.window === window,
                  !self.folderUndo.isBusy, self.folderDuplicateContextAvailable, selectionIsCurrent(), lease.isValid, window.attachedSheet == nil else { return false }
            guard let releaseSelection = isSelectionCommand ? self.sidebar.retainItemSelectionForSheet(items) : {} else { return false }
            consumed = true
            let proceed: (Bool) -> Void = { [weak self, weak window] approved in
                DispatchQueue.main.async {
                    guard let self, let window, self.window === window else { releaseSelection(); lease.end(); return }
                    guard approved, selectionIsCurrent(), lease.isValid,
                          !self.folderUndo.isBusy, self.folderDuplicateContextAvailable,
                          self.retirementUnavailableReason?(ids) == nil else {
                        releaseSelection(); lease.end()
                        self.updateNavigation(); declined()
                        if approved, self.retirementUnavailableReason?(ids) != nil { self.reportRefusedClose(ids, unsavedNotes: false) }
                        return
                    }
                    lease.end()
                    self.store.deleteFolder(target, selection: nextSelection, documents: documents, shouldCommit: { [weak self, weak window] in
                        guard let self, let window, self.window === window,
                              !self.isClosing, !self.wholeWindowClose, !self.windowClosePending,
                              !self.folderUndo.isBusy, self.folderDuplicateContextAvailable,
                              self.activeSpaceID == target.hierarchy.spaceID,
                              self.activeProfileID == target.hierarchy.profileID,
                              self.selectedTabIDs == selection, self.focusedTabID == focus, selectionIsCurrent() else { return false }
                        return FolderRemovalSelection.resolve(target: target, state: self.store.state,
                            selected: selection, focused: focus, referrerPool: self.presentation.referrerPool,
                            previouslySelectedItemID: self.presentation.previouslySelectedItemID,
                            available: { self.switcherCanUse($0) }) == nextSelection
                    }, didCommit: { [weak self, weak window] undo in
                        guard let self, let window, self.window === window, !self.isClosing else { return }
                        self.registerFolderUndo(undo)
                        if !target.folderIDs.isEmpty {
                            if !self.isPrivateBrowsing { self.closedItems.recordFolderDeletion(undo) }
                        } else if let reopen { self.closedItems.record(reopen, in: self.store.state) }
                    }) { [weak self, weak window] result in
                        releaseSelection()
                        guard let self, let window, self.window === window else { return }
                        switch result {
                        case .success(true):
                            for id in ids { self.presentation.remove(id) }
                            let applied = self.presentation.finishFolderRemoval(nextSelection, state: self.store.state,
                                available: { self.switcherCanUse($0) })
                            if applied { self.focusedTabID = nextSelection.focusedTabID }
                            self.render(self.store.state)
                            if applied && !ids.isDisjoint(with: selection) {
                                self.requestNativeSelection(); self.focusSelectedLocalContent()
                            }
                        case .success(false): self.updateNavigation(); declined()
                        case .failure(let error): self.updateNavigation(); declined(); showError(error)
                        }
                    }
                }
            }
            if requiresConfirmation {
                let singleFolder = target.roots.count == 1 && !target.folderIDs.isEmpty, empty = target.tabs.isEmpty
                ParcDialog.confirm(in: window,
                    title: singleFolder ? "Delete your “\(target.name)” folder?"
                        : empty ? "Delete the selected folders?"
                        : target.folderIDs.isEmpty ? "Archive the selected tabs?" : "Delete the selected items?",
                    message: empty ? (singleFolder ? "This folder holds" : "These folders hold") + " no tabs, so none will be archived."
                        : singleFolder ? "Deleting this folder will archive the tabs inside it."
                        : "All selected tabs, including tabs inside selected folders, will be archived. Notes and Easels will remain in your Library.",
                    confirm: singleFolder ? "Delete Folder" : target.folderIDs.isEmpty ? "Archive Tabs" : "Delete",
                    destructive: true, decided: proceed)
            } else {
                proceed(true)
            }
            return true
        }
    }

    var windowUndoContextAvailable: Bool {
        windowUndoOwnerAvailable && window?.attachedSheet == nil
    }

    var windowUndoOwnerAvailable: Bool {
        guard let binding = nativeBinding, binding.window === window,
              presentation.isReady, !isPopupWindow, !isClosing, !wholeWindowClose,
              !windowClosePending, !windowCloseApproved,
              transferringTabIDs.isEmpty, resolvingTransfers.isEmpty, transferRecoveries.isEmpty,
              window?.isVisible == true else { return false }
        switch binding.browsingContextKind {
        case .regular: return !store.isEphemeral && !binding.isPrivateBrowsing
        case .offTheRecord: return store.isEphemeral && binding.isPrivateBrowsing
        case .unavailable: return !store.isEphemeral && !binding.isPrivateBrowsing
        case .mixed: return false
        @unknown default: return false
        }
    }

    private var folderUndoOwnerAvailable: Bool {
        folderDuplicateContextAvailable && presentation.isReady && !isPopupWindow
            && !isClosing && !wholeWindowClose && !windowClosePending && !windowCloseApproved
            && transferringTabIDs.isEmpty && resolvingTransfers.isEmpty
            && window?.isVisible == true
    }

    var folderUndoContextAvailable: Bool {
        folderUndoOwnerAvailable && window?.attachedSheet == nil
    }

    var usesFolderUndoResponder: Bool {
        if windowUndoContextAvailable, let editor = themeEditor,
           editor.window?.isKeyWindow == true,
           let responder = editor.window?.firstResponder as? NSView,
           responder === editor || responder.isDescendant(of: editor) { return true }
        guard windowUndoContextAvailable, let window, NSApp.mainWindow === window,
              PCNativeBrowserApplication.canUseWindowUndo(in: window),
              let responder = window.firstResponder else { return false }
        if responder is NSTextView || responder is NSControl { return false }
        guard let view = responder as? NSView else { return responder === window }
        if let page = selectedNativePage(), view === page.nativeView || view.isDescendant(of: page.nativeView) {
            return page.canUseWindowUndo
        }
        return view === sidebar || view.isDescendant(of: sidebar) || view === rootView || view === pageHost
            || libraryView.map { view === $0.spaceManager || view.isDescendant(of: $0.spaceManager) } == true
    }

    func windowWillReturnFieldEditor(_ sender: NSWindow, to client: Any?) -> Any? {
        guard sender === window else { return nil }
        return commandBar?.fieldEditor(for: client) ?? residentCommandBar?.fieldEditor(for: client)
    }

    func windowWillReturnUndoManager(_ window: NSWindow) -> UndoManager? {
        guard self.window === window else { return nil }
        return usesFolderUndoResponder ? folderUndo : nativeEditingUndo
    }

    func configureFolderUndoMenuItem(_ item: NSMenuItem, redo: Bool) {
        let direction: FolderUndoManager.Direction = redo ? .redo : .undo
        if usesFolderUndoResponder, let command = folderUndo.command(direction) {
            item.action = #selector(performFolderUndoCommand(_:)); item.target = self
            item.representedObject = command
            item.title = (redo ? "Redo " : "Undo ") + command.name
        } else {
            item.action = NSSelectorFromString(redo ? "redo:" : "undo:")
            item.target = nil; item.representedObject = nil; item.title = redo ? "Redo" : "Undo"
        }
    }

    func registerAppearanceUndo(from previous: AppAppearance, to next: AppAppearance) {
        guard folderUndoContextAvailable else { return }
        folderUndo.append(.init(name: "Update Appearance",
            isValid: { direction in AppAppearance.current == (direction == .undo ? next : previous) },
            isAvailable: { [weak self] _ in self?.folderUndoContextAvailable == true },
            perform: { direction, done in done(AppAppearance.apply(direction == .undo ? previous : next)) }))
    }

    @objc func performFolderUndoCommand(_ sender: NSMenuItem) {
        guard validateMenuItem(sender), let command = sender.representedObject as? FolderUndoManager.Command else { return }
        _ = folderUndo.perform(command)
    }

    func folderUndoShortcut(_ event: NSEvent) -> PCNativeShortcutCommand? {
        guard event.type == .keyDown, !event.isARepeat,
              let key = KeyboardShortcut.capture(event), key.key == "z",
              key.flags == .command || key.flags == [.command, .shift],
              usesFolderUndoResponder,
              let command = folderUndo.command(key.flags.contains(.shift) ? .redo : .undo) else { return nil }
        folderUndoKeyItem.representedObject = command
        return PCNativeShortcutCommand(item: folderUndoKeyItem, revision: folderUndo.revision, priority: .preferParc)
    }

    private func registerFolderUndo(_ record: FolderDeletionUndo) {
        let operation = FolderUndoOperation(record)
        _ = folderUndo.append(.init(name: record.actionName, isValid: { [weak self] direction in
            guard let self else { return false }
            switch direction {
            case .undo: return self.store.canUndoFolderDeletion(operation.record)
            case .redo: return operation.record.redoTarget(in: self.store.state) != nil
            }
        }, isAvailable: { [weak self] direction in
            guard let self, self.folderUndoContextAvailable,
                  operation.record.documentsAreAvailable else { return false }
            let ids = Set(operation.record.tabs.map(\.id))
            guard ids.isDisjoint(with: self.store.retiringTabIDs) else { return false }
            switch direction {
            case .undo: return ids.allSatisfy { self.switcherCanUse($0) }
            case .redo: return self.retirementUnavailableReason?(ids) == nil
            }
        }, perform: { [weak self] direction, completion in
            guard let self else { completion(false); return }
            switch direction {
            case .undo: self.undoFolder(operation, completion: completion)
            case .redo: self.redoFolder(operation, completion: completion)
            }
        }))
    }

    private func undoFolder(_ operation: FolderUndoOperation, completion: @escaping (Bool) -> Void) {
        guard folderUndoContextAvailable, let window else { completion(false); return }
        let record = operation.record
        do {
            let committed = try store.undoFolderDeletion(record, shouldCommit: { [weak self, weak window] in
                guard let self, let window, self.window === window, self.folderUndoContextAvailable else { return false }
                return record.tabs.allSatisfy { self.switcherCanUse($0.id) }
            })
            if committed {
                let focused = presentation.finishFolderUndo(record, state: store.state, available: { self.switcherCanUse($0) })
                if focused { focusedTabID = record.focusedTabID }
                render(store.state)
                if focused { requestNativeSelection(); focusSelectedLocalContent() }
            }
            completion(committed)
        } catch { completion(false); showError(error) }
    }

    private func redoFolder(_ operation: FolderUndoOperation, completion: @escaping (Bool) -> Void) {
        guard let target = operation.record.redoTarget(in: store.state) else { completion(false); return }
        retireSidebarItems(target, commit: { selection, shouldCommit, finished in
            store.deleteFolder(target, selection: selection, documents: operation.record.documentReferences,
                               shouldCommit: shouldCommit, didCommit: { [weak self] undo in
                operation.record = undo
                if let self, !target.folderIDs.isEmpty, !self.isPrivateBrowsing { self.closedItems.recordFolderDeletion(undo) }
            }, completion: finished)
        }, completion: completion)
    }

    func registerSidebarCopyUndo(_ name: String, roots: [SidebarItemReference], spaceID: UUID, profileID: UUID,
                                         sources: SidebarCopySources, openTabIDs: [UUID],
                                         originatingSpaceID: UUID, window: NSWindow) {
        guard let record = SidebarCopyUndo(actionName: name, roots: roots, spaceID: spaceID, profileID: profileID,
                                           documents: Array(sources.documents.values), openTabIDs: openTabIDs,
                                           state: store.state) else { return }
        folderUndo.appendSidebarCopy(record, store: store, canUse: { [weak self] ids, direction in
            guard let self, self.folderUndoContextAvailable else { return false }
            switch direction {
            case .undo: return self.retirementUnavailableReason?(ids) == nil
            case .redo: return ids.allSatisfy { self.switcherCanUse($0) }
            }
        }, remove: { [weak self] record, target, done in
            guard let self else { done(nil); return }
            var refreshed: SidebarCopyUndo?
            self.retireSidebarItems(target, commit: { selection, shouldCommit, finished in
                self.store.removeSidebarCopy(record, target: target, selection: selection, shouldCommit: shouldCommit,
                                             didCommit: { refreshed = $0 }, completion: finished)
            }) { committed in done(committed ? refreshed : nil) }
        }, didRestore: { [weak self, weak window] record in
            guard let self, let window, self.window === window else { return }
            self.render(self.store.state)
            self.openDuplicatedChildren(record.openTabIDs, spaceID: record.spaceID, profileID: record.profileID,
                                        window: window, originatingSpaceID: originatingSpaceID)
        }, onError: { [weak self] in self?.showError($0) })
    }

    private func retireSidebarItems(_ target: FolderRemovalTarget,
                                    commit: (FolderRemovalSelection?, @escaping () -> Bool,
                                             @escaping (Result<Bool, Error>) -> Void) -> Void,
                                    completion: @escaping (Bool) -> Void) {
        guard folderUndoContextAvailable, let window else { completion(false); return }
        let space = activeSpaceID, profile = activeProfileID, selection = selectedTabIDs, focus = focusedTabID
        let ids = Set(target.tabs.map(\.id))
        guard retirementUnavailableReason?(ids) == nil else { completion(false); return }
        let showsTarget = space == target.hierarchy.spaceID
            || (target.hierarchy.includesFavorites && profile == target.hierarchy.profileID)
        let nextSelection = showsTarget
            ? FolderRemovalSelection.resolve(target: target, state: store.state, spaceID: space, selected: selection,
                focused: focus, referrerPool: presentation.referrerPool,
                previouslySelectedItemID: presentation.previouslySelectedItemID,
                available: { self.switcherCanUse($0) }) : nil
        guard !showsTarget || nextSelection != nil else { completion(false); return }
        commit(nextSelection, { [weak self, weak window] in
            guard let self, let window, self.window === window, self.folderUndoOwnerAvailable,
                  self.activeSpaceID == space, self.activeProfileID == profile,
                  self.selectedTabIDs == selection, self.focusedTabID == focus else { return false }
            guard let nextSelection else { return true }
            return FolderRemovalSelection.resolve(target: target, state: self.store.state, spaceID: space,
                selected: selection, focused: focus, referrerPool: self.presentation.referrerPool,
                previouslySelectedItemID: self.presentation.previouslySelectedItemID,
                available: { self.switcherCanUse($0) }) == nextSelection
        }) { [weak self, weak window] result in
            guard let self, let window, self.window === window else { completion(false); return }
            switch result {
            case .success(let committed):
                if committed {
                    for id in ids { self.presentation.remove(id) }
                    let applied = nextSelection.map { self.presentation.finishFolderRemoval($0, state: self.store.state,
                        available: { self.switcherCanUse($0) }) } ?? false
                    if applied { self.focusedTabID = nextSelection?.focusedTabID }
                    self.render(self.store.state)
                    if applied && !ids.isDisjoint(with: selection) { self.requestNativeSelection(); self.focusSelectedLocalContent() }
                }
                completion(committed)
            case .failure(let error): completion(false); showError(error)
            }
        }
    }

    func openDuplicatedChildren(_ ids: [UUID], spaceID: UUID, profileID: UUID, window: NSWindow,
                                        originatingSpaceID: UUID? = nil) {
        for id in ids {
            guard self.window === window, folderDuplicateContextAvailable, !isClosing, !wholeWindowClose, !windowClosePending,
                  activeSpaceID == (originatingSpaceID ?? spaceID), activeProfileID == profileID,
                  !store.isProfileRemovalPending(profileID), !store.retiringTabIDs.contains(id),
                  !closingTabIDs.contains(id), !transferringTabIDs.contains(id),
                  browsers[id] == nil,
                  let tab = store.state.tab(id, where: { ($0.spaceID == spaceID || $0.kind == .favorite)
                      && $0.profileID == profileID && $0.archivedAt == nil }),
                  FolderDuplicateTarget.validDestination(tab.url), let url = URL(string: tab.url),
                  ownership.claim(id, owner: presentationID) else { continue }
            let pane = makePane(tab)
            pane.frame = pageHost.bounds
            panes[id] = pane; parkedPages.addSubview(pane)
            pane.layoutSubtreeIfNeeded()
            let browser = PCBrowserView(frame: pane.contentBounds,
                profilePath: store.independentEngineProfilePath(for: profileID))
            browser.delegate = self
            browsers[id] = browser; browserProfiles[id] = profileID; liveTabModels[id] = tab
            pane.browser = browser; pane.showBrowser(); pane.layoutSubtreeIfNeeded()
            requestedURLs[id] = tab.url
            if browser.loadBackgroundURL(url) {
                presentation.recordCreation(id, state: store.state)
            } else {
                failures[id] = "This copied page could not open. Select it to try again."
                requestedURLs.removeValue(forKey: id)
            }
        }
        attachOwnedPages()
    }
}
