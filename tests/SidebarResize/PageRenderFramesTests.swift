import AppKit

@MainActor final class Content: NSView {
    var onLayout: (() -> Void)?
    override var isFlipped: Bool { true }
    override func layout() { super.layout(); onLayout?() }
}

@main @MainActor struct PageRenderFramesTests {
    static var count = 0
    static func check(_ value: @autoclosure () -> Bool, _ message: String) {
        count += 1
        guard value() else { fatalError("PageRenderFrames: \(message)") }
    }
    static func size(_ width: CGFloat, _ height: CGFloat = 600) -> CGSize { CGSize(width: width, height: height) }
    static func main() {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 1200, height: 700),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 1200, height: 700))
        root.wantsLayer = true; window.contentView = root
        func pane(_ width: CGFloat) -> (Content, PageContentResizer) {
            let content = Content(frame: NSRect(origin: .zero, size: size(width)))
            root.addSubview(content)
            return (content, PageContentResizer())
        }
        func attach(_ browser: PCBrowserView, to content: Content, _ resizer: PageContentResizer) {
            content.addSubview(browser)
            content.onLayout = { resizer.place(browser, in: content) }
            resizer.place(browser, in: content)
        }

        let (content, resizer) = pane(800)
        let page = PCNativePage()
        page.host.infobarHeight = 40
        let browser = PCBrowserView(frame: .zero, page: page)
        browser.pane.dockedWidth = 300
        attach(browser, to: content, resizer)
        root.layoutSubtreeIfNeeded()
        let renderer = page.host.renderer
        check(browser.frame.size == size(800) && renderer.frame.size == size(500, 560), "the renderer sits beside DevTools below the shelf")
        let paneLayouts = browser.pane.layouts
        resizer.place(browser, in: content)
        check(browser.pane.layouts == paneLayouts && renderer.frame.size == size(500, 560),
              "an unchanged page size does not relayout docked tools or the renderer")
        content.frame.size.width = 820
        root.layoutSubtreeIfNeeded()
        check(browser.frame.size == size(820) && renderer.frame.size == size(520, 560) && browser.pane.layouts == paneLayouts + 1,
              "an intrinsic size change still flushes the hosted Chromium surface in the same pass")
        content.frame.size.width = 800
        root.layoutSubtreeIfNeeded()
        check(browser.frame.size == size(800) && renderer.frame.size == size(500, 560),
              "restoring the intrinsic size returns the renderer to the docked surface")
        page.draw()
        resizer.mode = .throttle
        root.layoutSubtreeIfNeeded()
        check(page.liveLeases == 1 && resizer.hold.lockedSize == nil && resizer.hold.pendingFrames.isEmpty,
              "a drawn page holds nothing when the drag starts")
        func resize(_ content: Content, _ width: CGFloat) {
            content.frame.size.width = width
            root.layoutSubtreeIfNeeded()
        }
        let sent = renderer.sentSizes.count
        resize(content, 790)
        check(resizer.hold.lockedSize == size(790) && renderer.frame.size == size(490, 560), "the first step reaches the renderer and holds")
        let heldLayouts = browser.pane.layouts
        resize(content, 780); resize(content, 770)
        check(renderer.sentSizes.count == sent + 1 && browser.frame.size == size(790), "later steps wait for its frame")
        check(browser.pane.layouts == heldLayouts, "a held size does not relayout docked tools")
        page.draw()
        check(resizer.hold.lockedSize == nil && resizer.hold.pendingFrames.isEmpty, "that frame's report matches and releases")
        root.layoutSubtreeIfNeeded()
        check(resizer.hold.lockedSize == size(770) && renderer.frame.size == size(470, 560), "the latest size follows and holds")
        page.draw()
        root.layoutSubtreeIfNeeded()
        check(resizer.hold.lockedSize == nil && resizer.hold.pendingFrames.isEmpty && renderer.sentSizes.count == sent + 2,
              "one size per report, nothing queued once drawn")
        resize(content, 770.5)
        check(resizer.hold.lockedSize == nil && browser.frame.size.width == 770.5, "a change within a point follows live")
        resize(content, 760)
        resize(content, 750)
        page.draw(size(480, 560))
        check(resizer.hold.lockedSize == nil && resizer.hold.pendingFrames.isEmpty, "an older frame's report still releases")
        root.layoutSubtreeIfNeeded()
        check(resizer.hold.lockedSize == size(750), "and the latest size is held next")
        resizer.mode = .intrinsic
        root.layoutSubtreeIfNeeded()
        check(page.liveLeases == 0 && browser.frame == content.bounds && renderer.frame.size == size(450, 560),
              "the drag's end fills the content")

        let (shelved, shelvedResizer) = pane(800)
        let still = PCNativePage()
        still.host.infobarHeight = 40
        let stillBrowser = PCBrowserView(frame: .zero, page: still)
        attach(stillBrowser, to: shelved, shelvedResizer)
        root.layoutSubtreeIfNeeded()
        still.draw()
        shelvedResizer.mode = .throttle
        root.layoutSubtreeIfNeeded()
        check(shelvedResizer.hold.lockedSize == nil && shelvedResizer.hold.pendingFrames.isEmpty, "the shelf's height is added back")
        resize(shelved, 760)
        check(shelvedResizer.hold.lockedSize == size(760) && still.host.renderer.frame.size == size(760, 560), "its first step holds")
        still.draw()
        root.layoutSubtreeIfNeeded()
        check(shelvedResizer.hold.lockedSize == nil && stillBrowser.frame.size == size(760), "and its report releases")
        shelvedResizer.mode = .intrinsic

        let (target, targetResizer) = pane(700)
        targetResizer.mode = .throttle
        content.onLayout = nil; browser.removeFromSuperview()
        root.layoutSubtreeIfNeeded()
        page.draw()
        attach(browser, to: target, targetResizer)
        check(page.liveLeases == 1 && renderer.frame.size == size(400, 560) && targetResizer.hold.lockedSize == size(700),
              "a moved page holds its new size until its renderer draws it")
        page.draw()
        root.layoutSubtreeIfNeeded()
        check(targetResizer.hold.lockedSize == nil && browser.frame.size == size(700), "its first report releases it")
        resizer.mode = .throttle
        check(page.liveLeases == 1, "the old pane's next mode change does not observe the moved page")
        resizer.mode = .intrinsic
        targetResizer.mode = .intrinsic

        let (older, olderResizer) = pane(800)
        let legacy = PCNativePage(olderEngine: true)
        let legacyBrowser = PCBrowserView(frame: .zero, page: legacy)
        attach(legacyBrowser, to: older, olderResizer)
        root.layoutSubtreeIfNeeded()
        olderResizer.mode = .throttle
        check(olderResizer.hold.mode == .intrinsic && legacy.liveLeases == 0, "no report keeps the page intrinsic")
        let before = legacy.host.renderer.sentSizes.count
        for width in stride(from: 790, through: 750, by: -10) { resize(older, CGFloat(width)) }
        check(legacy.host.renderer.sentSizes.count == before + 5 && legacyBrowser.frame.size == size(750),
              "every size reaches the renderer")

        window.close()
        print("PageRenderFrames: \(count) assertions passed")
    }
}
