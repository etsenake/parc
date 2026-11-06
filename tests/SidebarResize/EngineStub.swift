import AppKit

// The engine's page view tree for the production PCBrowserView adapter
// (PageRenderFrames.swift), with the renderer driven by the test. These types
// are NOT the engine; they mirror its geometry:
// PCBrowserView > PCNativeDevToolsPaneView (autoresized; frames the page host
// beside docked DevTools only in its own layout(), devtools_pane_view.mm and
// NativeDevToolsPane::Layout) > PCNativePageHost (no autoresizing; the infobar
// shelf above the content view, both by constraints, page_host.mm) > the
// content view, whose size is the renderer's.

@MainActor final class PCNativeRenderFrameObservation: NSObject {
    var handler: ((NSSize) -> Void)?
    func invalidate() { handler = nil }
}

/// The renderer's view; records every size the renderer would be sent.
@MainActor final class StubRenderer: NSView {
    private(set) var sentSizes: [CGSize] = []
    override func setFrameSize(_ newSize: NSSize) {
        if newSize != frame.size { sentSizes.append(newSize) }
        super.setFrameSize(newSize)
    }
}

@MainActor final class PCNativePageHost: NSView {
    let renderer = StubRenderer(frame: .zero)
    private let shelf: NSLayoutConstraint
    var contentView: NSView? { renderer }
    var infobarHeight: CGFloat {
        get { shelf.constant }
        set { shelf.constant = newValue }
    }
    init() {
        let infobar = NSView()
        shelf = infobar.heightAnchor.constraint(equalToConstant: 0)
        super.init(frame: .zero)
        for view in [infobar, renderer] { view.translatesAutoresizingMaskIntoConstraints = false; addSubview(view) }
        NSLayoutConstraint.activate([
            infobar.topAnchor.constraint(equalTo: topAnchor), shelf,
            infobar.leadingAnchor.constraint(equalTo: leadingAnchor), infobar.trailingAnchor.constraint(equalTo: trailingAnchor),
            renderer.topAnchor.constraint(equalTo: infobar.bottomAnchor), renderer.bottomAnchor.constraint(equalTo: bottomAnchor),
            renderer.leadingAnchor.constraint(equalTo: leadingAnchor), renderer.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }
}

@objc(PCNativeDevToolsPaneView) @MainActor final class StubDevToolsPane: NSView {
    weak var inspected: NSView?
    var dockedWidth: CGFloat = 0 { didSet { needsLayout = true } }
    private(set) var layouts = 0
    override var isFlipped: Bool { true }
    override func layout() {
        super.layout()
        layouts += 1
        inspected?.frame = NSRect(x: 0, y: 0, width: bounds.width - dockedWidth, height: bounds.height)
    }
}

@MainActor final class PCNativePage: NSObject {
    let host = PCNativePageHost()
    var isClosed = false
    /// An engine before the RenderFrameViewport overlay.
    let olderEngine: Bool
    var nativeView: NSView { host }
    private var drawn = CGSize.zero
    private var leases: [PCNativeRenderFrameObservation] = []
    var liveLeases: Int { leases.filter { $0.handler != nil }.count }
    init(olderEngine: Bool = false) { self.olderEngine = olderEngine }

    @objc var renderFrameViewportSize: NSSize { drawn }
    @objc func observeRenderFrameViewportSize(_ handler: @escaping (NSSize) -> Void) -> PCNativeRenderFrameObservation? {
        let lease = PCNativeRenderFrameObservation(); lease.handler = handler; leases.append(lease)
        return lease
    }
    nonisolated override func responds(to selector: Selector!) -> Bool {
        if olderEngine, selector == #selector(getter: PCNativePage.renderFrameViewportSize)
            || selector == #selector(PCNativePage.observeRenderFrameViewportSize(_:)) { return false }
        return super.responds(to: selector)
    }
    /// The browser activates a frame of the size the renderer was last sent,
    /// or of an older `viewport`.
    func draw(_ viewport: CGSize? = nil) {
        drawn = viewport ?? host.renderer.frame.size
        leases.forEach { $0.handler?(drawn) }
    }
}

@MainActor final class PCBrowserView: NSView {
    private(set) var nativePage: PCNativePage?
    let pane = StubDevToolsPane()
    init(frame: NSRect, page: PCNativePage) {
        super.init(frame: frame)
        autoresizingMask = [.width, .height]
        pane.frame = bounds; pane.autoresizingMask = [.width, .height]; addSubview(pane)
        page.host.frame = pane.bounds; pane.addSubview(page.host); pane.inspected = page.host
        nativePage = page
    }
    required init?(coder: NSCoder) { fatalError() }
}
