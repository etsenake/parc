import AppKit
import ParcCore
import ParcEngine

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
