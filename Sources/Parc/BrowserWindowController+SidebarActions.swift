import AppKit
import Combine
import ParcCore
import ParcEngine

extension BrowserWindowController {
    func prepareSidebarTabMute(_ expected: BrowserTab, audio: SidebarTabAudio) -> (() -> Bool)? {
        guard canPerformSidebarTabAction(expected, closing: false), let browser = browsers[expected.id],
              let page = browser.nativePage, !page.isClosed else { return nil }
        var used = false
        return { [weak self, weak browser, weak page] in
            guard let self, let browser, let page, !used,
                  self.canPerformSidebarTabAction(expected, closing: false),
                  self.browsers[expected.id] === browser, browser.nativePage === page,
                  browser.window === self.window, !page.isClosed,
                  page.responds(to: #selector(PCNativePage.toggleTabAudioMuted(_:))) else { return false }
            used = true
            return page.toggleTabAudioMuted(audio.lease)
        }
    }

    func canPerformSidebarTabAction(_ expected: BrowserTab, closing: Bool) -> Bool {
        guard sidebarTabActionWindowAvailable,
              window?.isKeyWindow == true,
              expected.profileID == activeProfileID, visibleTabs.contains(expected),
              PageReparenting.rowAction(closing: closing, busy: !sidebarTabActionAvailable(expected.id),
                  usableHere: closing ? ownership.canUse(expected.id, owner: presentationID) : switcherCanUse(expected.id),
                  heldElsewhere: canMovePageHere(expected.id)) != nil else { return false }
        return !closing || retirementUnavailableReason?([expected.id]) == nil
    }

    private var sidebarTabActionWindowAvailable: Bool {
        !isPopupWindow && presentation.isReady && !isClosing && !wholeWindowClose
            && !windowClosePending && !windowCloseApproved && nativeFullscreenTabID == nil
            && window?.attachedSheet == nil && !store.isProfileRemovalPending(activeProfileID)
    }

    private func sidebarTabActionAvailable(_ id: UUID) -> Bool {
        !closingTabIDs.contains(id) && !transferringTabIDs.contains(id) && !resolvingTransfers.contains(id)
            && transferRecoveries[id] == nil && !store.retiringTabIDs.contains(id)
    }

    func sidebarRootsCloseAvailable(_ ids: Set<UUID>, movingHere: Bool = true) -> Bool {
        guard sidebarTabActionWindowAvailable, commandBar == nil, !ids.isEmpty,
              ids.allSatisfy({ id in
                  visibleTabs.contains { $0.id == id }
                      && PageReparenting.rowAction(closing: true, busy: !sidebarTabActionAvailable(id),
                          usableHere: switcherCanUse(id), heldElsewhere: movingHere && canMovePageHere(id)) != nil
              })
        else { return false }
        return retirementUnavailableReason?(ids) == nil
    }

    private var currentRenameTab: BrowserTab? {
        SidebarTabTitle.currentRenameTab(state: store.state, spaceID: activeSpaceID,
            profileID: activeProfileID, selectedTabIDs: selectedTabIDs)
    }

    private var currentRenameSplit: SidebarSplitTitleEdit? {
        SidebarSplitTitleEdit.current(state: store.state, spaceID: activeSpaceID,
            profileID: activeProfileID, selectedTabIDs: selectedTabIDs)
    }

    var canRenameCurrentItem: Bool {
        guard spaceCommandsAvailable, activePeek == nil, !sidebar.isEditingTitle else { return false }
        if let target = currentRenameSplit {
            return target.children.allSatisfy { canPerformSidebarTabAction($0, closing: false) }
        }
        guard let tab = currentRenameTab, !InternalPage.isInternal(tab.url) else { return false }
        return canPerformSidebarTabAction(tab, closing: false)
    }

    func renameCurrentItem() {
        if let target = currentRenameSplit { renameCurrentSplit(target); return }
        guard canRenameCurrentItem, let expected = currentRenameTab else { return }
        commandBar?.dismiss()
        guard canRenameCurrentItem, let current = currentRenameTab,
              SidebarTabTitle.sameItemForEditing(current, expected),
              let window, PCNativeBrowserApplication.canPresentTabSwitcher(in: window),
              canPerformSidebarTabAction(current, closing: false) else { return }
        if !store.isEphemeral {
            guard let reveal = SidebarItemReveal(item: .tab(current.id), spaceID: activeSpaceID,
                profileID: activeProfileID, state: store.state) else { return }
            do { guard try store.revealSidebarItem(reveal) else { return } }
            catch { showError(error); return }
        }
        closeLibrary(restoreFocus: false)
        render(store.state)
        revealSidebarForEditing()
        guard let target = currentRenameTab, SidebarTabTitle.sameItemForEditing(target, expected),
              canPerformSidebarTabAction(target, closing: false) else { return }
        _ = sidebar.beginTitleEditing(target)
    }

    var currentSidebarMenuItems: [SidebarItemReference]? {
        if let selection = sidebar.commandBarSelectionItems() { return selection }
        guard activePeek == nil, let id = currentTabID else { return nil }
        if let group = SidebarSplitItems.groups(in: store.state, spaceID: activeSpaceID).first(where: { $0.tabIDs.contains(id) }) {
            return [.split(group.id)]
        }
        return [.tab(id)]
    }
    var canDuplicateCurrentItem: Bool {
        commandBar == nil && currentSidebarMenuItems.flatMap { prepareSidebarDuplicate($0) } != nil
    }
    func duplicateCurrentItem() {
        guard commandBar == nil, let items = currentSidebarMenuItems,
              let duplicate = prepareSidebarDuplicate(items) else { return }
        _ = duplicate()
    }

    func revealSidebarForEditing() {
        if sidebarPresentation == .hidden { setSidebarPresentation(.floating) }
        settleSidebarMotion(); layoutChrome(); rootView.layoutSubtreeIfNeeded()
    }

    private func renameCurrentSplit(_ expected: SidebarSplitTitleEdit) {
        guard canRenameCurrentItem else { return }
        commandBar?.dismiss()
        if expected.isFavorite { _ = prepareFavoriteSplitRename(expected)?(); return }
        guard canRenameCurrentItem, currentRenameSplit == expected,
              let window, PCNativeBrowserApplication.canPresentTabSwitcher(in: window),
              expected.children.allSatisfy({ canPerformSidebarTabAction($0, closing: false) }) else { return }
        if !store.isEphemeral {
            guard let reveal = SidebarItemReveal(item: .split(expected.group.id), spaceID: activeSpaceID,
                profileID: activeProfileID, state: store.state) else { return }
            do { guard try store.revealSidebarItem(reveal) else { return } }
            catch { showError(error); return }
        }
        closeLibrary(restoreFocus: false)
        render(store.state)
        revealSidebarForEditing()
        guard currentRenameSplit == expected,
              expected.children.allSatisfy({ canPerformSidebarTabAction($0, closing: false) }) else { return }
        _ = sidebar.beginTitleEditing(expected)
    }

    func prepareSidebarSplitTitleEdit(_ expected: SidebarSplitTitleEdit) -> ((String) -> Bool)? {
        guard !folderUndo.isBusy, expected.group.spaceID == activeSpaceID, expected.profileID == activeProfileID,
              expected.matches(store.state), activePeek == nil,
              expected.children.allSatisfy({ canPerformSidebarTabAction($0, closing: false) }) else { return nil }
        let leases: [() -> Bool] = expected.children.map { original in
            let browser = browsers[original.id], page = browser?.nativePage
            let note = noteEditors[original.id]?.editor, easel = easelEditors[original.id]?.editor
            let hadBrowser = browser != nil, hadPage = page != nil
            let hadNote = note != nil, hadEasel = easel != nil
            return { [weak self, weak browser, weak page, weak note, weak easel] in
                guard let self,
                      let current = self.visibleTabs.first(where: { $0.id == original.id }),
                      SidebarTabTitle.sameItemForEditing(current, original),
                      self.canPerformSidebarTabAction(current, closing: false),
                      (self.browsers[original.id] != nil) == hadBrowser,
                      (self.noteEditors[original.id]?.editor != nil) == hadNote,
                      (self.easelEditors[original.id]?.editor != nil) == hadEasel else { return false }
                if hadBrowser {
                    guard let browser, self.browsers[original.id] === browser,
                          (browser.nativePage != nil) == hadPage else { return false }
                    if hadPage { guard let page, browser.nativePage === page, !page.isClosed else { return false } }
                }
                if hadNote { guard let note, self.noteEditors[original.id]?.editor === note else { return false } }
                if hadEasel { guard let easel, self.easelEditors[original.id]?.editor === easel else { return false } }
                return true
            }
        }
        var used = false
        return { [weak self] title in
            guard let self, !used, !self.folderUndo.isBusy, self.activeSpaceID == expected.group.spaceID,
                  self.activeProfileID == expected.profileID, expected.matches(self.store.state),
                  self.activePeek == nil, leases.allSatisfy({ $0() }) else { return false }
            used = true
            do {
                if let change = try self.store.saveSidebarSplitTitle(expected, title: title) {
                    self.folderUndo.appendSplitTitleChange(change, store: self.store, available: { [weak self] in
                        guard let self, self.windowUndoContextAvailable,
                              self.activeProfileID == change.profileID else { return false }
                        return true
                    }, onError: { [weak self] in self?.showError($0) })
                }
                return true
            } catch { showError(error); return false }
        }
    }

    func prepareSidebarTitleEdit(_ expected: BrowserTab) -> ((String) -> Bool)? {
        guard !folderUndo.isBusy, SidebarTabTitle.isRenameable(expected),
              canPerformSidebarTabAction(expected, closing: false) else { return nil }
        let space = activeSpaceID, browser = browsers[expected.id], page = browser?.nativePage
        let hadBrowser = browser != nil, hadPage = page != nil
        let group = store.state.splitLayouts.first { $0.tabIDs.contains(expected.id) }
        var used = false
        return { [weak self, weak browser, weak page] title in
            guard let self, !used, !self.folderUndo.isBusy, self.activeSpaceID == space,
                  let current = self.visibleTabs.first(where: { $0.id == expected.id }),
                  SidebarTabTitle.sameItemForEditing(current, expected),
                  self.canPerformSidebarTabAction(current, closing: false),
                  !InternalPage.isInternal(current.url),
                  self.store.state.splitLayouts.first(where: { $0.tabIDs.contains(expected.id) }) == group,
                  (self.browsers[expected.id] != nil) == hadBrowser else { return false }
            if hadBrowser {
                guard let browser, self.browsers[expected.id] === browser,
                      (browser.nativePage != nil) == hadPage else { return false }
                if hadPage { guard let page, browser.nativePage === page, !page.isClosed else { return false } }
            }
            used = true
            do {
                if let change = try self.store.saveSidebarTitle(expected, title: title) {
                    self.folderUndo.appendTabTitleChange(change, store: self.store, available: { [weak self] in
                        guard let self, self.windowUndoContextAvailable,
                              self.activeProfileID == change.profileID else { return false }
                        return true
                    }, onError: { [weak self] in self?.showError($0) })
                }
                return true
            } catch { showError(error); return false }
        }
    }


    private func splitCustomizationOwner(_ expected: SidebarSplitTitleEdit,
        presentationWindow: @escaping () -> NSWindow? = { nil },
        current: @escaping () -> SidebarSplitTitleEdit? = { nil }) -> (() -> Bool)? {
        guard !folderUndo.isBusy, expected.profileID == activeProfileID,
              expected.isVisible(in: activeSpaceID, state: store.state), expected.matches(store.state),
              activePeek == nil, let window,
              PCNativeBrowserApplication.canPresentTabSwitcher(in: window),
              expected.children.allSatisfy({ canPerformSidebarTabAction($0, closing: false) }) else { return nil }
        let space = activeSpaceID, selection = selectedTabIDs, focus = focusedTabID
        let leases: [() -> Bool] = expected.children.map { original in
            let browser = browsers[original.id], page = browser?.nativePage
            let note = noteEditors[original.id]?.editor, easel = easelEditors[original.id]?.editor
            let hadBrowser = browser != nil, hadPage = page != nil, hadNote = note != nil, hadEasel = easel != nil
            return { [weak self, weak browser, weak page, weak note, weak easel] in
                guard let self, self.ownership.canUse(original.id, owner: self.presentationID),
                      !self.closingTabIDs.contains(original.id), !self.transferringTabIDs.contains(original.id),
                      !self.resolvingTransfers.contains(original.id), self.transferRecoveries[original.id] == nil,
                      !self.store.retiringTabIDs.contains(original.id), !self.modelRetirementIDs.contains(original.id),
                      (self.browsers[original.id] != nil) == hadBrowser,
                      (self.noteEditors[original.id]?.editor != nil) == hadNote,
                      (self.easelEditors[original.id]?.editor != nil) == hadEasel else { return false }
                if hadBrowser {
                    guard let browser, self.browsers[original.id] === browser, (browser.nativePage != nil) == hadPage else { return false }
                    if hadPage { guard let page, browser.nativePage === page, !page.isClosed else { return false } }
                }
                if hadNote { guard let note, self.noteEditors[original.id]?.editor === note else { return false } }
                if hadEasel { guard let easel, self.easelEditors[original.id]?.editor === easel else { return false } }
                return true
            }
        }
        return { [weak self, weak window] in
            guard let self, let window, self.window === window,
                  !self.isClosing, !self.wholeWindowClose, !self.windowClosePending, !self.windowCloseApproved,
                  self.presentation.isReady, self.nativeFullscreenTabID == nil, self.activePeek == nil,
                  !self.folderUndo.isBusy, self.activeSpaceID == space, self.activeProfileID == expected.profileID,
                  self.selectedTabIDs == selection, self.focusedTabID == focus,
                  (current() ?? expected).matches(self.store.state), leases.allSatisfy({ $0() }) else { return false }
            return SplitCustomizationFocus.isHeld(window: window, presentation: presentationWindow())
        }
    }

    func prepareFavoriteSplitRename(_ expected: SidebarSplitTitleEdit) -> (() -> Bool)? {
        guard expected.isFavorite, favoriteSplitRename == nil, favoriteRename == nil, splitIconPicker == nil,
              splitCustomizationOwner(expected) != nil else { return nil }
        let space = activeSpaceID
        var used = false
        return { [weak self] in
            guard let self, !used, self.activeSpaceID == space, let window = self.window,
                  self.splitCustomizationOwner(expected) != nil,
                  let anchor = expected.group.sidebarAnchorID else { return false }
            self.selectTab(anchor)
            guard self.selectedTabIDs == expected.group.tabIDs,
                  let dialogOwner = self.splitCustomizationOwner(expected, presentationWindow: { [weak self] in self?.favoriteSplitRename?.sheetWindow }) else { return false }
            used = true
            let title = expected.group.customTitle ?? expected.children.map(SidebarTabTitle.display).joined(separator: " / ")
            let dialog = FavoriteRenameDialog(title: title)
            dialog.isCurrent = dialogOwner
            dialog.onCommit = { [weak self] title in
                guard let self, dialogOwner() else { throw SidebarSplitTitleEdit.EditError.unavailable }
                if let change = try self.store.saveSidebarSplitTitle(expected, title: title) {
                    self.folderUndo.appendSplitTitleChange(change, store: self.store,
                        available: { [weak self] in self?.windowUndoContextAvailable == true && self?.activeProfileID == change.profileID },
                        onError: { [weak self] in self?.showError($0) })
                }
            }
            dialog.onFinish = { [weak self, weak dialog] in
                guard let self, self.favoriteSplitRename === dialog else { return }
                self.favoriteSplitRename = nil
                if self.activeSpaceID == space, self.selectedTabIDs == expected.group.tabIDs {
                    self.requestNativeSelection(); self.focusSelectedLocalContent()
                }
            }
            self.favoriteSplitRename = dialog; dialog.present(in: window)
            return self.favoriteSplitRename === dialog
        }
    }

    func prepareSplitAppearance(_ expected: SidebarSplitTitleEdit, reset: Bool) -> (() -> Bool)? {
        guard favoriteSplitRename == nil, favoriteRename == nil, splitIconPicker == nil,
              !sidebar.isEditingTitle, let valid = splitCustomizationOwner(expected),
              !reset || expected.group.customTitle != nil || expected.group.customIcon != nil else { return nil }
        var used = false
        return { [weak self] in
            guard let self, !used, valid() else { return false }
            if reset {
                used = true
                do { try self.commitSplitAppearance(expected, icon: nil, reset: true); return true }
                catch { showError(error); return false }
            }
            guard let anchor = self.sidebar.appearanceAnchor(for: expected.group), anchor.window === self.window else { return false }
            let picker = SidebarGroupIconPicker(selected: expected.group.customIcon, iconSet: .tabAndSpacePicker)
            var current = expected
            guard let owner = self.splitCustomizationOwner(expected, presentationWindow: { [weak picker] in picker?.presentationWindow },
                                                           current: { current }) else { return false }
            picker.isCurrent = owner
            picker.onCommit = { [weak self] icon in
                guard let self, owner() else { throw SidebarSplitTitleEdit.EditError.unavailable }
                try self.commitSplitAppearance(current, icon: icon)
                if let group = self.store.state.splitLayouts.first(where: { $0.id == current.group.id }),
                   let next = SidebarSplitTitleEdit(group: group, profileID: current.profileID, state: self.store.state) { current = next }
            }
            picker.onFailure = { [weak self] in self?.showError($0) }
            picker.onFinish = { [weak self, weak picker] in
                guard let self, self.splitIconPicker === picker else { return }
                self.splitIconPicker = nil
            }
            used = true; self.splitIconPicker = picker
            let rect = (anchor as? SidebarSplitGroupView)?.appearanceAnchorRect ?? anchor.bounds
            let host = anchor.enclosingScrollView?.documentView ?? anchor
            picker.present(from: host, rect: host.convert(rect, from: anchor))
            return self.splitIconPicker === picker
        }
    }

    private func commitSplitAppearance(_ expected: SidebarSplitTitleEdit, icon: SidebarGroupIcon?, reset: Bool = false) throws {
        if let change = try store.saveSplitAppearance(expected, icon: icon, reset: reset) {
            folderUndo.appendSplitAppearance(change, store: store,
                available: { [weak self] in self?.windowUndoContextAvailable == true && self?.activeProfileID == change.profileID },
                onError: { [weak self] in self?.showError($0) })
        }
    }

    func prepareFavoriteRename(_ expected: BrowserTab, selectOriginal: Bool = true) -> (() -> Bool)? {
        guard favoriteRename == nil, !folderUndo.isBusy, !sidebar.isEditingTitle,
              !isPrivateBrowsing, expected.kind == .favorite,
              let window, let binding = nativeBinding, binding.window === window,
              !binding.isPrivateBrowsing, binding.browsingContextKind != .mixed,
              PCNativeBrowserApplication.canPresentTabSwitcher(in: window),
              canPerformSidebarTabAction(expected, closing: false) else { return nil }
        let space = activeSpaceID
        var used = false
        return { [weak self, weak window, weak binding] in
            guard let self, let window, let binding, !used, self.activeSpaceID == space,
                  self.window === window, self.nativeBinding === binding, binding.window === window,
                  PCNativeBrowserApplication.canPresentTabSwitcher(in: window),
                  self.favoriteRename == nil, !self.folderUndo.isBusy,
                  let current = self.visibleTabs.first(where: { $0.id == expected.id }),
                  SidebarTabTitle.sameItemForEditing(current, expected) else { return false }
            if selectOriginal {
                guard let activate = self.prepareFavoriteAction(current, closing: false), activate() else { return false }
            }
            guard window.attachedSheet == nil, self.selectedTabIDs == [expected.id] else { return false }
            used = true
            let browser = self.browsers[expected.id], page = browser?.nativePage
            let hadBrowser = browser != nil, hadPage = page != nil
            let note = self.noteEditors[expected.id]?.editor, easel = self.easelEditors[expected.id]?.editor
            let hadNote = note != nil, hadEasel = easel != nil
            let dialog = FavoriteRenameDialog(title: SidebarTabTitle.display(current))
            dialog.isCurrent = { [weak self, weak window, weak binding, weak dialog, weak browser, weak page, weak note, weak easel] in
                guard let self, let window, let binding, let dialog,
                      self.window === window, self.favoriteRename === dialog,
                      self.nativeBinding === binding, binding.window === window,
                      !binding.isPrivateBrowsing, binding.browsingContextKind != .mixed,
                      self.presentation.isReady, !self.isClosing, !self.wholeWindowClose,
                      !self.windowClosePending, !self.windowCloseApproved, self.nativeFullscreenTabID == nil,
                      self.activeSpaceID == space, self.activeProfileID == expected.profileID,
                      self.selectedTabIDs == [expected.id], self.activePeek == nil,
                      self.commandBar == nil, !self.folderUndo.isBusy,
                      !self.store.isProfileRemovalPending(expected.profileID),
                      !self.closingTabIDs.contains(expected.id), !self.transferringTabIDs.contains(expected.id),
                      !self.resolvingTransfers.contains(expected.id), self.transferRecoveries[expected.id] == nil,
                      !self.store.retiringTabIDs.contains(expected.id), !self.modelRetirementIDs.contains(expected.id),
                      self.ownership.canUse(expected.id, owner: self.presentationID),
                      let tab = self.visibleTabs.first(where: { $0.id == expected.id }),
                      SidebarTabTitle.sameItemForEditing(tab, expected),
                      (self.browsers[expected.id] != nil) == hadBrowser,
                      (self.noteEditors[expected.id]?.editor != nil) == hadNote,
                      (self.easelEditors[expected.id]?.editor != nil) == hadEasel,
                      window.attachedSheet == nil || window.attachedSheet === dialog.sheetWindow else { return false }
                if hadBrowser {
                    guard let browser, self.browsers[expected.id] === browser,
                          (browser.nativePage != nil) == hadPage else { return false }
                    if hadPage { guard let page, browser.nativePage === page, !page.isClosed else { return false } }
                }
                if hadNote { guard let note, self.noteEditors[expected.id]?.editor === note else { return false } }
                if hadEasel { guard let easel, self.easelEditors[expected.id]?.editor === easel else { return false } }
                return true
            }
            dialog.onCommit = { [weak self] title in
                guard let self else { throw SidebarTabTitle.EditError.unavailable }
                if let change = try self.store.saveFavoriteTitle(expected, title: title) {
                    self.folderUndo.appendTabTitleChange(change, store: self.store, available: { [weak self] in
                        guard let self, self.windowUndoContextAvailable,
                              self.activeProfileID == change.profileID else { return false }
                        return true
                    }, onError: { [weak self] in self?.showError($0) })
                }
            }
            dialog.onFinish = { [weak self, weak dialog] in
                guard let self, self.favoriteRename === dialog else { return }
                self.favoriteRename = nil
                if self.selectedTabIDs == [expected.id], self.activeSpaceID == space {
                    self.requestNativeSelection(); self.focusSelectedLocalContent()
                }
            }
            self.favoriteRename = dialog
            dialog.present(in: window)
            return self.favoriteRename === dialog
        }
    }

    func prepareFavoritePointerAction(_ expected: BrowserTab,
                                             intent: FavoritePointerAction) -> (() -> Bool)? {
        guard expected.kind == .favorite, !isPrivateBrowsing else { return nil }
        if intent == .activate { return prepareFavoriteActivation(expected) }
        if intent == .openInSplit { return prepareFavoriteOptionRelease(expected) }
        let force = intent == .resetAndSelect
        guard let reset = prepareSavedTabReset(expected, allowUnchanged: force) else { return nil }
        if force && prepareFavoriteAction(expected, closing: false) == nil { return nil }
        return { [weak self] in
            guard let self, reset() else { return false }
            if force {
                guard let current = self.visibleTabs.first(where: { $0.id == expected.id }),
                      current.profileID == expected.profileID, current.kind == .favorite,
                      current.createdAt == expected.createdAt, current.savedURL == expected.savedURL,
                      let select = self.prepareFavoriteAction(current, closing: false) else { return false }
                return select()
            }
            return true
        }
    }

    func prepareFavoriteActivation(_ expected: BrowserTab) -> (() -> Bool)? {
        prepareFavoriteTransferOffer(expected) ?? prepareFavoriteAction(expected, closing: false)
    }

    private func favoritePanes(_ expected: BrowserTab) -> [UUID] {
        SidebarSplitItems.groups(in: store.state, spaceID: activeSpaceID)
            .first { $0.tabIDs.contains(expected.id) }?.tabIDs ?? [expected.id]
    }

    private func currentFavorite(_ expected: BrowserTab) -> BrowserTab? {
        visibleTabs.first { $0.id == expected.id && $0.kind == .favorite
            && $0.profileID == expected.profileID && $0.createdAt == expected.createdAt }
    }

    private func canOfferFavoriteTransfer(_ expected: BrowserTab) -> Bool {
        expected.kind == .favorite && !isPrivateBrowsing && !isPopupWindow && presentation.isReady
            && !isClosing && !wholeWindowClose && !windowClosePending && !windowCloseApproved
            && nativeFullscreenTabID == nil && window?.isKeyWindow == true
            && window?.attachedSheet == nil && onRequestTabTransfer != nil
            && expected.profileID == activeProfileID && !store.isProfileRemovalPending(expected.profileID)
            && visibleTabs.contains(expected)
    }

    func canMovePageHere(_ id: UUID) -> Bool {
        guard !isPopupWindow, !closingTabIDs.contains(id), !transferringTabIDs.contains(id), !resolvingTransfers.contains(id),
              transferRecoveries[id] == nil, !store.retiringTabIDs.contains(id),
              let owner = ownership.owner(of: id), owner != presentationID else { return false }
        if case .none = tabHolder?(id, self) ?? .none { return false }
        return true
    }

    func holdsEmptyClaim(_ id: UUID) -> Bool {
        !isPopupWindow && !isClosing && claimsTab(id)
            && browsers[id] == nil && noteEditors[id] == nil && easelEditors[id] == nil
            && !transferringTabIDs.contains(id) && !closingTabIDs.contains(id) && !modelRetirementIDs.contains(id)
            && !store.retiringTabIDs.contains(id) && pendingSearchNavigations[id] == nil
    }
    func handOverEmptyClaim(_ id: UUID, to destination: BrowserWindowController) -> Bool {
        guard destination !== self, destination.store === store, !destination.isPopupWindow, holdsEmptyClaim(id) else { return false }
        ownership.release(id, owner: presentationID)
        guard ownership.claim(id, owner: destination.presentationID) else {
            _ = ownership.claim(id, owner: presentationID); return false
        }
        presentation.leavePlaceholder(id, state: store.state)
        failures.removeValue(forKey: id); easelFailures.removeValue(forKey: id)
        if focusedTabID == id { focusedTabID = presentation.preferredFocusedTabID }
        if !rendering { render(store.state) }
        return true
    }

    func canMoveContent(_ id: UUID, to destination: BrowserWindowController) -> Bool {
        guard destination !== self, store === destination.store, !isPopupWindow, !destination.isPopupWindow,
              !destination.isClosing, !destination.wholeWindowClose, destination.transferringTabIDs.isEmpty,
              destination.collectionTransfer == nil, destination.nativeFullscreenTabID == nil,
              let destinationWindow = destination.window, destinationWindow !== window, destination.nativeBinding != nil,
              let tab = store.state.tab(id, where: { $0.archivedAt == nil }),
              tab.profileID == destination.activeProfileID, destination.browsers[id] == nil else { return false }
        if browsers[id] == nil, noteEditors[id] != nil || easelEditors[id] != nil {
            return !destination.isPrivateBrowsing && !destination.store.isEphemeral && destination.presentation.isReady
                && !destination.windowClosePending && !destination.windowCloseApproved && destination.activePeek == nil
        }
        if peeks.values.contains(where: { $0.parentTabID == id && $0.parentPage != nil && !$0.page.isClosed }) { return destination.activePeek == nil }
        return true
    }
    func claimsTab(_ id: UUID) -> Bool { ownership.owner(of: id) == presentationID }
    func closeTabMovingHere(_ id: UUID) -> Bool {
        if ownership.canUse(id, owner: presentationID) { return closeTab(id) }
        guard canMovePageHere(id), let request = onRequestTabTransfer else { refuseTabMove(); return false }
        let origins = closeOrigins([id])
        let unsavedNotes = origins[id]?()?.prepareNotesToClose([id]) == false
        if unsavedNotes || retirementUnavailableReason?([id]) != nil {
            reportRefusedClose([id], unsavedNotes: unsavedNotes); return false
        }
        return request(id, self) { [weak self] in self?.closeArrivedTab(id, origins: origins); return true }
    }
    private func closeArrivedTab(_ id: UUID, origins: [UUID: () -> BrowserWindowController?]) {
        let start = startTabClose(id)
        guard start != .started else { return }
        handBackRefusedClose([id], origins: origins)
        reportRefusedClose([id], unsavedNotes: start == .unsavedNotes)
    }
    func closeOrigins(_ ids: [UUID]) -> [UUID: () -> BrowserWindowController?] {
        var origins: [UUID: () -> BrowserWindowController?] = [:]
        for id in ids {
            switch tabHolder?(id, self) ?? .none {
            case .content(let holder), .emptyClaim(let holder): origins[id] = { [weak holder] in holder }
            case .none: break
            }
        }
        return origins
    }
    func handBackRefusedClose(_ ids: ArraySlice<UUID>, origins: [UUID: () -> BrowserWindowController?]) {
        guard let id = ids.first else { return }
        let rest = ids.dropFirst()
        let arrival = PendingArrival { [weak self] in self?.handBackRefusedClose(rest, origins: origins) }
        let started = origins[id]?().map { origin in
            transferTab(id, to: origin, placement: { [weak self] in
                arrival.ran = true
                self?.handBackRefusedClose(rest, origins: origins)
                return true
            }, untargeted: true)
        } ?? false
        guard !started else { return }
        arrival.ran = true
        returnIfUnshown(id)
        handBackRefusedClose(rest, origins: origins)
    }
    func finishEmptyClaimHandOver(_ id: UUID, placement: (() -> Bool)?) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if !(placement?() ?? false) { _ = self.selectTab(id) }
        }
    }

    private func favoritePagesElsewhere(_ expected: BrowserTab) -> [UUID] {
        guard canOfferFavoriteTransfer(expected) else { return [] }
        let pages = favoritePanes(expected).filter {
            ownership.isClaimed($0) && !ownership.canUse($0, owner: presentationID)
        }
        return pages.allSatisfy(canMovePageHere) ? pages : []
    }

    private func prepareFavoriteTransferOffer(_ expected: BrowserTab) -> (() -> Bool)? {
        let pages = favoritePagesElsewhere(expected)
        guard let first = pages.first else { return nil }
        let space = activeSpaceID, panes = favoritePanes(expected)
        var used = false
        return { [weak self] in
            guard let self, !used, self.activeSpaceID == space, self.favoritePanes(expected) == panes,
                  self.favoritePagesElsewhere(expected) == pages else { return false }
            used = true
            guard panes.count > 1 else { return self.onRequestTabTransfer?(first, self, nil) ?? false }
            return self.movePagesHere(pages[...]) { [weak self] in
                guard let self, self.activeSpaceID == space, self.favoritePanes(expected) == panes,
                      let current = self.currentFavorite(expected),
                      let select = self.prepareFavoriteAction(current, closing: false) else { return false }
                return select()
            }
        }
    }

    private func prepareFavoriteOptionRelease(_ expected: BrowserTab) -> (() -> Bool)? {
        switch FavoriteOptionRoute(favoriteID: expected.id, selection: selectedTabIDs, focusedID: currentTabID) {
        case .split: return prepareFavoriteSplit(expected) ?? prepareFavoriteSplitTransfer(expected)
        case .present: return prepareFavoriteActivation(expected)
        case .paneLimit: return prepareFavoritePaneLimit(expected)
        case .unchanged: return nil
        }
    }

    private func prepareFavoritePaneLimit(_ expected: BrowserTab) -> (() -> Bool)? {
        guard expected.kind == .favorite, !isPrivateBrowsing, splitCommandsAvailable, commandBar == nil,
              window?.isKeyWindow == true, window?.attachedSheet == nil,
              expected.profileID == activeProfileID, visibleTabs.contains(expected) else { return nil }
        let space = activeSpaceID, selection = selectedTabIDs
        var used = false
        return { [weak self] in
            guard let self, !used, self.activeSpaceID == space, self.selectedTabIDs == selection,
                  self.splitCommandsAvailable, self.commandBar == nil, self.window?.isKeyWindow == true,
                  self.window?.attachedSheet == nil, self.visibleTabs.contains(expected),
                  FavoriteOptionRoute(favoriteID: expected.id, selection: selection,
                                      focusedID: self.currentTabID) == .paneLimit else { return false }
            used = true
            self.showToast(.cannotAddNewPane, at: .window); return true
        }
    }

    private func prepareFavoriteSplitTransfer(_ expected: BrowserTab) -> (() -> Bool)? {
        guard splitCommandsAvailable, commandBar == nil, canOfferFavoriteTransfer(expected),
              canMovePageHere(expected.id), let focus = currentTabID else { return nil }
        let space = activeSpaceID, selection = selectedTabIDs
        let unchanged = { (owner: BrowserWindowController) in
            owner.activeSpaceID == space && owner.selectedTabIDs == selection && owner.currentTabID == focus
        }
        var used = false
        return { [weak self] in
            guard let self, !used, unchanged(self), self.splitCommandsAvailable, self.commandBar == nil,
                  self.canOfferFavoriteTransfer(expected), self.canMovePageHere(expected.id) else { return false }
            used = true
            return self.onRequestTabTransfer?(expected.id, self) { [weak self] in
                guard let self, unchanged(self), let current = self.currentFavorite(expected),
                      let insert = self.prepareFavoriteSplit(current) else { return false }
                return insert()
            } ?? false
        }
    }

    private func prepareFavoriteSplit(_ expected: BrowserTab) -> (() -> Bool)? {
        guard expected.kind == .favorite, !isPrivateBrowsing, splitCommandsAvailable,
              commandBar == nil, transferRecoveries.isEmpty,
              canPerformSidebarTabAction(expected, closing: false), switcherCanUse(expected.id),
              let window, let focus = currentTabID else { return nil }
        let space = activeSpaceID, selection = selectedTabIDs
        var identities: [UUID: SplitPaneIdentity] = [:]
        for id in selection {
            guard let identity = splitPaneIdentity(id) else { return nil }
            identities[id] = identity
        }
        let browser = browsers[expected.id], page = browser?.nativePage
        let hadBrowser = browser != nil
        let sourceURL: String
        if let browser {
            guard browser.window === window, browserProfiles[expected.id] == expected.profileID,
                  let page, !page.isClosed, let binding = nativeBinding,
                  existingNativeSelection(binding, page)?.1 === browser,
                  let url = page.url else { return nil }
            sourceURL = url.absoluteString
        } else {
            guard !ownership.isClaimed(expected.id) else { return nil }
            sourceURL = expected.savedURL
        }
        let revision = browser?.readerRevision
        guard let probe = FavoriteSplitRequest(favorite: expected, spaceID: space,
                  selection: selection, focusedID: focus, state: store.state,
                  duplicateURL: sourceURL, duplicateTitle: page?.title),
              let plan = splitHomePlan(probe.savedHomeSources(in: store.state)),
              let request = FavoriteSplitRequest(favorite: expected, spaceID: space,
                  selection: selection, focusedID: focus, state: store.state,
                  duplicateURL: sourceURL, duplicateTitle: page?.title, newID: probe.newID, homeIDs: plan.ids) else { return nil }
        var consumed = false
        return { [weak self, weak window, weak browser, weak page] in
            guard let self, let window, !consumed, self.window === window,
                  self.splitCommandsAvailable, self.commandBar == nil, self.transferRecoveries.isEmpty,
                  self.activeSpaceID == space, self.activeProfileID == expected.profileID,
                  self.selectedTabIDs == selection, self.currentTabID == focus,
                  self.canPerformSidebarTabAction(expected, closing: false), self.switcherCanUse(expected.id),
                  selection.allSatisfy({ self.splitPaneIdentity($0) == identities[$0] }),
                  (self.browsers[expected.id] != nil) == hadBrowser else { return false }
            if hadBrowser {
                guard let browser, let page, self.browsers[expected.id] === browser,
                      browser.nativePage === page, !page.isClosed, browser.window === window,
                      browser.readerRevision == revision, page.url?.absoluteString == sourceURL,
                      let binding = self.nativeBinding,
                      self.existingNativeSelection(binding, page)?.1 === browser else { return false }
            } else if self.ownership.isClaimed(expected.id) { return false }
            guard SidebarDocumentReference.validates(request.savedHomeSources(in: self.store.state),
                                                     references: plan.documents) else { return false }
            consumed = true
            var target: UUID?
            self.performWindowCommand(selectNativePage: false) {
                do { target = try self.store.commitFavoriteSplit(request) }
                catch { self.showError(error) }
            }
            guard let target else { return false }
            self.openSplitHomes(plan.ids, profileID: expected.profileID, originatingSpaceID: space)
            self.focusedTabID = target
            self.render(self.store.state)
            self.requestNativeSelection(); self.focusSelectedLocalContent()
            return true
        }
    }

    func prepareFavoriteAction(_ expected: BrowserTab, closing: Bool) -> (() -> Bool)? {
        guard !isPrivateBrowsing, expected.kind == .favorite else { return nil }
        return prepareSidebarTabAction(expected, closing: closing)
    }

    func prepareSidebarTabAction(_ expected: BrowserTab, closing: Bool) -> (() -> Bool)? {
        guard canPerformSidebarTabAction(expected, closing: closing) else { return nil }
        let space = activeSpaceID, browser = browsers[expected.id], page = browser?.nativePage
        let group = SidebarSplitItems.groups(in: store.state, spaceID: space).first { $0.tabIDs.contains(expected.id) }
        let hadBrowser = browser != nil, hadPage = page != nil
        var used = false
        return { [weak self, weak browser, weak page] in
            guard let self, !used, self.activeSpaceID == space,
                  self.canPerformSidebarTabAction(expected, closing: closing),
                  SidebarSplitItems.groups(in: self.store.state, spaceID: space).first(where: { $0.tabIDs.contains(expected.id) }) == group,
                  (self.browsers[expected.id] != nil) == hadBrowser else { return false }
            if hadBrowser {
                guard let browser, self.browsers[expected.id] === browser,
                      (browser.nativePage != nil) == hadPage else { return false }
                if hadPage { guard let page, browser.nativePage === page, !page.isClosed else { return false } }
            }
            used = true
            if closing {
                return self.closeTabMovingHere(expected.id)
            }
            return self.selectTab(expected.id)
        }
    }

    private func canResetSavedTab(_ expected: BrowserTab, allowUnchanged: Bool = false) -> Bool {
        guard !isPopupWindow, !isClosing, !wholeWindowClose, !windowClosePending,
              libraryView == nil, window?.isKeyWindow == true, window?.attachedSheet == nil,
              savedResetDestination(expected, allowUnchanged: allowUnchanged) != nil, expected.profileID == activeProfileID,
              let current = visibleTabs.first(where: { $0.id == expected.id }),
              current.kind == expected.kind, current.profileID == expected.profileID,
              current.url == expected.url, current.savedURL == expected.savedURL,
              !closingTabIDs.contains(expected.id), !transferringTabIDs.contains(expected.id),
              !resolvingTransfers.contains(expected.id), transferRecoveries[expected.id] == nil,
              !store.retiringTabIDs.contains(expected.id), peekPages(forTabID: expected.id).isEmpty,
              ownership.canUse(expected.id, owner: presentationID) else { return false }
        if let browser = browsers[expected.id] {
            guard browserProfiles[expected.id] == expected.profileID,
                  browser.window === window, let page = browser.nativePage, !page.isClosed,
                  page.url?.absoluteString == expected.url else { return false }
        } else if ownership.isClaimed(expected.id) { return false }
        return true
    }
    func prepareSavedTabReset(_ expected: BrowserTab, allowUnchanged: Bool = false) -> (() -> Bool)? {
        guard canResetSavedTab(expected, allowUnchanged: allowUnchanged) else { return nil }
        let space = activeSpaceID
        let browser = browsers[expected.id], page = browser?.nativePage
        let hadPage = page != nil
        var used = false
        return { [weak self, weak browser, weak page] in
            guard let self, !used, self.activeSpaceID == space, self.canResetSavedTab(expected, allowUnchanged: allowUnchanged) else { return false }
            if hadPage {
                guard let browser, let page, self.browsers[expected.id] === browser,
                      browser.nativePage === page else { return false }
            } else if self.browsers[expected.id] != nil { return false }
            used = true
            self.resetSavedTab(expected, allowUnchanged: allowUnchanged); return true
        }
    }
    func prepareSavedTabIconReset(_ expected: BrowserTab, separating: Bool) -> (() -> Bool)? {
        guard let action = separating ? prepareSavedTabSeparation(expected) : prepareSavedTabReset(expected) else { return nil }
        return { [weak self] in
            guard let self, action() else { return false }
            if !self.selectedTabIDs.contains(expected.id) { _ = self.selectTab(expected.id) }
            return true
        }
    }
    private func prepareSavedTabSeparation(_ expected: BrowserTab) -> (() -> Bool)? {
        guard expected.kind == .pinned, nativeFullscreenTabID != expected.id, canResetSavedTab(expected),
              !SidebarSplitItems.groups(in: store.state, spaceID: activeSpaceID)
                  .contains(where: { $0.tabIDs.contains(expected.id) }) else { return nil }
        let space = activeSpaceID
        let browser = browsers[expected.id], page = browser?.nativePage
        let hadPage = page != nil
        var used = false
        return { [weak self, weak browser, weak page] in
            guard let self, !used, self.activeSpaceID == space, self.nativeFullscreenTabID != expected.id,
                  self.canResetSavedTab(expected) else { return false }
            guard hadPage else {
                guard self.browsers[expected.id] == nil else { return false }
                used = true; return true
            }
            guard let browser, let page, self.browsers[expected.id] === browser,
                  browser.nativePage === page else { return false }
            used = true
            return self.separateFromPinnedTab(expected, browser: browser, page: page)
        }
    }
    private func separateFromPinnedTab(_ expected: BrowserTab, browser: PCBrowserView, page: PCNativePage) -> Bool {
        guard let binding = nativeBinding, !page.isClosed, browser.window === window,
              PCNativeBrowserApplication.owner(of: page) === binding else { return false }
        navigationHistory?.dismiss(); sidebarPreviews?.dismiss(); tabSwitcher?.cancel()
        let id = UUID()
        prepareStoreContext()
        guard store.separateFromPinnedTab(expected, todayID: id, title: browser.title),
              let tab = store.state.tab(id),
              let reset = store.state.tab(expected.id) else { return false }
        let source = panes[expected.id]
        binding.pageWillDetach(page)
        source?.browser = nil
        let pane = makePane(tab)
        pane.frame = pageHost.bounds; parkedPages.addSubview(pane)
        pane.browser = browser; pane.showBrowser(); pane.layoutSubtreeIfNeeded()
        func restore() {
            pane.browser = nil; pane.removeFromSuperview()
            source?.browser = browser
            _ = binding.pageDidAttach(page, container: browser)
            store.removeTab(id)
            _ = store.restoreLiveTab(expected, replacing: reset)
        }
        guard binding.pageDidAttach(page, container: browser) else { restore(); return false }
        ownership.release(expected.id, owner: presentationID)
        guard ownership.claim(id, owner: presentationID, page: page.identifier) else {
            _ = ownership.claim(expected.id, owner: presentationID, page: page.identifier)
            binding.pageWillDetach(page); restore(); return false
        }
        browsers.removeValue(forKey: expected.id); browsers[id] = browser
        browserProfiles.removeValue(forKey: expected.id); browserProfiles[id] = tab.profileID
        liveTabModels.removeValue(forKey: expected.id); liveTabModels[id] = tab
        requestedURLs.removeValue(forKey: expected.id); requestedURLs[id] = tab.url
        zoomLevels[id] = zoomLevels.removeValue(forKey: expected.id)
        failures[id] = failures.removeValue(forKey: expected.id)
        if loadingTabs.remove(expected.id) != nil { loadingTabs.insert(id) }
        inputRevisions.removeValue(forKey: expected.id); pendingSearchNavigations.removeValue(forKey: expected.id)
        if pendingNativeSelection?.tabID == expected.id { pendingNativeSelection = nil }
        panes[id] = pane; attachedPageIDs.insert(page.identifier)
        render(store.state); requestNativeSelection()
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.isClosing, let tab = self.store.state.tab(id) else { return }
            let other = tab.spaceID != self.activeSpaceID ? self.store.state.spaces.first { $0.id == tab.spaceID }?.name : nil
            self.showToast(.backgroundTabCreated(inSpace: other, document: InternalPage.isInternal(tab.url)),
                           onTap: { [weak self] in _ = self?.selectTab(id) })
        }
        return true
    }
    var canResetCurrentTab: Bool {
        activePeek == nil && currentTabID.flatMap { id in visibleTabs.first { $0.id == id } }
            .map { canResetSavedTab($0) } == true
    }
    func resetCurrentTab() {
        guard activePeek == nil, let tab = visibleTabs.first(where: { $0.id == currentTabID }) else { return }
        resetSavedTab(tab)
    }
    private var visibleSavedResetTargets: [BrowserTab] {
        SavedTabResetTargets.collect(in: store.state, spaceID: activeSpaceID)
    }
    var canResetVisibleSavedTabs: Bool { visibleSavedResetTargets.contains { canResetSavedTab($0) } }
    func resetVisibleSavedTabs() {
        let actions = visibleSavedResetTargets.compactMap { prepareSavedTabReset($0) }
        for action in actions { _ = action() }
    }
    private func savedResetDestination(_ expected: BrowserTab, allowUnchanged: Bool) -> URL? {
        if !allowUnchanged { return expected.resetDestination }
        guard expected.archivedAt == nil, expected.kind == .favorite,
              !InternalPage.isInternal(expected.url), !InternalPage.isInternal(expected.savedURL),
              let url = URL(string: expected.savedURL), url.scheme != nil else { return nil }
        return url
    }
    private func resetSavedTab(_ expected: BrowserTab, allowUnchanged: Bool = false) {
        guard canResetSavedTab(expected, allowUnchanged: allowUnchanged),
              let destination = savedResetDestination(expected, allowUnchanged: allowUnchanged) else { return }
        navigationHistory?.dismiss(); sidebarPreviews?.dismiss(); tabSwitcher?.cancel()
        if let browser = browsers[expected.id] {
            pendingSearchNavigations.removeValue(forKey: expected.id)
            inputRevisions.removeValue(forKey: expected.id)
            browser.loadURL(destination)
        } else if !ownership.isClaimed(expected.id) {
            store.resetDormantSavedTab(expected)
        }
    }
}
