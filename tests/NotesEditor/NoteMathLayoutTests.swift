import AppKit
import CoreText

@main @MainActor
struct NoteMathLayoutTests {
    static var font: NoteMathFont!
    static let size: CGFloat = 20

    static func expect(_ value: Bool, _ message: String, line: UInt = #line) {
        if !value { failTest(message, line: line) }
    }

    static func box(_ latex: String, display: Bool = true, line: UInt = #line) -> NoteMathBox {
        do {
            return NoteMathTypesetter(font: font, baseSize: size).typeset(try NoteMathParser.parse(latex), display: display)
        } catch {
            failTest("\(latex) failed to parse: \(error.message)", line: line)
        }
    }

    static func glyph(_ symbol: String) -> CGGlyph {
        font.glyph(for: symbol.unicodeScalars.first!)
    }

    static func scriptGlyph(_ symbol: String, _ level: Int) -> CGGlyph {
        font.scriptGlyph(glyph(symbol), level: level)
    }

    static func inks(_ box: NoteMathBox, glyph target: CGGlyph) -> [NoteMathInk] {
        box.inks.filter { ink in
            if case .glyph(let glyph, _) = ink.content { return glyph == target }
            return false
        }
    }

    static func extent(_ inks: [NoteMathInk]) -> CGRect {
        inks.reduce(CGRect.null) { result, ink in
            guard case .glyph(let glyph, let ctFont) = ink.content else { return result }
            let scale = CTFontGetSize(ctFont) / font.unitsPerEm
            let bounds = font.metrics(glyph).bounds
            return result.union(CGRect(x: ink.origin.x + bounds.minX * scale, y: ink.origin.y + bounds.minY * scale,
                                       width: bounds.width * scale, height: bounds.height * scale))
        }
    }

    static func ruleCount(_ box: NoteMathBox) -> Int {
        box.inks.filter { ink in
            if case .rule = ink.content { return true }
            return false
        }.count
    }

    static func katexEnvironments() {
        let alignat = box("\\begin{alignat*}{2} a &= b & c &= d \\end{alignat*}")
        let aligned = box("\\begin{aligned} a &= b & c &= d \\end{aligned}")
        expect(abs(aligned.width - alignat.width - size) < 0.5, "alignat drops aligned's quad between pairs")
        let multline = box("\\begin{multline*} a+b+c+d+e \\\\ x \\\\ y \\end{multline*}")
        let rows = multline.inks.sorted { $0.origin.y > $1.origin.y }
        guard let first = rows.first, let last = rows.last else { failTest("multline draws") }
        expect(first.origin.x < 0.2 * size, "multline's first line hugs the left")
        expect(last.origin.x > multline.width - size, "multline's last line hugs the right")
        let middle = rows.filter { abs($0.origin.y - (first.origin.y + last.origin.y) / 2) < 0.3 * size }
        expect(middle.count == 1 && abs(middle[0].origin.x - multline.width / 2) < 0.6 * size, "multline centres the middle line")
        let subarray = box("\\begin{subarray}{c} a \\\\ b \\end{subarray}")
        let matrix = box("\\begin{matrix} a \\\\ b \\end{matrix}")
        expect(subarray.height < matrix.height * 0.75 && subarray.width < matrix.width, "subarray is script-sized and tight")
        let leftSubarray = box("\\begin{subarray}{l} abc \\\\ d \\end{subarray}")
        let leftRows = leftSubarray.inks.sorted { $0.origin.y > $1.origin.y }
        expect(abs((leftRows.first?.origin.x ?? 1) - (leftRows.last?.origin.x ?? 0)) < 0.1 * size, "subarray {l} aligns left")
        expect(box("\\begin{dcases} \\frac{1}{2} & x \\end{dcases}").height > box("\\begin{cases} \\frac{1}{2} & x \\end{cases}").height,
               "dcases sets its cells in display style")
        expect(box("\\begin{darray}{c} \\sum_{i=1}^n i \\end{darray}").height > box("\\begin{array}{c} \\sum_{i=1}^n i \\end{array}").height,
               "darray sets its cells in display style")
        let right = box("\\begin{matrix*}[r] 1 \\\\ -10 \\end{matrix*}").inks.max { $0.origin.y < $1.origin.y }
        let left = box("\\begin{matrix*}[l] 1 \\\\ -10 \\end{matrix*}").inks.max { $0.origin.y < $1.origin.y }
        expect((right?.origin.x ?? 0) > (left?.origin.x ?? 0) + 0.5 * size, "matrix*[r] pushes short entries right")
        expect(ruleCount(box("\\begin{array}{c:c} a & b \\\\ c & d \\end{array}")) > 2, "a dashed column draws as dashes")
        expect(ruleCount(box("\\begin{array}{c|c} a & b \\\\ c & d \\end{array}")) == 1, "a solid column is one rule")
        expect(ruleCount(box("\\begin{array}{cc} a & b \\\\ \\hdashline c & d \\end{array}")) > 2, "hdashline draws as dashes")
    }

    static func commutativeDiagrams() {
        let plain = box("\\begin{CD} A @>>> B \\end{CD}")
        let objects = box("A").width + box("B").width
        expect(plain.width >= objects + 3 * size + size - 0.5, "CD arrows reach at least 3em with half-em gaps: \(plain.width)")
        let labelled = box("\\begin{CD} A @>{\\text{a long label}}>> B \\end{CD}")
        expect(labelled.width > plain.width + size && labelled.ascent > plain.ascent, "labels above stretch the arrow")
        let below = box("\\begin{CD} A @>>{g}> B \\end{CD}")
        expect(below.descent > plain.descent, "labels below hang under the arrow")
        expect(ruleCount(box("\\begin{CD} A @= B \\end{CD}")) == 2, "@= draws a long equals")
        let column = box("\\begin{CD} A \\\\ @VVV \\\\ B \\end{CD}")
        expect(column.height > box("\\begin{matrix} A \\\\ B \\end{matrix}").height + 0.8 * size, "a vertical arrow row sits between objects")
        let sides = box("\\begin{CD} A \\\\ @VfVgV \\\\ B \\end{CD}")
        expect(sides.width > column.width + 0.3 * size, "side labels widen the diagram instead of spilling out")
        let sideInk = extent(sides.inks)
        expect(sideInk.minX >= -0.01 && sideInk.maxX <= sides.width + 0.01, "side labels stay inside the diagram: \(sideInk) in \(sides.width)")
        let grid = box("\\begin{CD} A @>>> B \\\\ @VVV @AAA \\\\ C @<<< D \\end{CD}")
        expect(grid.width >= 2 * box("A").width + 3 * size && grid.height > 2.5 * size, "a square diagram lays out")
    }

