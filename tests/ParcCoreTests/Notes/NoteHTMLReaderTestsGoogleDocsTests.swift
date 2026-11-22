import Foundation
import Testing
@testable import ParcCore

struct NoteHTMLReaderTestsGoogleDocsTests {
    private typealias Fixture = NoteHTMLReaderTestsSupport

    private func importedBlocks() -> [NoteBlock] {
        let span = "font-size:11pt;font-family:Arial,sans-serif;color:#000000;background-color:transparent;font-weight:400;font-style:normal;font-variant:normal;text-decoration:none;vertical-align:baseline;white-space:pre;white-space:pre-wrap;"
        let html = """
        <meta charset="utf-8"><b style="font-weight:normal;" id="docs-internal-guid-4f1c2a9e-7fff-1b2c-3d4e-5f6a7b8c9d0e">\
        <h1 dir="ltr" style="line-height:1.38;margin-top:20pt;margin-bottom:6pt;"><span style="\(span)font-size:20pt;">Launch plan</span></h1>\
        <p dir="ltr" style="line-height:1.38;margin-top:0pt;margin-bottom:0pt;"><span style="\(span)">We ship on </span>\
        <span style="\(span)font-weight:700;">Friday</span><span style="\(span)">, with </span>\
        <span style="\(span)font-style:italic;">care</span><span style="\(span)">. Run </span>\
        <span style="\(span)font-family:'Courier New',monospace;">make ship</span><span style="\(span)"> or the </span>\
        <span style="\(span)color:#ff0000;">red alert</span><span style="\(span)"> and </span>\
        <span style="\(span)background-color:#ffff00;">highlighted</span><span style="\(span)"> bits, </span>\
        <span style="\(span)text-decoration:line-through;">struck</span><span style="\(span)">, </span>\
        <span style="\(span)text-decoration:underline;">under</span><span style="\(span)"> and </span>\
        <a href="https://www.google.com/url?q=https://example.com/docs&amp;sa=D&amp;source=editors" style="text-decoration:none;">\
        <span style="\(span)color:#1155cc;text-decoration:underline;-webkit-text-decoration-skip:none;">the docs</span></a>\
        <span style="\(span)">.</span></p><br>\
        <ul style="margin-top:0;margin-bottom:0;padding-inline-start:48px;"><li dir="ltr" style="list-style-type:disc;\(span)" aria-level="1">\
        <p dir="ltr" style="line-height:1.38;margin-top:0pt;margin-bottom:0pt;" role="presentation"><span style="\(span)">Design review</span></p></li>\
        <ul style="margin-top:0;margin-bottom:0;padding-inline-start:48px;"><li dir="ltr" style="list-style-type:circle;\(span)" aria-level="2">\
        <p dir="ltr" role="presentation"><span style="\(span)">Icons</span></p></li></ul>\
        <li dir="ltr" style="list-style-type:disc;\(span)" aria-level="1"><p dir="ltr" role="presentation"><span style="\(span)">QA pass</span></p></li></ul><br>\
        <ol style="margin-top:0;margin-bottom:0;"><li dir="ltr" style="list-style-type:decimal;\(span)" aria-level="1">\
        <p dir="ltr" role="presentation"><span style="\(span)">Write notes</span></p></li>\
        <li dir="ltr" style="list-style-type:decimal;\(span)" aria-level="1"><p dir="ltr" role="presentation"><span style="\(span)">Tag release</span></p></li></ol>\
        <ul style="margin-top:0;margin-bottom:0;"><li dir="ltr" role="checkbox" aria-checked="true" style="list-style-type:none;\(span)" aria-level="1">\
        <img src="https://lh7-rt.googleusercontent.com/docsz/AD_4nX-checked" width="17.6px" height="17.6px" alt="checked" aria-roledescription="checkbox" style="margin-right:3px;">\
        <p dir="ltr" style="display:inline-block;margin-top:0pt;margin-bottom:0pt;" role="presentation"><span style="\(span)text-decoration:line-through;">Book the room</span></p></li>\
        <li dir="ltr" role="checkbox" aria-checked="false" style="list-style-type:none;\(span)" aria-level="1">\
        <img src="https://lh7-rt.googleusercontent.com/docsz/AD_4nX-unchecked" width="17.6px" height="17.6px" alt="unchecked" aria-roledescription="checkbox">\
        <p dir="ltr" style="display:inline-block;" role="presentation"><span style="\(span)">Order cake</span></p></li></ul>\
        <div dir="ltr" style="margin-left:0pt;" align="left"><table style="border:none;border-collapse:collapse;"><colgroup><col width="200"><col width="200"></colgroup><tbody>\
        <tr style="height:0pt"><td style="border-left:solid #000000 1pt;border-right:solid #000000 1pt;vertical-align:top;padding:5pt 5pt 5pt 5pt;overflow:hidden;overflow-wrap:break-word;">\
        <p dir="ltr" style="line-height:1.2;margin-top:0pt;margin-bottom:0pt;"><span style="\(span)font-weight:700;">Owner</span></p></td>\
        <td style="vertical-align:top;padding:5pt;"><p dir="ltr"><span style="\(span)font-weight:700;">Task</span></p></td></tr>\
        <tr style="height:0pt"><td style="vertical-align:top;"><p dir="ltr"><span style="\(span)">Sam</span></p></td>\
        <td style="vertical-align:top;"><p dir="ltr"><span style="\(span)">Slides</span></p></td></tr></tbody></table></div>\
        <hr><p dir="ltr"><span style="\(span)">H</span><span style="\(span)vertical-align:sub;font-size:0.6em;">2</span><span style="\(span)">O and x</span>\
        <span style="\(span)vertical-align:super;">2</span></p></b><br class="Apple-interchange-newline">
        """
        return Fixture.read(html)
    }

