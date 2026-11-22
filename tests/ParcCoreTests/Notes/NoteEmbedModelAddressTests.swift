import Foundation
import Testing
@testable import ParcCore

struct NoteEmbedModelAddressTests {
    struct Address: Sendable, CustomTestStringConvertible {
        let testDescription: String
        let input: String
        let expected: String
    }

    private static let addresses = [
        Address(testDescription: "YouTube watch links play in the embed player from their timestamp", input: "https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=42s", expected: "https://www.youtube.com/embed/dQw4w9WgXcQ?start=42"),
        Address(testDescription: "short YouTube links use the player", input: "https://youtu.be/dQw4w9WgXcQ", expected: "https://www.youtube.com/embed/dQw4w9WgXcQ"),
        Address(testDescription: "Shorts use the player", input: "https://www.youtube.com/shorts/abc_DEF-123", expected: "https://www.youtube.com/embed/abc_DEF-123"),
        Address(testDescription: "player links stay put", input: "https://www.youtube.com/embed/xyz", expected: "https://www.youtube.com/embed/xyz"),
        Address(testDescription: "Vimeo uses its player", input: "https://vimeo.com/76979871", expected: "https://player.vimeo.com/video/76979871"),
        Address(testDescription: "Loom uses its embed", input: "https://www.loom.com/share/abc123", expected: "https://www.loom.com/embed/abc123"),
        Address(testDescription: "Spotify uses its embed player", input: "https://open.spotify.com/track/4uLU6hMCjMI75M1A2tKUQC", expected: "https://open.spotify.com/embed/track/4uLU6hMCjMI75M1A2tKUQC"),
        Address(testDescription: "other pages load as they are", input: "https://example.com/page?x=1", expected: "https://example.com/page?x=1"),
        Address(testDescription: "odd ids keep the original page", input: "https://www.youtube.com/watch?v=bad%20id", expected: "https://www.youtube.com/watch?v=bad%20id"),
    ]

    struct UnusableIdentifier: Sendable, CustomTestStringConvertible {
        let testDescription: String
        let id: String?
    }

    private static let unusableIdentifiers = [
        UnusableIdentifier(testDescription: "missing", id: nil),
        UnusableIdentifier(testDescription: "empty", id: ""),
        UnusableIdentifier(testDescription: "spaces and slash", id: "bad id/x"),
        UnusableIdentifier(testDescription: "leading dot", id: ".parc"),
    ]

    @Test(arguments: addresses) func embedAddressesResolveToTheExpectedLiveURL(_ example: Address) throws {
        let url = try #require(URL(string: example.input))
        #expect(NoteEmbedAddress.liveURL(for: url).absoluteString == example.expected)
    }

    @Test func figmaFilesUseTheEmbedViewer() {
        func live(_ string: String) -> String { NoteEmbedAddress.liveURL(for: URL(string: string)!).absoluteString }
        #expect(live("https://www.figma.com/file/abc/Design").hasPrefix("https://www.figma.com/embed?embed_host=parc&url=https"), "Figma files open in Figma's embed viewer")
    }

    @Test func embedReferrersUseTheLowercasedAppIdentifier() {
        #expect(NoteEmbedAddress.embedderReferrer(appID: "Com.Example.Parc")?.absoluteString == "https://com.example.parc", "embeds name the app as their referrer, as YouTube's player requires")
    }

    @Test(arguments: unusableIdentifiers) func invalidAppIdentifiersDoNotProduceReferrers(_ example: UnusableIdentifier) {
        #expect(NoteEmbedAddress.embedderReferrer(appID: example.id) == nil)
    }
}
