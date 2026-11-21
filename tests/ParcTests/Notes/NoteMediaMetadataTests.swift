import Foundation
import Testing
@testable import Parc
@testable import ParcCore

struct NoteMediaMetadataTests {
    let page = URL(string: "https://www.example.com/posts/hello?ref=1")!

    func preview(_ html: String) -> NoteLinkPreview {
        NoteLinkMetadataParser.parse(html: html, baseURL: page)
    }

    let openGraphPage = """
    <!doctype html><html><head>
    <meta charset="utf-8">
    <title>Plain title | Example</title>
    <meta property="og:title" content="Hello, &quot;world&quot;">
    <meta property="og:description" content="A   friendly
        greeting &amp; more">
    <meta property="og:site_name" content="Example Blog">
    <meta property="og:image" content="/images/cover.jpg">
    <meta name="twitter:image" content="https://cdn.example.com/twitter.jpg">
    <link rel="icon" href="/favicon-32.png" sizes="32x32">
    <link rel="apple-touch-icon" href="/touch.png" sizes="180x180">
    </head><body><h1>Hi</h1></body></html>
    """

    @Test func openGraphTitlesWinAndEntitiesDecode() {
        #expect(preview(openGraphPage).title == "Hello, \"world\"")
    }

    @Test func descriptionsCollapseWhitespace() {
        #expect(preview(openGraphPage).summary == "A friendly greeting & more")
    }

    @Test func theSiteNameComesFromOgSiteName() {
        #expect(preview(openGraphPage).siteName == "Example Blog")
    }

    @Test func aRelativeOgImageResolves() {
        #expect(preview(openGraphPage).imageURL == "https://www.example.com/images/cover.jpg")
    }

    @Test func theBiggestTouchIconWins() {
        #expect(preview(openGraphPage).iconURL == "https://www.example.com/touch.png")
    }

    @Test func previewsBecomeBookmarks() {
        let result = preview(openGraphPage)
        #expect(result.bookmark.title == result.title)
        #expect(result.bookmark.imageURL == result.imageURL)
    }

    let fallbackPage = """
    <html><head>
    <TITLE>
      Just a   title
    </TITLE>
    <META NAME="Description" CONTENT='Single quoted &#8217;n fine'>
    <meta name="twitter:title" content="Twitter title">
    <meta name="twitter:image:src" content="//img.example.net/pic.png">
    </head></html>
    """

    @Test func twitterTitleBeatsTheTitleElement() {
        #expect(preview(fallbackPage).title == "Twitter title")
    }

    @Test func nameDescriptionAndNumericEntitiesParse() {
        #expect(preview(fallbackPage).summary == "Single quoted ’n fine")
    }

    @Test func protocolRelativeImagesTakeThePageScheme() {
        #expect(preview(fallbackPage).imageURL == "https://img.example.net/pic.png")
    }

    @Test func noIconLinksFallBackToFavicon() {
        #expect(preview(fallbackPage).iconURL == "https://www.example.com/favicon.ico")
    }

    @Test func noSiteNameMeansNone() {
        #expect(preview(fallbackPage).siteName == nil)
    }

    @Test func aLoneTitleIsEnough() {
        let bare = preview("<html><head><title> Only </title></head></html>")
        #expect(bare.title == "Only")
        #expect(bare.summary == nil)
        #expect(bare.imageURL == nil)
    }

    @Test func emptyPagesFallBackToTheHost() {
        #expect(preview("").title == "www.example.com")
    }

    let messyPage = """
    <html><head>
    <!-- <meta property="og:title" content="Commented out"> -->
    <meta content="Content first" property="og:title"/>
    <meta property=og:description content=unquoted>
    <script>var s = "<meta property='og:image' content='nope'>";</script>
    <meta property="og:image" content="javascript:alert(1)">
    <meta property="og:image" content="data:image/png;base64,AAAA">
    <meta property="og:site_name" content="">
    <base href="https://static.example.org/root/">
    <link rel="shortcut icon" href="img/fav.ico">
    <meta name="description" content="x
    """

    @Test func commentsAreSkippedAndAttributeOrderIsFree() {
        #expect(preview(messyPage).title == "Content first")
    }

    @Test func unquotedAttributesParse() {
        #expect(preview(messyPage).summary == "unquoted")
    }

    @Test func scriptStringsJavascriptAndDataNeverBecomeImages() {
        #expect(preview(messyPage).imageURL == nil)
    }

    @Test func emptyValuesAreIgnored() {
        #expect(preview(messyPage).siteName == nil)
    }

    @Test func baseMovesRelativeIcons() {
        #expect(preview(messyPage).iconURL == "https://static.example.org/root/img/fav.ico")
    }

    @Test func svgTitlesInTheBodyAreNotPageTitles() {
        #expect(preview("<html><body><svg><title>Logo</title></svg></body></html>").title == "www.example.com")
    }

    @Test func veryLongTextIsClipped() {
        let long = String(repeating: "word ", count: 200)
        let clipped = preview("<meta name=description content=\"\(long)\">")
        #expect(clipped.summary?.hasSuffix("…") == true)
        #expect((clipped.summary?.count ?? 0) < long.count)
    }

