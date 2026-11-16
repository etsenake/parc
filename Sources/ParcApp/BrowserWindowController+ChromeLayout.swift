import AppKit
import Combine

extension BrowserWindowController {
    func layoutChrome() {
        let fingerprint = chromeGeometryFingerprint()
        let dirtyHostedLayout = pageHost.needsLayout
            || pageHost.subviews.contains(where: \.needsLayout)
            || extensionSidePanel.needsLayout
            || extensionSidePanel.subviews.contains(where: \.needsLayout)
        if LayoutChromeGeometrySkip.shouldReturnEarly(
            previous: lastAppliedChromeGeometryFingerprint,
            next: fingerprint,
            dirtyHostedLayout: dirtyHostedLayout
        ) {
            return
        }
        refreshSidebarHoverZones()
        refreshStartPageChrome()
        if sidebarChromePass == .geometry {
            layoutChromeGeometry()
            lastAppliedChromeGeometryFingerprint = fingerprint
            return
        }
        let fullPass = sidebarChromePass == .full
        defer { if fullPass { pageHost.validateDrop() } }
        defer { if fullPass { pageCapture?.reconcile() } }
        let sidebarAvailable = libraryView == nil && !isPopupWindow && nativeFullscreenTabID == nil
        let sidebarVisible = sidebarAvailable && sidebarPresentation != .hidden
        let resizable = sidebarVisible && (!sidebarMotionVisible || isSidebarResizing)
        if !resizable { sidebarResizeRegion.isHidden = true }
        let sidebarWidth = sidebarLayoutWidth
        let bounds = rootView.bounds
        let layoutKey: [CGFloat] = [bounds.width, bounds.height, sidebarWidth,
            nativeFullscreenTabID == nil ? 0 : 1, libraryView == nil ? 0 : 1,
            findHost.isHidden ? 0 : 1,
            extensionSidePanelVisible ? 1 : 0]
        if sidebarMotionLayoutKey != layoutKey {
            sidebarPreviews?.dismiss()
            if libraryMotion.isAnimating {
                libraryMotion.cancel(); pageHost.needsLayout = true; extensionSidePanel.needsLayout = true
            }
            if !preparingSidebarMotion, sidebarMotion.isAnimating {
                settleSidebarMotion()
            }
        }
        sidebarMotionLayoutKey = layoutKey
        sidebarContainer.isHidden = !sidebarAvailable
        let floatingSurface = sidebarPresentation == .floating || sidebarFloatingSurface
        if sidebarContainer.drawsBackground != floatingSurface { sidebarContainer.drawsBackground = floatingSurface }
        let frames = chromeFrames(sidebarWidth: sidebarWidth, in: bounds)
        let sidebarMoved = sidebarContainer.frame != frames.sidebar
        sidebarContainer.frame = frames.sidebar
        sidebarContainer.floatingCornerRadius = floatingSurface ? FloatingSidebarSurface.cornerRadius : nil
        sidebarContainer.docksFloatingSurface = fullPass && sidebarFloatingSurface && sidebarPresentation == .locked
        if fullPass { sidebarContainer.preparesFloatingDock = false }
        sidebar.layer?.cornerRadius = floatingSurface ? FloatingSidebarSurface.cornerRadius : 0
        sidebar.clipsToBounds = floatingSurface
        if fullPass, sidebarMoved { sidebarContainer.invalidateCoordinates() }
        sidebar.frame = sidebarContainer.bounds
        let presented = sidebarAvailable && sidebarPresentation.presents(inMotion: sidebarMotionVisible)
        let dismissed = sidebar.isPresented && !presented
        sidebar.isPresented = presented
        if dismissed, sidebarOwnsFirstResponder { window?.makeFirstResponder(nil) }
        sidebar.setFloating(sidebarPresentation != .locked)
        if resizable {
            sidebarResizeRegion.frame = SidebarResizeRegionView.frame(trailing: sidebarContainer.frame, in: bounds)
            sidebarResizeRegion.isHidden = false
        }
        libraryView?.isHidden = nativeFullscreenTabID != nil
        pageHost.layer?.cornerRadius = pageCornerRadius
        pageShadow.cornerRadius = isPopupWindow ? WindowFrameThickness.cornerRadius(for: SidebarChromeFrames.pageInset) : nil
        libraryView?.frame = frames.library
        popupChrome.isHidden = frames.popupChrome.height == 0
        popupChrome.frame = frames.popupChrome
        var flushedHostedLayout = false
        let pageHostMoved = pageHost.frame != frames.pageHost
        pageHost.frame = frames.pageHost
        if pageHostMoved, loadedStartPage?.superview != nil { loadedStartPage?.invalidateCoordinates() }
        splitView.dividerThickness = frameThickness
        pageShadow.place(around: frames.pageHost)
        refreshPageShadow()
        splitMarginHandle.frame = splitMarginFrame(frames)
        let sidePanelHidden = !frames.showsSidePanel
        let sidePanelMoved = extensionSidePanel.isHidden != sidePanelHidden
            || extensionSidePanel.frame != frames.sidePanel
        extensionSidePanel.isHidden = sidePanelHidden
        extensionSidePanel.frame = frames.sidePanel
        if sidePanelMoved || extensionSidePanel.needsLayout
            || extensionSidePanel.subviews.contains(where: \.needsLayout) {
            extensionSidePanel.layoutSubtreeIfNeeded()
            flushedHostedLayout = true
        }
        loadingIndicator.frame = PageLoadingIndicatorHost.frame(pageHost: frames.pageHost)
        layoutFrameCrank(frames)
        refreshWindowButtons()
        defer { lastAppliedChromeGeometryFingerprint = fingerprint }
        guard fullPass else { return }
        if pageHostMoved {
            pageHost.needsLayout = true
            pageHost.layoutSubtreeIfNeeded()
            flushedHostedLayout = true
        } else if pageHost.needsLayout
            || pageHost.subviews.contains(where: \.needsLayout) {
            pageHost.layoutSubtreeIfNeeded()
            flushedHostedLayout = true
        }
        refreshLoadingIndicators()
        layoutPeeks()
        for pane in easelEditors.values { pane.editor.refreshPageVisibility() }
        if flushedHostedLayout {
            synchronizeNativeLayout()
        }
        layoutFindBar()
        refreshPaymentControls()
        commandBar?.refreshPosition()
        windowKeyViews.relink()
    }

