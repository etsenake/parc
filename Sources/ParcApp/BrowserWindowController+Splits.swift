import AppKit
import Combine
import ParcCore
import ParcEngine

extension BrowserWindowController {
    private func externalSplitDropContent(_ id: UUID) -> (view: NSView, local: Bool, valid: () -> Bool)? {
        if let browser = browsers[id], let page = browser.nativePage {
            return (page.nativeView, false, { [weak self, weak browser, weak page] in
                guard let self, let browser, let page else { return false }
                return self.browsers[id] === browser && browser.nativePage === page && !page.isClosed
            })
        }
        if let note = noteEditors[id], note.editor.isViewLoaded, note.editor.canAcceptExternalDrop {
            let editor = note.editor, profileID = note.profileID
            return (editor.view, true, { [weak self, weak editor] in
                guard let self, let editor, self.noteEditors[id]?.editor === editor,
                      self.noteEditors[id]?.profileID == profileID,
                      let tab = self.store.state.tab(id),
                      tab.profileID == profileID, InternalPage(urlString: tab.url) == .note(editor.file.url) else { return false }
                return editor.canAcceptExternalDrop
            })
        }
        if let easel = easelEditors[id], easel.editor.isViewLoaded, easel.editor.canAcceptExternalSplitDrop {
            let editor = easel.editor, documentID = easel.documentID, profileID = easel.profileID
            return (editor.view, true, { [weak self, weak editor] in
                guard let self, let editor, self.easelEditors[id]?.editor === editor,
                      self.easelEditors[id]?.documentID == documentID,
                      self.easelEditors[id]?.profileID == profileID,
                      let tab = self.store.state.tab(id),
                      tab.profileID == profileID, InternalPage(urlString: tab.url)?.easelID == documentID else { return false }
                return editor.canAcceptExternalSplitDrop
            })
        }
        return nil
    }

    func beginExternalSplitDrop(from nativeView: NSView, info: NSDraggingInfo) -> ExternalSplitDropSession? {
        let otherWindow = window.map { !$0.isKeyWindow && NSApp.isActive && info.draggingSource != nil } ?? false
        guard otherWindow ? interProfileDropAvailable : splitCommandsAvailable,
              splitDropView == nil, commandBar == nil, pageCapture == nil,
              let window, window.isKeyWindow || otherWindow,
              let url = ExternalSplitDropSession.readURL(info.draggingPasteboard),
              selectedTabIDs.allSatisfy({ id in
                  store.state.containsTab(id, where: { $0.archivedAt == nil }) &&
                  peekPages(forTabID: id).isEmpty
              }) else { return nil }
        let selection = selectedTabIDs, layout = activeSplitLayout
        let contents = selection.compactMap(externalSplitDropContent)
        guard contents.count == selection.count,
              Self.admitsExternalSplitDrop(into: nativeView, info: info, contents: contents) else { return nil }
        let spaceID = activeSpaceID, profileID = activeProfileID, focusID = currentTabID
        let bounds = pageHost.bounds, hostFrame = pageHost.frame, windowFrame = window.frame
        let identities = selection.compactMap { splitPaneIdentity($0) }
        let frames = selection.compactMap { panes[$0].map { $0.content.convert($0.content.bounds, to: pageHost) } }
        let originalTabs = selection.compactMap { id in store.state.tab(id) }
        let tabID = UUID(), savedHomeID = UUID()
        let hierarchy = SidebarHierarchySnapshot(state: store.state, spaceID: spaceID, profileID: profileID, includesFavorites: true)
        let possibleHome = ExternalSplitDrop.savedHomeSource(state: store.state, selection: selection, layout: layout, target: .insert(0))
        let typedHome = possibleHome.flatMap { InternalPage(urlString: $0.savedURL) != nil ? $0 : nil }
        let documents = typedHome.flatMap { resolveSidebarCopyDestinations?([$0])?.documents } ?? [:]
        guard hierarchy != nil, identities.count == selection.count, frames.count == selection.count,
              let reservation = splitView.prepareDropReservation(in: pageHost,
                  contents: selection.compactMap { panes[$0]?.content }) else { return nil }
        let validate: () -> Bool = { [weak self, weak window, weak nativeView] in
            guard let self, let window, let nativeView, self.window === window,
                  otherWindow ? self.interProfileDropAvailable : (window.isKeyWindow && self.splitCommandsAvailable),
                  self.commandBar == nil, self.pageCapture == nil, self.splitDropView == nil,
                  self.activeSpaceID == spaceID, self.activeProfileID == profileID,
                  self.selectedTabIDs == selection, self.currentTabID == focusID,
                  self.activeSplitLayout == layout, self.pageHost.bounds == bounds,
                  SidebarHierarchySnapshot(state: self.store.state, spaceID: spaceID, profileID: profileID, includesFavorites: true) == hierarchy,
                  contents.allSatisfy({ $0.valid() && $0.view.window === window && $0.view.isDescendant(of: self.pageHost) }),
                  self.pageHost.frame == hostFrame, window.frame == windowFrame,
                  nativeView.window === window, nativeView.isDescendant(of: self.pageHost),
                  selection.enumerated().allSatisfy({ item in
                      guard self.splitPaneIdentity(item.element) == identities[item.offset],
                            let tab = self.store.state.tab(item.element),
                            tab.archivedAt == nil, tab.spaceID == originalTabs[item.offset].spaceID,
                            tab.profileID == profileID, tab.kind == originalTabs[item.offset].kind,
                            tab.folderID == originalTabs[item.offset].folderID,
                            tab.savedURL == originalTabs[item.offset].savedURL,
                            tab.savedTitle == originalTabs[item.offset].savedTitle,
                            tab.customTitle == originalTabs[item.offset].customTitle,
                            self.peekPages(forTabID: item.element).isEmpty,
                            let pane = self.panes[item.element] else { return false }
                      return pane.window === window && reservation.isCurrent
                  }) else { return false }
            return otherWindow || PCNativeBrowserApplication.canPresentTabSwitcher(in: window)
        }
        let creation = TabCreationProvenance(referrerID: nil, activeTabID: focusID,
            profileID: profileID, state: store.state)
        var admissions: [(target: SplitDropTarget, orientation: SplitOrientation, allowed: Bool)] = []
        let session = ExternalSplitDropSession(host: pageHost, info: info, frames: frames,
            orientation: layout?.orientation ?? .horizontal,
            slotSizes: layout?.stacks?.validated(paneCount: selection.count)?.slotSizes, reservation: reservation, validate: validate,
            insertionColor: { [weak self] in self.map { ThemeChromePalette.appearanceBasedMaxContrast(theme: $0.rootView.paletteTheme) } ?? .clear },
            canPropose: { [weak self] target, orientation in
                guard validate(), let self else { return false }
                if let home = ExternalSplitDrop.savedHomeSource(state: self.store.state, selection: selection, layout: layout, target: target),
                   !SidebarDocumentReference.validates([home], references: documents) { return false }
                if let cached = admissions.first(where: { $0.target == target && $0.orientation == orientation }) {
                    return cached.allowed
                }
                let allowed = ExternalSplitDrop.proposal(url: url, tabID: tabID, state: self.presentedState,
                    spaceID: spaceID, profileID: profileID, selection: selection, layout: layout,
                    target: target, orientation: orientation, creation: creation, now: Date(), savedHomeID: savedHomeID) != nil
                admissions.append((target, orientation, allowed))
                return allowed
            }, commit: { [weak self] target, orientation in
                guard let self, validate() else { return false }
                var committed = false
                self.performWindowCommand {
                    do {
                        committed = try self.store.dropExternalURLIntoSplit(url, tabID: tabID,
                            spaceID: spaceID, profileID: profileID, expectedSelection: selection,
                            expectedLayout: layout, target: target, orientation: orientation, creation: creation,
                            savedHomeID: savedHomeID, documents: ExternalSplitDrop.savedHomeSource(state: self.store.state,
                                selection: selection, layout: layout, target: target) == nil ? [:] : documents)
                        if committed { self.presentation.recordCreation(tabID, state: self.store.state) }
                    } catch { self.showToast(.standard("Couldn’t add link"), at: .window) }
                }
                if committed {
                    self.focusedTabID = tabID; self.updateNavigation(); self.requestNativeSelection()
                    if let home = self.store.state.tab(savedHomeID) {
                        self.openDuplicatedChildren([savedHomeID], spaceID: home.spaceID, profileID: profileID,
                            window: window, originatingSpaceID: spaceID)
                    }
                }
                return committed
            })
        if session == nil { reservation.end() }
        session?.targets.onChange = { [weak self] target in self?.setSplitDropProposal(target, selection: selection) }
        session?.admitsReceiver = { view, info in
            validate() && Self.admitsExternalSplitDrop(into: view, info: info, contents: contents)
        }
        return session
    }

