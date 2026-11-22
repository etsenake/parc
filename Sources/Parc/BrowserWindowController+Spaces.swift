import AppKit
import Combine
import ParcCore
import ParcEngine

extension BrowserWindowController {
    func configureSpaceManager(_ library: LibraryView) {
        let manager = library.spaceManager
        let valid: () -> Bool = { [weak self, weak library] in
            guard let self, let library else { return false }
            return self.libraryView === library && library.kind == .spaces && self.spaceCommandsAvailable
        }
        manager.ownerValid = valid
        manager.windowSpaceID = { [weak self] in self?.activeSpaceID }
        manager.onClose = { [weak self] in if valid() { self?.closeLibrary() } }
        library.onLeaveSpaces = { [weak self] in self?.spaceIconPicker?.cancel(); self?.themePopover?.performClose(nil) }
        manager.onCreate = { [weak self] in
            guard let self, valid() else { return }
            self.createSpace()
        }
        manager.onReorder = { [weak self] id, before, order in
            guard let self, valid(), self.managementSpace(id) != nil else { return false }
            do { return try self.store.reorderSpace(id, before: before, expectedOrder: order) }
            catch { showError(error); return false }
        }
        manager.makeMenu = { [weak self] id, _ in
            guard let self, valid() else { return nil }
            return self.spaceManagementMenu(id)?.makeMenu()
        }
        manager.configureSidebar = { [weak self, weak library] id, sidebar in
            guard let self, let library else { return }
            let targetValid: () -> Bool = { [weak self] in valid() && self?.managementSpace(id) != nil }
            sidebar.makeSpaceManagementMenu = { [weak self] target in targetValid() ? self?.spaceManagementMenu(target) : nil }
            sidebar.onRenameSpace = { [weak self] target in if targetValid() { self?.renameSpace(target) } }
            sidebar.onChangeSpaceIcon = { [weak self] target in if targetValid() { self?.changeSpaceIcon(target) } }
            sidebar.onEditTheme = { [weak self] in if targetValid() { self?.editTheme(spaceID: id) } }
            sidebar.onNewFolder = { [weak self] in if targetValid() { self?.createFolder(in: id) } }
            sidebar.onToggleFolder = { [weak self] folderID in
                guard let self, targetValid(), let space = self.managementSpace(id),
                      let folder = self.store.state.folders.first(where: { $0.id == folderID && $0.spaceID == id }) else { return }
                do { _ = try self.store.setFolderExpanded(!folder.isExpanded, expected: folder, profileID: space.profileID) }
                catch { showError(error) }
            }
            sidebar.prepareTabActivation = { [weak self] expected in
                guard let self, targetValid(), expected.spaceID == id,
                      self.store.state.containsTab(expected.id, where: { $0.spaceID == id && $0.profileID == expected.profileID && $0.archivedAt == nil }),
                      self.canUseOrMoveHere(expected.id) else { return nil }
                return { [weak self] in
                    guard let self, targetValid(), self.store.state.containsTab(expected.id, where: { $0.spaceID == id && $0.profileID == expected.profileID && $0.archivedAt == nil }),
                          self.canUseOrMoveHere(expected.id), self.selectSpaceFromUser(id, profileID: expected.profileID) else { return false }
                    self.closeLibrary(restoreFocus: false); self.selectTab(expected.id); return true
                }
            }
            sidebar.configureManagementInteraction(ownerValid: targetValid, onCancel: { [weak self] in
                if targetValid() { self?.closeLibrary() }
            })
            sidebar.prepareTabClose = { [weak self] expected in
                guard let self, targetValid(), expected.spaceID == id, self.canCloseOrMoveHere(expected.id),
                      self.retirementUnavailableReason?([expected.id]) == nil else { return nil }
                return { [weak self] in
                    guard let self, targetValid(), self.store.state.containsTab(expected.id, where: { $0.spaceID == id && $0.profileID == expected.profileID && $0.archivedAt == nil }),
                          self.canCloseOrMoveHere(expected.id), self.retirementUnavailableReason?([expected.id]) == nil else { return false }
                    return self.closeTabMovingHere(expected.id)
                }
            }
            sidebar.onNewTab = { [weak self] in
                guard let self, targetValid(), let space = self.managementSpace(id), self.selectSpaceFromUser(id, profileID: space.profileID) else { return }
                self.closeLibrary(restoreFocus: false); self.newTab()
            }
            let clearable = { [weak self] () -> Set<UUID> in
                guard let self, let space = self.managementSpace(id) else { return [] }
                return SpaceClearToday.ids(in: self.store.state, spaceID: id, profileID: space.profileID)
                    .filter { self.ownership.canUse($0, owner: self.presentationID) }
            }
            sidebar.canClearToday = { targetValid() && !clearable().isEmpty }
            sidebar.onClearToday = { [weak self] in
                guard let self, targetValid(), let space = self.managementSpace(id) else { return }
                let ids = clearable()
                guard !ids.isEmpty else { NSSound.beep(); return }
                self.archiveTabs(ids, reason: .clearButton, in: space)
            }
            sidebar.managementItemMenu = { [weak self, weak sidebar] item in
                guard let self, let sidebar, targetValid() else { return nil }
                let menu = NSMenu(); menu.autoenablesItems = false
                switch item {
                case .folder(let folderID):
                    guard let folder = self.store.state.folders.first(where: { $0.id == folderID && $0.spaceID == id }) else { return nil }
                    menu.addItem(MenuAction.item(folder.isExpanded ? "Collapse Folder" : "Expand Folder") { sidebar.onToggleFolder?(folderID) })
                    menu.addItem(MenuAction.item("New Folder Inside…") { [weak self] in if targetValid() { self?.createFolder(in: id, parent: folder) } })
                    menu.addItem(MenuAction.item("Rename Folder…") { [weak self] in if targetValid() { self?.renameFolder(folderID) } })
                case .tab(let tabID), .split(let tabID):
                    let actual = { if case .split = item { return self.store.state.splitLayouts.first { $0.id == tabID }?.sidebarAnchorID }; return tabID }()
                    guard let tab = self.store.state.tabs.first(where: { $0.id == actual && $0.spaceID == id && $0.archivedAt == nil }) else { return nil }
                    let open = sidebar.prepareTabActivation?(tab)
                    let entry = MenuAction.item("Open Tab") { _ = open?() }; entry.isEnabled = open != nil; menu.addItem(entry)
                    if case .tab = item {
                        let close = sidebar.prepareTabClose?(tab)
                        let entry = MenuAction.item("Close Tab") { _ = close?() }; entry.isEnabled = close != nil; menu.addItem(entry)
                    }
                }
                return menu
            }
            sidebar.requestTabFavicon = { [weak self, weak library] tab, completion in
                guard let self, let library, self.libraryView === library, tab.spaceID == id,
                      let url = URL(string: tab.url), self.managementSpace(id, profileID: tab.profileID) != nil else { completion(nil); return }
                PCNativeBrowserApplication.favicon(for: url, profilePath: self.store.independentEngineProfilePath(for: tab.profileID)) { image in
                    MainActor.assumeIsolated { completion(image) }
                }
            }
        }
        manager.reload(store.state)
    }

