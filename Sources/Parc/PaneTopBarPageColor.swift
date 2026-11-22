import AppKit
import ParcEngine

extension PCNativePage {
    var reportsTopBandColor: Bool { responds(to: #selector(getter: PCNativePage.topBandColor)) }

    var topBandSample: TopBarColorClient.Sample {
        hasTopBandColorSample ? TopBarColorClient.Sample(color: topBandColor, host: topBandColorHost)
            : TopBarColorClient.Sample(color: nil, host: nil)
    }

    var approximateTopBarColor: NSColor? {
        if let theme = PaneTopBarColor.fill(from: developerModeTint) { return theme }
        guard responds(to: #selector(getter: PCNativePage.pageBackgroundColor)) else { return nil }
        return PaneTopBarColor.fill(from: pageBackgroundColor)
    }
}

@MainActor protocol TopBarColorWindow: AnyObject {
    var isPrivateBrowsing: Bool { get }
}

extension BrowserToolbarView {
    func showPageColor(of page: PCNativePage?, failing: Bool) {
        followSampledColor(of: nil, changes: TopBarColorClient.displayColorDidChangeNotification) { _ in }
        guard let page, !page.isClosed, !failing else { setPageColor(nil, for: page); return }
        guard page.reportsTopBandColor else {
            setPageColor(page.approximateTopBarColor, for: page, holdingWhileUnknown: page.loading)
            return
        }
        let privateBrowsing = (window?.windowController as? TopBarColorWindow)?.isPrivateBrowsing ?? true
        let client = TopBarColorClient.client(privateBrowsing: privateBrowsing)
        client.track(page) { [weak page] in
            guard let page, !page.isClosed else { return nil }
            return page.topBandSample
        }
        followSampledColor(of: page, changes: TopBarColorClient.displayColorDidChangeNotification) { [weak self] page in
            self?.showPageColor(of: page as? PCNativePage, failing: false)
        }
        let sample = page.topBandSample
        client.deliver(sample, for: page)
        setPageColor(client.initialColor(for: page, host: sample.host ?? page.url?.host), for: page,
                     animated: page.topBandColorCrossfades)
    }
}
