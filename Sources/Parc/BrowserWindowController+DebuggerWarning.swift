import AppKit
import ParcEngine
import ParcKit

extension BrowserWindowController {
    private static let debuggerWarningAnnouncements = DebuggerWarningAnnouncements<PCNativeDebuggerWarning>()

    func setupDebuggerWarnings() {
        menuObservers.append(NotificationCenter.default.addObserver(
            forName: NSNotification.Name(PCNativePageDebuggerWarningsDidChangeNotification), object: nil, queue: .main
        ) { [weak self] notification in
            MainActor.assumeIsolated {
                guard let self, let page = notification.object as? PCNativePage else { return }
                self.debuggerWarningsDidChange(page)
            }
        })
    }

    private func debuggerWarningsDidChange(_ page: PCNativePage) {
        guard presentation.isReady, !isClosing, !wholeWindowClose, !page.isClosed,
              peeks[page.identifier] != nil || browsers.values.contains(where: { $0.nativePage === page }) else { return }
        refreshDeveloperToolbars()
    }

    var debuggerWarningPalette: ParcToastPalette {
        ParcToastPalette(theme: rootView.theme,
                         isDark: rootView.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua,
                         basicBackground: windowBasicBackground)
    }

    func refreshDebuggerWarningPalettes() {
        let palette = debuggerWarningPalette
        for pane in panes.values where !pane.debuggerWarning.warnings.isEmpty { pane.debuggerWarning.apply(palette) }
        for peek in presentedPeeks where !peek.view.debuggerWarning.warnings.isEmpty { peek.view.debuggerWarning.apply(palette) }
    }

    @discardableResult
    func configureDebuggerWarning(_ strip: DebuggerWarningStrip, browser: PCBrowserView?, visible: Bool) -> Bool {
        let page = browser?.nativePage.flatMap { page -> PCNativePage? in
            page.isClosed || !page.responds(to: #selector(getter: PCNativePage.debuggerWarnings)) ? nil : page
        }
        let warnings = page?.debuggerWarnings ?? []
        let suppressed = !visible || isClosing || wholeWindowClose || libraryView != nil
        let ownedFocus = strip.ownsFocus
        let keyViewsChanged = strip.update(warnings, palette: debuggerWarningPalette, suppressed: suppressed)
        if ownedFocus, !strip.ownsFocus, let page, window?.isKeyWindow == true, commandBar == nil {
            window?.makeFirstResponder(page.nativeView)
        }
        strip.onCancel = { [weak self, weak page] warning in
            guard let self, let page, !page.isClosed,
                  page.responds(to: #selector(PCNativePage.cancelDebuggerWarning(_:))),
                  page.cancelDebuggerWarning(warning) else { return }
            self.refreshDeveloperToolbars()
        }
        strip.onClose = { [weak self, weak page] warning in
            guard let self, let page, !page.isClosed,
                  page.responds(to: #selector(PCNativePage.dismissDebuggerWarning(_:))),
                  page.dismissDebuggerWarning(warning) else { return }
            self.refreshDeveloperToolbars()
        }
        guard !suppressed, let window, window.isKeyWindow else { return keyViewsChanged }
        for warning in Self.debuggerWarningAnnouncements.claim(strip.warnings) {
            NSAccessibility.post(element: window, notification: .announcementRequested,
                                 userInfo: [.announcement: warning.message,
                                            .priority: NSAccessibilityPriorityLevel.high.rawValue])
        }
        return keyViewsChanged
    }

    @objc(nativeBrowser:focusDebuggerWarningForPage:)
    func nativeBrowser(_ browser: PCNativeBrowserWindow, focusDebuggerWarningFor page: PCNativePage) -> Bool {
        guard browser === nativeBinding, presentation.isReady, !isClosing, !wholeWindowClose, !page.isClosed,
              let window, window.isKeyWindow, window.attachedSheet == nil, commandBar == nil else { return false }
        let strip: DebuggerWarningStrip?
        if activePeek != nil { strip = activePagePeek.flatMap { $0.browser.nativePage === page ? $0.view.debuggerWarning : nil } }
        else { strip = panes.first(where: { $0.value.browser?.nativePage === page })?.value.debuggerWarning }
        return strip?.focusFirstCancel() == true
    }
}
