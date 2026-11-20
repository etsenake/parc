import Foundation

@main
struct NoteHTMLReaderTests {
    static func expect(_ value: Bool, _ message: @autoclosure () -> String, line: UInt = #line) {
        NoteHTMLCheck.expect(value, value ? "" : message(), line: line)
    }

    static func marks(_ word: String, _ text: NoteText) -> NoteMarks? { NoteHTMLCheck.marks(of: word, in: text) }

    static func main() {
        googleDocs()
        word()
        github()
        notion()
        webArticle()
        appleNotes()
        slack()
        tables()
        nestedLists()
        NoteHTMLCheck.finish("NoteHTMLReaderTests")
    }

    static func read(_ html: String, base: String? = nil) -> [NoteBlock] {
        NoteHTMLReader.blocks(from: html, baseURL: base.flatMap(URL.init(string:)))
    }

    static func shape(_ blocks: [NoteBlock], _ expected: [String], _ label: String) {
        let kinds = blocks.map { $0.kind.rawValue }
        expect(kinds == expected, "\(label) shape:\n\(NoteHTMLCheck.outline(blocks))")
    }

    static func googleDocs() {
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
        let blocks = read(html)
        shape(blocks, ["heading", "paragraph", "bulletedItem", "bulletedItem", "numberedItem", "numberedItem", "todo", "todo",
                       "table", "divider", "paragraph"], "Google Docs")
        guard blocks.count == 11 else { return }
        expect(blocks[0].text.string == "Launch plan" && blocks[0].props.level == 1, "Docs heading")
        expect(blocks[0].text.runs().allSatisfy { !$0.marks.bold }, "Docs heading carries no bold")
        let body = blocks[1].text
        expect(body.plainText == "We ship on Friday, with care. Run make ship or the red alert and highlighted bits, struck, under and the docs.",
               "Docs paragraph text: \(body.plainText.debugDescription)")
        expect(marks("We ship on ", body)?.isPlain == true, "the guid wrapper's <b> does not bold everything")
        expect(marks("Friday", body)?.bold == true, "font-weight 700 is bold")
        expect(marks("care", body)?.italic == true, "font-style italic")
        expect(marks("make ship", body)?.code == true, "Courier New becomes code")
        expect(marks("red alert", body)?.color == .text(.red), "#ff0000 is red ink")
        expect(marks("highlighted", body)?.color == .background(.yellow), "#ffff00 background is a yellow highlight")
        expect(marks("struck", body)?.strikethrough == true, "line-through")
        expect(marks("under", body)?.underline == true, "underline")
        let link = marks("the docs", body)
        expect(link?.link == "https://example.com/docs", "Google redirect links unwrap: \(String(describing: link?.link))")
        expect(link?.underline == false && link?.color == nil, "link styling stays out of the marks")
        expect(blocks[2].text.string == "Design review" && blocks[2].children.map(\.text.string) == ["Icons"],
               "a list inside a list nests under the previous item")
        expect(blocks[3].text.string == "QA pass", "list continues after the nested list")
        expect(blocks[4].text.string == "Write notes" && blocks[5].text.string == "Tag release", "numbered items")
        expect(blocks[6].props.checked && blocks[6].text.string == "Book the room", "checked checklist item")
        expect(!blocks[6].text.runs().contains { $0.marks.strikethrough }, "checked items drop the strike Docs adds")
        expect(!blocks[7].props.checked && blocks[7].text.string == "Order cake", "unchecked checklist item")
        if let table = blocks[8].props.table {
            expect(table.rows.map { $0.map(\.string) } == [["Owner", "Task"], ["Sam", "Slides"]], "Docs table cells")
            expect(table.headerRow && !table.headerColumn, "a bold first row becomes the header")
            expect(table.rows[0].allSatisfy { cell in cell.runs().allSatisfy { !$0.marks.bold } }, "header cells lose the redundant bold")
        }
        expect(blocks[10].text.string == "H₂O and x²", "sub and super scripts use Unicode forms: \(blocks[10].text.string)")
    }

