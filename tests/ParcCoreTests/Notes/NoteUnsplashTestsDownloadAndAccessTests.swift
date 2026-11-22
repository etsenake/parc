import Foundation
import ParcTestSupport
import Testing
@testable import ParcCore

struct NoteUnsplashTestsDownloadAndAccessTests {
    struct ImageCase: Sendable, CustomTestStringConvertible {
        let testDescription: String
        let data: Data
        let fileExtension: String?

        init(_ label: String, _ data: Data, _ fileExtension: String?) {
            testDescription = label
            self.data = data
            self.fileExtension = fileExtension
        }
    }

    @Test(arguments: [
        ImageCase("JPEG downloads save as .jpg", Data([0xFF, 0xD8, 0xFF, 0xE0, 0, 0x10]), "jpg"),
        ImageCase("PNG downloads save as .png", Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 0]), "png"),
        ImageCase("WebP downloads save as .webp", Data("RIFF\u{0}\u{0}\u{0}\u{0}WEBP".utf8), "webp"),
        ImageCase("AVIF downloads save as .avif", Data("\u{0}\u{0}\u{0}\u{1C}ftypavif".utf8), "avif"),
        ImageCase("an HTML error page isn't an image", Data("<html>oops</html>".utf8), nil),
    ])
    func downloadedImageBytesDetermineTheFileExtension(fixture: ImageCase) {
        #expect(NoteUnsplash.fileExtension(for: fixture.data) == fixture.fileExtension)
    }

    struct ErrorCase: Sendable, CustomTestStringConvertible {
        let testDescription: String
        let status: Int
        let remaining: String?
        let body: Data?
        let expected: NoteUnsplashError?

        init(_ label: String, _ status: Int, _ remaining: String?, _ body: Data?, _ expected: NoteUnsplashError?) {
            testDescription = label
            self.status = status
            self.remaining = remaining
            self.body = body
            self.expected = expected
        }
    }

    @Test(arguments: [
        ErrorCase("success is no error", 200, nil, nil, nil),
        ErrorCase("401 means a bad key", 401, nil, nil, .unauthorized),
        ErrorCase("403 with nothing left is the rate limit", 403, "0", nil, .rateLimited),
        ErrorCase("the rate-limit body is recognised", 403, "12", Data("Rate Limit Exceeded".utf8), .rateLimited),
        ErrorCase("other 403s are about the key", 403, "12", nil, .unauthorized),
        ErrorCase("server trouble keeps its status", 503, nil, nil, .unavailable(503)),
    ])
    func unsplashResponsesMapToTheExpectedError(fixture: ErrorCase) {
        #expect(NoteUnsplash.error(status: fixture.status, remaining: fixture.remaining, body: fixture.body) == fixture.expected)
    }

    @Test
    func parcShipsWithoutABuiltInAccessKey() {
        #expect(NoteUnsplash.builtInAccessKey.isEmpty, "Parc ships without a baked-in key")
    }

    @Test
    func unsplashIsOffWithoutAnAccessKey() throws {
        let defaults = try #require(TestDefaults("parc.tests.unsplash."), "a scratch defaults suite opens")
        #expect(NoteUnsplash.accessKey(defaults: defaults) == nil, "no key means no Unsplash tab")
    }

    @Test
    func aSavedAccessKeyIsTrimmed() throws {
        let defaults = try #require(TestDefaults("parc.tests.unsplash."), "a scratch defaults suite opens")
        _ = NoteUnsplash.accessKey(defaults: defaults)
        defaults.set("  live-key \n", forKey: NoteUnsplash.accessKeyDefaultsKey)
        #expect(NoteUnsplash.accessKey(defaults: defaults) == "live-key", "a key set in defaults turns Unsplash on")
    }

    @Test
    func aWhitespaceOnlyAccessKeyKeepsUnsplashOff() throws {
        let defaults = try #require(TestDefaults("parc.tests.unsplash."), "a scratch defaults suite opens")
        defaults.set("  live-key \n", forKey: NoteUnsplash.accessKeyDefaultsKey)
        _ = NoteUnsplash.accessKey(defaults: defaults)
        defaults.set("   ", forKey: NoteUnsplash.accessKeyDefaultsKey)
        #expect(NoteUnsplash.accessKey(defaults: defaults) == nil, "a blank key keeps it off")
    }
}
