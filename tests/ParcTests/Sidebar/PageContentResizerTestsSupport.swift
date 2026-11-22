import AppKit
import QuartzCore
@testable import Parc

@MainActor
enum PageContentResizerTestsSupport {
    final class FakePage: NSView, RenderFrameReporting {
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
            let lease = Lease()
            lease.handler = handler
            leases.append(lease)
            return lease
        }

        var liveLeases: Int { leases.filter { $0.handler != nil }.count }
        func emit(_ size: CGSize) { viewport = size; leases.forEach { $0.handler?(size) } }
        func drawn() { emit(frame.size) }
    }

    final class Content: NSView {
        var onLayout: (() -> Void)?
        var layouts = 0
        override var isFlipped: Bool { true }
        override func layout() { super.layout(); layouts += 1; onLayout?() }
    }

    static func size(_ width: CGFloat, _ height: CGFloat = 600) -> CGSize { CGSize(width: width, height: height) }

    @MainActor final class Resizing {
        let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 1200, height: 700),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 1200, height: 700))
        let content = Content(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        let resizer = PageContentResizer()
        var page: FakePage
        let ownClipping: Bool

        init() {
            window.isReleasedWhenClosed = false
            root.wantsLayer = true
            window.contentView = root
            root.addSubview(content)
            page = FakePage(frame: content.bounds)
            content.addSubview(page)
            ownClipping = content.clipsToBounds
            let resizer = self.resizer
            content.onLayout = { [unowned self] in resizer.place(page, in: content) }
            root.layoutSubtreeIfNeeded()
        }

        deinit { MainActor.assumeIsolated { window.close() } }

        func resize(_ width: CGFloat) {
            content.frame.size.width = width
            root.layoutSubtreeIfNeeded()
        }

        func throttling() -> Resizing {
            resize(700)
            page.reports = true
            page.viewport = CGSize(width: 700, height: 600)
            resizer.mode = .throttle
            root.layoutSubtreeIfNeeded()
            return self
        }
    }
}