    static func word() {
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
        let blocks = read(html)
        shape(blocks, ["heading", "paragraph", "bulletedItem", "bulletedItem", "numberedItem", "numberedItem", "paragraph", "table"], "Word")
        guard blocks.count == 8 else { return }
        expect(blocks[0].text.string == "Quarterly review" && blocks[0].color == nil && marks("review", blocks[0].text)?.color == nil,
               "Word heading without its theme colour")
        let body = blocks[1].text
        expect(body.string == "Revenue grew 12% and churn fell slightly. See the appendix.", "Word paragraph: \(body.string.debugDescription)")
        expect(marks("12%", body)?.bold == true && marks("slightly", body)?.italic == true, "Word inline marks")
        expect(marks("appendix", body)?.italic == true, "class rules from Word's stylesheet apply")
        expect(blocks[2].text.string == "Hire two engineers" && blocks[2].children.map(\.text.string) == ["One for mobile"],
               "mso-list levels nest: \(NoteHTMLCheck.outline([blocks[2]]))")
        expect(blocks[2].children.first?.kind == .bulletedItem, "the o marker is a bullet")
        expect(blocks[3].text.string == "Open the Berlin office", "marker text never leaks into the item")
        expect(blocks[4].text.string == "Draft budget" && blocks[5].text.string == "Get sign-off", "numbered Word list")
        let mixed = blocks[6].text
        expect(marks("Highlighted", mixed)?.color == .background(.yellow), "Word highlight is yellow")
        expect(marks("dark red", mixed)?.color == .text(.red), "#C00000 is red")
        expect(marks("monospace", mixed)?.code == true, "Courier New is code")
        expect(blocks[7].props.table?.rows.map { $0.map(\.string) } == [["Region", "Sales"], ["EMEA", "4.2M"]], "Word table")
        expect(blocks[7].props.table?.headerRow == true, "bold Word header row")
    }

