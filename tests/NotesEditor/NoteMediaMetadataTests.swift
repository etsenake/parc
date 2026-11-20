import Foundation

@main @MainActor
struct NoteMediaMetadataTests {
    static func expect(_ value: Bool, _ message: String) {
        if !value { failTest(message) }
    }

    static let page = URL(string: "https://www.example.com/posts/hello?ref=1")!

    static func main() {
        openGraph()
        fallbacks()
        tolerance()
        icons()
        entities()
        encodings()
        responses()
        print("NoteMediaMetadataTests passed")
    }

    static func openGraph() {
        let html = """
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
        let preview = NoteLinkMetadataParser.parse(html: html, baseURL: page)
        expect(preview.title == "Hello, \"world\"", "og:title wins and entities decode: \(preview.title ?? "nil")")
        expect(preview.summary == "A friendly greeting & more", "descriptions collapse whitespace: \(preview.summary ?? "nil")")
        expect(preview.siteName == "Example Blog", "site name comes from og:site_name")
        expect(preview.imageURL == "https://www.example.com/images/cover.jpg", "relative og:image resolves: \(preview.imageURL ?? "nil")")
        expect(preview.iconURL == "https://www.example.com/touch.png", "the biggest touch icon wins: \(preview.iconURL ?? "nil")")
        expect(preview.bookmark.title == preview.title && preview.bookmark.imageURL == preview.imageURL, "previews become bookmarks")
    }

    static func fallbacks() {
        let html = """
        <html><head>
        <TITLE>
          Just a   title
        </TITLE>
        <META NAME="Description" CONTENT='Single quoted &#8217;n fine'>
        <meta name="twitter:title" content="Twitter title">
        <meta name="twitter:image:src" content="//img.example.net/pic.png">
        </head></html>
        """
        let preview = NoteLinkMetadataParser.parse(html: html, baseURL: page)
        expect(preview.title == "Twitter title", "twitter:title beats <title>")
        expect(preview.summary == "Single quoted ’n fine", "name=description and numeric entities: \(preview.summary ?? "nil")")
        expect(preview.imageURL == "https://img.example.net/pic.png", "protocol-relative images take the page scheme")
        expect(preview.iconURL == "https://www.example.com/favicon.ico", "no icon links fall back to /favicon.ico")
        expect(preview.siteName == nil, "no site name means none")
        let bare = NoteLinkMetadataParser.parse(html: "<html><head><title> Only </title></head></html>", baseURL: page)
        expect(bare.title == "Only" && bare.summary == nil && bare.imageURL == nil, "a lone title is enough")
        let empty = NoteLinkMetadataParser.parse(html: "", baseURL: page)
        expect(empty.title == "www.example.com", "empty pages fall back to the host")
    }

    static func tolerance() {
        let html = """
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
        let preview = NoteLinkMetadataParser.parse(html: html, baseURL: page)
        expect(preview.title == "Content first", "comments are skipped and attribute order is free: \(preview.title ?? "nil")")
        expect(preview.summary == "unquoted", "unquoted attributes parse")
        expect(preview.imageURL == nil, "script strings, javascript: and data: never become images: \(preview.imageURL ?? "nil")")
        expect(preview.siteName == nil, "empty values are ignored")
        expect(preview.iconURL == "https://static.example.org/root/img/fav.ico", "<base> moves relative icons: \(preview.iconURL ?? "nil")")
        let svg = NoteLinkMetadataParser.parse(html: "<html><body><svg><title>Logo</title></svg></body></html>", baseURL: page)
        expect(svg.title == "www.example.com", "svg titles in the body are not page titles")
        let long = String(repeating: "word ", count: 200)
        let clipped = NoteLinkMetadataParser.parse(html: "<meta name=description content=\"\(long)\">", baseURL: page)
        expect((clipped.summary?.count ?? 0) <= 401 && clipped.summary?.hasSuffix("…") == true, "very long text is clipped")
        let tag = NoteLinkMetadataParser.parseTag("link REL=\"Icon\" href='/a b.png' data-x")
        expect(tag?.name == "link" && tag?.attributes["rel"] == "Icon" && tag?.attributes["href"] == "/a b.png"
               && tag?.attributes["data-x"] == "", "tags keep values and boolean attributes")
        expect(NoteLinkMetadataParser.parseTag("/head") == nil && NoteLinkMetadataParser.parseTag("!doctype html") == nil,
               "closing tags and doctypes are not tags")
    }

