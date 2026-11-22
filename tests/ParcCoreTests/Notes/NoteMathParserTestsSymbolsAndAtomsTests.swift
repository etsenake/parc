import Foundation
import Testing
@testable import ParcCore

struct NoteMathParserTestsSymbolsAndAtomsTests {
    typealias NodeCase = NoteMathParserTestsSupport.NodeCase
    typealias ErrorCase = NoteMathParserTestsSupport.ErrorCase
    private typealias Parser = NoteMathParserTestsSupport

    private static let symbolNames = """
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

    @Test(arguments: symbolNames.map(String.init))
    func eachSymbolOrShorthandIsBuiltIn(name: String) {
        #expect(NoteMathParser.isBuiltIn(name), "\\\(name) is built in")
    }

    @Test(arguments: symbolNames.map(String.init))
    func eachBuiltInSymbolOrShorthandParses(name: String) throws {
        _ = try Parser.parse("\\\(name)")
    }

    @Test(arguments: [
        NodeCase("lt is a relation", "a \\lt b") { [.char("a", .ord), .char("<", .rel), .char("b", .ord)] },
        NodeCase("colon pairs kern together", "\\Coloneq") { [.classed(.rel, [.char("\u{2237}", .ord), .space(-1.2 / 18), .char("\u{2212}", .ord)])] },
        NodeCase("char reads hex, decimal, backtick and octal codes", "\\char\"263A \\char65 \\char`b \\char'101") { [.char("☺", .ord), .char("A", .ord), .char("b", .ord), .char("A", .ord)] },
        NodeCase("verb keeps its text", "\\verb|x_1 \\y|") { [.text("x_1 \\y", .monospace)] },
        NodeCase("verb star shows spaces", "\\verb*|a b|") { [.text("a\u{2423}b", .monospace)] },
        NodeCase("TextOrMath picks math", "\\TextOrMath{t}{m}") { [.group([.char("m", .ord)])] },
        NodeCase("html wrappers keep their content", "\\htmlClass{big}{x}") { [.group([.char("x", .ord)])] },
        NodeCase("mathchoice keeps four branches", "\\mathchoice{a}{b}{c}{d}") { [.choice([[.char("a", .ord)], [.char("b", .ord)], [.char("c", .ord)], [.char("d", .ord)]])] },
        NodeCase("vcenter", "\\vcenter{x}") { [.vcenter([.char("x", .ord)])] },
        NodeCase("relax does nothing", "\\relax x") { [.space(0), .char("x", .ord)] },
        NodeCase("bold is mathbf", "\\bold{x}") { [.styled(.bold, [.char("x", .ord)])] },
        NodeCase("frak is mathfrak", "\\frak{g}") { [.styled(.fraktur, [.char("g", .ord)])] },
        NodeCase("Greek letters and a binary plus", "\\alpha + \\beta") { [.char("α", .ord), .char("+", .bin), .char("β", .ord)] },
        NodeCase("hyphen becomes a minus sign", "a-b") { [.char("a", .ord), .char("\u{2212}", .bin), .char("b", .ord)] },
        NodeCase("relations", "x \\leq y") { [.char("x", .ord), .char("≤", .rel), .char("y", .ord)] },
        NodeCase("open, close and punctuation", "f(x), y") { [.char("f", .ord), .char("(", .open), .char("x", .ord), .char(")", .close),
            .char(",", .punct), .char("y", .ord)] },
        NodeCase("Greek variants follow TeX", "\\varepsilon\\epsilon\\varphi\\phi") { [.char("ε", .ord), .char("ϵ", .ord), .char("φ", .ord), .char("ϕ", .ord)] },
        NodeCase("upright and italic capitals", "\\Gamma\\varGamma") { [.char("Γ", .ord), .styled(.italic, [.char("Γ", .ord)])] },
        NodeCase("ordinary symbols", "\\infty \\partial \\nabla \\forall \\exists") { [.char("∞", .ord), .char("∂", .ord), .char("∇", .ord),
            .char("∀", .ord), .char("∃", .ord)] },
        NodeCase("binary operators", "\\cdot\\times\\div\\pm\\mp\\cup\\cap") { ["⋅", "×", "÷", "±", "∓", "∪", "∩"].map { .char($0, .bin) } },
        NodeCase("relations table", "\\neq\\approx\\equiv\\sim\\propto\\in\\notin\\subset\\subseteq") { ["≠", "≈", "≡", "∼", "∝", "∈", "∉", "⊂", "⊆"].map { .char($0, .rel) } },
        NodeCase("arrows", "\\to\\Rightarrow\\iff\\mapsto\\leftarrow") { ["→", "⇒", "⟺", "↦", "←"].map { .char($0, .rel) } },
        NodeCase("typed Unicode keeps its class", "α≤β") { [.char("α", .ord), .char("≤", .rel), .char("β", .ord)] },
        NodeCase("typed big operators stay big", "∑") { [.largeOperator("∑", .auto)] },
        NodeCase("escaped characters", "\\{\\}\\|\\%") { [.char("{", .open), .char("}", .close), .char("‖", .ord), .char("%", .ord)] },
        NodeCase("dots", "\\ldots\\cdots\\vdots") { [.char("…", .inner), .char("⋯", .inner), .char("⋮", .ord)] },
        NodeCase("spaces and comments vanish", "  x   % a comment\n y ") { [.char("x", .ord), .char("y", .ord)] },
    ])
    func symbolsAndAtomsKeepTheirTeXClasses(fixture: NodeCase) throws {
        #expect(try Parser.parse(fixture.source) == fixture.expected())
    }

    @Test
    func varlimsupIsAnOverlinedLimitOperator() throws {
        guard case .operatorName(let lim, .auto) = try Parser.parse("\\varlimsup")[0], case .decorated(.overline, _) = lim[0] else {
            Issue.record("varlimsup is an overlined lim")
            return
        }
    }

    @Test
    func poorMansBoldKeepsTheBinaryClass() throws {
        guard case .classed(.bin, _) = try Parser.parse("\\pmb{+}")[0] else { Issue.record("pmb keeps a binary class"); return }
    }

    @Test
    func anEmptyFormulaHasNoNodes() throws {
        #expect(try Parser.parse("").isEmpty, "empty formula")
    }

    @Test(arguments: [
        ErrorCase("unclosed verb", "\\verb|abc",
                  .prefix("\\verb never finds")),
    ])
    func unclosedVerbatimExplainsTheError(fixture: ErrorCase) throws {
        try NoteMathParserTestsSupport.expectError(fixture)
    }
}