    static func github() {
        let html = """
        <article class="markdown-body entry-content container-lg" itemprop="text"><div class="markdown-heading" dir="auto"><h1 tabindex="-1" class="heading-element" dir="auto">Parc</h1><a id="user-content-parc" class="anchor" aria-label="Permalink: Parc" href="#parc"><svg class="octicon octicon-link" viewBox="0 0 16 16" version="1.1" width="16" height="16" aria-hidden="true"><path d="m7.775 3.275"></path></svg></a></div>
        <p dir="auto">A browser that <strong>feels</strong> like home. See <a href="/etsenake/parc/blob/main/docs/product.md">the guide</a> and <code>make test</code>.</p>
        <div class="markdown-alert markdown-alert-warning" dir="auto"><p class="markdown-alert-title" dir="auto"><svg class="octicon octicon-alert mr-2" viewBox="0 0 16 16" version="1.1" width="16" height="16" aria-hidden="true"><path d="M6.457 1.047"></path></svg>Warning</p><p dir="auto">Builds take a while.</p>
        </div>
        <div class="highlight highlight-source-shell notranslate position-relative overflow-auto" dir="auto"><pre>git clone https://github.com/etsenake/parc
        <span class="pl-c1">cd</span> parc &amp;&amp; make</pre><div class="zeroclipboard-container"><clipboard-copy aria-label="Copy" class="ClipboardButton btn" data-copy-feedback="Copied!" value="git clone" tabindex="0" role="button"><svg aria-hidden="true" height="16" viewBox="0 0 16 16" version="1.1" width="16" class="octicon octicon-copy"><path d="M0 6.75C0"></path></svg></clipboard-copy></div></div>
        <ul class="contains-task-list">
        <li class="task-list-item"><input type="checkbox" id="" disabled="" class="task-list-item-checkbox" checked=""> Tabs</li>
        <li class="task-list-item"><input type="checkbox" id="" disabled="" class="task-list-item-checkbox"> Notes
        <ul>
        <li>Markdown files</li>
        </ul>
        </li>
        </ul>
        <markdown-accessiblity-table><table>
        <thead>
        <tr>
        <th align="left">Key</th>
        <th align="center">Action</th>
        </tr>
        </thead>
        <tbody>
        <tr>
        <td align="left"><kbd>⌘T</kbd></td>
        <td align="center">New tab</td>
        </tr>
        </tbody>
        </table></markdown-accessiblity-table>
        <p dir="auto"><a target="_blank" rel="noopener noreferrer" href="/etsenake/parc/raw/main/docs/screenshot.png"><img src="/etsenake/parc/raw/main/docs/screenshot.png" alt="Screenshot" style="max-width: 100%;"></a></p>
        <p dir="auto">Math: <math-renderer class="js-inline-math" style="display: inline" data-static-url="https://github.githubassets.com/static" data-run-id="abc">$E = mc^2$</math-renderer> <g-emoji class="g-emoji" alias="tada">🎉</g-emoji></p>
        <math-renderer class="js-display-math" style="display: block" data-static-url="https://github.githubassets.com/static">$$\\sum_{i=1}^n i$$</math-renderer>
        <details><summary>More</summary><p dir="auto">Hidden <em>bits</em>.</p></details>
        <blockquote><p dir="auto">Quote line one<br>line two</p></blockquote>
        </article>
        """
        let blocks = read(html, base: "https://github.com/etsenake/parc")
        shape(blocks, ["heading", "paragraph", "callout", "code", "todo", "todo", "table", "image", "paragraph", "equation", "toggle", "quote"], "GitHub")
        guard blocks.count == 12 else { return }
        expect(blocks[0].text.string == "Parc", "permalink anchors vanish")
        let body = blocks[1].text
        expect(marks("feels", body)?.bold == true && marks("make test", body)?.code == true, "GitHub inline marks")
        expect(marks("the guide", body)?.link == "https://github.com/etsenake/parc/blob/main/docs/product.md", "relative links resolve")
        expect(blocks[2].props.alert == "WARNING" && blocks[2].text.string == "Builds take a while.", "GitHub alert becomes a callout")
        expect(blocks[3].props.language == "shell" && blocks[3].text.string == "git clone https://github.com/etsenake/parc\ncd parc && make",
               "code block keeps lines and language: \(blocks[3].text.string.debugDescription)")
        expect(blocks[4].props.checked && blocks[4].text.string == "Tabs", "checked task")
        expect(!blocks[5].props.checked && blocks[5].text.string == "Notes" && blocks[5].children.map(\.text.string) == ["Markdown files"],
               "task with nested list")
        if let table = blocks[6].props.table {
            expect(table.headerRow && table.alignments == [.left, .center], "GitHub table header and alignment")
            expect(table.rows[1].map(\.string) == ["⌘T", "New tab"] && table.rows[1][0].runs().first?.marks.code == true, "kbd is code")
        }
        expect(blocks[7].props.source == "https://github.com/etsenake/parc/raw/main/docs/screenshot.png" && blocks[7].props.alt == "Screenshot",
               "image src resolves against the base URL")
        let math = blocks[8].text
        expect(math.runs().contains { $0.marks.atom == .equation("E = mc^2") }, "inline math becomes an equation")
        expect(math.plainText.hasSuffix("🎉"), "g-emoji keeps its emoji")
        expect(blocks[9].text.string == "\\sum_{i=1}^n i", "display math becomes an equation block")
        expect(blocks[10].text.string == "More" && !blocks[10].props.expanded && blocks[10].children.first?.text.string == "Hidden bits.",
               "details becomes a toggle")
        expect(blocks[11].text.string == "Quote line one\nline two", "br inside a quote is a soft break")
    }

