import Foundation

@main @MainActor
struct NoteMathParserTests {
    static func expect(_ value: Bool, _ message: String, line: UInt = #line) {
        if !value { failTest(message, line: line) }
    }

    static func parse(_ source: String, line: UInt = #line) -> [NoteMathNode] {
        do {
            return try NoteMathParser.parse(source)
        } catch {
            failTest("\(source) failed to parse: \(error.message) at \(error.offset)", line: line)
        }
    }

    static func failure(_ source: String, line: UInt = #line) -> NoteMathParseError {
        do {
            let nodes = try NoteMathParser.parse(source)
            failTest("\(source) should fail but parsed as \(nodes)", line: line)
        } catch {
            return error
        }
    }

    static func main() {
        atomsAndClasses()
        scriptsAndPrimes()
        fractionsAndRadicals()
        operatorsAndFunctions()
        delimiters()
        environments()
        fontsTextAndColour()
        accentsSpacingAndMisc()
        errors()
        print("NoteMathParserTests passed")
    }

    static func atomsAndClasses() {
        expect(parse("\\alpha + \\beta") == [.char("α", .ord), .char("+", .bin), .char("β", .ord)], "Greek letters and a binary plus")
        expect(parse("a-b") == [.char("a", .ord), .char("\u{2212}", .bin), .char("b", .ord)], "hyphen becomes a minus sign")
        expect(parse("x \\leq y") == [.char("x", .ord), .char("≤", .rel), .char("y", .ord)], "relations")
        expect(parse("f(x), y") == [.char("f", .ord), .char("(", .open), .char("x", .ord), .char(")", .close),
                                     .char(",", .punct), .char("y", .ord)], "open, close and punctuation")
        expect(parse("\\varepsilon\\epsilon\\varphi\\phi") == [.char("ε", .ord), .char("ϵ", .ord), .char("φ", .ord), .char("ϕ", .ord)],
               "Greek variants follow TeX")
        expect(parse("\\Gamma\\varGamma") == [.char("Γ", .ord), .styled(.italic, [.char("Γ", .ord)])], "upright and italic capitals")
        expect(parse("\\infty \\partial \\nabla \\forall \\exists") == [.char("∞", .ord), .char("∂", .ord), .char("∇", .ord),
                                                                         .char("∀", .ord), .char("∃", .ord)], "ordinary symbols")
        expect(parse("\\cdot\\times\\div\\pm\\mp\\cup\\cap") == ["⋅", "×", "÷", "±", "∓", "∪", "∩"].map { .char($0, .bin) },
               "binary operators")
        expect(parse("\\neq\\approx\\equiv\\sim\\propto\\in\\notin\\subset\\subseteq") ==
               ["≠", "≈", "≡", "∼", "∝", "∈", "∉", "⊂", "⊆"].map { .char($0, .rel) }, "relations table")
        expect(parse("\\to\\Rightarrow\\iff\\mapsto\\leftarrow") == ["→", "⇒", "⟺", "↦", "←"].map { .char($0, .rel) }, "arrows")
        expect(parse("α≤β") == [.char("α", .ord), .char("≤", .rel), .char("β", .ord)], "typed Unicode keeps its class")
        expect(parse("∑") == [.largeOperator("∑", .auto)], "typed big operators stay big")
        expect(parse("\\{\\}\\|\\%") == [.char("{", .open), .char("}", .close), .char("‖", .ord), .char("%", .ord)], "escaped characters")
        expect(parse("\\ldots\\cdots\\vdots") == [.char("…", .inner), .char("⋯", .inner), .char("⋮", .ord)], "dots")
        expect(parse("  x   % a comment\n y ") == [.char("x", .ord), .char("y", .ord)], "spaces and comments vanish")
        expect(parse("").isEmpty, "empty formula")
    }

