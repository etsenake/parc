import AppKit

extension BrowserWindowController {
    func beginCloseFade(_ id: UUID) -> Bool {
        guard closeFade == nil, !isPopupWindow, presentation.isReady, !isClosing, !wholeWindowClose, !windowClosePending,
              let window, window.isVisible, !window.isMiniaturized, window.attachedSheet == nil,
              activePeek == nil, peek(over: id) == nil, tabPeeks.current == nil, libraryView == nil, spaceCreation == nil, splitInsertion == nil,
              nativeFullscreenTabID == nil, !startPageDeparting, !showsStartPage, !switchHold.isHolding,
              currentTabID == id, renderedPaneIDs == [id], let pane = panes[id],
              splitView.arrangedSubviews.count == 1, splitView.arrangedSubviews.first === pane,
              !pane.isHiddenOrHasHiddenAncestor, closeEmptiesSpace(id) else { return false }
        let page = startPage
        refreshStartPageChrome()
        page.isDeparting = false
        page.alphaValue = 0
        page.autoresizingMask = [.width, .height]
        pageHost.addSubview(page, positioned: .below, relativeTo: splitView)
        page.frame = splitView.frame
        let fade = TabCloseFade(tabID: id, page: pane, startPage: page)
        fade.passesInput = { [weak pane] in pane?.passesInput = $0 }
        fade.returnFocus = { [weak self, weak pane] responder in
            guard let self, let pane, let window = self.window, let view = responder as? NSView, window.firstResponder !== view,
                  view.window === window, !view.isHiddenOrHasHiddenAncestor else { return }
            if let page = self.browsers[id]?.nativePage, !page.isClosed,
               view === page.nativeView || view.isDescendant(of: page.nativeView) {
                _ = self.nativeBinding?.requestFocus(for: page)
            } else if view.isDescendant(of: pane) {
                window.makeFirstResponder(view)
            }
        }
        fade.onRequestClose = { [weak self] in self?.requestFadedTabClose(id) }
        fade.onRestored = { [weak self, weak fade] in
            guard let self, let fade, self.closeFade === fade else { return }
            self.endCloseFade()
        }
        closeFade = fade
        refreshPageHostBacking()
        fade.begin()
        return true
    }

    private func closeEmptiesSpace(_ id: UUID) -> Bool {
        guard let next = FolderRemovalSelection.resolve(removing: [id], spaceID: activeSpaceID, profileID: activeProfileID,
                state: store.state, selected: selectedTabIDs, focused: focusedTabID, referrerPool: presentation.referrerPool,
                previouslySelectedItemID: presentation.previouslySelectedItemID,
                available: { self.switcherCanUse($0) }) else { return false }
        return next.tabIDs.isEmpty && next.replacementSpaceID == activeSpaceID
    }

    private func requestFadedTabClose(_ id: UUID) {
        let unsavedNotes = !prepareNotesToClose([id])
        guard !unsavedNotes, tabCloseAvailable(id) else {
            if let fade = closeFade, fade.tabID == id { fade.refused() }
            reportRefusedClose([id], unsavedNotes: unsavedNotes)
            return
        }
        commitTabClose(id)
    }

    func closeFadeLanded(_ id: UUID, approved: Bool) {
        guard let fade = closeFade, fade.tabID == id else { return }
        if approved { fade.finish() } else { fade.refused() }
    }

    func reconcileCloseFade() {
        guard let fade = closeFade else { return }
        if fade.phase == .finished, startPagePresented { endCloseFade(); return }
        if fade.phase != .resting, loadedStartPage?.superview === splitView { fade.handOff(); return }
        let displayed = splitView.arrangedSubviews.count == 1 && splitView.arrangedSubviews.first === panes[fade.tabID]
        if fade.phase == .finished || !displayed { endCloseFade() }
    }

    func takeCloseFadeArrival() -> Bool {
        guard let fade = closeFade, fade.phase == .finished else { return false }
        closeFade = nil
        fade.end()
        return true
    }

    func endCloseFade() {
        guard let fade = closeFade else { return }
        closeFade = nil
        fade.interrupt()
        fade.end()
        if let pane = panes[fade.tabID], pane.superview === splitView { pane.alphaValue = 1 }
        if let page = loadedStartPage, page.superview === pageHost, !startPageDeparting {
            page.removeFromSuperview()
            page.alphaValue = 1
        }
        if !rendering { refreshPageHostBacking() }
    }
}