    @Test func tagsKeepValuesAndBooleanAttributes() {
        let tag = NoteLinkMetadataParser.parseTag(Substring("link REL=\"Icon\" href='/a b.png' data-x"))
        #expect(tag?.name == "link")
        #expect(tag?.attributes["rel"] == "Icon")
        #expect(tag?.attributes["href"] == "/a b.png")
        #expect(tag?.attributes["data-x"] == "")
    }

    @Test(arguments: ["/head", "!doctype html"])
    func closingTagsAndDoctypesAreNotTags(text: String) {
        #expect(NoteLinkMetadataParser.parseTag(Substring(text)) == nil)
    }

    @Test func rasterIconsBeatSvgAndMaskIcons() {
        let html = """
        <link rel="mask-icon" href="/mask.svg">
        <link rel="icon" type="image/svg+xml" href="/icon.svg" sizes="any">
        <link rel="icon" href="/icon-16.png" sizes="16x16">
        <link rel="icon" href="/icon-96.png" sizes="96x96">
        """
        #expect(preview(html).iconURL == "https://www.example.com/icon-96.png")
    }

    @Test func defaultIconsKeepSchemeAndPort() {
        #expect(NoteLinkMetadataParser.defaultIcon(for: URL(string: "http://a.io:8080/x/y")!) == "http://a.io:8080/favicon.ico")
    }

    @Test func filesHaveNoFavicon() {
        #expect(NoteLinkMetadataParser.defaultIcon(for: URL(fileURLWithPath: "/tmp/a.html")) == nil)
    }

    @Test(arguments: [
        ("Tom &amp; Jerry &lt;3", "Tom & Jerry <3"), ("&#x1F600; &#65;", "😀 A"), ("AT&T &bogus; &", "AT&T &bogus; &"),
        ("&#xD800;", "&#xD800;"),
    ])
    func entitiesDecodeAndUnknownOnesStayPut(text: String, decoded: String) {
        #expect(NoteLinkMetadataParser.decodeEntities(text) == decoded)
    }

    @Test func headerCharsetsWin() {
        #expect(NoteLinkMetadataParser.charset(contentType: "text/html; charset=ISO-8859-1", head: Data()) == .isoLatin1)
    }

    @Test func metaCharsetsAreSniffed() {
        #expect(NoteLinkMetadataParser.charset(contentType: "text/html", head: Data("<meta charset=\"windows-1252\">".utf8)) == .windowsCP1252)
    }

    @Test func quotedCharsetsParse() {
        #expect(NoteLinkMetadataParser.charset(contentType: "text/html; charset=\"utf-8\"", head: Data()) == .utf8)
    }

    @Test func unknownCharsetsFallBackToUtf8() {
        #expect(NoteLinkMetadataParser.charset(contentType: "text/html; charset=klingon", head: Data()) == .utf8)
    }

    func response(_ status: Int, _ type: String, url: URL? = nil) -> HTTPURLResponse {
        HTTPURLResponse(url: url ?? page, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": type])!
    }

    let fetched = Data("<title>Fetched</title><meta property=\"og:image\" content=\"a.png\">".utf8)

    @Test func htmlResponsesParse() throws {
        let result = NoteLinkMetadata.interpret(data: fetched, response: response(200, "text/html; charset=utf-8"), url: page)
        guard case .success(let preview) = result else {
            Issue.record("html responses succeed")
            return
        }
        #expect(preview.title == "Fetched")
        #expect(preview.imageURL == "https://www.example.com/posts/a.png")
    }

    @Test func redirectedPagesResolveAgainstTheFinalURL() {
        let moved = URL(string: "https://example.org/final/")!
        guard case .success(let preview) = NoteLinkMetadata.interpret(data: fetched, response: response(200, "text/html", url: moved), url: page) else {
            Issue.record("redirected responses succeed")
            return
        }
        #expect(preview.imageURL == "https://example.org/final/a.png")
    }

    @Test func errorStatusesFail() {
        #expect(NoteLinkMetadata.interpret(data: fetched, response: response(404, "text/html"), url: page) == .failure(.badStatus(404)))
    }

    @Test func nonHtmlDocumentsFailPolitely() {
        #expect(NoteLinkMetadata.interpret(data: Data(), response: response(200, "application/pdf"), url: page) == .failure(.notHTML))
    }

    @Test func imageLinksPreviewThemselves() {
        let picture = URL(string: "https://example.com/photos/sunset.jpg")!
        guard case .success(let preview) = NoteLinkMetadata.interpret(data: Data(), response: response(200, "image/jpeg", url: picture), url: picture) else {
            Issue.record("image responses succeed")
            return
        }
        #expect(preview.title == "sunset.jpg")
        #expect(preview.imageURL == picture.absoluteString)
        #expect(preview.siteName == "example.com")
    }

    @Test(arguments: [("", true), ("application/xhtml+xml", true), ("application/zip", false)])
    func contentTypesAreAdmittedOrNot(type: String, admitted: Bool) {
        #expect(NoteLinkMetadata.admits(contentType: type) == admitted)
    }

    @Test func requestsAreGetsWithATimeout() {
        let request = NoteLinkMetadata.request(for: page)
        #expect(request.httpMethod == "GET")
        #expect(request.timeoutInterval == NoteLinkMetadata.timeout)
    }
}
