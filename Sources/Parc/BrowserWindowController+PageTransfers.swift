import AppKit
import Combine
import ParcCore
import ParcEngine
import ParcKit
import ParcNotes

extension BrowserWindowController {
    func movePagesHere(_ ids: ArraySlice<UUID>, then completion: @escaping () -> Bool) -> Bool {
        guard let id = ids.first else { return completion() }
        guard ownership.isClaimed(id), !ownership.canUse(id, owner: presentationID),
              let request = onRequestTabTransfer else { return movePagesHere(ids.dropFirst(), then: completion) }
        return request(id, self) { [weak self] in self?.movePagesHere(ids.dropFirst(), then: completion) ?? false }
    }

    func moveRootsHere(_ ids: ArraySlice<UUID>, moved: [UUID], then close: @escaping ([UUID]) -> Bool) -> Bool {
        guard let id = ids.first else { return close(moved) }
        guard ownership.isClaimed(id), !ownership.canUse(id, owner: presentationID),
              let request = onRequestTabTransfer else { return moveRootsHere(ids.dropFirst(), moved: moved, then: close) }
        let arrival = PendingArrival { [weak self] in self?.returnMovedRoots(moved) }
        let started = request(id, self) { [weak self] in
            arrival.ran = true
            _ = self?.moveRootsHere(ids.dropFirst(), moved: moved + [id], then: close)
            return true
        }
        if !started { arrival.ran = true; returnMovedRoots(moved) }
        return started
    }
    func returnMovedRoots(_ ids: [UUID]) { for id in ids { returnIfUnshown(id) } }

    func refuseTabMove() { NSSound.beep() }

    func displaysPlaceholder(for id: UUID) -> Bool { presentation.displayedPlaceholders.contains(id) }
    func showsPlaceholder(for id: UUID) -> Bool { presentation.showsPlaceholder(id) }

    func pullBackPlaceholder(_ id: UUID) {
        guard presentation.displayedPlaceholders.contains(id), commandBar == nil, activePeek == nil,
              window?.attachedSheet == nil else { return }
        _ = selectTab(id)
    }

    private func capturePlaceholderSnapshot(_ id: UUID, page: PCNativePage, from source: BrowserWindowController,
                                            attempt: Int = 0, generation: Int? = nil) {
        let generation = generation ?? { placeholderCaptureGeneration += 1; return placeholderCaptureGeneration }()
        if attempt == 0 {
            source.syncPlaceholderImageHolders()
            placeholderCapturesPending[id] = generation
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + PagePlaceholderCaptureOrder.delay(before: attempt)) { [weak self, weak source, weak page] in
            guard let self, self.placeholderCapturesPending[id] == generation else { return }
            guard let page, !page.isClosed, self.store.placeholderImages.isShown(id),
                  self.pageCapture == nil, let window = self.window,
                  self.browsers[id]?.nativePage === page, page.nativeView.window === window else {
                self.placeholderCapturesPending.removeValue(forKey: id); return
            }
            if PagePlaceholderCaptureOrder.waits(id, attempt: attempt, pending: Set(self.placeholderCapturesPending.keys),
                                                 focused: self.currentTabID) {
                self.capturePlaceholderSnapshot(id, page: page, from: source ?? self, attempt: attempt + 1, generation: generation)
                return
            }
            let key = ObjectIdentifier(page)
            guard Self.placeholderCaptureLeases[key] == nil, page.canCapture(in: window),
                  let capture = page.beginPlaceholderSnapshot(in: window) else {
                if PagePlaceholderCaptureOrder.retries(after: attempt), let source {
                    self.capturePlaceholderSnapshot(id, page: page, from: source, attempt: attempt + 1, generation: generation)
                } else { self.placeholderCapturesPending.removeValue(forKey: id) }
                return
            }
            Self.placeholderCaptureLeases[key] = capture
            capture.captureViewport { [weak self, weak source] result in
                capture.invalidate()
                if Self.placeholderCaptureLeases[key] === capture { Self.placeholderCaptureLeases.removeValue(forKey: key) }
                guard let self, self.placeholderCapturesPending[id] == generation else { return }
                guard let data = result.pngData, self.store.placeholderImages.isShown(id) else {
                    self.placeholderCapturesPending.removeValue(forKey: id); return
                }
                let size = PagePlaceholderSnapshot.maxPixelSize(source: result.pixelSize, filling: source?.placeholderPixelSize(for: id))
                PagePlaceholderSnapshot.thumbnail(fromPNG: data, maxPixelSize: size) { [weak self, weak source] image in
                    MainActor.assumeIsolated {
                        guard let self, self.placeholderCapturesPending[id] == generation else { return }
                        self.placeholderCapturesPending.removeValue(forKey: id)
                        source?.syncPlaceholderImageHolders()
                        if let image { self.store.placeholderImages.store(image, for: id) }
                    }
                }
            }
        }
    }