    static func notion() {
        let html = """
        <meta charset="utf-8"><h2 id="1a2b" class="">Trip ideas</h2><p id="2b3c" class="">A <mark class="highlight-red">red</mark> word, a <span class="highlight-yellow_background">sunny</span> one and <code>inline code</code>.</p><ul id="3c4d" class="bulleted-list"><li style="list-style-type:disc">Lisbon<ul id="3c4e" class="bulleted-list"><li style="list-style-type:circle">Trams</li></ul></li></ul><ol type="1" id="4d5e" class="numbered-list" start="3"><li>Book flights</li></ol><ul id="5e6f" class="to-do-list"><li><div class="checkbox checkbox-on"></div> <span class="to-do-children-checked">Passport</span></li></ul><ul id="6f7a" class="to-do-list"><li><div class="checkbox checkbox-off"></div> <span class="to-do-children-unchecked">Adapters</span></li></ul><ul id="7a8b" class="toggle"><li><details open=""><summary>Packing</summary><p id="8b9c" class="">Socks</p></details></li></ul><figure class="block-color-gray_background callout" style="white-space:pre-wrap;display:flex" id="9c0d"><div style="font-size:1.5em"><span class="icon">✈️</span></div><div style="width:100%">Window seat, always.</div></figure><blockquote id="0d1e" class="block-color-purple">Travel light.</blockquote><pre id="1e2f" class="code"><code class="language-JavaScript">const trip = plan("Lisbon")</code></pre><figure id="2f3a" class="equation"><style>@import url('https://cdnjs.cloudflare.com/ajax/libs/KaTeX/0.16.9/katex.min.css')</style><div class="equation-container"><span class="katex-display"><span class="katex"><span class="katex-mathml"><math xmlns="http://www.w3.org/1998/Math/MathML" display="block"><semantics><mrow><mi>a</mi></mrow><annotation encoding="application/x-tex">a^2 + b^2 = c^2</annotation></semantics></math></span><span class="katex-html" aria-hidden="true"><span class="base">a2+b2=c2</span></span></span></span></div></figure><table id="3a4b" class="simple-table"><thead class="simple-table-header"><tr id="r1"><th id="c1" class="simple-table-header-color simple-table-header">City</th><th id="c2" class="simple-table-header-color simple-table-header">Days</th></tr></thead><tbody><tr id="r2"><th id="c3" class="simple-table-header-color simple-table-header">Porto</th><td id="c4">2</td></tr></tbody></table><div id="4b5c" class="column-list"><div id="a1" style="width:50%" class="column"><p>Left side</p></div><div id="b1" style="width:50%" class="column"><p>Right side</p></div></div><figure id="5c6d"><a href="https://www.visitportugal.com/" class="bookmark source"><div class="bookmark-info"><div class="bookmark-text"><div class="bookmark-title">Visit Portugal</div><div class="bookmark-description">Official tourism site</div></div><div class="bookmark-href">https://www.visitportugal.com/</div></div></a></figure><hr id="6d7e"/><figure id="7e8f" class="image"><a href="Trip/tram.jpg"><img style="width:640px" src="Trip/tram.jpg"/></a><figcaption>Tram 28</figcaption></figure><p>Equation <span class="notion-text-equation-token" contenteditable="false"><span class="katex"><span class="katex-mathml"><math><semantics><annotation encoding="application/x-tex">\\pi r^2</annotation></semantics></math></span><span class="katex-html" aria-hidden="true">πr2</span></span></span> inline.</p>
        """
        let blocks = read(html)
        shape(blocks, ["heading", "paragraph", "bulletedItem", "numberedItem", "todo", "todo", "toggle", "callout", "quote", "code",
                       "equation", "table", "columns", "bookmark", "divider", "image", "paragraph"], "Notion")
        guard blocks.count == 17 else { return }
        expect(blocks[0].props.level == 2 && blocks[0].text.string == "Trip ideas", "Notion heading")
        expect(marks("red", blocks[1].text)?.color == .text(.red), "highlight-red is red ink")
        expect(marks("sunny", blocks[1].text)?.color == .background(.yellow), "highlight-yellow_background")
        expect(marks("inline code", blocks[1].text)?.code == true, "inline code")
        expect(blocks[2].children.map(\.text.string) == ["Trams"], "nested bullets")
        expect(blocks[3].props.listStart == 3, "ol start carries over")
        expect(blocks[4].props.checked && blocks[4].text.string == "Passport", "Notion checked to-do")
        expect(!blocks[5].props.checked && blocks[5].text.string == "Adapters", "Notion open to-do")
        expect(blocks[6].text.string == "Packing" && blocks[6].props.expanded && blocks[6].children.first?.text.string == "Socks",
               "toggle list item lifts to a toggle")
        expect(blocks[7].props.icon == "✈️" && blocks[7].text.string == "Window seat, always." && blocks[7].color == .background(.gray),
               "Notion callout: \(NoteHTMLCheck.outline([blocks[7]])) icon \(String(describing: blocks[7].props.icon))")
        expect(blocks[8].text.string == "Travel light." && blocks[8].color == .text(.purple), "quote colour")
        expect(blocks[9].props.language == "javascript" && blocks[9].text.string == "const trip = plan(\"Lisbon\")", "Notion code")
        expect(blocks[10].text.string == "a^2 + b^2 = c^2", "Notion equation reads the TeX annotation")
        expect(blocks[11].props.table?.headerRow == true && blocks[11].props.table?.headerColumn == true, "Notion simple table headers")
        expect(blocks[12].children.count == 2 && blocks[12].children.allSatisfy { $0.kind == .column }
               && blocks[12].children[1].children.first?.text.string == "Right side", "Notion columns")
        expect(blocks[13].props.source == "https://www.visitportugal.com/" && blocks[13].props.bookmark?.title == "Visit Portugal"
               && blocks[13].props.bookmark?.summary == "Official tourism site", "Notion bookmark")
        expect(blocks[15].props.source == "Trip/tram.jpg" && blocks[15].props.caption.string == "Tram 28", "Notion image with caption")
        expect(blocks[16].text.runs().contains { $0.marks.atom == .equation("\\pi r^2") } && blocks[16].text.plainText == "Equation \\pi r^2 inline.",
               "Notion inline equation: \(blocks[16].text.plainText.debugDescription)")
    }