    func clearArchive() {
        showLibrary(.archive)
        guard libraryView?.kind == .archive else { return }
        libraryView?.clearAll()
    }

    func showLibraryFromEntry(_ target: LibraryEntryPage?) {
        let showing = libraryView.flatMap { $0.profileID == activeProfileID ? Self.libraryPage($0.kind) : nil }
        switch LibraryEntryRoute.decide(target: target, showing: showing,
                                        lastSelected: LibraryEntryPreferences.shared.lastSelectedPage) {
        case .close: closeLibrary()
        case .open(let page): showLibrary(isPrivateBrowsing && page != .captures ? .downloads : Self.libraryKind(page))
        }
    }
    func dismissForNewSpaceForm() {
        closeLibrary(restoreFocus: false)
        commandBar?.dismiss()
        pageCapture?.dismiss(restoreFocus: false)
        if !findHost.isHidden { dismissFind(restoreFocus: false) }
        navigationHistory?.dismiss(); sidebarPreviews?.dismiss()
        favoriteRename?.cancel(); favoriteSplitRename?.cancel(); splitIconPicker?.cancel()
        sidebar.cancelSpaceNameEditing()
        if let peek = activePeek { peek.requestDismiss(.closeShortcut) }
        if siteControlCenter != nil { dismissSiteControlCenter() }
    }

    var newSpaceBlockingPeekState: NewSpaceBlockerWait.PeekState {
        guard let peek = activePeek else { return .none }
        switch peek.modalPhase {
        case .awaitingDismissConfirmation: return .awaitingConfirmation
        case .dismissing: return .closing
        case .presented: return .open
        }
    }

