import Foundation
import Testing
@testable import Parc

struct BlockedPopupsTests {
    private static let page = "https://canvas.school.edu/courses/4821"

    private static func snapshot(_ items: [(String, Int, String)], allowed: Bool = false, canAllow: Bool = true,
                                 site: String = page) -> [String: Any] {
        ["revision": NSNumber(value: 7), "site": site, "allowed": NSNumber(value: allowed),
         "canAllow": NSNumber(value: canAllow),
         "items": items.map { ["kind": $0.0, "identifier": NSNumber(value: $0.1), "url": $0.2] }]
    }

    private static func content(_ items: [(String, Int, String)], allowed: Bool = false,
                                canAllow: Bool = true) -> BlockedPageContent? {
        BlockedPageContent(snapshot: snapshot(items, allowed: allowed, canAllow: canAllow))
    }

    private static let signIn = [("popup", 0, "https://sso.canvaslms.com/login?x=1")]

    @Test func noSnapshotShowsNothing() {
        #expect(BlockedPageContent(snapshot: nil) == nil)
    }

    @Test func anEmptyListShowsNothing() {
        #expect(Self.content([]) == nil)
    }

    @Test func rowsOfAnUnknownKindAreIgnored() {
        #expect(Self.content([("download", 1, "https://a.example/")]) == nil)
    }

    @Test func theEnginesRevisionAndRowsSurviveParsing() throws {
        let parsed = try #require(Self.content(Self.signIn))
        #expect(parsed.revision == 7)
        #expect(parsed.items.count == 1)
    }

    @Test func aPopupRowNamesItsDestinationHost() throws {
        let item = try #require(Self.content(Self.signIn)?.items.first)
        #expect(item.title == "sso.canvaslms.com")
        #expect(item.subtitle == "Pop-up")
        #expect(item.actionTitle == "Open")
    }

    @Test func alwaysAllowNamesThePagesOwnSite() throws {
        let parsed = try #require(Self.content(Self.signIn))
        #expect(parsed.siteName == "canvas.school.edu")
        #expect(parsed.allowDetail == "from canvas.school.edu")
    }

    @Test func theTooltipSaysWhatAlwaysAllowCoversAndWhereToUndoIt() throws {
        let parsed = try #require(Self.content(Self.signIn))
        #expect(parsed.allowTooltip == "Allows pop-ups and redirects from canvas.school.edu until you change it in Settings")
    }

    @Test func aUserControlledBlockCanBeAllowed() throws {
        let parsed = try #require(Self.content(Self.signIn))
        #expect(parsed.canAllow)
        #expect(!parsed.allowed)
    }

    @Test func popupsUseTheWindowGlyph() throws {
        #expect(try #require(Self.content(Self.signIn)).glyphName == "popup-blocked")
    }

    @Test func aRedirectIsListedFirstSoItIsNeverHiddenBehindMore() throws {
        let parsed = try #require(Self.content([("popup", 3, "https://a.example/"), ("popup", 4, "https://b.example/"),
                                                ("popup", 5, "https://c.example/"), ("redirect", 0, "https://go.example/")]))
        #expect(parsed.displayItems.first?.kind == .redirect)
        #expect(parsed.displayItems.first?.actionTitle == "Go")
    }

    @Test func countsSplitByKind() throws {
        let parsed = try #require(Self.content([("popup", 3, "https://a.example/"), ("popup", 4, "https://b.example/"),
                                                ("popup", 5, "https://c.example/"), ("redirect", 0, "https://go.example/")]))
        #expect(parsed.popupCount == 3)
        #expect(parsed.redirectCount == 1)
    }

    @Test(arguments: [
        ([("popup", 0, "https://a.example/")], "Pop-up blocked"),
        ([("redirect", 0, "https://go.example/")], "Redirect blocked"),
        ([("redirect", 0, "https://go.example/"), ("redirect", 1, "https://two.example/")], "2 redirects blocked"),
        ([("popup", 0, "https://a.example/"), ("redirect", 0, "https://go.example/")], "A pop-up and a redirect blocked"),
        ([("popup", 0, "https://a.example/"), ("redirect", 0, "https://go.example/"),
          ("redirect", 1, "https://two.example/")], "A pop-up and 2 redirects blocked"),
        ([("popup", 3, "https://a.example/"), ("popup", 4, "https://b.example/"), ("popup", 5, "https://c.example/"),
          ("redirect", 0, "https://go.example/")], "3 pop-ups and a redirect blocked"),
    ] as [([(String, Int, String)], String)])
    func theSummaryReadsNaturally(items: [(String, Int, String)], summary: String) throws {
        #expect(try #require(Self.content(items)).summary == summary)
    }

    @Test func aRedirectOnlyPageUsesTheRedirectGlyph() throws {
        let parsed = try #require(Self.content([("redirect", 0, "https://go.example/")]))
        #expect(parsed.glyphName == "redirect-blocked")
    }

    @Test func aMalformedRowDoesNotHideTheGoodOnes() throws {
        var damaged = Self.snapshot([("popup", 0, "https://a.example/")])
        damaged["items"] = (damaged["items"] as? [Any] ?? []) + ["not a row"]
        #expect(BlockedPageContent(snapshot: damaged)?.items.count == 1)
    }

    @Test func anEmptyAddressStillGetsAReadableTitle() throws {
        let parsed = try #require(Self.content([("popup", 0, ""), ("redirect", 0, "")]))
        #expect(parsed.items.map(\.title) == ["Blank pop-up", "Blank page"])
    }

    @Test func anAllowedSiteOffersNoSecondAlwaysAllow() throws {
        let parsed = try #require(Self.content([("popup", 0, "https://a.example/")], allowed: true, canAllow: true))
        #expect(parsed.allowed)
        #expect(!parsed.canAllow)
    }

    @Test func aSettingTheUserDoesNotControlOffersNoAlwaysAllow() throws {
        let parsed = try #require(Self.content([("popup", 0, "https://a.example/")], canAllow: false))
        #expect(!parsed.canAllow)
    }

    @Test func aHostlessPopupShowsItsAddress() throws {
        let parsed = try #require(Self.content([("popup", 0, "about:blank")]))
        #expect(parsed.items.first?.title == "about:blank")
    }

    @Test func theHintSteersSignInAndPaymentWindowsToAlwaysAllow() {
        #expect(BlockedPageContent.allowHint == "Sign-in or payment window? Allow, then try again.")
    }
}
