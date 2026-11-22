import Foundation
import Testing
@testable import ParcCore

struct EaselEquationPresentationTests {
    private static func equation(_ text: String = "x^2", frame: EaselRect = EaselRect(x: 10, y: 20, width: 128, height: 68),
                                 color: String? = nil) -> EaselItem {
        var item = EaselItem(kind: .equation, frame: frame, text: text)
        if let color { item.color = color }
        return item
    }


    @Test func blankIsSpokenAsEmpty() {
        #expect(NoteEquationSpeech.label(source: "", error: nil) == "Empty equation")
    }

    @Test func texIsSpoken() {
        #expect(NoteEquationSpeech.label(source: "x", error: nil) == "Equation: x")
    }

    @Test func typosAreSpoken() {
        #expect(NoteEquationSpeech.label(source: "x", error: "Oops").hasPrefix("Equation that won\u{2019}t typeset: x."))
    }

    private static let toolbarItem = EaselItem(kind: .equation, frame: EaselRect(x: 0, y: 0, width: 100, height: 50), text: "x")

    @Test func anEquationHasItsOwnToolbarThatOffersInk() {
        #expect(EaselToolbarSubject(Self.toolbarItem) == .equation)
        #expect(EaselSelectionToolbarPlan.controls(for: .equation, editingText: false) == [[.color]])
    }

    @Test func anEquationTakesInkOnly() {
        #expect(EaselStyleFamily.of(Self.toolbarItem) == .equations)
        #expect(EaselStyleFamily.equations.weights.isEmpty)
        #expect(!EaselStyleFamily.equations.takesFill)
    }

    @Test func anEquationTurnsButNeverMirrors() {
        #expect(EaselRotation.isRotatable(.equation))
        #expect(!EaselRotation.isFlippable(.equation))
    }

    @Test func aBlankEquationMatchesItsPlaceholder() {
        #expect(EaselEquation.emptySize.width == EaselMediaPlacement.placeholderSize(for: .equation).width)
    }
}