    static func webArticle() {
        let html = """
        <html><head><title>Ignore me</title><script>var x = "<p>not content</p>"; if (a < b) {}</script>
        <style>.byline{color:#999} .lede { font-weight: bold } nav a { color: red }</style></head><body>
        <nav class="site-nav"><ul><li><a href="/">Home</a></li><li><a href="/news">News</a></li></ul></nav>
        <div role="navigation" class="breadcrumbs"><a href="/">Home</a> › <a href="/tech">Tech</a></div>
        <article>
          <header><h1>The   quiet
          web</h1><p class="byline">By <a href="/authors/ada">Ada</a> &middot; <time datetime="2026-11-02">Nov 2</time></p></header>
          <p class="lede">Websites are getting
             lighter again.</p>
          <p>It started with a <em>simple</em> idea &mdash; ship less JavaScript. &ldquo;Less is more,&rdquo; said one engineer&nbsp;&nbsp;proudly.
          <p>Unclosed paragraphs are fine<br>and so are <b>unclosed <i>tags</b> here</i>.
          <figure><img src="/img/hero.jpg" alt="A calm website" width="800" height="400"><figcaption>Calm, isn't it?</figcaption></figure>
          <img src="https://tracker.example.com/pixel.gif" width="1" height="1">
          <aside class="pullquote">💬 Speed is a feature.</aside>
          <div style="display:none">Hidden promo</div>
          <span class="sr-only">Skip to footer</span>
          <h2>What changed<span hidden> (secret)</span></h2>
          <ul><li>Fewer trackers<li>Smaller images</ul>
          <p>Read more at <a href="javascript:void(0)">nowhere</a> or <a href="//cdn.example.com/more">the CDN</a> &amp; <a href="#top">top</a>.</p>
          <div class="ad-slot"><iframe src="https://ads.example.com/frame" width="300" height="250"></iframe></div>
          <iframe src="https://www.youtube.com/embed/dQw4w9WgXcQ" width="560" height="315" allowfullscreen></iframe>
          <!-- a comment <p>inside</p> -->
          <![CDATA[ raw & cdata ]]>
          <p>Tom &amp; Jerry &lt;3 &copy2026 &unknown; &#x1F600;</p>
        </article>
        <footer>&copy; 2026 Example &amp; Co</footer>
        </body></html>
        """
        let blocks = read(html, base: "https://news.example.com/2026/quiet-web")
        shape(blocks, ["heading", "paragraph", "paragraph", "paragraph", "paragraph", "image", "callout", "heading", "bulletedItem",
                       "bulletedItem", "paragraph", "embed", "paragraph", "paragraph"], "Web article")
        guard blocks.count == 14 else { return }
        expect(blocks[0].text.string == "The quiet web", "whitespace collapses in headings")
        expect(blocks[1].text.string == "By Ada · Nov 2" && marks("By", blocks[1].text)?.color == nil, "byline keeps text, drops grey")
        expect(marks("Ada", blocks[1].text)?.link == "https://news.example.com/authors/ada", "relative author link resolves")
        expect(blocks[2].text.string == "Websites are getting lighter again." && marks("Websites", blocks[2].text)?.bold == true,
               "class rules can bold a lede")
        expect(blocks[3].text.string == "It started with a simple idea — ship less JavaScript. “Less is more,” said one engineer  proudly.",
               "entities and non-breaking spaces: \(blocks[3].text.string.debugDescription)")
        expect(blocks[4].text.string == "Unclosed paragraphs are fine\nand so are unclosed tags here.", "unclosed tags: \(blocks[4].text.string.debugDescription)")
        expect(marks("unclosed", blocks[4].text)?.bold == true && marks("tags", blocks[4].text)?.italic == true, "misnested marks")
        expect(blocks[5].props.source == "https://news.example.com/img/hero.jpg" && blocks[5].props.caption.string == "Calm, isn't it?",
               "figure image and caption")
        expect(blocks[6].text.string == "Speed is a feature." && blocks[6].props.icon == "💬", "aside becomes a callout with its emoji")
        expect(blocks[7].text.string == "What changed", "hidden spans are skipped")
        expect(blocks[8].text.string == "Fewer trackers" && blocks[9].text.string == "Smaller images", "implied li ends")
        let links = blocks[10].text
        expect(marks("nowhere", links)?.link == nil, "javascript: links are dropped")
        expect(marks("the CDN", links)?.link == "https://cdn.example.com/more", "protocol-relative links")
        expect(marks("top", links)?.link == "https://news.example.com/2026/quiet-web#top", "fragment links resolve against the page")
        expect(blocks[11].props.source == "https://www.youtube.com/embed/dQw4w9WgXcQ", "known embeds survive, ad frames do not")
        expect(blocks[12].text.string == "Tom & Jerry <3 ©2026 &unknown; 😀", "entity decoding: \(blocks[12].text.string.debugDescription)")
        expect(blocks[13].text.string == "© 2026 Example & Co", "footer text")
        let flat = blocks.map(\.text.plainText).joined(separator: " ")
        expect(!flat.contains("not content") && !flat.contains("Hidden promo") && !flat.contains("Skip to footer")
               && !flat.contains("News") && !flat.contains("cdata") && !flat.contains("secret"), "chrome, scripts and hidden bits stay out")
    }