    func syncPlaceholderImageHolders() {
        store.placeholderImages.setShown(presentation.allPlaceholders, in: presentationID)
    }
    static func yieldPlaceholderCapture(of page: PCNativePage) {
        placeholderCaptureLeases.removeValue(forKey: ObjectIdentifier(page))?.invalidate()
    }
    private func placeholderPixelSize(for id: UUID) -> CGSize? {
        guard let size = panes[id]?.bounds.size, size.width > 0, size.height > 0 else { return nil }
        let scale = window?.backingScaleFactor ?? 2
        return CGSize(width: size.width * scale, height: size.height * scale)
    }
    private func paneSizedSnapshot(_ image: CGImage, for id: UUID) -> CGImage {
        guard let pixels = placeholderPixelSize(for: id) else { return image }
        return PagePlaceholderView.downsampled(image, toFill: pixels)
    }

    func scheduleUntargetedReturns() {
        guard !untargetedReturnScheduled, onUntargetedReturn != nil else { return }
        untargetedReturnScheduled = true
        enqueueUntargetedReturns { [weak self] in
            guard let self else { return }
            self.untargetedReturnScheduled = false
            guard self.presentation.isReady, !self.isClosing, !self.wholeWindowClose, !self.windowClosePending,
                  self.transferringTabIDs.isEmpty, self.resolvingTransfers.isEmpty, self.collectionTransfer == nil,
                  self.nativeFullscreenTabID == nil else { return }
            let shown = Set(self.presentation.displayedTabIDs)
            for id in self.returnableIDs.sorted(by: { $0.uuidString < $1.uuidString })
            where !shown.contains(id) && self.shownSinceArrival.contains(id)
                && (self.canHandOverPage(id) || self.holdsEmptyClaim(id)) {
                self.shownSinceArrival.remove(id)
                let outcome = self.onUntargetedReturn?(id, self, .deselected)
                if outcome == .started { return }
                if outcome == .blocked, self.failedDuringReturn != id { self.heldReturns.insert(id) }
            }
        }
    }
    func retryHeldReturns() {
        guard !heldReturns.isEmpty, !isClosing else { return }
        shownSinceArrival.formUnion(heldReturns)
        heldReturns.removeAll()
        scheduleUntargetedReturns()
    }
    private func holdFailedReturn(_ id: UUID) {
        failedDuringReturn = id
        guard !presentation.displayedTabIDs.contains(id), heldContentIDs.contains(id) || holdsEmptyClaim(id) else { return }
        if failedReturns.insert(id).inserted { heldReturns.insert(id) } else {
            failedReturns.remove(id); heldReturns.remove(id); shownSinceArrival.remove(id)
        }
    }
    func returnFailed(_ id: UUID) -> Bool { failedDuringReturn == id }
    private var returnGateOpen: Bool {
        presentation.isReady && activePeek == nil && !promotingPeek && commandBar == nil && tabSwitcher == nil
            && themePopover == nil && !siteControlCenterDefers && closingTabIDs.isEmpty && modelRetirementIDs.isEmpty
            && peekRetirementParents.isEmpty && peeks.values.allSatisfy({ !$0.closePending })
            && !store.isProfileRemovalPending(activeProfileID) && nativeBinding?.canParticipateInPageTransfer == true
    }
    func noteReturnGate() {
        let open = returnGateOpen, space = activeSpaceID
        defer { returnGateWasOpen = open; returnGateSpaceID = space }
        if open, !returnGateWasOpen || space != returnGateSpaceID { onReturnUnblocked?() }
    }

