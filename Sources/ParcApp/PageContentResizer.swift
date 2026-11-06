import AppKit

/// Gate for `BrowserPane` content layout so everyday pane layout does not
/// `layoutSubtreeIfNeeded` the whole Chromium tree when hosted chrome is current.
///
/// `NSView.layoutSubtreeIfNeeded` always recurses into every descendant. After
/// `content.layout` runs `PageContentResizer.place` (which already flushes a
/// real page-size change via `flushHostedLayout`), only dirty direct content
/// children still need a subtree walk — start/error/native chrome, or a page
/// that place left dirty. Clean hosted geometry is a true no-op.
enum PaneContentHostedLayoutFlush {
    /// Run `content.layout` (and therefore `place`) when the content frame
    /// moved or content is already dirty.
    static func shouldLayoutContent(frameChanged: Bool, needsLayout: Bool) -> Bool {
        frameChanged || needsLayout
    }

    /// After content layout/place, walk a direct child's subtree only when
    /// that child still needs layout.
    static func shouldLayoutChild(needsLayout: Bool) -> Bool {
        needsLayout
    }
}

/// A page view whose renderer reports the viewport of each frame it draws, in
///
@MainActor protocol RenderFrameReporting: AnyObject {
    /// The latest frame's viewport; zero before the first frame.
    var renderFrameViewport: CGSize { get }
    /// Reports each later frame until the lease is invalidated; nil when this
    /// page cannot report frames.
    func observeRenderFrameViewport(_ handler: @escaping (CGSize) -> Void) -> RenderFrameObservation?
}

@MainActor protocol RenderFrameObservation: AnyObject {
    func invalidate()
}

///
/// one pane's page view; the window sets `mode` from its
/// PageContentResizeReasons (docs/sidebar-resize.md).
@MainActor final class PageContentResizer {
    /// A page that cannot report frames, or none yet, takes throttle as
    /// intrinsic and keeps resizing live.
    var mode = PageContentResizeMode.intrinsic {
        didSet { if mode != oldValue { joined = false; join() } }
    }
    private(set) var hold = PageContentResizeHold()
    private weak var page: (NSView & RenderFrameReporting)?
    private weak var container: NSView?
    private var observation: RenderFrameObservation?
    ///
    /// pendingRenderFrameViewportSize); layout compares against it.
    private var lastReport = CGSize.zero
    /// Whether the page has taken `mode`. A held mode waits for a page and
    /// content with a size: a new pane's page view starts empty.
    private var joined = false
    /// The container's own clipping while a hold clips the page to it.
    private var containerClips: Bool?
    private var placing = false
    /// The page frame last pushed into Chromium. Intrinsic autoresizing can
    /// update `page.frame` before `apply` runs, so "apply did not setFrame"
    /// is not proof the hosted surface is current.
    private var lastFlushedFrame: CGRect?

    ///
    /// fills `container`, or keeps a held size at its top-leading corner,
    /// clipped. Only intrinsic pages autoresize, so a held size never reaches
    /// the renderer before this runs.
    func place(_ page: NSView & RenderFrameReporting, in container: NSView) {
        placing = true
        defer { placing = false }
        if self.page !== page || self.container !== container {
            setClipping(false); containerClips = nil
            observation?.invalidate(); observation = nil
            self.page = page; self.container = container
            hold = PageContentResizeHold(); lastReport = .zero; joined = false
            lastFlushedFrame = nil
        }
        apply(page, in: container)
        if !joined {
            // The engine frames its renderer in the page's own layout, and the
            // first report is converted against that geometry.
            if mode == .throttle { page.layoutSubtreeIfNeeded() }
            join()
            // Joining can take or drop a hold, such as the one a page that
            // left mid-drag comes back with.
            apply(page, in: container)
        }
        hold.didApply(frameSize: page.frame.size, lastReport: lastReport)
        setClipping(hold.lockedSize != nil)
    }

