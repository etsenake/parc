import Foundation

@main
struct EaselEquationTests {
    @MainActor static var assertions = 0

    @MainActor static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        assertions += 1
        if !condition() { fatalError(message) }
    }

    @MainActor static func main() {
        blanks()
        sizing()
        markup()
        speech()
        toolbar()
        print("EaselEquationTests: \(assertions) assertions passed")
    }

    @MainActor static func blanks() {
        expect(EaselEquation.isBlank(""), "an empty equation is blank")
        expect(EaselEquation.isBlank(" \n\t "), "whitespace is blank")
        expect(!EaselEquation.isBlank("x"), "TeX is not blank")
        expect(EaselEquation.clamped(String(repeating: "x", count: EaselEquation.maximumLength + 50)).count == EaselEquation.maximumLength,
               "long TeX is capped")
        expect(EaselEquation.clamped("x^2") == "x^2", "short TeX is untouched")
    }

    @MainActor static func sizing() {
        let natural = EaselEquation.natural(typeset: EaselEquationSize(width: 100, height: 40))
        expect(natural == EaselEquationSize(width: 100 + 2 * EaselEquation.padding, height: 40 + 2 * EaselEquation.padding),
               "the frame is the typeset size plus padding")
        expect(EaselEquation.natural(typeset: nil) == EaselEquation.emptySize, "no typesetting uses the placeholder size")
        expect(EaselEquation.natural(typeset: EaselEquationSize(width: 0, height: 10)) == EaselEquation.emptySize, "a degenerate size uses the placeholder size")
        expect(EaselEquation.natural(typeset: EaselEquationSize(width: .nan, height: 10)) == EaselEquation.emptySize, "a non-finite size uses the placeholder size")

        let frame = EaselEquation.frame(natural: natural, scale: 1, centeredOn: EaselPoint(x: 300, y: 200))
        expect(frame.width == natural.width && frame.height == natural.height, "scale one keeps the natural size")
        expect(frame.x + frame.width / 2 == 300 && frame.y + frame.height / 2 == 200, "the frame is centred")
        expect(EaselEquation.scale(of: frame, natural: natural) == 1, "scale reads back")

        let doubled = EaselEquation.frame(natural: natural, scale: 2, centeredOn: EaselPoint(x: 300, y: 200))
        expect(doubled.width == natural.width * 2 && doubled.height == natural.height * 2, "scaling keeps the aspect")
        expect(EaselEquation.scale(of: doubled, natural: natural) == 2, "doubled scale reads back")

        let wider = EaselEquationSize(width: 400, height: 80)
        let refit = EaselEquation.refitted(doubled, from: natural, to: wider)
        expect(refit.width == wider.width * 2 && refit.height == wider.height * 2, "typing keeps the chosen scale")
        expect(abs((refit.x + refit.width / 2) - (doubled.x + doubled.width / 2)) < 0.001, "typing keeps the centre across")
        expect(abs((refit.y + refit.height / 2) - (doubled.y + doubled.height / 2)) < 0.001, "typing keeps the centre down")

        expect(EaselEquation.scale(of: EaselRect(x: 0, y: 0, width: 1, height: 1), natural: natural) == EaselEquation.minimumScale, "tiny frames clamp")
        expect(EaselEquation.scale(of: EaselRect(x: 0, y: 0, width: 1_000_000, height: 1), natural: natural) == EaselEquation.maximumScale, "huge frames clamp")
        expect(EaselEquation.scale(of: frame, natural: EaselEquationSize(width: 0, height: 0)) == 1, "an unusable natural size reads as one")
        expect(EaselEquation.frame(natural: natural, scale: .nan, centeredOn: EaselPoint(x: 0, y: 0)).x >= 0, "frames never go negative")

        let inner = EaselEquation.inner(doubled, natural: natural)
        expect(inner.width == 200 && inner.height == 80, "the inner box is the typeset size at scale")
        expect(inner.x == doubled.x + EaselEquation.padding * 2, "the inner box is inset by the scaled padding")
    }

    @MainActor static func placement() {
        let natural = EaselEquation.emptySize
        let visible = EaselRect(x: 0, y: 0, width: 800, height: 600)
        let first = EaselEquation.placed(natural: natural, visible: visible, occupied: [])
        let second = EaselEquation.placed(natural: natural, visible: visible, occupied: [first])
        expect(first.x != second.x && first.y != second.y, "a second equation steps aside")
    }

    @MainActor static func markup() {
        placement()
        var item = EaselItem(kind: .equation, frame: EaselRect(x: 10, y: 20, width: 228, height: 92), text: "x^2")
        let art = EaselVectorEquation(width: 100, height: 40,
                                      parts: [EaselVectorEquationPart(path: "M0 0L10 0L10 10Z"),
                                              EaselVectorEquationPart(path: "M20 0L30 0L30 10Z", color: "#FF0000", opacity: 0.5)])
        let svg = EaselVectorExport.equation(item, art)
        let routed = EaselVectorExport.element(item, art: EaselVectorArt(equations: [item.id: art]))
        expect(routed == svg, "the object export routes through the equation art")
        expect(svg.contains("<path d=\"M0 0L10 0L10 10Z\""), "the outline is drawn as a path")
        expect(svg.contains("fill:var(--easel-ink)"), "automatic ink follows the page ink")
        expect(svg.contains("fill:#FF0000;fill-opacity:0.5"), "custom colours and opacity are kept")
        expect(svg.contains("translate(24 34)"), "the outline sits inside the padding")
        expect(svg.contains("scale(1)"), "scale one is written")
        expect(svg.contains("aria-label=\"Equation: x^2\""), "the equation is labelled for screen readers")

        item.frame = EaselRect(x: 0, y: 0, width: 256, height: 136)
        expect(EaselVectorExport.equation(item, art).contains("scale(2)"), "resizing scales the vectors")

        item.color = "#2C6C91"
        expect(EaselVectorExport.equation(item, art).contains("fill:#2C6C91"), "a chosen ink is written")

        item.text = "\\frac{"
        let failure = EaselVectorEquation(width: 0, height: 0, parts: [], error: "Missing }")
        let fallback = EaselVectorExport.equation(item, failure)
        expect(fallback.contains("<text") && fallback.contains("\\frac{"), "a TeX typo exports its source")
        expect(fallback.contains("won\u{2019}t typeset"), "a TeX typo is labelled as one")
        expect(EaselVectorExport.equation(item, nil).contains("<text"), "no art falls back to the source")

        item.text = "  "
        expect(EaselVectorExport.equation(item, art).isEmpty, "a blank equation exports nothing")

        item.text = "<script>"
        expect(!EaselVectorExport.equation(item, nil).contains("<script>"), "the source is escaped")
    }

    @MainActor static func speech() {
        expect(NoteEquationSpeech.label(source: "", error: nil) == "Empty equation", "blank is spoken as empty")
        expect(NoteEquationSpeech.label(source: "x", error: nil) == "Equation: x", "TeX is spoken")
        expect(NoteEquationSpeech.label(source: "x", error: "Oops").hasPrefix("Equation that won\u{2019}t typeset: x."), "typos are spoken")
    }

    @MainActor static func toolbar() {
        let item = EaselItem(kind: .equation, frame: EaselRect(x: 0, y: 0, width: 100, height: 50), text: "x")
        expect(EaselToolbarSubject(item) == .equation, "an equation has its own toolbar")
        expect(EaselSelectionToolbarPlan.controls(for: .equation, editingText: false) == [[.color]], "an equation offers ink")
        expect(EaselStyleFamily.of(item) == .equations, "an equation takes ink only")
        expect(EaselStyleFamily.equations.weights.isEmpty && !EaselStyleFamily.equations.takesFill, "an equation has no stroke or fill")
        expect(EaselRotation.isRotatable(.equation) && !EaselRotation.isFlippable(.equation), "an equation turns but never mirrors")
        expect(EaselEquation.emptySize.width == EaselMediaPlacement.placeholderSize(for: .equation).width, "a blank equation matches its placeholder")
    }
}