    private static func admitsExternalSplitDrop(into nativeView: NSView, info: NSDraggingInfo,
                                                contents: [(view: NSView, local: Bool, valid: () -> Bool)]) -> Bool {
        guard let receiver = contents.first(where: { nativeView === $0.view || nativeView.isDescendant(of: $0.view) }) else { return false }
        guard receiver.local else { return true }
        let richTypes: [NSPasteboard.PasteboardType] = [EaselStyledText.pasteboardType,
            EaselStyledText.previousPasteboardType, EaselStyledText.legacyPasteboardType,
            .rtfd, .rtf, .png, .tiff]
        guard info.draggingPasteboard.availableType(from: richTypes) == nil else { return false }
        if let source = info.draggingSource as? NSView,
           source === receiver.view || source.isDescendant(of: receiver.view) { return false }
        return true
    }

    private func beginSplitDrag(_ sourceID: UUID) -> SidebarSplitDrag? {
        guard splitCommandsAvailable, splitDropView == nil,
              let window, window.isKeyWindow, commandBar == nil,
              let source = store.state.tab(sourceID, where: { $0.archivedAt == nil }),
              source.profileID == activeProfileID, source.spaceID == activeSpaceID, source.kind != .favorite,
              switcherCanUse(sourceID) || canMovePageHere(sourceID), peekPages(forTabID: sourceID).isEmpty else { return nil }
        let sourceElsewhere = !switcherCanUse(sourceID)
        let selection = selectedTabIDs, layout = activeSplitLayout
        guard !selection.contains(sourceID) else { return nil }
        let spaceID = activeSpaceID, profileID = activeProfileID, focusID = currentTabID
        let frame = pageHost.bounds, windowFrame = window.frame
        let sourceBrowser = browsers[sourceID], sourcePage = sourceBrowser?.nativePage
        let sourcePane = panes[sourceID]
        let sourceBrowserIdentity = sourceBrowser.map(ObjectIdentifier.init)
        let sourcePaneIdentity = sourcePane.map(ObjectIdentifier.init)
        let sourcePageIdentity = sourcePage?.identifier
        let groups = store.state.splitLayouts.filter { $0.spaceID == spaceID }
        let allIDs = Set(selection + [sourceID])
        let originals = allIDs.compactMap { id in store.state.tab(id) }
        let hierarchy = SidebarHierarchySnapshot(state: store.state, spaceID: spaceID, profileID: profileID, includesFavorites: true)
        let homes = originals.filter { ($0.kind == .pinned || $0.kind == .favorite) && !(layout?.tabIDs.contains($0.id) ?? false) }
        let savedHomeIDs = Dictionary(uniqueKeysWithValues: homes.map { ($0.id, UUID()) })
        let typed = homes.filter { InternalPage(urlString: $0.savedURL) != nil }
        let documents = typed.isEmpty ? [:] : (resolveSidebarCopyDestinations?(typed)?.documents ?? [:])
        let claims = Dictionary(uniqueKeysWithValues: allIDs.map { ($0, ownership.claimSnapshot($0)) })
        let noteOwners = Dictionary(uniqueKeysWithValues: allIDs.compactMap { id in noteEditors[id].map { (id, ObjectIdentifier($0.editor)) } })
        let easelOwners = Dictionary(uniqueKeysWithValues: allIDs.compactMap { id in easelEditors[id].map { (id, ObjectIdentifier($0.editor)) } })
        let embedded = allIDs.flatMap { embeddedPages(forTabID: $0) }
        let creation = TabCreationProvenance(referrerID: nil, activeTabID: focusID, profileID: profileID, state: store.state)
        let identities = selection.compactMap { splitPaneIdentity($0) }
        guard hierarchy != nil, originals.count == allIDs.count, identities.count == selection.count, selection.allSatisfy({ panes[$0] != nil }),
              let reservation = splitView.prepareDropReservation(in: pageHost,
                  contents: selection.compactMap { panes[$0]?.content }) else { return nil }
        let validate: () -> Bool = { [weak self, weak window] in
            guard let self, let window, self.window === window, window.isKeyWindow,
                  self.splitCommandsAvailable,
                  self.activeSpaceID == spaceID, self.activeProfileID == profileID,
                  self.selectedTabIDs == selection, self.currentTabID == focusID, self.activeSplitLayout == layout,
                  self.pageHost.bounds == frame, window.frame == windowFrame,
                  sourceElsewhere ? self.canMovePageHere(sourceID) : self.switcherCanUse(sourceID),
                  self.peekPages(forTabID: sourceID).isEmpty,
                  SidebarHierarchySnapshot(state: self.store.state, spaceID: spaceID, profileID: profileID, includesFavorites: true) == hierarchy,
                  allIDs.allSatisfy({ id in self.ownership.claimSnapshot(id) == claims[id]
                      && (id == sourceID && sourceElsewhere || self.switcherCanUse(id)) }),
                  originals.allSatisfy({ original in self.store.state.tabs.contains { actual in
                      actual.id == original.id && actual.archivedAt == nil && actual.savedURL == original.savedURL
                          && actual.savedTitle == original.savedTitle && actual.customTitle == original.customTitle
                  } }),
                  Dictionary(uniqueKeysWithValues: allIDs.compactMap { id in self.noteEditors[id].map { (id, ObjectIdentifier($0.editor)) } }) == noteOwners,
                  Dictionary(uniqueKeysWithValues: allIDs.compactMap { id in self.easelEditors[id].map { (id, ObjectIdentifier($0.editor)) } }) == easelOwners,
                  Set(allIDs.flatMap { self.embeddedPages(forTabID: $0) }.map(ObjectIdentifier.init)) == Set(embedded.map(ObjectIdentifier.init)),
                  embedded.allSatisfy({ !$0.isClosed && $0.embeddedOwnerValid && PCNativeBrowserApplication.owner(of: $0) === self.nativeBinding }),
                  self.store.state.splitLayouts.filter({ $0.spaceID == spaceID }) == groups,
                  let actual = self.store.state.tab(sourceID),
                  actual.archivedAt == nil, actual.profileID == source.profileID,
                  actual.spaceID == source.spaceID, actual.kind == source.kind, actual.folderID == source.folderID,
                  self.browsers[sourceID].map(ObjectIdentifier.init) == sourceBrowserIdentity,
                  self.panes[sourceID].map(ObjectIdentifier.init) == sourcePaneIdentity,
                  self.browsers[sourceID]?.nativePage?.identifier == sourcePageIdentity,
                  self.browsers[sourceID]?.nativePage?.isClosed != true,
                  selection.enumerated().allSatisfy({ item in
                      guard self.splitPaneIdentity(item.element) == identities[item.offset], let pane = self.panes[item.element] else { return false }
                      return pane.window === window && reservation.isCurrent
                  }) else { return false }
            return PCNativeBrowserApplication.canPresentTabSwitcher(in: window)
        }
        let drag = SidebarSplitDrag(tabID: sourceID, window: window, validate: validate,
            commit: { [weak self] target, orientation in
                guard validate(), let self else { return false }
                guard let required = OriginalSplitDrop.savedHomes(source: sourceID, state: self.presentedState,
                    selection: selection, layout: layout, target: target, orientation: orientation, spaceID: spaceID) else { return false }
                let requiredIDs = Set(required.map(\.id))
                var committed = false
                self.performWindowCommand {
                    committed = self.store.dropTabIntoSplit(sourceID, expectedSelection: selection,
                        expectedLayout: layout, target: target, orientation: orientation,
                        savedHomeIDs: savedHomeIDs, creation: creation,
                        documents: documents.filter { requiredIDs.contains($0.key) })
                }
                if committed {
                    if sourceElsewhere { _ = self.selectTab(sourceID) }
                    self.focusedTabID = sourceID; self.updateNavigation(); self.requestNativeSelection()
                    for original in required {
                        if let homeID = savedHomeIDs[original.id], let home = self.store.state.tab(homeID) {
                            self.openDuplicatedChildren([homeID], spaceID: home.spaceID, profileID: profileID,
                                window: window, originatingSpaceID: spaceID)
                        }
                    }
                } else if self.store.persistenceError != nil { self.showToast(.standard("Couldn’t move tab"), at: .window) }
                return committed
            }, finish: { [weak self] in
                reservation.end(animated: true); self?.splitDropView?.targets.reset()
                self?.splitDropView?.removeFromSuperview(); self?.splitDropView = nil
            })
        let overlay = SplitDropView(frame: frame, drag: drag,
            reservation: reservation, insertionColor: { [weak self] in self.map { ThemeChromePalette.appearanceBasedMaxContrast(theme: $0.rootView.paletteTheme) } ?? .clear })
        overlay.contentTarget = { [weak self, weak overlay] info in overlay.flatMap { self?.noteContentDropTarget(for: info, over: $0) } }
        overlay.canPropose = { [weak self] target, orientation in
            guard let self, validate(), let required = OriginalSplitDrop.savedHomes(source: sourceID, state: self.presentedState,
                selection: selection, layout: layout, target: target, orientation: orientation, spaceID: spaceID) else { return false }
            let requiredIDs = Set(required.map(\.id))
            return SidebarDocumentReference.validates(required, references: documents.filter { requiredIDs.contains($0.key) })
                && OriginalSplitDrop.proposal(source: sourceID, state: self.presentedState, selection: selection,
                    layout: layout, target: target, orientation: orientation, spaceID: spaceID, profileID: profileID,
                    now: Date(), savedHomeIDs: savedHomeIDs, creation: creation) != nil
        }
        overlay.targets.onChange = { [weak self] target in self?.setSplitDropProposal(target, selection: selection) }
        pageHost.addSubview(overlay, positioned: .above, relativeTo: splitView); splitDropView = overlay
        return drag
    }

