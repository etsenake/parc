import AppKit

/// P1-AJ: layoutChrome → layoutSubtreeIfNeeded must not dirty the side-panel
/// header fill when content/close/title frames are already current. Geometry
/// and appearance that affect the painted fill still redraw.
@main
@MainActor
struct ExtensionSidePanelNeedsDisplayTests {
    static func main() {
        _ = NSApplication.shared
        var checks = 0
        func check(_ condition: @autoclosure () -> Bool, _ message: String) {
            precondition(condition(), message); checks += 1
        }

        let panel = ExtensionSidePanelView(frame: NSRect(x: 0, y: 0, width: 320, height: 600))
        let window = NSWindow(contentRect: panel.frame, styleMask: [.titled], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        window.contentView = panel

        panel.layout()
        let afterFirst = panel.headerDisplayInvalidations
        let contentFrame = panel.content.frame
        let closeFrame = panel.closeButton.frame
        let title = panel.subviews.compactMap { $0 as? NSTextField }.first!
        let titleFrame = title.frame
        check(afterFirst == 1, "first layout dirties the header fill once")
        check(contentFrame.height == 600 - ExtensionSidePanelView.headerHeight, "layout places content below the header")
        check(!panel.closeButton.isHidden && !title.isHidden, "wide panel shows close and title")

        panel.layout()
        check(panel.headerDisplayInvalidations == afterFirst
              && panel.content.frame == contentFrame
              && panel.closeButton.frame == closeFrame
              && title.frame == titleFrame,
              "no-op layout skips header invalidation when frames already match")

        panel.setFrameSize(NSSize(width: 280, height: 600))
        panel.layout()
        check(panel.headerDisplayInvalidations == afterFirst + 1
              && panel.content.frame.width == 280
              && title.frame.width < titleFrame.width,
              "a width change still dirties and rewrites chrome frames")

        let afterWidth = panel.headerDisplayInvalidations
        panel.layout()
        check(panel.headerDisplayInvalidations == afterWidth,
              "a follow-up layout at the new size remains a no-op")

        panel.setFrameSize(NSSize(width: 100, height: 600))
        panel.layout()
        check(panel.headerDisplayInvalidations == afterWidth + 1 && title.isHidden,
              "crossing the title visibility threshold still dirties")

        let afterNarrow = panel.headerDisplayInvalidations
        panel.setFrameSize(NSSize(width: 320, height: 480))
        panel.layout()
        check(panel.headerDisplayInvalidations == afterNarrow + 1
              && panel.content.frame.height == 480 - ExtensionSidePanelView.headerHeight
              && !title.isHidden,
              "a height change still dirties content geometry")

        let afterHeight = panel.headerDisplayInvalidations
        panel.viewDidChangeEffectiveAppearance()
        check(panel.headerDisplayInvalidations == afterHeight + 1,
              "appearance changes that affect the fill still dirty")

        print("ExtensionSidePanelNeedsDisplayTests: \(checks) checks passed")
    }
}