    static func appleNotes() {
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
        let blocks = read(html)
        shape(blocks, ["heading", "paragraph", "heading", "bulletedItem", "bulletedItem", "paragraph"], "Apple Notes")
        guard blocks.count == 6 else { return }
        expect(blocks[0].props.level == 1 && blocks[0].text.string == "Groceries", "big Cocoa text becomes a title heading")
        expect(marks("weekend", blocks[1].text)?.color == .text(.red) && marks("cash", blocks[1].text)?.code == true,
               "Cocoa class styles give colour and code")
        expect(blocks[2].props.level == 2 && blocks[2].text.string == "Produce", "18px over 13px is a heading 2")
        expect(blocks[3].children.map(\.text.string) == ["Honeycrisp", "Gala"], "Cocoa nested lists")
        expect(blocks[4].text.string == "Pears", "list continues")
        expect(blocks[5].text.string == "Tab\there  end", "Apple tab spans keep the tab: \(blocks[5].text.string.debugDescription)")
    }

    static func slack() {
        let html = """
        <meta charset='utf-8'><div class="p-rich_text_section">Here's the plan for <b data-stringify-type="bold">Friday</b>:</div><ul data-stringify-type="unordered-list" data-indent="0" class="p-rich_text_list p-rich_text_list__bullet" data-border="0"><li data-stringify-indent="0" data-stringify-border="0">Ship it</li></ul><ul data-stringify-type="unordered-list" data-indent="1" class="p-rich_text_list p-rich_text_list__bullet p-rich_text_list--nested" data-border="0"><li data-stringify-indent="1" data-stringify-border="0">Run tests</li><li data-stringify-indent="1" data-stringify-border="0">Tag it</li></ul><ul data-stringify-type="unordered-list" data-indent="0" class="p-rich_text_list p-rich_text_list__bullet" data-border="0"><li data-stringify-indent="0" data-stringify-border="0">Celebrate <img data-id=":tada:" data-stringify-type="emoji" data-stringify-emoji=":tada:" class="c-emoji c-emoji__medium c-emoji--inline" src="https://a.slack-edge.com/production-standard-emoji-assets/14.0/apple-medium/1f389.png" alt="tada" aria-label="tada emoji"></li></ul><div class="p-rich_text_section"><a target="_blank" class="c-link" data-stringify-link="https://example.com" delay="150" data-sk="tooltip_parent" href="https://example.com" rel="noopener noreferrer">example.com</a> then <code data-stringify-type="code" class="c-mrkdwn__code">npm test</code><span class="c-mrkdwn__br" data-stringify-type="paragraph-break"></span>New paragraph</div><pre class="c-mrkdwn__pre" data-stringify-type="pre"><div class="p-rich_text_block--no-overflow">let x = 1<br>let y = 2</div></pre><blockquote type="cite" class="c-mrkdwn__quote" data-stringify-type="quote">Quoted <i data-stringify-type="italic">text</i></blockquote><span style="color: rgb(29, 28, 29); font-family: Slack-Lato, Slack-Fractions, appleLogo, sans-serif; font-size: 15px; background-color: rgb(248, 248, 248);">Plain loose text</span>
        """
        let blocks = read(html)
        shape(blocks, ["paragraph", "bulletedItem", "bulletedItem", "paragraph", "paragraph", "code", "quote", "paragraph"], "Slack")
        guard blocks.count == 8 else { return }
        expect(marks("Friday", blocks[0].text)?.bold == true, "Slack bold")
        expect(blocks[1].text.string == "Ship it" && blocks[1].children.map(\.text.string) == ["Run tests", "Tag it"],
               "data-indent lists nest: \(NoteHTMLCheck.outline([blocks[1]]))")
        expect(blocks[2].text.string == "Celebrate :tada:", "Slack emoji images become their shortcode")
        expect(marks("example.com", blocks[3].text)?.link == "https://example.com" && marks("npm test", blocks[3].text)?.code == true,
               "Slack link and code")
        expect(blocks[4].text.string == "New paragraph", "paragraph-break spans split paragraphs")
        expect(blocks[5].text.string == "let x = 1\nlet y = 2", "Slack pre")
        expect(blocks[6].text.string == "Quoted text" && marks("text", blocks[6].text)?.italic == true, "Slack quote")
        expect(blocks[7].text.string == "Plain loose text" && marks("Plain", blocks[7].text)?.isPlain == true,
               "near-black ink and near-white backgrounds are ignored")
    }