    static func icons() {
        let html = """
        <link rel="mask-icon" href="/mask.svg">
        <link rel="icon" type="image/svg+xml" href="/icon.svg" sizes="any">
        <link rel="icon" href="/icon-16.png" sizes="16x16">
        <link rel="icon" href="/icon-96.png" sizes="96x96">
        """
        let preview = NoteLinkMetadataParser.parse(html: html, baseURL: page)
        expect(preview.iconURL == "https://www.example.com/icon-96.png", "raster icons beat svg and mask icons: \(preview.iconURL ?? "nil")")
        expect(NoteLinkMetadataParser.defaultIcon(for: URL(string: "http://a.io:8080/x/y")!) == "http://a.io:8080/favicon.ico",
               "default icons keep scheme and port")
        expect(NoteLinkMetadataParser.defaultIcon(for: URL(fileURLWithPath: "/tmp/a.html")) == nil, "files have no favicon")
    }

    static func entities() {
        expect(NoteLinkMetadataParser.decodeEntities("Tom &amp; Jerry &lt;3") == "Tom & Jerry <3", "named entities")
        expect(NoteLinkMetadataParser.decodeEntities("&#x1F600; &#65;") == "😀 A", "hex and decimal entities")
        expect(NoteLinkMetadataParser.decodeEntities("AT&T &bogus; &") == "AT&T &bogus; &", "unknown entities stay put")
        expect(NoteLinkMetadataParser.decodeEntities("&#xD800;") == "&#xD800;", "invalid scalars stay put")
    }

    static func encodings() {
        let latin = NoteLinkMetadataParser.charset(contentType: "text/html; charset=ISO-8859-1", head: Data())
        expect(latin == .isoLatin1, "header charsets win")
        let sniffed = NoteLinkMetadataParser.charset(contentType: "text/html", head: Data("<meta charset=\"windows-1252\">".utf8))
        expect(sniffed == .windowsCP1252, "meta charsets are sniffed")
        let quoted = NoteLinkMetadataParser.charset(contentType: "text/html; charset=\"utf-8\"", head: Data())
        expect(quoted == .utf8, "quoted charsets parse")
        let unknown = NoteLinkMetadataParser.charset(contentType: "text/html; charset=klingon", head: Data())
        expect(unknown == .utf8, "unknown charsets fall back to UTF-8")
    }

    static func responses() {
        func response(_ status: Int, _ type: String, url: URL? = nil) -> HTTPURLResponse {
            HTTPURLResponse(url: url ?? page, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": type])!
        }
        let html = Data("<title>Fetched</title><meta property=\"og:image\" content=\"a.png\">".utf8)
        if case .success(let preview) = NoteLinkMetadata.interpret(data: html, response: response(200, "text/html; charset=utf-8"), url: page) {
            expect(preview.title == "Fetched" && preview.imageURL == "https://www.example.com/posts/a.png", "html responses parse")
        } else {
            expect(false, "html responses succeed")
        }
        let moved = URL(string: "https://example.org/final/")!
        if case .success(let preview) = NoteLinkMetadata.interpret(data: html, response: response(200, "text/html", url: moved), url: page) {
            expect(preview.imageURL == "https://example.org/final/a.png", "redirected pages resolve against the final URL")
        } else {
            expect(false, "redirected responses succeed")
        }
        let notFound = NoteLinkMetadata.interpret(data: html, response: response(404, "text/html"), url: page)
        expect(notFound == .failure(.badStatus(404)), "error statuses fail")
        let pdf = NoteLinkMetadata.interpret(data: Data(), response: response(200, "application/pdf"), url: page)
        expect(pdf == .failure(.notHTML), "non-HTML documents fail politely")
        let picture = URL(string: "https://example.com/photos/sunset.jpg")!
        if case .success(let preview) = NoteLinkMetadata.interpret(data: Data(), response: response(200, "image/jpeg", url: picture), url: picture) {
            expect(preview.title == "sunset.jpg" && preview.imageURL == picture.absoluteString && preview.siteName == "example.com",
                   "image links preview themselves")
        } else {
            expect(false, "image responses succeed")
        }
        expect(NoteLinkMetadata.admits(contentType: "") && NoteLinkMetadata.admits(contentType: "application/xhtml+xml"),
               "missing and xhtml types are admitted")
        expect(!NoteLinkMetadata.admits(contentType: "application/zip"), "zips are not admitted")
        let request = NoteLinkMetadata.request(for: page)
        expect(request.httpMethod == "GET" && request.timeoutInterval == NoteLinkMetadata.timeout, "requests are GETs with a timeout")
    }
}