    private func chromeGeometryFingerprint() -> LayoutChromeGeometryFingerprint {
        let bounds = rootView.bounds
        return LayoutChromeGeometryFingerprint(
            boundsWidth: bounds.width,
            boundsHeight: bounds.height,
            sidebarWidth: sidebarLayoutWidth,
            presentation: sidebarPresentation,
            motionVisible: sidebarMotionVisible,
            floatingSurface: sidebarFloatingSurface,
            revealsAnchored: sidebarRevealsAnchored,
            previewingHidden: sidebarPreviewingHidden,
            fullscreen: nativeFullscreenTabID != nil,
            library: libraryView != nil,
            libraryContentWidth: libraryContentWidth,
            popup: isPopupWindow,
            sidePanel: extensionSidePanelVisible,
            findVisible: !findHost.isHidden,
            resizing: isSidebarResizing,
            currentTabID: currentTabID,
            activePeekID: activePeek?.identity,
            commandBarOpen: commandBar != nil,
            windowClosePending: windowClosePending,
            transferringTabIDs: transferringTabIDs.sorted { $0.uuidString < $1.uuidString },
            frameThickness: frameThickness
        )
    }

    private var frameThickness: CGFloat {
        isPopupWindow ? SidebarChromeFrames.pageInset : WindowFramePreferences.shared.thickness
    }

    private var pageCornerRadius: CGFloat {
        nativeFullscreenTabID != nil ? 0
            : isPopupWindow ? WindowFrameThickness.cornerRadius(for: SidebarChromeFrames.pageInset) : PageCard.cornerRadius
    }