    private func apply(_ page: NSView, in container: NSView) {
        page.autoresizingMask = hold.mode == .intrinsic ? [.width, .height] : []
        let target = hold.frame(in: container.bounds)
        //
        // setFrame: and does not walk the hosted tree or call
        // layoutSubtreeIfNeeded. Parc still has to flush Chromium when the
        // hosted surface actually changes size.
        let moved = page.frame != target
        if moved { page.frame = target }
        // Autoresizing may already have written `target` onto the page and
        // its DevTools pane. The inspected Chromium host does not autoresize,
        // so still flush when this page frame has not been pushed yet.
        // Skip when the last flushed page frame matches and shallow hosted
        // chrome is already clean/filling — do not re-walk every Chromium
        // descendant just to re-verify (P0-K leftover after 3beb941d).
        if lastFlushedFrame != page.frame || Self.hostedChromeNeedsFlush(page) {
            Self.flushHostedLayout(page)
            lastFlushedFrame = page.frame
        }
    }

    /// Chromium's hosted view only adopts a new size from `NSView.layout`. A
    /// parent frame change does not mark that child dirty, so the compositor
    /// keeps the previous surface until some later AppKit pass. Skip only when
    /// this page frame was already flushed and shallow hosted chrome (stopping
    /// at the DevTools pane) already fills it: the compositor has this surface.
    static func flushHostedLayout(_ view: NSView) {
        func mark(_ view: NSView) {
            view.needsLayout = true
            // Docked tools own inspected/overlay/tools frames. Marking those
            // children dirty on every page place retriggers their layout and
            // writes the same rects back onto the inspected WebContents.
            if Self.isDevToolsPane(view) { return }
            for child in view.subviews { mark(child) }
        }
        mark(view)
        view.layoutSubtreeIfNeeded()
    }

    /// Shallow hosted-chrome fingerprint (P1-W spirit): dirty page, or a
    /// direct child whose frame does not fill the page / still needs layout.
    /// Stop at the DevTools pane — looking inside it always sees docked
    /// frames. Deep recursive verification after `lastFlushedFrame` matched
    /// was the everyday Chromium tree walk; real page-size changes still
    /// miss `lastFlushedFrame` and flush.
    private static func hostedChromeNeedsFlush(_ view: NSView) -> Bool {
        if Self.isDevToolsPane(view) { return false }
        if view.needsLayout { return true }
        for child in view.subviews {
            if child.frame != view.bounds { return true }
            if Self.isDevToolsPane(child) { continue }
            if child.needsLayout { return true }
        }
        return false
    }

    private static func isDevToolsPane(_ view: NSView) -> Bool {
        guard let paneClass = Self.devToolsPaneClass else { return false }
        return view.isKind(of: paneClass)
    }
    private static let devToolsPaneClass: AnyClass? = NSClassFromString("PCNativeDevToolsPaneView")

    ///
    /// lives only while throttling, and locked holds the page's current size.
    private func join() {
        observation?.invalidate(); observation = nil
        // A page moved to another pane is that pane's resizer's now.
        guard let page, let container, page.superview === container else { return }
        var effective = mode
        if effective != .intrinsic, container.bounds.isEmpty || page.frame.isEmpty { return }
        joined = true
        if effective == .throttle {
            observation = page.observeRenderFrameViewport { [weak self] in self?.rendererDidReport($0) }
            if observation == nil { effective = .intrinsic }
        }
        if hold.setMode(effective, frameSize: page.frame.size) { requestLayout() }
        // A Published publisher delivers its current value on subscription.
        if observation != nil { rendererDidReport(page.renderFrameViewport) }
    }

    private func rendererDidReport(_ viewport: CGSize) {
        lastReport = viewport
        hold.acknowledge(viewport)
        requestLayout()
    }

    /// Inside place() the page is about to be laid out anyway.
    private func requestLayout() {
        if !placing { container?.needsLayout = true }
    }

    private func setClipping(_ clips: Bool) {
        guard let container else { return }
        if clips, containerClips == nil {
            containerClips = container.clipsToBounds; container.clipsToBounds = true
        } else if !clips, let own = containerClips {
            container.clipsToBounds = own; containerClips = nil
        }
    }
}
