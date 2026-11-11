import AppKit
import QuartzCore

@MainActor final class FakePage: NSView, RenderFrameReporting {
    final class Lease: RenderFrameObservation {
        var handler: ((CGSize) -> Void)?
        func invalidate() { handler = nil }
    }
    var reports = true
    var viewport = CGSize.zero
    private(set) var leases: [Lease] = []
    private(set) var sentSizes: [CGSize] = []
    override var isFlipped: Bool { true }
    override func setFrameSize(_ newSize: NSSize) {
        if newSize != frame.size { sentSizes.append(newSize) }
        super.setFrameSize(newSize)
    }
    var renderFrameViewport: CGSize { reports ? viewport : .zero }
    func observeRenderFrameViewport(_ handler: @escaping (CGSize) -> Void) -> RenderFrameObservation? {
        guard reports else { return nil }
        let lease = Lease(); lease.handler = handler; leases.append(lease)
        return lease
    }
    var liveLeases: Int { leases.filter { $0.handler != nil }.count }
    func emit(_ size: CGSize) { viewport = size; leases.forEach { $0.handler?(size) } }
    func drawn() { emit(frame.size) }
}

@MainActor final class Content: NSView {
    var onLayout: (() -> Void)?
    var layouts = 0
    override var isFlipped: Bool { true }
    override func layout() { super.layout(); layouts += 1; onLayout?() }
}

