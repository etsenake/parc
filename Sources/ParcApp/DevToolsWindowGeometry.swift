import AppKit

enum DevToolsWindowGeometry {
    static let autosaveSuffix = ".devToolsWindowAutosaveFrame"
    static let styleMask: NSWindow.StyleMask = [
        .titled, .closable, .miniaturizable, .resizable, .fullSizeContentView
    ]
    static let collectionBehavior: NSWindow.CollectionBehavior = .fullScreenPrimary
    static let emptyRestoreFallbackSize = NSSize(width: 840, height: 640)
    static let defaultTitle = "Developer Tools"

    static func frameAutosaveName(bundleIdentifier: String?) -> String {
        (bundleIdentifier ?? "") + autosaveSuffix
    }

    static func applyChrome(to window: NSWindow) {
        window.isOpaque = false
        window.collectionBehavior = collectionBehavior
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.title = defaultTitle
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

struct DevToolsRootLayoutPlan: Equatable {
    var sidePanelFrame: NSRect
    var pageContainerFrame: NSRect
    var errorLabelFrame: NSRect
    var sidePanelHidden: Bool
}

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
