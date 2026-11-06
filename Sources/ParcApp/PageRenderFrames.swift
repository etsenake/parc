import AppKit

/// PCBrowserView's renderer frames for PageContentResizer, in this view's own
/// size. The engine reports the renderer's viewport: the page host's content
/// view, below the host's infobar shelf, beside docked DevTools. Each report is
/// converted with the geometry at hand when it arrives, outside layout, where
/// the engine's own layout has framed that view. Older engines report nothing.
extension PCBrowserView: RenderFrameReporting {
    var renderFrameViewport: CGSize {
        guard let page = nativePage, !page.isClosed,
              page.responds(to: #selector(getter: PCNativePage.renderFrameViewportSize)) else { return .zero }
        return ownSize(page.renderFrameViewportSize, page)
    }

    func observeRenderFrameViewport(_ handler: @escaping (CGSize) -> Void) -> RenderFrameObservation? {
        guard let page = nativePage, !page.isClosed,
              page.responds(to: #selector(PCNativePage.observeRenderFrameViewportSize(_:))) else { return nil }
        return page.observeRenderFrameViewportSize { [weak self, weak page] viewport in
            guard let self, let page else { return }
            handler(self.ownSize(viewport, page))
        }
    }

    private func ownSize(_ viewport: CGSize, _ page: PCNativePage) -> CGSize {
        let renderer = (page.nativeView as? PCNativePageHost)?.contentView ?? page.nativeView
        guard renderer.isDescendant(of: self) else { return viewport }
        return PageContentResizeHold.pageSize(ofViewport: viewport, page: bounds.size, renderer: renderer.bounds.size)
    }
}

extension PCNativeRenderFrameObservation: RenderFrameObservation {}
