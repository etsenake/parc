import Foundation
import Testing
@testable import ParcCore

@MainActor struct NoteMathParserTests {
    func parse(_ source: String) throws -> [NoteMathNode] {
        do {
            return try NoteMathParser.parse(source)
        } catch {
            throw NoteTestFailure("\(source) failed to parse: \(error.message) at \(error.offset)")
        }
    }

    func failure(_ source: String) throws -> NoteMathParseError {
        do {
            let nodes = try NoteMathParser.parse(source)
            throw NoteTestFailure("\(source) should fail but parsed as \(nodes)")
        } catch let error as NoteMathParseError {
            return error
        }
    }

    func contains(_ nodes: [NoteMathNode], _ predicate: (NoteMathNode) -> Bool) -> Bool {
        nodes.contains { node in
            if predicate(node) { return true }
            switch node {
            case .group(let content), .styled(_, let content), .classed(_, let content), .colored(_, let content),
                 .mathStyle(_, let content), .decorated(_, let content):
                return contains(content, predicate)
            case .scripts(let base, let upper, let lower):
                return contains(base.map { [$0] } ?? [], predicate) || contains(upper ?? [], predicate) || contains(lower ?? [], predicate)
            case .extensibleArrow(_, let over, let under):
                return contains(over, predicate) || contains(under ?? [], predicate)
            default:
                return false
            }
        }
    }

    func arrow(_ nodes: [NoteMathNode]) -> (String, [NoteMathNode], [NoteMathNode]?)? {
        for node in nodes {
            if case .extensibleArrow(let symbol, let over, let under) = node { return (symbol, over, under) }
            if case .group(let content) = node, let found = arrow(content) { return found }
        }
        return nil
    }

    func equation(_ source: String, display: Bool = true) throws -> NoteMathEquation {
        do {
            return try NoteMathParser.parseEquation(source, display: display)
        } catch {
            throw NoteTestFailure("\(source) failed to parse: \(error.message) at \(error.offset)")
        }
    }

    func rowTags(_ source: String) throws -> [[NoteMathNode]?] {
        guard case .environment(let environment)? = try equation(source).nodes.first else {
            throw NoteTestFailure("\(source) parses as an environment")
        }
        return environment.tags
    }

    func failure(_ source: String, display: Bool) throws -> NoteMathParseError {
        do {
            let parsed = try NoteMathParser.parseEquation(source, display: display)
            throw NoteTestFailure("\(source) should fail but parsed as \(parsed)")
        } catch let error as NoteMathParseError {
            return error
        }
    }