    func beginSidebarSplitDrag(_ sourceID: UUID) -> SidebarSplitDrag? {
        guard let drag = beginSplitDrag(sourceID) ?? beginForeignOnlySplitDrag(sourceID) else { return nil }
        onSplitDragBegan?(drag, self)
        return drag
    }

    private func beginForeignOnlySplitDrag(_ sourceID: UUID) -> SidebarSplitDrag? {
        guard let window, window.isKeyWindow, !isPopupWindow, !isPrivateBrowsing, !store.isEphemeral,
              let source = store.state.tab(sourceID),
              source.profileID == activeProfileID, source.spaceID == activeSpaceID,
              source.kind == .pinned || source.kind == .today, InterProfileMove.admits(source),
              switcherCanUse(sourceID), peekPages(forTabID: sourceID).isEmpty else { return nil }
        return SidebarSplitDrag(tabID: sourceID, window: window, validate: { [weak self, weak window] in
            guard let self, let window, self.window === window, window.isKeyWindow,
                  let actual = self.store.state.tab(sourceID),
                  InterProfileMove.samePlacement(actual, source),
                  self.switcherCanUse(sourceID), self.peekPages(forTabID: sourceID).isEmpty else { return false }
            return true
        }, commit: { _, _ in false }, finish: {})
    }

    private var interProfileDropAvailable: Bool {
        guard !isPopupWindow, !isPrivateBrowsing, !store.isEphemeral, presentation.isReady,
              !isClosing, !wholeWindowClose, !windowClosePending, !windowCloseApproved,
              nativeFullscreenTabID == nil, transferringTabIDs.isEmpty, resolvingTransfers.isEmpty,
              collectionTransfer == nil, closingTabIDs.isEmpty, modelRetirementIDs.isEmpty,
              peekRetirementParents.isEmpty, tabSwitcher == nil, themePopover == nil, activePeek == nil,
              libraryView == nil, commandBar == nil, splitInsertion == nil,
              splitDropView == nil, spaceCreation == nil, !store.isProfileRemovalPending(activeProfileID),
              !selectedTabIDs.isEmpty, selectedTabIDs.count == 1 || activeSplitLayout != nil,
              let window, window.isVisible, !window.isMiniaturized, window.attachedSheet == nil,
              let binding = nativeBinding, binding.window === window else { return false }
        return binding.canParticipateInPageTransfer
    }