    var heldContentIDs: Set<UUID> {
        Set(browsers.keys).union(noteEditors.keys).union(easelEditors.keys)
    }
    var returnableIDs: Set<UUID> {
        heldContentIDs.union(panes.keys.filter(holdsEmptyClaim)).union(shownSinceArrival.union(heldReturns).filter(holdsEmptyClaim))
    }
    func returnIfUnshown(_ id: UUID) {
        guard !presentation.displayedTabIDs.contains(id), heldContentIDs.contains(id) || holdsEmptyClaim(id) else { return }
        shownSinceArrival.insert(id)
        scheduleUntargetedReturns()
    }
    private func placeArrival(_ id: UUID, placement: @escaping () -> Bool) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if !placement(), !self.selectTab(id) { self.returnIfUnshown(id) }
        }
    }
    func canHandOverPage(_ id: UUID) -> Bool {
        guard claimsTab(id), switcherCanUse(id), !peekRetirementParents.contains(id) else { return false }
        if let browser = browsers[id] { return browser.nativePage.map { !$0.isClosed } == true }
        return noteEditors[id] != nil || easelEditors[id] != nil
    }

    func showTabTransferFailure(_ detail: String) {
        if let window { ParcDialog.inform(in: window, .init(title: "This tab couldn’t move", message: detail)) }
    }

    @discardableResult
    func transferTab(_ id: UUID, to destination: BrowserWindowController, placement: (() -> Bool)? = nil,
                     untargeted: Bool = false) -> Bool {
        if untargeted { failedDuringReturn = nil }
        settleTabPeek(before: id)
        if untargeted, holdsEmptyClaim(id) {
            guard handOverEmptyClaim(id, to: destination) else { return false }
            if !destination.rendering { destination.render(destination.store.state) }
            return true
        }
        if let peek = peeks.values.first(where: { $0.parentTabID == id && $0.parentPage != nil && !$0.page.isClosed }) {
            return transferTabWithPeek(id, peek: peek, to: destination, placement: placement, untargeted: untargeted)
        }
        if browsers[id] == nil, noteEditors[id] != nil || easelEditors[id] != nil {
            return transferDocument(id, to: destination, placement: placement, untargeted: untargeted)
        }
        guard self !== destination, store === destination.store, !isPopupWindow, !destination.isPopupWindow,
              transferringTabIDs.isEmpty, destination.transferringTabIDs.isEmpty,
              !isClosing, !wholeWindowClose, !destination.isClosing, !destination.wholeWindowClose,
              !closingTabIDs.contains(id), !store.retiringTabIDs.contains(id),
              nativeFullscreenTabID != id, destination.nativeFullscreenTabID == nil,
              let browser = browsers[id], let page = browser.nativePage, !page.isClosed,
              let sourceWindow = window, browser.window === sourceWindow,
              let destinationWindow = destination.window, destinationWindow !== sourceWindow,
              let binding = destination.nativeBinding,
              let tab = store.state.tab(id, where: { $0.archivedAt == nil }),
              tab.profileID == browserProfiles[id], tab.profileID == destination.activeProfileID,
              page.profilePath == store.independentEngineProfilePath(for: tab.profileID),
              destination.browsers[id] == nil,
              let reservation = ownership.reserveTransfer(id, page: page.identifier,
                  from: presentationID, to: destination.presentationID) else {
            if !untargeted { destination.refuseTabMove() }
            return false
        }
        transferringTabIDs.insert(id)
        destination.transferringTabIDs.insert(id)
        let container = NSView(frame: destination.pageHost.bounds)
        container.autoresizingMask = [.width, .height]
        destination.parkedPages.addSubview(container)
        destination.transferContainers[page.identifier] = container
        attachedPageIDs.remove(page.identifier)
        binding.transferPage(page, profilePath: page.profilePath, container: container) { [self, destination, browser, page, container] result, error in
            MainActor.assumeIsolated {
                resolveTabTransfer(id, reservation: reservation, tab: tab, browser: browser,
                    page: page, container: container, destination: destination,
                    placement: placement, untargeted: untargeted, detail: error?.localizedDescription)
            }
        }
        return true
    }

    private func transferDocument(_ id: UUID, to destination: BrowserWindowController,
                                  placement: (() -> Bool)?, untargeted: Bool) -> Bool {
        let snapshot: CGImage? = panes[id].flatMap { pane in
            guard pane.window != nil, !pane.isHiddenOrHasHiddenAncestor, !pane.bounds.isEmpty,
                  let bitmap = pane.bitmapImageRepForCachingDisplay(in: pane.bounds) else { return nil }
            pane.cacheDisplay(in: pane.bounds, to: bitmap)
            return bitmap.cgImage
        }
        var plan = SidebarWindowTransfer.Plan(tabIDs: [id], sourceSpaceID: activeSpaceID, profileID: activeProfileID,
            destinationSpaceID: destination.activeSpaceID, isCurrent: { _ in true }, commit: { _ in true })
        plan.leavesPlaceholder = true
        plan.failureReport = untargeted ? .silent : .beep
        guard self !== destination, store === destination.store, activeProfileID == destination.activeProfileID,
              !isPopupWindow, !destination.isPopupWindow,
              sidebarWindowMoveAvailable, destination.sidebarWindowMoveAvailable,
              let transaction = SidebarWindowTransfer(source: self, destination: destination, plan: plan) else {
            if !untargeted { destination.refuseTabMove() }
            return false
        }
        transaction.onFinish = { [weak self, weak destination] committed in
            guard let self else { return }
            defer { self.resumeCloseAfterEjecting() }
            guard committed else { if untargeted { self.holdFailedReturn(id) }; return }
            guard let destination else { return }
            if let snapshot, self.presentation.showsPlaceholder(id) {
                self.syncPlaceholderImageHolders()
                self.store.placeholderImages.store(self.paneSizedSnapshot(snapshot, for: id), for: id)
                if !self.rendering { self.render(self.store.state) }
            }
            guard !untargeted else { return }
            destination.window?.makeKeyAndOrderFront(nil)
            destination.placeArrival(id, placement: placement ?? { false })
        }
        guard transaction.begin() else {
            if !untargeted { destination.refuseTabMove() }
            return false
        }
        return true
    }

    private func resolveTabTransfer(_ id: UUID, reservation: NativePageOwnership.Transfer,
                                    tab: BrowserTab, browser: PCBrowserView, page: PCNativePage,
                                    container: NSView, destination: BrowserWindowController,
                                    placement: (() -> Bool)?, untargeted: Bool, detail: String?) {
        guard !resolvingTransfers.contains(id), transferringTabIDs.contains(id) else { return }
        resolvingTransfers.insert(id)
        defer { resolvingTransfers.remove(id) }
        let finish = {
            self.transferRecoveries.removeValue(forKey: id)
            destination.transferRecoveries.removeValue(forKey: id)
            self.transferringTabIDs.remove(id)
            destination.transferringTabIDs.remove(id)
            destination.transferContainers.removeValue(forKey: page.identifier)
            self.refreshMiniPlayers(force: true)
            destination.refreshMiniPlayers(force: true)
            self.schedulePresentationSessionRecord()
            destination.schedulePresentationSessionRecord()
            if container.subviews.isEmpty { container.removeFromSuperview() }
            self.resumeCloseAfterEjecting()
        }
        let finishClosed = {
            _ = self.ownership.finishTransfer(reservation, moved: false)
            finish()
            self.releaseClosedTab(id, updateSavedTab: false)
            destination.discardTransferPane(id)
            self.render(self.store.state)
            destination.render(self.store.state)
            self.requestNativeSelection()
            destination.requestNativeSelection()
        }
        if page.isClosed { finishClosed(); return }
        let owner = PCNativeBrowserApplication.owner(of: page)
        var resolved = false
        var moved = false
        var leftPlaceholder = false
        if browsers[id] === browser, ownership.isCurrent(reservation),
           let binding = destination.nativeBinding, owner === binding,
           let destinationWindow = destination.window {
            let pane = destination.panes[id] ?? destination.makePane(tab)
            destination.panes[id] = pane
            if pane.superview == nil { destination.parkedPages.addSubview(pane) }
            if panes[id]?.browser === browser { panes[id]?.browser = nil }
            if pane.browser !== browser || browser.window !== destinationWindow { pane.browser = browser }
            pane.showBrowser()
            if binding.pageDidAttach(page, container: browser), !page.isClosed,
               PCNativeBrowserApplication.owner(of: page) === binding,
               browser.window === destinationWindow,
               ownership.finishTransfer(reservation, moved: true) {
                let request = requestedURLs.removeValue(forKey: id)
                let zoom = zoomLevels.removeValue(forKey: id)
                let loading = loadingTabs.remove(id) != nil
                failures.removeValue(forKey: id)
                browsers.removeValue(forKey: id)
                browserProfiles.removeValue(forKey: id)
                liveTabModels.removeValue(forKey: id)
                panes.removeValue(forKey: id)?.removeFromSuperview()
                leftPlaceholder = presentation.leavePlaceholder(id, state: store.state)
                renderedPaneIDs.removeAll { $0 == id }
                if focusedTabID == id { focusedTabID = presentation.preferredFocusedTabID }
                destination.browsers[id] = browser
                destination.browserProfiles[id] = tab.profileID
                destination.liveTabModels[id] = store.state.tab(id) ?? tab
                destination.requestedURLs[id] = request ?? tab.url
                destination.zoomLevels[id] = zoom
                destination.failures.removeValue(forKey: id)
                if loading { destination.loadingTabs.insert(id) }
                browser.delegate = destination
                destination.attachedPageIDs.insert(page.identifier)
                destination.presentation.adopt(id, state: store.state, foreground: placement == nil)
                if placement == nil { destination.focusedTabID = id }
                resolved = true
                moved = true
            }
        } else if browsers[id] === browser, ownership.isCurrent(reservation),
                  let binding = nativeBinding, owner === binding, let sourceWindow = window {
            if destination.panes[id]?.browser === browser { destination.panes[id]?.browser = nil }
            if let pane = panes[id], pane.browser !== browser || browser.window !== sourceWindow { pane.browser = browser }
            if binding.pageDidAttach(page, container: browser), !page.isClosed,
               PCNativeBrowserApplication.owner(of: page) === binding,
               browser.window === sourceWindow,
               ownership.finishTransfer(reservation, moved: false) {
                attachedPageIDs.insert(page.identifier)
                failures.removeValue(forKey: id)
                destination.discardTransferPane(id)
                resolved = true
            }
        }
        if page.isClosed { finishClosed(); return }
        if resolved {
            finish()
            render(store.state)
            destination.render(store.state)
            requestNativeSelection()
            destination.requestNativeSelection()
            if moved {
                destination.prepareStoreContext()
                if !untargeted { destination.window?.makeKeyAndOrderFront(nil) }
                if leftPlaceholder { destination.capturePlaceholderSnapshot(id, page: page, from: self) }
                if let placement { destination.placeArrival(id, placement: placement) }
            } else if detail != nil, !untargeted {
                destination.refuseTabMove()
            } else if untargeted {
                holdFailedReturn(id)
            }
            return
        }
        let retry: () -> Void = { [weak self, weak destination, browser, page, container] in
            guard let self, let destination else { return }
            self.resolveTabTransfer(id, reservation: reservation, tab: tab, browser: browser,
                page: page, container: container, destination: destination,
                placement: placement, untargeted: untargeted, detail: detail)
        }
        presentTransferRecovery(id, destination: destination, pages: [page], retry: retry)
    }

    private func presentTransferRecovery(_ id: UUID, destination: BrowserWindowController,
                                         pages: [PCNativePage], retry: @escaping () -> Void) {
        transferRecoveries[id] = retry
        destination.transferRecoveries[id] = retry
        var content = ParcDialog.Content(title: "The page move needs attention",
            message: "The live page is retained, but its current owner or attachment couldn’t be confirmed. Retry to reconnect it, or close the actual page with its normal leave-page confirmation.",
            confirm: "Retry")
        content.secondary = "Close Page"; content.auxiliary = "Keep Open"
        func close(_ remaining: ArraySlice<PCNativePage>) {
            guard let page = remaining.first else { retry(); return }
            guard !page.isClosed else { close(remaining.dropFirst()); return }
            page.requestClose { _ in MainActor.assumeIsolated { close(remaining.dropFirst()) } }
        }
        if let window = destination.window {
            _ = ParcDialog(content).begin(for: window) { response in
                if response == .confirm { retry() }
                else if response == .secondary { close(pages[...]) }
            }
        }
    }

    private func transferTabWithPeek(_ id: UUID, peek: PeekController, to destination: BrowserWindowController,
                                     placement: (() -> Bool)?, untargeted: Bool) -> Bool {
        guard self !== destination, store === destination.store, !isPopupWindow, !destination.isPopupWindow,
              transferringTabIDs.isEmpty, destination.transferringTabIDs.isEmpty,
              collectionTransfer == nil, destination.collectionTransfer == nil,
              !isClosing, !wholeWindowClose, !destination.isClosing, !destination.wholeWindowClose,
              !promotingPeek, !peek.closePending, peeks[peek.page.identifier] === peek,
              peeks.values.filter({ $0.parentTabID == id && !$0.page.isClosed }).count == 1,
              !closingTabIDs.contains(id), !store.retiringTabIDs.contains(id), !peekRetirementParents.contains(id),
              nativeFullscreenTabID != id, destination.nativeFullscreenTabID == nil, destination.activePeek == nil,
              let browser = browsers[id], let page = browser.nativePage, !page.isClosed, peek.parentPage === page,
              !peek.page.isClosed, let sourceWindow = window, browser.window === sourceWindow,
              peek.browser.window === sourceWindow, let sourceBinding = nativeBinding,
              PCNativeBrowserApplication.owner(of: page) === sourceBinding,
              PCNativeBrowserApplication.owner(of: peek.page) === sourceBinding,
              let destinationWindow = destination.window, destinationWindow !== sourceWindow,
              let binding = destination.nativeBinding,
              let tab = store.state.tab(id, where: { $0.archivedAt == nil }),
              tab.profileID == browserProfiles[id], tab.profileID == destination.activeProfileID,
              page.profilePath == store.independentEngineProfilePath(for: tab.profileID),
              peek.page.profilePath == page.profilePath, destination.browsers[id] == nil,
              let reservation = ownership.reserveCollection([id, peek.identity], from: presentationID, to: destination.presentationID)
        else {
            if !untargeted { destination.refuseTabMove() }
            return false
        }
        transferringTabIDs.insert(id)
        destination.transferringTabIDs.insert(id)
        let moving = [page, peek.page]
        let containers = moving.map { movingPage -> NSView in
            let container = NSView(frame: destination.pageHost.bounds)
            container.autoresizingMask = [.width, .height]
            destination.parkedPages.addSubview(container)
            destination.transferContainers[movingPage.identifier] = container
            return container
        }
        attachedPageIDs.remove(page.identifier)
        binding.transferPages(moving, profilePath: page.profilePath, containers: containers, commit: { true }) { [self] _, error in
            MainActor.assumeIsolated {
                resolvePeekTransfer(id, peek: peek, reservation: reservation, tab: tab, browser: browser, page: page,
                    containers: containers, destination: destination, placement: placement,
                    untargeted: untargeted, failed: error != nil)
            }
        }
        return true
    }

    private func resolvePeekTransfer(_ id: UUID, peek: PeekController, reservation: NativePageOwnership.CollectionTransfer,
                                     tab: BrowserTab, browser: PCBrowserView, page: PCNativePage, containers: [NSView],
                                     destination: BrowserWindowController, placement: (() -> Bool)?,
                                     untargeted: Bool, failed: Bool) {
        guard transferringTabIDs.contains(id), !resolvingTransfers.contains(id) else { return }
        resolvingTransfers.insert(id)
        defer { resolvingTransfers.remove(id) }
        let moving = [page, peek.page]
        var closed = Set<UUID>()
        if page.isClosed { closed.insert(id) }
        if peek.page.isClosed { closed.insert(peek.identity) }
        let retry: () -> Void = { [weak self, weak destination, weak peek, browser, page] in
            guard let self, let destination, let peek else { return }
            self.resolvePeekTransfer(id, peek: peek, reservation: reservation, tab: tab, browser: browser, page: page,
                containers: containers, destination: destination, placement: placement, untargeted: untargeted, failed: failed)
        }
        let finish = {
            self.transferRecoveries.removeValue(forKey: id)
            destination.transferRecoveries.removeValue(forKey: id)
            self.transferringTabIDs.remove(id)
            destination.transferringTabIDs.remove(id)
            for (movingPage, container) in zip(moving, containers) {
                destination.transferContainers.removeValue(forKey: movingPage.identifier)
                if container.subviews.isEmpty { container.removeFromSuperview() }
            }
            self.refreshMiniPlayers(force: true)
            destination.refreshMiniPlayers(force: true)
            self.schedulePresentationSessionRecord()
            destination.schedulePresentationSessionRecord()
            self.resumeCloseAfterEjecting()
        }
        let live = moving.filter { !$0.isClosed }
        guard ownership.isCurrent(reservation, closed: closed), !live.isEmpty else {
            if live.isEmpty, ownership.finishCollection(reservation, moved: false, closed: closed) {
                finish()
                releaseClosedTab(id, updateSavedTab: false)
                removePeek(peek)
                render(store.state); destination.render(store.state)
                requestNativeSelection(); destination.requestNativeSelection()
                return
            }
            presentTransferRecovery(id, destination: destination, pages: live, retry: retry); return
        }
        if live.allSatisfy({ PCNativeBrowserApplication.owner(of: $0) === destination.nativeBinding }),
           let binding = destination.nativeBinding, let destinationWindow = destination.window {
            if !page.isClosed {
                let pane = destination.panes[id] ?? destination.makePane(tab)
                destination.panes[id] = pane
                if pane.superview == nil { destination.parkedPages.addSubview(pane) }
                if panes[id]?.browser === browser { panes[id]?.browser = nil }
                if pane.browser !== browser || browser.window !== destinationWindow { pane.browser = browser }
                pane.showBrowser()
                guard binding.pageDidAttach(page, container: browser), browser.window === destinationWindow else {
                    presentTransferRecovery(id, destination: destination, pages: live, retry: retry); return
                }
            }
            if !peek.page.isClosed {
                if peek.view.superview !== destination.peekLayer {
                    destination.peekLayer.addSubview(peek.view, positioned: .above, relativeTo: nil)
                }
                destination.placePeek(peek)
                guard binding.pageDidAttach(peek.page, container: peek.browser), peek.browser.window === destinationWindow else {
                    presentTransferRecovery(id, destination: destination, pages: live, retry: retry); return
                }
            }
            guard ownership.finishCollection(reservation, moved: true, closed: closed) else {
                presentTransferRecovery(id, destination: destination, pages: live, retry: retry); return
            }
            let request = requestedURLs.removeValue(forKey: id)
            let zoom = zoomLevels.removeValue(forKey: id)
            let loading = loadingTabs.remove(id) != nil
            failures.removeValue(forKey: id)
            browsers.removeValue(forKey: id); browserProfiles.removeValue(forKey: id); liveTabModels.removeValue(forKey: id)
            panes.removeValue(forKey: id)?.removeFromSuperview()
            let leftPlaceholder = presentation.leavePlaceholder(id, state: store.state)
            renderedPaneIDs.removeAll { $0 == id }
            if focusedTabID == id { focusedTabID = presentation.preferredFocusedTabID }
            peeks.removeValue(forKey: peek.page.identifier)
            if !page.isClosed {
                destination.browsers[id] = browser
                destination.browserProfiles[id] = tab.profileID
                destination.liveTabModels[id] = store.state.tab(id) ?? tab
                destination.requestedURLs[id] = request ?? tab.url
                destination.zoomLevels[id] = zoom
                destination.failures.removeValue(forKey: id)
                if loading { destination.loadingTabs.insert(id) }
                browser.delegate = destination
                destination.attachedPageIDs.insert(page.identifier)
            }
            if !peek.page.isClosed {
                destination.peeks[peek.page.identifier] = peek
                destination.wirePeek(peek, binding: binding)
                destination.zoomLevels[peek.identity] = zoomLevels.removeValue(forKey: peek.identity)
                destination.inputRevisions[peek.identity] = inputRevisions.removeValue(forKey: peek.identity)
            } else {
                zoomLevels.removeValue(forKey: peek.identity); inputRevisions.removeValue(forKey: peek.identity)
                peek.finish()
            }
            destination.presentation.adopt(id, state: store.state, foreground: placement == nil)
            if placement == nil { destination.focusedTabID = id }
            finish()
            render(store.state); destination.render(store.state)
            destination.layoutPeeks()
            requestNativeSelection(); destination.requestNativeSelection()
            destination.prepareStoreContext()
            if !untargeted { destination.window?.makeKeyAndOrderFront(nil) }
            if leftPlaceholder, !page.isClosed { destination.capturePlaceholderSnapshot(id, page: page, from: self) }
            if let placement { destination.placeArrival(id, placement: placement) }
            return
        }
        if live.allSatisfy({ PCNativeBrowserApplication.owner(of: $0) === nativeBinding }),
           let binding = nativeBinding, let sourceWindow = window {
            if !page.isClosed {
                if destination.panes[id]?.browser === browser { destination.panes[id]?.browser = nil }
                if let pane = panes[id], pane.browser !== browser || browser.window !== sourceWindow { pane.browser = browser }
                guard binding.pageDidAttach(page, container: browser), browser.window === sourceWindow else {
                    presentTransferRecovery(id, destination: destination, pages: live, retry: retry); return
                }
            }
            if !peek.page.isClosed {
                guard binding.pageDidAttach(peek.page, container: peek.browser), peek.browser.window === sourceWindow else {
                    presentTransferRecovery(id, destination: destination, pages: live, retry: retry); return
                }
            }
            guard ownership.finishCollection(reservation, moved: false, closed: closed) else {
                presentTransferRecovery(id, destination: destination, pages: live, retry: retry); return
            }
            if !page.isClosed { attachedPageIDs.insert(page.identifier) }
            destination.discardTransferPane(id)
            finish()
            render(store.state); destination.render(store.state)
            layoutPeeks()
            requestNativeSelection(); destination.requestNativeSelection()
            if failed, !untargeted { destination.refuseTabMove() }
            if untargeted, !page.isClosed { holdFailedReturn(id) }
            return
        }
        presentTransferRecovery(id, destination: destination, pages: live, retry: retry)
    }

    private func discardTransferPane(_ id: UUID) {
        guard browsers[id] == nil, let pane = panes.removeValue(forKey: id) else { return }
        pane.browser = nil
        pane.removeFromSuperview()
        if renderedPaneIDs.contains(id) { renderedPaneIDs = [] }
    }

    func nativePage(forTabID id: UUID) -> PCNativePage? {
        guard let page = (browsers[id] ?? coveredPages[id]?.browser)?.nativePage, !page.isClosed else { return nil }
        return page
    }
    func holdsContent(forTabID id: UUID) -> Bool {
        nativePage(forTabID: id) != nil || noteEditors[id] != nil || easelEditors[id] != nil
    }

    func hasPendingNativePage(in ids: Set<UUID>) -> Bool {
        ids.contains { id in
            (browsers[id].map { $0.nativePage == nil && $0.isLoading } ?? false)
                || embeddedPagePool(forTabID: id)?.hasPendingCreation == true
        }
    }

    var currentTabID: UUID? {
        WindowPaneFocus.currentTab(fullscreen: nativeFullscreenTabID, focused: focusedTabID, selection: selectedTabIDs)
    }
    var currentBrowser: PCBrowserView? {
        if activePeek != nil { return activePagePeek?.browser }
        return currentTabID.flatMap(paneBrowser)
    }
    func paneBrowser(_ id: UUID) -> PCBrowserView? {
        guard !transferringTabIDs.contains(id), let tab = store.state.tab(id),
              !InternalPage.isInternal(tab.url) else { return nil }
        return browsers[id]
    }

    var canCreateNote: Bool {
        !isPopupWindow && !isPrivateBrowsing && presentation.isReady && !isClosing && !wholeWindowClose
            && !windowClosePending && window?.attachedSheet == nil && !store.isProfileRemovalPending(activeProfileID)
            && transferringTabIDs.isEmpty && resolvingTransfers.isEmpty && activePeek == nil
    }
    var canCreateNoteInSplit: Bool { canCreateNote && !selectedTabIDs.isEmpty && selectedTabIDs.count < 4 }
}

extension PCNativePage {
    func beginPlaceholderSnapshot(in window: NSWindow) -> PCNativePageCapture? {
        responds(to: #selector(beginPlaceholderCapture(in:))) ? beginPlaceholderCapture(in: window) : beginCapture(in: window)
    }
}
