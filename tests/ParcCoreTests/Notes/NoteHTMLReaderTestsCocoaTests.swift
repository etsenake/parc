import Foundation
import Testing
@testable import ParcCore

struct NoteHTMLReaderTestsCocoaTests {
    private typealias Fixture = NoteHTMLReaderTestsSupport

    private func importedBlocks() -> [NoteBlock] {
        let html = """
        <!DOCTYPE html PUBLIC "-//W3C//DTD HTML 4.01//EN" "http://www.w3.org/TR/html4/strict.dtd">
        <html>
        <head>
        <meta http-equiv="Content-Type" content="text/html; charset=UTF-8">
        <meta http-equiv="Content-Style-Type" content="text/css">
        <title></title>
        <meta name="Generator" content="Cocoa HTML Writer">
        <meta name="CocoaVersion" content="2575.4">
        <style type="text/css">
        p.p1 {margin: 0.0px 0.0px 0.0px 0.0px; font: 24.0px 'Helvetica Neue'}
        p.p2 {margin: 0.0px 0.0px 0.0px 0.0px; font: 13.0px 'Helvetica Neue'}
        p.p3 {margin: 0.0px 0.0px 0.0px 0.0px; font: 13.0px 'Helvetica Neue'; min-height: 15.0px}
        p.p4 {margin: 0.0px 0.0px 0.0px 0.0px; font: 18.0px 'Helvetica Neue'}
        li.li2 {margin: 0.0px 0.0px 0.0px 0.0px; font: 13.0px 'Helvetica Neue'}
        span.s1 {font-family: 'HelveticaNeue-Bold'; font-weight: bold; font-style: normal; font-size: 24.00px}
        span.s2 {font-family: 'Menlo-Regular'; font-weight: normal; font-style: normal; font-size: 12.00px}
        span.s3 {color: #fb0207}
        span.Apple-tab-span {white-space:pre}
        ul.ul1 {list-style-type: disc}
        ul.ul2 {list-style-type: circle}
        </style>
        </head>
        <body>
        <p class="p1"><span class="s1">Groceries</span></p>
        <p class="p2">For the <span class="s3">weekend</span> party, bring <span class="s2">cash</span>.</p>
        <p class="p3"><br></p>
        <p class="p4"><b>Produce</b></p>
        <ul class="ul1">
        <li class="li2">Apples</li>
        <ul class="ul2">
        <li class="li2">Honeycrisp</li>
        <li class="li2">Gala</li>
        </ul>
        <li class="li2">Pears</li>
        </ul>
        <p class="p2">Tab<span class="Apple-tab-span">\t</span>here<span class="Apple-converted-space">&nbsp; </span>end</p>
        </body>
        </html>
        """
        return Fixture.read(html)
    }

    private func blocks() throws -> [NoteBlock] {
        let blocks = importedBlocks()
        try #require(blocks.count == 6)
        return blocks
    }

    @Test
    func theImportKeepsTheExpectedBlockOrder() {
        let blocks = importedBlocks()
        Fixture.shape(blocks, ["heading", "paragraph", "heading", "bulletedItem", "bulletedItem", "paragraph"], "Apple Notes")
    }

    @Test
    func largeCocoaTextBecomesATitleHeading() throws {
        let blocks = try blocks()
        #expect(blocks[0].props.level == 1 && blocks[0].text.string == "Groceries", "big Cocoa text becomes a title heading")
    }

    @Test
    func cocoaClassStylesKeepColorAndCode() throws {
        let blocks = try blocks()
        #expect(Fixture.marks("weekend", blocks[1].text)?.color == .text(.red) && Fixture.marks("cash", blocks[1].text)?.code == true, "Cocoa class styles give colour and code")
    }

    @Test
    func mediumCocoaTextBecomesASecondLevelHeading() throws {
        let blocks = try blocks()
        #expect(blocks[2].props.level == 2 && blocks[2].text.string == "Produce", "18px over 13px is a heading 2")
    }

    @Test
    func cocoaSublistsNestAndTheOuterListContinues() throws {
        let blocks = try blocks()
        #expect(blocks[3].children.map(\.text.string) == ["Honeycrisp", "Gala"], "Cocoa nested lists")
        #expect(blocks[4].text.string == "Pears", "list continues")
    }

    @Test
    func appleTabSpansKeepTheirTab() throws {
        let blocks = try blocks()
        #expect(blocks[5].text.string == "Tab\there  end", "Apple tab spans keep the tab: \(blocks[5].text.string.debugDescription)")
    }
}
