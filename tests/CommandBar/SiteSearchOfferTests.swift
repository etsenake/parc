import AppKit

final class PCNativeSearchNavigation {
    let url: URL
    let search: Bool
    init(_ url: String, search: Bool = false) { self.url = URL(string: url)!; self.search = search }
}
final class ExtensionAction {}
final class PCNativeOmniboxScope {
    let searchHost: String
    let isLearned: Bool
    var result: PCNativeSearchNavigation?
    var extensionAction: ExtensionAction?
    var isExtension = false
    init(_ host: String, learned: Bool = false) { searchHost = host; isLearned = learned }
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
    static func isLearned(_ scope: PCNativeOmniboxScope) -> Bool { scope.isLearned }
}

@main struct SiteSearchOfferTests {
    @MainActor static func main() { exitOnFailure(runChecks) }
    @MainActor static func runChecks() {
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
        for (page, searchHost) in [("https://www.linkedin.com/feed/", "linkedin.com"),
                                   ("https://en.wikipedia.org/wiki/Chromium", "wikipedia.org"),
                                   ("https://mobile.twitter.com/home", "twitter.com")] {
            let scope = PCNativeOmniboxScope(searchHost)
            fixture.siteScopes = [scope]
            fixture.results = [.init(url: URL(string: page)!, tabID: UUID())]
            check(fixture.selectedScopeOffer === scope, "a page on a subdomain of \(searchHost) offers that site's search")
            fixture.results = [.init(url: URL(string: "https://not\(searchHost)/")!, tabID: UUID())]
            check(fixture.selectedScopeOffer == nil, "a look-alike of \(searchHost) never acquires its search")
        }
        let google = PCNativeOmniboxScope("www.google.com"), gmail = PCNativeOmniboxScope("mail.google.com")
        let docs = PCNativeOmniboxScope("docs.google.com")
        fixture.siteScopes = [google, gmail, docs]
        fixture.results = [.init(url: URL(string: "https://mail.google.com/mail/u/0/")!, tabID: UUID())]
        check(fixture.selectedScopeOffer === gmail, "Gmail rows offer Gmail, not the Google engine listed first")
        fixture.results = [.init(url: URL(string: "https://docs.google.com/document/u/0/")!, tabID: UUID())]
        check(fixture.selectedScopeOffer === docs, "Docs rows offer Docs")
        fixture.results = [.init(url: URL(string: "https://www.google.com/maps")!, tabID: UUID())]
        check(fixture.selectedScopeOffer === google, "Google's own pages still offer Google")
        let broadGoogle = PCNativeOmniboxScope("google.com")
        fixture.siteScopes = [broadGoogle, gmail]
        fixture.results = [.init(url: URL(string: "https://mail.google.com/mail/u/0/")!, tabID: UUID())]
        check(fixture.selectedScopeOffer === gmail, "an exact site beats a broader engine listed first")
        fixture.results = [.init(url: URL(string: "https://news.google.com/")!, tabID: UUID())]
        check(fixture.selectedScopeOffer === broadGoogle, "the broader engine still covers its other subdomains")
        let wikipedia = PCNativeOmniboxScope("wikipedia.org"), english = PCNativeOmniboxScope("en.wikipedia.org")
        fixture.siteScopes = [wikipedia, english]
        fixture.results = [.init(url: URL(string: "https://EN.Wikipedia.org/wiki/Chromium")!, tabID: UUID())]
        check(fixture.selectedScopeOffer === english, "the exact site wins, ignoring case")
        fixture.results = [.init(url: URL(string: "https://m.en.wikipedia.org/wiki/Chromium")!, tabID: UUID())]
        check(fixture.selectedScopeOffer === english, "the closest parent site wins over a broader one listed first")
        let intranet = PCNativeOmniboxScope("wiki")
        fixture.siteScopes = [intranet]
        fixture.results = [.init(url: URL(string: "https://minecraft.wiki/")!, tabID: UUID())]
        check(fixture.selectedScopeOffer == nil, "a single-label intranet engine never claims public sites under that name")
        let spotify = PCNativeOmniboxScope("open.spotify.com")
        fixture.siteScopes = [spotify]
        fixture.results = [.init(url: URL(string: "https://spotify.com/")!, tabID: UUID())]
        check(fixture.selectedScopeOffer === spotify, "a parent site still offers its search subdomain")
        let gitlab = PCNativeOmniboxScope("gitlab.com", learned: true)
        fixture.siteScopes = [gitlab]
        for page in ["https://gitlab.com/gitlab-org/gitlab", "https://www.gitlab.com/", "https://GitLab.com/explore"] {
            fixture.results = [.init(url: URL(string: page)!, tabID: UUID())]
            check(fixture.selectedScopeOffer === gitlab, "a search GitLab advertised is offered on GitLab's own page \(page)")
        }
        for page in ["https://docs.gitlab.com/", "https://about.gitlab.com.evil.example/", "https://notgitlab.com/", "https://evil.example/gitlab.com"] {
            fixture.results = [.init(url: URL(string: page)!, tabID: UUID())]
            check(fixture.selectedScopeOffer == nil, "a learned search never reaches another site such as \(page)")
        }
        let vimeo = PCNativeOmniboxScope("www.vimeo.com", learned: true)
        fixture.siteScopes = [gitlab, vimeo]
        fixture.results = [.init(url: URL(string: "https://vimeo.com/channels")!, tabID: UUID())]
        check(fixture.selectedScopeOffer === vimeo, "a learned search on the www host covers the bare site")
        let learnedDocs = PCNativeOmniboxScope("docs.github.com", learned: true), github = PCNativeOmniboxScope("github.com")
        fixture.siteScopes = [learnedDocs, github]
        fixture.results = [.init(url: URL(string: "https://docs.github.com/en")!, tabID: UUID())]
        check(fixture.selectedScopeOffer === github, "an engine the Space already uses beats a learned one on the same page")
        let learnedHub = PCNativeOmniboxScope("github.com", learned: true)
        fixture.siteScopes = [learnedHub]
        fixture.results = [.init(url: URL(string: "https://gist.github.com/")!, tabID: UUID())]
        check(fixture.selectedScopeOffer == nil, "a learned search never claims its subdomains")
        fixture.siteScopes = [PCNativeOmniboxScope("gist.github.com", learned: true)]
        fixture.results = [.init(url: URL(string: "https://github.com/")!, tabID: UUID())]
        check(fixture.selectedScopeOffer == nil, "a learned search never claims its parent site")
        let learnedPage = PCNativeSearchNavigation("https://gitlab.com/")
        fixture.siteScopes = [gitlab]
        fixture.results = [.init(navigation: learnedPage, url: learnedPage.url)]
        fixture.nativeResults = [learnedPage]
        check(fixture.selectedScopeOffer === gitlab, "a current native GitLab page offers its learned search")
        let learnedSearch = PCNativeSearchNavigation("https://gitlab.com/search?search=ci", search: true)
        fixture.results = [.init(navigation: learnedSearch, url: learnedSearch.url)]
        fixture.nativeResults = [learnedSearch]
        check(fixture.selectedScopeOffer == nil, "a search result never gains a learned offer")
        fixture.nativeResults = []

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
