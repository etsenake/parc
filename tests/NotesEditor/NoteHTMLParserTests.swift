import Foundation

@main
struct NoteHTMLParserTests {
    static func expect(_ value: Bool, _ message: @autoclosure () -> String, line: UInt = #line) {
        NoteHTMLCheck.expect(value, value ? "" : message(), line: line)
    }

    static func main() {
        entities()
        structure()
        styles()
        colors()
        NoteHTMLCheck.finish("NoteHTMLParserTests")
    }

    static func names(_ node: NoteHTMLNode) -> String {
        node.children.map { child in
            child.isText ? child.text : "<" + child.name + ">" + names(child) + "</" + child.name + ">"
        }.joined()
    }

    static func entities() {
        expect(NoteHTMLEntities.latin1Count == 96, "Latin-1 entity table covers 160...255")
        let decoded = NoteHTMLEntities.decode("&amp;&lt;&gt;&quot;&apos;&#x1F600;&#128512;&copy2026&notanentity;&#150;&#0;&nbsp;&eacute;&hellip;&rarr;")
        expect(decoded == "&<>\"'😀😀©2026¬anentity;–\u{FFFD}\u{A0}é…→", "entity decoding: \(decoded.debugDescription)")
        let attribute = NoteHTMLParser.parse("<a href=\"?a=1&copy=2&amp;b=3\" title='it&#39;s'>x</a>").children.first
        expect(attribute?["href"] == "?a=1&copy=2&b=3", "legacy entities stay literal before = in attributes: \(attribute?["href"] ?? "")")
        expect(attribute?["title"] == "it's", "single-quoted attribute")
    }

    static func structure() {
        expect(names(NoteHTMLParser.parse("<p>One<p>Two")) == "<p>One</p><p>Two</p>", "p closes p")
        expect(names(NoteHTMLParser.parse("<ul><li>a<li>b</ul>")) == "<ul><li>a</li><li>b</li></ul>", "li closes li")
        expect(names(NoteHTMLParser.parse("<ul><li>a<ul><li>b</ul><li>c</ul>")) == "<ul><li>a<ul><li>b</li></ul></li><li>c</li></ul>",
               "nested lists close the right items")
        expect(names(NoteHTMLParser.parse("<dl><dt>T<dd>D<dt>U</dl>")) == "<dl><dt>T</dt><dd>D</dd><dt>U</dt></dl>", "dt and dd")
        expect(names(NoteHTMLParser.parse("<table><tr><td>1<td>2<tr><td>3</table>"))
               == "<table><tr><td>1</td><td>2</td></tr><tr><td>3</td></tr></table>", "implied cells and rows")
        expect(names(NoteHTMLParser.parse("<p>a<div>b</div>c</p>")) == "<p>a</p><div>b</div>c", "blocks close paragraphs")
        expect(names(NoteHTMLParser.parse("<b>bold <i>both</b> after</i>")) == "<b>bold <i>both</i></b> after", "misnested inline tags")
        expect(names(NoteHTMLParser.parse("<div><span>x</div>y")) == "<div><span>x</span></div>y", "unclosed inline tags close with their block")
        expect(names(NoteHTMLParser.parse("a<br>b</br>c<img src=x>d<hr/>e")) == "a<br></br>b<br></br>c<img></img>d<hr></hr>e", "void elements")
        expect(names(NoteHTMLParser.parse("<!DOCTYPE html><html><head><title>T</title></head><body>x<!-- <p>no</p> --></body></html>"))
               == "<title>T</title>x", "doctype, html, head and comments")
        expect(names(NoteHTMLParser.parse("<script>if (a<b) { x = \"</p>\" }</script>z")) == "<script>if (a<b) { x = \"</p>\" }</script>z",
               "script is raw text")
        expect(names(NoteHTMLParser.parse("<textarea>&lt;b&gt;</textarea>")) == "<textarea><b></textarea>", "textarea decodes entities")
        expect(names(NoteHTMLParser.parse("x<![CDATA[hidden]]>y<svg><![CDATA[shown]]></svg>")) == "xy<svg>shown</svg>", "CDATA only in foreign content")
        expect(names(NoteHTMLParser.parse("1 < 2 and 3 <> 4 </ >")) == "1 < 2 and 3 <> 4 ", "stray angle brackets are text")
        expect(names(NoteHTMLParser.parse("<P CLASS=\"A\">Up</P>")) == "<p>Up</p>", "tag names are case-insensitive")
        let word = NoteHTMLParser.parse("<p><![if !supportLists]><span>1.</span><![endif]>Item</p>")
        expect(names(word) == "<p><#mso-marker><span>1.</span></#mso-marker>Item</p>", "Word list markers are fenced: \(names(word))")
        let unterminated = NoteHTMLParser.parse("<div class=\"open")
        expect(unterminated.children.count == 1, "unterminated attributes do not crash")
        expect(names(NoteHTMLParser.parse("a\r\nb\rc")) == "a\nb\nc", "line endings normalise")
    }

