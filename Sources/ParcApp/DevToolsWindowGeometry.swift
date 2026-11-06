import AppKit

///
/// Docked left/right/bottom bounds stay with Chromium's resizing strategy.
enum DevToolsWindowGeometry {
    ///
    static let autosaveSuffix = ".devToolsWindowAutosaveFrame"
    /// `initWithContentRect:styleMask:backing:defer:` mask `0x800f`.
    static let styleMask: NSWindow.StyleMask = [
        .titled, .closable, .miniaturizable, .resizable, .fullSizeContentView
    ]
    /// `setCollectionBehavior:` value `0x100`.
    static let collectionBehavior: NSWindow.CollectionBehavior = .fullScreenPrimary
    /// Used only when `setFrameUsingName:` fails and the window is still empty.
    ///
    /// Parc has no hosting controller, so this first-open size is an adaptation.
    static let emptyRestoreFallbackSize = NSSize(width: 840, height: 640)

    static func frameAutosaveName(bundleIdentifier: String?) -> String {
        (bundleIdentifier ?? "") + autosaveSuffix
    }

    static func applyChrome(to window: NSWindow) {
        window.isOpaque = false
        window.collectionBehavior = collectionBehavior
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.title = "Developer Tools"
    }

    @discardableResult
    static func restoreFrame(_ window: NSWindow, using name: String,
                             fallbackContentSize: NSSize = emptyRestoreFallbackSize) -> Bool {
        if window.setFrameUsingName(name) { return true }
        if window.frame.width < 1 || window.frame.height < 1 {
            window.setContentSize(NSSize(width: max(1, fallbackContentSize.width),
                                         height: max(1, fallbackContentSize.height)))
        }
        window.center()
        return false
    }
}

/// Planned undocked DevTools root frames for one layout pass. Identical child
/// frames/hidden mean frame writes + `synchronizeLayout` are a true no-op;
/// reveal (`showToolsWindowIfHidden`) still runs on every layout.
struct DevToolsRootLayoutPlan: Equatable {
    var sidePanelFrame: NSRect
    var pageContainerFrame: NSRect
    var errorLabelFrame: NSRect
    var sidePanelHidden: Bool
}

/// True no-op gate for undocked root frame writes / geometry sync. Real bounds,
/// side panel, or error-footer changes still rewrite frames and sync hosts.
enum DevToolsRootLayoutSkip {
    static func plan(bounds: NSRect, sidePanelVisible: Bool,
                     errorHidden: Bool) -> DevToolsRootLayoutPlan {
        let errorHeight: CGFloat = errorHidden ? 0 : 44
        let width = min(320, max(0, bounds.width - 200))
        return DevToolsRootLayoutPlan(
            sidePanelFrame: NSRect(x: bounds.width - width, y: errorHeight,
                                   width: width,
                                   height: max(0, bounds.height - errorHeight)),
            pageContainerFrame: NSRect(
                x: 0, y: errorHeight,
                width: max(0, bounds.width - (sidePanelVisible ? width : 0)),
                height: max(0, bounds.height - errorHeight)),
            errorLabelFrame: NSRect(x: 12, y: 8,
                                    width: max(0, bounds.width - 24), height: 32),
            sidePanelHidden: !sidePanelVisible
        )
    }

    /// Surfaces already match the plan: skip frame writes and onLayout.
    static func surfacesAlreadyMatch(
        _ plan: DevToolsRootLayoutPlan,
        sidePanelFrame: NSRect,
        sidePanelHidden: Bool,
        pageContainerFrame: NSRect,
        errorLabelFrame: NSRect
    ) -> Bool {
        sidePanelFrame == plan.sidePanelFrame
            && sidePanelHidden == plan.sidePanelHidden
            && pageContainerFrame == plan.pageContainerFrame
            && errorLabelFrame == plan.errorLabelFrame
    }
}
