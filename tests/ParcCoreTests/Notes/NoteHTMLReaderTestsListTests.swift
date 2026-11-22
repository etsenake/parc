import Foundation
import Testing
@testable import ParcCore

struct NoteHTMLReaderTestsListTests {
    private typealias Fixture = NoteHTMLReaderTestsSupport

    private func importedBlocks() -> [NoteBlock] {
        let html = """
        <ol start="5"><li>Five<ol type="a"><li>Five a</li><li>Five b<ul><li>deep</li></ul></li></ol></li><li><p>Six</p><p>Six more</p></li></ol>
        <ul><li></li><li>[x] Done markdown style</li><li>[ ] Not yet</li></ul>
        <p>Text <ul><li>breaks the paragraph</li></ul> after</p>
        <ul data-type="taskList"><li data-checked="true">Tiptap done</li></ul>
        <ol><li data-list="bullet">Quill bullet</li><li data-list="checked">Quill done</li></ol>
        <h2>Heading <ul><li>can't hold lists</li></ul></h2>
        """
        return Fixture.read(html)
    }

    private func blocks() throws -> [NoteBlock] {
        let blocks = importedBlocks()
        try #require(blocks.count == 12)
        return blocks
    }

    @Test
    func theImportKeepsTheExpectedBlockOrder() {
        let blocks = importedBlocks()
        Fixture.shape(blocks, ["numberedItem", "numberedItem", "todo", "todo", "paragraph", "bulletedItem", "paragraph", "todo",
                       "bulletedItem", "todo", "heading", "bulletedItem"], "Nested lists")
    }

    @Test
    func nestedOrderedListsKeepTheirStartAndChildren() throws {
        let blocks = try blocks()
        #expect(blocks[0].props.listStart == 5 && blocks[0].children.map(\.text.string) == ["Five a", "Five b"], "nested ordered")
        #expect(blocks[0].children.last?.children.first?.text.string == "deep", "three levels deep")
    }

    @Test
    func extraListItemParagraphsBecomeChildren() throws {
        let blocks = try blocks()
        #expect(blocks[1].text.string == "Six" && blocks[1].children.map(\.text.string) == ["Six more"], "extra paragraphs become children")
    }

    @Test
    func aCheckedMarkdownPrefixBecomesACheckedTodo() throws {
        let blocks = try blocks()
        #expect(blocks[2].props.checked && blocks[2].text.string == "Done markdown style", "[x] prefix")
    }

    @Test
    func anUncheckedMarkdownPrefixBecomesAnOpenTodo() throws {
        let blocks = try blocks()
        #expect(!blocks[3].props.checked && blocks[3].text.string == "Not yet", "[ ] prefix")
    }

    @Test
    func listsSplitParagraphs() throws {
        let blocks = try blocks()
        #expect(blocks[4].text.string == "Text" && blocks[6].text.string == "after", "lists split paragraphs")
    }

    @Test
    func tiptapAndQuillMarkersBecomeListItems() throws {
        let blocks = try blocks()
        #expect(blocks[7].props.checked && blocks[8].text.string == "Quill bullet" && blocks[9].props.checked, "editor checklist flavours")
    }

    @Test
    func headingsNeverTakeListChildren() throws {
        let blocks = try blocks()
        #expect(blocks[10].text.string == "Heading" && blocks[10].children.isEmpty, "headings never take children")
    }

    private static let blockIndices = 0..<12

    @Test(arguments: blockIndices)
    func onlyBlocksThatAcceptChildrenHaveThem(index: Int) throws {
        let block = try blocks()[index]
        #expect(block.acceptsChildren || block.children.isEmpty, "children only where accepted")
    }
}
