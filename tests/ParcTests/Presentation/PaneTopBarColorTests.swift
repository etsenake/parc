import AppKit
import Testing
import ParcCore
import ParcEngine
import ParcEngineDoubles
@testable import Parc

@MainActor struct PaneTopBarColorTests {
    @MainActor private struct Fixture {
        let toolbar: BrowserToolbarView
        let window: SidebarTestWindow
        let site: BrowserToolbarActionButton
        var shown: NSColor? { toolbar.pageColor?.usingColorSpace(.sRGB) }
        var fill: NSColor? { toolbar.layer?.backgroundColor.flatMap { NSColor(cgColor: $0)?.usingColorSpace(.sRGB) } }
        var ink: CGFloat? { site.contentTintColor?.usingColorSpace(.sRGB)?.redComponent }
        func refresh() { toolbar.viewDidChangeEffectiveAppearance(); site.viewDidChangeEffectiveAppearance() }
    }

    private func fixture() -> Fixture {
        _ = NSApplication.shared
        let toolbar = BrowserToolbarView(frame: NSRect(x: 0, y: 0, width: 720, height: BrowserToolbarView.height))
        toolbar.update(url: URL(string: "https://example.test/page"), fullURL: true, enabled: true, canBack: true,
                       canForward: false, loading: false, canReload: true, canCopy: true, canShowSiteInfo: true,
                       canSplit: true, close: true, showSidebar: true, extensionItems: [])
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 720, height: 100))
        let window = sidebarTestWindow(containing: content)
        content.addSubview(toolbar)
        toolbar.layoutSubtreeIfNeeded()
        let site = toolbar.subviews.compactMap { $0 as? BrowserToolbarActionButton }
            .first { $0.parcTooltip?.label == "Site Control Center" }!
        toolbar.reducesMotion = { false }
        return Fixture(toolbar: toolbar, window: window, site: site)
    }

    private let black = NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)
    private let theme = NSColor(srgbRed: 0.02, green: 0.447, blue: 0.925, alpha: 1)
    private let background = NSColor(srgbRed: 0.059, green: 0.059, blue: 0.059, alpha: 1)

    @Test(arguments: [(0.0, 0.0, 0.0, true), (1.0, 1.0, 1.0, false), (0.059, 0.059, 0.059, true),
                      (0.02, 0.447, 0.925, true), (1.0, 0.8, 0.0, false)])
    func aPageColorPicksTheReadableScheme(example: (CGFloat, CGFloat, CGFloat, Bool)) {
        let color = NSColor(srgbRed: example.0, green: example.1, blue: example.2, alpha: 1)
        #expect(PaneTopBarColor.usesDarkScheme(on: color) == example.3)
    }

    @Test(arguments: [(0.0, 0.0, 0.0, true), (1.0, 1.0, 1.0, false), (0.059, 0.059, 0.059, true),
                      (0.02, 0.447, 0.925, true), (1.0, 0.8, 0.0, false)])
    func aNewContentsColorFillsTheBarAtOnceWithReadableControls(example: (CGFloat, CGFloat, CGFloat, Bool)) throws {
        let f = fixture()
        f.toolbar.setPageColor(NSColor(srgbRed: example.0, green: example.1, blue: example.2, alpha: 1), for: NSObject())
        f.site.viewDidChangeEffectiveAppearance()
        #expect(f.site.appearance?.name == (example.3 ? .darkAqua : .aqua))
        #expect(f.ink == (example.3 ? 1 : 0))
        let fill = try #require(f.fill)
        #expect(abs(fill.redComponent - example.0) < 0.01 && abs(fill.blueComponent - example.2) < 0.01)
        #expect(f.toolbar.layer?.animation(forKey: "page-color") == nil)
        f.window.close()
    }

    @Test func reduceMotionSwapsALaterColorWithoutACrossfade() {
        let f = fixture()
        f.toolbar.reducesMotion = { true }
        let page = NSObject()
        f.toolbar.setPageColor(NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 1), for: page)
        f.toolbar.setPageColor(black, for: page)
        #expect(f.toolbar.layer?.animation(forKey: "page-color") == nil)
        #expect(f.shown == black)
        f.window.close()
    }

    @Test func aLaterColorForTheSameContentCrossfades() {
        let f = fixture()
        let page = NSObject()
        f.toolbar.setPageColor(NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 1), for: page)
        f.toolbar.setPageColor(black, for: page)
        #expect(abs((f.toolbar.layer?.animation(forKey: "page-color")?.duration ?? 0) - 0.18) < 0.00001)
        #expect(f.shown == black)
        f.window.close()
    }

    @Test func aPageThatFinishedLoadingWithoutAColorLeavesTheBarClear() {
        let f = fixture()
        let page = NSObject()
        f.toolbar.setPageColor(black, for: page)
        f.toolbar.setPageColor(nil, for: page)
        #expect(f.toolbar.pageColor == nil)
        f.window.close()
    }

    @Test func aTranslucentColorLeavesTheControlsOnTheWindowScheme() {
        let f = fixture()
        f.toolbar.setPageColor(NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.5), for: NSObject())
        #expect(f.toolbar.pageColor == nil && f.site.appearance == nil)
        f.window.close()
    }

    @Test(arguments: [(NSAppearance.Name.aqua, CGFloat(0.666)), (.darkAqua, 0.1)])
    func withoutAPageColorTheBarFollowsTheWindowAndShowsTheContentBacking(example: (NSAppearance.Name, CGFloat)) throws {
        let f = fixture()
        f.window.appearance = NSAppearance(named: example.0)
        f.refresh()
        let dark = example.0 == .darkAqua
        #expect(f.toolbar.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == example.0)
        #expect(f.ink == (dark ? 1 : 0))
        let fill = try #require(f.fill)
        #expect(fill.redComponent == 1 && abs(fill.alphaComponent - example.1) < 0.001)
        f.window.close()
    }

    @Test(arguments: [(false, NSAppearance.Name.darkAqua, false), (false, .aqua, false), (true, .darkAqua, true), (true, .aqua, false)])
    func aThemeBackingKeepsTheInkReadableInEitherWindow(example: (Bool, NSAppearance.Name, Bool)) throws {
        let f = fixture()
        let palette = ThemeChromePalette(theme: SpaceTheme(primaryColor: ThemeColor(red: 0.6, green: 0.85, blue: 0.7), colorCount: 2),
                                         isDark: example.0)
        f.window.appearance = NSAppearance(named: example.1)
        f.toolbar.themeBackground = palette.background
        f.refresh()
        #expect(f.site.appearance?.name == (example.2 ? .darkAqua : .aqua))
        #expect(f.ink == (example.2 ? 1 : 0))
        let fill = try #require(f.fill)
        #expect(abs(fill.alphaComponent - (example.1 == .darkAqua ? 0.1 : 0.666)) < 0.001)
        f.window.close()
    }

    @Test func aPageColorOutranksTheThemeBacking() {
        let f = fixture()
        let palette = ThemeChromePalette(theme: SpaceTheme(primaryColor: ThemeColor(red: 0.6, green: 0.85, blue: 0.7), colorCount: 2),
                                         isDark: false)
        f.toolbar.themeBackground = palette.background
        f.toolbar.setPageColor(black, for: NSObject())
        #expect(f.site.appearance?.name == .darkAqua)
        f.window.close()
    }

    private func nativePage() -> ToolbarTestEnginePage {
        let page = ToolbarTestEnginePage()
        page.developerModeTint = theme
        page.pageBackgroundColor = background
        return page
    }

    private func show(_ page: ToolbarTestEnginePage, on toolbar: BrowserToolbarView, failing: Bool = false) throws {
        toolbar.showPageColor(of: try #require(page.page as? PCNativePage), failing: failing)
    }

    @Test func theDeclaredThemeColorOutranksThePageBackground() throws {
        let f = fixture()
        try show(nativePage(), on: f.toolbar)
        #expect(f.shown == theme.usingColorSpace(.sRGB))
        f.window.close()
    }

    @Test func withoutAThemeColorTheBarTakesThePageBackground() throws {
        let f = fixture()
        let page = nativePage()
        page.developerModeTint = nil
        try show(page, on: f.toolbar)
        #expect(f.shown == background.usingColorSpace(.sRGB))
        f.window.close()
    }

    @Test func anEngineWithoutPageBackgroundsLeavesAnUnthemedPageClear() throws {
        let f = fixture()
        let page = nativePage()
        page.developerModeTint = nil
        page.reportsPageBackgroundColor = false
        try show(page, on: f.toolbar)
        #expect(f.shown == nil)
        f.window.close()
    }

    @Test(arguments: [true, false])
    func onlyAStillLoadingDocumentKeepsTheLastColor(loading: Bool) throws {
        let f = fixture()
        let page = nativePage()
        page.developerModeTint = nil
        try show(page, on: f.toolbar)
        page.pageBackgroundColor = nil
        page.loading = loading
        try show(page, on: f.toolbar)
        #expect(f.shown == (loading ? background.usingColorSpace(.sRGB) : nil))
        f.window.close()
    }

    @Test(arguments: [true, false])
    func aFailureOrCrashClearsTheBarWhetherLoadingOrNot(loading: Bool) throws {
        let f = fixture()
        let page = nativePage()
        page.loading = loading
        try show(page, on: f.toolbar)
        try show(page, on: f.toolbar, failing: true)
        #expect(f.shown == nil)
        f.window.close()
    }

    @Test func aClosedPageLeavesTheBarClear() throws {
        let f = fixture()
        let page = nativePage()
        try show(page, on: f.toolbar)
        page.closed = true
        try show(page, on: f.toolbar)
        #expect(f.shown == nil)
        f.window.close()
    }

    private func sampledPage(host: String) -> ToolbarTestEnginePage {
        let page = nativePage()
        page.reportsTopBandColor = true
        page.url = URL(string: "https://\(host)/vault")
        return page
    }

    private func uniqueHost() -> String { "toolbar-\(UUID().uuidString.lowercased()).test" }
    private let blue = NSColor(srgbRed: 0.1, green: 0.45, blue: 0.91, alpha: 1)

    private func matches(_ color: NSColor?, _ expected: NSColor) -> Bool {
        color.map { TopBarColorClient.distance($0, expected) < 0.0001 } == true
    }

    @Test func aSampledPageWithNoColorOrCacheStartsWhite() throws {
        let f = fixture()
        try show(sampledPage(host: uniqueHost()), on: f.toolbar)
        #expect(f.shown == NSColor.white.usingColorSpace(.sRGB))
        f.window.close()
    }

    private func sampled(_ f: Fixture, host: String) throws -> ToolbarTestEnginePage {
        let page = sampledPage(host: host)
        try show(page, on: f.toolbar)
        page.hasTopBandColorSample = true
        page.topBandColor = blue
        page.topBandColorHost = host
        try show(page, on: f.toolbar)
        return page
    }

    @Test func aSampleReplacesTheInitialColorWithoutACrossfade() throws {
        let f = fixture()
        _ = try sampled(f, host: uniqueHost())
        #expect(matches(f.shown, blue))
        #expect(f.toolbar.layer?.animation(forKey: "page-color") == nil)
        f.window.close()
    }

    @Test func aSampleWithoutAColorKeepsTheBarsColor() throws {
        let f = fixture()
        let page = try sampled(f, host: uniqueHost())
        page.topBandColor = nil
        try show(page, on: f.toolbar)
        #expect(matches(f.shown, blue))
        f.window.close()
    }

    @Test func aLaterSampleThatAsksToCrossfadeCrossfades() throws {
        let f = fixture()
        let page = try sampled(f, host: uniqueHost())
        page.topBandColor = black
        page.topBandColorCrossfades = true
        try show(page, on: f.toolbar)
        #expect(f.toolbar.layer?.animation(forKey: "page-color") != nil)
        f.window.close()
    }

    @Test func anotherPageOnTheHostStartsWithTheHostsSettledColor() throws {
        let f = fixture()
        let host = uniqueHost()
        _ = try sampled(f, host: host)
        try show(sampledPage(host: host), on: f.toolbar)
        #expect(matches(f.shown, blue))
        f.window.close()
    }

    @Test func aFailureCoversASampledPagesColor() throws {
        let f = fixture()
        let page = try sampled(f, host: uniqueHost())
        try show(page, on: f.toolbar, failing: true)
        #expect(f.shown == nil)
        f.window.close()
    }
}

