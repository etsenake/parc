import Foundation
import Testing
@testable import ParcCore

struct NoteMarkdownHostileInputTests {
    private func depth(_ blocks: [NoteBlock]) -> Int {
        1 + (blocks.map { depth($0.children) }.max() ?? 0)
    }

    @Test func tenThousandNestedTogglesReadWithoutRunningOutOfStack() {
        let source = String(repeating: "<details>\n<summary>x</summary>\n\n", count: 10_000) + "bottom\n\n"
            + String(repeating: "</details>\n\n", count: 10_000)
        let (text, levels, written) = runOnLargeStack { () -> (String, Int, String) in
            let page = NoteMarkdown.parse(source)
            return (page.plainText, depth(page.blocks), NoteMarkdown.serialize(page))
        }
        #expect(text.contains("bottom"))
        #expect(levels <= 200)
        #expect(written.contains("bottom"))
    }

    @Test func tenThousandNestedSyncedBlocksReadWithoutRunningOutOfStack() {
        let source = String(repeating: "<!-- parc synced -->\n\n", count: 10_000) + "bottom\n\n"
            + String(repeating: "<!-- parc /synced -->\n\n", count: 10_000)
        let (text, levels, written) = runOnLargeStack { () -> (String, Int, String) in
            let page = NoteMarkdown.parse(source)
            return (page.plainText, depth(page.blocks), NoteMarkdown.serialize(page))
        }
        #expect(text.contains("bottom"))
        #expect(levels <= 200)
        #expect(written.contains("bottom"))
    }

    @Test func tenThousandNestedButtonsReadWithoutRunningOutOfStack() {
        let source = String(repeating: "<details><summary>go <!-- parc button --></summary>\n\n", count: 10_000) + "bottom\n\n"
            + String(repeating: "</details>\n\n", count: 10_000)
        #expect(runOnLargeStack { depth(NoteMarkdown.parse(source).blocks) } <= 400)
    }

    @Test func aBlockSizeThatIsNotANumberIsNotKept() throws {
        let page = NoteMarkdown.parse("![a](picture.png) <!-- parc width=\"nan\" height=\"inf\" -->\n")
        let image = try #require(page.blocks.first)
        #expect(image.kind == .image)
        #expect(image.props.width == nil)
        #expect(image.props.height == nil)
    }

    @Test func tableColumnWidthsThatAreNotNumbersAreDropped() throws {
        let page = NoteMarkdown.parse("| a | b |\n| - | - |\n| 1 | 2 |\n<!-- parc widths=\"inf,1e999\" -->\n")
        let table = try #require(page.blocks.first?.props.table)
        #expect(table.columnWidths.compactMap { $0 }.allSatisfy { $0.isFinite })
    }
}