@main @MainActor struct PageContentResizerTests {
    static var count = 0
    static func check(_ value: @autoclosure () -> Bool, _ message: String) {
        count += 1
        guard value() else { fatalError("PageContentResizer: \(message)") }
    }
    static func size(_ width: CGFloat, _ height: CGFloat = 600) -> CGSize { CGSize(width: width, height: height) }
    static func main() {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 1200, height: 700),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 1200, height: 700))
        root.wantsLayer = true; window.contentView = root
        let content = Content(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        root.addSubview(content)
        let resizer = PageContentResizer()
        var page = FakePage(frame: content.bounds)
        content.addSubview(page)
        content.onLayout = { resizer.place(page, in: content) }
        func resize(_ width: CGFloat) {
            content.frame.size.width = width
            root.layoutSubtreeIfNeeded()
        }
        root.layoutSubtreeIfNeeded()
        let ownClipping = content.clipsToBounds

        check(page.autoresizingMask == [.width, .height] && page.frame == content.bounds, "intrinsic fills the content")
        resize(760)
        check(page.frame.size == size(760) && resizer.hold.pendingFrames.isEmpty, "intrinsic resizes at once")
        final class FillingChild: NSView {
            var layouts = 0
            override func layout() {
                super.layout()
                layouts += 1
                frame = superview?.bounds ?? frame
            }
        }
        let filler = FillingChild(frame: NSRect(x: 0, y: 0, width: 1, height: 1))
        page.addSubview(filler)
        resizer.place(page, in: content)
        check(filler.frame.size == page.frame.size, "hosted views that size in layout follow the page immediately")
        let hostedLayouts = filler.layouts
        resizer.place(page, in: content)
        check(filler.layouts == hostedLayouts && filler.frame.size == page.frame.size,
              "an unchanged page size does not relayout the hosted subtree")
        filler.frame = NSRect(x: 0, y: 0, width: 1, height: 1)
        filler.needsLayout = false
        resizer.place(page, in: content)
        check(filler.frame.size == page.frame.size && filler.layouts == hostedLayouts + 1,
              "a direct hosted child that no longer fills still flushes in the same pass")
        let afterFill = filler.layouts
        content.frame.size.width = 740
        resizer.place(page, in: content)
        check(filler.frame.width == 740 && filler.frame.size == page.frame.size && filler.layouts == afterFill + 1,
              "a later size is pushed into the hosted subtree in the same pass")

        page.reports = false
        resizer.mode = .throttle
        check(resizer.hold.mode == .intrinsic && page.leases.isEmpty, "no report keeps the page intrinsic")
        let before = page.sentSizes.count
        for width in stride(from: 750, through: 700, by: -10) { resize(CGFloat(width)) }
        check(page.sentSizes.count == before + 6 && page.frame.size == size(700), "without the report every size reaches the page")
        resizer.mode = .intrinsic

        page.reports = true
        page.viewport = size(700)
        resizer.mode = .throttle
        check(resizer.hold.mode == .throttle && page.liveLeases == 1, "throttle subscribes to the renderer")
        check(content.needsLayout, "entering throttle relays out")
        root.layoutSubtreeIfNeeded()
        check(page.autoresizingMask == [] && resizer.hold.lockedSize == nil, "throttle stops autoresizing without holding yet")
        let sent = page.sentSizes.count
        resize(660)
        check(page.frame.size == size(660) && resizer.hold.lockedSize == size(660), "the first new size reaches the page and holds")
        check(content.clipsToBounds, "a held page is clipped to its content")
        for width in stride(from: 650, through: 600, by: -10) { resize(CGFloat(width)) }
        check(page.sentSizes.count == sent + 1, "unreported sizes never reach the page")
        check(page.frame == NSRect(x: 0, y: 0, width: 660, height: 600), "the held page keeps its top-leading corner")
        page.drawn()
        check(resizer.hold.lockedSize == nil && resizer.hold.pendingFrames.isEmpty, "the renderer's report releases the hold")
        check(content.needsLayout, "a report relays out")
        root.layoutSubtreeIfNeeded()
        check(page.frame.size == size(600) && resizer.hold.lockedSize == size(600), "the latest size follows and holds again")
        check(page.sentSizes.count == sent + 2, "one size per renderer report")
        resize(640)
        check(page.frame == NSRect(x: 0, y: 0, width: 600, height: 600), "a growing content keeps the held page at the leading edge")
        page.emit(size(10))
        root.layoutSubtreeIfNeeded()
        check(page.frame.size == size(640), "a report of any size releases the hold")
        page.emit(size(640))
        root.layoutSubtreeIfNeeded()
        check(resizer.hold.lockedSize == nil && page.frame.size == size(640), "an unchanged size after its report does not hold")
        resize(640.5)
        check(resizer.hold.lockedSize == nil && page.frame.size.width == 640.5, "a change within a point follows live")

        resize(620)
        check(resizer.hold.lockedSize == size(620), "held before the drag ends")
        resize(580)
        resizer.mode = .intrinsic
        check(page.liveLeases == 0, "leaving throttle cancels the subscription")
        root.layoutSubtreeIfNeeded()
        check(page.frame == content.bounds && page.frame.size == size(580), "the final size is applied after the drag")
        check(page.autoresizingMask == [.width, .height] && content.clipsToBounds == ownClipping, "autoresizing and clipping are restored")

        page.viewport = size(580)
        resizer.mode = .throttle
        check(page.liveLeases == 1 && resizer.hold.pendingFrames.isEmpty, "the current report drains any stale frame")

        let first = page
        page = FakePage(frame: content.bounds)
        first.removeFromSuperview(); content.addSubview(page)
        page.viewport = content.bounds.size
        resizer.place(page, in: content)
        check(first.liveLeases == 0 && page.liveLeases == 1 && resizer.hold.mode == .throttle, "a replaced page re-subscribes")
        resize(540)
        check(resizer.hold.lockedSize == size(540), "the new page is held")
        resizer.mode = .intrinsic
        root.layoutSubtreeIfNeeded()

        page.reports = false
        resizer.mode = .locked
        check(resizer.hold.mode == .locked && resizer.hold.lockedSize == size(540), "locked holds the current size")
        resize(700)
        check(page.frame.size == size(540) && content.clipsToBounds, "a locked page ignores its content size")
        resizer.mode = .intrinsic
        root.layoutSubtreeIfNeeded()
        check(page.frame.size == size(700) && content.clipsToBounds == ownClipping, "unlocking fills the content")

        let fresh = Content(frame: .zero)
        root.addSubview(fresh)
        let freshResizer = PageContentResizer()
        var late = FakePage(frame: .zero)
        fresh.addSubview(late)
        fresh.onLayout = { freshResizer.place(late, in: fresh) }
        freshResizer.mode = .locked
        freshResizer.place(late, in: fresh)
        check(freshResizer.hold.lockedSize == nil, "an empty content locks nothing")
        fresh.frame.size = size(500)
        root.layoutSubtreeIfNeeded()
        check(late.frame.size == size(500) && freshResizer.hold.lockedSize == size(500), "the lock holds the content's first size")
        let joining = FakePage(frame: .zero)
        late.removeFromSuperview(); late = joining; fresh.addSubview(late)
        freshResizer.place(late, in: fresh)
        check(late.frame.size == size(500) && freshResizer.hold.lockedSize == size(500),
              "a page that joins a lock holds the content's size, not its own empty frame")
        freshResizer.mode = .intrinsic
        fresh.frame.size = .zero
        root.layoutSubtreeIfNeeded()
        let unrendered = FakePage(frame: .zero)
        late.removeFromSuperview(); late = unrendered; fresh.addSubview(late)
        freshResizer.mode = .throttle
        freshResizer.place(late, in: fresh)
        check(freshResizer.hold.mode == .intrinsic && late.liveLeases == 0, "an empty content does not throttle yet")
        fresh.frame.size = size(480)
        root.layoutSubtreeIfNeeded()
        check(late.frame.size == size(480) && late.liveLeases == 1 && freshResizer.hold.lockedSize == size(480),
              "the first size reaches the page and holds until the renderer draws it")
        late.drawn()
        root.layoutSubtreeIfNeeded()
        check(freshResizer.hold.lockedSize == nil && late.frame.size == size(480), "its report releases the page")
        freshResizer.mode = .intrinsic

        let home = Content(frame: NSRect(origin: .zero, size: size(800)))
        let elsewhere = Content(frame: NSRect(origin: .zero, size: size(600)))
        root.addSubview(home); root.addSubview(elsewhere)
        let homeResizer = PageContentResizer()
        let mover = FakePage(frame: home.bounds)
        var homePage: FakePage? = mover
        home.addSubview(mover)
        home.onLayout = { if let homePage { homeResizer.place(homePage, in: home) } }
        root.layoutSubtreeIfNeeded()
        mover.viewport = size(800)
        homeResizer.mode = .throttle
        for width: CGFloat in [790, 780] { home.frame.size.width = width; root.layoutSubtreeIfNeeded() }
        check(mover.frame.size == size(790), "the page leaves while held")
        homePage = nil; elsewhere.addSubview(mover)
        homeResizer.mode = .intrinsic
        root.layoutSubtreeIfNeeded()
        homePage = mover; home.addSubview(mover); homeResizer.place(mover, in: home)
        check(mover.frame.size == size(780) && mover.autoresizingMask == [.width, .height] && homeResizer.hold.lockedSize == nil,
              "a returning page drops the hold it left with")

        window.close()
        print("PageContentResizer: \(count) assertions passed")
    }
}