    func presentNewSpaceForm(attemptsLeft: Int, wait: Int, confirmationShown: Bool = false) {
        guard wait == newSpaceWait else { return }
        if let session = spaceCreation { newSpaceWaitActive = false; session.view.focusName(); return }
        guard window != nil, !isClosing, !wholeWindowClose, !windowClosePending, !windowCloseApproved else {
            newSpaceWaitActive = false; return
        }
        if prepareSidebarNewSpace([])?() == true { newSpaceWaitActive = false; return }
        let peek = newSpaceBlockingPeekState
        let shown = confirmationShown || peek == .awaitingConfirmation
        let step = NewSpaceBlockerWait.next(peek: peek, confirmationShown: shown, attemptsLeft: attemptsLeft)
        guard step != .giveUp else { newSpaceWaitActive = false; return }
        let remaining = step == .waitForConfirmation ? attemptsLeft : attemptsLeft - 1
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.presentNewSpaceForm(attemptsLeft: remaining, wait: wait, confirmationShown: shown)
        }
    }

    private var spaceCreationCanBegin: Bool {
        !isPrivateBrowsing && !store.isEphemeral && spaceCreation == nil
            && spaceCommandsAvailable && activePeek == nil && commandBar == nil
            && libraryView == nil && pageCapture == nil && !siteControlCenterDefers
            && favoriteRename == nil && favoriteSplitRename == nil && splitIconPicker == nil
            && !sidebar.isEditingTitle && !folderUndo.isBusy && collectionTransfer == nil
            && transferRecoveries.isEmpty && !store.isProfileRemovalPending(activeProfileID)
    }

    func prepareSidebarNewSpace(_ items: [SidebarItemReference]) -> (() -> Bool)? {
        guard spaceCreationCanBegin, let window,
              let source = SidebarHierarchySnapshot(state: store.state, spaceID: activeSpaceID, profileID: activeProfileID),
              let draft = SidebarNewSpaceDraft(items: items, from: source, state: store.state,
                  theme: store.state.spaces.first { $0.id == source.spaceID }.map(store.savedTheme(of:))) else { return nil }
        let ids = Set(draft.tabIDs + selectedTabIDs)
        guard let owners = prepareSidebarSpaceMoveOwners?(ids), owners(),
              !hasPendingNativePage(in: ids) else { return nil }
        let claims = Dictionary(uniqueKeysWithValues: ids.map { ($0, ownership.claimSnapshot($0)) })
        var probe = draft; probe.name = "Space"
        guard claims.values.allSatisfy({ $0.transfer == nil }),
              probe.roots.isEmpty || probe.move(in: store.state)?.permitsSplitOwners(claims.compactMapValues(\.owner), in: presentationID) == true else { return nil }
        let selection = selectedTabIDs, focus = focusedTabID
        var consumed = false
        return { [weak self, weak window] in
            guard let self, let window, self.window === window, !consumed,
                  self.spaceCreationCanBegin, self.activeSpaceID == source.spaceID,
                  self.activeProfileID == source.profileID, self.selectedTabIDs == selection,
                  self.focusedTabID == focus, owners(),
                  ids.allSatisfy({ self.ownership.claimSnapshot($0) == claims[$0] }),
                  SidebarNewSpaceDraft(items: items, from: source, state: self.store.state,
                      spaceID: draft.spaceID) != nil,
                  self.prepareNotesToClose(Set(selection)), owners() else { return false }
            let session = SpaceCreationSession(draft: draft, owner: self, claims: claims, validateOwners: owners)
            guard window.makeFirstResponder(nil), owners() else { return false }
            consumed = true
            self.beginSpaceCreation(session)
            return self.spaceCreation === session
        }
    }

    func prepareTurnFolderIntoSpace(_ folderID: UUID) -> (() -> Bool)? {
        guard spaceCreationCanBegin,
              let folder = store.state.folders.first(where: { $0.id == folderID }), folder.spaceID == activeSpaceID,
              let source = SidebarHierarchySnapshot(state: store.state, spaceID: activeSpaceID, profileID: activeProfileID) else { return nil }
        let items = SidebarHierarchy.children(in: .init(spaceID: folder.spaceID, folderID: folderID, section: .pinned), state: store.state)
        guard var draft = SidebarNewSpaceDraft(items: items, from: source, state: store.state,
                  theme: store.state.spaces.first { $0.id == source.spaceID }.map(store.savedTheme(of:))) else { return nil }
        let name = folder.name.trimmingCharacters(in: .whitespacesAndNewlines)
        draft.name = name.isEmpty ? "Untitled" : folder.name
        let ids = Set(draft.tabIDs)
        guard let owners = prepareSidebarSpaceMoveOwners?(ids), owners(),
              !hasPendingNativePage(in: ids) else { return nil }
        let claims = Dictionary(uniqueKeysWithValues: ids.map { ($0, ownership.claimSnapshot($0)) })
        guard claims.values.allSatisfy({ $0.transfer == nil }),
              draft.roots.isEmpty || draft.move(in: store.state)?.permitsSplitOwners(claims.compactMapValues(\.owner), in: presentationID) == true,
              draft.applying(to: store.state) != nil else { return nil }
        var consumed = false
        return { [weak self] in
            guard let self, !consumed, self.spaceCreationCanBegin, self.activeSpaceID == source.spaceID,
                  self.activeProfileID == source.profileID, owners(),
                  ids.allSatisfy({ self.ownership.claimSnapshot($0) == claims[$0] }) else { return false }
            consumed = true
            do {
                guard let spaceID = try self.store.turnFolderIntoSpace(draft, folder: folder) else { return false }
                self.selectSpace(spaceID); self.requestNativeSelection()
                return true
            } catch {
                showError(error)
                return false
            }
        }
    }

    func creationOwnerIsCurrent(_ session: SpaceCreationSession) -> Bool {
        guard spaceCreation === session, let window = session.window, self.window === window,
              !isClosing, !wholeWindowClose, !windowClosePending, !windowCloseApproved,
              presentation.isReady, activeSpaceID == session.draft.source.spaceID,
              activeProfileID == session.draft.source.profileID, selectedTabIDs.isEmpty,
              transferringTabIDs.isEmpty, resolvingTransfers.isEmpty, collectionTransfer == nil,
              store.retiringTabIDs.isDisjoint(with: session.claims.keys),
              closingTabIDs.isDisjoint(with: session.claims.keys),
              modelRetirementIDs.isDisjoint(with: session.claims.keys),
              session.claims.allSatisfy({ ownership.claimSnapshot($0.key) == $0.value }) else { return false }
        var probe = session.draft; probe.name = "Space"
        return probe.applying(to: store.state) != nil
    }

    private func beginSpaceCreation(_ session: SpaceCreationSession) {
        navigationHistory?.dismiss(); sidebarPreviews?.dismiss()
        pageHost.cancelDrop(); sharedQuotes.invalidate()
        if !findHost.isHidden { dismissFind() }
        pendingNativeSelection = nil
        spaceCreation = session
        for id in selectedTabIDs { presentation.remove(id) }
        focusedTabID = nil
        let view = session.view
        view.onNameChange = { [weak self, weak session] name in
            guard let self, let session, self.spaceCreation === session, !session.committing else { return }
            session.draft.name = name
            self.refreshSpaceCreation(session)
        }
        view.onSharingChange = { [weak self, weak session] sharing in
            guard let self, let session, self.creationOwnerIsCurrent(session), !session.committing else { return }
            switch sharing {
            case .share(let id):
                guard session.draft.shareData(withSpace: id, in: self.store.state) else {
                    self.refreshSpaceCreation(session); return
                }
                session.sharedSpaceID = id
            case .separate:
                session.draft.keepSeparate()
                session.sharedSpaceID = nil
            }
            session.view.showError(nil); self.refreshSpaceCreation(session)
        }
        view.onChooseIcon = { [weak self, weak session] anchor in
            guard let self, let session else { return }; self.chooseCreationIcon(session, from: anchor)
        }
        view.onChooseTheme = { [weak self, weak session] anchor in
            guard let self, let session else { return }; self.chooseCreationTheme(session, from: anchor)
        }
        view.onCreate = { [weak self, weak session] in
            guard let self, let session else { return }; self.commitSpaceCreation(session)
        }
        view.onCancel = { [weak self, weak session] in
            guard let self, self.spaceCreation === session else { return }; self.cancelSpaceCreation()
        }
        sidebar.setSpaceCreationView(view)
        setSidebarPresentation(.locked)
        refreshSpaceCreation(session)
        render(store.state); requestNativeSelection(); view.focusName()
    }

    var creationSharingSpaces: [BrowserSpace] {
        store.state.spaces.filter { !store.isProfileRemovalPending($0.profileID) }
    }

    private func refreshSpaceCreation(_ session: SpaceCreationSession) {
        guard spaceCreation === session else { return }
        session.view.replaceSpaces(creationSharingSpaces, selected: session.sharedSpaceID)
        session.view.setCreationAvailable(creationOwnerIsCurrent(session), committing: session.committing)
    }

    func reconcileSpaceCreation() {
        guard let session = spaceCreation, !session.committing else { return }
        if !creationOwnerIsCurrent(session) {
            cancelSpaceCreation(restoreFocus: false, renderContent: false)
        } else {
            refreshSpaceCreation(session); session.iconPicker?.reconcile()
        }
    }

    func finishSpaceCreation(_ session: SpaceCreationSession) {
        spaceCreation = nil
        session.iconPicker?.cancel(); session.iconPicker = nil
        session.themePopover?.close(); session.themePopover = nil; session.themeEditor = nil
        sidebar.setSpaceCreationView(nil)
        session.view.onNameChange = nil; session.view.onSharingChange = nil
        session.view.onChooseIcon = nil; session.view.onChooseTheme = nil
        session.view.onCreate = nil; session.view.onCancel = nil
    }

    func cancelSpaceCreation(restoreFocus: Bool = true, renderContent: Bool = true) {
        guard let session = spaceCreation, !session.committing else { return }
        finishSpaceCreation(session)
        presentation = session.originalPresentation
        presentation.reconcile(store.state) { ownership.canUse($0, owner: presentationID) }
        focusedTabID = session.originalFocus.flatMap { selectedTabIDs.contains($0) ? $0 : nil }
            ?? presentation.preferredFocusedTabID
        pendingNativeSelection = nil
        setSidebarPresentation(session.originalSidebar)
        applyChromeTheme(activeSpace.theme)
        if renderContent, !isClosing, !wholeWindowClose {
            render(store.state); requestNativeSelection()
            if restoreFocus, window?.isKeyWindow == true, window?.attachedSheet == nil {
                if let responder = session.originalResponder as? NSView,
                   SavedFocus.mayReturn(to: responder, in: window) { window?.makeFirstResponder(responder) }
                else if let currentBrowser { window?.makeFirstResponder(currentBrowser) }
                else { focusSelectedLocalContent() }
            }
        }
    }

    private func commitSpaceCreation(_ session: SpaceCreationSession) {
        guard creationOwnerIsCurrent(session), !session.committing, !session.view.hasMarkedText,
              session.window?.isKeyWindow == true, session.window?.attachedSheet == nil,
              let window = session.window, PCNativeBrowserApplication.canPresentTabSwitcher(in: window),
              session.draft.applying(to: store.state) != nil else { return }
        guard session.validateOwners() else {
            session.view.showError("An original page is unavailable. Try again when it is ready, or Cancel."); return
        }
        session.themeEditor?.finishEditing()
        guard creationOwnerIsCurrent(session), session.validateOwners() else { return }
        if let block = documentMoveBlock(session.draft) { session.view.showError(block.message); return }
        session.committing = true; refreshSpaceCreation(session)
        store.createSpace(session.draft) { [weak self, weak session] result in
            guard let self, let session, self.spaceCreation === session else { return }
            switch result {
            case .failure(let error):
                session.committing = false; self.refreshSpaceCreation(session)
                session.view.showError(error.localizedDescription)
            case .success(nil):
                session.committing = false; self.refreshSpaceCreation(session)
                if !session.draft.movesItemsAcrossProfiles {
                    session.view.showError("The original items changed. Cancel and try again.")
                } else if let block = self.documentMoveBlock(session.draft) {
                    session.view.showError(block.message)
                }
            case .success(let id?):
                self.finishSpaceCreation(session)
                self.presentation = session.originalPresentation
                self.presentation.reconcile(self.store.state) { self.ownership.canUse($0, owner: self.presentationID) }
                self.focusedTabID = self.presentation.preferredFocusedTabID
                self.selectSpace(id)
                session.window?.makeFirstResponder(self.sidebar)
            }
        }
    }

    private func documentMoveBlock(_ draft: SidebarNewSpaceDraft) -> InterProfileDocumentBlock? {
        guard draft.movesItemsAcrossProfiles else { return nil }
        return InterProfileDocumentBlock(moving: Set(draft.tabIDs), before: store.state, after: draft.applying(to: store.state))
    }

    private func chooseCreationIcon(_ session: SpaceCreationSession, from anchor: NSView) {
        guard creationOwnerIsCurrent(session), !session.committing, session.window?.attachedSheet == nil else { return }
        session.themePopover?.close(); session.iconPicker?.cancel()
        let picker = SidebarGroupIconPicker(selected: session.draft.customIcon, iconSet: .tabAndSpacePicker)
        picker.closesAfterChoice = true
        picker.isCurrent = { [weak self, weak session, weak picker] in
            guard let self, let session, let picker else { return false }
            return self.creationOwnerIsCurrent(session) && !session.committing && session.iconPicker === picker
        }
        picker.onCommit = { [weak self, weak session, weak picker] icon in
            guard let self, let session, let picker, session.iconPicker === picker,
                  self.creationOwnerIsCurrent(session), !session.committing else { return }
            session.draft.customIcon = icon; session.view.setIcon(icon)
        }
        picker.onFinish = { [weak session, weak picker] in
            guard let session, session.iconPicker === picker else { return }; session.iconPicker = nil
        }
        session.iconPicker = picker; picker.present(from: anchor)
    }

    func chooseCreationTheme(_ session: SpaceCreationSession, from anchor: NSView) {
        guard creationOwnerIsCurrent(session), !session.committing,
              anchor.window === window, window?.isKeyWindow == true, window?.attachedSheet == nil else { return }
        session.iconPicker?.cancel(); session.themePopover?.close()
        let editor = makeThemeEditor(theme: session.draft.theme)
        let update: (SpaceTheme) -> Void = { [weak self, weak session, weak editor] theme in
            guard let self, let session, let editor, session.themeEditor === editor,
                  self.creationOwnerIsCurrent(session), !session.committing else { return }
            session.draft.theme = theme; self.applyChromeTheme(theme)
        }
        editor.onPreview = update; editor.onCommit = update
        editor.onSetAppearance = { [weak self, weak session, weak editor] appearance in
            guard let self, let session, let editor, session.themeEditor === editor,
                  self.creationOwnerIsCurrent(session), !session.committing,
                  session.window?.attachedSheet == nil else { return }
            self.setThemeEditorAppearance(appearance)
        }
        let content = NSViewController(); content.view = editor
        let popover = NSPopover(); popover.contentViewController = content
        popover.contentSize = NSSize(width: 356, height: 508); popover.behavior = .transient; popover.delegate = self
        popover.animates = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        editor.onDismiss = { [weak popover] in popover?.performClose(nil) }
        session.themeEditor = editor; session.themePopover = popover
        popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .maxX)
        editor.window?.makeFirstResponder(editor)
    }

    func copyFolderLinks(_ target: FolderLinkTarget, format: FolderLinkFormat) {
        guard presentation.isReady, !isClosing, !wholeWindowClose,
              !windowClosePending, !windowCloseApproved,
              activeSpaceID == target.spaceID, activeProfileID == target.profileID,
              let links = FolderLinks.links(in: store.state, target: target) else { return }
        LinkPasteboard.write(links, format: format)
    }

    func prepareFolderDisclosureMenuItem(_ item: NSMenuItem, expanded: Bool,
                                         preservingTarget: Bool) -> Bool {
        if !preservingTarget { item.representedObject = FolderDisclosureTarget(owner: self, expanded: expanded) }
        return (item.representedObject as? FolderDisclosureTarget)?.isAvailable == true
    }

    func createFolder() { createFolder(in: activeSpaceID) }
    func createFolder(parentID: UUID) {
        guard let parent = store.state.folders.first(where: { $0.id == parentID }) else { return }
        createFolder(in: parent.spaceID, parent: parent)
    }
    func createFolder(in id: UUID, parent: BrowserFolder? = nil) {
        guard let expected = managementSpace(id), spaceCommandsAvailable, let window else { return }
        if id == activeSpaceID, libraryView == nil, activePeek == nil, !sidebar.isEditingTitle {
            let folderID: UUID?
            do {
                var container = parent
                if let parent, !parent.isExpanded {
                    _ = try store.setFolderExpanded(true, expected: parent, profileID: expected.profileID)
                    container = store.state.folders.first { $0.id == parent.id }
                    guard container != nil else { NSSound.beep(); return }
                }
                folderID = try store.createFolder(name: SidebarFolderFromItems.defaultName, in: expected, parent: container)
            } catch { showError(error); return }
            guard let folderID else { NSSound.beep(); return }
            render(store.state)
            sidebar.scrollItemToVisible(.folder(folderID))
            if !sidebar.beginFolderTitleEditing(folderID, untitled: true) { renameFolder(folderID) }
            return
        }
        prompt("New Folder", detail: parent.map { "Create a folder inside \($0.name)." } ?? "Organize pinned tabs in \(expected.name).",
               value: "", placeholder: "Folder name") { [weak self, weak window] name in
            guard let self, let window, self.window === window, self.managementSpace(id, profileID: expected.profileID) != nil else { return }
            do { _ = try self.store.createFolder(name: name, in: expected, parent: parent) }
            catch { showError(error) }
        }
    }
    func prepareFolderInlineRename(_ expected: BrowserFolder) -> ((String) -> Bool)? {
        guard let space = managementSpace(expected.spaceID), store.state.folders.contains(where: { $0.id == expected.id }) else { return nil }
        return { [weak self, weak window] name in
            guard let self, let window, self.window === window,
                  self.managementSpace(space.id, profileID: space.profileID) != nil else { return false }
            do { return try self.store.renameFolder(expected, profileID: space.profileID, name: name) }
            catch { showError(error); return false }
        }
    }
    func prepareFolderIconChange(_ expected: BrowserFolder) -> (() -> Bool)? {
        guard let space = managementSpace(expected.spaceID),
              store.state.folders.contains(where: { $0.id == expected.id }) else { return nil }
        var used = false
        return { [weak self] in
            guard let self, !used, let window = self.window, self.splitIconPicker == nil,
                  self.favoriteRename == nil, self.favoriteSplitRename == nil, !self.sidebar.isEditingTitle,
                  let anchor = self.sidebar.folderIconAnchor(expected.id), anchor.view.window === window else { return false }
            let picker = SidebarGroupIconPicker(selected: expected.customIcon, iconSet: .folderPicker)
            picker.isCurrent = { [weak self] in
                guard let self, self.managementSpace(space.id, profileID: space.profileID) != nil else { return false }
                return self.store.state.folders.contains { $0.id == expected.id && $0.spaceID == expected.spaceID }
            }
            picker.onCommit = { [weak self] icon in
                guard let self, let current = self.store.state.folders.first(where: { $0.id == expected.id }),
                      try self.store.setFolderIcon(icon, expected: current, profileID: space.profileID) else {
                    throw FolderIconError.unavailable
                }
            }
            picker.onFailure = { [weak self] in self?.showError($0) }
            picker.onFinish = { [weak self, weak picker] in
                guard let self, self.splitIconPicker === picker else { return }
                self.splitIconPicker = nil
            }
            used = true; self.splitIconPicker = picker
            picker.present(from: anchor.view, rect: anchor.rect)
            return self.splitIconPicker === picker
        }
    }
    func renameFolder(_ id: UUID) {
        guard let folder = store.state.folders.first(where: { $0.id == id }),
              let space = managementSpace(folder.spaceID), let window else { return }
        prompt("Rename folder", detail: "Choose a name for this group of tabs.", value: folder.name, placeholder: "Folder name") { [weak self, weak window] name in
            guard let self, let window, self.window === window,
                  self.managementSpace(space.id, profileID: space.profileID) != nil else { return }
            do { _ = try self.store.renameFolder(folder, profileID: space.profileID, name: name) }
            catch { showError(error) }
        }
    }
    private func turnSpaceIntoFolder(_ id: UUID, destinationID: UUID) {
        guard spaceCommandsAvailable, !folderUndo.isBusy, managementSpace(id) != nil,
              managementSpace(destinationID) != nil,
              let target = SpaceDeletionTarget(spaceID: id, state: store.state) else { return }
        let typed = target.tabs.filter { InternalPage(urlString: $0.savedURL) != nil }
        guard let documents = typed.isEmpty ? [:] : resolveSidebarCopyDestinations?(typed)?.documents,
              SidebarDocumentReference.validates(target.tabs, references: documents),
              let conversion = SpaceFolderConversion(source: id, destination: destinationID, state: store.state, documents: documents) else { return }
        if conversion.crossesProfiles {
            let proposal: (BrowserState) -> BrowserState? = { [weak self] state in
                guard let self, !self.isClosing, !self.wholeWindowClose, !self.windowClosePending else { return nil }
                return conversion.applying(to: state)?.0
            }
            _ = confirmInterProfileMove(tabCount: conversion.tabIDs.count,
                sourceProfiles: conversion.tabIDs.isEmpty ? [] : [target.space.profileID], destinationSpaceID: destinationID,
                moving: conversion.tabIDs, proposal: proposal) { [weak self] in
                guard let self, self.spaceCommandsAvailable, self.managementSpace(id, profileID: target.space.profileID) != nil else { return }
                let wasFocused = self.activeSpaceID == id
                self.store.moveAcrossProfiles(conversion.tabIDs, proposal: proposal) { [weak self] result in
                    guard let self else { return }
                    switch result {
                    case .success(true):
                        self.onInterProfileMoveCommitted?(conversion.tabIDs)
                        self.finishSpaceConversion(conversion, wasFocused: wasFocused)
                    case .success(false): self.explainRefusedInterProfileMove(conversion.tabIDs, proposal: proposal)
                    case .failure(let error): showError(error)
                    }
                }
            }
        } else {
            do {
                guard let validOwners = spaceConversionOwners(conversion), validOwners() else { return }
                let wasFocused = activeSpaceID == id, selection = selectedTabIDs, focus = focusedTabID
                guard let record = try store.convertSpaceToFolder(conversion) else { return }
                registerSpaceConversionUndo(record, wasFocused: wasFocused, selection: selection, focus: focus)
                finishSpaceConversion(conversion, wasFocused: wasFocused)
            } catch { showError(error) }
        }
    }
    private func spaceConversionOwners(_ conversion: SpaceFolderConversion) -> (() -> Bool)? {
        guard let owners = prepareSidebarSpaceMoveOwners?(conversion.tabIDs), owners(),
              conversion.tabIDs.isDisjoint(with: store.retiringTabIDs) else { return nil }
        let claims = Dictionary(uniqueKeysWithValues: conversion.tabIDs.map { ($0, ownership.claimSnapshot($0)) })
        guard claims.values.allSatisfy({ $0.transfer == nil }),
              conversion.target.groups.allSatisfy({ $0.tabIDs.allSatisfy { claims[$0]?.owner == nil || claims[$0]?.owner == presentationID } }) else { return nil }
        return { [weak self] in
            guard let self, !self.isClosing, owners(), conversion.tabIDs.isDisjoint(with: self.store.retiringTabIDs) else { return false }
            return conversion.tabIDs.allSatisfy { self.ownership.claimSnapshot($0) == claims[$0] }
        }
    }
    private func finishSpaceConversion(_ conversion: SpaceFolderConversion, wasFocused: Bool) {
        if wasFocused {
            presentation.selectSpace(conversion.destination.spaceID, state: store.state, available: { self.switcherCanUse($0) })
        }
        render(store.state); requestNativeSelection()
        if libraryView?.kind == .spaces { libraryView?.spaceManager.focusFirst() }
        else { showSidebarMoveNotice(item: .folder(conversion.folderID), space: conversion.destination.spaceID,
                                    profile: conversion.destination.profileID) }
    }
    private func registerSpaceConversionUndo(_ initial: SpaceFolderUndo, wasFocused: Bool, selection: [UUID], focus: UUID?) {
        var record = initial, focused = wasFocused, selected = selection, focusedTab = focus
        folderUndo.append(.init(name: "Turn into Folder", isValid: { [weak self] direction in
            guard let self else { return false }
            return direction == .undo ? record.restoring(in: self.store.state) != nil : record.redo(in: self.store.state) != nil
        }, isAvailable: { [weak self] _ in
            guard let self, self.windowUndoContextAvailable, record.documentsAreAvailable,
                  let owners = self.spaceConversionOwners(record.conversion) else { return false }
            return owners()
        }, perform: { [weak self] direction, done in
            guard let self, self.windowUndoContextAvailable, let owners = self.spaceConversionOwners(record.conversion), owners() else { done(false); return }
            do {
                switch direction {
                case .undo:
                    let restored = try self.store.undoSpaceFolderConversion(record)
                    if restored && focused {
                        self.presentation.restoreDeletedSpace(record.conversion.target.space.id, selection: selected, focus: focusedTab,
                            state: self.store.state, available: { self.switcherCanUse($0) })
                    }
                    if restored { self.render(self.store.state); self.requestNativeSelection() }
                    done(restored)
                case .redo:
                    guard let conversion = record.redo(in: self.store.state) else { done(false); return }
                    let wasFocused = self.activeSpaceID == conversion.target.space.id
                    let selection = self.selectedTabIDs, focus = self.focusedTabID
                    guard let next = try self.store.convertSpaceToFolder(conversion) else { done(false); return }
                    record = next; focused = wasFocused; selected = selection; focusedTab = focus
                    self.finishSpaceConversion(conversion, wasFocused: wasFocused); done(true)
                }
            } catch { showError(error); done(false) }
        }))
    }

    @discardableResult
    func deleteSpace(_ id: UUID, confirmingIn sheetWindow: NSWindow? = nil) -> Bool {
        guard let window, sheetWindow == nil ? spaceCommandsAvailable : (spaceStateAvailable && !isPrivateBrowsing),
              !folderUndo.isBusy, managementSpace(id) != nil,
              let target = SpaceDeletionTarget(spaceID: id, state: store.state),
              retirementUnavailableReason?(target.tabIDs) == nil else { return false }
        commandBar?.dismiss(); sidebar.cancelSpaceNameEditing(); spaceIconPicker?.cancel()
        let typed = target.tabs.filter { InternalPage(urlString: $0.savedURL) != nil }
        guard let documents = typed.isEmpty ? [:] : resolveSidebarCopyDestinations?(typed)?.documents,
              SidebarDocumentReference.validates(target.tabs, references: documents) else { return false }
        let wasFocused = activeSpaceID == id, selection = selectedTabIDs, focus = focusedTabID
        let unused = store.unusedProfile(ifDeletingSpace: id)
        let message = "This will archive all the tabs and folders inside it."
            + (unused == nil ? "" : " " + SpaceSharingWarning.deletionNote)
        let dialogWindow = sheetWindow ?? window
        return ParcDialog.confirm(in: dialogWindow, title: "Delete your “\(target.space.name)” Space?", message: message,
                                 confirm: "Delete", destructive: true) { [weak self, weak window] approved in
            DispatchQueue.main.async {
                guard approved, let self, let window, self.window === window else { return }
                if sheetWindow != nil {
                    window.makeKeyAndOrderFront(nil)
                }
                guard sheetWindow == nil ? self.spaceCommandsAvailable : (self.spaceStateAvailable && !self.isPrivateBrowsing),
                      !self.folderUndo.isBusy,
                      SpaceDeletionTarget(spaceID: id, state: self.store.state) == target,
                      self.store.unusedProfile(ifDeletingSpace: id) == unused else { return }
                self.performSpaceDeletion(target, documents: documents, wasFocused: wasFocused,
                    didCommit: { [weak self] record in
                        guard unused == nil else { return }
                        self?.registerSpaceDeletionUndo(SpaceUndoOperation(record: record,
                            wasFocused: wasFocused, selection: selection, focus: focus))
                    }, completion: { committed in
                        if committed, let unused { SpaceSharingConfirmation.handOff(unused) }
                    })
            }
        }
    }

    private func performSpaceDeletion(_ target: SpaceDeletionTarget,
                                      documents: [UUID: SidebarDocumentReference], wasFocused: Bool,
                                      didCommit: @escaping (SpaceDeletionUndo) -> Void,
                                      completion: @escaping (Bool) -> Void) {
        guard let window, retirementUnavailableReason?(target.tabIDs) == nil else { completion(false); return }
        var record: SpaceDeletionUndo?
        store.deleteSpace(target, documents: documents, shouldCommit: { [weak self, weak window] in
            guard let self, let window, self.window === window else { return false }
            return !self.isClosing && !self.wholeWindowClose && !self.windowClosePending
                && !self.windowCloseApproved && self.spaceCreation == nil
        }, didCommit: { value in record = value; didCommit(value) }) { [weak self, weak window] result in
            guard let self, let window, self.window === window else { completion(false); return }
            switch result {
            case .success(let committed):
                if committed, let record {
                    if wasFocused {
                        self.presentation.selectSpace(record.replacementSpaceID, state: self.store.state, available: { self.switcherCanUse($0) })
                    }
                    self.render(self.store.state)
                    if self.libraryView?.kind == .spaces { self.libraryView?.spaceManager.focusFirst() }
                    else if wasFocused { self.requestNativeSelection(); self.focusSelectedLocalContent() }
                }
                completion(committed)
            case .failure(let error): completion(false); showError(error)
            }
        }
    }

    private func registerSpaceDeletionUndo(_ operation: SpaceUndoOperation) {
        folderUndo.append(.init(name: "Delete Space", isValid: { [weak self] direction in
            guard let self else { return false }
            return direction == .undo ? self.store.canUndoSpaceDeletion(operation.record)
                : operation.record.redoTarget(in: self.store.state) != nil
                    && self.store.unusedProfile(ifDeletingSpace: operation.record.target.space.id) == nil
        }, isAvailable: { [weak self] direction in
            guard let self, self.windowUndoContextAvailable, operation.record.documentsAreAvailable,
                  operation.record.target.tabIDs.isDisjoint(with: self.store.retiringTabIDs) else { return false }
            return direction == .undo ? operation.record.target.tabIDs.allSatisfy { self.switcherCanUse($0) }
                : self.retirementUnavailableReason?(operation.record.target.tabIDs) == nil
        }, perform: { [weak self] direction, done in
            guard let self, self.windowUndoContextAvailable, let window else { done(false); return }
            switch direction {
            case .undo:
                do {
                    let restored = try self.store.undoSpaceDeletion(operation.record, shouldCommit: { [weak self, weak window] in
                        guard let self, let window, self.window === window, self.windowUndoContextAvailable else { return false }
                        return operation.record.target.tabIDs.allSatisfy { self.switcherCanUse($0) }
                    })
                    if restored, operation.wasFocused {
                        self.presentation.restoreDeletedSpace(operation.record.target.space.id,
                            selection: operation.selection, focus: operation.focus, state: self.store.state,
                            available: { self.switcherCanUse($0) })
                        self.render(self.store.state); self.requestNativeSelection(); self.focusSelectedLocalContent()
                    }
                    done(restored)
                } catch { done(false); showError(error) }
            case .redo:
                guard let target = operation.record.redoTarget(in: self.store.state) else { done(false); return }
                let wasFocused = self.activeSpaceID == target.space.id
                let selection = self.selectedTabIDs, focus = self.focusedTabID
                self.performSpaceDeletion(target, documents: operation.record.documents, wasFocused: wasFocused,
                    didCommit: {
                        operation.record = $0; operation.wasFocused = wasFocused
                        operation.selection = selection; operation.focus = focus
                    }, completion: done)
            }
        }))
    }

    func managementSpace(_ id: UUID, profileID: UUID? = nil) -> BrowserSpace? {
        guard !isPrivateBrowsing, !store.isEphemeral, !isPopupWindow, presentation.isReady,
              !isClosing, !wholeWindowClose, !windowClosePending, !windowCloseApproved,
              nativeFullscreenTabID == nil, spaceCreation == nil,
              transferringTabIDs.isEmpty, resolvingTransfers.isEmpty, closingTabIDs.isEmpty,
              modelRetirementIDs.isEmpty, collectionTransfer == nil,
              let space = store.state.spaces.first(where: { $0.id == id && (profileID == nil || $0.profileID == profileID) }),
              store.state.profiles.contains(where: { $0.id == space.profileID }),
              !store.isProfileRemovalPending(space.profileID) else { return nil }
        return space
    }

    func spaceManagementMenu(_ id: UUID) -> SidebarSpaceMenu? {
        guard let expected = managementSpace(id) else { return nil }
        let valid: () -> Bool = { [weak self] in
            guard let self else { return false }
            return self.spaceCommandsAvailable && self.managementSpace(id, profileID: expected.profileID) != nil
        }
        let choose: (SpaceDataSharing) -> Void = { [weak self] sharing in
            guard let self, valid() else { return }
            self.commandBar?.dismiss()
            guard let window = self.window else { return }
            let ownerValid: () -> Bool = { [weak self, weak window] in
                guard let self, let window, self.window === window else { return false }
                return !self.isClosing && !self.wholeWindowClose && !self.windowClosePending
                    && !self.windowCloseApproved && self.spaceCreation == nil
            }
            SpaceSharingConfirmation.present(on: window, store: self.store, spaceID: id, sharing: sharing,
                ownerValid: ownerValid, explain: { [weak self] block in
                    guard let self, ownerValid() else { return }
                    self.showDocumentMoveBlock(block)
                }, completion: { [weak self] result in
                    if case .failure(let error) = result { self?.showError(error) }
                })
        }
        let others = store.state.spaces.filter { $0.id != id }
        let shareData = others.map { other in
            (name: other.name, shared: other.profileID == expected.profileID,
             action: store.isProfileRemovalPending(other.profileID) ? nil : { choose(.share(withSpace: other.id)) } as (() -> Void)?)
        }
        return SidebarSpaceMenu(includesManagement: true, changeIcon: { [weak self] in if valid() { self?.changeSpaceIcon(id) } },
            shareData: shareData,
            keepSeparate: (selected: !shareData.contains { $0.shared }, action: { choose(.separate) }),
            delete: store.state.spaces.count > 1 ? { [weak self] in if valid() { self?.deleteSpace(id) } } : nil,
            manage: { [weak self] in if valid() { self?.showLibrary(.spaces) } },
            turnIntoFolder: store.state.spaces.filter { $0.id != id }.map { destination in
                (name: destination.name, action: store.isProfileRemovalPending(destination.profileID) ? nil : { [weak self] in
                    guard let self, valid(), self.managementSpace(destination.id, profileID: destination.profileID) != nil else { return }
                    self.turnSpaceIntoFolder(id, destinationID: destination.id)
                })
            },
            rename: { [weak self] in if valid() { self?.renameSpace(id) } },
            editTheme: { [weak self] in if valid() { self?.editTheme(spaceID: id) } },
            newFolder: { [weak self] in if valid() { self?.createFolder(in: id) } }, toggleTitle: SidebarChromeLayout.SpaceHeader.toggleTitle(spaceCount: store.state.spaces.count,
                titled: expected.title != nil, customIcon: expected.customIcon != nil,
                showOnSingleUnnamedSpace: store.state.settings.showSpaceHeaderOnSingleUnnamedSpaces ?? false),
            toggleHeader: { [weak self] in if valid() { self?.store.toggleSpaceHeaderOnSingleUnnamedSpaces() } })
    }

    func renameSpace(_ id: UUID) {
        guard let expected = managementSpace(id), spaceCommandsAvailable, let window else { return }
        commandBar?.dismiss()
        guard spaceCommandsAvailable else { return }
        let managerSidebar = libraryView?.kind == .spaces ? libraryView?.spaceManager.sidebar(for: id) : nil
        if id != activeSpaceID && managerSidebar == nil {
            let dialog = ParcDialog(.init(title: [("Rename Space", false)], confirm: "Save", cancel: "Cancel",
                field: .init(value: expected.title ?? "", placeholder: expected.name, required: false)))
            guard let field = dialog.textField else { return }
            _ = dialog.begin(for: window, queued: true) { [weak self, weak window] response in
                guard response == .confirm, let self, let window, self.window === window,
                      self.managementSpace(id, profileID: expected.profileID) != nil else { return }
                do { try self.store.saveSpaceTitle(expected, title: field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)) }
                catch { if (error as NSError).code != CocoaError.userCancelled.rawValue { showError(error) } }
            }
            return
        }
        guard PCNativeBrowserApplication.canPresentTabSwitcher(in: window),
              managementSpace(id, profileID: expected.profileID)?.title == expected.title else { return }
        spaceIconPicker?.cancel()
        if managerSidebar == nil { closeLibrary(restoreFocus: false); revealSidebarForEditing() }
        let editingSidebar = managerSidebar ?? sidebar
        _ = editingSidebar.beginSpaceNameEditing(expected) { [weak self, weak window, weak editingSidebar] value in
            guard let self, let window, self.window === window else { return }
            if let value, self.managementSpace(id, profileID: expected.profileID) != nil,
               (self.activeSpaceID == id || self.libraryView?.spaceManager.sidebar(for: id) === editingSidebar) {
                do { try self.store.saveSpaceTitle(expected, title: value.trimmingCharacters(in: .whitespacesAndNewlines)) }
                catch { if (error as NSError).code != CocoaError.userCancelled.rawValue { showError(error) } }
            }
            self.render(self.store.state)
        }
    }

    func changeSpaceIcon(_ id: UUID) {
        guard spaceIconPicker == nil, let expected = managementSpace(id),
              spaceCommandsAvailable, let window else { return }
        commandBar?.dismiss(); sidebar.cancelSpaceNameEditing()
        let manager = libraryView?.kind == .spaces ? libraryView?.spaceManager : nil
        if manager == nil { closeLibrary(restoreFocus: false); revealSidebarForEditing() }
        guard self.window === window, spaceCommandsAvailable,
              let actual = managementSpace(id, profileID: expected.profileID), actual.customIcon == expected.customIcon,
              let anchor = manager?.anchor(for: id) ?? sidebar.spaceAppearanceAnchor(id), anchor.window === window else { return }
        let picker = SidebarGroupIconPicker(selected: expected.customIcon, iconSet: .tabAndSpacePicker)
        var current = expected
        picker.isCurrent = { [weak self, weak window, weak picker] in
            guard let self, let window, let picker, self.window === window,
                  self.spaceIconPicker === picker,
                  SplitCustomizationFocus.isHeld(window: window, presentation: picker.presentationWindow),
                  let actual = self.managementSpace(id, profileID: current.profileID) else { return false }
            return actual.customIcon == current.customIcon
        }
        picker.onCommit = { [weak self, weak picker] icon in
            guard let self, let picker, picker.isCurrent() else { throw CocoaError(.userCancelled) }
            try self.store.saveSpaceIcon(current, icon: icon)
            current.customIcon = icon
        }
        picker.onFinish = { [weak self, weak picker] in
            guard let self, self.spaceIconPicker === picker else { return }
            self.spaceIconPicker = nil
            self.refreshSidebarPointerIfKey()
        }
        picker.onFailure = { [weak self] in self?.showError($0) }
        spaceIconPicker = picker
        picker.present(from: anchor)
    }

    func prompt(_ title: String, detail: String, value: String, placeholder: String, accept: @escaping (String) -> Void) {
        guard let window else { return }
        let dialog = ParcDialog(.init(title: [(title, false)], message: [(detail, false)], confirm: "Save", cancel: "Cancel",
                                     field: .init(value: value, placeholder: placeholder)))
        guard let field = dialog.textField else { return }
        _ = dialog.begin(for: window, queued: true) { response in
            let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if response == .confirm && !name.isEmpty { accept(name) }
        }
    }

    var downloadStore: BrowserStore { downloadCatalog ?? store }
}
