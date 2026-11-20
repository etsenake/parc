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

    static func katexBoxesSizesAndLinks() {
        expect(parse("a \\Huge b c") == [.char("a", .ord), .sized(2.488, [.char("b", .ord), .char("c", .ord)])], "size switches cover the rest")
        expect(parse("{\\tiny x} y") == [.group([.sized(0.5, [.char("x", .ord)])]), .char("y", .ord)], "size switches stop at the brace")
        let sizes = ["tiny": 0.5, "scriptsize": 0.7, "footnotesize": 0.8, "small": 0.9, "normalsize": 1.0, "large": 1.2,
                     "Large": 1.44, "LARGE": 1.728, "huge": 2.074, "Huge": 2.488]
        for (name, factor) in sizes { expect(parse("\\\(name) x") == [.sized(factor, [.char("x", .ord)])], "\\\(name) is \(factor)") }
        expect(parse("\\raisebox{0.25em}{hi}") == [.raised(0.25, [.text("hi", .roman)])], "raisebox lifts text")
        expect(parse("\\raisebox{-.1em}{$x$}") == [.raised(-0.1, [.mathStyle(.text, [.char("x", .ord)])])], "raisebox takes math in dollars")
        expect(parse("\\smash{y}") == [.smashed([.char("y", .ord)], top: true, bottom: true)], "smash flattens both sides")
        expect(parse("\\smash[t]{y}") == [.smashed([.char("y", .ord)], top: true, bottom: false)], "smash t keeps depth")
        expect(parse("\\smash[b]{y}") == [.smashed([.char("y", .ord)], top: false, bottom: true)], "smash b keeps height")
        expect(failure("\\smash[x]{y}").message == "\\smash takes [t] or [b], not [x]", "smash rejects other options")
        expect(parse("\\sum_{\\substack{i<n\\\\j}}") == [.scripts(base: .largeOperator("\u{2211}", .auto), superscript: nil,
               subscript: [.substack([[.char("i", .ord), .char("<", .rel), .char("n", .ord)], [.char("j", .ord)]])])], "substack splits rows")
        expect(failure("\\substack{a").message == "Missing } to close this {", "unclosed substack")
        guard case .fraction(let general) = parse("\\genfrac(]{0pt}{2}{a}{b}")[0] else { failTest("genfrac is a fraction") }
        expect(general.left == "(" && general.right == "]" && !general.hasRule && general.level == .script, "genfrac reads delimiters, rule and style")
        guard case .fraction(let thick) = parse("\\genfrac{}{}{2pt}{}{a}{b}")[0] else { failTest("genfrac thickness") }
        expect(thick.hasRule && thick.thickness == 0.2 && thick.left == nil && thick.level == nil, "genfrac keeps a custom rule")
        guard case .fraction(let curly) = parse("\\genfrac{\\{}{\\}}{}{0}{a}{b}")[0] else { failTest("genfrac curly") }
        expect(curly.left == "{" && curly.right == "}" && curly.level == .display, "genfrac takes brace delimiters")
        expect(failure("\\genfrac(){}{7}{a}{b}").message.hasPrefix("\\genfrac styles"), "bad genfrac style")
        let red = NoteMathSymbols.color(named: "red")!, blue = NoteMathSymbols.color(named: "blue")!
        expect(parse("\\colorbox{red}{hi}") == [.colorBox(red, frame: nil, [.text("hi", .roman)])], "colorbox")
        expect(parse("\\fcolorbox{blue}{red}{a $x$}") == [.colorBox(red, frame: blue, [.text("a ", .roman), .mathStyle(.text, [.char("x", .ord)])])],
               "fcolorbox takes frame then background")
        expect(parse("\\href{https://katex.org/}{x}") == [.link("https://katex.org/", [.char("x", .ord)])], "href wraps math")
        expect(parse("\\url{https://a.b/c\\#d\\_e}") == [.link("https://a.b/c#d_e", [.text("https://a.b/c#d_e", .monospace)])], "url unescapes")
        expect(failure("\\url{}").message.hasPrefix("\\url needs a link"), "empty url")
        expect(parse("\\rule[0.1em]{1em}{2pt}") == [.rule(width: 1, height: 0.2, raise: 0.1)], "rule with a lift")
        expect(parse("\\overgroup{AB}") == [.decorated(.overArrow("\u{23E0}"), [.char("A", .ord), .char("B", .ord)])], "overgroup")
        expect(parse("\\undergroup{AB}") == [.decorated(.underArrow("\u{23E1}"), [.char("A", .ord), .char("B", .ord)])], "undergroup")
        for name in ["tiny", "Huge", "raisebox", "smash", "substack", "genfrac", "colorbox", "fcolorbox", "href", "url", "overgroup", "tripledash"] {
            expect(NoteMathParser.isBuiltIn(name), "\\\(name) is built in")
        }
        let wavy = String(describing: parse("\\ce{A\\bond{~-}B}"))
        expect(wavy.contains("raised(-0.1") && wavy.contains("sized(0.5"), "a dashed bond stacks a raised line over a tiny triple dash")
        for bond in ["~", "~-", "~=", "~--", "-~-", "...", "...."] { _ = parse("\\ce{C\\bond{\(bond)}C}") }
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
        macros()
        macroErrors()
        delimitedParameters()
        expansionPrimitives()
        cellScopes()
        katexBoxesSizesAndLinks()
        katexEnvironments()
        commutativeDiagrams()
        chemistry()
        units()
        mhchemManual()
        tags()
        labels()
        print("NoteMathParserTests passed")
    }

    static func katexEnvironments() {
        guard case .environment(let alignat)? = parse("\\begin{alignat}{2} a &= b & c &= d \\\\ e &= f \\end{alignat}").first else {
            failTest("alignat parses")
        }
        expect(alignat.kind == .alignedAt && alignat.columns == [.right, .left, .right, .left], "alignat takes its column pairs")
        expect(alignat.tags == [[.text("(1)", .roman)], [.text("(2)", .roman)]], "alignat numbers every row: \(alignat.tags)")
        guard case .environment(let alignedat)? = parse("\\begin{alignedat}{1} a &= b \\end{alignedat}").first else {
            failTest("alignedat parses")
        }
        expect(alignedat.kind == .alignedAt && alignedat.tags.isEmpty, "alignedat never numbers")
        expect(parse("\\begin{alignat*}{1} a &= b \\\\ c &= d \\end{alignat*}").first.map { node in
            if case .environment(let environment) = node { return environment.tags.isEmpty }
            return false
        } == true, "alignat* stays unnumbered")
        expect(failure("\\begin{alignat}{1} a &= b & c \\end{alignat}").message.contains("more columns"), "alignat caps the pairs")
        expect(failure("\\begin{alignat}{x} a \\end{alignat}").message.contains("column pairs"), "alignat needs a count")
        guard case .environment(let multline)? = parse("\\begin{multline} a + b \\\\ c \\label{long} \\\\ d \\end{multline}").first else {
            failTest("multline parses")
        }
        expect(multline.kind == .multline && multline.rows.count == 3, "multline keeps its lines")
        expect(multline.tags == [nil, nil, [.text("(1)", .roman)]], "multline takes one number on its last line: \(multline.tags)")
        guard case .environment(let quiet)? = parse("\\begin{multline*} a \\\\ b \\\\ \\end{multline*}").first else {
            failTest("multline* parses")
        }
        expect(quiet.tags.isEmpty && quiet.rows.count == 2, "multline* stays unnumbered and drops a trailing break")
        guard case .environment(let tagged)? = parse("\\begin{multline} a \\tag{M} \\\\ b \\end{multline}").first else {
            failTest("tagged multline parses")
        }
        expect(tagged.tags.count == 2 && tagged.tags[0] == nil && tagged.tags[1] != nil, "a multline tag lands on the last line")
        expect(failure("\\begin{multline} a & b \\end{multline}").message.contains("doesn't use &"), "multline has one column")
        guard case .environment(let subarray)? = parse("\\begin{subarray}{l} i < n \\\\ j < m \\end{subarray}").first else {
            failTest("subarray parses")
        }
        expect(subarray.kind == .subarray && subarray.columns == [.left] && subarray.rows.count == 2, "subarray is one left column")
        expect(failure("\\begin{subarray}{cc} a \\end{subarray}").message.contains("single column"), "subarray takes one column")
        expect(failure("\\begin{subarray}{r} a \\end{subarray}").message.contains("single column"), "subarray takes only c or l")
        expect(failure("\\begin{subarray}{c} a & b \\end{subarray}").message.contains("more columns"), "subarray rejects &")
        guard case .environment(let dcases)? = parse("\\begin{dcases} \\frac12 & x > 0 \\end{dcases}").first,
              case .environment(let drcases)? = parse("\\begin{drcases} a & b \\end{drcases}").first,
              case .environment(let darray)? = parse("\\begin{darray}{rl} a & b \\end{darray}").first,
              case .environment(let plainCases)? = parse("\\begin{cases} a & b \\end{cases}").first else {
            failTest("display-style environments parse")
        }
        expect(dcases.kind == .cases && dcases.displayCells && dcases.left == "{" && dcases.columns == [.left, .left], "dcases")
        expect(drcases.kind == .cases && drcases.displayCells && drcases.right == "}" && drcases.left == nil, "drcases")
        expect(darray.kind == .array && darray.displayCells && darray.columns == [.right, .left], "darray")
        expect(!plainCases.displayCells, "cases stays text style")
        guard case .environment(let starred)? = parse("\\begin{pmatrix*}[r] 1 & -1 \\\\ -10 & 2 \\end{pmatrix*}").first,
              case .environment(let centred)? = parse("\\begin{bmatrix*} 1 & 2 \\end{bmatrix*}").first else {
            failTest("starred matrices parse")
        }
        expect(starred.kind == .matrix && starred.left == "(" && starred.columns == [.right, .right], "pmatrix* lines columns up")
        expect(centred.left == "[" && centred.columns == [.center, .center], "matrix* defaults to centred")
        expect(failure("\\begin{Vmatrix*}[x] 1 \\end{Vmatrix*}").message.contains("[l], [c] or [r]"), "matrix* checks its alignment")
        guard case .environment(let dashed)? = parse("\\begin{array}{c:c|c} a & b & c \\\\ \\hdashline d & e & f \\\\ \\hline \\end{array}").first else {
            failTest("dashed array parses")
        }
        expect(dashed.columnRules == [1, 2] && dashed.columnRuleDashes == [true, false], "colons draw dashed columns")
        expect(dashed.rowRules == [1, 2] && dashed.rowRuleDashes == [true, false], "hdashline draws a dashed row rule")
    }

    static func commutativeDiagrams() {
        let source = "\\begin{CD} A @>a>b> B \\\\ @VcVdV @AAA \\\\ C @<<< D @= E \\\\ @| @. \\\\ \\end{CD}"
        guard case .environment(let diagram)? = parse(source).first else { failTest("CD parses") }
        expect(diagram.kind == .commutativeDiagram && diagram.rows.count == 4 && diagram.arrows.count == 4, "CD keeps object and arrow rows")
        expect(diagram.rows[0].count == 3 && diagram.rows[0][0] == parse("A") && diagram.rows[0][2] == parse("B"), "objects sit between arrows")
        expect(diagram.arrows[0][1] == NoteMathDiagramArrow(direction: .right, first: parse("a"), second: parse("b")),
               "@>a>b> puts a above and b below: \(diagram.arrows[0])")
        expect(diagram.arrows[0][0] == nil && diagram.arrows[0][2] == nil, "object cells aren't arrows")
        expect(diagram.arrows[1].count == 3 && diagram.arrows[1][0] == NoteMathDiagramArrow(direction: .down, first: parse("c"), second: parse("d")),
               "@VcVdV labels both sides: \(diagram.arrows[1])")
        expect(diagram.arrows[1][2]?.direction == .up && diagram.arrows[1][1] == nil, "@AAA points up under the next object")
        expect(diagram.arrows[2][1]?.direction == .left && diagram.arrows[2][3]?.direction == .equals, "@<<< and @=")
        expect(diagram.arrows[3][0]?.direction == .parallel && diagram.arrows[3][2]?.direction == .empty, "@| and @.")
        expect(diagram.columns == Array(repeating: .center, count: 5), "CD centres every column")
        expect((try? NoteMathParser.parseEquation(source, display: true).automaticNumbers) == 0, "CD never takes a number")
        expect(failure("\\begin{CD} A @>a B \\end{CD}").message.contains("needs another >"), "an unfinished arrow says so")
        expect(failure("\\begin{CD} A @>a @>>> B \\end{CD}").message.contains("needs another >"), "a new arrow can't start inside a label")
        expect(failure("\\begin{CD} A @x B \\end{CD}").message.contains("follow it with"), "unknown arrow letters explain themselves")
        expect(failure("\\begin{CD} A @>>> B").message == "Missing \\end{CD}", "an unclosed CD")
        expect(failure("\\begin{CD} A \\end{matrix}").message.contains("ends with"), "mismatched CD end")
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
        expect(parse("\\xrightarrow[a]{b}") == [.extensibleArrow("→", over: [.char("b", .ord)], under: [.char("a", .ord)])],
               "labelled arrow with both labels")
        expect(parse("\\xLeftarrow{}") == [.extensibleArrow("⇐", over: [], under: nil)], "empty labelled arrow")
        expect(parse("\\cancel{x}\\bcancel{y}\\xcancel{z}\\sout{w}") == [
            .decorated(.cancel, [.char("x", .ord)]), .decorated(.backCancel, [.char("y", .ord)]),
            .decorated(.crossCancel, [.char("z", .ord)]), .decorated(.strike, [.char("w", .ord)]),
        ], "cancel family")
        expect(parse("\\R\\N\\Z\\Q\\C") == ["ℝ", "ℕ", "ℤ", "ℚ", "ℂ"].map { .char($0, .ord) }, "number set shorthands")
        expect(parse("f\\colon A \\ltimes B") == [.char("f", .ord), .group([.space(2.0 / 18), .char(":", .punct), .space(6.0 / 18)]),
                                                .char("A", .ord), .char("⋉", .bin), .char("B", .ord)],
               "colon spaces like amsmath and ltimes is binary")
        expect(parse("\\llap{a}\\mathrlap{b}\\clap{c}") == [.lap(.left, [.char("a", .ord)]), .lap(.right, [.char("b", .ord)]),
                                                               .lap(.center, [.char("c", .ord)])], "laps")
        expect(parse("\\mathrel{x}\\mathbin{y}") == [.classed(.rel, [.char("x", .ord)]), .classed(.bin, [.char("y", .ord)])], "math classes")
    }

    static func contains(_ nodes: [NoteMathNode], _ predicate: (NoteMathNode) -> Bool) -> Bool {
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

    static func arrow(_ nodes: [NoteMathNode]) -> (String, [NoteMathNode], [NoteMathNode]?)? {
        for node in nodes {
            if case .extensibleArrow(let symbol, let over, let under) = node { return (symbol, over, under) }
            if case .group(let content) = node, let found = arrow(content) { return found }
        }
        return nil
    }

    static func macros() {
        expect(parse("\\newcommand{\\RR}{\\mathbb{R}} \\RR^n") == parse("\\mathbb{R}^n"), "newcommand without arguments")
        expect(parse("\\newcommand\\sq[1]{#1^2} \\sq{a}+\\sq b") == parse("a^2+b^2"), "argument count with braced and bare arguments")
        expect(parse("\\newcommand{\\pair}[2][0]{(#1,#2)} \\pair{x} \\pair[1]{y}") == parse("(0,x) (1,y)"), "optional argument with a default")
        expect(parse("\\newcommand*{\\one}{1}\\one") == parse("1"), "starred newcommand")
        expect(parse("\\newcommand{\\e}{e}\\renewcommand{\\e}{f}\\e") == parse("f"), "renewcommand replaces a macro")
        expect(parse("\\renewcommand{\\alpha}{a}\\alpha") == parse("a"), "renewcommand can redefine a built-in")
        expect(parse("\\providecommand{\\pi}{p}\\providecommand{\\q}{q}\\pi\\q") == parse("\\pi q"), "providecommand only fills gaps")
        expect(parse("\\def\\f#1#2{#1+#2}\\f ab") == parse("a+b"), "def with parameter text")
        expect(parse("\\def\\g{x}\\g\\g") == parse("xx"), "def without parameters")
        expect(parse("\\def\\g{\\alpha}\\g x") == parse("\\alpha x"), "expansions keep control words apart from letters")
        expect(parse("\\let\\a\\alpha \\a") == parse("\\alpha"), "let copies a built-in")
        expect(parse("\\let\\a=\\beta\\a") == parse("\\beta"), "let with an equals sign")
        expect(parse("\\def\\b{y}\\let\\c=\\b \\def\\b{z}\\c\\b") == parse("yz"), "let snapshots a macro's meaning")
        expect(parse("\\renewcommand{\\beta}{b}\\let\\c\\alpha\\renewcommand{\\alpha}{a}\\c") == parse("\\alpha"), "let snapshots a built-in")
        expect(parse("{\\def\\h{1}\\h}") == parse("{1}"), "definitions work inside their group")
        expect(failure("{\\def\\h{1}}\\h").message == "Unknown command \\h", "definitions end with their group")
        expect(parse("{\\gdef\\k{w}}\\k") == parse("{}w"), "gdef escapes its group")
        expect(parse("{\\global\\def\\m{v}}\\m") == parse("{}v"), "global prefix")
        expect(parse("\\def\\n{a}\\edef\\o{\\n}\\def\\n{b}\\o") == parse("a"), "edef expands when defined")
        expect(parse("\\def\\outer{\\def\\inner##1{##1!}}\\outer\\inner x") == parse("x!"), "## builds nested parameters")
        expect(parse("\\newcommand{\\abs}[1]{\\left|#1\\right|}\\abs{\\abs{x}}") == parse("\\left|\\left|x\\right|\\right|"), "macros nest")
        expect(parse("\\newcommand{\\ip}[2]{\\langle #1, #2 \\rangle}\\ip{\\frac12}{y}") == parse("\\langle \\frac12, y \\rangle"),
               "arguments carry structure")
        let many = "\\def\\a{x}" + String(repeating: "\\a", count: 900)
        expect(parse(many).count == 900, "hundreds of expansions are fine")
        expect(parse("% \\def\\a{b}\n a") == parse("a"), "definitions in comments are ignored")
    }

    static func macroErrors() {
        let loop = failure("\\def\\a{\\a}\\a")
        expect(loop.message == "\\a keeps expanding (over 1,000 times). Is it calling itself?" && loop.offset == 10 && loop.length == 2,
               "runaway recursion is caught at the call: \(loop.message) \(loop.offset) \(loop.length)")
        expect(failure("\\def\\a{\\a\\a}\\a").message.hasPrefix("\\a keeps expanding"), "exponential recursion is caught")
        expect(failure("\\newcommand{\\b}{\\c}\\newcommand{\\c}{\\b}\\b").message.hasPrefix("\\b keeps expanding"), "mutual recursion is caught")
        let taken = failure("\\newcommand{\\alpha}{x}")
        expect(taken.message == "\\alpha already means something; use \\renewcommand to change it" && taken.offset == 12 && taken.length == 6,
               "newcommand refuses to clobber")
        expect(failure("\\newcommand{\\f}{x}\\newcommand{\\f}{y}").message.hasPrefix("\\f already means something"), "newcommand twice")
        expect(failure("\\renewcommand{\\nope}{x}").message == "\\nope isn't defined yet, so use \\newcommand", "renewcommand needs a definition")
        expect(failure("\\newcommand{\\f}[1]{#2}").message == "\\f only takes 1 argument, so there's no #2", "parameter out of range")
        expect(failure("\\newcommand{\\f}[10]{x}").message == "The number of arguments has to be 0 to 9", "argument count range")
        expect(failure("\\def\\f#2{x}").message.hasPrefix("\\def parameters have to be #1, #2"), "def parameters in order")
        let short = failure("\\newcommand{\\x}[3]{#1#2#3}\\x ab")
        expect(short.message == "\\x needs 3 arguments" && short.offset == 26 && short.length == 2, "missing macro argument")
        let inner = failure("\\newcommand{\\y}{\\frac{a}}\\y")
        expect(inner.message == "\\frac needs 2 arguments" && inner.offset == 25 && inner.length == 2, "errors inside a macro point at its use")
        expect(failure("\\newcommand").message.hasPrefix("\\newcommand needs a command name"), "newcommand needs a name")
        expect(failure("\\newcommand{\\z}").message == "\\newcommand{\\z} needs a definition in braces", "newcommand needs a body")
        expect(failure("\\def\\z").message.hasPrefix("\\def\\z needs a definition"), "def needs a body")
        expect(failure("\\newcommand{\\z}{x").message == "Missing } to close this {", "unclosed definition")
    }

    static func delimitedParameters() {
        expect(parse("\\def\\pt(#1,#2){#1+#2}\\pt(a,b)") == parse("a+b"), "delimiters around and between parameters")
        expect(parse("\\def\\foo#1.{[#1]}\\foo abc.d") == parse("[abc]d"), "an argument runs to its delimiter")
        expect(parse("\\def\\foo#1.{[#1]}\\foo {a.b}.") == parse("[a.b]"), "braces hide the delimiter and come off")
        expect(parse("\\def\\foo#1.{[#1]}\\foo {a}{b}.") == parse("[{a}{b}]"), "braces stay when they don't wrap the whole argument")
        expect(parse("\\def\\foo#1.{[#1]}\\foo .") == parse("[]"), "an empty delimited argument")
        expect(parse("\\def\\foo#1\\stop{(#1)}\\foo xy\\stop") == parse("(xy)"), "a command works as a delimiter")
        expect(parse("\\def\\foo#1#2;{#2#1}\\foo ab c;") == parse("bca"), "undelimited then delimited")
        expect(parse("\\def\\foo#1 #2.{#2#1}\\foo x y.") == parse("yx"), "a space is a delimiter too")
        expect(parse("\\def\\foo.#1{#1!}\\foo.x") == parse("x!"), "text before the first parameter has to match")
        expect(parse("\\def\\foo#1#{#1\\boxed}\\foo ab{c}") == parse("ab\\boxed{c}"), "#{ stops at a brace and leaves it")
        expect(parse("\\def\\foo#1.{#1}\\def\\bar{\\foo x.}\\bar") == parse("x"), "delimited macros inside macros")
        expect(parse("\\def\\cs#1.#2.{#2#1}\\cs a.b.") == parse("ba"), "two delimited parameters")
        expect(parse("\\def\\ab#1ab{[#1]}\\ab aab") == parse("[a]"), "the shortest argument that the delimiter follows")
        let mismatch = failure("\\def\\foo.#1{#1}\\foo x")
        expect(mismatch.message == "\\foo has to be followed by \u{201C}.\u{201D}, the way it was defined" && mismatch.offset == 15,
               "a prefix that doesn't match: \(mismatch.message)")
        let runaway = failure("\\def\\foo#1.{#1}\\foo abc")
        expect(runaway.message == "\\foo never finds the \u{201C}.\u{201D} that ends its argument" && runaway.offset == 15,
               "a missing delimiter: \(runaway.message)")
        expect(failure("{\\def\\foo#1.{#1}\\foo a}.").message == "\\foo's argument has an extra }", "a brace can't close mid-argument")
        expect(failure("\\def\\foo#1}{x}").message == "\\def\\foo has a } before its definition starts", "stray brace in parameter text")
    }

    static func expansionPrimitives() {
        expect(parse("\\def\\a{x.y}\\def\\b#1.{[#1]}\\expandafter\\b\\a") == parse("[x]y"), "expandafter expands the second token first")
        expect(failure("\\def\\a{x.y}\\def\\b#1.{[#1]}\\b\\a").message.hasPrefix("\\b never finds"), "without expandafter the macro sees \\a")
        expect(parse("\\def\\a{1}\\def\\b{\\a}\\def\\c#1.{[#1]}\\expandafter\\expandafter\\expandafter\\c\\b.") == parse("[1]"),
               "expandafter chains expand twice")
        expect(parse("\\def\\a{1}\\edef\\b{\\noexpand\\a\\a}\\def\\a{2}\\b") == parse("21"), "noexpand keeps a command for later in edef")
        expect(parse("\\noexpand\\alpha") == parse("\\alpha"), "noexpand on a built-in")
        expect(parse("x\\def\\q{1}\\noexpand\\q y") == parse("xy"), "noexpand on a macro acts like relax")
        expect(parse("\\csname alpha\\endcsname") == parse("\\alpha"), "csname builds a command")
        expect(parse("\\expandafter\\def\\csname my thing\\endcsname{z}\\csname my thing\\endcsname") == parse("z"),
               "csname defines and uses a macro, spaces and all")
        expect(parse("\\def\\n{al}\\csname\\n pha\\endcsname") == parse("\\alpha"), "macros expand inside csname")
        expect(parse("x\\csname nothinghere\\endcsname y") == parse("xy"), "an undefined csname is a no-op")
        expect(parse("\\expandafter\\let\\csname b\\endcsname\\beta \\b") == parse("\\beta"), "csname with let")
        expect(parse("\\expandafter\\newcommand\\csname sq\\endcsname[1]{#1^2}\\sq{y}") == parse("y^2"), "csname with newcommand")
        expect(parse("\\csname alpha\\endcsname b") == parse("\\alpha b"), "a built name stays apart from the next letter")
        let open = failure("x \\csname alpha")
        expect(open.message == "\\csname needs an \\endcsname to finish the name" && open.offset == 2, "csname needs its end")
        expect(failure("\\csname \\alpha\\endcsname").message == "\\csname builds names from letters and symbols, so \\alpha can't go inside",
               "csname refuses commands that don't expand")
        expect(failure("\\expandafter").message == "\\expandafter needs two things after it", "expandafter needs tokens")
        expect(failure("\\def\\a{\\expandafter\\a\\a}\\a").message.contains("keeps expanding"), "expandafter loops hit the limit")
        expect(failure("\\def\\a{\\csname a\\endcsname}\\a").message.contains("keeps expanding"), "csname loops hit the limit")
        expect(parse("% \\csname alpha\\endcsname\n a") == parse("a"), "primitives in comments are ignored")
    }

    static func cellScopes() {
        expect(parse("\\begin{matrix}\\def\\x{1}\\x & 2\\end{matrix}") == parse("\\begin{matrix}1 & 2\\end{matrix}"),
               "a definition works in its own cell")
        expect(failure("\\begin{matrix}\\def\\x{1}\\x & \\x\\end{matrix}").message == "Unknown command \\x", "a definition ends with its cell")
        expect(failure("\\begin{aligned} \\def\\y{a} \\y \\\\ \\y \\end{aligned}").message == "Unknown command \\y", "a new row starts fresh")
        expect(failure("\\begin{matrix}\\def\\z{1}\\end{matrix}\\z").message == "Unknown command \\z", "nothing leaks out of an environment")
        expect(parse("\\begin{matrix}\\gdef\\w{1}\\end{matrix}\\w") == parse("\\begin{matrix}\\end{matrix}1"), "gdef still escapes a cell")
        expect(parse("\\def\\v{3}\\begin{matrix}\\v & \\v\\end{matrix}") == parse("\\begin{matrix}3 & 3\\end{matrix}"),
               "outer macros reach every cell")
        expect(parse("\\begin{array}{cc}\\def\\u{4}\\u & 5\\end{array}") == parse("\\begin{array}{cc}4 & 5\\end{array}"),
               "array column specs don't confuse scopes")
        expect(failure("\\begin{matrix}\\begin{matrix}\\def\\t{1}\\t\\end{matrix} & \\t\\end{matrix}").message == "Unknown command \\t",
               "nested environments scope their own cells")
        expect(parse("\\begin{matrix}{\\def\\s{1}\\s} & 2\\end{matrix}") == parse("\\begin{matrix}{1} & 2\\end{matrix}"),
               "groups still work inside cells")
    }

    static func chemistry() {
        expect(parse("\\ce{H2O}") == parse("{\\mathrm{H}_{2}\\mathrm{O}}"), "subscripted formula")
        expect(parse("\\ce{Fe2(SO4)3}") == parse("{\\mathrm{Fe}_{2}(\\mathrm{S}\\mathrm{O}_{4})_{3}}"), "parentheses take subscripts")
        expect(parse("\\ce{SO4^2-}") == parse("{\\mathrm{S}\\mathrm{O}_{4}^{2-}}"), "charge over a subscript")
        expect(parse("\\ce{Na+}") == parse("{\\mathrm{Na}^{+}}") && parse("\\ce{NO3-}") == parse("{\\mathrm{N}\\mathrm{O}_{3}^{-}}"),
               "trailing charges")
        expect(parse("\\ce{Fe^{3+}}") == parse("\\ce{Fe^3+}"), "braced and bare charges")
        expect(parse("\\ce{^{14}_{6}C}") == parse("{{}^{\\hphantom{14}}_{\\hphantom{6}}{}^{\\mathllap{14}}_{\\mathllap{6}}\\mathrm{C}}"),
               "isotope prescripts line up on the right")
        expect(parse("\\ce{{}^{14}_{6}C}") == parse("\\ce{^{14}_{6}C}"), "braced isotope form")
        expect(parse("\\ce{2H2O}") == parse("{2\\mathrm{H}_{2}\\mathrm{O}}"), "stoichiometric number")
        expect(parse("\\ce{1/2O2}") == parse("{\\tfrac{1}{2}\\mathrm{O}_{2}}"), "fractional stoichiometric number")
        expect(parse("\\ce{NaCl(aq)}") == parse("{\\mathrm{Na}\\mathrm{Cl}\\mathrm{(}\\mathrm{aq}\\mathrm{)}}"), "aqueous state")
        expect(parse("\\ce{H2O(l)}") == parse("{\\mathrm{H}_{2}\\mathrm{O}\\mathrm{(}\\mathrm{l}\\mathrm{)}}") && parse("\\ce{Fe(s)}") == parse("{\\mathrm{Fe}\\mathrm{(}\\mathrm{s}\\mathrm{)}}"),
               "liquid and solid states")
        expect(parse("\\ce{Fe(CN)6^3-}") == parse("{\\mathrm{Fe}(\\mathrm{C}\\mathrm{N})_{6}^{3-}}"), "capital parentheses are groups, not states")
        expect(parse("\\ce{C6H5-CHO}") == parse("{\\mathrm{C}_{6}\\mathrm{H}_{5}{-}\\mathrm{C}\\mathrm{H}\\mathrm{O}}"), "single bond")
        expect(parse("\\ce{X=Y#Z}") == parse("{\\mathrm{X}{=}\\mathrm{Y}{\\equiv}\\mathrm{Z}}"), "double and triple bonds")
        expect(parse("\\ce{CuSO4*5H2O}") == parse("\\ce{CuSO4.5H2O}"), "star and dot both make addition compounds")
        expect(contains(parse("\\ce{CuSO4*5H2O}")) { $0 == .char("⋅", .bin) }, "addition dot")
        expect(parse("\\ce{[AgCl2]-}") == parse("{\\lbrack\\mathrm{Ag}\\mathrm{Cl}_{2}\\rbrack^{-}}"), "bracketed complex ion")
        expect(parse("\\ce{e-}") == parse("{\\mathrm{e}^{-}}"), "electron")
        expect(parse("\\ce{Fe^{II}}") == parse("{\\mathrm{Fe}^{\\mathrm{II}}}"), "oxidation state")
        expect(parse("\\ce{$x$ H2O}") == parse("{{x} \\mathrm{H}_{2}\\mathrm{O}}"), "math escapes")
        expect(parse("\\ce{n H2O}") == parse("{n\\, \\mathrm{H}_{2}\\mathrm{O}}"), "variable stoichiometry stays italic")
        let reaction = parse("\\ce{2H2 + O2 -> 2H2O}")
        expect(contains(reaction) { $0 == .char("+", .bin) }, "plus between species")
        let checks: [(String, String)] = [("->", "→"), ("<-", "←"), ("<->", "↔"), ("<-->", "⇄"), ("<=>", "⇌"), ("<=>>", "⥂"), ("<<=>", "⥄")]
        for (text, symbol) in checks {
            expect(arrow(parse("\\ce{A \(text) B}"))?.0 == symbol, "\(text) becomes \(symbol)")
        }
        expect(arrow(parse("\\ce{A->B}"))?.0 == "→", "arrows need no spaces")
        guard let labelled = arrow(parse("\\ce{A ->[H2O][\\Delta] B}")) else { failTest("labelled arrow parses") }
        expect(labelled.1 == parse("\\mathrm{H}_{2}\\mathrm{O}") && labelled.2 == [.group([.char("Δ", .ord)])],
               "arrow labels above and below, with chemistry in the label")
        expect(arrow(parse("\\ce{A ->[heat] B}"))?.2 == nil, "a single label goes above")
        expect(contains(parse("\\ce{BaSO4 v}")) { $0 == .classed(.rel, [.char("↓", .rel)]) }, "precipitate")
        expect(contains(parse("\\ce{H2 ^}")) { $0 == .classed(.rel, [.char("↑", .rel)]) }, "gas")
        expect(!contains(parse("\\ce{V2O5}")) { $0 == .char("↓", .rel) }, "a capital V is vanadium")
        let nested = parse("\\newcommand{\\water}{\\ce{H2O}}\\water")
        expect(nested == parse("\\ce{H2O}"), "chemistry inside a macro")
        let unclosed = failure("x + \\ce{A ->[heat B}")
        expect(unclosed.message == "Missing ] in this formula" && unclosed.offset == 4, "chemistry errors point at \\ce")
        expect(failure("\\ce").message == "\\ce needs {…} after it", "ce needs an argument")
    }

    static func mhchemManual() {
        expect(parse("\\ce{A\\bond{-}B\\bond{=}C\\bond{#}D}") == parse("\\ce{A-B=C#D}"), "bond commands match bond characters")
        expect(parse("\\ce{A\\bond{1}B\\bond{2}C\\bond{3}D}") == parse("\\ce{A-B=C#D}"), "numbered bonds")
        for bond in ["~", "~-", "~=", "~--", "-~-", "...", "....", "->", "<-"] {
            let nodes = parse("\\ce{A\\bond{\(bond)}B}")
            expect(nodes.count == 1 && !parse("\\ce{AB}").isEmpty && nodes != parse("\\ce{AB}"), "bond \(bond) draws something")
        }
        expect(contains(parse("\\ce{A\\bond{->}B}")) { $0 == .char("→", .rel) }, "arrow bond")
        expect(failure("\\ce{A\\bond{?}B}").message == "\\bond doesn't know \u{201C}?\u{201D}", "unknown bonds explain themselves")
        expect(parse("\\ce{OCO^{.-}}") == parse("{\\mathrm{O}\\mathrm{C}\\mathrm{O}^{\\cdot -}}"), "radical anion")
        expect(parse("\\ce{NO^{(2.)-}}") == parse("{\\mathrm{N}\\mathrm{O}^{(2\\cdot )-}}"), "radical with a count")
        expect(parse("\\ce{Mg^.}") == parse("{\\mathrm{Mg}^{\\cdot}}") && parse("\\ce{M^{..}_i}") == parse("{\\mathrm{M}^{\\cdot \\cdot }_{i}}"),
               "electron dots")
        expect(parse("\\ce{NO^*}") == parse("{\\mathrm{N}\\mathrm{O}^{*}}"), "excited state keeps its asterisk")
        expect(parse("\\ce{NO_x}") == parse("{\\mathrm{N}\\mathrm{O}_{x}}") && parse("\\ce{Fe^n+}") == parse("{\\mathrm{Fe}^{n+}}"),
               "variables are italic")
        expect(parse("\\ce{[Pt(\\eta^2-C2H4)Cl3]-}") == parse("{\\lbrack\\mathrm{Pt}(\\eta ^{2}{-}\\mathrm{C}_{2}\\mathrm{H}_{4})\\mathrm{Cl}_{3}\\rbrack^{-}}"),
               "hapticity then a bond")
        expect(parse("\\ce{\\beta +}") == parse("{\\beta ^{+}}"), "a space after a Greek letter is ignored")
        expect(parse("\\ce{CO3^2-_{(aq)}}") == parse("{\\mathrm{C}\\mathrm{O}_{3}^{2-}{}_{(\\mathrm{aq})}}"), "a second subscript gets its own base")
        expect(parse("\\ce{NaOH(aq,$\\infty$)}") == parse("{\\mathrm{Na}\\mathrm{O}\\mathrm{H}\\mathrm{(}\\mathrm{aq}{,}{\\infty}\\mathrm{)}}"),
               "math inside a state")
        expect(parse("\\ce{ZnS(\\ca$c$)}") == parse("{\\mathrm{Zn}\\mathrm{S}({\\sim}{c})}"), "circa")
        expect(parse("\\ce{{Gluconic Acid} + H2O2}") == parse("{\\text{Gluconic Acid} + \\mathrm{H}_{2}\\mathrm{O}_{2}}"), "braces make upright text")
        expect(parse("\\ce{$cis${-}[PtCl2(NH3)2]}") == parse("{{cis}\\text{-}\\lbrack\\mathrm{Pt}\\mathrm{Cl}_{2}(\\mathrm{N}\\mathrm{H}_{3})_{2}\\rbrack}"),
               "a braced hyphen isn't a bond")
        expect(parse("\\ce{A - B}") == parse("{\\mathrm{A} - \\mathrm{B}}"), "a spaced minus is an operator")
        expect(contains(parse("\\ce{A v B (v) -> B ^ B (^)}")) { $0 == .classed(.rel, [.char("(", .open), .char("↓", .rel), .char(")", .close)]) },
               "precipitate in parentheses")
        expect(parse("\\ce{H^3HO}") == parse("{\\mathrm{H}{}^{\\hphantom{3}}{}^{\\mathllap{3}}\\mathrm{H}\\mathrm{O}}"), "a bare mass number belongs to the next element")
        expect(parse("\\ce{1s^2-N}") == parse("{1\\mathrm{s}^{2}{-}\\mathrm{N}}"), "orbitals")
        expect(parse("\\ce{n-Pr}") == parse("{n{-}\\mathrm{Pr}}") && parse("\\ce{iPr}") == parse("{i\\mathrm{Pr}}"), "italic prefixes")
        expect(parse("\\ce{\\frac{[Hg^2+][Hg]}{[Hg2^2+]}}") ==
               parse("{\\frac{\\lbrack\\mathrm{Hg}^{2+}\\rbrack\\lbrack\\mathrm{Hg}\\rbrack}{\\lbrack\\mathrm{Hg}_{2}^{2+}\\rbrack}}"),
               "chemistry inside \\frac")
        expect(parse("\\ce{A~B}") == parse("{\\mathrm{A}\\ \\mathrm{B}}"), "a tilde is a space")
        expect(parse("\\pu{1,2e3 kJ}") == parse("{1{,}2\\cdot 10^{3}~\\mathrm{kJ}}"), "comma decimals stay commas")
        expect(parse("\\pu{1.2x10^3 kJ}") == parse("{1.2\\times 10^{3}~\\mathrm{kJ}}") && parse("\\pu{1.2*10^-3 m}") == parse("{1.2\\cdot 10^{-3}~\\mathrm{m}}"),
               "written-out powers of ten")
        expect(parse("\\pu{1.2e3 kJ mol-1}") == parse("{1.2\\cdot 10^{3}~\\mathrm{kJ}\\,\\mathrm{mol}^{-1}}"), "number, product and exponent")
        expect(parse("\\pu{123 J*s}") == parse("{123~\\mathrm{J}\\cdot \\mathrm{s}}") && parse("\\pu{123 J.s}") == parse("\\pu{123 J*s}"), "products")
        expect(parse("\\pu{75.3 J // mol K}") == parse("{75.3~\\frac{\\mathrm{J}}{\\mathrm{mol}\\,\\mathrm{K}}}"), "quotient with a spaced denominator")
        expect(parse("\\pu{10-20 K}") == parse("{10\\text{\u{2013}}20~\\mathrm{K}}"), "ranges get an en dash")
        expect(parse("\\pu{3 m^{-2}}") == parse("{3~\\mathrm{m}^{-2}}"), "braced exponents")
    }

    static func units() {
        expect(parse("\\pu{123 kJ/mol}") == parse("{123~\\mathrm{kJ}/\\mathrm{mol}}"), "number and unit")
        expect(parse("\\pu{1.2e3 kJ}") == parse("{1.2\\cdot 10^{3}~\\mathrm{kJ}}"), "lowercase e uses a dot")
        expect(parse("\\pu{1.2E-3 kJ}") == parse("{1.2\\times 10^{-3}~\\mathrm{kJ}}"), "capital E uses a cross")
        expect(parse("\\pu{kJ mol-1}") == parse("{\\mathrm{kJ}\\,\\mathrm{mol}^{-1}}"), "exponents without a caret")
        expect(parse("\\pu{m/s^2}") == parse("{\\mathrm{m}/\\mathrm{s}^{2}}"), "exponents with a caret")
        expect(parse("\\pu{kg*m2}") == parse("{\\mathrm{kg}\\cdot \\mathrm{m}^{2}}"), "multiplied units")
        expect(parse("\\pu{12345.67891 m}") == parse("{12\\,345.678\\,91~\\mathrm{m}}"), "digit groups")
        expect(parse("\\pu{1234 m}") == parse("{1234~\\mathrm{m}}"), "four digits stay together")
        expect(parse("\\pu{J//mol}") == parse("{\\frac{\\mathrm{J}}{\\mathrm{mol}}}"), "double slash makes a fraction")
        expect(parse("\\pu{25 °C}") == parse("{25~{}^{\\circ}\\mathrm{C}}"), "degrees Celsius")
        expect(parse("\\pu{1.2+-0.1 mm}") == parse("{1.2\\pm 0.1~\\mathrm{mm}}"), "uncertainty")
        expect(parse("\\pu{-40 K}") == parse("{-40~\\mathrm{K}}"), "negative numbers")
        expect(parse("\\pu{5 µm}") == parse("{5~\\mu \\mathrm{m}}"), "micro sign")
    }

    static func equation(_ source: String, display: Bool = true, line: UInt = #line) -> NoteMathEquation {
        do {
            return try NoteMathParser.parseEquation(source, display: display)
        } catch {
            failTest("\(source) failed to parse: \(error.message) at \(error.offset)", line: line)
        }
    }

    static func rowTags(_ source: String, line: UInt = #line) -> [[NoteMathNode]?] {
        guard case .environment(let environment)? = equation(source, line: line).nodes.first else {
            failTest("\(source) parses as an environment", line: line)
        }
        return environment.tags
    }

    static func tags() {
        let plain = equation("E = mc^2 \\tag{1}")
        expect(plain.tag == [.text("(1)", .roman)] && plain.nodes == parse("E = mc^2"), "tag wraps its label in parentheses")
        expect(equation("x \\tag*{A.1}").tag == [.text("A.1", .roman)], "tag* keeps the label as written")
        expect(equation("x \\tag{$\\ast$}").tag == [.text("(", .roman), .mathStyle(.text, [.char("∗", .bin)]), .text(")", .roman)],
               "math inside a tag")
        expect(equation("\\tag{eq} x").tag == [.text("(eq)", .roman)], "a tag can come first")
        expect(equation("x \\notag").tag == nil && equation("x \\nonumber").nodes == parse("x"), "notag on its own is harmless")
        expect(parse("x \\tag{1}") == parse("x"), "parse drops the tag from the formula")
        let inline = failure("x \\tag{1}", display: false)
        expect(inline.message == "\\tag only works in display equations" && inline.offset == 2 && inline.length == 4, "inline tags explain themselves")
        expect(failure("x \\tag{1} \\tag{2}").message == "Only one \\tag per line", "one tag per line")
        expect(failure("x^\\tag{1}").message == "\\tag has to stand on its own, not inside a script or argument", "tag inside a script")
        expect(failure("x \\tag").message == "\\tag needs {text} after it", "tag needs a label")
        expect(equation("x \\tag 1").tag == [.text("(1)", .roman)], "a one-character tag needs no braces")
        let one: [NoteMathNode] = [.text("(1)", .roman)], two: [NoteMathNode] = [.text("(2)", .roman)]
        expect(rowTags("\\begin{align} a &= b \\\\ c &= d \\end{align}") == [one, two], "align numbers every row")
        expect(rowTags("\\begin{align} a &= b \\\\ c &= d \\\\ \\end{align}") == [one, two], "a trailing break doesn't number an empty row")
        expect(rowTags("\\begin{align} a &= b \\notag \\\\ c &= d \\end{align}") == [nil, one], "notag skips a row")
        expect(rowTags("\\begin{align} a &= b \\nonumber \\\\ c &= d \\nonumber \\end{align}") == [], "nonumber everywhere leaves no tags")
        expect(rowTags("\\begin{align} a &= b \\tag{x} \\\\ c &= d \\end{align}") == [[.text("(x)", .roman)], one],
               "an explicit tag doesn't use up a number")
        expect(rowTags("\\begin{align*} a &= b \\\\ c &= d \\tag{y} \\end{align*}") == [nil, [.text("(y)", .roman)]],
               "align* only shows explicit tags, here on its last line")
        expect(rowTags("\\begin{align*} a \\\\ b \\end{align*}") == [], "align* has no numbers")
        expect(rowTags("\\begin{gather} a \\\\ b \\end{gather}") == [one, two], "gather numbers rows")
        expect(rowTags("\\begin{equation} E = mc^2 \\end{equation}") == [one], "equation is numbered")
        expect(rowTags("\\begin{equation*} E = mc^2 \\tag{$\\star$} \\end{equation*}").count == 1, "equation* takes a tag")
        let aligned = equation("\\begin{aligned} a &= b \\tag{1} \\\\ c &= d \\end{aligned}")
        expect(aligned.tag == one, "a tag inside aligned tags the whole equation")
        if case .environment(let environment)? = aligned.nodes.first { expect(environment.tags.isEmpty, "aligned rows carry no tags") }
        let after = equation("\\begin{aligned} a &= b \\\\ c &= d \\end{aligned} \\tag{2}")
        expect(after.tag == two, "a tag after aligned tags the whole equation")
        if case .environment(let environment)? = (try? NoteMathParser.parseEquation("\\begin{align} a \\\\ b \\end{align}", display: false))?.nodes.first {
            expect(environment.tags.isEmpty, "inline align stays unnumbered")
        } else {
            failTest("inline align parses")
        }
        expect(failure("\\begin{align} a \\tag{1} \\tag{2} \\end{align}").message == "Only one \\tag per line", "one tag per align row")
        expect(equation("\\newcommand{\\eq}[1]{\\tag{#1}} x \\eq{7}").tag == [.text("(7)", .roman)], "tags from macros")
    }

    static func labels() {
        let numbered = equation("\\begin{align} a &= b \\label{first} \\\\ c &= d \\tag{x}\\label{second} \\\\ e \\label{third} \\end{align}")
        expect(numbered.labels == [NoteMathLabel(key: "first", target: .automatic(1)), NoteMathLabel(key: "second", target: .tag([.text("x", .roman)])),
                                   NoteMathLabel(key: "third", target: .automatic(2))] && numbered.automaticNumbers == 2,
               "labels attach to row numbers and tags: \(numbered.labels)")
        let later = NoteMathNumberingContext(firstNumber: 4)
        let shifted = try? NoteMathParser.parseEquation("\\begin{gather} a \\\\ b \\end{gather}", display: true, numbering: later)
        if case .environment(let environment)? = shifted?.nodes.first {
            expect(environment.tags == [[.text("(5)", .roman)], [.text("(6)", .roman)]], "numbers continue from earlier equations")
        } else {
            failTest("numbered gather parses")
        }
        let context = NoteMathNumberingContext(references: ["e": [.text("3", .roman)]])
        let refs = try? NoteMathParser.parseEquation("\\eqref{e} + \\ref{e} + \\eqref{nope}", display: false, numbering: context)
        expect(refs?.nodes == [.reference("e", parenthesized: true, label: [.text("3", .roman)]), .char("+", .bin),
                               .reference("e", parenthesized: false, label: [.text("3", .roman)]), .char("+", .bin),
                               .reference("nope", parenthesized: true, label: nil)], "references resolve or stay missing")
        expect(parse("\\text{see \\eqref{a}}") == [.group([.text("see ", .roman), .reference("a", parenthesized: true, label: nil)])],
               "references work inside text")
        expect(equation("x \\tag{A} \\label{k}").labels == [NoteMathLabel(key: "k", target: .tag([.text("A", .roman)]))], "a tagged display takes a label")
        expect(failure("x \\label{k}").message.hasPrefix("\\label needs a numbered equation"), "an unnumbered display can't take a label")
        expect(failure("x \\label{k}", display: false).message == "\\label only works in display equations", "inline labels explain themselves")
        expect(failure("\\begin{align} a \\label{k} \\\\ b \\label{k} \\end{align}").message == "\u{201C}k\u{201D} already labels another line here",
               "duplicate labels in one equation")
        expect(failure("\\begin{align*} a \\label{k} \\end{align*}").message == "\\label needs a numbered line, and this one isn't numbered",
               "labels need numbered rows")
        let taken = NoteMathNumberingContext(takenLabels: ["k"])
        do {
            _ = try NoteMathParser.parseEquation("\\begin{equation} a \\label{k} \\end{equation}", display: true, numbering: taken)
            failTest("a label taken by an earlier equation fails")
        } catch {
            expect(error.message == "\u{201C}k\u{201D} already labels an earlier equation", "labels are unique across the note")
        }
        expect(failure("\\begin{align} a \\label{x} \\label{y} \\end{align}").message == "Only one \\label per line", "one label per line")
        expect(failure("\\eqref{}").message == "\\eqref needs a label, like \\eqref{eq:energy}", "references need a key")
    }

    static func failure(_ source: String, display: Bool, line: UInt = #line) -> NoteMathParseError {
        do {
            let parsed = try NoteMathParser.parseEquation(source, display: display)
            failTest("\(source) should fail but parsed as \(parsed)", line: line)
        } catch {
            return error
        }
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
        expect(failure("\\begin{array}{cx} a \\end{array}").message == "Array columns only take l, c, r, | and :", "bad array spec")
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
