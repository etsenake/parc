import Testing
@testable import ParcCore

struct CapturePaletteKeysTests {
    typealias Keys = CapturePaletteKeys

    @Test func arrowsMoveTheSingleHighlight() {
        #expect(Keys.command(.down, focus: .main, highlighted: nil) == .move(1))
        #expect(Keys.command(.up, focus: .main, highlighted: .copy) == .move(-1))
    }

    @Test func returnActivatesTheHighlightedAction() {
        #expect(Keys.command(.enter, focus: .main, highlighted: .copy) == .activate)
    }

    @Test func returnOnTheOpeningHighlightSavesToTheLibraryInOnePress() {
        #expect(Keys.command(.enter, focus: .main, highlighted: .library) == .activate)
    }

    @Test func returnWithoutAHighlightRevealsTheFirstRowInsteadOfActingUnseen() {
        #expect(Keys.command(.enter, focus: .main, highlighted: nil) == .move(1))
    }

    @Test func returnOnEaselOpensItsSubmenu() {
        #expect(Keys.command(.enter, focus: .main, highlighted: .easels) == .open(.easels))
    }

    @Test func rightOpensTheHighlightedSubmenu() {
        #expect(Keys.command(.right, focus: .main, highlighted: .notes) == .open(.notes))
    }

    @Test func rightInsideTypedTextStillMovesTheCaret() {
        #expect(Keys.command(.right, focus: .main, highlighted: .notes, caretAtEnd: false) == .pass)
    }

    @Test func rightOnAPlainActionStaysWithTheField() {
        #expect(Keys.command(.right, focus: .main, highlighted: .copy) == .pass)
    }

    @Test func escapeInThePaletteCancelsTheCapture() {
        #expect(Keys.command(.escape, focus: .main, highlighted: .copy) == .cancel)
    }

    @Test func tabStaysInTheMenu() {
        #expect(Keys.command(.tab, focus: .main, highlighted: nil) == .consume)
    }

    @Test func inputMethodCompositionNeverDispatchesADestination() {
        #expect(Keys.command(.enter, focus: .main, highlighted: .copy, composing: true) == .pass)
    }

    @Test func leftLeavesASubmenuOnlyFromTheStartOfItsSearch() {
        #expect(Keys.command(.left, focus: .submenu(.easels), highlighted: nil) == .closeSubmenu)
        #expect(Keys.command(.left, focus: .submenu(.easels), highlighted: nil, caretAtStart: false) == .pass)
    }

    @Test func escapeInASubmenuClosesJustTheSubmenu() {
        #expect(Keys.command(.escape, focus: .submenu(.notes), highlighted: nil) == .closeSubmenu)
    }

    @Test func returnInASubmenuSendsThere() {
        #expect(Keys.command(.enter, focus: .submenu(.notes), highlighted: .newNote) == .activate)
    }

    @Test func escapeAndLeftGoBackFromTheFramePage() {
        #expect(Keys.command(.escape, focus: .frame, highlighted: nil) == .back)
        #expect(Keys.command(.left, focus: .frame, highlighted: nil) == .back)
    }

    @Test func returnAppliesOnTheFramePageAndTabWalksItsControls() {
        #expect(Keys.command(.enter, focus: .frame, highlighted: nil) == .activate)
        #expect(Keys.command(.tab, focus: .frame, highlighted: nil) == .pass)
    }
}