    static func tables() {
        let html = """
        <table><tr><td colspan="2"><b>Plan</b></td></tr><tr><td>Mon</td><td><ul><li>Gym</li><li>Read<ol><li>Book</li></ol></li></ul></td></tr></table>
        <table role="presentation"><tr><td><h3>Inside layout</h3></td><td><p>Side text</p></td></tr></table>
        <table><tr><td><p>Only cell</p></td></tr></table>
        <table><caption>Scores</caption><tr><th>Name</th><th>Score</th></tr><tr><td>Ann<td style="text-align:right">10<tr><td>Bo</td><td>7</td></tr></table>
        <table><tr><td>a</td><td>b</td></tr><tr><td>c</td><td>d</td></tr></table>
        """
        let blocks = read(html)
        shape(blocks, ["table", "heading", "paragraph", "paragraph", "paragraph", "table", "table"], "Tables")
        guard blocks.count == 7 else { return }
        if let table = blocks[0].props.table {
            expect(table.rows.map { $0.map(\.string) } == [["Plan", ""], ["Mon", "• Gym\n• Read\n  1. Book"]],
                   "colspan pads and lists flatten into cell text: \(table.rows.map { $0.map(\.string) })")
            expect(table.headerRow, "bold spanning row is the header")
        }
        expect(blocks[1].text.string == "Inside layout" && blocks[2].text.string == "Side text", "layout tables unwrap")
        expect(blocks[3].text.string == "Only cell", "a single cell unwraps")
        expect(blocks[4].text.string == "Scores", "captions come first")
        if let table = blocks[5].props.table {
            expect(table.headerRow && table.rows.map { $0.map(\.string) } == [["Name", "Score"], ["Ann", "10"], ["Bo", "7"]],
                   "implied tr and td ends")
        }
        expect(blocks[6].props.table?.headerRow == false, "plain tables have no header")
    }