    static func scriptsAndPrimes() {
        expect(parse("x^2") == [.scripts(base: .char("x", .ord), superscript: [.char("2", .ord)], subscript: nil)], "superscript")
        expect(parse("x_i^2") == parse("x^2_i"), "script order doesn't matter")
        expect(parse("x_{ij}") == [.scripts(base: .char("x", .ord), superscript: nil, subscript: [.char("i", .ord), .char("j", .ord)])],
               "grouped subscript")
        expect(parse("f'") == [.scripts(base: .char("f", .ord), superscript: [.char("′", .ord)], subscript: nil)], "prime")
        expect(parse("f''") == [.scripts(base: .char("f", .ord), superscript: [.char("″", .ord)], subscript: nil)], "double prime")
        expect(parse("f'^2") == [.scripts(base: .char("f", .ord), superscript: [.char("′", .ord), .char("2", .ord)], subscript: nil)],
               "prime then superscript merge")
        expect(parse("f'_1") == [.scripts(base: .char("f", .ord), superscript: [.char("′", .ord)], subscript: [.char("1", .ord)])],
               "prime then subscript")
        expect(parse("^2") == [.scripts(base: nil, superscript: [.char("2", .ord)], subscript: nil)], "script with no base")
        expect(parse("x^\\alpha") == [.scripts(base: .char("x", .ord), superscript: [.char("α", .ord)], subscript: nil)],
               "command as a script")
        expect(parse("e^\\frac12").count == 1, "TeX-style unbraced fraction in a script")
        expect(parse("{x^2}^3").count == 1, "braced base takes another superscript")
    }

    static func fractionsAndRadicals() {
        expect(parse("\\frac{a}{b}") == [.fraction(NoteMathFraction(numerator: [.char("a", .ord)], denominator: [.char("b", .ord)]))],
               "fraction")
        expect(parse("\\frac12") == [.fraction(NoteMathFraction(numerator: [.char("1", .ord)], denominator: [.char("2", .ord)]))],
               "unbraced fraction")
        if case .fraction(let display)? = parse("\\dfrac ab").first { expect(display.level == .display, "dfrac forces display") }
        if case .fraction(let text)? = parse("\\tfrac ab").first { expect(text.level == .text, "tfrac forces text") }
        if case .fraction(let binom)? = parse("\\binom{n}{k}").first {
            expect(!binom.hasRule && binom.left == "(" && binom.right == ")", "binom has parens and no rule")
        } else {
            failTest("binom parses as a fraction")
        }
        expect(parse("{a \\over b}") == [.group([.fraction(NoteMathFraction(numerator: [.char("a", .ord)], denominator: [.char("b", .ord)]))])],
               "infix over")
        expect(parse("\\sqrt{x}") == [.radical([.char("x", .ord)], degree: nil)], "square root")
        expect(parse("\\sqrt[3]{x}") == [.radical([.char("x", .ord)], degree: [.char("3", .ord)])], "cube root")
        expect(parse("\\sqrt[n]2") == [.radical([.char("2", .ord)], degree: [.char("n", .ord)])], "unbraced radicand")
    }

    static func operatorsAndFunctions() {
        expect(parse("\\sum_{i=1}^n") == [.scripts(base: .largeOperator("∑", .auto), superscript: [.char("n", .ord)],
                                                    subscript: [.char("i", .ord), .char("=", .rel), .char("1", .ord)])], "sum with limits")
        expect(parse("\\int_0^1") == [.scripts(base: .largeOperator("∫", .beside), superscript: [.char("1", .ord)],
                                                subscript: [.char("0", .ord)])], "integrals keep limits beside")
        expect(parse("\\int\\limits_0^1").first.map { node in
            if case .scripts(.largeOperator("∫", .above)?, _, _) = node { return true }
            return false
        } == true, "\\limits stacks integral limits")
        expect(parse("\\sum\\nolimits_i") == [.scripts(base: .largeOperator("∑", .beside), superscript: nil, subscript: [.char("i", .ord)])],
               "\\nolimits")
        expect(parse("\\iint\\oint\\bigcup\\prod") == [.largeOperator("∬", .beside), .largeOperator("∮", .beside),
                                                       .largeOperator("⋃", .auto), .largeOperator("∏", .auto)], "more big operators")
        expect(parse("\\lim_{x\\to0}").first == .scripts(base: .function("lim", .auto), superscript: nil,
                                                          subscript: [.char("x", .ord), .char("→", .rel), .char("0", .ord)]), "lim")
        expect(parse("\\sin x") == [.function("sin", .beside), .char("x", .ord)], "sin")
        expect(parse("\\max\\log\\ln\\exp") == [.function("max", .auto), .function("log", .beside), .function("ln", .beside),
                                               .function("exp", .beside)], "function names")
        expect(parse("\\operatorname{Tr} A") == [.operatorName([.char("T", .ord), .char("r", .ord)], .beside), .char("A", .ord)],
               "operatorname")
        expect(parse("\\operatorname*{argmax}_x").first.map { node in
            if case .scripts(.operatorName(_, .auto)?, nil, _) = node { return true }
            return false
        } == true, "operatorname star takes limits")
        expect(parse("a \\bmod b").count == 3, "bmod")
    }

