import Foundation
import Testing
@testable import ParcCore

struct NoteUnsplashTests {
    let photoJSON = """

    {
      "id": "Dwu85P9SOIk",
      "width": 6000,
      "height": 4000,
      "color": "#26598c",
      "description": null,
      "alt_description": "a mountain lake at\\nsunrise",
      "urls": {
        "raw": "https://images.unsplash.com/photo-1417325384643?ixid=M3w1&ixlib=rb-4.0.3",
        "full": "https://images.unsplash.com/photo-1417325384643?ixid=M3w1&q=85&fm=jpg",
        "regular": "https://images.unsplash.com/photo-1417325384643?ixid=M3w1&w=1080",
        "small": "https://images.unsplash.com/photo-1417325384643?ixid=M3w1&w=400",
        "thumb": "https://images.unsplash.com/photo-1417325384643?ixid=M3w1&w=200"
      },
      "links": {
        "html": "https://unsplash.com/photos/Dwu85P9SOIk",
        "download": "https://unsplash.com/photos/Dwu85P9SOIk/download",
        "download_location": "https://api.unsplash.com/photos/Dwu85P9SOIk/download?ixid=M3w1"
      },
      "user": {
        "username": "jane",
        "name": "Jane \\"JJ\\" Doe",
        "links": { "html": "https://unsplash.com/@jane" }
      }
    }

    """

    func photo() throws -> NoteUnsplashPhoto {
        guard let photo = try? NoteUnsplash.decoder().decode(NoteUnsplashPhoto.self, from: Data(photoJSON.utf8)) else {
            throw NoteTestFailure("a photo from the API decodes")
        }
        return photo
    }

