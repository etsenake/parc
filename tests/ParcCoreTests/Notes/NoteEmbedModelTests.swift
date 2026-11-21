import Foundation
import Testing
@testable import ParcCore

@MainActor struct NoteEmbedModelTests {
    @Test func noHeightMeansTheDefault() {
        #expect(NoteEmbedSizing.clamped(nil) == NoteEmbedSizing.defaultHeight, "no height means the default")
        #expect(NoteEmbedSizing.clamped(.nan) == NoteEmbedSizing.defaultHeight && NoteEmbedSizing.clamped(.infinity) == NoteEmbedSizing.defaultHeight, "broken numbers fall back to the default")
        #expect(NoteEmbedSizing.clamped(10) == NoteEmbedSizing.minimumHeight, "tiny heights clamp up")
        #expect(NoteEmbedSizing.clamped(99_999) == NoteEmbedSizing.maximumHeight, "huge heights clamp down")
        #expect(NoteEmbedSizing.clamped(512.4) == 512, "heights round to whole points")
        #expect(NoteEmbedSizing.resized(from: nil, by: 80) == NoteEmbedSizing.defaultHeight + 80, "dragging grows from the default")
        #expect(NoteEmbedSizing.resized(from: 300, by: -1000) == NoteEmbedSizing.minimumHeight, "dragging can't squash past the floor")
        #expect(NoteEmbedSizing.resized(from: 300, by: .nan) == 300, "a broken drag delta changes nothing")
        #expect(NoteEmbedSizing.stored(NoteEmbedSizing.defaultHeight) == nil, "the default height isn't written to the file")
        #expect(NoteEmbedSizing.stored(612.6) == 613, "custom heights are stored clamped and rounded")
        var props = NoteBlockProps()
        props.height = 2
        #expect(NoteEmbedSizing.height(of: props) == NoteEmbedSizing.minimumHeight, "stored heights clamp when read")
    }

    @Test func youTubeWatchLinksPlayInTheEmbedPlayer() {
        func live(_ string: String) -> String { NoteEmbedAddress.liveURL(for: URL(string: string)!).absoluteString }
        #expect(live("https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=42s") == "https://www.youtube.com/embed/dQw4w9WgXcQ?start=42", "YouTube watch links play in the embed player from their timestamp")
        #expect(live("https://youtu.be/dQw4w9WgXcQ") == "https://www.youtube.com/embed/dQw4w9WgXcQ", "short YouTube links use the player")
        #expect(live("https://www.youtube.com/shorts/abc_DEF-123") == "https://www.youtube.com/embed/abc_DEF-123", "Shorts use the player")
        #expect(live("https://www.youtube.com/embed/xyz") == "https://www.youtube.com/embed/xyz", "player links stay put")
        #expect(live("https://vimeo.com/76979871") == "https://player.vimeo.com/video/76979871", "Vimeo uses its player")
        #expect(live("https://www.loom.com/share/abc123") == "https://www.loom.com/embed/abc123", "Loom uses its embed")
        #expect(live("https://open.spotify.com/track/4uLU6hMCjMI75M1A2tKUQC") == "https://open.spotify.com/embed/track/4uLU6hMCjMI75M1A2tKUQC", "Spotify uses its embed player")
        #expect(live("https://www.figma.com/file/abc/Design").hasPrefix("https://www.figma.com/embed?embed_host=parc&url=https"), "Figma files open in Figma's embed viewer")
        #expect(live("https://example.com/page?x=1") == "https://example.com/page?x=1", "other pages load as they are")
        #expect(live("https://www.youtube.com/watch?v=bad%20id") == "https://www.youtube.com/watch?v=bad%20id", "odd ids keep the original page")
        #expect(NoteEmbedAddress.embedderReferrer(appID: "Com.Example.Parc")?.absoluteString == "https://com.example.parc", "embeds name the app as their referrer, as YouTube's player requires")
        #expect(NoteEmbedAddress.embedderReferrer(appID: nil) == nil && NoteEmbedAddress.embedderReferrer(appID: "") == nil, "no app identifier means no referrer")
        #expect(NoteEmbedAddress.embedderReferrer(appID: "bad id/x") == nil && NoteEmbedAddress.embedderReferrer(appID: ".parc") == nil, "identifiers that aren't host names send no referrer")
    }

    @Test func theCommentKeepsTheEmbedKind() {
        let source = "![](https://example.com/widget) <!-- parc embed height=\"640\" -->\n"
        let page = NoteMarkdown.parse(source)
        #expect(page.blocks.count == 1 && page.blocks[0].kind == .embed, "the comment keeps the embed kind")
        #expect(page.blocks[0].props.height == 640, "the height comes back from the parc comment")
        let written = NoteMarkdown.serialize(page)
        #expect(written.contains("height=\"640\""), "the height is written back")
        #expect(NoteMarkdown.parse(written).blocks[0].props == page.blocks[0].props, "props survive a second round trip")
        var plain = page
        plain.blocks[0].props.height = nil
        #expect(!NoteMarkdown.serialize(plain).contains("height"), "an embed at the default height writes no height")
        let video = NoteMarkdown.parse("![](https://www.youtube.com/watch?v=dQw4w9WgXcQ) <!-- parc height=\"300\" -->\n")
        #expect(video.blocks[0].kind == .embed && video.blocks[0].props.height == 300, "inferred embeds read their height too")
        #expect(NoteMarkdown.serialize(video).contains("height=\"300\""), "and write it back")
    }
}