    static func delimiters() {
        expect(parse("\\left( x \\right)") == [.fenced(left: "(", right: ")", middles: [], segments: [[.char("x", .ord)]])], "left right")
        expect(parse("\\left\\{ x \\middle| y \\right.") == [.fenced(left: "{", right: nil, middles: ["|"],
                                                                     segments: [[.char("x", .ord)], [.char("y", .ord)]])], "middle and null")
        expect(parse("\\left\\langle a \\right\\rangle") == [.fenced(left: "⟨", right: "⟩", middles: [], segments: [[.char("a", .ord)]])],
               "angle brackets")
        expect(parse("\\left\\lfloor a \\right\\rceil").first == .fenced(left: "⌊", right: "⌉", middles: [], segments: [[.char("a", .ord)]]),
               "floor and ceiling")
        expect(parse("\\left| a \\right\\|").first == .fenced(left: "|", right: "‖", middles: [], segments: [[.char("a", .ord)]]), "bars")
        expect(parse("\\left[ a \\right]^2").first.map { node in
            if case .scripts(.fenced?, _, nil) = node { return true }
            return false
        } == true, "fence takes scripts")
        expect(parse("\\bigl( x \\bigr)") == [.sizedDelimiter("(", size: 1, kind: .open), .char("x", .ord),
                                              .sizedDelimiter(")", size: 1, kind: .close)], "big delimiters")
        expect(parse("\\Bigg\\uparrow") == [.sizedDelimiter("↑", size: 4, kind: .ord)], "Bigg arrow")
    }

    static func environments() {
        guard case .environment(let matrix)? = parse("\\begin{pmatrix} a & b \\\\ c & d \\end{pmatrix}").first else {
            failTest("pmatrix parses")
        }
        expect(matrix.kind == .matrix && matrix.left == "(" && matrix.right == ")", "pmatrix delimiters")
        expect(matrix.rows.count == 2 && matrix.rows.allSatisfy { $0.count == 2 }, "2 by 2 matrix")
        expect(matrix.columns == [.center, .center], "matrix columns centre")
        for (name, left, right) in [("bmatrix", "[", "]"), ("Bmatrix", "{", "}"), ("vmatrix", "|", "|"), ("Vmatrix", "‖", "‖")] {
            guard case .environment(let environment)? = parse("\\begin{\(name)}1\\end{\(name)}").first else {
                failTest("\(name) parses")
            }
            expect(environment.left == left && environment.right == right, "\(name) delimiters")
        }
        guard case .environment(let trailing)? = parse("\\begin{matrix} 1 \\\\ 2 \\\\ \\end{matrix}").first else {
            failTest("trailing row break parses")
        }
        expect(trailing.rows.count == 2, "a trailing \\\\ doesn't add a row")
        guard case .environment(let cases)? = parse("f(x) = \\begin{cases} 1 & x > 0 \\\\ 0 & \\text{otherwise} \\end{cases}").last else {
            failTest("cases parses")
        }
        expect(cases.kind == .cases && cases.left == "{" && cases.right == nil && cases.columns == [.left, .left], "cases shape")
        guard case .environment(let aligned)? = parse("\\begin{aligned} a &= b \\\\ &= c \\end{aligned}").first else {
            failTest("aligned parses")
        }
        expect(aligned.columns == [.right, .left] && aligned.rows[1][0].isEmpty, "aligned alternates right and left")
        expect(parse("\\begin{align*} x &= 1 \\end{align*}").count == 1, "align*")
        guard case .environment(let gathered)? = parse("\\begin{gathered} a \\\\ b \\end{gathered}").first else {
            failTest("gathered parses")
        }
        expect(gathered.kind == .gathered && gathered.rows.count == 2, "gathered")
        guard case .environment(let array)? = parse("\\begin{array}{|c|l|} \\hline a & b \\\\[2pt] \\hline c & d \\\\ \\hline \\end{array}").first else {
            failTest("array parses")
        }
        expect(array.columns == [.center, .left] && array.columnRules == [0, 1, 2], "array spec with rules")
        expect(array.rowRules == [0, 1, 2] && array.rows.count == 2, "array hlines")
        expect(array.rowSpacing[0] == 0.2, "row spacing after \\\\[2pt]")
    }

