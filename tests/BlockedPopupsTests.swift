import Foundation

@main
struct BlockedPopupsTests {
    static func main() { exitOnFailure(runChecks) }
    static func runChecks() {
        var checks = 0
        func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
            checks += 1
            precondition(condition(), message)
        }
        func snapshot(_ items: [(String, Int, String)], allowed: Bool = false, canAllow: Bool = true,
                      site: String = "https://canvas.school.edu/courses/4821") -> [String: Any] {
            ["revision": NSNumber(value: 7), "site": site, "allowed": NSNumber(value: allowed),
             "canAllow": NSNumber(value: canAllow),
             "items": items.map { ["kind": $0.0, "identifier": NSNumber(value: $0.1), "url": $0.2] }]
        }

        expect(BlockedPageContent(snapshot: nil) == nil, "no snapshot means nothing is shown")
        expect(BlockedPageContent(snapshot: snapshot([])) == nil, "an empty list shows no sign")
        expect(BlockedPageContent(snapshot: snapshot([("download", 1, "https://a.example/")])) == nil,
               "rows of an unknown kind are ignored")

        let canvas = BlockedPageContent(snapshot: snapshot([("popup", 0, "https://sso.canvaslms.com/login?x=1")]))
        expect(canvas?.revision == 7 && canvas?.items.count == 1, "the engine's revision and rows survive parsing")
        expect(canvas?.summary == "Pop-up blocked", "one pop-up reads as a calm singular")
        expect(canvas?.items.first?.title == "sso.canvaslms.com" && canvas?.items.first?.subtitle == "Pop-up"
               && canvas?.items.first?.actionTitle == "Open", "a pop-up row names its destination host")
        expect(canvas?.siteName == "canvas.school.edu" && canvas?.allowDetail == "from canvas.school.edu",
               "Always Allow names the page's own site")
        expect(canvas?.canAllow == true && canvas?.allowed == false, "a user-controlled block can be allowed")
        expect(canvas?.glyphName == "popup-blocked", "pop-ups use the window glyph")

        let busy = BlockedPageContent(snapshot: snapshot([("popup", 3, "https://a.example/"), ("popup", 4, "https://b.example/"),
                                                         ("popup", 5, "https://c.example/"), ("redirect", 0, "https://go.example/")]))
        expect(busy?.summary == "3 pop-ups and a redirect blocked", "pop-ups and a redirect share one summary")
        expect(busy?.displayItems.first?.kind == .redirect && busy?.displayItems.first?.actionTitle == "Go",
               "a redirect is listed first so it is never hidden behind More")
        expect(busy?.popupCount == 3 && busy?.redirectCount == 1, "counts split by kind")

        let redirect = BlockedPageContent(snapshot: snapshot([("redirect", 0, "https://go.example/"), ("redirect", 1, "https://two.example/")]))
        expect(redirect?.summary == "2 redirects blocked" && redirect?.glyphName == "redirect-blocked",
               "redirect-only pages use the redirect glyph and wording")
        let pair = BlockedPageContent(snapshot: snapshot([("popup", 0, "https://a.example/"), ("redirect", 0, "https://go.example/")]))
        expect(pair?.summary == "A pop-up and a redirect blocked", "one of each reads naturally")
        let mixed = BlockedPageContent(snapshot: snapshot([("popup", 0, "https://a.example/"), ("redirect", 0, "https://go.example/"),
                                                          ("redirect", 1, "https://two.example/")]))
        expect(mixed?.summary == "A pop-up and 2 redirects blocked", "one pop-up with several redirects reads naturally")
        var damaged = snapshot([("popup", 0, "https://a.example/")])
        damaged["items"] = (damaged["items"] as? [Any] ?? []) + ["not a row"]
        expect(BlockedPageContent(snapshot: damaged)?.items.count == 1, "a malformed row doesn't hide the good ones")
        let empty = BlockedPageContent(snapshot: snapshot([("popup", 0, ""), ("redirect", 0, "")]))
        expect(empty?.items.map(\.title) == ["Blank pop-up", "Blank page"], "an empty address still gets a readable title")
        expect(canvas?.allowTooltip == "Allows pop-ups and redirects from canvas.school.edu until you change it in Settings",
               "the tooltip says what Always Allow covers and where to undo it")
        let single = BlockedPageContent(snapshot: snapshot([("redirect", 0, "https://go.example/")]))
        expect(single?.summary == "Redirect blocked", "one redirect reads as a calm singular")

        let allowed = BlockedPageContent(snapshot: snapshot([("popup", 0, "https://a.example/")], allowed: true, canAllow: true))
        expect(allowed?.allowed == true && allowed?.canAllow == false, "an allowed site offers no second Always Allow")
        let managed = BlockedPageContent(snapshot: snapshot([("popup", 0, "https://a.example/")], canAllow: false))
        expect(managed?.canAllow == false, "a setting the user doesn't control offers no Always Allow")

        let blank = BlockedPageContent(snapshot: snapshot([("popup", 0, "about:blank")]))
        expect(blank?.items.first?.title == "about:blank", "a hostless pop-up shows its address")
        expect(BlockedPageContent.allowHint == "Sign-in or payment window? Allow, then try again.",
               "the hint steers sign-in and payment windows to Always Allow")
        print("BlockedPopupsTests: \(checks) checks passed")
    }
}