    static func main() {
        let repository = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : FileManager.default.currentDirectoryPath)
        let url = repository.appendingPathComponent("Resources/NoteFonts/STIXTwoMath-Regular.otf")
        expect(FileManager.default.fileExists(atPath: url.path), "bundled STIX Two Math font exists")
        NoteMathRenderer.useFont(at: url)
        guard let loaded = NoteMathRenderer.font else { failTest("math font loads") }
        font = loaded
        mathTable()
        alphabets()
        spacing()
        scripts()
        fractions()
        radicals()
        operators()
        delimiters()
        accents()
        environments()
        katexEnvironments()
        commutativeDiagrams()
        scriptSizes()
        macrosAndChemistry()
        tags()
        renderer()
        bitmaps()
        fallbackGlyphs()
        references()
        katexBoxesSizesAndLinks()
        samples()
        print("NoteMathLayoutTests passed")
    }

    static func mathTable() {
        expect(font.hasMathTable, "STIX Two Math has a MATH table")
        expect(font.unitsPerEm == 1000, "units per em")
        expect(font.constants[.axisHeight] > 200 && font.constants[.axisHeight] < 300, "axis height is about a quarter em")
        expect(font.constants.scriptPercentScaleDown == 70 && font.constants.scriptScriptPercentScaleDown == 55, "script scale")
        expect(font.constants[.fractionRuleThickness] > 0 && font.constants[.radicalKernAfterDegree] < 0, "constants decode with signs")
        expect(font.minConnectorOverlap > 0, "connector overlap")
        let paren = font.verticalConstruction(glyph("("))
        expect((paren?.variants.count ?? 0) > 5 && paren?.parts.contains(where: \.isExtender) == true, "parentheses have variants and an assembly")
        expect(font.horizontalConstruction(glyph("\u{23DE}"))?.parts.isEmpty == false, "overbrace assembles horizontally")
        expect(font.italicCorrection(glyph("𝑓")) > 0, "italic f has an italic correction")
        expect(font.topAccentAttachment(glyph("𝑥")) != nil, "italic x has an accent attachment")
        expect(font.kernSet(glyph("𝑉")) != nil, "italic V has math kerning")
    }

    static func alphabets() {
        let checks: [(String, NoteMathVariant, UInt32)] = [
            ("x", .normal, 0x1D465), ("h", .normal, 0x210E), ("α", .normal, 0x1D6FC), ("Γ", .normal, 0x393), ("2", .normal, 0x32),
            ("R", .doubleStruck, 0x211D), ("Z", .doubleStruck, 0x2124), ("L", .script, 0x2112), ("g", .fraktur, 0x1D524),
            ("v", .bold, 0x1D42F), ("Γ", .italic, 0x1D6E4), ("μ", .boldItalic, 0x1D741), ("x", .roman, 0x78), ("1", .monospace, 0x1D7F7),
            ("a", .sansSerif, 0x1D5BA), ("ϕ", .normal, 0x1D719), ("∂", .normal, 0x1D715),
        ]
        for (symbol, variant, expected) in checks {
            let mapped = NoteMathAlphabet.map(symbol, variant: variant)
            expect(mapped.unicodeScalars.first?.value == expected, "\(symbol) in \(variant) maps to U+\(String(expected, radix: 16))")
            expect(font.glyph(for: mapped.unicodeScalars.first!) != 0, "the font covers \(mapped)")
        }
        expect(NoteMathAlphabet.mapText("ab1é", style: .bold) == "𝐚𝐛𝟏é", "bold text maps ASCII and keeps accents")
    }

    static func spacing() {
        let a = box("a").width, b = box("b").width
        let plus = font.metrics(glyph("+")).advance * size / 1000
        let equals = font.metrics(glyph("=")).advance * size / 1000
        let binary = box("a+b").width - (a + b + plus)
        let relation = box("a=b").width - (a + b + equals)
        expect(abs(binary - 2 * 4 * size / 18) < 0.01, "binary operators get medium spaces")
        expect(abs(relation - 2 * 5 * size / 18) < 0.01, "relations get thick spaces")
        expect(abs(box("-b").width - (font.metrics(glyph("\u{2212}")).advance * size / 1000 + b)) < 0.01, "a leading minus is unary")
        expect(box("a,b").width > a + b + font.metrics(glyph(",")).advance * size / 1000 + 0.1, "punctuation gets a thin space")
        let scriptSum = box("x^{a+b}").width - box("x^{ab}").width
        expect(abs(scriptSum - font.metrics(scriptGlyph("+", 1)).advance * size * 0.7 / 1000) < 0.01, "no medium space inside scripts")
        expect(abs(box("a\\quad b").width - (a + b + size)) < 0.01, "quad is one em")
        expect(box("\\sin x").width > box("sinx").width - 3, "function names are upright and spaced")
    }

    static func scripts() {
        let base = box("x")
        let raised = box("x^2")
        let two = inks(raised, glyph: scriptGlyph("2", 1))
        expect(two.count == 1 && two[0].origin.y > size * 0.25, "superscripts are raised")
        expect(raised.ascent > base.ascent && raised.width > base.width, "superscript grows the box")
        if case .glyph(_, let scriptFont) = two[0].content { expect(abs(CTFontGetSize(scriptFont) - size * 0.7) < 0.01, "script size is 70%") }
        let lowered = box("x_2")
        let sub = inks(lowered, glyph: scriptGlyph("2", 1))
        expect(sub.count == 1 && sub[0].origin.y < 0 && lowered.descent > base.descent, "subscripts are lowered")
        let both = box("x_2^2")
        let pair = inks(both, glyph: scriptGlyph("2", 1)).sorted { $0.origin.y > $1.origin.y }
        expect(pair.count == 2 && pair[0].origin.y > 0 && pair[1].origin.y < 0, "superscript above subscript")
        let gap = extent([pair[0]]).minY - extent([pair[1]]).maxY
        expect(gap >= font.constants[.subSuperscriptGapMin] * size / 1000 - 0.01, "sub and superscript keep their gap")
        expect(pair[0].origin.x > pair[1].origin.x, "superscript is nudged by the italic correction")
        let prime = box("f'")
        expect(inks(prime, glyph: scriptGlyph("′", 1)).first.map { $0.origin.y > 0 } == true, "primes ride high")
        let nested = box("e^{x^2}")
        let nestedTwo = inks(nested, glyph: scriptGlyph("2", 2))
        if case .glyph(_, let tiny)? = nestedTwo.first?.content {
            expect(abs(CTFontGetSize(tiny) - size * 0.55) < 0.01, "second-level scripts are 55%")
        } else {
            failTest("nested script exists")
        }
        let groupBase = box("(x+y)^2")
        expect(groupBase.ascent > box("(x+y)").ascent, "superscript on a closing paren")
    }

    static func fractions() {
        let fraction = box("\\frac{a}{b}")
        let numerator = box("a")
        expect(fraction.height > numerator.height * 2, "a fraction is taller than its numerator")
        let a = inks(fraction, glyph: glyph("𝑎")), b = inks(fraction, glyph: glyph("𝑏"))
        expect(a.count == 1 && b.count == 1 && a[0].origin.y > 0 && b[0].origin.y < 0, "numerator above, denominator below")
        let rules = fraction.inks.filter { if case .rule = $0.content { return true }; return false }
        expect(rules.count == 1, "fraction has a rule")
        if let rule = rules.first, case .rule(let ruleSize) = rule.content {
            let axis = font.constants[.axisHeight] * size / 1000
            expect(abs(rule.origin.y + ruleSize.height / 2 - axis) < 0.01, "rule sits on the math axis")
            expect(ruleSize.width >= numerator.width, "rule covers the numerator")
        }
        expect(box("\\frac{a}{b}", display: true).height > box("\\frac{a}{b}", display: false).height, "display fractions are bigger")
        expect(box("\\tfrac{a}{b}").height < box("\\dfrac{a}{b}").height, "tfrac is smaller than dfrac")
        let binom = box("\\binom{n}{k}")
        expect(binom.inks.allSatisfy { if case .rule = $0.content { return false }; return true }, "binomials have no rule")
        expect(binom.width > box("\\frac{n}{k}").width, "binomials have parentheses")
        let nested = box("\\frac{\\frac{1}{2}}{3}")
        expect(nested.height > fraction.height, "nested fractions stack")
    }

    static func radicals() {
        let root = box("\\sqrt{x}")
        let x = box("x")
        expect(root.width > x.width && root.ascent > x.ascent, "a radical wraps its radicand")
        let rule = root.inks.first { if case .rule = $0.content { return true }; return false }
        expect(rule != nil, "radical has an overbar")
        let tall = box("\\sqrt{\\frac{a}{b}}")
        let surdGlyphs = tall.inks.compactMap { ink -> CGGlyph? in
            if case .glyph(let glyph, _) = ink.content, ink.origin.x < 1 { return glyph }
            return nil
        }
        expect(!surdGlyphs.contains(glyph("√")), "a tall radicand picks a bigger radical")
        let cube = box("\\sqrt[3]{x}")
        expect(cube.width > root.width, "the degree takes room")
        let huge = box("\\sqrt{\\begin{matrix}1\\\\2\\\\3\\\\4\\\\5\\\\6\\end{matrix}}")
        expect(huge.height > size * 6, "radicals stretch to tall content")
    }

    static func operators() {
        let display = box("\\sum_{i=1}^{n} i")
        let text = box("\\sum_{i=1}^{n} i", display: false)
        let sumDisplay = extent(display.inks.filter { if case .glyph(let g, _) = $0.content { return font.verticalConstruction(glyph("∑"))?.variants.contains { $0.glyph == g } == true }; return false })
        let sumText = extent(inks(text, glyph: glyph("∑")))
        expect(sumDisplay.height > sumText.height, "display sums are bigger")
        let n = inks(display, glyph: scriptGlyph("𝑛", 1))
        expect(n.count == 1 && extent(n).minY > sumDisplay.maxY, "display limits sit above")
        let i = inks(display, glyph: scriptGlyph("𝑖", 1)).sorted { $0.origin.y < $1.origin.y }
        expect(extent([i[0]]).maxY < sumDisplay.minY, "lower limit sits below")
        let textN = inks(text, glyph: scriptGlyph("𝑛", 1))
        expect(textN.count == 1 && textN[0].origin.x > sumText.maxX - 1, "text-style limits go beside")
        let integral = box("\\int_0^1 f")
        let one = inks(integral, glyph: scriptGlyph("1", 1))
        let zero = inks(integral, glyph: scriptGlyph("0", 1))
        expect(one.count == 1 && zero.count == 1 && one[0].origin.x > zero[0].origin.x, "integral limits go beside, nudged by its slant")
        let limited = box("\\int\\limits_0^1 f")
        let stackedOne = inks(limited, glyph: scriptGlyph("1", 1))
        expect(stackedOne.count == 1 && stackedOne[0].origin.y > one[0].origin.y, "\\limits stacks integral limits")
        let lim = box("\\lim_{x\\to 0} f")
        expect(lim.descent > box("\\lim f").descent + size * 0.3, "lim puts its limit underneath in display")
        let axis = font.constants[.axisHeight] * size / 1000
        let centre = (sumText.minY + sumText.maxY) / 2
        expect(abs(centre - axis) < 0.5, "big operators centre on the axis")
    }

    static func delimiterExtent(_ latex: String) -> CGRect {
        let laidOut = box(latex)
        let left = laidOut.inks.filter { $0.origin.x < 0.5 }
        return extent(left)
    }

    static func delimiters() {
        let small = delimiterExtent("\\left( x \\right)")
        let medium = delimiterExtent("\\left( \\frac{a}{b} \\right)")
        let large = delimiterExtent("\\left( \\frac{\\frac{a}{b}}{\\frac{c}{d}} \\right)")
        expect(small.height < medium.height && medium.height < large.height, "big delimiters grow")
        let content = box("\\begin{matrix}1\\\\2\\\\3\\\\4\\\\5\\\\6\\\\7\\\\8\\end{matrix}")
        let assembled = box("\\left( \\begin{matrix}1\\\\2\\\\3\\\\4\\\\5\\\\6\\\\7\\\\8\\end{matrix} \\right)")
        let leftInks = assembled.inks.filter { $0.origin.x < 0.5 }
        expect(leftInks.count > 2, "very tall delimiters are assembled from parts")
        expect(extent(leftInks).height >= content.height * 0.9, "the assembly covers the content")
        let fenced = box("\\left\\{ x \\middle| x > 0 \\right\\}")
        expect(inks(fenced, glyph: glyph("|")).count == 1, "middle delimiter is drawn")
        let null = box("\\left. x \\right|")
        expect(null.width > box("x").width, "null delimiter keeps a sliver of space")
        let sizes = ["\\big(", "\\Big(", "\\bigg(", "\\Bigg("].map { extent(box($0).inks).height }
        expect(sizes == sizes.sorted() && Set(sizes).count == 4, "big, Big, bigg and Bigg grow")
        let angle = delimiterExtent("\\left\\langle \\begin{matrix}1\\\\2\\\\3\\\\4\\\\5\\\\6\\\\7\\\\8\\\\9\\\\10\\end{matrix} \\right\\rangle")
        expect(angle.height > size * 3, "delimiters without assemblies use their largest variant")
    }

    static func accents() {
        let x = box("x")
        let hat = box("\\hat{x}")
        expect(hat.ascent > x.ascent && abs(hat.width - x.width + font.italicCorrection(glyph("𝑥")) * size / 1000) < 0.5, "hat sits above without widening")
        let accentInk = inks(hat, glyph: glyph("\u{0302}"))
        expect(accentInk.count == 1, "hat uses the combining circumflex")
        let tall = box("\\hat{A}")
        let tallAccent = inks(tall, glyph: font.flattenedAccent(glyph("\u{0302}")) ?? glyph("\u{0302}"))
        expect(tallAccent.first.map { $0.origin.y > 0 } == true, "accents rise over tall bases")
        let wide = box("\\widehat{xyz}")
        expect(inks(wide, glyph: glyph("\u{0302}")).isEmpty, "widehat picks a wider variant")
        let arrow = box("\\overrightarrow{ABCD}")
        let letters = Set(["𝐴", "𝐵", "𝐶", "𝐷"].map(glyph))
        let arrowInks = arrow.inks.filter { ink in
            if case .glyph(let value, _) = ink.content { return !letters.contains(value) }
            return false
        }
        expect(extent(arrowInks).width >= box("ABCD").width * 0.95, "over arrows stretch across their base")
        let brace = box("\\overbrace{a+b+c}^{n}")
        expect(brace.ascent > box("a+b+c").ascent + size * 0.4, "overbrace and its label stack up")
        let under = box("\\underbrace{a+b+c}_{n}")
        expect(under.descent > box("a+b+c").descent + size * 0.4, "underbrace and its label hang down")
        let label = box("\\xrightarrow{\\text{long label}}")
        let labelWidth = box("\\scriptstyle\\text{long label}").width
        let labelArrow = extent(label.inks.filter { if case .glyph = $0.content { return true }; return false })
        expect(labelArrow.width > labelWidth && label.width > labelWidth, "labelled arrows stretch past their label")
        expect(label.ascent > size * 0.6, "the label sits above the arrow")
        let both = box("\\xleftarrow[below]{above}")
        expect(both.descent > size * 0.3 && both.ascent > size * 0.6, "labels above and below")
        expect(box("\\xLeftrightarrow{}").width >= size * 1.4 - 0.01, "empty labelled arrows still read as long arrows")
        let cancel = box("\\cancel{x+y}")
        let segments = cancel.inks.filter { if case .segment = $0.content { return true }; return false }
        expect(segments.count == 1 && abs(cancel.width - box("x+y").width) < 0.01, "cancel strikes without changing width")
        expect(box("\\xcancel{x}").inks.filter { if case .segment = $0.content { return true }; return false }.count == 2, "xcancel crosses")
        let overline = box("\\overline{xy}")
        expect(overline.ascent > box("xy").ascent && overline.inks.contains { if case .rule = $0.content { return true }; return false }, "overline")
        let underline = box("\\underline{xy}")
        expect(underline.descent > box("xy").descent, "underline")
    }

    static func environments() {
        let aligned = box("\\begin{aligned} a &= b + c \\\\ x + y + z &= d \\end{aligned}")
        let equals = inks(aligned, glyph: glyph("="))
        expect(equals.count == 2 && abs(equals[0].origin.x - equals[1].origin.x) < 0.01, "aligned lines up the equals signs")
        expect(equals[0].origin.y > equals[1].origin.y, "rows go downwards")
        let matrix = box("\\begin{matrix} 1 \\\\ 333 \\end{matrix}")
        let one = extent(inks(matrix, glyph: glyph("1")))
        let threes = extent(inks(matrix, glyph: glyph("3")))
        expect(abs(one.midX - threes.midX) < 0.6, "matrix columns centre their cells")
        let columns = box("\\begin{pmatrix} 1 & 2 \\\\ 3 & 4 \\end{pmatrix}")
        let x1 = inks(columns, glyph: glyph("1"))[0].origin.x, x3 = inks(columns, glyph: glyph("3"))[0].origin.x
        let x2 = inks(columns, glyph: glyph("2"))[0].origin.x, x4 = inks(columns, glyph: glyph("4"))[0].origin.x
        expect(abs(x1 - x3) < 0.01 && abs(x2 - x4) < 0.01 && x2 > x1 + size * 0.9, "matrix columns align with a gap")
        let axis = font.constants[.axisHeight] * size / 1000
        expect(abs((columns.ascent - columns.descent) / 2 - axis) < 0.5, "matrices centre on the axis")
        let cases = box("f = \\begin{cases} 1 & x > 0 \\\\ 0 & \\text{else} \\end{cases}")
        expect(cases.height > size * 1.8, "cases stack their rows")
        let array = box("\\begin{array}{c|c} a & b \\\\ \\hline c & d \\end{array}")
        let arrayRules = array.inks.filter { if case .rule = $0.content { return true }; return false }
        expect(arrayRules.count == 2, "array draws its vertical and horizontal rules")
        let lines = box("a = b \\\\ c = d")
        expect(lines.height > size * 1.5, "top-level line breaks stack lines")
        let centred = inks(box("x \\\\ xxx"), glyph: glyph("𝑥"))
        let top = extent(centred.filter { $0.origin.y > 0 }), bottom = extent(centred.filter { $0.origin.y < 0 })
        expect(abs(top.midX - bottom.midX) < 0.6 && top.width < bottom.width, "lines are centred")
    }

    static func scriptSizes() {
        expect(font.hasScriptAlternates, "STIX Two Math carries ssty alternates")
        for symbol in ["𝑥", "2", "+", "(", "∑", "′"] {
            let one = scriptGlyph(symbol, 1), two = scriptGlyph(symbol, 2)
            expect(one != glyph(symbol) && two != one && two != glyph(symbol), "\(symbol) has distinct ssty levels")
        }
        let level1 = box("x^{y}")
        expect(inks(level1, glyph: scriptGlyph("𝑦", 1)).count == 1 && inks(level1, glyph: glyph("𝑦")).isEmpty, "superscripts use ssty level 1")
        let level2 = box("x^{y^{z}}")
        expect(inks(level2, glyph: scriptGlyph("𝑧", 2)).count == 1, "second-level scripts use ssty level 2")
        if case .glyph(_, let tiny)? = inks(level2, glyph: scriptGlyph("𝑧", 2)).first?.content {
            expect(abs(CTFontGetSize(tiny) - size * 0.55) < 0.01, "ssty glyphs still use the MATH script scale")
        }
        let styled = box("\\scriptstyle a \\scriptscriptstyle b")
        expect(inks(styled, glyph: scriptGlyph("𝑎", 1)).count == 1 && inks(styled, glyph: scriptGlyph("𝑏", 2)).count == 1,
               "style switches pick the matching ssty level")
        expect(inks(box("e^{\\sin x}"), glyph: scriptGlyph("s", 1)).count == 1, "function names in scripts use ssty")
        expect(inks(box("\\frac{a}{b}", display: false), glyph: scriptGlyph("𝑎", 1)).count == 1, "text-style fractions use script glyphs")
        expect(inks(box("x_{\\left( a \\right)}"), glyph: scriptGlyph("(", 1)).count == 1, "small delimiters in scripts use ssty")
        expect(font.metrics(scriptGlyph("2", 1)).advance > font.metrics(glyph("2")).advance, "script-size 2 is wider than the text 2")
        guard let flat = font.flattenedAccent(glyph("\u{0302}")) else { failTest("STIX Two Math has a flattened circumflex") }
        expect(inks(box("\\hat{A}"), glyph: flat).count == 1, "tall bases get the flattened accent")
        expect(inks(box("\\hat{x}"), glyph: flat).isEmpty && inks(box("\\hat{x}"), glyph: glyph("\u{0302}")).count == 1,
               "short bases keep the full accent")
        let typesetter = NoteMathTypesetter(font: font, baseSize: 40)
        func rendered(_ glyph: CGGlyph) -> Bitmap {
            let entry = NoteMathLayoutEntry(box: typesetter.glyphBox(glyph, size: 28, color: .inherited), error: nil, isEmpty: false)
            return bitmap(NoteMathRendering(source: "2", fontSize: 28, color: .black, display: true, entry: entry), scale: 4)
        }
        let plain = rendered(glyph("2")).ink(x: 0...1, y: 0...1)
        let optical = rendered(scriptGlyph("2", 1)).ink(x: 0...1, y: 0...1)
        expect(Double(optical) > Double(plain) * 1.05, "script-size glyphs draw heavier strokes than shrunken text glyphs (\(optical) vs \(plain))")
        let power = bitmap(NoteMathRenderer.render("x^{2}", fontSize: 40, color: .black, display: true), scale: 4)
        expect(power.ink(x: 0.62...1, y: 0...0.45) > 30, "the ssty superscript draws")
    }

    static func macrosAndChemistry() {
        expect(abs(box("\\newcommand{\\sq}[1]{#1^2}\\sq{x}").width - box("x^2").width) < 0.001, "macros lay out like their expansion")
        let water = box("\\ce{H2O}")
        let two = inks(water, glyph: scriptGlyph("2", 1))
        expect(two.count == 1 && two[0].origin.y < 0, "formula numbers are subscripts")
        expect(inks(water, glyph: glyph("H")).count == 1 && inks(water, glyph: glyph("𝐻")).isEmpty, "elements are upright")
        let sulfate = box("\\ce{SO4^2-}")
        let four = inks(sulfate, glyph: scriptGlyph("4", 1)), charge = inks(sulfate, glyph: scriptGlyph("2", 1))
        expect(four.count == 1 && charge.count == 1 && four[0].origin.y < 0 && charge[0].origin.y > 0, "charge above, count below")
        expect(abs(four[0].origin.x - charge[0].origin.x) < 0.5, "charge and count share a column")
        let isotope = box("\\ce{^{227}_{90}Th}")
        let seven = inks(isotope, glyph: scriptGlyph("7", 1)), zero = inks(isotope, glyph: scriptGlyph("0", 1))
        let scriptScale = size * 0.7 / 1000
        let sevenRight = (seven.first?.origin.x ?? 0) + font.metrics(scriptGlyph("7", 1)).advance * scriptScale
        let zeroRight = (zero.first?.origin.x ?? 0) + font.metrics(scriptGlyph("0", 1)).advance * scriptScale
        expect(seven.count == 1 && zero.count == 1 && abs(sevenRight - zeroRight) < 0.01
               && extent(seven).minY > extent(zero).maxY, "isotope numbers right-align on the left")
        let lapped = box("x\\llap{y}")
        expect(abs(lapped.width - box("x").width) < 0.01, "llap takes no width")
        let lapY = inks(lapped, glyph: glyph("𝑦"))
        expect(lapY.count == 1 && lapY[0].origin.x < box("x").width - 1, "llap overlaps leftwards")
        let axis = font.constants[.axisHeight] * size / 1000
        func halves(_ latex: String) -> (CGRect, CGRect) {
            let marks = box(latex).inks.filter { ink in
                if case .glyph(let value, _) = ink.content { return value != glyph("A") && value != glyph("B") }
                return false
            }
            return (extent(marks.filter { extent([$0]).midY > axis }), extent(marks.filter { extent([$0]).midY < axis }))
        }
        let balanced = halves("\\ce{A <=> B}")
        expect(!balanced.0.isNull && !balanced.1.isNull, "equilibrium harpoons stack around the axis")
        expect(abs(balanced.0.width - balanced.1.width) < 0.6 && balanced.0.minY > balanced.1.maxY - 0.01, "balanced harpoons match")
        expect(balanced.0.width >= size * 1.3, "the equilibrium arrow is long")
        let right = halves("\\ce{A <=>> B}"), left = halves("\\ce{A <<=> B}")
        expect(right.0.width > right.1.width * 1.3, "<=>> leans right with a long top harpoon")
        expect(left.1.width > left.0.width * 1.3, "<<=> leans left with a long bottom harpoon")
        let label = box("\\ce{A ->[heat][cat] B}")
        expect(label.ascent > size * 0.7 && label.descent > size * 0.3, "arrow labels sit above and below")
        expect(box("\\ce{A ->[very long label] B}").width > box("\\ce{A -> B}").width + size, "arrows stretch for labels")
        expect(inks(box("\\ce{BaSO4 v}"), glyph: glyph("↓")).count == 1, "precipitate arrow")
        expect(box("\\pu{9.81 m/s^2}").width > box("9.81").width + size, "units follow their number")
        let reaction = bitmap(NoteMathRenderer.render("\\ce{N2 + 3H2 <=> 2NH3}", fontSize: 40, color: .black, display: true))
        expect(reaction.ink(x: 0...1, y: 0...1) > 400, "a reaction renders")
        let arrowBand = bitmap(NoteMathRenderer.render("\\ce{<=>}", fontSize: 40, color: .black, display: true))
        expect(arrowBand.ink(x: 0.1...0.9, y: 0...0.48) > 20 && arrowBand.ink(x: 0.1...0.9, y: 0.52...1) > 20,
               "the equilibrium arrow draws two strokes")
        let macroBitmap = bitmap(NoteMathRenderer.render("\\def\\half#1{\\frac{#1}{2}}\\half{x}", fontSize: 40, color: .black, display: true))
        expect(!macroBitmap.fullRows().isEmpty && macroBitmap.ink(x: 0...1, y: 0...0.4) > 30, "macro fractions draw their rule and numerator")
        let error = NoteMathRenderer.render("\\def\\a{\\a}\\a", fontSize: 20, color: .black, display: true)
        expect(error.error?.hasPrefix("\\a keeps expanding") == true && error.errorRange == NSRange(location: 10, length: 2),
               "runaway macros render as a clear error")
    }

    static func tagged(_ latex: String, line: UInt = #line) -> NoteMathBox {
        do {
            return NoteMathTypesetter(font: font, baseSize: size).typeset(try NoteMathParser.parseEquation(latex, display: true), display: true)
        } catch {
            failTest("\(latex) failed to parse: \(error.message)", line: line)
        }
    }

    static func tags() {
        let single = tagged("x = y \\tag{1}")
        expect(single.tags.count == 1 && abs(single.tags[0].baseline) < 0.001, "a one-line tag sits on the baseline")
        expect(abs(single.width - box("x = y").width) < 0.001 && single.inks.count == box("x = y").inks.count, "the tag stays out of the formula box")
        let align = tagged("\\begin{align} a &= b \\\\ c &= d \\end{align}")
        let equals = inks(align, glyph: glyph("=")).map(\.origin.y).sorted(by: >)
        let baselines = align.tags.map(\.baseline).sorted(by: >)
        expect(align.tags.count == 2 && equals.count == 2 && zip(equals, baselines).allSatisfy { abs($0 - $1) < 0.001 },
               "align tags sit on their rows")
        let last = tagged("\\begin{align} a &= b \\notag \\\\ c &= d \\end{align}")
        expect(last.tags.count == 1 && abs(last.tags[0].baseline - equals[1]) < 0.001, "notag leaves the number on the last line")
        let lines = tagged("a \\\\ b \\\\ c \\tag{1}")
        let middle = (lines.ascent - lines.descent) / 2
        let tagBox = lines.tags[0].box
        expect(abs(lines.tags[0].baseline + (tagBox.ascent - tagBox.descent) / 2 - middle) < 0.001, "multi-line tags centre on the equation")
        let matrix = tagged("\\begin{pmatrix} 1 \\\\ 2 \\\\ 3 \\end{pmatrix} \\tag{M}")
        let axis = font.constants[.axisHeight] * size / 1000
        expect(abs((matrix.ascent - matrix.descent) / 2 - axis) < 0.5 && abs(matrix.tags[0].baseline) < 0.001,
               "tags line up with the middle of tall formulas")
        let rendering = NoteMathRenderer.render("E = mc^2 \\tag{1}", fontSize: 40, color: .black, display: true)
        let plain = NoteMathRenderer.render("E = mc^2", fontSize: 40, color: .black, display: true)
        expect(rendering.error == nil && rendering.hasTags && !plain.hasTags, "renderings know about tags")
        expect(rendering.size.width > plain.size.width + 40, "the natural size leaves room for the tag")
        let width: CGFloat = 600
        let canvasWidth = Int(width * 2), canvasHeight = Int((rendering.size.height * 2).rounded(.up))
        var pixels = [UInt8](repeating: 0, count: canvasWidth * canvasHeight * 4)
        pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: canvasWidth, height: canvasHeight, bitsPerComponent: 8,
                                          bytesPerRow: canvasWidth * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
            context.scaleBy(x: 2, y: 2)
            rendering.draw(in: context, at: .zero, width: width)
        }
        let wide = Bitmap(width: canvasWidth, height: canvasHeight, alpha: stride(from: 3, to: pixels.count, by: 4).map { pixels[$0] })
        expect(wide.ink(x: 0.9...1, y: 0...1) > 30, "the tag sits flush right")
        expect(wide.ink(x: 0.35...0.65, y: 0...1) > 100, "the formula stays centred")
        expect(wide.ink(x: 0...0.3, y: 0...1) == 0 && wide.ink(x: 0.7...0.88, y: 0...1) == 0, "open space either side")
        expect(abs(rendering.equationOffset(width: width) - (width - plain.size.width) / 2) < 1.5, "the formula centres as if untagged")
        let crowded = NoteMathRenderer.render("\\sum_{n=1}^{\\infty} \\frac{1}{n^2} = \\frac{\\pi^2}{6} \\tag{Basel}", fontSize: 40, color: .black, display: true)
        let snug = crowded.size.width + 20
        expect(crowded.equationOffset(width: snug) + crowded.size.width - crowded.equationOffset(width: crowded.size.width) <= snug + 0.5,
               "a crowded formula slides left to make room for its tag")
        expect(crowded.equationOffset(width: 10) == 0, "a narrow block falls back to the natural layout")
        let tight = bitmap(crowded)
        expect(tight.ink(x: 0.85...1, y: 0.2...0.8) > 30 && tight.ink(x: 0...0.5, y: 0...1) > 100, "natural size draws formula then tag")
        let numbered = bitmap(NoteMathRenderer.render("\\begin{align} a &= b \\\\ c &= d \\end{align}", fontSize: 40, color: .black, display: true))
        expect(numbered.ink(x: 0.75...1, y: 0...0.5) > 30 && numbered.ink(x: 0.75...1, y: 0.5...1) > 30, "align draws a number per row")
        let inline = NoteMathRenderer.render("x \\tag{1}", fontSize: 20, color: .black, display: false)
        expect(inline.error == "\\tag only works in display equations", "inline tags show an error")
    }

    static func renderer() {
        let black = NSColor.black
        let rendering = NoteMathRenderer.render("x^2 + y^2 = z^2", fontSize: size, color: black, display: true)
        expect(rendering.error == nil && rendering.size.width > size * 4 && rendering.baseline > 0, "renders without error")
        expect(rendering.baseline < rendering.size.height && rendering.descent > 0, "baseline sits inside the frame")
        let broken = NoteMathRenderer.render("\\frac{a}", fontSize: size, color: black, display: true)
        expect(broken.error == "\\frac needs 2 arguments" && broken.size.width > size, "errors render the source")
        expect(broken.errorRange == NSRange(location: 7, length: 1), "error range points at the last brace")
        let empty = NoteMathRenderer.render("   ", fontSize: size, color: black, display: false)
        expect(empty.isEmpty && empty.error == nil && empty.size == .zero, "empty input is empty")
        let first = NoteMathRenderer.layout("\\frac{1}{2}", fontSize: size, display: true)
        let second = NoteMathRenderer.layout("\\frac{1}{2}", fontSize: size, display: true)
        expect(first === second, "layouts are cached")
        expect(NoteMathRenderer.layout("\\frac{1}{2}", fontSize: size, display: false) !== first, "cache keys include the style")
        let textFont = NSFont.systemFont(ofSize: 16)
        let matched = NoteMathRenderer.fontSize(matching: textFont)
        expect(matched >= 16 * 0.9 && matched <= 16 * 1.35, "inline size matches the text x-height")
        let attachment = NoteMathRenderer.attachment(for: "\\sqrt{2}", font: textFont, color: black)
        expect(attachment.image != nil && attachment.bounds.minY < 0 && attachment.bounds.height > 10, "attachment sits on the baseline")
        let image = rendering.image()
        expect(image.size == rendering.size && image.accessibilityDescription == "Equation: x^2 + y^2 = z^2", "image helper")
        expect(rendering.cgImage(scale: 2)?.width == Int((rendering.size.width * 2).rounded(.up)), "CGImage helper")
        let flippedImage = rendering.image(appearance: NSAppearance(named: .darkAqua))
        expect(flippedImage.size == rendering.size, "appearance-resolved image helper")
    }

    struct Bitmap {
        let width: Int
        let height: Int
        let alpha: [UInt8]

        func ink(x: ClosedRange<Double>, y: ClosedRange<Double>) -> Int {
            var count = 0
            let columns = Int(x.lowerBound * Double(width))..<max(Int(x.upperBound * Double(width)), Int(x.lowerBound * Double(width)) + 1)
            let rows = Int(y.lowerBound * Double(height))..<max(Int(y.upperBound * Double(height)), Int(y.lowerBound * Double(height)) + 1)
            for row in rows where row >= 0 && row < height {
                for column in columns where column >= 0 && column < width {
                    if alpha[row * width + column] > 40 { count += 1 }
                }
            }
            return count
        }

        func fullRows() -> [Int] {
            (0..<height).filter { row in (0..<width).filter { alpha[row * width + $0] > 200 }.count > width * 6 / 10 }
        }
    }

    static func bitmap(_ rendering: NoteMathRendering, scale: CGFloat = 2) -> Bitmap {
        let width = Int((rendering.size.width * scale).rounded(.up)), height = Int((rendering.size.height * scale).rounded(.up))
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
            context.scaleBy(x: scale, y: scale)
            rendering.draw(in: context, at: .zero)
        }
        return Bitmap(width: width, height: height, alpha: stride(from: 3, to: pixels.count, by: 4).map { pixels[$0] })
    }

    static func bitmaps() {
        let fraction = bitmap(NoteMathRenderer.render("\\frac{a}{b}", fontSize: 40, color: .black, display: true))
        expect(fraction.ink(x: 0...1, y: 0...0.4) > 50, "numerator ink in the top band")
        expect(fraction.ink(x: 0...1, y: 0.6...1) > 50, "denominator ink in the bottom band")
        expect(!fraction.fullRows().isEmpty, "the fraction rule spans the width")
        let power = bitmap(NoteMathRenderer.render("x^2", fontSize: 40, color: .black, display: true))
        expect(power.ink(x: 0.62...1, y: 0...0.45) > 30, "superscript ink at the top right")
        expect(power.ink(x: 0.62...1, y: 0.75...1) == 0, "nothing at the bottom right")
        expect(power.ink(x: 0...0.55, y: 0.4...1) > 50, "base ink at the bottom left")
        let root = bitmap(NoteMathRenderer.render("\\sqrt{x}", fontSize: 40, color: .black, display: true))
        expect(root.ink(x: 0.5...1, y: 0...0.2) > 20, "radical overbar on top")
        let afterText = bitmap(NoteMathRenderer.render("\\text{ab}\\,x", fontSize: 40, color: .black, display: true))
        expect(afterText.ink(x: 0.7...1, y: 0...1) > 30, "glyphs after a text run stay in place")
        let afterFunction = bitmap(NoteMathRenderer.render("\\sin\\frac{x}{y}", fontSize: 40, color: .black, display: true))
        expect(afterFunction.ink(x: 0.6...1, y: 0...0.4) > 20 && afterFunction.ink(x: 0.6...1, y: 0.6...1) > 20,
               "a fraction after a function name stays in place")
        let struck = bitmap(NoteMathRenderer.render("\\cancel{\\phantom{x}}", fontSize: 40, color: .black, display: true))
        expect(struck.ink(x: 0...0.4, y: 0.6...1) > 5 && struck.ink(x: 0.6...1, y: 0...0.4) > 5, "cancel draws a rising stroke")
        let red = bitmap(NoteMathRenderer.render("\\color{red}{x}", fontSize: 40, color: .black, display: true))
        expect(red.ink(x: 0...1, y: 0...1) > 50, "coloured ink draws")
        let error = bitmap(NoteMathRenderer.render("\\frac{a}", fontSize: 40, color: .black, display: true))
        expect(error.ink(x: 0...1, y: 0...1) > 50, "error source draws")
        let matrix = bitmap(NoteMathRenderer.render("\\begin{bmatrix} a & b \\\\ c & d \\end{bmatrix}", fontSize: 40, color: .black, display: true))
        expect(matrix.ink(x: 0...0.12, y: 0.1...0.9) > 50 && matrix.ink(x: 0.88...1, y: 0.1...0.9) > 50, "brackets on both sides")
        expect(matrix.ink(x: 0.2...0.45, y: 0...0.5) > 30 && matrix.ink(x: 0.55...0.8, y: 0.5...1) > 30, "cells in their quadrants")
    }

    static func lineInks(_ box: NoteMathBox) -> [NoteMathInk] {
        box.inks.filter { if case .line = $0.content { return true } else { return false } }
    }

    static func fallbackGlyphs() {
        for text in ["日本", "😀"] {
            let full = box("x\\text{\(text)}")
            let script = box("x_{\\text{\(text)}}")
            let fullLine = lineInks(full), scriptLine = lineInks(script)
            expect(fullLine.count == 1 && scriptLine.count == 1, "\(text) falls back to one system run")
            guard case .line(let fullRun)? = fullLine.first?.content, case .line(let scriptRun)? = scriptLine.first?.content else { continue }
            let fullFont = (CTRunGetAttributes((CTLineGetGlyphRuns(fullRun) as! [CTRun])[0]) as NSDictionary)[kCTFontAttributeName] as! CTFont
            let scriptFont = (CTRunGetAttributes((CTLineGetGlyphRuns(scriptRun) as! [CTRun])[0]) as NSDictionary)[kCTFontAttributeName] as! CTFont
            expect(abs(CTFontGetSize(fullFont) - size) < 0.01, "\(text) uses the text size: \(CTFontGetSize(fullFont))")
            expect(abs(CTFontGetSize(scriptFont) - size * font.constants.scriptPercentScaleDown / 100) < 0.01,
                   "\(text) in a subscript scales to script size: \(CTFontGetSize(scriptFont))")
            expect(CTFontCopyPostScriptName(scriptFont) as String != "STIXTwoMath-Regular", "\(text) isn't drawn with the math font")
            expect(script.width < full.width, "\(text) in a subscript is narrower")
            let subscriptRun = scriptLine[0]
            expect(subscriptRun.origin.y < -0.5, "the subscript run sits below the baseline: \(subscriptRun.origin.y)")
            let typographic = box("\\text{\(text)}")
            expect(typographic.ascent > 0 && typographic.ascent < size * 1.3 && typographic.descent < size * 0.5,
                   "\(text) keeps sensible metrics: \(typographic.ascent) \(typographic.descent)")
        }
        let mixed = box("x_{\\text{a日}}")
        expect(!inks(mixed, glyph: scriptGlyph("a", 1)).isEmpty && lineInks(mixed).count == 1,
               "covered letters keep the script glyph and only the gap falls back")
        let symbol = box("x^{★}")
        expect(symbol.width > box("x").width, "a symbol from either font draws in a superscript")
        let picture = bitmap(NoteMathRenderer.render("x_{\\text{日本}}", fontSize: 40, color: .black, display: true))
        expect(picture.ink(x: 0.4...1, y: 0.35...1) > 30, "fallback subscript ink at the bottom right")
        expect(picture.ink(x: 0.45...1, y: 0...0.2) == 0, "nothing floats above the fallback subscript")
    }

    static func references() {
        let context = NoteMathNumberingContext(references: ["e": [.text("12", .roman)]], referenceDigest: "e=12")
        let resolved = NoteMathRenderer.render("x = \\eqref{e}", fontSize: 40, color: .black, display: false, numbering: context)
        let missing = NoteMathRenderer.render("x = \\eqref{gone}", fontSize: 40, color: .black, display: false, numbering: context)
        let found = resolved.links(width: resolved.size.width)
        expect(found.count == 1 && found[0].key == "e" && found[0].resolved, "a resolved reference is a link")
        expect(found[0].rect.maxX <= resolved.size.width + 0.5 && found[0].rect.minX > resolved.size.width * 0.3, "the link sits on the reference")
        let lost = missing.links(width: missing.size.width)
        expect(lost.count == 1 && !lost[0].resolved, "a missing reference is marked")
        let missingBox = NoteMathTypesetter(font: font, baseSize: size).typeset([.reference("gone", parenthesized: true, label: nil)], display: false)
        expect(missingBox.inks.allSatisfy { if case .muted = $0.color { return true } else { return false } }, "missing references use muted ink")
        let plain = NoteMathRenderer.render("x = \\eqref{e}", fontSize: 40, color: .black, display: false)
        expect(plain.size.width != resolved.size.width, "the cache keeps numbered and unnumbered renders apart")
        let display = NoteMathRenderer.render("\\begin{equation} a \\end{equation}", fontSize: 40, color: .black, display: true,
                                             numbering: NoteMathNumberingContext(firstNumber: 6))
        expect(display.hasTags, "page numbering keeps the tag")
        let picture = bitmap(resolved)
        expect(picture.ink(x: 0.55...1, y: 0...1) > 40, "the reference number draws")
        let pictureMissing = bitmap(missing)
        expect(pictureMissing.ink(x: 0.55...1, y: 0...1) > 40, "the missing marker draws")
    }

    static func katexBoxesSizesAndLinks() {
        let normal = box("x", display: false), huge = box("\\Huge x", display: false), tiny = box("\\tiny x", display: false)
        expect(abs(huge.width / normal.width - 2.488) < 0.02, "Huge is 2.488 times as wide")
        expect(abs(tiny.width / normal.width - 0.5) < 0.02, "tiny is half as wide")
        expect(abs(box("\\Huge{\\tiny x}", display: false).width - tiny.width) < 0.01, "sizes are absolute, not nested")
        expect(abs(box("x^{\\normalsize y}", display: false).width - box("x^{y}", display: false).width) < 0.01, "normalsize in a script keeps the script")
        let raised = box("\\raisebox{0.5em}{x}", display: false), flat = box("\\text{x}", display: false)
        expect(abs(raised.ascent - flat.ascent - 0.5 * size) < 0.01, "raisebox lifts by its length")
        let smashed = box("\\smash{\\frac{a}{b}}", display: false)
        expect(smashed.ascent == 0 && smashed.descent == 0 && !smashed.inks.isEmpty, "smash keeps ink and drops height")
        let bottomless = box("\\smash[b]{y}", display: false)
        expect(bottomless.ascent > 0 && bottomless.descent == 0, "smash b keeps the height")
        let stack = box("\\substack{a\\\\b\\\\c}", display: false), single = box("\\substack{a}", display: false)
        expect(stack.height > single.height * 2, "substack stacks rows")
        expect(abs(single.width - box("{\\scriptstyle a}", display: false).width) < 0.01, "substack cells use script size")
        let thin = box("\\genfrac{}{}{0.1em}{}{a}{b}", display: false)
        let rules = thin.inks.compactMap { ink -> CGSize? in if case .rule(let size) = ink.content { return size }; return nil }
        expect(rules.count == 1 && abs(rules[0].height - 0.1 * size) < 0.01, "genfrac draws its own rule thickness")
        let colorBox = box("\\colorbox{red}{hi}", display: false), text = box("\\text{hi}", display: false)
        expect(abs(colorBox.width - text.width - 0.6 * size) < 0.01, "colorbox pads by fboxsep")
        expect(colorBox.inks.first.map { if case .rule = $0.content, case .custom = $0.color { true } else { false } } == true, "background draws first")
        let framed = box("\\fcolorbox{blue}{red}{hi}", display: false)
        expect(abs(framed.width - text.width - 0.68 * size) < 0.01 && framed.inks.count == text.inks.count + 5, "fcolorbox adds a frame")
        let link = NoteMathRenderer.render("a + \\href{https://katex.org}{b}", fontSize: 40, color: .black, display: false)
        let marks = link.links(width: link.size.width)
        expect(marks.count == 1 && marks[0].url == "https://katex.org" && marks[0].resolved, "href makes a clickable link")
        expect(marks.first.map { $0.rect.minX > link.size.width * 0.5 } == true, "the link covers the linked part")
        let url = box("\\url{https://parc.is}", display: false)
        expect(url.links.first?.url == "https://parc.is" && url.inks.contains { if case .link = $0.color { true } else { false } }, "url underlines")
        let group = box("\\overgroup{ABCD}", display: false), plain = box("ABCD", display: false)
        expect(group.ascent > plain.ascent + 0.1 * size, "overgroup arcs over its base")
        expect(box("\\undergroup{ABCD}", display: false).descent > plain.descent + 0.1 * size, "undergroup hangs below")
        let dash = box("\\tripledash", display: false), minus = box("-", display: false)
        expect(dash.ascent >= minus.ascent - 0.01, "tripledash keeps a minus strut")
        let lines = box("\\ce{A\\bond{~-}B}", display: false), plainBond = box("\\ce{A\\bond{-}B}", display: false)
        expect(lines.inks.count > plainBond.inks.count, "a dashed bond adds its dashes above the line")
        for bond in ["~", "~-", "~=", "~--", "-~-", "...", "...."] {
            let rendering = NoteMathRenderer.render("\\ce{C\\bond{\(bond)}C}", fontSize: 30, color: .black, display: false)
            expect(rendering.error == nil && bitmap(rendering).ink(x: 0.35...0.65, y: 0...1) > 4, "bond \(bond) draws between the atoms")
        }
    }

    static func samples() {
        let formulas = [
            "x = \\frac{-b \\pm \\sqrt{b^2 - 4ac}}{2a}",
            "e^{i\\pi} + 1 = 0",
            "\\nabla \\times \\vec{E} = -\\frac{\\partial \\vec{B}}{\\partial t}",
            "\\int_{-\\infty}^{\\infty} e^{-x^2}\\,dx = \\sqrt{\\pi}",
            "\\sum_{n=1}^{\\infty} \\frac{1}{n^2} = \\frac{\\pi^2}{6}",
            "\\lim_{h \\to 0} \\frac{f(x+h) - f(x)}{h}",
            "\\mathbb{R}^n \\subseteq \\mathcal{L}(\\mathfrak{g}) \\cup \\boldsymbol{\\mu}",
            "\\begin{vmatrix} a & b \\\\ c & d \\end{vmatrix} = ad - bc",
            "\\begin{Bmatrix} 1 \\end{Bmatrix}\\begin{Vmatrix} 2 \\end{Vmatrix}",
            "|x| = \\begin{cases} x & \\text{if } x \\geq 0 \\\\ -x & \\text{otherwise} \\end{cases}",
            "\\begin{align*} f(x) &= (x+1)^2 \\\\ &= x^2 + 2x + 1 \\end{align*}",
            "\\begin{gathered} a = b \\\\ c = d \\end{gathered}",
            "\\oint_C \\mathbf{F} \\cdot d\\mathbf{r} = \\iint_S (\\nabla \\times \\mathbf{F}) \\cdot d\\mathbf{S}",
            "\\left\\langle \\psi \\middle| \\hat{H} \\middle| \\psi \\right\\rangle",
            "\\left\\lfloor \\frac{n}{2} \\right\\rfloor + \\left\\lceil \\frac{n}{2} \\right\\rceil = n",
            "\\binom{n}{k} = \\frac{n!}{k!(n-k)!}",
            "\\overbrace{1 + 2 + \\cdots + n}^{n \\text{ terms}} = \\underbrace{\\frac{n(n+1)}{2}}_{\\text{Gauss}}",
            "\\color{#e03e3e}{a^2} + \\textcolor{blue}{b^2}",
            "\\operatorname*{arg\\,max}_{\\theta} \\log p(x \\mid \\theta)",
            "\\sqrt[3]{\\frac{\\alpha}{\\beta}} \\approx \\tilde{x} \\ne \\bar{y} \\equiv \\dot{z} \\sim \\ddot{w}",
            "\\widetilde{abc} \\widehat{xyz} \\overleftarrow{AB} \\underrightarrow{CD} \\overleftrightarrow{EF}",
            "A \\longleftarrow B \\Longrightarrow C",
            "\\Bigl( \\bigl[ x \\bigr] \\Bigr) \\quad \\biggl\\{ y \\biggr\\} \\Biggl| z \\Biggr|",
            "\\begin{array}{|l|c|r|} \\hline 1 & 2 & 3 \\\\ \\hline \\end{array}",
            "\\boxed{E = mc^2} \\phantom{x} \\hphantom{y} \\vphantom{\\frac{a}{b}}",
            "\\displaystyle\\sum_i x_i \\textstyle\\sum_i x_i \\scriptstyle x \\scriptscriptstyle y",
            "\\forall \\epsilon > 0\\ \\exists \\delta > 0 : |x - a| < \\delta \\implies |f(x) - f(a)| < \\epsilon",
            "f'(x) = f''(x) + f'''(x)",
            "\\text{Résumé: 😀 数学}",
            "\\begin{smallmatrix} a & b \\\\ c & d \\end{smallmatrix}",
            "\\stackrel{\\text{def}}{=} \\overset{?}{=} \\underset{n}{\\max}",
            "x \\in \\{1, 2, 3\\} \\setminus \\emptyset",
            "A \\xrightarrow[\\text{under}]{f \\circ g} B \\xLeftrightarrow{} C \\xmapsto{n} D \\xhookrightarrow{i} E",
            "\\cancel{a} \\bcancel{b} \\xcancel{c} \\sout{d} \\in \\R \\setminus \\Q",
            "\\newcommand{\\norm}[1]{\\left\\lVert #1 \\right\\rVert} \\norm{\\vec{v}} \\le \\norm{u}",
            "\\ce{2H2 + O2 -> 2H2O}",
            "\\ce{Fe2(SO4)3 + 3Ba^2+ -> 3BaSO4 v + 2Fe^3+}",
            "\\ce{CaCO3(s) ->[\\Delta] CaO(s) + CO2(g) ^}",
            "\\ce{CH3COOH <=> CH3COO- + H+} \\quad \\ce{A <=>> B} \\quad \\ce{C <<=> D} \\quad \\ce{E <--> F}",
            "\\ce{^{235}_{92}U + ^{1}_{0}n -> ^{141}_{56}Ba + ^{92}_{36}Kr + 3^{1}_{0}n}",
            "\\ce{CuSO4*5H2O} \\quad \\ce{H-C#C-H} \\quad \\ce{[Cu(NH3)4]^2+}",
            "\\Delta H = \\pu{-285.8 kJ/mol} \\quad \\pu{6.022e23 mol-1} \\quad \\pu{25 °C}",
            "\\begin{equation*} \\llap{a}b \\mathrlap{c}d \\clap{e} \\end{equation*}",
        ]
        for formula in formulas {
            for display in [true, false] {
                let rendering = NoteMathRenderer.render(formula, fontSize: 18, color: .black, display: display)
                expect(rendering.error == nil, "\(formula) renders: \(rendering.error ?? "")")
                expect(rendering.size.width > 4 && rendering.size.height > 4 && rendering.size.width.isFinite && rendering.size.height.isFinite,
                       "\(formula) has a sane size")
                let pixels = bitmap(rendering, scale: 1)
                expect(pixels.ink(x: 0...1, y: 0...1) > 10, "\(formula) leaves ink")
            }
        }
    }
}