    static func fontsTextAndColour() {
        expect(parse("\\mathbb{R}") == [.styled(.doubleStruck, [.char("R", .ord)])], "blackboard bold")
        expect(parse("\\mathcal{L}\\mathfrak{g}\\mathsf{x}\\mathtt{y}\\mathrm{d}\\mathbf{v}\\mathit{w}\\boldsymbol{\\mu}") == [
            .styled(.script, [.char("L", .ord)]), .styled(.fraktur, [.char("g", .ord)]), .styled(.sansSerif, [.char("x", .ord)]),
            .styled(.monospace, [.char("y", .ord)]), .styled(.roman, [.char("d", .ord)]), .styled(.bold, [.char("v", .ord)]),
            .styled(.italic, [.char("w", .ord)]), .styled(.boldItalic, [.char("μ", .ord)]),
        ], "font commands")
        expect(parse("\\text{if } x") == [.text("if ", .roman), .char("x", .ord)], "text keeps its spaces")
        expect(parse("\\text{a  {b}\\%}") == [.text("a b%", .roman)], "text collapses spaces and unescapes")
        expect(parse("\\textbf{Hi}") == [.text("Hi", .bold)], "bold text")
        expect(parse("\\text{for $x>0$}").first.map { node in
            if case .group(let parts) = node, parts.count == 2, case .mathStyle(.text, let math) = parts[1] { return math.count == 3 }
            return false
        } == true, "inline math inside text")
        let red = NoteMathColor(red: 1, green: 0, blue: 0)
        expect(parse("a \\color{red} b + c") == [.char("a", .ord), .colored(red, [.char("b", .ord), .char("+", .bin), .char("c", .ord)])],
               "colour switch covers the rest of the group")
        expect(parse("\\textcolor{#00f}{y} z") == [.colored(NoteMathColor(red: 0, green: 0, blue: 1), [.char("y", .ord)]), .char("z", .ord)],
               "textcolor with short hex")
        expect(parse("\\color{FF8000}x") == [.colored(NoteMathColor(red: 1, green: 128.0 / 255, blue: 0), [.char("x", .ord)])], "bare hex colour")
        expect(parse("{\\displaystyle x}") == [.group([.mathStyle(.display, [.char("x", .ord)])])], "style switch")
    }

    static func accentsSpacingAndMisc() {
        expect(parse("\\hat{x}") == [.decorated(.accent("\u{0302}"), [.char("x", .ord)])], "hat")
        expect(parse("\\vec v") == [.decorated(.accent("\u{20D7}"), [.char("v", .ord)])], "unbraced vec")
        expect(parse("\\widehat{AB}") == [.decorated(.wideAccent("\u{0302}"), [.char("A", .ord), .char("B", .ord)])], "widehat")
        expect(parse("\\overline{z}\\underline{w}") == [.decorated(.overline, [.char("z", .ord)]), .decorated(.underline, [.char("w", .ord)])],
               "overline and underline")
        expect(parse("\\overbrace{a+b}^{n}").first.map { node in
            if case .scripts(.decorated(.overbrace, _)?, [.char("n", .ord)]?, nil) = node { return true }
            return false
        } == true, "overbrace label")
        expect(parse("\\underbrace{x}_{k}").count == 1, "underbrace label")
        expect(parse("\\overrightarrow{AB}") == [.decorated(.overArrow("→"), [.char("A", .ord), .char("B", .ord)])], "over arrow")
        let spaces: [Double] = parse("a\\,b\\:c\\;d\\!e\\quad f\\qquad g~h").compactMap { node in
            if case .space(let amount) = node { return amount }
            return nil
        }
        let expectedSpaces: [Double] = [3.0 / 18, 4.0 / 18, 5.0 / 18, -3.0 / 18, 1, 2, 1.0 / 3]
        expect(spaces == expectedSpaces, "spacing commands")
        expect(parse("\\hspace{2em}\\mkern18mu") == [.space(2), .space(1)], "explicit spaces")
        expect(parse("\\not= \\not\\in \\not<") == [.char("≠", .rel), .char("∉", .rel), .char("≮", .rel)], "negations")
        expect(parse("\\overset{!}{=}") == [.stacked(base: [.char("=", .rel)], over: [.char("!", .close)], under: nil)], "overset")
        expect(parse("\\stackrel{def}{=}").first.map { node in
            if case .classed(.rel, _) = node { return true }
            return false
        } == true, "stackrel is a relation")
        expect(parse("a \\\\ b") == [.lines([[.char("a", .ord)], [.char("b", .ord)]])], "top-level line breaks")
        expect(parse("\\boxed{x}\\phantom{y}") == [.boxed([.char("x", .ord)]), .phantom([.char("y", .ord)], keepsWidth: true, keepsHeight: true)],
               "boxed and phantom")
        expect(parse("\\mathrel{x}\\mathbin{y}") == [.classed(.rel, [.char("x", .ord)]), .classed(.bin, [.char("y", .ord)])], "math classes")
    }