    static func nestedLists() {
        let html = """
        <ol start="5"><li>Five<ol type="a"><li>Five a</li><li>Five b<ul><li>deep</li></ul></li></ol></li><li><p>Six</p><p>Six more</p></li></ol>
        <ul><li></li><li>[x] Done markdown style</li><li>[ ] Not yet</li></ul>
        <p>Text <ul><li>breaks the paragraph</li></ul> after</p>
        <ul data-type="taskList"><li data-checked="true">Tiptap done</li></ul>
        <ol><li data-list="bullet">Quill bullet</li><li data-list="checked">Quill done</li></ol>
        <h2>Heading <ul><li>can't hold lists</li></ul></h2>
        """
        let blocks = read(html)
        shape(blocks, ["numberedItem", "numberedItem", "todo", "todo", "paragraph", "bulletedItem", "paragraph", "todo",
                       "bulletedItem", "todo", "heading", "bulletedItem"], "Nested lists")
        guard blocks.count == 12 else { return }
        expect(blocks[0].props.listStart == 5 && blocks[0].children.map(\.text.string) == ["Five a", "Five b"], "nested ordered")
        expect(blocks[0].children.last?.children.first?.text.string == "deep", "three levels deep")
        expect(blocks[1].text.string == "Six" && blocks[1].children.map(\.text.string) == ["Six more"], "extra paragraphs become children")
        expect(blocks[2].props.checked && blocks[2].text.string == "Done markdown style", "[x] prefix")
        expect(!blocks[3].props.checked && blocks[3].text.string == "Not yet", "[ ] prefix")
        expect(blocks[4].text.string == "Text" && blocks[6].text.string == "after", "lists split paragraphs")
        expect(blocks[7].props.checked && blocks[8].text.string == "Quill bullet" && blocks[9].props.checked, "editor checklist flavours")
        expect(blocks[10].text.string == "Heading" && blocks[10].children.isEmpty, "headings never take children")
        for block in blocks { expect(block.acceptsChildren || block.children.isEmpty, "children only where accepted") }
    }
}