struct BrowserToolbarModelTests {
    private let key = "parc.browserToolbar.v1"

    @MainActor private func withDefaults(_ body: (UserDefaults) throws -> Void) throws {
        let name = "parc.toolbar.model.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        try body(defaults)
    }

    @Test @MainActor func readingPreferencesWritesNothing() throws {
        try withDefaults { defaults in
            let preferences = BrowserToolbarPreferences(defaults: defaults)
            #expect(!preferences.loadError)
            #expect(defaults.object(forKey: key) == nil)
        }
    }

    @Test @MainActor func sharedConsumersReceiveTheNewVisibility() throws {
        try withDefaults { defaults in
            let preferences = BrowserToolbarPreferences(defaults: defaults)
            try preferences.setVisible(true)
            var published: [BrowserToolbarPreferences.State] = []
            let observation = preferences.$state.sink { published.append($0) }
            try preferences.setVisible(false)
            #expect(published.last?.isVisible == false)
            withExtendedLifetime(observation) {}
        }
    }

    @Test @MainActor func anUnexpectedLegacyValueIsPreservedAndRefusesChanges() throws {
        try withDefaults { defaults in
            defaults.set("unexpected legacy type", forKey: key)
            let preferences = BrowserToolbarPreferences(defaults: defaults)
            #expect(preferences.loadError)
            #expect(throws: BrowserToolbarPreferences.Failure.unavailable) { try preferences.setVisible(true) }
            #expect(defaults.string(forKey: key) == "unexpected legacy type")
        }
    }

