import AppKit
import ParcCore

enum PaneContentHostedLayoutFlush {
    static func shouldLayoutContent(frameChanged: Bool, needsLayout: Bool) -> Bool {
        frameChanged || needsLayout
    }

    static func shouldLayoutChild(needsLayout: Bool) -> Bool {
        needsLayout
    }
}

@MainActor protocol RenderFrameReporting: AnyObject {
    var renderFrameViewport: CGSize { get }
    func observeRenderFrameViewport(_ handler: @escaping (CGSize) -> Void) -> RenderFrameObservation?
}

@MainActor protocol RenderFrameObservation: AnyObject {
    func invalidate()
}

@MainActor final class PageContentResizer {
    var mode = PageContentResizeMode.intrinsic {
        didSet { if mode != oldValue { joined = false; join() } }
    }
    private(set) var hold = PageContentResizeHold()
    private weak var page: (NSView & RenderFrameReporting)?
    private weak var container: NSView?
    private var observation: RenderFrameObservation?
    private var lastReport = CGSize.zero
    private var joined = false
    private var containerClips: Bool?
    private var placing = false
    private var lastFlushedFrame: CGRect?

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
            if mode == .throttle { page.layoutSubtreeIfNeeded() }
            join()
            apply(page, in: container)
        }
        hold.didApply(frameSize: page.frame.size, lastReport: lastReport)
        setClipping(hold.lockedSize != nil)
    }

    private func apply(_ page: NSView, in container: NSView) {
        page.autoresizingMask = hold.mode == .intrinsic ? [.width, .height] : []
        let target = hold.frame(in: container.bounds)
        let moved = page.frame != target
        if moved { page.frame = target }
        if lastFlushedFrame != page.frame || Self.hostedChromeNeedsFlush(page) {
            Self.flushHostedLayout(page)
            lastFlushedFrame = page.frame
        }
    }

    static func flushHostedLayout(_ view: NSView) {
        func mark(_ view: NSView) {
            view.needsLayout = true
            if Self.isDevToolsPane(view) { return }
            for child in view.subviews { mark(child) }
        }
        mark(view)
        view.layoutSubtreeIfNeeded()
    }

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

    private func join() {
        observation?.invalidate(); observation = nil
        guard let page, let container, page.superview === container else { return }
        var effective = mode
        if effective != .intrinsic, container.bounds.isEmpty || page.frame.isEmpty { return }
        joined = true
        if effective == .throttle {
            observation = page.observeRenderFrameViewport { [weak self] in self?.rendererDidReport($0) }
            if observation == nil { effective = .intrinsic }
        }
        if hold.setMode(effective, frameSize: page.frame.size) { requestLayout() }
        if observation != nil { rendererDidReport(page.renderFrameViewport) }
    }

    private func rendererDidReport(_ viewport: CGSize) {
        lastReport = viewport
        hold.acknowledge(viewport)
        requestLayout()
    }

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