    func beginForeignSplitDrop(_ drag: SidebarSplitDrag, from source: BrowserWindowController) {
        guard source !== self, source.store === store, source.ownership === ownership,
              foreignSplitDropView == nil, interProfileDropAvailable, drag.isValid,
              let dragWindow = drag.window, dragWindow === source.window, let window,
              let original = store.state.tab(drag.tabID),
              original.kind == .pinned || original.kind == .today, InterProfileMove.admits(original),
              original.profileID == activeProfileID
                || InterProfileMove.profilesAvailable(original.profileID, activeProfileID, in: store.state) else { return }
        let selection = selectedTabIDs, layout = activeSplitLayout
        let spaceID = activeSpaceID, profileID = activeProfileID, focusID = currentTabID
        let frame = pageHost.bounds, windowFrame = window.frame
        let hierarchy = SidebarHierarchySnapshot(state: store.state, spaceID: spaceID, profileID: profileID, includesFavorites: true)
        let identities = selection.compactMap { splitPaneIdentity($0) }
        let members = selection.compactMap { id in store.state.tab(id) }
        let homes = members.filter { ($0.kind == .pinned || $0.kind == .favorite) && !(layout?.tabIDs.contains($0.id) ?? false) }
        let homeIDs = Dictionary(uniqueKeysWithValues: homes.map { ($0.id, UUID()) })
        let typed = (homes + (original.kind == .pinned ? [original] : [])).filter { InternalPage(urlString: $0.savedURL) != nil }
        let documents = typed.isEmpty ? [:] : (resolveSidebarCopyDestinations?(typed)?.documents ?? [:])
        let sourceHomeID = UUID()
        guard hierarchy != nil, identities.count == selection.count, selection.allSatisfy({ panes[$0] != nil }),
              members.count == selection.count,
              let reservation = splitView.prepareDropReservation(in: pageHost,
                  contents: selection.compactMap { panes[$0]?.content }) else { return }
        let current: () -> Bool = { [weak self, weak window] in
            guard let self, let window, self.window === window, self.interProfileDropAvailable,
                  self.activeSpaceID == spaceID, self.activeProfileID == profileID,
                  self.selectedTabIDs == selection, self.currentTabID == focusID, self.activeSplitLayout == layout,
                  SidebarHierarchySnapshot(state: self.store.state, spaceID: spaceID, profileID: profileID, includesFavorites: true) == hierarchy,
                  selection.enumerated().allSatisfy({ self.splitPaneIdentity($0.element) == identities[$0.offset] }),
                  let actual = self.store.state.tab(original.id),
                  InterProfileMove.samePlacement(actual, original), !self.store.retiringTabIDs.contains(original.id) else { return false }
            return true
        }
        let gesture: () -> Bool = { [weak self, weak window] in
            guard let self, let window, current(), drag.isValid, self.pageHost.bounds == frame,
                  window.frame == windowFrame, reservation.isCurrent else { return false }
            return true
        }
        let creation = TabCreationProvenance(referrerID: nil, activeTabID: focusID, profileID: profileID, state: store.state)
        let request: (SplitDropTarget, SplitOrientation) -> ForeignSplitDrop.Request = { target, orientation in
            .init(source: original, sourceHomeID: sourceHomeID, spaceID: spaceID, profileID: profileID, selection: selection,
                  layout: layout, target: target, orientation: orientation, destinationHomeIDs: homeIDs)
        }
        let proposal: (ForeignSplitDrop.Request, BrowserState) -> BrowserState? = { value, state in
            guard let required = ForeignSplitDrop.destinationHomes(value, state: state) else { return nil }
            let checked = original.profileID == profileID ? required : required.filter { $0.id != original.id }
            let ids = Set(checked.map(\.id))
            guard SidebarDocumentReference.validates(checked, references: documents.filter { ids.contains($0.key) }) else { return nil }
            return ForeignSplitDrop.proposal(value, state: state, now: Date(), creation: creation)
        }
        let overlay = SplitDropView(frame: frame, drag: drag,
            reservation: reservation, perform: { [weak self, weak source] target, orientation in
                guard let self, gesture() else { return false }
                let value = request(target, orientation)
                guard proposal(value, self.store.state) != nil else { return false }
                if original.profileID == profileID, let source {
                    return self.moveForeignSplitDropHere(original.id, from: source, sourceSpaceID: original.spaceID,
                        proposal: { proposal(value, $0) }, sourceHomeID: sourceHomeID, homeIDs: Array(homeIDs.values))
                }
                let moved: Set<UUID> = [original.id]
                return self.confirmInterProfileMove(tabCount: 1, sourceProfiles: [original.profileID], destinationSpaceID: spaceID,
                                                    moving: moved, proposal: { proposal(value, $0) }) { [weak self, weak source] in
                    guard let self, current() else { return }
                    self.store.moveAcrossProfiles(moved, proposal: { proposal(value, $0) }) { [weak self, weak source] result in
                        guard let self else { return }
                        switch result {
                        case .success(true):
                            self.onInterProfileMoveCommitted?(moved)
                            self.finishInterProfileArrival(original.id)
                            source?.openSavedHomeInBackground(sourceHomeID)
                            if let window = self.window {
                                for homeID in homeIDs.values where self.store.state.containsTab(homeID) {
                                    self.openDuplicatedChildren([homeID], spaceID: spaceID, profileID: profileID,
                                        window: window, originatingSpaceID: spaceID)
                                }
                            }
                        case .success(false): self.explainRefusedInterProfileMove(moved) { proposal(value, $0) }
                        case .failure: self.showToast(.standard("Couldn’t move tab"), at: .window)
                        }
                    }
                }
            }, insertionColor: { [weak self] in self.map { ThemeChromePalette.appearanceBasedMaxContrast(theme: $0.rootView.paletteTheme) } ?? .clear })
        overlay.contentTarget = { [weak self, weak overlay] info in overlay.flatMap { self?.noteContentDropTarget(for: info, over: $0) } }
        overlay.canPropose = { [weak self] target, orientation in
            guard let self, gesture() else { return false }
            return proposal(request(target, orientation), self.store.state) != nil
        }
        overlay.targets.onChange = { [weak self] target in self?.setSplitDropProposal(target, selection: selection) }
        pageHost.addSubview(overlay, positioned: .above, relativeTo: splitView); foreignSplitDropView = overlay
        drag.onEnd { [weak self, weak overlay] in
            reservation.end(animated: true)
            guard let self, let overlay, self.foreignSplitDropView === overlay else { return }
            overlay.targets.reset(); overlay.removeFromSuperview(); self.foreignSplitDropView = nil
        }
    }

    private func moveForeignSplitDropHere(_ id: UUID, from source: BrowserWindowController, sourceSpaceID: UUID,
                                          proposal: @escaping (BrowserState) -> BrowserState?,
                                          sourceHomeID: UUID, homeIDs: [UUID]) -> Bool {
        guard source.activeSpaceID == sourceSpaceID, source.sidebarWindowMoveAvailable, sidebarWindowMoveAvailable,
              let window else { return false }
        let spaceID = activeSpaceID, profileID = activeProfileID
        var plan = SidebarWindowTransfer.Plan(tabIDs: [id], sourceSpaceID: sourceSpaceID, profileID: profileID,
            destinationSpaceID: spaceID, isCurrent: { proposal($0) != nil },
            commit: { try $0.commitForeignSplitDrop([id], proposal: proposal) })
        plan.arrival = id
        guard let transaction = SidebarWindowTransfer(source: source, destination: self, plan: plan) else { return false }
        transaction.onFinish = { [weak self, weak source, weak window] committed in
            guard committed, let self, let window else { return }
            source?.openSavedHomeInBackground(sourceHomeID)
            for homeID in homeIDs where self.store.state.containsTab(homeID) {
                self.openDuplicatedChildren([homeID], spaceID: spaceID, profileID: profileID, window: window, originatingSpaceID: spaceID)
            }
        }
        return transaction.begin()
    }