    @Test(arguments: [(0, false, true), (1, false, true), (2, false, false), (0, true, false)])
    func onlyASplitPaneCanRetireItsOwnPage(example: (Int, Bool, Bool)) {
        let a = UUID(), b = UUID()
        let tab = [a, b, UUID()][example.0]
        #expect(SplitPaneCloseAdmission.accepts(tabID: tab, selected: [a, b], isPeek: example.1) == example.2)
    }

    @Test func aSinglePageHasNoSplitClose() {
        let a = UUID()
        #expect(!SplitPaneCloseAdmission.accepts(tabID: a, selected: [a]))
    }

    @Test func aMissingPageNeverInventsADestination() {
        #expect(BrowserToolbarAddress(url: nil, full: true).fullURL.isEmpty)
    }

    @Test func theFullAddressSplitsTheDomainFromItsSuffix() throws {
        let address = BrowserToolbarAddress(url: URL(string: "https://sub.example.test:8443/a%20b?q=%2F#part"), full: true)
        #expect(address.primary == "sub.example.test")
        #expect(address.suffix == ":8443/a%20b?q=%2f#part")
    }

    @Test(arguments: [("https://www.example.test/?", "example.test"),
                      ("https://http://www.example.test/?", "http://www.example.test")])
    func displayTrimmingRemovesOnePrefixAndOneTrailingMarker(example: (String, String)) {
        #expect(BrowserToolbarAddress(url: URL(string: example.0), full: true).title == example.1)
    }