    private func splitMarginFrame(_ frames: SidebarChromeFrames) -> NSRect {
        let page = frames.pageHost, inset = frameThickness
        guard WindowFrameThickness.showsSplitGrip(inset), !frames.showsSidePanel, nativeFullscreenTabID == nil, page.height > 0,
              rootView.bounds.maxX - page.maxX >= inset else { return .zero }
        return NSRect(x: page.maxX, y: page.minY, width: inset, height: page.height)
    }

    private func chromeFrames(sidebarWidth: CGFloat, in bounds: NSRect) -> SidebarChromeFrames {
        let placement = SidebarPresentationFrame(sidebarPresentation, inMotion: sidebarMotionVisible,
                                                 floatingSurface: sidebarFloatingSurface, revealsAnchored: sidebarRevealsAnchored)
        return SidebarChromeFrames(bounds: bounds, sidebarWidth: sidebarWidth, presentation: sidebarPresentation, placement: placement,
            previewingHidden: sidebarPreviewingHidden, fullscreen: nativeFullscreenTabID != nil, library: libraryView != nil,
            libraryContentWidth: libraryContentWidth, popup: isPopupWindow,
            sidePanel: extensionSidePanelVisible, thickness: frameThickness)
    }
    private func refreshWindowButtons() {
        let sidebarless = isPopupWindow && nativeFullscreenTabID == nil
        let phase = WindowFullscreenPhase.current(fullscreenPhase, inFullScreen: window?.styleMask.contains(.fullScreen) == true)
        let showsOwn = WindowFullscreenPhase.apply(phase, sidebarless: sidebarless, system: systemWindowButtons)
        sidebar.showsWindowButtons = showsOwn
        libraryView?.showsWindowButtons = showsOwn && !sidebarless
        loadedStartPage?.showsWindowButtons = showsOwn
    }
    func setFullscreenPhase(_ phase: WindowFullscreenPhase?) {
        guard fullscreenPhase != phase else { return }
        fullscreenPhase = phase
        refreshWindowButtons()
    }

