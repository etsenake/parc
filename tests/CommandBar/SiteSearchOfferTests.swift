import AppKit

final class PCNativeSearchNavigation {
    let url: URL
    let search: Bool
    init(_ url: String, search: Bool = false) { self.url = URL(string: url)!; self.search = search }
}
final class ExtensionAction {}
final class PCNativeOmniboxScope {
    let searchHost: String
    var result: PCNativeSearchNavigation?
    var extensionAction: ExtensionAction?
    var isExtension = false
    init(_ host: String) { searchHost = host }
}
@MainActor final class ScopeOfferFixture {
    struct Result {
        var isExpired = false
        var navigation: PCNativeSearchNavigation?
        var extensionAction: ExtensionAction?
        var url: URL?
        var tabID: UUID?
        var input: String?
    }
    struct Table { var selectedRow = 0 }
    struct Site { let host: String }
    var isScoped = false, scopeInvalidated = false, dismissed = false
    var extensionDisposition: Bool? = true
    let input = NSTextField()
    var table = Table()
    var results: [Result] = []
    var nativeResults: [PCNativeSearchNavigation] = []
    var scopeOffers: [PCNativeOmniboxScope] = []
    var siteScopes: [PCNativeOmniboxScope] = []
    static func site(of scope: PCNativeOmniboxScope) -> Site? { Site(host: scope.searchHost) }
}

@main struct SiteSearchOfferTests {
    @MainActor static func main() {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        var assertions = 0
        func check(_ value: @autoclosure () -> Bool, _ message: String) {
            assertions += 1; precondition(value(), message)
        }
        let fixture = ScopeOfferFixture()
        for host in ["google.com", "youtube.com"] {
            let url = URL(string: "https://www.\(host)/")!
            let scope = PCNativeOmniboxScope("www." + host)
            fixture.siteScopes = [scope]
            fixture.results = [.init(url: url, tabID: UUID())]
            check(fixture.selectedScopeOffer === scope, "an open \(host) tab retains its site-search offer")
            fixture.results = [.init(url: url, input: url.absoluteString)]
            check(fixture.selectedScopeOffer === scope, "a top-site or recent-history website offers its active engine")
            fixture.results = [.init(url: url)]
            check(fixture.selectedScopeOffer == nil, "a URL alone does not turn a command into a website result")
            fixture.results = [.init(input: host)]
            check(fixture.selectedScopeOffer == nil, "unclassified text does not invent a site-search engine")
            fixture.results = [.init(isExpired: true, url: url, tabID: UUID())]
            check(fixture.selectedScopeOffer == nil, "an expired result has no scope offer")
        }
        let youtube = PCNativeOmniboxScope("www.youtube.com")
        fixture.siteScopes = [youtube]
        fixture.results = [.init(url: URL(string: "https://notyoutube.com/"), tabID: UUID())]
        check(fixture.selectedScopeOffer == nil, "a different site never acquires YouTube's engine")
        fixture.results = [.init(url: URL(string: "parc://www.youtube.com/"), tabID: UUID())]
        check(fixture.selectedScopeOffer == nil, "local documents and internal pages do not offer a website scope")
        fixture.results = [.init(url: URL(string: "https://www.youtube.com/"), tabID: UUID())]
        fixture.siteScopes = []
        check(fixture.selectedScopeOffer == nil, "no published active engine means no offer")
        fixture.siteScopes = [youtube]
        fixture.scopeInvalidated = true
        check(fixture.selectedScopeOffer == nil, "an invalidated engine cannot be re-entered")
        fixture.scopeInvalidated = false; fixture.isScoped = true
        check(fixture.selectedScopeOffer == nil, "an active scope does not offer another entry")
        fixture.isScoped = false; fixture.dismissed = true
        check(fixture.selectedScopeOffer == nil, "a dismissed session has no offer")
        fixture.dismissed = false; fixture.table.selectedRow = -1
        check(fixture.selectedScopeOffer == nil, "no selection means no offer")
        fixture.table.selectedRow = 0

        let page = PCNativeSearchNavigation("https://www.youtube.com/")
        fixture.results = [.init(navigation: page, url: page.url)]
        check(fixture.selectedScopeOffer == nil, "a native page outside the published results is stale")
        fixture.nativeResults = [page]
        check(fixture.selectedScopeOffer === youtube, "a current native page still offers its engine")
        let search = PCNativeSearchNavigation("https://www.youtube.com/results?search_query=music", search: true)
        fixture.results = [.init(navigation: search, url: search.url)]
        fixture.nativeResults = [search]
        check(fixture.selectedScopeOffer == nil, "native search results do not gain a host-inferred offer")
        let explicit = PCNativeOmniboxScope("www.youtube.com")
        explicit.result = search; fixture.scopeOffers = [explicit]
        check(fixture.selectedScopeOffer === explicit, "an explicit native keyword offer keeps its original identity")

        let action = ExtensionAction(), extensionScope = PCNativeOmniboxScope("")
        extensionScope.isExtension = true; extensionScope.extensionAction = action
        fixture.results = [.init(extensionAction: action)]
        fixture.scopeOffers = [extensionScope]
        check(fixture.selectedScopeOffer === extensionScope, "an extension offer stays tied to its action")
        fixture.extensionDisposition = nil
        check(fixture.selectedScopeOffer == nil, "an unavailable extension cannot enter a scope")
        print("SiteSearchOfferTests: \(assertions) assertions passed")
    }
}
