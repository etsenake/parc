import AppKit

extension BrowserWindowController {
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

    func configureDebuggerWarning(_ strip: DebuggerWarningStrip, browser: PCBrowserView?, visible: Bool) {
        let page = browser?.nativePage.flatMap { page -> PCNativePage? in
            page.isClosed || !page.responds(to: #selector(getter: PCNativePage.debuggerWarnings)) ? nil : page
        }
        let warnings = page?.debuggerWarnings ?? []
        let suppressed = !visible || isClosing || wholeWindowClose || libraryView != nil
        let ownedFocus = strip.ownsFocus
        let appeared = strip.update(warnings, palette: debuggerWarningPalette, suppressed: suppressed)
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
        guard !suppressed, let window, window.isKeyWindow else { return }
        for warning in appeared {
            NSAccessibility.post(element: window, notification: .announcementRequested,
                                 userInfo: [.announcement: warning.message,
                                            .priority: NSAccessibilityPriorityLevel.high.rawValue])
        }
    }
}
