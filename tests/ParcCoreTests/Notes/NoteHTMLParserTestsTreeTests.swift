import Foundation
import Testing
@testable import ParcCore

struct NoteHTMLParserTestsTreeTests {
    private func names(_ node: NoteHTMLNode) -> String {
        node.children.map { child in
            child.isText ? child.text : "<" + child.name + ">" + names(child) + "</" + child.name + ">"
        }.joined()
    }

    struct HTMLCase: Sendable, CustomTestStringConvertible {
        let testDescription: String
        let input: String
        let tree: String

        init(_ label: String, _ input: String, _ tree: String) {
            testDescription = label
            self.input = input
            self.tree = tree
        }
    }

    @Test(arguments: [
        HTMLCase("p closes p", "<p>One<p>Two",
                 "<p>One</p><p>Two</p>"),
        HTMLCase("li closes li", "<ul><li>a<li>b</ul>",
                 "<ul><li>a</li><li>b</li></ul>"),
        HTMLCase("nested lists close the right items", "<ul><li>a<ul><li>b</ul><li>c</ul>",
                 "<ul><li>a<ul><li>b</li></ul></li><li>c</li></ul>"),
        HTMLCase("dt and dd", "<dl><dt>T<dd>D<dt>U</dl>",
                 "<dl><dt>T</dt><dd>D</dd><dt>U</dt></dl>"),
        HTMLCase("implied cells and rows", "<table><tr><td>1<td>2<tr><td>3</table>",
                 "<table><tr><td>1</td><td>2</td></tr><tr><td>3</td></tr></table>"),
        HTMLCase("blocks close paragraphs", "<p>a<div>b</div>c</p>",
                 "<p>a</p><div>b</div>c"),
        HTMLCase("misnested inline tags", "<b>bold <i>both</b> after</i>",
                 "<b>bold <i>both</i></b> after"),
        HTMLCase("unclosed inline tags close with their block", "<div><span>x</div>y",
                 "<div><span>x</span></div>y"),
        HTMLCase("void elements", "a<br>b</br>c<img src=x>d<hr/>e",
                 "a<br></br>b<br></br>c<img></img>d<hr></hr>e"),
        HTMLCase("doctype, html, head and comments", "<!DOCTYPE html><html><head><title>T</title></head><body>x<!-- <p>no</p> --></body></html>",
                 "<title>T</title>x"),
        HTMLCase("script is raw text", "<script>if (a<b) { x = \"</p>\" }</script>z",
                 "<script>if (a<b) { x = \"</p>\" }</script>z"),
        HTMLCase("textarea decodes entities", "<textarea>&lt;b&gt;</textarea>",
                 "<textarea><b></textarea>"),
        HTMLCase("CDATA only in foreign content", "x<![CDATA[hidden]]>y<svg><![CDATA[shown]]></svg>",
                 "xy<svg>shown</svg>"),
        HTMLCase("stray angle brackets are text", "1 < 2 and 3 <> 4 </ >",
                 "1 < 2 and 3 <> 4 "),
        HTMLCase("tag names are case-insensitive", "<P CLASS=\"A\">Up</P>",
                 "<p>Up</p>"),
        HTMLCase("line endings normalise", "a\r\nb\rc",
                 "a\nb\nc"),
    ])
    func htmlParsesIntoTheExpectedTree(fixture: HTMLCase) {
        #expect(names(NoteHTMLParser.parse(fixture.input)) == fixture.tree)
    }

    @Test
    func wordListMarkersAreFencedOffFromItemText() {
        let word = NoteHTMLParser.parse("<p><![if !supportLists]><span>1.</span><![endif]>Item</p>")
        #expect(names(word) == "<p><#mso-marker><span>1.</span></#mso-marker>Item</p>", "Word list markers are fenced: \(names(word))")
    }

    @Test
    func unterminatedAttributesStillLeaveOneChild() {
        let unterminated = NoteHTMLParser.parse("<div class=\"open")
        #expect(unterminated.children.count == 1, "unterminated attributes do not crash")
    }
}