    @Test(arguments: [false, true])
    func theNewTabIconUsesTheSecondaryForeground(dark: Bool) throws {
        let icon = try #require(SidebarNewTabAppearance.plusColor(dark: dark).usingColorSpace(.sRGB))
        #expect(abs(icon.redComponent - (dark ? 1 : 0)) < 0.001 && abs(icon.alphaComponent - 0.5) < 0.001)
    }

    @Test func newTabShowsASixteenPointMediumPlus() throws {
        let plus = try #require(NSImage(systemSymbolName: "plus", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 16, weight: .medium)))
        #expect(SidebarNewTabAppearance.title == "New Tab")
        #expect(SidebarNewTabAppearance.plus?.size == plus.size)
    }

    @MainActor private func clear(dark: Bool, hovered: Bool = false) -> ActionButton {
        _ = NSApplication.shared
        let button = ActionButton(SidebarClearAppearance.title)
        SidebarClearAppearance.apply(to: button, dark: dark, hovered: hovered)
        return button
    }

    @MainActor private func colors(_ button: ActionButton) throws -> (NSColor, NSColor) {
        let label = try #require(button.attributedTitle.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor)
        return (try #require(label.usingColorSpace(.sRGB)), try #require(button.contentTintColor?.usingColorSpace(.sRGB)))
    }

    @Test(arguments: [false, true])
    @MainActor func restingClearUsesTheTertiaryForeground(dark: Bool) throws {
        let button = clear(dark: dark)
        let (label, tint) = try colors(button)
        #expect(button.title == "Clear")
        #expect(abs(label.redComponent - (dark ? 1 : 0)) < 0.001 && abs(label.alphaComponent - 0.3) < 0.001)
        #expect(abs(tint.redComponent - (dark ? 1 : 0)) < 0.001 && abs(tint.alphaComponent - 0.3) < 0.001)
    }

    @Test(arguments: [false, true])
    @MainActor func clearLeadsWithABoldArrowInSemiboldTenPointType(dark: Bool) throws {
        let button = clear(dark: dark)
        let arrow = try #require(NSImage(systemSymbolName: "arrow.down", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 10, weight: .bold)))
        #expect(button.font == NSFont.systemFont(ofSize: 10, weight: .semibold))
        #expect(button.image?.size == arrow.size && button.imagePosition == .imageLeading && button.imageHugsTitle)
    }

    @Test(arguments: [false, true])
    @MainActor func hoveredClearUsesThePrimaryForeground(dark: Bool) throws {
        let (label, tint) = try colors(clear(dark: dark, hovered: true))
        #expect(abs(label.alphaComponent - (dark ? 0.8 : 0.9)) < 0.001 && abs(tint.alphaComponent - (dark ? 0.8 : 0.9)) < 0.001)
        #expect(dark ? label.redComponent > 0.99 : label.redComponent < 0.07)
    }
}
