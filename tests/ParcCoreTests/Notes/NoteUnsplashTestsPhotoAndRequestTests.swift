import Foundation
import Testing
@testable import ParcCore

struct NoteUnsplashTestsPhotoAndRequestTests {
    private typealias Fixture = NoteUnsplashTestsSupport

    @Test
    func thePhotographersNameComesFromTheUser() throws {
        let photo = try Fixture.photo()
        #expect(photo.photographer == "Jane \"JJ\" Doe", "the photographer's name comes from the user")
    }

    @Test
    func photoAspectRatioFollowsItsPixelSize() throws {
        let photo = try Fixture.photo()
        #expect(abs(photo.aspectRatio - 1.5) < 0.0001, "the aspect ratio follows the pixel size")
    }

    @Test
    func photoColorBecomesThePlaceholder() throws {
        let photo = try Fixture.photo()
        #expect(photo.placeholderColor.map { abs($0.red - 0x26 / 255.0) < 0.001 && abs($0.blue - 0x8c / 255.0) < 0.001 } == true, "the API's colour becomes the tile's placeholder")
    }

    @Test
    func altTextIsCapitalizedAndFitsOnOneLine() throws {
        let photo = try Fixture.photo()
        #expect(NoteUnsplash.altText(for: photo) == "A mountain lake at sunrise", "alt text is one tidy, capitalised line")
    }

    @Test
    func attachmentNamesCreditThePhotographer() throws {
        let photo = try Fixture.photo()
        #expect(NoteUnsplash.suggestedName(for: photo) == "Photo by Jane \"JJ\" Doe", "attachments are named after the photographer")
    }

    @Test
    func aPhotoQueryUsesTheSearchEndpointAndRequestedParameters() {
        let search = NoteUnsplash.listRequest(query: "  lake  ", page: 2, orientation: .landscape, key: "abc")
        #expect(search.url?.path == "/search/photos", "a query searches photos")
        let searchQuery = Fixture.query(search.url)
        #expect(searchQuery["query"] == "lake" && searchQuery["page"] == "2" && searchQuery["per_page"] == "30", "search sends the trimmed query and page")
        #expect(searchQuery["orientation"] == "landscape" && searchQuery["content_filter"] == "high", "cover searches ask for safe landscape photos")
    }

    @Test
    func photoRequestsSendTheAccessKeyAndPinTheAPIVersion() {
        let search = NoteUnsplash.listRequest(query: "  lake  ", page: 2, orientation: .landscape, key: "abc")
        #expect(search.value(forHTTPHeaderField: "Authorization") == "Client-ID abc", "requests carry the access key")
        #expect(search.value(forHTTPHeaderField: "Accept-Version") == "v1", "requests pin the API version")
    }

    @Test
    func aBlankQueryUsesTheEditorialFeedWithoutAnOrientation() {
        let feed = NoteUnsplash.listRequest(query: " ", page: 0, orientation: .landscape, key: "abc")
        #expect(feed.url?.path == "/photos" && Fixture.query(feed.url)["page"] == "1", "an empty query shows the editorial feed from page one")
        #expect(Fixture.query(feed.url)["orientation"] == nil, "the feed doesn't take an orientation")
    }

    @Test
    func downloadTrackingUsesTheAuthorizedUnsplashEndpoint() throws {
        let photo = try Fixture.photo()
        let tracking = NoteUnsplash.trackingRequest(for: photo, key: "abc")
        #expect(tracking?.url?.absoluteString == "https://api.unsplash.com/photos/Dwu85P9SOIk/download?ixid=M3w1", "downloads ping the tracking endpoint")
        #expect(tracking?.value(forHTTPHeaderField: "Authorization") == "Client-ID abc", "the tracking ping is authorised")
    }

    @Test
    func downloadTrackingNeverSendsTheKeyToAnotherHost() throws {
        let photo = try Fixture.photo()
        var stray = photo
        stray.links.downloadLocation = "https://example.com/steal"
        #expect(NoteUnsplash.trackingRequest(for: stray, key: "abc") == nil, "the key never goes anywhere but the Unsplash API")
    }

    @Test
    func theDownloadUsesASizedJPEGOfTheRawPhoto() throws {
        let photo = try Fixture.photo()
        let image = Fixture.query(NoteUnsplash.imageURL(for: photo, width: NoteUnsplash.coverWidth))
        #expect(image["w"] == "2400" && image["fm"] == "jpg" && image["fit"] == "max" && image["ixid"] == "M3w1", "the download is a sized JPEG of the raw photo")
    }

    @Test
    func aThumbnailHotlinksASmallRendition() throws {
        let photo = try Fixture.photo()
        let thumb = NoteUnsplash.thumbnailURL(for: photo, width: 400)
        #expect(Fixture.query(thumb)["w"] == "400" && thumb?.host == "images.unsplash.com", "thumbnails hotlink a small rendition")
    }

    @Test
    func theFullRenditionIsUsedWhenTheRawURLIsMissing() throws {
        let photo = try Fixture.photo()
        var noRaw = photo
        noRaw.urls.raw = nil
        #expect(NoteUnsplash.imageURL(for: noRaw, width: 2000)?.absoluteString == photo.urls.full, "without a raw URL the full rendition is used")
    }

    @Test
    func searchPaginationEndsAtTheLastPage() {
        let searchJSON = "{\"total\": 61, \"total_pages\": 3, \"results\": [" + Fixture.photoJSON + "]}"
        guard let first = try? NoteUnsplash.page(from: Data(searchJSON.utf8), searching: true, page: 1),
              let last = try? NoteUnsplash.page(from: Data(searchJSON.utf8), searching: true, page: 3) else { Issue.record("search results decode"); return }
        #expect(first.photos.count == 1 && first.hasMore && !last.hasMore, "search pages until the last one")
    }

    @Test
    func aShortEditorialFeedPageEndsTheFeed() throws {
        let feedPage = try #require(try? NoteUnsplash.page(from: Data(("[" + Fixture.photoJSON + "]").utf8), searching: false, page: 1), "the feed decodes")
        #expect(feedPage.photos.count == 1 && !feedPage.hasMore, "a short feed page is the end")
    }

    @Test
    func anInvalidSearchReplyReportsAnUnreadableResponse() {
        do {
            _ = try NoteUnsplash.page(from: Data("{\"errors\":[\"nope\"]}".utf8), searching: true, page: 1)
            Issue.record("garbage doesn't decode")
        } catch {
            #expect(error as? NoteUnsplashError == .unreadable, "garbage reports an unreadable reply")
        }
    }

    @Test
    func duplicatePhotosAcrossPagesAppearOnce() throws {
        let photo = try Fixture.photo()
        #expect(NoteUnsplash.merge([photo], [photo]).count == 1, "repeated photos across pages show once")
    }
}