    static func errors() {
        let missingArgument = failure("\\frac{a}")
        expect(missingArgument.message == "\\frac needs 2 arguments", "missing argument message: \(missingArgument.message)")
        let double = failure("x^2^3")
        expect(double.message.hasPrefix("Double superscript") && double.offset == 3 && double.length == 1, "double superscript at the second ^")
        expect(failure("x_1_2").message.hasPrefix("Double subscript"), "double subscript")
        expect(failure("x^2'").message.hasPrefix("Double superscript"), "prime after superscript")
        let open = failure("a + {x")
        expect(open.message == "Missing } to close this {" && open.offset == 4, "unclosed brace points at the brace")
        let close = failure("x}")
        expect(close.message == "There's a } without a matching {" && close.offset == 1, "stray brace")
        let unknown = failure("1 + \\foo")
        expect(unknown.message == "Unknown command \\foo" && unknown.offset == 4 && unknown.length == 4, "unknown command range")
        let wide = failure("😀 \\foo")
        expect(wide.offset == 3, "offsets count UTF-16 units")
        let fence = failure("\\left( x")
        expect(fence.message == "Missing \\right to close this \\left" && fence.offset == 0, "unclosed left")
        expect(failure("x \\right)").message == "\\right without a matching \\left", "stray right")
        expect(failure("\\middle|").message.hasPrefix("\\middle only works"), "stray middle")
        expect(failure("\\left x \\right)").message.hasPrefix("\\left needs a delimiter"), "left needs a delimiter")
        let mismatch = failure("\\begin{matrix} a \\end{pmatrix}")
        expect(mismatch.message == "\\begin{matrix} ends with \\end{pmatrix}", "mismatched environment")
        expect(failure("\\begin{matrix} a").message == "Missing \\end{matrix}", "unclosed environment")
        expect(failure("\\begin{foo} a \\end{foo}").message == "Unknown environment \u{201C}foo\u{201D}", "unknown environment")
        expect(failure("\\begin{array}{cx} a \\end{array}").message == "Array columns only take l, c, r and |", "bad array spec")
        expect(failure("\\begin{array}{c} a & b \\end{array}").message.hasPrefix("This row has more columns"), "too many cells")
        expect(failure("\\begin{gathered} a & b \\end{gathered}").message == "gathered doesn't use &", "gathered has one column")
        expect(failure("a & b").message.hasPrefix("& only works"), "stray ampersand")
        expect(failure("\\color{nope}{x}").message == "Unknown colour \u{201C}nope\u{201D}", "unknown colour")
        expect(failure("x^").message == "^ needs something to raise", "empty superscript")
        expect(failure("x_}").message == "_ needs something to lower", "empty subscript")
        expect(failure("\\sqrt[3").message == "Missing ] to close this [", "unclosed degree")
        expect(failure("\\text{abc").message == "Missing } to close this \\text", "unclosed text")
        expect(failure("\\text{\\alpha}").message == "\\alpha doesn't work inside \\text", "math command in text")
        expect(failure("$x$").message.hasPrefix("You're already in math mode"), "dollar signs")
        expect(failure("\\hspace{2furlongs}").message.hasSuffix("isn't a size I understand, like 1em or 3mu"), "bad size")
        expect(failure("x\\").message == "A lone \\ needs a command name after it", "lone backslash")
        expect(parse("\\sum\\limits\\limits").count == 1, "limits twice is fine")
        expect(failure("x\\limits").message.hasPrefix("\\limits has to come right after"), "limits needs an operator")
        expect(failure(String(repeating: "{", count: 400)).message == "This formula nests too deep to draw", "deep nesting is caught")
        expect(failure("{a \\over b \\over c}").message.hasPrefix("Only one \\over"), "ambiguous over")
    }
}
