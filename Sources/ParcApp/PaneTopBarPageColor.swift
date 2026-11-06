import AppKit

/// Where a pane or Peek top bar's page colour comes from, and its one
///
/// TopBandColorTracker) and its TopBarColorClient settles and caches the
/// colour per site; Parc's engine reports the same samples from overlay 294
/// (`topBandColor`), which `TopBarColorClient` turns into the bar's colour.
/// Older engines report only the declared theme colour (`developerModeTint`)
/// and the page's composited background (`pageBackgroundColor`, overlay 293),
/// which stand in for the sample there. The page observer notifies when a
/// colour input changes; `PCBrowserView` compares them and calls
/// `browserViewDidChangePageColor(_:)`, whose owners (the window for panes,
/// `PeekController` for its Peek) call `showPageColor(of:failing:)` on a
/// visible bar alone. Full configuration (`configureBrowserToolbar`)
/// uses the same call. See docs/top-band-color.md.
extension PCNativePage {
    var reportsTopBandColor: Bool { responds(to: #selector(getter: PCNativePage.topBandColor)) }

    /// The delivered colour and the host of the document it was sampled
    /// from, never the visible or Reader display URL's.
    var topBandSample: TopBarColorClient.Sample {
        hasTopBandColorSample ? TopBarColorClient.Sample(color: topBandColor, host: topBandColorHost)
            : TopBarColorClient.Sample(color: nil, host: nil)
    }

    /// Engines before overlay 294: the declared theme colour, then the
    /// composited background.
    var approximateTopBarColor: NSColor? {
        if let theme = PaneTopBarColor.fill(from: developerModeTint) { return theme }
        guard responds(to: #selector(getter: PCNativePage.pageBackgroundColor)) else { return nil }
        return PaneTopBarColor.fill(from: pageBackgroundColor)
    }
}

/// The window controller owning a top bar, for its store's private state.
@MainActor protocol TopBarColorWindow: AnyObject {
    var isPrivateBrowsing: Bool { get }
}

extension BrowserToolbarView {
    /// Clear while a navigation failure or renderer crash covers the page.
    /// With the engine's samples a newly shown page starts with its displayed,
    /// cached or white colour, and a later sample crossfades when the engine
    /// says so. Without them, while the same page loads without a colour the
    ///
    /// sample without a colour.
    func showPageColor(of page: PCNativePage?, failing: Bool) {
        followSampledColor(of: nil, changes: TopBarColorClient.displayColorDidChangeNotification) { _ in }
        guard let page, !page.isClosed, !failing else { setPageColor(nil, for: page); return }
        guard page.reportsTopBandColor else {
            setPageColor(page.approximateTopBarColor, for: page, holdingWhileUnknown: page.loading)
            return
        }
        // A bar outside a browser window is treated as private: nothing it
        // samples is written to disk.
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
        //
        setPageColor(client.initialColor(for: page, host: sample.host ?? page.url?.host), for: page,
                     animated: page.topBandColorCrossfades)
    }
}