    private func blocks() throws -> [NoteBlock] {
        let blocks = importedBlocks()
        try #require(blocks.count == 11)
        return blocks
    }

    @Test
    func theImportKeepsTheExpectedBlockOrder() {
        let blocks = importedBlocks()
        Fixture.shape(blocks, ["heading", "paragraph", "bulletedItem", "bulletedItem", "numberedItem", "numberedItem", "todo", "todo",
                       "table", "divider", "paragraph"], "Google Docs")
    }

    @Test
    func aDocsHeadingKeepsItsLevelWithoutBold() throws {
        let blocks = try blocks()
        #expect(blocks[0].text.string == "Launch plan" && blocks[0].props.level == 1, "Docs heading")
        #expect(blocks[0].text.runs().allSatisfy { !$0.marks.bold }, "Docs heading carries no bold")
    }

    @Test
    func docsParagraphsKeepTheirText() throws {
        let blocks = try blocks()
        let body = blocks[1].text
        #expect(body.plainText == "We ship on Friday, with care. Run make ship or the red alert and highlighted bits, struck, under and the docs.", "Docs paragraph text: \(body.plainText.debugDescription)")
    }

    @Test
    func theDocsGuidWrapperDoesNotBoldTheParagraph() throws {
        let blocks = try blocks()
        let body = blocks[1].text
        #expect(Fixture.marks("We ship on ", body)?.isPlain == true, "the guid wrapper's <b> does not bold everything")
    }

    @Test
    func docsFontWeightBecomesBold() throws {
        let blocks = try blocks()
        let body = blocks[1].text
        #expect(Fixture.marks("Friday", body)?.bold == true, "font-weight 700 is bold")
    }

    @Test
    func docsFontStyleBecomesItalic() throws {
        let blocks = try blocks()
        let body = blocks[1].text
        #expect(Fixture.marks("care", body)?.italic == true, "font-style italic")
    }

    @Test
    func docsCourierNewBecomesCode() throws {
        let blocks = try blocks()
        let body = blocks[1].text
        #expect(Fixture.marks("make ship", body)?.code == true, "Courier New becomes code")
    }

    @Test
    func docsRedBecomesRedInk() throws {
        let blocks = try blocks()
        let body = blocks[1].text
        #expect(Fixture.marks("red alert", body)?.color == .text(.red), "#ff0000 is red ink")
    }

    @Test
    func docsYellowBecomesAYellowHighlight() throws {
        let blocks = try blocks()
        let body = blocks[1].text
        #expect(Fixture.marks("highlighted", body)?.color == .background(.yellow), "#ffff00 background is a yellow highlight")
    }

    @Test
    func docsLineThroughBecomesStrike() throws {
        let blocks = try blocks()
        let body = blocks[1].text
        #expect(Fixture.marks("struck", body)?.strikethrough == true, "line-through")
    }

    @Test
    func docsUnderlineBecomesAnUnderlineMark() throws {
        let blocks = try blocks()
        let body = blocks[1].text
        #expect(Fixture.marks("under", body)?.underline == true, "underline")
    }

    @Test
    func docsRedirectLinksUnwrap() throws {
        let blocks = try blocks()
        let body = blocks[1].text
        let link = Fixture.marks("the docs", body)
        #expect(link?.link == "https://example.com/docs", "Google redirect links unwrap: \(String(describing: link?.link))")
    }

    @Test
    func docsLinkDecorationStaysOutOfMarks() throws {
        let blocks = try blocks()
        let body = blocks[1].text
        let link = Fixture.marks("the docs", body)
        #expect(link?.underline == false && link?.color == nil, "link styling stays out of the marks")
    }

    @Test
    func docsSublistsNestUnderThePreviousItem() throws {
        let blocks = try blocks()
        #expect(blocks[2].text.string == "Design review" && blocks[2].children.map(\.text.string) == ["Icons"], "a list inside a list nests under the previous item")
        #expect(blocks[3].text.string == "QA pass", "list continues after the nested list")
    }

    @Test
    func docsNumberedItemsKeepTheirOrder() throws {
        let blocks = try blocks()
        #expect(blocks[4].text.string == "Write notes" && blocks[5].text.string == "Tag release", "numbered items")
    }

    @Test
    func docsCheckedItemsDropAutomaticStrike() throws {
        let blocks = try blocks()
        #expect(blocks[6].props.checked && blocks[6].text.string == "Book the room", "checked checklist item")
        #expect(!blocks[6].text.runs().contains { $0.marks.strikethrough }, "checked items drop the strike Docs adds")
    }

    @Test
    func docsUncheckedItemsStayUnchecked() throws {
        let blocks = try blocks()
        #expect(!blocks[7].props.checked && blocks[7].text.string == "Order cake", "unchecked checklist item")
    }

    @Test
    func docsTablesKeepTheirCellText() throws {
        let blocks = try blocks()
        let table = try #require(blocks[8].props.table)
        #expect(table.rows.map { $0.map(\.string) } == [["Owner", "Task"], ["Sam", "Slides"]], "Docs table cells")
    }

    @Test
    func aBoldDocsTableRowBecomesAnUnboldedHeaderRow() throws {
        let blocks = try blocks()
        let table = try #require(blocks[8].props.table)
        #expect(table.headerRow && !table.headerColumn, "a bold first row becomes the header")
        #expect(table.rows[0].allSatisfy { cell in cell.runs().allSatisfy { !$0.marks.bold } }, "header cells lose the redundant bold")
    }

    @Test
    func docsSuperAndSubscriptsUseUnicodeForms() throws {
        let blocks = try blocks()
        #expect(blocks[10].text.string == "H₂O and x²", "sub and super scripts use Unicode forms: \(blocks[10].text.string)")
    }
}