    func query(_ url: URL?) -> [String: String] {
        let items = url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems } ?? []
        return Dictionary(items.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { _, last in last })
    }

    @Test func thePhotographersNameComesFromTheUser() throws {
        let photo = try photo()
        #expect(photo.photographer == "Jane \"JJ\" Doe", "the photographer's name comes from the user")
        #expect(abs(photo.aspectRatio - 1.5) < 0.0001, "the aspect ratio follows the pixel size")
        #expect(photo.placeholderColor.map { abs($0.red - 0x26 / 255.0) < 0.001 && abs($0.blue - 0x8c / 255.0) < 0.001 } == true, "the API's colour becomes the tile's placeholder")
        #expect(NoteUnsplash.altText(for: photo) == "A mountain lake at sunrise", "alt text is one tidy, capitalised line")
        #expect(NoteUnsplash.suggestedName(for: photo) == "Photo by Jane \"JJ\" Doe", "attachments are named after the photographer")

        let search = NoteUnsplash.listRequest(query: "  lake  ", page: 2, orientation: .landscape, key: "abc")
        #expect(search.url?.path == "/search/photos", "a query searches photos")
        let searchQuery = query(search.url)
        #expect(searchQuery["query"] == "lake" && searchQuery["page"] == "2" && searchQuery["per_page"] == "30", "search sends the trimmed query and page")
        #expect(searchQuery["orientation"] == "landscape" && searchQuery["content_filter"] == "high", "cover searches ask for safe landscape photos")
        #expect(search.value(forHTTPHeaderField: "Authorization") == "Client-ID abc", "requests carry the access key")
        #expect(search.value(forHTTPHeaderField: "Accept-Version") == "v1", "requests pin the API version")
        let feed = NoteUnsplash.listRequest(query: " ", page: 0, orientation: .landscape, key: "abc")
        #expect(feed.url?.path == "/photos" && query(feed.url)["page"] == "1", "an empty query shows the editorial feed from page one")
        #expect(query(feed.url)["orientation"] == nil, "the feed doesn't take an orientation")

        let tracking = NoteUnsplash.trackingRequest(for: photo, key: "abc")
        #expect(tracking?.url?.absoluteString == "https://api.unsplash.com/photos/Dwu85P9SOIk/download?ixid=M3w1", "downloads ping the tracking endpoint")
        #expect(tracking?.value(forHTTPHeaderField: "Authorization") == "Client-ID abc", "the tracking ping is authorised")
        var stray = photo
        stray.links.downloadLocation = "https://example.com/steal"
        #expect(NoteUnsplash.trackingRequest(for: stray, key: "abc") == nil, "the key never goes anywhere but the Unsplash API")

        let image = query(NoteUnsplash.imageURL(for: photo, width: NoteUnsplash.coverWidth))
        #expect(image["w"] == "2400" && image["fm"] == "jpg" && image["fit"] == "max" && image["ixid"] == "M3w1", "the download is a sized JPEG of the raw photo")
        let thumb = NoteUnsplash.thumbnailURL(for: photo, width: 400)
        #expect(query(thumb)["w"] == "400" && thumb?.host == "images.unsplash.com", "thumbnails hotlink a small rendition")
        var noRaw = photo
        noRaw.urls.raw = nil
        #expect(NoteUnsplash.imageURL(for: noRaw, width: 2000)?.absoluteString == photo.urls.full, "without a raw URL the full rendition is used")

        let searchJSON = "{\"total\": 61, \"total_pages\": 3, \"results\": [" + photoJSON + "]}"
        guard let first = try? NoteUnsplash.page(from: Data(searchJSON.utf8), searching: true, page: 1),
              let last = try? NoteUnsplash.page(from: Data(searchJSON.utf8), searching: true, page: 3) else { Issue.record("search results decode"); return }
        #expect(first.photos.count == 1 && first.hasMore && !last.hasMore, "search pages until the last one")
        let feedPage = try #require(try? NoteUnsplash.page(from: Data(("[" + photoJSON + "]").utf8), searching: false, page: 1), "the feed decodes")
        #expect(feedPage.photos.count == 1 && !feedPage.hasMore, "a short feed page is the end")
        do {
            _ = try NoteUnsplash.page(from: Data("{\"errors\":[\"nope\"]}".utf8), searching: true, page: 1)
            Issue.record("garbage doesn't decode")
        } catch {
            #expect(error as? NoteUnsplashError == .unreadable, "garbage reports an unreadable reply")
        }
        #expect(NoteUnsplash.merge([photo], [photo]).count == 1, "repeated photos across pages show once")
        #expect(NoteUnsplash.fileExtension(for: Data([0xFF, 0xD8, 0xFF, 0xE0, 0, 0x10])) == "jpg", "JPEG downloads save as .jpg")
        #expect(NoteUnsplash.fileExtension(for: Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 0])) == "png", "PNG downloads save as .png")
        #expect(NoteUnsplash.fileExtension(for: Data("RIFF\u{0}\u{0}\u{0}\u{0}WEBP".utf8)) == "webp", "WebP downloads save as .webp")
        #expect(NoteUnsplash.fileExtension(for: Data("\u{0}\u{0}\u{0}\u{1C}ftypavif".utf8)) == "avif", "AVIF downloads save as .avif")
        #expect(NoteUnsplash.fileExtension(for: Data("<html>oops</html>".utf8)) == nil, "an HTML error page isn't an image")

        #expect(NoteUnsplash.error(status: 200, remaining: nil, body: nil) == nil, "success is no error")
        #expect(NoteUnsplash.error(status: 401, remaining: nil, body: nil) == .unauthorized, "401 means a bad key")
        #expect(NoteUnsplash.error(status: 403, remaining: "0", body: nil) == .rateLimited, "403 with nothing left is the rate limit")
        #expect(NoteUnsplash.error(status: 403, remaining: "12", body: Data("Rate Limit Exceeded".utf8)) == .rateLimited, "the rate-limit body is recognised")
        #expect(NoteUnsplash.error(status: 403, remaining: "12", body: nil) == .unauthorized, "other 403s are about the key")
        #expect(NoteUnsplash.error(status: 503, remaining: nil, body: nil) == .unavailable(503), "server trouble keeps its status")

        let suite = "parc.tests.unsplash." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite), "a scratch defaults suite opens")
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(NoteUnsplash.builtInAccessKey.isEmpty, "Parc ships without a baked-in key")
        #expect(NoteUnsplash.accessKey(defaults: defaults) == nil, "no key means no Unsplash tab")
        defaults.set("  live-key \n", forKey: NoteUnsplash.accessKeyDefaultsKey)
        #expect(NoteUnsplash.accessKey(defaults: defaults) == "live-key", "a key set in defaults turns Unsplash on")
        defaults.set("   ", forKey: NoteUnsplash.accessKeyDefaultsKey)
        #expect(NoteUnsplash.accessKey(defaults: defaults) == nil, "a blank key keeps it off")
    }

    @Test func theCreditNamesAndLinksThePhotographer() throws {
        let credit = NoteUnsplash.credit(for: try photo())
        #expect(credit == NoteMediaCredit(name: "Jane \"JJ\" Doe", link: "https://unsplash.com/@jane"), "the credit names and links the photographer")
        #expect(credit.sentence == "Photo by Jane \"JJ\" Doe on Unsplash", "the credit reads like Unsplash asks")
        let profile = query(credit.profileURL)
        #expect(profile["utm_source"] == "parc" && profile["utm_medium"] == "referral", "profile links carry Unsplash's referral tags")
        #expect(credit.provider?.name == "Unsplash" && query(credit.provider?.url)["utm_medium"] == "referral", "Unsplash itself is linked with referral tags")
        let tagged = NoteMediaCredit.referral(URL(string: "https://unsplash.com/@jane?utm_source=other")!)
        #expect(query(tagged)["utm_source"] == "other" && query(tagged)["utm_medium"] == "referral", "existing tags are kept")
        let elsewhere = NoteMediaCredit(name: "Sam", link: "https://example.com/sam")
        #expect(elsewhere.provider == nil && elsewhere.sentence == "Photo by Sam", "other sites get a plain credit")
        #expect(elsewhere.profileURL?.absoluteString == "https://example.com/sam", "other links aren't tagged")
        #expect(NoteMediaCredit(name: "Sam", link: "javascript:alert(1)").profileURL == nil, "only web links are clickable")
        let blank: String? = "  "
        let nameless = NoteMediaCredit(name: blank, link: "https://unsplash.com/@x")
        #expect(nameless == nil, "a credit needs a name")
        #expect(NoteMediaCredit(name: " Sam ", link: " ").link == nil, "blank links are dropped")
    }

    @Test func theCreditRidesInTheBlocksParcCommentN() throws {
        var block = NoteBlock(.image)
        block.props.source = "Attachments/Photo%20by%20Jane.jpg"
        block.props.alt = "A mountain lake"
        block.props.credit = NoteMediaCredit(name: "Jane \"JJ\" <Doe> -->", link: "https://unsplash.com/@jane")
        let page = NotePage(blocks: [block, NoteBlock.paragraph(NoteText("After"))])
        let written = NoteMarkdown.serialize(page)
        #expect(written.contains("<!-- parc credit=\"Jane &quot;JJ&quot; &lt;Doe&gt; --&gt;\" credit-url=\"https://unsplash.com/@jane\" -->"), "the credit rides in the block's parc comment:\n\(written)")
        let read = NoteMarkdown.parse(written)
        #expect(read.blocks.first?.kind == .image, "the block stays an image")
        #expect(read.blocks.first?.props.credit == block.props.credit, "the credit survives a save and reload")
        #expect(NoteMarkdown.serialize(read) == written, "a second save writes the same bytes")

        let handWritten = "![](https://example.com/clip.mp4) <!-- parc credit=\"Sam\" -->\n"
        let video = NoteMarkdown.parse(handWritten)
        #expect(video.blocks.first?.kind == .video && video.blocks.first?.props.credit == NoteMediaCredit(name: "Sam"), "any media block can carry a credit")
        #expect(NoteMarkdown.serialize(video) == handWritten, "a credit without a link round-trips")
        let paragraph = NoteMarkdown.parse("Hello <!-- parc credit=\"Sam\" -->\n")
        #expect(paragraph.blocks.first?.props.credit == nil, "text blocks don't take credits")
    }

    @Test func coverCreditsSitRightUnderTheCoverN() throws {
        var page = NotePage(blocks: [NoteBlock.paragraph(NoteText("Body"))])
        page.settings.cover = NoteCover(source: "Attachments/Photo by Jane.jpg", position: 0.3,
                                        credit: NoteMediaCredit(name: "1999", link: "https://unsplash.com/@jane"))
        let written = NoteMarkdown.serialize(page)
        #expect(written.hasPrefix("---\ncover: Attachments/Photo by Jane.jpg\ncover-position: 0.3\ncover-credit: \"1999\"\ncover-credit-url: https://unsplash.com/@jane\n---\n"), "cover credits sit right under the cover:\n\(written)")
        let read = NoteMarkdown.parse(written)
        #expect(read.settings.cover == page.settings.cover, "the cover credit survives a save and reload")
        #expect(read.settings.properties.isEmpty, "the credit keys aren't page properties")
        #expect(NoteMarkdown.serialize(read) == written, "a second save writes the same bytes")

        let orphan = "---\ncover-credit: Jane\ncover-credit-url: https://unsplash.com/@jane\n---\n\nBody\n"
        let orphaned = NoteMarkdown.parse(orphan)
        #expect(orphaned.settings.cover == nil && orphaned.settings.properties.count == 2, "a credit without a cover is kept as it was")
        #expect(NoteMarkdown.serialize(orphaned) == orphan, "an orphaned credit round-trips")
        let linkOnly = "---\ncover: a.jpg\ncover-credit-url: https://unsplash.com/@jane\n---\n\nBody\n"
        let linked = NoteMarkdown.parse(linkOnly)
        #expect(linked.settings.cover?.credit == nil, "a link without a name isn't a credit")
        #expect(NoteMarkdown.serialize(linked) == linkOnly, "a lone credit link round-trips")
        #expect(NotePropertyEditing.reservedKeys.isSuperset(of: ["cover-credit", "cover-credit-url"]), "people can't make properties that shadow the credit")
    }

    @Test func exportedImagesCreditThePhotographerUnderTheCaptionN() throws {
        var block = NoteBlock(.image)
        block.props.source = "https://images.unsplash.com/photo.jpg"
        block.props.caption = NoteText("Morning")
        block.props.credit = NoteMediaCredit(name: "Jane & Co", link: "https://unsplash.com/@jane")
        let fragment = NotePageHTML.fragment([block])
        #expect(fragment.contains("<figcaption>Morning<br><span class=\"credit\">Photo by <a href=\"https://unsplash.com/@jane?utm_source=parc&amp;utm_medium=referral\">Jane &amp; Co</a> on <a href=\"https://unsplash.com/?utm_source=parc&amp;utm_medium=referral\">Unsplash</a></span></figcaption>"), "exported images credit the photographer under the caption:\n\(fragment)")
        block.props.caption = NoteText()
        #expect(NotePageHTML.fragment([block]).contains("<figcaption><span class=\"credit\">Photo by"), "the credit alone still makes a caption")

        var page = NotePage(blocks: [])
        page.settings.cover = NoteCover(source: "https://images.unsplash.com/cover.jpg", credit: NoteMediaCredit(name: "Jane", link: "https://unsplash.com/@jane"))
        let document = NotePageHTML.document(page, title: "Trip", assets: { _ in nil }, embedImages: false)
        #expect(document.contains("<div class=\"page-cover-frame\"><img class=\"page-cover\"") && document.contains("<p class=\"cover-credit\"><span class=\"credit\">Photo by <a"), "exported covers carry their credit")
        page.settings.cover?.credit = nil
        let plain = NotePageHTML.document(page, title: "Trip", assets: { _ in nil }, embedImages: false)
        #expect(!plain.contains("<div class=\"page-cover-frame\">") && plain.contains("<img class=\"page-cover\""), "covers without a credit export as before")
    }
}