    static func styles() {
        let css = NoteHTMLStyleSheet.declarations("color: red; background: url(data:image/png;base64,AA==) no-repeat; font-weight:700 !important;;")
        expect(css["color"] == "red" && css["font-weight"] == "700" && css["background"]?.hasPrefix("url(data:image/png;base64") == true,
               "declarations split outside parentheses: \(css)")
        let document = NoteHTMLParser.parse("<style>/* x */ p.p1 {font: italic bold 12.0px Menlo} .s1{color:#f00} h1{color:blue} div span.no{x:y} @media print{.s1{color:green}}</style><p class=\"p1 s1\">t</p>")
        let sheet = NoteHTMLStyleSheet(document)
        let paragraph = document.first { $0.name == "p" }!
        let declarations = sheet.declarations(for: paragraph)
        expect(declarations["color"] == "#f00", "class rules apply and @media is skipped: \(declarations)")
        let font = NoteHTMLFont(declarations)
        expect(font.bold == true && font.italic == true && font.isMonospace && font.size == 9, "font shorthand: \(font)")
        expect(NoteHTMLFont(["font-family": "\"Courier New\", monospace"]).isMonospace, "Courier New is mono")
        expect(!NoteHTMLFont(["font-family": "Montserrat, sans-serif"]).isMonospace, "Montserrat is not")
        expect(NoteHTMLFont(["font-weight": "500"]).bold == false && NoteHTMLFont(["font-weight": "600"]).bold == true, "weights")
    }

    static func colors() {
        let cases: [(String, NoteColor?)] = [
            ("#ff0000", .red), ("rgb(212, 76, 71)", .red), ("#C00000", .red), ("#ffa500", .orange), ("#FF9900", .orange),
            ("#D9730D", .orange), ("#ffff00", .yellow), ("#FFF2CC", .yellow), ("#CB912F", .yellow), ("#00ff00", .green),
            ("#448361", .green), ("hsl(120, 60%, 35%)", .green), ("#0000ff", .blue), ("#1155cc", .blue), ("#337EA9", .blue),
            ("teal", .blue), ("#9900ff", .purple), ("purple", .purple), ("#9065B0", .purple), ("#ff00ff", .pink),
            ("#C14C8A", .pink), ("hotpink", .pink), ("#8B4513", .brown), ("#9F6B53", .brown), ("#000000", nil),
            ("#1d1c1d", nil), ("#333", nil), ("#777777", nil), ("#ffffff", nil), ("#f8f8f8", nil), ("rgb(29, 28, 29)", nil),
            ("#E9F3F7", nil)
        ]
        for (value, expected) in cases {
            let reading = NoteHTMLColor.read(value)
            let actual: NoteColor?
            if case .color(let color) = reading { actual = color } else { actual = nil }
            expect(actual == expected, "\(value) maps to \(String(describing: actual)), expected \(String(describing: expected))")
        }
        expect(NoteHTMLColor.read("transparent") == .transparent && NoteHTMLColor.read("rgba(255,0,0,0.1)") == .transparent, "transparent")
        expect(NoteHTMLColor.read("inherit") == nil, "keywords are not colours")
        expect(NoteHTMLColor.style(token: "red_background") == .background(.red) && NoteHTMLColor.style(token: "teal") == .text(.green)
               && NoteHTMLColor.style(token: "default") == nil, "Notion colour tokens")
    }
}