    @Test func katexBraketAndSets() throws {
        let x: NoteMathNode = .char("x", .ord), y: NoteMathNode = .char("y", .ord)
        #expect(try parse("\\bra{x}") == [.classed(.inner, [.char("⟨", .open), x, .char("|", .close)])], "bra")
        #expect(try parse("\\ket{x}") == [.classed(.inner, [.char("|", .open), x, .char("⟩", .close)])], "ket")
        #expect(try parse("\\braket{x}") == [.classed(.inner, [.char("⟨", .open), x, .char("⟩", .close)])], "braket")
        #expect(try parse("\\Bra{x}") == [.fenced(left: "⟨", right: "|", middles: [], segments: [[x]])], "Bra")
        #expect(try parse("\\Ket{x}") == [.fenced(left: "|", right: "⟩", middles: [], segments: [[x]])], "Ket")
        let thin = NoteMathNode.space(3.0 / 18)
        #expect(try parse("\\Braket{x|y}") == [.fenced(left: "⟨", right: "⟩", middles: ["|"], segments: [[x, thin], [thin, y]])], "Braket splits at bars")
        #expect(try parse("\\set{x|y}") == [.group([.char("{", .open), thin, x, .char("∣", .rel), y, thin, .char("}", .close)])], "set uses mid")
        guard case .fenced("{", "}", let middles, let segments) = try parse("\\Set{x|y|z}")[0] else { Issue.record("Set is fenced"); return }
        #expect(middles == ["|"] && segments.count == 2, "Set splits only the first bar")
        for name in ["bra", "ket", "braket", "Bra", "Ket", "Braket", "set", "Set"] { #expect(NoteMathParser.isBuiltIn(name), "\\\(name) is built in") }
    }

    @Test func katexTextMode() throws {
        #expect(try parse("\\text{\\'e\\`a\\^o\\~n\\=u\\u{a}\\.z\\\"o\\r a\\H o\\v c}") == [.text("éàôñūăżöåőč", .roman)], "text accents compose")
        #expect(try parse("\\text{\\'{\\i}}") == [.text("ı\u{0301}", .roman)], "accents sit on dotless i")
        #expect(try parse("\\text{a \\textbf{b} c}") == [.group([.text("a ", .roman), .text("b", .bold), .text(" c", .roman)])], "nested text styles")
        #expect(try parse("\\text{a {\\bf b} c}") == [.group([.text("a ", .roman), .text("b", .bold), .text(" c", .roman)])], "text switches stop at the brace")
        let red = NoteMathSymbols.color(named: "red")!
        #expect(try parse("\\text{a {\\color{red} b}}") == [.group([.text("a ", .roman), .colored(red, [.text(" b", .roman)])])], "color in text")
        #expect(try parse("\\text{\\textcolor{red}{b}}") == [.group([.colored(red, [.text("b", .roman)])])], "textcolor in text")
        #expect(try parse("\\text{\\tiny a}") == [.group([.sized(0.5, [.text("a", .roman)])])], "sizes in text")
        #expect(try parse("\\text{\\textdollar\\textless\\textunderscore\\textquotedblleft\\pounds\\aa\\ss\\o}") == [.text("$<_“£åßø", .roman)], "text symbols")
        #expect(try parse("\\text{a---b--c ``q'' it's}") == [.text("a—b–c “q” it’s", .roman)], "text ligatures")
        #expect(try parse("\\texttt{a--b}") == [.text("a--b", .monospace)], "typewriter text keeps its dashes")
        #expect(try parse("\\text{a~b}") == [.text("a\u{00A0}b", .roman)], "tie is a no-break space")
        #expect(try parse("\\text{a\\hspace{1em}b}") == [.group([.text("a", .roman), .space(1), .text("b", .roman)])], "spacing in text")
        #expect(try parse("\\text{\\href{https://a.b}{go}}") == [.group([.link("https://a.b", [.text("go", .roman)])])], "href in text")
        #expect(try parse("\\text{\\textcircled{a}}") == [.text("ⓐ", .roman)], "textcircled")
        #expect(try parse("\\text{\\underline{a}}") == [.group([.decorated(.underline, [.text("a", .roman)])])], "underline in text")
        #expect(try parse("\\text{\\(x\\)}") == [.group([.mathStyle(.text, [.char("x", .ord)])])], "paren math in text")
        #expect(try parse("\\text{\\KaTeX}").count == 1 && parse("\\text{\\verb|a|}").count == 1, "logos and verb in text")
        #expect(try failure("\\text{\\(x}").message.hasPrefix("Missing \\) to close"), "unclosed paren math")
        #expect(try failure("x \\)").message == "\\) without a matching \\(", "stray close paren math")
    }

    @Test func katexStretchyMarks() throws {
        let ab: [NoteMathNode] = [.char("A", .ord), .char("B", .ord)]
        #expect(try parse("\\utilde{AB}") == [.decorated(.underArrow("\u{0330}"), ab)], "utilde")
        #expect(try parse("\\Overrightarrow{AB}") == [.decorated(.overArrow("\u{21D2}"), ab)], "Overrightarrow")
        #expect(try parse("\\overleftharpoon{AB}") == [.decorated(.overArrow("\u{21BC}"), ab)], "overleftharpoon")
        #expect(try parse("\\overrightharpoon{AB}") == [.decorated(.overArrow("\u{21C0}"), ab)], "overrightharpoon")
        #expect(try parse("\\overlinesegment{AB}") == [.decorated(.lineSegment(true), ab)], "overlinesegment")
        #expect(try parse("\\underlinesegment{AB}") == [.decorated(.lineSegment(false), ab)], "underlinesegment")
        #expect(try parse("\\phase{AB}") == [.decorated(.phase, ab)], "phase")
        #expect(try parse("\\angl{n}") == [.decorated(.actuarialAngle, [.char("n", .ord)])] && parse("\\angln") == parse("\\angl{n}"), "angl")
        #expect(try parse("\\underbar{ab}") == [.decorated(.underline, [.text("ab", .roman)])], "underbar underlines text")
        #expect(try parse("\\xlongequal{a}") == [.extensibleArrow("=", over: [.char("a", .ord)], under: nil)], "xlongequal")
        #expect(try parse("\\xtwoheadrightarrow{a}") == [.extensibleArrow("↠", over: [.char("a", .ord)], under: nil)], "xtwoheadrightarrow")
        #expect(try parse("\\xtwoheadleftarrow[b]{a}") == [.extensibleArrow("↞", over: [.char("a", .ord)], under: [.char("b", .ord)])], "xtwoheadleftarrow")
    }

    @Test func katexSymbolsAndShorthands() throws {
        let names = """
            maltese Vvdash nvdash nvDash nVdash nVDash minuso ratio shortmid nshortmid shortparallel nshortparallel mathellipsis \
            vcentcolon dblcolon coloneqq Coloneqq coloneq Coloneq eqqcolon Eqqcolon eqcolon Eqcolon approxcolon Approxcolon \
            simcolon Simcolon colonapprox Colonapprox colonsim Colonsim approxcoloncolon simcoloncolon colondash Colondash \
            dashcolon Dashcolon lt gt doteqdot Doteq origof imageof llless gggtr lessgtr gtrless lesseqgtr gtreqless lesseqqgtr \
            gtreqqless lessdot gtrdot lessapprox gtrapprox lneqq gneqq lvertneqq gvertneqq lnsim gnsim lnapprox gnapprox \
            nleqslant ngeqslant nleqq ngeqq precsim succsim precapprox succapprox preccurlyeq succcurlyeq curlyeqprec \
            curlyeqsucc precneqq succneqq precnsim succnsim precnapprox succnapprox nprec nsucc npreceq nsucceq subseteqq \
            supseteqq subsetneqq supsetneqq varsubsetneq varsupsetneq varsubsetneqq varsupsetneqq nsubseteqq nsupseteqq notni \
            backepsilon backsimeq eqcirc circeq bumpeq Bumpeq smallsmile smallfrown vartriangle ntriangleleft ntriangleright \
            ntrianglelefteq ntrianglerighteq blacktriangleleft blacktriangleright eqslantless eqslantgtr leftthreetimes \
            rightthreetimes doublebarwedge Cap Cup doublecap doublecup bigcirc And darr dArr Darr lang rang uarr uArr Uarr harr \
            hArr Harr larr lArr Larr rarr rArr Rarr lrarr lrArr Lrarr alef alefsym clubs cnums Dagger diamonds empty exist hearts \
            image isin plusmn real sdot sect spades sub sube supe thetasym weierp bull leftrightsquigarrow looparrowleft \
            looparrowright restriction Lleftarrow Rrightarrow arctg arcctg ch cosec cotg ctg cth sh tg th mathstrut nobreak \
            allowbreak relax KaTeX LaTeX TeX lparen rparen textbackslash
            """.split(whereSeparator: \.isWhitespace).filter { $0 != "\\" }
        for name in names {
            #expect(NoteMathParser.isBuiltIn(String(name)), "\\\(name) is built in")
            _ = try parse("\\\(name)")
        }
        #expect(try parse("a \\lt b") == [.char("a", .ord), .char("<", .rel), .char("b", .ord)], "lt is a relation")
        #expect(try parse("\\Coloneq") == [.classed(.rel, [.char("\u{2237}", .ord), .space(-1.2 / 18), .char("\u{2212}", .ord)])], "colon pairs kern together")
        #expect(try parse("\\char\"263A \\char65 \\char`b \\char'101") == [.char("☺", .ord), .char("A", .ord), .char("b", .ord), .char("A", .ord)], "char reads hex, decimal, backtick and octal codes")
        #expect(try parse("\\verb|x_1 \\y|") == [.text("x_1 \\y", .monospace)], "verb keeps its text")
        #expect(try parse("\\verb*|a b|") == [.text("a\u{2423}b", .monospace)], "verb star shows spaces")
        #expect(try failure("\\verb|abc").message.hasPrefix("\\verb never finds"), "unclosed verb")
        #expect(try parse("\\TextOrMath{t}{m}") == [.group([.char("m", .ord)])], "TextOrMath picks math")
        #expect(try parse("\\htmlClass{big}{x}") == [.group([.char("x", .ord)])], "html wrappers keep their content")
        #expect(try parse("\\mathchoice{a}{b}{c}{d}") == [.choice([[.char("a", .ord)], [.char("b", .ord)], [.char("c", .ord)], [.char("d", .ord)]])], "mathchoice keeps four branches")
        #expect(try parse("\\vcenter{x}") == [.vcenter([.char("x", .ord)])], "vcenter")
        #expect(try parse("\\relax x") == [.space(0), .char("x", .ord)], "relax does nothing")
        #expect(try parse("\\bold{x}") == [.styled(.bold, [.char("x", .ord)])], "bold is mathbf")
        #expect(try parse("\\frak{g}") == [.styled(.fraktur, [.char("g", .ord)])], "frak is mathfrak")
        guard case .operatorName(let lim, .auto) = try parse("\\varlimsup")[0], case .decorated(.overline, _) = lim[0] else {
            Issue.record("varlimsup is an overlined lim")
            return
        }
        guard case .classed(.bin, _) = try parse("\\pmb{+}")[0] else { Issue.record("pmb keeps a binary class"); return }
        #expect(abs(NoteMathParser.dimension("1px")! - 0.100375) < 1e-12 && abs(NoteMathParser.dimension("1ex")! - 0.431) < 1e-12, "px and ex match KaTeX")
        #expect(abs(NoteMathParser.dimension("10dd")! - 1.0700086430423511) < 1e-9 && abs(NoteMathParser.dimension("65536sp")! - 0.1) < 1e-12, "dd and sp units")
        #expect(NoteMathParser.dimension("1cc") != nil && NoteMathParser.dimension("1nd") != nil && NoteMathParser.dimension("1nc") != nil, "cc, nd and nc units")
        #expect(try parse("\\left\\lparen x \\right\\rang").count == 1, "new delimiter names work with left and right")
    }

    @Test func katexBoxesSizesAndLinks() throws {
        #expect(try parse("a \\Huge b c") == [.char("a", .ord), .sized(2.488, [.char("b", .ord), .char("c", .ord)])], "size switches cover the rest")
        #expect(try parse("{\\tiny x} y") == [.group([.sized(0.5, [.char("x", .ord)])]), .char("y", .ord)], "size switches stop at the brace")
        let sizes = ["tiny": 0.5, "scriptsize": 0.7, "footnotesize": 0.8, "small": 0.9, "normalsize": 1.0, "large": 1.2,
                     "Large": 1.44, "LARGE": 1.728, "huge": 2.074, "Huge": 2.488]
        for (name, factor) in sizes { #expect(try parse("\\\(name) x") == [.sized(factor, [.char("x", .ord)])], "\\\(name) is \(factor)") }
        #expect(try parse("\\raisebox{0.25em}{hi}") == [.raised(0.25, [.text("hi", .roman)])], "raisebox lifts text")
        #expect(try parse("\\raisebox{-.1em}{$x$}") == [.raised(-0.1, [.mathStyle(.text, [.char("x", .ord)])])], "raisebox takes math in dollars")
        #expect(try parse("\\smash{y}") == [.smashed([.char("y", .ord)], top: true, bottom: true)], "smash flattens both sides")
        #expect(try parse("\\smash[t]{y}") == [.smashed([.char("y", .ord)], top: true, bottom: false)], "smash t keeps depth")
        #expect(try parse("\\smash[b]{y}") == [.smashed([.char("y", .ord)], top: false, bottom: true)], "smash b keeps height")
        #expect(try failure("\\smash[x]{y}").message == "\\smash takes [t] or [b], not [x]", "smash rejects other options")
        #expect(try parse("\\sum_{\\substack{i<n\\\\j}}") == [.scripts(base: .largeOperator("\u{2211}", .auto), superscript: nil,
               subscript: [.substack([[.char("i", .ord), .char("<", .rel), .char("n", .ord)], [.char("j", .ord)]])])], "substack splits rows")
        #expect(try failure("\\substack{a").message == "Missing } to close this {", "unclosed substack")
        guard case .fraction(let general) = try parse("\\genfrac(]{0pt}{2}{a}{b}")[0] else { Issue.record("genfrac is a fraction"); return }
        #expect(general.left == "(" && general.right == "]" && !general.hasRule && general.level == .script, "genfrac reads delimiters, rule and style")
        guard case .fraction(let thick) = try parse("\\genfrac{}{}{2pt}{}{a}{b}")[0] else { Issue.record("genfrac thickness"); return }
        #expect(thick.hasRule && thick.thickness == 0.2 && thick.left == nil && thick.level == nil, "genfrac keeps a custom rule")
        guard case .fraction(let curly) = try parse("\\genfrac{\\{}{\\}}{}{0}{a}{b}")[0] else { Issue.record("genfrac curly"); return }
        #expect(curly.left == "{" && curly.right == "}" && curly.level == .display, "genfrac takes brace delimiters")
        #expect(try failure("\\genfrac(){}{7}{a}{b}").message.hasPrefix("\\genfrac styles"), "bad genfrac style")
        let red = NoteMathSymbols.color(named: "red")!, blue = NoteMathSymbols.color(named: "blue")!
        #expect(try parse("\\colorbox{red}{hi}") == [.colorBox(red, frame: nil, [.text("hi", .roman)])], "colorbox")
        #expect(try parse("\\fcolorbox{blue}{red}{a $x$}") == [.colorBox(red, frame: blue, [.text("a ", .roman), .mathStyle(.text, [.char("x", .ord)])])], "fcolorbox takes frame then background")
        #expect(try parse("\\href{https://katex.org/}{x}") == [.link("https://katex.org/", [.char("x", .ord)])], "href wraps math")
        #expect(try parse("\\url{https://a.b/c\\#d\\_e}") == [.link("https://a.b/c#d_e", [.text("https://a.b/c#d_e", .monospace)])], "url unescapes")
        #expect(try failure("\\url{}").message.hasPrefix("\\url needs a link"), "empty url")
        #expect(try parse("\\rule[0.1em]{1em}{2pt}") == [.rule(width: 1, height: 0.2, raise: 0.1)], "rule with a lift")
        #expect(try parse("\\overgroup{AB}") == [.decorated(.overArrow("\u{23E0}"), [.char("A", .ord), .char("B", .ord)])], "overgroup")
        #expect(try parse("\\undergroup{AB}") == [.decorated(.underArrow("\u{23E1}"), [.char("A", .ord), .char("B", .ord)])], "undergroup")
        for name in ["tiny", "Huge", "raisebox", "smash", "substack", "genfrac", "colorbox", "fcolorbox", "href", "url", "overgroup", "tripledash"] {
            #expect(NoteMathParser.isBuiltIn(name), "\\\(name) is built in")
        }
        let wavy = String(describing: try parse("\\ce{A\\bond{~-}B}"))
        #expect(wavy.contains("raised(-0.1") && wavy.contains("sized(0.5"), "a dashed bond stacks a raised line over a tiny triple dash")
        for bond in ["~", "~-", "~=", "~--", "-~-", "...", "...."] { _ = try parse("\\ce{C\\bond{\(bond)}C}") }
    }

    @Test func alignatTakesItsColumnPairs() throws {
        guard case .environment(let alignat)? = try parse("\\begin{alignat}{2} a &= b & c &= d \\\\ e &= f \\end{alignat}").first else {
            Issue.record("alignat parses")
            return
        }
        #expect(alignat.kind == .alignedAt && alignat.columns == [.right, .left, .right, .left], "alignat takes its column pairs")
        #expect(alignat.tags == [[.text("(1)", .roman)], [.text("(2)", .roman)]], "alignat numbers every row: \(alignat.tags)")
        guard case .environment(let alignedat)? = try parse("\\begin{alignedat}{1} a &= b \\end{alignedat}").first else {
            Issue.record("alignedat parses")
            return
        }
        #expect(alignedat.kind == .alignedAt && alignedat.tags.isEmpty, "alignedat never numbers")
        #expect(try parse("\\begin{alignat*}{1} a &= b \\\\ c &= d \\end{alignat*}").first.map { node in
            if case .environment(let environment) = node { return environment.tags.isEmpty }
            return false
        } == true, "alignat* stays unnumbered")
        #expect(try failure("\\begin{alignat}{1} a &= b & c \\end{alignat}").message.contains("more columns"), "alignat caps the pairs")
        #expect(try failure("\\begin{alignat}{x} a \\end{alignat}").message.contains("column pairs"), "alignat needs a count")
        guard case .environment(let multline)? = try parse("\\begin{multline} a + b \\\\ c \\label{long} \\\\ d \\end{multline}").first else {
            Issue.record("multline parses")
            return
        }
        #expect(multline.kind == .multline && multline.rows.count == 3, "multline keeps its lines")
        #expect(multline.tags == [nil, nil, [.text("(1)", .roman)]], "multline takes one number on its last line: \(multline.tags)")
        guard case .environment(let quiet)? = try parse("\\begin{multline*} a \\\\ b \\\\ \\end{multline*}").first else {
            Issue.record("multline* parses")
            return
        }
        #expect(quiet.tags.isEmpty && quiet.rows.count == 2, "multline* stays unnumbered and drops a trailing break")
        guard case .environment(let tagged)? = try parse("\\begin{multline} a \\tag{M} \\\\ b \\end{multline}").first else {
            Issue.record("tagged multline parses")
            return
        }
        #expect(tagged.tags.count == 2 && tagged.tags[0] == nil && tagged.tags[1] != nil, "a multline tag lands on the last line")
        #expect(try failure("\\begin{multline} a & b \\end{multline}").message.contains("doesn't use &"), "multline has one column")
        guard case .environment(let subarray)? = try parse("\\begin{subarray}{l} i < n \\\\ j < m \\end{subarray}").first else {
            Issue.record("subarray parses")
            return
        }
        #expect(subarray.kind == .subarray && subarray.columns == [.left] && subarray.rows.count == 2, "subarray is one left column")
        #expect(try failure("\\begin{subarray}{cc} a \\end{subarray}").message.contains("single column"), "subarray takes one column")
        #expect(try failure("\\begin{subarray}{r} a \\end{subarray}").message.contains("single column"), "subarray takes only c or l")
        #expect(try failure("\\begin{subarray}{c} a & b \\end{subarray}").message.contains("more columns"), "subarray rejects &")
        guard case .environment(let dcases)? = try parse("\\begin{dcases} \\frac12 & x > 0 \\end{dcases}").first,
              case .environment(let drcases)? = try parse("\\begin{drcases} a & b \\end{drcases}").first,
              case .environment(let darray)? = try parse("\\begin{darray}{rl} a & b \\end{darray}").first,
              case .environment(let plainCases)? = try parse("\\begin{cases} a & b \\end{cases}").first else {
            Issue.record("display-style environments parse")
            return
        }
        #expect(dcases.kind == .cases && dcases.displayCells && dcases.left == "{" && dcases.columns == [.left, .left], "dcases")
        #expect(drcases.kind == .cases && drcases.displayCells && drcases.right == "}" && drcases.left == nil, "drcases")
        #expect(darray.kind == .array && darray.displayCells && darray.columns == [.right, .left], "darray")
        #expect(!plainCases.displayCells, "cases stays text style")
        guard case .environment(let starred)? = try parse("\\begin{pmatrix*}[r] 1 & -1 \\\\ -10 & 2 \\end{pmatrix*}").first,
              case .environment(let centred)? = try parse("\\begin{bmatrix*} 1 & 2 \\end{bmatrix*}").first else {
            Issue.record("starred matrices parse")
            return
        }
        #expect(starred.kind == .matrix && starred.left == "(" && starred.columns == [.right, .right], "pmatrix* lines columns up")
        #expect(centred.left == "[" && centred.columns == [.center, .center], "matrix* defaults to centred")
        #expect(try failure("\\begin{Vmatrix*}[x] 1 \\end{Vmatrix*}").message.contains("[l], [c] or [r]"), "matrix* checks its alignment")
        guard case .environment(let dashed)? = try parse("\\begin{array}{c:c|c} a & b & c \\\\ \\hdashline d & e & f \\\\ \\hline \\end{array}").first else {
            Issue.record("dashed array parses")
            return
        }
        #expect(dashed.columnRules == [1, 2] && dashed.columnRuleDashes == [true, false], "colons draw dashed columns")
        #expect(dashed.rowRules == [1, 2] && dashed.rowRuleDashes == [true, false], "hdashline draws a dashed row rule")
    }

    @Test func cdKeepsObjectAndArrowRows() throws {
        let source = "\\begin{CD} A @>a>b> B \\\\ @VcVdV @AAA \\\\ C @<<< D @= E \\\\ @| @. \\\\ \\end{CD}"
        guard case .environment(let diagram)? = try parse(source).first else { Issue.record("CD parses"); return }
        #expect(diagram.kind == .commutativeDiagram && diagram.rows.count == 4 && diagram.arrows.count == 4, "CD keeps object and arrow rows")
        #expect(try diagram.rows[0].count == 3 && diagram.rows[0][0] == parse("A") && diagram.rows[0][2] == parse("B"), "objects sit between arrows")
        #expect(try diagram.arrows[0][1] == NoteMathDiagramArrow(direction: .right, first: parse("a"), second: parse("b")), "@>a>b> puts a above and b below: \(diagram.arrows[0])")
        #expect(diagram.arrows[0][0] == nil && diagram.arrows[0][2] == nil, "object cells aren't arrows")
        #expect(try diagram.arrows[1].count == 3 && diagram.arrows[1][0] == NoteMathDiagramArrow(direction: .down, first: parse("c"), second: parse("d")), "@VcVdV labels both sides: \(diagram.arrows[1])")
        #expect(diagram.arrows[1][2]?.direction == .up && diagram.arrows[1][1] == nil, "@AAA points up under the next object")
        #expect(diagram.arrows[2][1]?.direction == .left && diagram.arrows[2][3]?.direction == .equals, "@<<< and @=")
        #expect(diagram.arrows[3][0]?.direction == .parallel && diagram.arrows[3][2]?.direction == .empty, "@| and @.")
        #expect(diagram.columns == Array(repeating: .center, count: 5), "CD centres every column")
        #expect((try? NoteMathParser.parseEquation(source, display: true).automaticNumbers) == 0, "CD never takes a number")
        #expect(try failure("\\begin{CD} A @>a B \\end{CD}").message.contains("needs another >"), "an unfinished arrow says so")
        #expect(try failure("\\begin{CD} A @>a @>>> B \\end{CD}").message.contains("needs another >"), "a new arrow can't start inside a label")
        #expect(try failure("\\begin{CD} A @x B \\end{CD}").message.contains("follow it with"), "unknown arrow letters explain themselves")
        #expect(try failure("\\begin{CD} A @>>> B").message == "Missing \\end{CD}", "an unclosed CD")
        #expect(try failure("\\begin{CD} A \\end{matrix}").message.contains("ends with"), "mismatched CD end")
    }

    @Test func atomsAndClasses() throws {
        #expect(try parse("\\alpha + \\beta") == [.char("α", .ord), .char("+", .bin), .char("β", .ord)], "Greek letters and a binary plus")
        #expect(try parse("a-b") == [.char("a", .ord), .char("\u{2212}", .bin), .char("b", .ord)], "hyphen becomes a minus sign")
        #expect(try parse("x \\leq y") == [.char("x", .ord), .char("≤", .rel), .char("y", .ord)], "relations")
        #expect(try parse("f(x), y") == [.char("f", .ord), .char("(", .open), .char("x", .ord), .char(")", .close),
                                     .char(",", .punct), .char("y", .ord)], "open, close and punctuation")
        #expect(try parse("\\varepsilon\\epsilon\\varphi\\phi") == [.char("ε", .ord), .char("ϵ", .ord), .char("φ", .ord), .char("ϕ", .ord)], "Greek variants follow TeX")
        #expect(try parse("\\Gamma\\varGamma") == [.char("Γ", .ord), .styled(.italic, [.char("Γ", .ord)])], "upright and italic capitals")
        #expect(try parse("\\infty \\partial \\nabla \\forall \\exists") == [.char("∞", .ord), .char("∂", .ord), .char("∇", .ord),
                                                                         .char("∀", .ord), .char("∃", .ord)], "ordinary symbols")
        #expect(try parse("\\cdot\\times\\div\\pm\\mp\\cup\\cap") == ["⋅", "×", "÷", "±", "∓", "∪", "∩"].map { .char($0, .bin) }, "binary operators")
        #expect(try parse("\\neq\\approx\\equiv\\sim\\propto\\in\\notin\\subset\\subseteq") ==
               ["≠", "≈", "≡", "∼", "∝", "∈", "∉", "⊂", "⊆"].map { .char($0, .rel) }, "relations table")
        #expect(try parse("\\to\\Rightarrow\\iff\\mapsto\\leftarrow") == ["→", "⇒", "⟺", "↦", "←"].map { .char($0, .rel) }, "arrows")
        #expect(try parse("α≤β") == [.char("α", .ord), .char("≤", .rel), .char("β", .ord)], "typed Unicode keeps its class")
        #expect(try parse("∑") == [.largeOperator("∑", .auto)], "typed big operators stay big")
        #expect(try parse("\\{\\}\\|\\%") == [.char("{", .open), .char("}", .close), .char("‖", .ord), .char("%", .ord)], "escaped characters")
        #expect(try parse("\\ldots\\cdots\\vdots") == [.char("…", .inner), .char("⋯", .inner), .char("⋮", .ord)], "dots")
        #expect(try parse("  x   % a comment\n y ") == [.char("x", .ord), .char("y", .ord)], "spaces and comments vanish")
        #expect(try parse("").isEmpty, "empty formula")
    }

    @Test func scriptsAndPrimes() throws {
        #expect(try parse("x^2") == [.scripts(base: .char("x", .ord), superscript: [.char("2", .ord)], subscript: nil)], "superscript")
        #expect(try parse("x_i^2") == parse("x^2_i"), "script order doesn't matter")
        #expect(try parse("x_{ij}") == [.scripts(base: .char("x", .ord), superscript: nil, subscript: [.char("i", .ord), .char("j", .ord)])], "grouped subscript")
        #expect(try parse("f'") == [.scripts(base: .char("f", .ord), superscript: [.char("′", .ord)], subscript: nil)], "prime")
        #expect(try parse("f''") == [.scripts(base: .char("f", .ord), superscript: [.char("″", .ord)], subscript: nil)], "double prime")
        #expect(try parse("f'^2") == [.scripts(base: .char("f", .ord), superscript: [.char("′", .ord), .char("2", .ord)], subscript: nil)], "prime then superscript merge")
        #expect(try parse("f'_1") == [.scripts(base: .char("f", .ord), superscript: [.char("′", .ord)], subscript: [.char("1", .ord)])], "prime then subscript")
        #expect(try parse("^2") == [.scripts(base: nil, superscript: [.char("2", .ord)], subscript: nil)], "script with no base")
        #expect(try parse("x^\\alpha") == [.scripts(base: .char("x", .ord), superscript: [.char("α", .ord)], subscript: nil)], "command as a script")
        #expect(try parse("e^\\frac12").count == 1, "TeX-style unbraced fraction in a script")
        #expect(try parse("{x^2}^3").count == 1, "braced base takes another superscript")
    }

    @Test func fractionsAndRadicals() throws {
        #expect(try parse("\\frac{a}{b}") == [.fraction(NoteMathFraction(numerator: [.char("a", .ord)], denominator: [.char("b", .ord)]))], "fraction")
        #expect(try parse("\\frac12") == [.fraction(NoteMathFraction(numerator: [.char("1", .ord)], denominator: [.char("2", .ord)]))], "unbraced fraction")
        if case .fraction(let display)? = try parse("\\dfrac ab").first { #expect(display.level == .display, "dfrac forces display") }
        if case .fraction(let text)? = try parse("\\tfrac ab").first { #expect(text.level == .text, "tfrac forces text") }
        if case .fraction(let binom)? = try parse("\\binom{n}{k}").first {
            #expect(!binom.hasRule && binom.left == "(" && binom.right == ")", "binom has parens and no rule")
        } else {
            Issue.record("binom parses as a fraction")
            return
        }
        #expect(try parse("{a \\over b}") == [.group([.fraction(NoteMathFraction(numerator: [.char("a", .ord)], denominator: [.char("b", .ord)]))])], "infix over")
        #expect(try parse("\\sqrt{x}") == [.radical([.char("x", .ord)], degree: nil)], "square root")
        #expect(try parse("\\sqrt[3]{x}") == [.radical([.char("x", .ord)], degree: [.char("3", .ord)])], "cube root")
        #expect(try parse("\\sqrt[n]2") == [.radical([.char("2", .ord)], degree: [.char("n", .ord)])], "unbraced radicand")
    }

    @Test func operatorsAndFunctions() throws {
        #expect(try parse("\\sum_{i=1}^n") == [.scripts(base: .largeOperator("∑", .auto), superscript: [.char("n", .ord)],
                                                    subscript: [.char("i", .ord), .char("=", .rel), .char("1", .ord)])], "sum with limits")
        #expect(try parse("\\int_0^1") == [.scripts(base: .largeOperator("∫", .beside), superscript: [.char("1", .ord)],
                                                subscript: [.char("0", .ord)])], "integrals keep limits beside")
        #expect(try parse("\\int\\limits_0^1").first.map { node in
            if case .scripts(.largeOperator("∫", .above)?, _, _) = node { return true }
            return false
        } == true, "\\limits stacks integral limits")
        #expect(try parse("\\sum\\nolimits_i") == [.scripts(base: .largeOperator("∑", .beside), superscript: nil, subscript: [.char("i", .ord)])], "\\nolimits")
        #expect(try parse("\\iint\\oint\\bigcup\\prod") == [.largeOperator("∬", .beside), .largeOperator("∮", .beside),
                                                       .largeOperator("⋃", .auto), .largeOperator("∏", .auto)], "more big operators")
        #expect(try parse("\\lim_{x\\to0}").first == .scripts(base: .function("lim", .auto), superscript: nil,
                                                          subscript: [.char("x", .ord), .char("→", .rel), .char("0", .ord)]), "lim")
        #expect(try parse("\\sin x") == [.function("sin", .beside), .char("x", .ord)], "sin")
        #expect(try parse("\\max\\log\\ln\\exp") == [.function("max", .auto), .function("log", .beside), .function("ln", .beside),
                                               .function("exp", .beside)], "function names")
        #expect(try parse("\\operatorname{Tr} A") == [.operatorName([.char("T", .ord), .char("r", .ord)], .beside), .char("A", .ord)], "operatorname")
        #expect(try parse("\\operatorname*{argmax}_x").first.map { node in
            if case .scripts(.operatorName(_, .auto)?, nil, _) = node { return true }
            return false
        } == true, "operatorname star takes limits")
        #expect(try parse("a \\bmod b").count == 3, "bmod")
    }

    @Test func leftRight() throws {
        #expect(try parse("\\left( x \\right)") == [.fenced(left: "(", right: ")", middles: [], segments: [[.char("x", .ord)]])], "left right")
        #expect(try parse("\\left\\{ x \\middle| y \\right.") == [.fenced(left: "{", right: nil, middles: ["|"],
                                                                     segments: [[.char("x", .ord)], [.char("y", .ord)]])], "middle and null")
        #expect(try parse("\\left\\langle a \\right\\rangle") == [.fenced(left: "⟨", right: "⟩", middles: [], segments: [[.char("a", .ord)]])], "angle brackets")
        #expect(try parse("\\left\\lfloor a \\right\\rceil").first == .fenced(left: "⌊", right: "⌉", middles: [], segments: [[.char("a", .ord)]]), "floor and ceiling")
        #expect(try parse("\\left| a \\right\\|").first == .fenced(left: "|", right: "‖", middles: [], segments: [[.char("a", .ord)]]), "bars")
        #expect(try parse("\\left[ a \\right]^2").first.map { node in
            if case .scripts(.fenced?, _, nil) = node { return true }
            return false
        } == true, "fence takes scripts")
        #expect(try parse("\\bigl( x \\bigr)") == [.sizedDelimiter("(", size: 1, kind: .open), .char("x", .ord),
                                              .sizedDelimiter(")", size: 1, kind: .close)], "big delimiters")
        #expect(try parse("\\Bigg\\uparrow") == [.sizedDelimiter("↑", size: 4, kind: .ord)], "Bigg arrow")
    }

    @Test func pmatrixDelimiters() throws {
        guard case .environment(let matrix)? = try parse("\\begin{pmatrix} a & b \\\\ c & d \\end{pmatrix}").first else {
            Issue.record("pmatrix parses")
            return
        }
        #expect(matrix.kind == .matrix && matrix.left == "(" && matrix.right == ")", "pmatrix delimiters")
        #expect(matrix.rows.count == 2 && matrix.rows.allSatisfy { $0.count == 2 }, "2 by 2 matrix")
        #expect(matrix.columns == [.center, .center], "matrix columns centre")
        for (name, left, right) in [("bmatrix", "[", "]"), ("Bmatrix", "{", "}"), ("vmatrix", "|", "|"), ("Vmatrix", "‖", "‖")] {
            guard case .environment(let environment)? = try parse("\\begin{\(name)}1\\end{\(name)}").first else {
                Issue.record("\(name) parses")
                return
            }
            #expect(environment.left == left && environment.right == right, "\(name) delimiters")
        }
        guard case .environment(let trailing)? = try parse("\\begin{matrix} 1 \\\\ 2 \\\\ \\end{matrix}").first else {
            Issue.record("trailing row break parses")
            return
        }
        #expect(trailing.rows.count == 2, "a trailing \\\\ doesn't add a row")
        guard case .environment(let cases)? = try parse("f(x) = \\begin{cases} 1 & x > 0 \\\\ 0 & \\text{otherwise} \\end{cases}").last else {
            Issue.record("cases parses")
            return
        }
        #expect(cases.kind == .cases && cases.left == "{" && cases.right == nil && cases.columns == [.left, .left], "cases shape")
        guard case .environment(let aligned)? = try parse("\\begin{aligned} a &= b \\\\ &= c \\end{aligned}").first else {
            Issue.record("aligned parses")
            return
        }
        #expect(aligned.columns == [.right, .left] && aligned.rows[1][0].isEmpty, "aligned alternates right and left")
        #expect(try parse("\\begin{align*} x &= 1 \\end{align*}").count == 1, "align*")
        guard case .environment(let gathered)? = try parse("\\begin{gathered} a \\\\ b \\end{gathered}").first else {
            Issue.record("gathered parses")
            return
        }
        #expect(gathered.kind == .gathered && gathered.rows.count == 2, "gathered")
        guard case .environment(let array)? = try parse("\\begin{array}{|c|l|} \\hline a & b \\\\[2pt] \\hline c & d \\\\ \\hline \\end{array}").first else {
            Issue.record("array parses")
            return
        }
        #expect(array.columns == [.center, .left] && array.columnRules == [0, 1, 2], "array spec with rules")
        #expect(array.rowRules == [0, 1, 2] && array.rows.count == 2, "array hlines")
        #expect(array.rowSpacing[0] == 0.2, "row spacing after \\\\[2pt]")
    }

    @Test func fontsTextAndColour() throws {
        #expect(try parse("\\mathbb{R}") == [.styled(.doubleStruck, [.char("R", .ord)])], "blackboard bold")
        #expect(try parse("\\mathcal{L}\\mathfrak{g}\\mathsf{x}\\mathtt{y}\\mathrm{d}\\mathbf{v}\\mathit{w}\\boldsymbol{\\mu}") == [
            .styled(.script, [.char("L", .ord)]), .styled(.fraktur, [.char("g", .ord)]), .styled(.sansSerif, [.char("x", .ord)]),
            .styled(.monospace, [.char("y", .ord)]), .styled(.roman, [.char("d", .ord)]), .styled(.bold, [.char("v", .ord)]),
            .styled(.italic, [.char("w", .ord)]), .styled(.boldItalic, [.char("μ", .ord)]),
        ], "font commands")
        #expect(try parse("\\text{if } x") == [.text("if ", .roman), .char("x", .ord)], "text keeps its spaces")
        #expect(try parse("\\text{a  {b}\\%}") == [.text("a b%", .roman)], "text collapses spaces and unescapes")
        #expect(try parse("\\textbf{Hi}") == [.text("Hi", .bold)], "bold text")
        #expect(try parse("\\text{for $x>0$}").first.map { node in
            if case .group(let parts) = node, parts.count == 2, case .mathStyle(.text, let math) = parts[1] { return math.count == 3 }
            return false
        } == true, "inline math inside text")
        let red = NoteMathColor(red: 1, green: 0, blue: 0)
        #expect(try parse("a \\color{red} b + c") == [.char("a", .ord), .colored(red, [.char("b", .ord), .char("+", .bin), .char("c", .ord)])], "colour switch covers the rest of the group")
        #expect(try parse("\\textcolor{#00f}{y} z") == [.colored(NoteMathColor(red: 0, green: 0, blue: 1), [.char("y", .ord)]), .char("z", .ord)], "textcolor with short hex")
        #expect(try parse("\\color{FF8000}x") == [.colored(NoteMathColor(red: 1, green: 128.0 / 255, blue: 0), [.char("x", .ord)])], "bare hex colour")
        #expect(try parse("{\\displaystyle x}") == [.group([.mathStyle(.display, [.char("x", .ord)])])], "style switch")
    }

    @Test func accentsSpacingAndMisc() throws {
        #expect(try parse("\\hat{x}") == [.decorated(.accent("\u{0302}"), [.char("x", .ord)])], "hat")
        #expect(try parse("\\vec v") == [.decorated(.accent("\u{20D7}"), [.char("v", .ord)])], "unbraced vec")
        #expect(try parse("\\widehat{AB}") == [.decorated(.wideAccent("\u{0302}"), [.char("A", .ord), .char("B", .ord)])], "widehat")
        #expect(try parse("\\overline{z}\\underline{w}") == [.decorated(.overline, [.char("z", .ord)]), .decorated(.underline, [.char("w", .ord)])], "overline and underline")
        #expect(try parse("\\overbrace{a+b}^{n}").first.map { node in
            if case .scripts(.decorated(.overbrace, _)?, [.char("n", .ord)]?, nil) = node { return true }
            return false
        } == true, "overbrace label")
        #expect(try parse("\\underbrace{x}_{k}").count == 1, "underbrace label")
        #expect(try parse("\\overrightarrow{AB}") == [.decorated(.overArrow("→"), [.char("A", .ord), .char("B", .ord)])], "over arrow")
        let spaces: [Double] = try parse("a\\,b\\:c\\;d\\!e\\quad f\\qquad g~h").compactMap { node in
            if case .space(let amount) = node { return amount }
            return nil
        }
        let expectedSpaces: [Double] = [3.0 / 18, 4.0 / 18, 5.0 / 18, -3.0 / 18, 1, 2, 1.0 / 3]
        #expect(spaces == expectedSpaces, "spacing commands")
        #expect(try parse("\\hspace{2em}\\mkern18mu") == [.space(2), .space(1)], "explicit spaces")
        #expect(try parse("\\not= \\not\\in \\not<") == [.char("≠", .rel), .char("∉", .rel), .char("≮", .rel)], "negations")
        #expect(try parse("\\overset{!}{=}") == [.stacked(base: [.char("=", .rel)], over: [.char("!", .close)], under: nil)], "overset")
        #expect(try parse("\\stackrel{def}{=}").first.map { node in
            if case .classed(.rel, _) = node { return true }
            return false
        } == true, "stackrel is a relation")
        #expect(try parse("a \\\\ b") == [.lines([[.char("a", .ord)], [.char("b", .ord)]])], "top-level line breaks")
        #expect(try parse("\\boxed{x}\\phantom{y}") == [.boxed([.char("x", .ord)]), .phantom([.char("y", .ord)], keepsWidth: true, keepsHeight: true)], "boxed and phantom")
        #expect(try parse("\\xrightarrow[a]{b}") == [.extensibleArrow("→", over: [.char("b", .ord)], under: [.char("a", .ord)])], "labelled arrow with both labels")
        #expect(try parse("\\xLeftarrow{}") == [.extensibleArrow("⇐", over: [], under: nil)], "empty labelled arrow")
        #expect(try parse("\\cancel{x}\\bcancel{y}\\xcancel{z}\\sout{w}") == [
            .decorated(.cancel, [.char("x", .ord)]), .decorated(.backCancel, [.char("y", .ord)]),
            .decorated(.crossCancel, [.char("z", .ord)]), .decorated(.strike, [.char("w", .ord)]),
        ], "cancel family")
        #expect(try parse("\\R\\N\\Z\\Q\\C") == ["ℝ", "ℕ", "ℤ", "ℚ", "ℂ"].map { .char($0, .ord) }, "number set shorthands")
        #expect(try parse("f\\colon A \\ltimes B") == [.char("f", .ord), .group([.space(2.0 / 18), .char(":", .punct), .space(6.0 / 18)]),
                                                .char("A", .ord), .char("⋉", .bin), .char("B", .ord)], "colon spaces like amsmath and ltimes is binary")
        #expect(try parse("\\llap{a}\\mathrlap{b}\\clap{c}") == [.lap(.left, [.char("a", .ord)]), .lap(.right, [.char("b", .ord)]),
                                                               .lap(.center, [.char("c", .ord)])], "laps")
        #expect(try parse("\\mathrel{x}\\mathbin{y}") == [.classed(.rel, [.char("x", .ord)]), .classed(.bin, [.char("y", .ord)])], "math classes")
    }

    @Test func newcommandWithoutArguments() throws {
        #expect(try parse("\\newcommand{\\RR}{\\mathbb{R}} \\RR^n") == parse("\\mathbb{R}^n"), "newcommand without arguments")
        #expect(try parse("\\newcommand\\sq[1]{#1^2} \\sq{a}+\\sq b") == parse("a^2+b^2"), "argument count with braced and bare arguments")
        #expect(try parse("\\newcommand{\\pair}[2][0]{(#1,#2)} \\pair{x} \\pair[1]{y}") == parse("(0,x) (1,y)"), "optional argument with a default")
        #expect(try parse("\\newcommand*{\\one}{1}\\one") == parse("1"), "starred newcommand")
        #expect(try parse("\\newcommand{\\e}{e}\\renewcommand{\\e}{f}\\e") == parse("f"), "renewcommand replaces a macro")
        #expect(try parse("\\renewcommand{\\alpha}{a}\\alpha") == parse("a"), "renewcommand can redefine a built-in")
        #expect(try parse("\\providecommand{\\pi}{p}\\providecommand{\\q}{q}\\pi\\q") == parse("\\pi q"), "providecommand only fills gaps")
        #expect(try parse("\\def\\f#1#2{#1+#2}\\f ab") == parse("a+b"), "def with parameter text")
        #expect(try parse("\\def\\g{x}\\g\\g") == parse("xx"), "def without parameters")
        #expect(try parse("\\def\\g{\\alpha}\\g x") == parse("\\alpha x"), "expansions keep control words apart from letters")
        #expect(try parse("\\let\\a\\alpha \\a") == parse("\\alpha"), "let copies a built-in")
        #expect(try parse("\\let\\a=\\beta\\a") == parse("\\beta"), "let with an equals sign")
        #expect(try parse("\\def\\b{y}\\let\\c=\\b \\def\\b{z}\\c\\b") == parse("yz"), "let snapshots a macro's meaning")
        #expect(try parse("\\renewcommand{\\beta}{b}\\let\\c\\alpha\\renewcommand{\\alpha}{a}\\c") == parse("\\alpha"), "let snapshots a built-in")
        #expect(try parse("{\\def\\h{1}\\h}") == parse("{1}"), "definitions work inside their group")
        #expect(try failure("{\\def\\h{1}}\\h").message == "Unknown command \\h", "definitions end with their group")
        #expect(try parse("{\\gdef\\k{w}}\\k") == parse("{}w"), "gdef escapes its group")
        #expect(try parse("{\\global\\def\\m{v}}\\m") == parse("{}v"), "global prefix")
        #expect(try parse("\\def\\n{a}\\edef\\o{\\n}\\def\\n{b}\\o") == parse("a"), "edef expands when defined")
        #expect(try parse("\\def\\outer{\\def\\inner##1{##1!}}\\outer\\inner x") == parse("x!"), "## builds nested parameters")
        #expect(try parse("\\newcommand{\\abs}[1]{\\left|#1\\right|}\\abs{\\abs{x}}") == parse("\\left|\\left|x\\right|\\right|"), "macros nest")
        #expect(try parse("\\newcommand{\\ip}[2]{\\langle #1, #2 \\rangle}\\ip{\\frac12}{y}") == parse("\\langle \\frac12, y \\rangle"), "arguments carry structure")
        let many = "\\def\\a{x}" + String(repeating: "\\a", count: 900)
        #expect(try parse(many).count == 900, "hundreds of expansions are fine")
        #expect(try parse("% \\def\\a{b}\n a") == parse("a"), "definitions in comments are ignored")
    }

    @Test func runawayRecursionIsCaughtAtTheCall() throws {
        let loop = try failure("\\def\\a{\\a}\\a")
        #expect(loop.message == "\\a keeps expanding (over 1,000 times). Is it calling itself?" && loop.offset == 10 && loop.length == 2, "runaway recursion is caught at the call: \(loop.message) \(loop.offset) \(loop.length)")
        #expect(try failure("\\def\\a{\\a\\a}\\a").message.hasPrefix("\\a keeps expanding"), "exponential recursion is caught")
        #expect(try failure("\\newcommand{\\b}{\\c}\\newcommand{\\c}{\\b}\\b").message.hasPrefix("\\b keeps expanding"), "mutual recursion is caught")
        let taken = try failure("\\newcommand{\\alpha}{x}")
        #expect(taken.message == "\\alpha already means something; use \\renewcommand to change it" && taken.offset == 12 && taken.length == 6, "newcommand refuses to clobber")
        #expect(try failure("\\newcommand{\\f}{x}\\newcommand{\\f}{y}").message.hasPrefix("\\f already means something"), "newcommand twice")
        #expect(try failure("\\renewcommand{\\nope}{x}").message == "\\nope isn't defined yet, so use \\newcommand", "renewcommand needs a definition")
        #expect(try failure("\\newcommand{\\f}[1]{#2}").message == "\\f only takes 1 argument, so there's no #2", "parameter out of range")
        #expect(try failure("\\newcommand{\\f}[10]{x}").message == "The number of arguments has to be 0 to 9", "argument count range")
        #expect(try failure("\\def\\f#2{x}").message.hasPrefix("\\def parameters have to be #1, #2"), "def parameters in order")
        let short = try failure("\\newcommand{\\x}[3]{#1#2#3}\\x ab")
        #expect(short.message == "\\x needs 3 arguments" && short.offset == 26 && short.length == 2, "missing macro argument")
        let inner = try failure("\\newcommand{\\y}{\\frac{a}}\\y")
        #expect(inner.message == "\\frac needs 2 arguments" && inner.offset == 25 && inner.length == 2, "errors inside a macro point at its use")
        #expect(try failure("\\newcommand").message.hasPrefix("\\newcommand needs a command name"), "newcommand needs a name")
        #expect(try failure("\\newcommand{\\z}").message == "\\newcommand{\\z} needs a definition in braces", "newcommand needs a body")
        #expect(try failure("\\def\\z").message.hasPrefix("\\def\\z needs a definition"), "def needs a body")
        #expect(try failure("\\newcommand{\\z}{x").message == "Missing } to close this {", "unclosed definition")
    }

    @Test func delimitersAroundAndBetweenParameters() throws {
        #expect(try parse("\\def\\pt(#1,#2){#1+#2}\\pt(a,b)") == parse("a+b"), "delimiters around and between parameters")
        #expect(try parse("\\def\\foo#1.{[#1]}\\foo abc.d") == parse("[abc]d"), "an argument runs to its delimiter")
        #expect(try parse("\\def\\foo#1.{[#1]}\\foo {a.b}.") == parse("[a.b]"), "braces hide the delimiter and come off")
        #expect(try parse("\\def\\foo#1.{[#1]}\\foo {a}{b}.") == parse("[{a}{b}]"), "braces stay when they don't wrap the whole argument")
        #expect(try parse("\\def\\foo#1.{[#1]}\\foo .") == parse("[]"), "an empty delimited argument")
        #expect(try parse("\\def\\foo#1\\stop{(#1)}\\foo xy\\stop") == parse("(xy)"), "a command works as a delimiter")
        #expect(try parse("\\def\\foo#1#2;{#2#1}\\foo ab c;") == parse("bca"), "undelimited then delimited")
        #expect(try parse("\\def\\foo#1 #2.{#2#1}\\foo x y.") == parse("yx"), "a space is a delimiter too")
        #expect(try parse("\\def\\foo.#1{#1!}\\foo.x") == parse("x!"), "text before the first parameter has to match")
        #expect(try parse("\\def\\foo#1#{#1\\boxed}\\foo ab{c}") == parse("ab\\boxed{c}"), "#{ stops at a brace and leaves it")
        #expect(try parse("\\def\\foo#1.{#1}\\def\\bar{\\foo x.}\\bar") == parse("x"), "delimited macros inside macros")
        #expect(try parse("\\def\\cs#1.#2.{#2#1}\\cs a.b.") == parse("ba"), "two delimited parameters")
        #expect(try parse("\\def\\ab#1ab{[#1]}\\ab aab") == parse("[a]"), "the shortest argument that the delimiter follows")
        let mismatch = try failure("\\def\\foo.#1{#1}\\foo x")
        #expect(mismatch.message == "\\foo has to be followed by \u{201C}.\u{201D}, the way it was defined" && mismatch.offset == 15, "a prefix that doesn't match: \(mismatch.message)")
        let runaway = try failure("\\def\\foo#1.{#1}\\foo abc")
        #expect(runaway.message == "\\foo never finds the \u{201C}.\u{201D} that ends its argument" && runaway.offset == 15, "a missing delimiter: \(runaway.message)")
        #expect(try failure("{\\def\\foo#1.{#1}\\foo a}.").message == "\\foo's argument has an extra }", "a brace can't close mid-argument")
        #expect(try failure("\\def\\foo#1}{x}").message == "\\def\\foo has a } before its definition starts", "stray brace in parameter text")
    }

    @Test func expandafterExpandsTheSecondTokenFirst() throws {
        #expect(try parse("\\def\\a{x.y}\\def\\b#1.{[#1]}\\expandafter\\b\\a") == parse("[x]y"), "expandafter expands the second token first")
        #expect(try failure("\\def\\a{x.y}\\def\\b#1.{[#1]}\\b\\a").message.hasPrefix("\\b never finds"), "without expandafter the macro sees \\a")
        #expect(try parse("\\def\\a{1}\\def\\b{\\a}\\def\\c#1.{[#1]}\\expandafter\\expandafter\\expandafter\\c\\b.") == parse("[1]"), "expandafter chains expand twice")
        #expect(try parse("\\def\\a{1}\\edef\\b{\\noexpand\\a\\a}\\def\\a{2}\\b") == parse("21"), "noexpand keeps a command for later in edef")
        #expect(try parse("\\noexpand\\alpha") == parse("\\alpha"), "noexpand on a built-in")
        #expect(try parse("x\\def\\q{1}\\noexpand\\q y") == parse("xy"), "noexpand on a macro acts like relax")
        #expect(try parse("\\csname alpha\\endcsname") == parse("\\alpha"), "csname builds a command")
        #expect(try parse("\\expandafter\\def\\csname my thing\\endcsname{z}\\csname my thing\\endcsname") == parse("z"), "csname defines and uses a macro, spaces and all")
        #expect(try parse("\\def\\n{al}\\csname\\n pha\\endcsname") == parse("\\alpha"), "macros expand inside csname")
        #expect(try parse("x\\csname nothinghere\\endcsname y") == parse("xy"), "an undefined csname is a no-op")
        #expect(try parse("\\expandafter\\let\\csname b\\endcsname\\beta \\b") == parse("\\beta"), "csname with let")
        #expect(try parse("\\expandafter\\newcommand\\csname sq\\endcsname[1]{#1^2}\\sq{y}") == parse("y^2"), "csname with newcommand")
        #expect(try parse("\\csname alpha\\endcsname b") == parse("\\alpha b"), "a built name stays apart from the next letter")
        let open = try failure("x \\csname alpha")
        #expect(open.message == "\\csname needs an \\endcsname to finish the name" && open.offset == 2, "csname needs its end")
        #expect(try failure("\\csname \\alpha\\endcsname").message == "\\csname builds names from letters and symbols, so \\alpha can't go inside", "csname refuses commands that don't expand")
        #expect(try failure("\\expandafter").message == "\\expandafter needs two things after it", "expandafter needs tokens")
        #expect(try failure("\\def\\a{\\expandafter\\a\\a}\\a").message.contains("keeps expanding"), "expandafter loops hit the limit")
        #expect(try failure("\\def\\a{\\csname a\\endcsname}\\a").message.contains("keeps expanding"), "csname loops hit the limit")
        #expect(try parse("% \\csname alpha\\endcsname\n a") == parse("a"), "primitives in comments are ignored")
    }

    @Test func aDefinitionWorksInItsOwnCell() throws {
        #expect(try parse("\\begin{matrix}\\def\\x{1}\\x & 2\\end{matrix}") == parse("\\begin{matrix}1 & 2\\end{matrix}"), "a definition works in its own cell")
        #expect(try failure("\\begin{matrix}\\def\\x{1}\\x & \\x\\end{matrix}").message == "Unknown command \\x", "a definition ends with its cell")
        #expect(try failure("\\begin{aligned} \\def\\y{a} \\y \\\\ \\y \\end{aligned}").message == "Unknown command \\y", "a new row starts fresh")
        #expect(try failure("\\begin{matrix}\\def\\z{1}\\end{matrix}\\z").message == "Unknown command \\z", "nothing leaks out of an environment")
        #expect(try parse("\\begin{matrix}\\gdef\\w{1}\\end{matrix}\\w") == parse("\\begin{matrix}\\end{matrix}1"), "gdef still escapes a cell")
        #expect(try parse("\\def\\v{3}\\begin{matrix}\\v & \\v\\end{matrix}") == parse("\\begin{matrix}3 & 3\\end{matrix}"), "outer macros reach every cell")
        #expect(try parse("\\begin{array}{cc}\\def\\u{4}\\u & 5\\end{array}") == parse("\\begin{array}{cc}4 & 5\\end{array}"), "array column specs don't confuse scopes")
        #expect(try failure("\\begin{matrix}\\begin{matrix}\\def\\t{1}\\t\\end{matrix} & \\t\\end{matrix}").message == "Unknown command \\t", "nested environments scope their own cells")
        #expect(try parse("\\begin{matrix}{\\def\\s{1}\\s} & 2\\end{matrix}") == parse("\\begin{matrix}{1} & 2\\end{matrix}"), "groups still work inside cells")
    }

    @Test func subscriptedFormula() throws {
        #expect(try parse("\\ce{H2O}") == parse("{\\mathrm{H}_{2}\\mathrm{O}}"), "subscripted formula")
        #expect(try parse("\\ce{Fe2(SO4)3}") == parse("{\\mathrm{Fe}_{2}(\\mathrm{S}\\mathrm{O}_{4})_{3}}"), "parentheses take subscripts")
        #expect(try parse("\\ce{SO4^2-}") == parse("{\\mathrm{S}\\mathrm{O}_{4}^{2-}}"), "charge over a subscript")
        #expect(try parse("\\ce{Na+}") == parse("{\\mathrm{Na}^{+}}") && parse("\\ce{NO3-}") == parse("{\\mathrm{N}\\mathrm{O}_{3}^{-}}"), "trailing charges")
        #expect(try parse("\\ce{Fe^{3+}}") == parse("\\ce{Fe^3+}"), "braced and bare charges")
        #expect(try parse("\\ce{^{14}_{6}C}") == parse("{{}^{\\hphantom{14}}_{\\hphantom{6}}{}^{\\mathllap{14}}_{\\mathllap{6}}\\mathrm{C}}"), "isotope prescripts line up on the right")
        #expect(try parse("\\ce{{}^{14}_{6}C}") == parse("\\ce{^{14}_{6}C}"), "braced isotope form")
        #expect(try parse("\\ce{2H2O}") == parse("{2\\mathrm{H}_{2}\\mathrm{O}}"), "stoichiometric number")
        #expect(try parse("\\ce{1/2O2}") == parse("{\\tfrac{1}{2}\\mathrm{O}_{2}}"), "fractional stoichiometric number")
        #expect(try parse("\\ce{NaCl(aq)}") == parse("{\\mathrm{Na}\\mathrm{Cl}\\mathrm{(}\\mathrm{aq}\\mathrm{)}}"), "aqueous state")
        #expect(try parse("\\ce{H2O(l)}") == parse("{\\mathrm{H}_{2}\\mathrm{O}\\mathrm{(}\\mathrm{l}\\mathrm{)}}") && parse("\\ce{Fe(s)}") == parse("{\\mathrm{Fe}\\mathrm{(}\\mathrm{s}\\mathrm{)}}"), "liquid and solid states")
        #expect(try parse("\\ce{Fe(CN)6^3-}") == parse("{\\mathrm{Fe}(\\mathrm{C}\\mathrm{N})_{6}^{3-}}"), "capital parentheses are groups, not states")
        #expect(try parse("\\ce{C6H5-CHO}") == parse("{\\mathrm{C}_{6}\\mathrm{H}_{5}{-}\\mathrm{C}\\mathrm{H}\\mathrm{O}}"), "single bond")
        #expect(try parse("\\ce{X=Y#Z}") == parse("{\\mathrm{X}{=}\\mathrm{Y}{\\equiv}\\mathrm{Z}}"), "double and triple bonds")
        #expect(try parse("\\ce{CuSO4*5H2O}") == parse("\\ce{CuSO4.5H2O}"), "star and dot both make addition compounds")
        #expect(try contains(parse("\\ce{CuSO4*5H2O}")) { $0 == .char("⋅", .bin) }, "addition dot")
        #expect(try parse("\\ce{[AgCl2]-}") == parse("{\\lbrack\\mathrm{Ag}\\mathrm{Cl}_{2}\\rbrack^{-}}"), "bracketed complex ion")
        #expect(try parse("\\ce{e-}") == parse("{\\mathrm{e}^{-}}"), "electron")
        #expect(try parse("\\ce{Fe^{II}}") == parse("{\\mathrm{Fe}^{\\mathrm{II}}}"), "oxidation state")
        #expect(try parse("\\ce{$x$ H2O}") == parse("{{x} \\mathrm{H}_{2}\\mathrm{O}}"), "math escapes")
        #expect(try parse("\\ce{n H2O}") == parse("{n\\, \\mathrm{H}_{2}\\mathrm{O}}"), "variable stoichiometry stays italic")
        let reaction = try parse("\\ce{2H2 + O2 -> 2H2O}")
        #expect(contains(reaction) { $0 == .char("+", .bin) }, "plus between species")
        let checks: [(String, String)] = [("->", "→"), ("<-", "←"), ("<->", "↔"), ("<-->", "⇄"), ("<=>", "⇌"), ("<=>>", "⥂"), ("<<=>", "⥄")]
        for (text, symbol) in checks {
            #expect(try arrow(parse("\\ce{A \(text) B}"))?.0 == symbol, "\(text) becomes \(symbol)")
        }
        #expect(try arrow(parse("\\ce{A->B}"))?.0 == "→", "arrows need no spaces")
        let labelled = try #require(arrow(parse("\\ce{A ->[H2O][\\Delta] B}")), "labelled arrow parses")
        #expect(try labelled.1 == parse("\\mathrm{H}_{2}\\mathrm{O}") && labelled.2 == [.group([.char("Δ", .ord)])], "arrow labels above and below, with chemistry in the label")
        #expect(try arrow(parse("\\ce{A ->[heat] B}"))?.2 == nil, "a single label goes above")
        #expect(try contains(parse("\\ce{BaSO4 v}")) { $0 == .classed(.rel, [.char("↓", .rel)]) }, "precipitate")
        #expect(try contains(parse("\\ce{H2 ^}")) { $0 == .classed(.rel, [.char("↑", .rel)]) }, "gas")
        #expect(try !contains(parse("\\ce{V2O5}")) { $0 == .char("↓", .rel) }, "a capital V is vanadium")
        let nested = try parse("\\newcommand{\\water}{\\ce{H2O}}\\water")
        #expect(try nested == parse("\\ce{H2O}"), "chemistry inside a macro")
        let unclosed = try failure("x + \\ce{A ->[heat B}")
        #expect(unclosed.message == "Missing ] in this formula" && unclosed.offset == 4, "chemistry errors point at \\ce")
        #expect(try failure("\\ce").message == "\\ce needs {…} after it", "ce needs an argument")
    }

    @Test func bondCommandsMatchBondCharacters() throws {
        #expect(try parse("\\ce{A\\bond{-}B\\bond{=}C\\bond{#}D}") == parse("\\ce{A-B=C#D}"), "bond commands match bond characters")
        #expect(try parse("\\ce{A\\bond{1}B\\bond{2}C\\bond{3}D}") == parse("\\ce{A-B=C#D}"), "numbered bonds")
        for bond in ["~", "~-", "~=", "~--", "-~-", "...", "....", "->", "<-"] {
            let nodes = try parse("\\ce{A\\bond{\(bond)}B}")
            #expect(try nodes.count == 1 && !parse("\\ce{AB}").isEmpty && nodes != parse("\\ce{AB}"), "bond \(bond) draws something")
        }
        #expect(try contains(parse("\\ce{A\\bond{->}B}")) { $0 == .char("→", .rel) }, "arrow bond")
        #expect(try failure("\\ce{A\\bond{?}B}").message == "\\bond doesn't know \u{201C}?\u{201D}", "unknown bonds explain themselves")
        #expect(try parse("\\ce{OCO^{.-}}") == parse("{\\mathrm{O}\\mathrm{C}\\mathrm{O}^{\\cdot -}}"), "radical anion")
        #expect(try parse("\\ce{NO^{(2.)-}}") == parse("{\\mathrm{N}\\mathrm{O}^{(2\\cdot )-}}"), "radical with a count")
        #expect(try parse("\\ce{Mg^.}") == parse("{\\mathrm{Mg}^{\\cdot}}") && parse("\\ce{M^{..}_i}") == parse("{\\mathrm{M}^{\\cdot \\cdot }_{i}}"), "electron dots")
        #expect(try parse("\\ce{NO^*}") == parse("{\\mathrm{N}\\mathrm{O}^{*}}"), "excited state keeps its asterisk")
        #expect(try parse("\\ce{NO_x}") == parse("{\\mathrm{N}\\mathrm{O}_{x}}") && parse("\\ce{Fe^n+}") == parse("{\\mathrm{Fe}^{n+}}"), "variables are italic")
        #expect(try parse("\\ce{[Pt(\\eta^2-C2H4)Cl3]-}") == parse("{\\lbrack\\mathrm{Pt}(\\eta ^{2}{-}\\mathrm{C}_{2}\\mathrm{H}_{4})\\mathrm{Cl}_{3}\\rbrack^{-}}"), "hapticity then a bond")
        #expect(try parse("\\ce{\\beta +}") == parse("{\\beta ^{+}}"), "a space after a Greek letter is ignored")
        #expect(try parse("\\ce{CO3^2-_{(aq)}}") == parse("{\\mathrm{C}\\mathrm{O}_{3}^{2-}{}_{(\\mathrm{aq})}}"), "a second subscript gets its own base")
        #expect(try parse("\\ce{NaOH(aq,$\\infty$)}") == parse("{\\mathrm{Na}\\mathrm{O}\\mathrm{H}\\mathrm{(}\\mathrm{aq}{,}{\\infty}\\mathrm{)}}"), "math inside a state")
        #expect(try parse("\\ce{ZnS(\\ca$c$)}") == parse("{\\mathrm{Zn}\\mathrm{S}({\\sim}{c})}"), "circa")
        #expect(try parse("\\ce{{Gluconic Acid} + H2O2}") == parse("{\\text{Gluconic Acid} + \\mathrm{H}_{2}\\mathrm{O}_{2}}"), "braces make upright text")
        #expect(try parse("\\ce{$cis${-}[PtCl2(NH3)2]}") == parse("{{cis}\\text{-}\\lbrack\\mathrm{Pt}\\mathrm{Cl}_{2}(\\mathrm{N}\\mathrm{H}_{3})_{2}\\rbrack}"), "a braced hyphen isn't a bond")
        #expect(try parse("\\ce{A - B}") == parse("{\\mathrm{A} - \\mathrm{B}}"), "a spaced minus is an operator")
        #expect(try contains(parse("\\ce{A v B (v) -> B ^ B (^)}")) { $0 == .classed(.rel, [.char("(", .open), .char("↓", .rel), .char(")", .close)]) }, "precipitate in parentheses")
        #expect(try parse("\\ce{H^3HO}") == parse("{\\mathrm{H}{}^{\\hphantom{3}}{}^{\\mathllap{3}}\\mathrm{H}\\mathrm{O}}"), "a bare mass number belongs to the next element")
        #expect(try parse("\\ce{1s^2-N}") == parse("{1\\mathrm{s}^{2}{-}\\mathrm{N}}"), "orbitals")
        #expect(try parse("\\ce{n-Pr}") == parse("{n{-}\\mathrm{Pr}}") && parse("\\ce{iPr}") == parse("{i\\mathrm{Pr}}"), "italic prefixes")
        #expect(try parse("\\ce{\\frac{[Hg^2+][Hg]}{[Hg2^2+]}}") ==
               parse("{\\frac{\\lbrack\\mathrm{Hg}^{2+}\\rbrack\\lbrack\\mathrm{Hg}\\rbrack}{\\lbrack\\mathrm{Hg}_{2}^{2+}\\rbrack}}"), "chemistry inside \\frac")
        #expect(try parse("\\ce{A~B}") == parse("{\\mathrm{A}\\ \\mathrm{B}}"), "a tilde is a space")
        #expect(try parse("\\pu{1,2e3 kJ}") == parse("{1{,}2\\cdot 10^{3}~\\mathrm{kJ}}"), "comma decimals stay commas")
        #expect(try parse("\\pu{1.2x10^3 kJ}") == parse("{1.2\\times 10^{3}~\\mathrm{kJ}}") && parse("\\pu{1.2*10^-3 m}") == parse("{1.2\\cdot 10^{-3}~\\mathrm{m}}"), "written-out powers of ten")
        #expect(try parse("\\pu{1.2e3 kJ mol-1}") == parse("{1.2\\cdot 10^{3}~\\mathrm{kJ}\\,\\mathrm{mol}^{-1}}"), "number, product and exponent")
        #expect(try parse("\\pu{123 J*s}") == parse("{123~\\mathrm{J}\\cdot \\mathrm{s}}") && parse("\\pu{123 J.s}") == parse("\\pu{123 J*s}"), "products")
        #expect(try parse("\\pu{75.3 J // mol K}") == parse("{75.3~\\frac{\\mathrm{J}}{\\mathrm{mol}\\,\\mathrm{K}}}"), "quotient with a spaced denominator")
        #expect(try parse("\\pu{10-20 K}") == parse("{10\\text{\u{2013}}20~\\mathrm{K}}"), "ranges get an en dash")
        #expect(try parse("\\pu{3 m^{-2}}") == parse("{3~\\mathrm{m}^{-2}}"), "braced exponents")
    }

    @Test func numberAndUnit() throws {
        #expect(try parse("\\pu{123 kJ/mol}") == parse("{123~\\mathrm{kJ}/\\mathrm{mol}}"), "number and unit")
        #expect(try parse("\\pu{1.2e3 kJ}") == parse("{1.2\\cdot 10^{3}~\\mathrm{kJ}}"), "lowercase e uses a dot")
        #expect(try parse("\\pu{1.2E-3 kJ}") == parse("{1.2\\times 10^{-3}~\\mathrm{kJ}}"), "capital E uses a cross")
        #expect(try parse("\\pu{kJ mol-1}") == parse("{\\mathrm{kJ}\\,\\mathrm{mol}^{-1}}"), "exponents without a caret")
        #expect(try parse("\\pu{m/s^2}") == parse("{\\mathrm{m}/\\mathrm{s}^{2}}"), "exponents with a caret")
        #expect(try parse("\\pu{kg*m2}") == parse("{\\mathrm{kg}\\cdot \\mathrm{m}^{2}}"), "multiplied units")
        #expect(try parse("\\pu{12345.67891 m}") == parse("{12\\,345.678\\,91~\\mathrm{m}}"), "digit groups")
        #expect(try parse("\\pu{1234 m}") == parse("{1234~\\mathrm{m}}"), "four digits stay together")
        #expect(try parse("\\pu{J//mol}") == parse("{\\frac{\\mathrm{J}}{\\mathrm{mol}}}"), "double slash makes a fraction")
        #expect(try parse("\\pu{25 °C}") == parse("{25~{}^{\\circ}\\mathrm{C}}"), "degrees Celsius")
        #expect(try parse("\\pu{1.2+-0.1 mm}") == parse("{1.2\\pm 0.1~\\mathrm{mm}}"), "uncertainty")
        #expect(try parse("\\pu{-40 K}") == parse("{-40~\\mathrm{K}}"), "negative numbers")
        #expect(try parse("\\pu{5 µm}") == parse("{5~\\mu \\mathrm{m}}"), "micro sign")
    }

    @Test func tagWrapsItsLabelInParentheses() throws {
        let plain = try equation("E = mc^2 \\tag{1}")
        #expect(try plain.tag == [.text("(1)", .roman)] && plain.nodes == parse("E = mc^2"), "tag wraps its label in parentheses")
        #expect(try equation("x \\tag*{A.1}").tag == [.text("A.1", .roman)], "tag* keeps the label as written")
        #expect(try equation("x \\tag{$\\ast$}").tag == [.text("(", .roman), .mathStyle(.text, [.char("∗", .bin)]), .text(")", .roman)], "math inside a tag")
        #expect(try equation("\\tag{eq} x").tag == [.text("(eq)", .roman)], "a tag can come first")
        #expect(try equation("x \\notag").tag == nil && equation("x \\nonumber").nodes == parse("x"), "notag on its own is harmless")
        #expect(try parse("x \\tag{1}") == parse("x"), "parse drops the tag from the formula")
        let inline = try failure("x \\tag{1}", display: false)
        #expect(inline.message == "\\tag only works in display equations" && inline.offset == 2 && inline.length == 4, "inline tags explain themselves")
        #expect(try failure("x \\tag{1} \\tag{2}").message == "Only one \\tag per line", "one tag per line")
        #expect(try failure("x^\\tag{1}").message == "\\tag has to stand on its own, not inside a script or argument", "tag inside a script")
        #expect(try failure("x \\tag").message == "\\tag needs {text} after it", "tag needs a label")
        #expect(try equation("x \\tag 1").tag == [.text("(1)", .roman)], "a one-character tag needs no braces")
        let one: [NoteMathNode] = [.text("(1)", .roman)], two: [NoteMathNode] = [.text("(2)", .roman)]
        #expect(try rowTags("\\begin{align} a &= b \\\\ c &= d \\end{align}") == [one, two], "align numbers every row")
        #expect(try rowTags("\\begin{align} a &= b \\\\ c &= d \\\\ \\end{align}") == [one, two], "a trailing break doesn't number an empty row")
        #expect(try rowTags("\\begin{align} a &= b \\notag \\\\ c &= d \\end{align}") == [nil, one], "notag skips a row")
        #expect(try rowTags("\\begin{align} a &= b \\nonumber \\\\ c &= d \\nonumber \\end{align}") == [], "nonumber everywhere leaves no tags")
        #expect(try rowTags("\\begin{align} a &= b \\tag{x} \\\\ c &= d \\end{align}") == [[.text("(x)", .roman)], one], "an explicit tag doesn't use up a number")
        #expect(try rowTags("\\begin{align*} a &= b \\\\ c &= d \\tag{y} \\end{align*}") == [nil, [.text("(y)", .roman)]], "align* only shows explicit tags, here on its last line")
        #expect(try rowTags("\\begin{align*} a \\\\ b \\end{align*}") == [], "align* has no numbers")
        #expect(try rowTags("\\begin{gather} a \\\\ b \\end{gather}") == [one, two], "gather numbers rows")
        #expect(try rowTags("\\begin{equation} E = mc^2 \\end{equation}") == [one], "equation is numbered")
        #expect(try rowTags("\\begin{equation*} E = mc^2 \\tag{$\\star$} \\end{equation*}").count == 1, "equation* takes a tag")
        let aligned = try equation("\\begin{aligned} a &= b \\tag{1} \\\\ c &= d \\end{aligned}")
        #expect(aligned.tag == one, "a tag inside aligned tags the whole equation")
        if case .environment(let environment)? = aligned.nodes.first { #expect(environment.tags.isEmpty, "aligned rows carry no tags") }
        let after = try equation("\\begin{aligned} a &= b \\\\ c &= d \\end{aligned} \\tag{2}")
        #expect(after.tag == two, "a tag after aligned tags the whole equation")
        if case .environment(let environment)? = (try? NoteMathParser.parseEquation("\\begin{align} a \\\\ b \\end{align}", display: false))?.nodes.first {
            #expect(environment.tags.isEmpty, "inline align stays unnumbered")
        } else {
            Issue.record("inline align parses")
            return
        }
        #expect(try failure("\\begin{align} a \\tag{1} \\tag{2} \\end{align}").message == "Only one \\tag per line", "one tag per align row")
        #expect(try equation("\\newcommand{\\eq}[1]{\\tag{#1}} x \\eq{7}").tag == [.text("(7)", .roman)], "tags from macros")
    }

    @Test func labelsAttachToRowNumbersAndTags() throws {
        let numbered = try equation("\\begin{align} a &= b \\label{first} \\\\ c &= d \\tag{x}\\label{second} \\\\ e \\label{third} \\end{align}")
        #expect(numbered.labels == [NoteMathLabel(key: "first", target: .automatic(1)), NoteMathLabel(key: "second", target: .tag([.text("x", .roman)])),
                                   NoteMathLabel(key: "third", target: .automatic(2))] && numbered.automaticNumbers == 2, "labels attach to row numbers and tags: \(numbered.labels)")
        let later = NoteMathNumberingContext(firstNumber: 4)
        let shifted = try? NoteMathParser.parseEquation("\\begin{gather} a \\\\ b \\end{gather}", display: true, numbering: later)
        if case .environment(let environment)? = shifted?.nodes.first {
            #expect(environment.tags == [[.text("(5)", .roman)], [.text("(6)", .roman)]], "numbers continue from earlier equations")
        } else {
            Issue.record("numbered gather parses")
            return
        }
        let context = NoteMathNumberingContext(references: ["e": [.text("3", .roman)]])
        let refs = try? NoteMathParser.parseEquation("\\eqref{e} + \\ref{e} + \\eqref{nope}", display: false, numbering: context)
        #expect(refs?.nodes == [.reference("e", parenthesized: true, label: [.text("3", .roman)]), .char("+", .bin),
                               .reference("e", parenthesized: false, label: [.text("3", .roman)]), .char("+", .bin),
                               .reference("nope", parenthesized: true, label: nil)], "references resolve or stay missing")
        #expect(try parse("\\text{see \\eqref{a}}") == [.group([.text("see ", .roman), .reference("a", parenthesized: true, label: nil)])], "references work inside text")
        #expect(try equation("x \\tag{A} \\label{k}").labels == [NoteMathLabel(key: "k", target: .tag([.text("A", .roman)]))], "a tagged display takes a label")
        #expect(try failure("x \\label{k}").message.hasPrefix("\\label needs a numbered equation"), "an unnumbered display can't take a label")
        #expect(try failure("x \\label{k}", display: false).message == "\\label only works in display equations", "inline labels explain themselves")
        #expect(try failure("\\begin{align} a \\label{k} \\\\ b \\label{k} \\end{align}").message == "\u{201C}k\u{201D} already labels another line here", "duplicate labels in one equation")
        #expect(try failure("\\begin{align*} a \\label{k} \\end{align*}").message == "\\label needs a numbered line, and this one isn't numbered", "labels need numbered rows")
        let taken = NoteMathNumberingContext(takenLabels: ["k"])
        do {
            _ = try NoteMathParser.parseEquation("\\begin{equation} a \\label{k} \\end{equation}", display: true, numbering: taken)
            Issue.record("a label taken by an earlier equation fails")
        } catch {
            #expect(error.message == "\u{201C}k\u{201D} already labels an earlier equation", "labels are unique across the note")
        }
        #expect(try failure("\\begin{align} a \\label{x} \\label{y} \\end{align}").message == "Only one \\label per line", "one label per line")
        #expect(try failure("\\eqref{}").message == "\\eqref needs a label, like \\eqref{eq:energy}", "references need a key")
    }

    @Test func missingArgumentMessage() throws {
        let missingArgument = try failure("\\frac{a}")
        #expect(missingArgument.message == "\\frac needs 2 arguments", "missing argument message: \(missingArgument.message)")
        let double = try failure("x^2^3")
        #expect(double.message.hasPrefix("Double superscript") && double.offset == 3 && double.length == 1, "double superscript at the second ^")
        #expect(try failure("x_1_2").message.hasPrefix("Double subscript"), "double subscript")
        #expect(try failure("x^2'").message.hasPrefix("Double superscript"), "prime after superscript")
        let open = try failure("a + {x")
        #expect(open.message == "Missing } to close this {" && open.offset == 4, "unclosed brace points at the brace")
        let close = try failure("x}")
        #expect(close.message == "There's a } without a matching {" && close.offset == 1, "stray brace")
        let unknown = try failure("1 + \\foo")
        #expect(unknown.message == "Unknown command \\foo" && unknown.offset == 4 && unknown.length == 4, "unknown command range")
        let wide = try failure("😀 \\foo")
        #expect(wide.offset == 3, "offsets count UTF-16 units")
        let fence = try failure("\\left( x")
        #expect(fence.message == "Missing \\right to close this \\left" && fence.offset == 0, "unclosed left")
        #expect(try failure("x \\right)").message == "\\right without a matching \\left", "stray right")
        #expect(try failure("\\middle|").message.hasPrefix("\\middle only works"), "stray middle")
        #expect(try failure("\\left x \\right)").message.hasPrefix("\\left needs a delimiter"), "left needs a delimiter")
        let mismatch = try failure("\\begin{matrix} a \\end{pmatrix}")
        #expect(mismatch.message == "\\begin{matrix} ends with \\end{pmatrix}", "mismatched environment")
        #expect(try failure("\\begin{matrix} a").message == "Missing \\end{matrix}", "unclosed environment")
        #expect(try failure("\\begin{foo} a \\end{foo}").message == "Unknown environment \u{201C}foo\u{201D}", "unknown environment")
        #expect(try failure("\\begin{array}{cx} a \\end{array}").message == "Array columns only take l, c, r, | and :", "bad array spec")
        #expect(try failure("\\begin{array}{c} a & b \\end{array}").message.hasPrefix("This row has more columns"), "too many cells")
        #expect(try failure("\\begin{gathered} a & b \\end{gathered}").message == "gathered doesn't use &", "gathered has one column")
        #expect(try failure("a & b").message.hasPrefix("& only works"), "stray ampersand")
        #expect(try failure("\\color{nope}{x}").message == "Unknown colour \u{201C}nope\u{201D}", "unknown colour")
        #expect(try failure("x^").message == "^ needs something to raise", "empty superscript")
        #expect(try failure("x_}").message == "_ needs something to lower", "empty subscript")
        #expect(try failure("\\sqrt[3").message == "Missing ] to close this [", "unclosed degree")
        #expect(try failure("\\text{abc").message == "Missing } to close this \\text", "unclosed text")
        #expect(try failure("\\text{\\alpha}").message == "\\alpha doesn't work inside \\text", "math command in text")
        #expect(try failure("$x$").message.hasPrefix("You're already in math mode"), "dollar signs")
        #expect(try failure("\\hspace{2furlongs}").message.hasSuffix("isn't a size I understand, like 1em or 3mu"), "bad size")
        #expect(try failure("x\\").message == "A lone \\ needs a command name after it", "lone backslash")
        #expect(try parse("\\sum\\limits\\limits").count == 1, "limits twice is fine")
        #expect(try failure("x\\limits").message.hasPrefix("\\limits has to come right after"), "limits needs an operator")
        #expect(try failure(String(repeating: "{", count: 400)).message == "This formula nests too deep to draw", "deep nesting is caught")
        #expect(try failure("{a \\over b \\over c}").message.hasPrefix("Only one \\over"), "ambiguous over")
    }
}
