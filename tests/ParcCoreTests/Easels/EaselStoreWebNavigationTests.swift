import Foundation
import Testing
@testable import ParcCore

struct EaselStoreWebNavigationTests {
    @Test(arguments: [(" example.com/a?x=1#part ", "https://example.com/a?x=1#part"), ("http://localhost:8000/a", "http://localhost:8000/a")])
    func anAddressKeepsItsExplicitSchemeOrDefaultsToHTTPS(_ input: String, _ expected: String) {
        #expect(EaselWebNavigation.address(input)?.absoluteString == expected)
    }

    @Test(arguments: ["", "a b", "javascript:alert(1)", "file:///tmp/a", "https://user:password@example.com", "https://", "https://example.com\nsecret"])
    func invalidAddressesAreRefused(_ input: String) {
        #expect(EaselWebNavigation.address(input) == nil, "Invalid or credential-bearing address stays unsubmitted")
    }

    @Test(arguments: EaselWebNavigation.Category.allCases)
    func searchPreservesTheExactQuery(_ category: EaselWebNavigation.Category) {
        let draft = EaselWebNavigation.Draft(mode: .search, text: "ice + snow & café?", category: category)
        let url = EaselWebNavigation.destination(draft)!
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        #expect(components.host == "duckduckgo.com" && components.queryItems?.first(where: { $0.name == "q" })?.value == draft.text, "Search preserves exact query once for every recovered category")
        #expect(!url.absoluteString.contains("t=hc") && url.absoluteString.contains("%2B"), "No copied tracking token; literal plus remains data")
    }

    @Test
    func mapsSearchUsesTheMapsVertical() {
        let maps = URLComponents(url: EaselWebNavigation.destination(.init(mode: .search, text: "Edmonton", category: .maps))!, resolvingAgainstBaseURL: false)!
        #expect(maps.queryItems?.first(where: { $0.name == "iaxm" })?.value == "maps", "Maps uses the current official provider route")
        #expect(maps.queryItems?.contains(where: { $0.name == "ia" }) == false, "Maps does not inherit the historical News vertical")
    }

    @Test
    func aBlankSearchHasNoDestination() {
        #expect(EaselWebNavigation.destination(.init(mode: .search, text: "  ")) == nil, "Empty query does not fabricate a destination")
    }
}
