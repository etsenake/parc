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
        renderer()
        bitmaps()
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
        expect(abs(scriptSum - font.metrics(glyph("+")).advance * size * 0.7 / 1000) < 0.01, "no medium space inside scripts")
        expect(abs(box("a\\quad b").width - (a + b + size)) < 0.01, "quad is one em")
        expect(box("\\sin x").width > box("sinx").width - 3, "function names are upright and spaced")
    }

    static func scripts() {
        let base = box("x")
        let raised = box("x^2")
        let two = inks(raised, glyph: glyph("2"))
        expect(two.count == 1 && two[0].origin.y > size * 0.25, "superscripts are raised")
        expect(raised.ascent > base.ascent && raised.width > base.width, "superscript grows the box")
        if case .glyph(_, let scriptFont) = two[0].content { expect(abs(CTFontGetSize(scriptFont) - size * 0.7) < 0.01, "script size is 70%") }
        let lowered = box("x_2")
        let sub = inks(lowered, glyph: glyph("2"))
        expect(sub.count == 1 && sub[0].origin.y < 0 && lowered.descent > base.descent, "subscripts are lowered")
        let both = box("x_2^2")
        let pair = inks(both, glyph: glyph("2")).sorted { $0.origin.y > $1.origin.y }
        expect(pair.count == 2 && pair[0].origin.y > 0 && pair[1].origin.y < 0, "superscript above subscript")
        let gap = extent([pair[0]]).minY - extent([pair[1]]).maxY
        expect(gap >= font.constants[.subSuperscriptGapMin] * size / 1000 - 0.01, "sub and superscript keep their gap")
        expect(pair[0].origin.x > pair[1].origin.x, "superscript is nudged by the italic correction")
        let prime = box("f'")
        expect(inks(prime, glyph: glyph("′")).first.map { $0.origin.y > 0 } == true, "primes ride high")
        let nested = box("e^{x^2}")
        let nestedTwo = inks(nested, glyph: glyph("2"))
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
        let n = inks(display, glyph: glyph("𝑛"))
        expect(n.count == 1 && extent(n).minY > sumDisplay.maxY, "display limits sit above")
        let i = inks(display, glyph: glyph("𝑖")).sorted { $0.origin.y < $1.origin.y }
        expect(extent([i[0]]).maxY < sumDisplay.minY, "lower limit sits below")
        let textN = inks(text, glyph: glyph("𝑛"))
        expect(textN.count == 1 && textN[0].origin.x > sumText.maxX - 1, "text-style limits go beside")
        let integral = box("\\int_0^1 f")
        let one = inks(integral, glyph: glyph("1"))
        let zero = inks(integral, glyph: glyph("0"))
        expect(one.count == 1 && zero.count == 1 && one[0].origin.x > zero[0].origin.x, "integral limits go beside, nudged by its slant")
        let limited = box("\\int\\limits_0^1 f")
        let stackedOne = inks(limited, glyph: glyph("1"))
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
        let tallAccent = inks(tall, glyph: glyph("\u{0302}"))
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
