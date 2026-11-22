import Foundation
import Testing
@testable import ParcCore

struct NoteHTMLReaderTestsWordTests {
    private typealias Fixture = NoteHTMLReaderTestsSupport

    private func importedBlocks() -> [NoteBlock] {
        let html = """
        <html xmlns:v="urn:schemas-microsoft-com:vml" xmlns:o="urn:schemas-microsoft-com:office:office" xmlns:w="urn:schemas-microsoft-com:office:word" xmlns="http://www.w3.org/TR/REC-html40">
        <head><meta http-equiv=Content-Type content="text/html; charset=utf-8"><meta name=ProgId content=Word.Document>
        <meta name=Generator content="Microsoft Word 15">
        <!--[if gte mso 9]><xml><o:OfficeDocumentSettings><o:AllowPNG/></o:OfficeDocumentSettings></xml><![endif]-->
        <style>
        <!--
         /* Font Definitions */
         @font-face {font-family:"Cambria Math"; panose-1:2 4 5 3 5 4 6 3 2 4;}
        p.MsoNormal, li.MsoNormal, div.MsoNormal {margin:0in; font-size:12.0pt; font-family:"Calibri",sans-serif;}
        h1 {mso-style-link:"Heading 1 Char"; color:#2F5496; font-size:16.0pt;}
        p.MsoListParagraph, li.MsoListParagraph {margin-left:.5in;}
        span.Emphasis {font-style:italic;}
        .MsoChpDefault {font-family:"Calibri",sans-serif;}
        @page WordSection1 {size:8.5in 11.0in; margin:1.0in 1.0in 1.0in 1.0in;}
        div.WordSection1 {page:WordSection1;}
        @list l0:level1 {mso-level-number-format:bullet; mso-level-text:\\F0B7; font-family:Symbol;}
        -->
        </style>
        </head>
        <body lang=EN-US style='tab-interval:.5in;word-wrap:break-word'>
        <!--StartFragment-->
        <div class=WordSection1>
        <h1>Quarterly <span class=SpellE>review</span><o:p></o:p></h1>
        <p class=MsoNormal>Revenue grew <b>12%</b> and churn fell <i style='mso-bidi-font-style:normal'>slightly</i>. See the <span class=Emphasis>appendix</span>.<o:p></o:p></p>
        <p class=MsoNormal><o:p>&nbsp;</o:p></p>
        <p class=MsoListParagraphCxSpFirst style='text-indent:-.25in;mso-list:l0 level1 lfo1'><![if !supportLists]><span style='font-family:Symbol;mso-fareast-font-family:Symbol;mso-bidi-font-family:Symbol'><span style='mso-list:Ignore'>·<span style='font:7.0pt "Times New Roman"'>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp; </span></span></span><![endif]>Hire two engineers<o:p></o:p></p>
        <p class=MsoListParagraphCxSpMiddle style='margin-left:1.0in;mso-add-space:auto;text-indent:-.25in;mso-list:l0 level2 lfo1'><![if !supportLists]><span style='font-family:"Courier New";mso-fareast-font-family:"Courier New"'><span style='mso-list:Ignore'>o<span style='font:7.0pt "Times New Roman"'>&nbsp;&nbsp; </span></span></span><![endif]>One for mobile<o:p></o:p></p>
        <p class=MsoListParagraphCxSpLast style='text-indent:-.25in;mso-list:l0 level1 lfo1'><![if !supportLists]><span style='font-family:Symbol'><span style='mso-list:Ignore'>·<span style='font:7.0pt "Times New Roman"'>&nbsp;&nbsp;&nbsp; </span></span></span><![endif]>Open the Berlin office<o:p></o:p></p>
        <p class=MsoNormal><o:p>&nbsp;</o:p></p>
        <p class=MsoListParagraphCxSpFirst style='text-indent:-.25in;mso-list:l1 level1 lfo2'><!--[if !supportLists]--><span style='mso-list:Ignore'>1.<span style='font:7.0pt "Times New Roman"'>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp; </span></span><!--[endif]-->Draft budget<o:p></o:p></p>
        <p class=MsoListParagraphCxSpLast style='text-indent:-.25in;mso-list:l1 level1 lfo2'><!--[if !supportLists]--><span style='mso-list:Ignore'>2.<span style='font:7.0pt "Times New Roman"'>&nbsp; </span></span><!--[endif]-->Get sign-off<o:p></o:p></p>
        <p class=MsoNormal><span style='background:yellow;mso-highlight:yellow'>Highlighted</span> and <span style='color:#C00000'>dark red</span> and <span style='font-family:"Courier New"'>monospace</span>.<o:p></o:p></p>
        <table class=MsoTableGrid border=1 cellspacing=0 cellpadding=0 style='border-collapse:collapse;border:none;mso-border-alt:solid windowtext .5pt'>
         <tr><td width=312 valign=top style='width:3.25in;border:solid windowtext 1.0pt;padding:0in 5.4pt 0in 5.4pt'><p class=MsoNormal><b>Region<o:p></o:p></b></p></td>
          <td width=312 valign=top style='width:3.25in;border:solid windowtext 1.0pt'><p class=MsoNormal><b>Sales<o:p></o:p></b></p></td></tr>
         <tr><td width=312 valign=top><p class=MsoNormal>EMEA<o:p></o:p></p></td><td width=312 valign=top><p class=MsoNormal>4.2M<o:p></o:p></p></td></tr>
        </table>
        </div>
        <!--EndFragment-->
        </body>
        </html>
        """
        return Fixture.read(html)
    }