    func confirmInterProfileMove(tabCount: Int, sourceProfiles: Set<UUID>, destinationSpaceID: UUID,
                                 moving ids: Set<UUID> = [], proposal: ((BrowserState) -> BrowserState?)? = nil,
                                 proceed: @escaping () -> Void) -> Bool {
        let block = proposal.flatMap { InterProfileDocumentBlock(moving: ids, before: store.state, after: $0(store.state)) }
        guard let destination = store.state.spaces.first(where: { $0.id == destinationSpaceID }),
              let gate = InterProfileMoveGate.resolve(sourceProfiles: sourceProfiles, destination: destination.profileID,
                  decision: nil, bypass: store.bypassesInterProfileMoveConfirmation, blocked: block != nil) else { return false }
        switch gate {
        case .abort: return false
        case .blocked:
            if let block { showDocumentMoveBlock(block) }
            return false
        case .proceed: proceed(); return true
        case .confirm:
            guard let window, window.attachedSheet == nil, interProfileDialog == nil,
                  let prompt = InterProfileMovePrompt(tabCount: tabCount, destinationSpaceID: destinationSpaceID, state: store.state) else { return false }
            let dialog = InterProfileMoveDialog(prompt: prompt)
            interProfileDialog = dialog
            if !window.isKeyWindow { window.makeKeyAndOrderFront(nil) }
            let began = dialog.begin(for: window) { [weak self] decision in
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.interProfileDialog = nil
                    guard case .proceed(let remember)? = InterProfileMoveGate.resolve(sourceProfiles: sourceProfiles,
                        destination: destination.profileID, decision: decision, bypass: self.store.bypassesInterProfileMoveConfirmation) else { return }
                    if remember { self.store.rememberInterProfileMoveChoice() }
                    proceed()
                }
            }
            if !began { interProfileDialog = nil }
            return began
        }
    }

    func showDocumentMoveBlock(_ block: InterProfileDocumentBlock) {
        showToast(.standard(block.title, subLabel: block.message), at: .window)
    }

    func explainRefusedInterProfileMove(_ ids: Set<UUID>, proposal: (BrowserState) -> BrowserState?) {
        guard let block = InterProfileDocumentBlock(moving: ids, before: store.state, after: proposal(store.state)) else {
            NSSound.beep(); return
        }
        showDocumentMoveBlock(block)
    }

    func finishInterProfileArrival(_ id: UUID) {
        if presentation.selectExistingTab(id, state: store.state, available: { ownership.canUse($0, owner: presentationID) }) {
            presentation.recordFocusedTab(id); focusedTabID = id
        }
        render(store.state); updateNavigation(); requestNativeSelection()
    }

    func easelEditorsForRelocation(in ids: Set<UUID>) -> [UUID: EaselEditorViewController] {
        Dictionary(uniqueKeysWithValues: easelEditors.filter { ids.contains($0.key) }.map { ($0.key, $0.value.editor) })
    }

    func closeLocalDocumentEditors(_ ids: Set<UUID>) -> Bool {
        guard ids.allSatisfy({ noteEditors[$0]?.editor.prepareToClose() ?? true }),
              ids.allSatisfy({ embeddedPages(forTabID: $0).isEmpty && !hasPendingNativePage(in: [$0]) }),
              easelEditorsForRelocation(in: ids).values.allSatisfy({ $0.canPrepareForProfileRelocation }),
              easelEditorsForRelocation(in: ids).values.allSatisfy({ $0.prepareForProfileRelocation() }) else { return false }
        for id in ids {
            retireNoteEditor(id)
            if let easel = easelEditors.removeValue(forKey: id) {
                easel.editor.retirePageOwner(); panes[id]?.clearNativeContent(); easelFailures.removeValue(forKey: id)
            }
        }
        return true
    }

    func openSavedHomeInBackground(_ id: UUID) {
        guard let window, let home = store.state.tab(id) else { return }
        openDuplicatedChildren([id], spaceID: home.spaceID, profileID: home.profileID, window: window)
    }

    func releaseInterProfileClaims(_ ids: Set<UUID>) {
        let released = ids.filter { id in
            browsers[id] == nil && noteEditors[id] == nil && easelEditors[id] == nil
                && !transferringTabIDs.contains(id) && ownership.claimSnapshot(id).owner == presentationID
        }
        for id in released { ownership.release(id, owner: presentationID); presentation.remove(id) }
        render(store.state)
        for id in released where !renderedPaneIDs.contains(id) {
            panes.removeValue(forKey: id)?.removeFromSuperview(); failures.removeValue(forKey: id)
        }
    }

    func showSplitPaneMenu(_ paneID: UUID, from anchor: NSView) {
        guard splitCommandsAvailable, splitInsertion == nil,
              let index = selectedTabIDs.firstIndex(of: paneID),
              let pane = panes[paneID], anchor.window === window,
              anchor.isDescendant(of: pane) else { return }
        let layout = activeSplitLayout
        let orientation = layout?.orientation ?? .horizontal
        let menu = SplitPaneMenu.make(orientation: orientation, index: index, count: selectedTabIDs.count,
                                      layout: layout) { [weak self] operation in
            guard let self else { return nil }
            let command: SplitCommand
            switch operation {
            case .movePrevious: command = .move(-1)
            case .moveNext: command = .move(1)
            case .stackPrevious: command = .moveInStack(-1)
            case .stackNext: command = .moveInStack(1)
            case .addBefore, .addAfter, .addAbove, .addBelow, .stackBefore, .stackAfter: command = .add(operation)
            case .separate: command = .separate
            case .copyLinks: command = .copyLinks
            case .flip: command = .orientation(orientation == .horizontal ? .vertical : .horizontal)
            }
            guard let target = self.splitCommandTarget(command, paneID: paneID) else { return nil }
            return { target.perform() }
        }
        menu.appearance = anchor.effectiveAppearance
        pane.trackSplitMenu {
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: anchor.bounds.maxY), in: anchor)
        }
    }

    private func fillSplitInsertionWithNewDocument(_ session: SplitPaneInsertionSession,
                                                   create: () throws -> (InternalPage, String),
                                                   reportError: (Error) -> Void) {
        guard splitInsertion === session, session.isValid, commandBar == nil, canCreateNoteInSplit else {
            cancelSplitInsertion(restoreFocus: true); return
        }
        let request = session.request
        let document: (InternalPage, String)
        do { document = try create() } catch {
            cancelSplitInsertion(restoreFocus: true); reportError(error); return
        }
        let id = UUID()
        let creation = creationProvenance(activeTabID: currentTabID)
        guard let prepared = request.preparedState(presentedState, tabID: id,
            navigationURL: nil, localPage: document.0, localTitle: document.1,
            now: Date(), creation: creation),
            let homes = OriginalSplitDrop.savedHomes(source: id, state: prepared,
                selection: request.selection, layout: request.layout, target: request.target,
                orientation: request.orientation, spaceID: request.spaceID),
            let plan = splitHomePlan(homes) else {
            cancelSplitInsertion(restoreFocus: true); return
        }
        splitInsertion = nil; session.cancel()
        var committed = false
        performWindowCommand(selectNativePage: false) {
            committed = store.insertSplitPane(request, tabID: id, navigationURL: nil,
                creation: creation, savedHomeIDs: plan.ids, documents: plan.documents,
                localPage: document.0, localTitle: document.1)
        }
        guard committed else {
            render(store.state); requestNativeSelection()
            showToast(.standard("Couldn’t add split pane"), at: .window); return
        }
        focusedTabID = id; render(store.state)
        requestNativeSelection(); focusSelectedLocalContent()
        openSplitHomes(plan.ids, profileID: request.profileID, originatingSpaceID: request.spaceID)
    }

    func cancelSplitInsertion(restoreFocus: Bool) {
        guard let session = splitInsertion else { return }
        splitInsertion = nil; session.cancel()
        let panel = commandBar; commandBar = nil; panel?.dismiss(restoreFocus: false)
        render(store.state)
        guard restoreFocus else { return }
        requestNativeSelection()
        if let find = visibleFind, isCurrentFind(find), !findHost.isHidden, window?.isKeyWindow == true {
            if let editor = findField.currentEditor(), window?.firstResponder === editor { return }
            if window?.makeFirstResponder(findField) == true { return }
        }
        focusSelectedContent()
    }

    func beginSplitInsertion(paneID: UUID, request makeRequest: (BrowserState) -> SplitPaneInsertion?) {
        guard splitInsertion == nil, commandBar == nil,
              splitCommandsAvailable, let window, window.isKeyWindow,
              PCNativeBrowserApplication.canPresentTabSwitcher(in: window),
              let request = makeRequest(presentedState),
              let index = selectedTabIDs.firstIndex(of: paneID),
              let owner = splitCommandTarget(.focus(index + 1), paneID: paneID) else { return }
        let focus = currentTabID, binding = nativeBinding
        let candidates = splitInsertionTabs(profileID: request.profileID).filter { !selectedTabIDs.contains($0.id)
            && (switcherCanUse($0.id) && ownership.canUse($0.id, owner: presentationID) || canMovePageHere($0.id)) }
        let elsewhere = Set(candidates.filter { canMovePageHere($0.id) }.map(\.id))
        var movedIn = Set<UUID>()
        let all = Set(request.selection + candidates.map(\.id))
        let originalCandidates = Dictionary(uniqueKeysWithValues: candidates.map { ($0.id, $0) })
        let embedded = Dictionary(uniqueKeysWithValues: all.map { ($0, embeddedPages(forTabID: $0)) })
        let claims = Dictionary(uniqueKeysWithValues: all.map { ($0, ownership.claimSnapshot($0)) })
        let wrappers = Dictionary(uniqueKeysWithValues: all.compactMap { id in browsers[id].map { (id, $0) } })
        let pages = Dictionary(uniqueKeysWithValues: all.compactMap { id in browsers[id]?.nativePage.map { (id, $0) } })
        let notes = Dictionary(uniqueKeysWithValues: all.compactMap { id in noteEditors[id].map { (id, $0.editor) } })
        let easels = Dictionary(uniqueKeysWithValues: all.compactMap { id in easelEditors[id].map { (id, $0.editor) } })
        let validItem: (UUID) -> Bool = { [weak self, weak window, weak binding] id in
            guard let self, let window, self.window === window, self.nativeBinding === binding else { return false }
            if elsewhere.contains(id) {
                guard movedIn.contains(id) else { return self.canMovePageHere(id) }
                guard self.switcherCanUse(id), self.peekPages(forTabID: id).isEmpty else { return false }
                return self.browsers[id]?.nativePage.map { !$0.isClosed && PCNativeBrowserApplication.owner(of: $0) === binding } ?? true
            }
            guard self.switcherCanUse(id), self.peekPages(forTabID: id).isEmpty,
                  self.ownership.claimSnapshot(id) == claims[id],
                  self.browsers[id] === wrappers[id], self.browsers[id]?.nativePage === pages[id],
                  self.noteEditors[id]?.editor === notes[id], self.easelEditors[id]?.editor === easels[id],
                  Set(self.embeddedPages(forTabID: id).map(ObjectIdentifier.init)) == Set((embedded[id] ?? []).map(ObjectIdentifier.init)),
                  (embedded[id] ?? []).allSatisfy({ !$0.isClosed && $0.embeddedOwnerValid && PCNativeBrowserApplication.owner(of: $0) === binding }) else { return false }
            if let page = pages[id] {
                return !page.isClosed && PCNativeBrowserApplication.owner(of: page) === binding
                    && wrappers[id]?.window === window
            }
            return true
        }
        let session = SplitPaneInsertionSession(request: request, candidateIDs: Set(candidates.map(\.id))) { [weak self, weak window] in
            guard let self, let window, self.window === window, window.isVisible,
                  window.attachedSheet == nil || self.commandBar?.ownsAttachedSheet == true,
                  owner.isAvailable, self.currentTabID == focus,
                  self.activePeek == nil,
                  self.nativeFullscreenTabID == nil, self.libraryView == nil,
                  request.isCurrent(in: self.presentedState), request.selection.allSatisfy(validItem) else { return false }
            return true
        }
        guard session.isValid else { return }
        splitInsertion = session
        render(store.state)
        let splitHistoryExcludedURL = currentBrowser?.url?.absoluteString
            ?? store.state.tabs.first(where: { $0.id == currentTabID })?.url
        let panel = CommandBar(parent: window, tabs: candidates, history: commandBarHistory(profileID: request.profileID),
            historyRevision: store.historyRevision, historyExcludedURL: splitHistoryExcludedURL,
            currentURL: nil, profilePath: store.independentEngineProfilePath(for: request.profileID),
            page: selectedNativePage(), nativeWindow: nativeBinding, extensionDisposition: nil, theme: windowPaletteTheme,
            contentAppearance: rootView.palette.contentAppearance)
        panel.tabCaption = { [weak self] tab in self?.commandBarTabCaption(tab)
            ?? .switchToTab }
        panel.isOwnerValid = session.validate
        panel.onWillSubmitDestination = { [weak session] in session?.submitting = true }
        panel.onRejectedDestination = { [weak self, weak session] in
            guard let self, let session, self.splitInsertion === session else { return }
            self.cancelSplitInsertion(restoreFocus: false)
        }
        panel.onDismiss = { [weak self, weak session, weak panel] in
            guard let self, let session, self.commandBar === panel else { return }
            self.commandBar = nil
            if !session.submitting { self.cancelSplitInsertion(restoreFocus: true) }
        }
        panel.restorePageFocus = { [weak self] in self?.requestNativeSelection(); self?.focusSelectedLocalContent() }
        @MainActor final class Submission { var run: (PCNativeSearchNavigation?, UUID?) -> Void = { _, _ in } }
        let submission = Submission()
        submission.run = { [weak self, weak session, weak window, weak submission] navigation, existing in
            guard let self, let session, let submission, self.splitInsertion === session else { return }
            guard let window, self.window === window, session.isValid, self.commandBar == nil,
                  window.isKeyWindow, PCNativeBrowserApplication.canPresentTabSwitcher(in: window) else {
                self.cancelSplitInsertion(restoreFocus: false); return
            }
            if let navigation {
                guard navigation.profilePath == self.store.independentEngineProfilePath(for: request.profileID) else {
                    self.cancelSplitInsertion(restoreFocus: true); return
                }
            } else if let existing {
                guard let expected = originalCandidates[existing], validItem(existing),
                      self.store.state.tab(existing) == expected,
                      self.splitInsertionTabs(profileID: request.profileID).contains(where: { $0.id == existing }) else {
                    self.cancelSplitInsertion(restoreFocus: true); return
                }
                if elsewhere.contains(existing), !movedIn.contains(existing) {
                    let started = self.movePagesHere([existing]) {
                        movedIn.insert(existing); submission.run(nil, existing); return true
                    }
                    if !started { self.cancelSplitInsertion(restoreFocus: true) }
                    return
                }
            } else { self.cancelSplitInsertion(restoreFocus: true); return }
            let id = existing ?? UUID()
            let creation = self.creationProvenance(activeTabID: focus)
            guard let prepared = request.preparedState(self.presentedState, tabID: id,
                navigationURL: navigation?.url, now: Date(), creation: creation),
                let homes = OriginalSplitDrop.savedHomes(source: id, state: prepared,
                    selection: request.selection, layout: request.layout, target: request.target,
                    orientation: request.orientation, spaceID: request.spaceID) else {
                self.cancelSplitInsertion(restoreFocus: true); return
            }
            guard let plan = self.splitHomePlan(homes) else {
                self.cancelSplitInsertion(restoreFocus: true); return
            }
            let homeIDs = plan.ids, documents = plan.documents
            if let navigation { self.pendingSearchNavigations[id] = navigation }
            self.splitInsertion = nil; session.cancel()
            var committed = false
            self.performWindowCommand(selectNativePage: false) {
                committed = self.store.insertSplitPane(request, tabID: id, navigationURL: navigation?.url,
                    creation: creation, savedHomeIDs: homeIDs, documents: documents)
                if committed && navigation != nil { self.presentation.recordCreation(id, state: self.store.state) }
            }
            guard committed else {
                self.pendingSearchNavigations.removeValue(forKey: id)
                self.render(self.store.state); self.requestNativeSelection()
                self.showToast(.standard("Couldn’t add split pane"), at: .window); return
            }
            self.focusedTabID = id; self.render(self.store.state)
            self.requestNativeSelection(); self.focusSelectedLocalContent()
            self.openSplitHomes(homeIDs, profileID: request.profileID, originatingSpaceID: request.spaceID)
        }
        panel.onSearchNavigation = { submission.run($0, nil) }
        panel.onSelectTab = { submission.run(nil, $0) }
        panel.onSplitNavigation = { submission.run($0, nil) }
        panel.onSplitTab = { submission.run(nil, $0) }
        panel.canSplitSelection = { [weak session] existing in
            guard let session, session.isValid else { return false }
            if let existing {
                return originalCandidates[existing] != nil && validItem(existing)
            }
            return true
        }
        let localDocumentCommands: Set<String> = ["createNote:", "createNoteInSplit:", "createEasel:"]
        panel.canSplitCommand = { localDocumentCommands.contains($0.id) }
        panel.onSplitCommand = { [weak self, weak session] command in
            guard let self, let session, self.splitInsertion === session, session.isValid else {
                self?.cancelSplitInsertion(restoreFocus: true); return
            }
            switch command.id {
            case "createNote:", "createNoteInSplit:":
                self.fillSplitInsertionWithNewDocument(session, create: {
                    let created = try NoteFolderPreferences.library(for: self.activeProfileID).createNote()
                    return (.note(created), InternalPage.noteTitle("", file: created))
                }, reportError: { self.showNoteError($0) })
            case "createEasel:":
                self.fillSplitInsertionWithNewDocument(session, create: {
                    let easels = try EaselEditorViewController.sharedStore(directory: self.store.easelsDirectory(for: self.activeProfileID))
                    let created = try easels.create()
                    return (.easel(created.document.id), created.document.title)
                }, reportError: { self.showEaselError($0) })
            default:
                self.cancelSplitInsertion(restoreFocus: true)
            }
        }
        let navigate: (String, String) -> Void = { [weak self, weak session] input, typed in
            guard let self, let session, self.splitInsertion === session else { return }
            guard session.isValid else { self.cancelSplitInsertion(restoreFocus: false); return }
            PCNativeBrowserApplication.resolveSearchInput(input, typedText: typed,
                profilePath: self.store.independentEngineProfilePath(for: request.profileID),
                page: self.selectedNativePage(), window: self.nativeBinding) { [weak self, weak session] navigation, error in
                    MainActor.assumeIsolated {
                        guard let self, let session, self.splitInsertion === session else { return }
                        guard session.isValid else { self.cancelSplitInsertion(restoreFocus: false); return }
                        if let navigation { submission.run(navigation, nil) }
                        else { self.cancelSplitInsertion(restoreFocus: true); self.showSearchError(error?.localizedDescription ?? "Search is unavailable for this Space.") }
                    }
                }
        }
        panel.onNavigate = navigate
        panel.onSplitInput = navigate
        commandBarCreatesNewTab = true; commandBarShowsNewTabPlaceholder = true
        commandBar = panel; panel.present()
    }

    func beginSplitInsertion(_ operation: SplitPaneOperation, paneID: UUID) {
        beginSplitInsertion(paneID: paneID) { SplitPaneInsertion(paneID: paneID, operation: operation, state: $0) }
    }

    func prepareSplitResize() -> (([Double]) -> Bool)? {
        guard let receipt = splitResizeReceipt(stacked: false) else { return nil }
        return { factors in receipt { store, layout in store.resizeSplit(expected: layout, widthFactors: factors) } }
    }

    func prepareStackedSplitResize() -> ((SplitStackResize) -> BrowserSplitStacks?)? {
        guard let receipt = splitResizeReceipt(stacked: true) else { return nil }
        return { change in
            var stacks: BrowserSplitStacks?
            let committed = receipt { store, layout in
                guard let resized = layout.resized(by: change), let shape = resized.stacks,
                      store.resizeSplit(expected: layout, resized: resized) else { return false }
                stacks = shape.validated(paneCount: resized.tabIDs.count)
                return true
            }
            return committed ? stacks : nil
        }
    }

    private func splitResizeReceipt(stacked: Bool) -> (((BrowserStore, BrowserSplitLayout) -> Bool) -> Bool)? {
        guard splitInsertion == nil, renderedPaneIDs == selectedTabIDs,
              let window, window.isKeyWindow, let layout = activeSplitLayout, (layout.stacks != nil) == stacked,
              let target = splitCommandTarget(.orientation(layout.orientation)), target.isAvailable,
              PCNativeBrowserApplication.canPresentTabSwitcher(in: window) else { return nil }
        let originalBounds = pageHost.bounds
        var used = false
        return { [weak self, weak window] save in
            guard !used else { return false }; used = true
            guard let self, let window, self.window === window, window.isKeyWindow,
                  target.isAvailable,
                  self.renderedPaneIDs == layout.tabIDs, self.activeSplitLayout == layout,
                  self.pageHost.bounds == originalBounds,
                  PCNativeBrowserApplication.canPresentTabSwitcher(in: window) else { return false }
            var committed = false
            self.performWindowCommand(selectNativePage: false) {
                committed = save(self.store, layout)
            }
            return committed
        }
    }

    var splitCommandsAvailable: Bool {
        spaceCommandsAvailable && activePeek == nil && libraryView == nil
            && !selectedTabIDs.isEmpty
            && (selectedTabIDs.count == 1 || activeSplitLayout != nil)
    }

    func resolvedSplitCommand(_ command: SplitCommand) -> SplitCommand {
        guard case .add(let operation) = command,
              operation.startsSplitView(paneCount: selectedTabIDs.count, isSplit: activeSplitLayout != nil) else { return command }
        return .addNew
    }

    func splitCommandIsAvailable(_ command: SplitCommand) -> Bool {
        guard splitCommandsAvailable else { return false }
        switch resolvedSplitCommand(command) {
        case .focus(let number): return (1...selectedTabIDs.count).contains(number)
        case .next, .previous: return true
        case .add(let operation):
            guard selectedTabIDs.count < 4, splitInsertion == nil else { return false }
            let stacking = operation.addsToStack
            guard stacking || activeSplitLayout?.stacks != nil, let focus = currentTabID else { return !stacking }
            return SplitPaneInsertion(paneID: focus, operation: operation, state: presentedState) != nil
        case .addNew: return selectedTabIDs.count < 4 && splitInsertion == nil
        case .widen, .narrow, .equalize: return splitResizeIsAvailable(command)
        default: return selectedTabIDs.count > 1
        }
    }

    func splitResizeIsAvailable(_ command: SplitCommand) -> Bool {
        guard selectedTabIDs.count > 1, splitInsertion == nil, renderedPaneIDs == selectedTabIDs,
              window?.isKeyWindow == true else { return false }
        let focused = currentTabID.flatMap { panes[$0] }
        switch command {
        case .widen: return focused.map { splitView.canResizePane($0, growing: true) } ?? false
        case .narrow: return focused.map { splitView.canResizePane($0, growing: false) } ?? false
        default: return splitView.canEqualizePanes
        }
    }

    func splitPaneIdentity(_ id: UUID) -> SplitPaneIdentity? {
        guard selectedTabIDs.contains(id), switcherCanUse(id),
              let tab = store.state.tab(id, where: { $0.archivedAt == nil }),
              tab.profileID == activeProfileID, tab.kind == .favorite || tab.spaceID == activeSpaceID,
              let pane = panes[id], pane.window === window else { return nil }
        if let browser = browsers[id] {
            guard let page = browser.nativePage, !page.isClosed, let binding = nativeBinding,
                  existingNativeSelection(binding, page)?.1 === browser else { return nil }
            return SplitPaneIdentity(pane: ObjectIdentifier(pane), browser: ObjectIdentifier(browser), page: page.identifier)
        }
        guard presentation.isLocalSelection(id, state: store.state, hasNativeWrapper: false) else { return nil }
        return SplitPaneIdentity(pane: ObjectIdentifier(pane), browser: nil, page: nil)
    }

    func splitCommandTarget(_ command: SplitCommand, paneID: UUID? = nil) -> SplitCommandTarget? {
        let command = resolvedSplitCommand(command)
        guard splitCommandIsAvailable(command), let focus = currentTabID,
              let index = selectedTabIDs.firstIndex(of: focus) else { return nil }
        let target: UUID
        switch command {
        case .focus(let number):
            guard (1...selectedTabIDs.count).contains(number) else { return nil }
            target = selectedTabIDs[number - 1]
        case .next: target = selectedTabIDs[(index + 1) % selectedTabIDs.count]
        case .previous: target = selectedTabIDs[(index + selectedTabIDs.count - 1) % selectedTabIDs.count]
        default: target = paneID ?? focus
        }
        guard selectedTabIDs.contains(target) else { return nil }
        if case .move(let delta) = command {
            guard let position = selectedTabIDs.firstIndex(of: target) else { return nil }
            if let layout = activeSplitLayout, layout.stacks != nil {
                guard layout.movingSlot(of: target, by: delta) != nil else { return nil }
            } else {
                guard selectedTabIDs.indices.contains(position + delta) else { return nil }
            }
        }
        if case .moveInStack(let delta) = command, activeSplitLayout?.movingWithinStack(target, by: delta) == nil { return nil }
        if case .copyLinks = command, splitLinks().isEmpty { return nil }
        var identities: [UUID: SplitPaneIdentity] = [:]
        for id in selectedTabIDs {
            guard let identity = splitPaneIdentity(id) else { return nil }
            identities[id] = identity
        }
        return SplitCommandTarget(owner: self, command: command, originalFocus: focus, targetID: target, identities: identities)
    }

    func splitLinks() -> [FolderLinks.Link] {
        guard selectedTabIDs.count > 1, activeSplitLayout != nil else { return [] }
        return FolderLinks.links(in: store.state, tabIDs: selectedTabIDs, spaceID: activeSpaceID, profileID: activeProfileID)
    }

    func prepareSplitMenuItem(_ item: NSMenuItem, command: SplitCommand, preservingTarget: Bool) -> Bool {
        if !preservingTarget { item.representedObject = splitCommandTarget(command) }
        return (item.representedObject as? SplitCommandTarget)?.isAvailable == true
    }

    func splitMenuItem(_ title: String, command: SplitCommand) -> NSMenuItem {
        let target = splitCommandTarget(command)
        let item = MenuAction.item(title) { target?.perform() }
        item.isEnabled = target != nil
        return item
    }

    func focusSelectedContent() {
        contentFocusRequest?.cancel(); contentFocusRequest = nil
        guard let window, window.isKeyWindow, presentation.isReady else { return }
        let tabID = currentTabID, peek = activePeek.flatMap { $0.view.isHidden ? nil : $0 }
        let browser = currentBrowser, hadPeek = peek != nil, hadBrowser = browser != nil
        let request = ContentFocusRequest(window: window, content: pageHost) { [weak self, weak window, weak peek, weak browser] in
            guard let self, let window, self.currentTabID == tabID, self.commandBar == nil, self.libraryView == nil,
                  self.spaceCreation == nil, self.pageCapture == nil, self.tabSwitcher == nil,
                  !self.isClosing, !self.wholeWindowClose, !self.windowClosePending,
                  self.activePeek === peek, (peek != nil) == hadPeek,
                  !hadBrowser || (browser != nil && self.currentBrowser === browser) else { return .cancelled }
            if let peek {
                guard !peek.view.isHidden else { return .cancelled }
                peek.focus()
                return (window.firstResponder as? NSView)?.isDescendant(of: peek.view) == true ? .focused : .waiting
            }
            guard let id = tabID else { return .cancelled }
            let paneHoldsFocus = { @MainActor () -> Bool in
                guard let pane = self.panes[id] else { return false }
                return (window.firstResponder as? NSView)?.isDescendant(of: pane) == true
            }
            if let browser = self.currentBrowser {
                guard let page = browser.nativePage, self.renderedPaneIDs.contains(id) else { return .waiting }
                guard !page.isClosed else { return .cancelled }
                if let crash = self.rendererPresentation(browser) {
                    self.focusRendererFailure(id, crash); return paneHoldsFocus() ? .focused : .waiting
                }
                return self.nativeBinding?.requestFocus(for: page) == true ? .focused : .waiting
            }
            guard self.presentation.isLocalSelection(id, state: self.store.state, hasNativeWrapper: false) else { return .waiting }
            if self.panes[id]?.showsBlank == true { window.makeFirstResponder(nil); return .focused }
            self.focusSelectedLocalContent()
            return paneHoldsFocus() ? .focused : .waiting
        }
        contentFocusRequest = request
        request.start()
    }

    func reclaimFocusAfterSplitPresentation() {
        guard let window, ContentFocusRequest.lostByPresentation(window.firstResponder, window: window) else { return }
        focusSelectedContent()
    }

    func focusSelectedLocalContent() {
        guard let id = currentTabID, renderedPaneIDs.contains(id),
              activePeek == nil, commandBar == nil, let window, window.isKeyWindow,
              window.attachedSheet == nil,
              presentation.isLocalSelection(id, state: store.state, hasNativeWrapper: browsers[id] != nil) else { return }
        if let editor = noteEditors[id]?.editor { editor.focusContent() }
        else if let editor = easelEditors[id]?.editor { editor.focusContent() }
        else if panes[id]?.showsBlank == true { window.makeFirstResponder(nil) }
    }

    func executeSplitCommand(_ command: SplitCommand, targetID: UUID) {
        switch command {
        case .focus, .next, .previous:
            pendingNativeSelection = nil
            focusedTabID = targetID
            render(store.state)
            requestNativeSelection()
            focusSelectedContent()
        case .move(let offset):
            guard let layout = activeSplitLayout else { return }
            performWindowCommand { store.moveSplitPane(targetID, offset: offset, expected: layout) }
            reclaimFocusAfterSplitPresentation()
        case .moveInStack(let offset):
            guard let layout = activeSplitLayout else { return }
            performWindowCommand { store.moveSplitPaneWithinStack(targetID, offset: offset, expected: layout) }
            reclaimFocusAfterSplitPresentation()
        case .addNew: toggleSplit()
        case .add(let operation): beginSplitInsertion(operation, paneID: targetID)
        case .copyLinks:
            let links = splitLinks()
            guard !links.isEmpty else { return }
            copyLinkOperation = UUID()
            if LinkPasteboard.write(links, format: .plain) {
                showToast(.copiedLinks(links.compactMap { URL(string: $0.url) }), at: .content(targetID))
            }
        case .close:
            closeClickedSplitPane(targetID)
        case .separate:
            guard let group = activeSplitLayout else { return }
            separateSplitTab(targetID, group: group, originalFocus: currentTabID)
        case .expand:
            NotificationCenter.default.post(name: Self.expandCurrentSplitNotification, object: nil)
        case .widen:
            if let pane = panes[targetID] { splitView.resizePane(pane, growing: true) }
        case .narrow:
            if let pane = panes[targetID] { splitView.resizePane(pane, growing: false) }
        case .equalize:
            splitView.equalizePanes()
        case .orientation(let orientation):
            guard let layout = activeSplitLayout else { return }
            performWindowCommand { store.setSplitLayout(orientation: orientation, widthFactors: layout.widthFactors) }
        }
    }

    func expandDisplayedSplit() {
        guard !isPopupWindow, presentation.isReady, !isClosing, !wholeWindowClose, !windowClosePending,
              spaceCreation == nil, splitInsertion == nil, nativeFullscreenTabID == nil,
              transferringTabIDs.isEmpty, let focus = currentTabID, let layout = activeSplitLayout else { return }
        if layout.stacks != nil {
            guard let expanded = layout.expanded(focusing: focus), expanded != layout else { return }
            prepareStoreContext()
            guard store.resizeSplit(expected: layout, resized: expanded) else { return }
            render(store.state)
            return
        }
        guard let factors = layout.expandedFactors(focusing: focus), factors != layout.widthFactors else { return }
        prepareStoreContext()
        guard store.resizeSplit(expected: layout, widthFactors: factors) else { return }
        render(store.state)
    }
}
