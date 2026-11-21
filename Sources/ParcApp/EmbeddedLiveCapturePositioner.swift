import AppKit

@MainActor
final class EmbeddedLiveCapturePositioner {
    static let positioningStatus = "Positioning live capture…"
    static let misalignedStatus = "This page could not align with the captured region."
    static let unavailableStatus = "Live capture is unavailable for this page."

    let layout: EaselCaptureLayout
    private var positioning: PCNativeLiveCapturePosition?
    private var generation: UInt64 = 0
    private var positionedWidth: CGFloat = 0
    private var positionedZoom: Double = 0

    init(layout: EaselCaptureLayout) { self.layout = layout }

    var isPositioning: Bool { positioning != nil }

    func clipFrame(in area: NSRect, zoom: Double) -> NSRect {
        let zoom = zoom.isFinite && zoom > 0 ? zoom : 1
        let aspect = layout.region.width / layout.region.height
        let width = max(0, min(Double(area.width), max(1, Double(area.height)) * aspect, layout.viewport.x * zoom, layout.viewport.y * zoom * aspect))
        let height = width / aspect
        return NSRect(x: (Double(area.midX) - width / 2).rounded(), y: (Double(area.midY) - height / 2).rounded(), width: width, height: height)
    }

    func pageSize(zoom: Double) -> NSSize {
        let zoom = zoom.isFinite && zoom > 0 ? zoom : 1
        return NSSize(width: layout.viewport.x * zoom, height: layout.viewport.y * zoom)
    }

    func cancel() {
        generation &+= 1
        positioning?.cancel()
        positioning = nil
        positionedWidth = 0
        positionedZoom = 0
    }

    func position(browser: PCBrowserView, clip: NSView, force: Bool, status: @escaping (String?, Bool) -> Void) {
        guard let page = browser.nativePage, !page.isClosed, page.embeddedOwnerValid, !browser.isLoading, browser.window != nil else { return }
        let zoom = page.liveCaptureZoomFactor
        let width = min(clip.bounds.width, clip.bounds.height * layout.region.width / layout.region.height)
        guard width > 0, zoom.isFinite, zoom > 0, force || positionedWidth != width || positionedZoom != zoom else { return }
        cancel()
        positionedWidth = width
        positionedZoom = zoom
        let expected = generation
        browser.frame = NSRect(origin: .zero, size: pageSize(zoom: zoom))
        status(Self.positioningStatus, false)
        positioning = page.positionLiveCapture(NSRect(x: layout.region.x, y: layout.region.y, width: layout.region.width, height: layout.region.height),
            scrollOffset: NSPoint(x: layout.scroll.x, y: layout.scroll.y), displayWidth: width) { [weak self, weak browser, weak page] success in
                MainActor.assumeIsolated {
                    guard let self, let browser, let page, self.generation == expected,
                          browser.nativePage === page, page.embeddedOwnerValid else { return }
                    self.positioning = nil
                    status(success ? nil : Self.misalignedStatus, !success)
                }
            }
        if positioning == nil { status(Self.unavailableStatus, true) }
    }
}
