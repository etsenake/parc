import Foundation
import Testing
@testable import ParcCore

struct MarkdownRoundTripTestsGeneratedPageTests {
    private typealias MarkdownRandom = MarkdownRoundTripTestsSupport.MarkdownRandom
    private typealias MarkdownPageGenerator = MarkdownRoundTripTestsSupport.MarkdownPageGenerator

    private func anchored(_ blocks: [NoteBlock], _ random: inout MarkdownRandom) -> [NoteBlock] {
        blocks.map { original in
            var block = original
            if block.kind != .html, block.kind != .raw, block.kind != .column, random.chance(20) {
                block.props.anchor = random.pick(["k3x9qa", "intro", "step-2", "a_b", "Z9"]) + String(random.int(0...99))
                if block.kind == .code, block.props.fence == "    " { block.props.fence = nil }
            }
            block.children = anchored(block.children, &random)
            return block
        }
    }

    @Test(arguments: 0..<2000)
    func aGeneratedPageSurvivesAMarkdownRoundTrip(seed: Int) {
        var generator = MarkdownPageGenerator(random: MarkdownRandom(state: UInt64(seed) &* 2654435761 &+ 17))
        var page = NotePage(blocks: generator.blocks(depth: 0, count: generator.random.int(1...8), trailingEmpty: true))
        var anchors = MarkdownRandom(state: UInt64(seed) &* 40503 &+ 99)
        if anchors.chance(40) { page.blocks = anchored(page.blocks, &anchors) }
        if generator.random.chance(30) {
            page.settings.icon = generator.random.pick(["🍎", "Attachments/icon.png", "true", "- dash"])
            if generator.random.chance(50) { page.settings.cover = NoteCover(source: "cover.jpg", position: generator.random.chance(50) ? 0.5 : 0.125) }
            page.settings.font = generator.random.pick(NotePageFont.allCases)
            page.settings.smallText = generator.random.chance(30)
            page.settings.fullWidth = generator.random.chance(30)
            page.settings.locked = generator.random.chance(30)
            page.settings.properties = [NotePageProperty(key: "title", value: .text(generator.plainString(maxWords: 3))),
                                        NotePageProperty(key: "tags", value: .list(["a", generator.plainString(maxWords: 2)]))]
        }
        #expect(NoteMarkdownCheck.checkModelRoundTrip(page, "seed \(seed)"))
    }
}