    private func blocks() throws -> [NoteBlock] {
        let blocks = importedBlocks()
        try #require(blocks.count == 8)
        return blocks
    }

    @Test
    func theImportKeepsTheExpectedBlockOrder() {
        let blocks = importedBlocks()
        Fixture.shape(blocks, ["heading", "paragraph", "bulletedItem", "bulletedItem", "numberedItem", "numberedItem", "paragraph", "table"], "Word")
    }

    @Test
    func wordHeadingsDropTheThemeColor() throws {
        let blocks = try blocks()
        #expect(blocks[0].text.string == "Quarterly review" && blocks[0].color == nil && Fixture.marks("review", blocks[0].text)?.color == nil, "Word heading without its theme colour")
    }

    @Test
    func wordParagraphsKeepTheirText() throws {
        let blocks = try blocks()
        let body = blocks[1].text
        #expect(body.string == "Revenue grew 12% and churn fell slightly. See the appendix.", "Word paragraph: \(body.string.debugDescription)")
    }

    @Test
    func wordInlineElementsKeepBoldAndItalic() throws {
        let blocks = try blocks()
        let body = blocks[1].text
        #expect(Fixture.marks("12%", body)?.bold == true && Fixture.marks("slightly", body)?.italic == true, "Word inline marks")
    }

    @Test
    func wordStylesheetClassesApply() throws {
        let blocks = try blocks()
        let body = blocks[1].text
        #expect(Fixture.marks("appendix", body)?.italic == true, "class rules from Word's stylesheet apply")
    }

    @Test
    func wordListLevelsNestUnderTheirBullet() throws {
        let blocks = try blocks()
        #expect(blocks[2].text.string == "Hire two engineers" && blocks[2].children.map(\.text.string) == ["One for mobile"], "mso-list levels nest: \(NoteHTMLCheck.outline([blocks[2]]))")
        #expect(blocks[2].children.first?.kind == .bulletedItem, "the o marker is a bullet")
    }

    @Test
    func wordBulletMarkersStayOutOfTheText() throws {
        let blocks = try blocks()
        #expect(blocks[3].text.string == "Open the Berlin office", "marker text never leaks into the item")
    }

    @Test
    func wordNumberedListItemsKeepTheirText() throws {
        let blocks = try blocks()
        #expect(blocks[4].text.string == "Draft budget" && blocks[5].text.string == "Get sign-off", "numbered Word list")
    }

    @Test
    func wordHighlightBecomesYellow() throws {
        let blocks = try blocks()
        let mixed = blocks[6].text
        #expect(Fixture.marks("Highlighted", mixed)?.color == .background(.yellow), "Word highlight is yellow")
    }

    @Test
    func wordDarkRedBecomesRedInk() throws {
        let blocks = try blocks()
        let mixed = blocks[6].text
        #expect(Fixture.marks("dark red", mixed)?.color == .text(.red), "#C00000 is red")
    }

    @Test
    func wordCourierNewBecomesCode() throws {
        let blocks = try blocks()
        let mixed = blocks[6].text
        #expect(Fixture.marks("monospace", mixed)?.code == true, "Courier New is code")
    }

    @Test
    func wordTablesKeepTheirCellText() throws {
        let blocks = try blocks()
        #expect(blocks[7].props.table?.rows.map { $0.map(\.string) } == [["Region", "Sales"], ["EMEA", "4.2M"]], "Word table")
    }

    @Test
    func aBoldWordTableRowBecomesAHeader() throws {
        let blocks = try blocks()
        #expect(blocks[7].props.table?.headerRow == true, "bold Word header row")
    }
}