    func scheduleWindowFrameLayout() {
        guard !windowFrameLayoutPending else { return }
        windowFrameLayoutPending = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.windowFrameLayoutPending = false
            self.applyWindowFrameThickness()
        }
    }

    private func applyWindowFrameThickness() {
        guard !isClosing, !wholeWindowClose else { return }
        let preferences = WindowFramePreferences.shared
        PageCard.follow(thickness: preferences.thickness)
        setContentResizeReason(.frameAdjust, active: preferences.isAdjusting)
        pageShadow.needsDisplay = true
        if !isPopupWindow { splitView.refreshPaneCorners(radius: PageCard.cornerRadius) }
        let ending = windowFrameAdjustApplied && !preferences.isAdjusting
        windowFrameAdjustApplied = preferences.isAdjusting
        if ending { lastAppliedChromeGeometryFingerprint = nil }
        guard sidebarChromePass == .full, !sidebarMotion.isAnimating, !libraryMotion.isAnimating else { return }
        if preferences.isAdjusting {
            sidebarChromePass = .geometry
            layoutChrome()
            sidebarChromePass = .full
        } else {
            layoutChrome()
        }
    }

    var isPresentingFrameCrank: Bool { frameCrank != nil }

    var canAdjustWindowFrame: Bool {
        frameCrank == nil && !isClosing && !wholeWindowClose && !isPopupWindow && libraryView == nil
            && nativeFullscreenTabID == nil && window != nil && !WindowFramePreferences.shared.loadError
    }

    func windowFrameContextMenu(rootHit hit: NSView?) -> NSMenu? {
        guard let hit else { return windowFrameContextMenu() }
        for owner in [pageHost, sidebarContainer, extensionSidePanel, findHost, popupChrome, splitMarginHandle] as [NSView]
        where hit === owner || hit.isDescendant(of: owner) { return nil }
        if let libraryView, hit.isDescendant(of: libraryView) { return nil }
        return Self.isInsideControl(hit, below: rootView) ? nil : windowFrameContextMenu()
    }

    func windowFrameContextMenu(sidebarHit hit: NSView?) -> NSMenu? {
        guard let hit else { return windowFrameContextMenu() }
        return Self.isInsideControl(hit, below: sidebarContainer) ? nil : windowFrameContextMenu()
    }

    private static func isInsideControl(_ view: NSView, below root: NSView) -> Bool {
        var current: NSView? = view
        while let candidate = current, candidate !== root {
            if candidate is NSControl || candidate is NSTextView { return true }
            current = candidate.superview
        }
        return false
    }

    func windowFrameContextMenu() -> NSMenu? {
        guard canAdjustWindowFrame else { return nil }
        let menu = NSMenu()
        let item = NSMenuItem(title: "Adjust Window Frame…", action: #selector(adjustWindowFrameFromMenu(_:)), keyEquivalent: "")
        item.target = self
        menu.addItem(item)
        return menu
    }

    @objc private func adjustWindowFrameFromMenu(_ sender: Any?) { presentFrameCrank() }

    func presentFrameCrank() {
        guard canAdjustWindowFrame else { return }
        if let other = Self.frameCrankOwner, other !== self { other.frameCrank?.finishNow(commit: true) }
        if let bar = commandBar { bar.dismiss(restoreFocus: false) }
        if sidebarPresentation == .floating { setSidebarPresentation(.hidden) }
        let crank = WindowFrameCrankView(value: WindowFramePreferences.shared.state.thickness, palette: frameCrankPalette())
        crank.onPreview = { WindowFramePreferences.shared.setPreview($0) }
        crank.onEvent = { [weak self] event in
            if case .end = event { self?.shudderWindowFrame() }
        }
        crank.onFinish = { [weak self, weak crank] commit, value in
            crank?.removeFromSuperview()
            guard let self else { WindowFramePreferences.shared.setPreview(nil); return }
            if Self.frameCrankOwner === self || Self.frameCrankOwner == nil {
                let preferences = WindowFramePreferences.shared
                if commit { try? preferences.setThickness(value) }
                preferences.setPreview(nil)
            }
            if self.frameCrank === crank { self.frameCrank = nil }
            if Self.frameCrankOwner === self { Self.frameCrankOwner = nil }
            self.sidebarHover.isEnabled = !self.isSidebarResizing
            self.onFrameCrankFinished?()
            self.onFrameCrankFinished = nil
        }
        rootView.addSubview(crank, positioned: .above, relativeTo: nil)
        frameCrank = crank
        Self.frameCrankOwner = self
        sidebarHover.isEnabled = false
        layoutFrameCrank(chromeFrames(sidebarWidth: sidebarLayoutWidth, in: rootView.bounds))
        window?.makeKeyAndOrderFront(nil)
        crank.present()
    }

    func abandonFrameCrank() {
        frameCrank?.finishNow(commit: true)
    }

    private func layoutFrameCrank(_ frames: SidebarChromeFrames) {
        guard let crank = frameCrank else { return }
        if libraryView != nil || nativeFullscreenTabID != nil || isClosing {
            crank.finishNow(commit: true)
            return
        }
        let bounds = rootView.bounds
        let docked: CGFloat? = sidebarPresentation == .locked && libraryView == nil && !frames.sidebar.isEmpty ? frames.sidebar.maxX : nil
        let hub = WindowFrameCrankPlacement.hub(in: bounds, dockedSidebarEdge: docked)
        let flippedY = rootView.isFlipped ? bounds.maxY - (hub.y - bounds.minY) : hub.y
        let side = WindowFrameCrankView.side
        crank.frame = rootView.backingAlignedRect(NSRect(x: hub.x - side / 2, y: flippedY - side / 2, width: side, height: side),
                                                  options: .alignAllEdgesNearest)
    }

    private func frameCrankPalette() -> WindowFrameCrankPalette {
        let dark = rootView.palette.isDark
        if store.isEphemeral {
            return WindowFrameCrankPalette(accent: NSColor(srgbRed: 0.30, green: 0.55, blue: 1, alpha: 1),
                                           deep: NSColor(srgbRed: 0.17, green: 0.29, blue: 0.53, alpha: 1),
                                           cap: NSColor(srgbRed: 0.14, green: 0.15, blue: 0.18, alpha: 1), dark: true)
        }
        guard let primary = rootView.theme.primaryColor, rootView.theme.isValid else {
            let accent = NSColor.controlAccentColor.usingColorSpace(.sRGB) ?? .systemBlue
            return WindowFrameCrankPalette(accent: accent, deep: accent.blended(withFraction: 0.35, of: .black) ?? accent,
                                           cap: NSColor(white: dark ? 0.32 : 0.78, alpha: 1), dark: dark)
        }
        let base: NSColor = primary.colorSpace == .displayP3
            ? NSColor(displayP3Red: primary.red, green: primary.green, blue: primary.blue, alpha: 1)
            : NSColor(srgbRed: primary.red, green: primary.green, blue: primary.blue, alpha: 1)
        let rgb = base.usingColorSpace(.sRGB) ?? base
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        rgb.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        let accent = NSColor(hue: hue, saturation: max(0.55, saturation), brightness: dark ? 0.92 : 0.78, alpha: 1)
        let deep = NSColor(hue: hue, saturation: max(0.4, saturation * 0.9), brightness: dark ? 0.55 : 0.62, alpha: 1)
        let cap = NSColor(hue: hue, saturation: min(0.6, max(0.25, saturation)), brightness: dark ? 0.5 : max(0.7, brightness), alpha: 1)
        return WindowFrameCrankPalette(accent: accent, deep: deep, cap: cap, dark: dark)
    }

    private func shudderWindowFrame() {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        let shake = CAKeyframeAnimation(keyPath: "transform.translation.x")
        shake.values = [0, 3.2, -2.8, 2, -1.4, 0.7, 0]
        shake.keyTimes = [0, 0.14, 0.32, 0.5, 0.68, 0.84, 1]
        shake.duration = 0.38
        shake.isAdditive = true
        for view in [pageHost, pageShadow, extensionSidePanel, splitMarginHandle, loadingIndicator] as [NSView] {
            view.layer?.add(shake, forKey: "windowFrameShudder")
        }
    }

    private func layoutChromeGeometry() {
        let bounds = rootView.bounds
        let frames = chromeFrames(sidebarWidth: sidebarLayoutWidth, in: bounds)
        sidebarContainer.frame = frames.sidebar
        sidebar.frame = sidebarContainer.bounds
        libraryView?.frame = frames.library
        if isSidebarResizing, !sidebarResizeRegion.isHidden {
            sidebarResizeRegion.frame = SidebarResizeRegionView.frame(trailing: sidebarContainer.frame, in: bounds)
        }
        if sidebarFloatingSurface && sidebarPresentation == .locked { sidebarContainer.docksFloatingSurface = true }
        pageHost.layer?.cornerRadius = pageCornerRadius
        splitView.dividerThickness = frameThickness
        pageHost.frame = frames.pageHost
        extensionSidePanel.isHidden = !frames.showsSidePanel
        extensionSidePanel.frame = frames.sidePanel
        pageShadow.place(around: frames.pageHost)
        loadingIndicator.frame = PageLoadingIndicatorHost.frame(pageHost: frames.pageHost)
        splitMarginHandle.frame = splitMarginFrame(frames)
        pageHost.needsLayout = true
        pageHost.layoutSubtreeIfNeeded()
        layoutFrameCrank(frames)
        refreshLoadingIndicators()
        for peek in peeks.values { peek.view.frame = pageHost.bounds; peek.view.layoutSubtreeIfNeeded() }
        layoutFindBar()
    }

    func newTab() {
        if isPopupWindow {
            guard window?.isKeyWindow == true, windowCommandSecurityAvailable else { return }
            onRequestBrowserTab?(nil); return
        }
        if focusResidentCommandBar() { return }
        presentCommandBar(newTab: true)
    }
    func focusAddress(anchor: NSView? = nil) {
        if !isPopupWindow, focusResidentCommandBar() { return }
        presentCommandBar(newTab: false, addressAnchor: anchor)
    }

    var showsStartPage: Bool {
        guard let page = loadedStartPage else { return false }
        return page.superview === splitView && !isClosing && !isPopupWindow
    }
}
