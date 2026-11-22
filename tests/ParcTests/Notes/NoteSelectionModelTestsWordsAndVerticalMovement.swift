import CoreGraphics
import Foundation
import Testing
@testable import Parc
@testable import ParcCore
@testable import ParcNotes

@MainActor
struct NoteSelectionModelTestsWordsAndVerticalMovement {
    private typealias Block = NoteSelectionModelTestsSupport.Layout.Block

    private func navigator(_ blocks: [Block]) -> (NoteSelectionNavigator, NoteSelectionModelTestsSupport.Layout) {
        let layout = NoteSelectionModelTestsSupport.Layout(blocks)
        return (NoteSelectionNavigator(items: layout.items), layout)
    }

    private let a = Block(text: "first"), b = Block(text: "second")

    @MainActor private struct Words {
        let a = Block(text: "one two three"), b = Block(text: "four five")
    }

    private func wordRange() -> (NoteSelectionNavigator, Words, Range<Int>) {
        let words = Words()
        let (nav, layout) = navigator([words.a, words.b])
        return (nav, words, nav.granularRange(at: NotePosition(words.a.id, 5), granularity: .word, layout: layout))
    }

    @Test func aWordRangeCoversTheWord() {
        #expect(wordRange().2 == 4..<7)
    }

    @Test func aForwardWordSpanRunsWordToWord() {
        let (nav, words, range) = wordRange()
        let down = nav.span(anchor: words.a.id, anchorRange: range, head: words.b.id, headRange: 5..<9)
        #expect(down.anchor == NotePosition(words.a.id, 4))
        #expect(down.head == NotePosition(words.b.id, 9))
    }

    @Test func aBackwardWordSpanRunsWordToWord() {
        let (nav, words, range) = wordRange()
        let up = nav.span(anchor: words.b.id, anchorRange: 5..<9, head: words.a.id, headRange: range)
        #expect(up.anchor == NotePosition(words.b.id, 9))
        #expect(up.head == NotePosition(words.a.id, 4))
    }

    @Test func theSameWordKeepsTheWord() {
        let (nav, words, _) = wordRange()
        let same = nav.span(anchor: words.a.id, anchorRange: 4..<7, head: words.a.id, headRange: 4..<7)
        #expect(same.anchor == NotePosition(words.a.id, 4))
        #expect(same.head == NotePosition(words.a.id, 7))
    }

    @Test func aBackwardWordSpanInOneBlock() {
        let (nav, words, _) = wordRange()
        let back = nav.span(anchor: words.a.id, anchorRange: 4..<7, head: words.a.id, headRange: 0..<3)
        #expect(back.anchor == NotePosition(words.a.id, 7))
        #expect(back.head == NotePosition(words.a.id, 0))
    }

    @Test func paragraphGranularityIsTheWholeBlock() {
        let words = Words()
        let (nav, layout) = navigator([words.a, words.b])
        #expect(nav.granularRange(at: NotePosition(words.b.id, 2), granularity: .paragraph, layout: layout) == 0..<9)
    }

    @Test func theGoalStartsAtTheCaretX() {
        var goal = NoteGoalColumn()
        var calls = 0
        #expect(goal.value(for: NotePosition(NoteBlockID(), 3)) { calls += 1; return 30 } == 30)
        #expect(calls == 1)
    }

    @Test func theGoalSurvivesAVerticalMove() {
        var goal = NoteGoalColumn()
        let id = NoteBlockID()
        var calls = 0
        _ = goal.value(for: NotePosition(id, 3)) { calls += 1; return 30 }
        goal.moved(to: NotePosition(id, 13))
        #expect(goal.value(for: NotePosition(id, 13)) { calls += 1; return 99 } == 30)
        #expect(calls == 1)
    }

    @Test func theGoalResetsAfterTheCaretMovedElsewhere() {
        var goal = NoteGoalColumn()
        let id = NoteBlockID()
        _ = goal.value(for: NotePosition(id, 3)) { 30 }
        goal.moved(to: NotePosition(id, 13))
        #expect(goal.value(for: NotePosition(id, 5)) { 50 } == 50)
    }

    @Test func resetClearsTheGoal() {
        var goal = NoteGoalColumn()
        _ = goal.value(for: NotePosition(NoteBlockID(), 3)) { 30 }
        goal.reset()
        #expect(goal.x == nil)
        #expect(goal.head == nil)
    }

    @MainActor private struct Vertical {
        let a = Block(text: "abcdefghijklmnopqrstuvwxy"), divider = Block(role: .decoration)
        let b = Block(text: "short"), image = Block(role: .object), c = Block(text: "last block")
        var all: [Block] { [a, divider, b, image, c] }
    }

    private let vertical = Vertical()

    private func landing(from position: NotePosition, up: Bool, x: CGFloat) -> NoteSelectionLanding? {
        let (nav, layout) = navigator(vertical.all)
        return nav.verticalLanding(from: position, up: up, x: x, layout: layout)
    }

    @Test func downInsideABlockKeepsTheColumn() {
        #expect(landing(from: NotePosition(vertical.a.id, 3), up: false, x: 30) == .caret(NotePosition(vertical.a.id, 13)))
    }

    @Test func downFromTheLastLineSkipsTheDividerAndKeepsX() {
        #expect(landing(from: NotePosition(vertical.a.id, 23), up: false, x: 30) == .caret(NotePosition(vertical.b.id, 3)))
    }

    @Test func aGoalXPastTheLineEndClampsToTheEnd() {
        #expect(landing(from: NotePosition(vertical.a.id, 25), up: false, x: 90) == .caret(NotePosition(vertical.b.id, 5)))
    }

    @Test func downIntoAnImageSelectsIt() {
        #expect(landing(from: NotePosition(vertical.b.id, 2), up: false, x: 20) == .block(vertical.image.id))
    }

    @Test func upEntersThePreviousBlocksLastLine() {
        #expect(landing(from: NotePosition(vertical.b.id, 2), up: true, x: 20) == .caret(NotePosition(vertical.a.id, 22)))
    }

    @Test func upOnTheFirstLineOfThePageGoesToTheStart() {
        #expect(landing(from: NotePosition(vertical.a.id, 4), up: true, x: 40) == .caret(NotePosition(vertical.a.id, 0)))
    }

    @Test func downOnTheLastLineOfThePageGoesToTheEnd() {
        #expect(landing(from: NotePosition(vertical.c.id, 2), up: false, x: 20) == .caret(NotePosition(vertical.c.id, 10)))
    }

    @Test func extendingSkipsOverTheImageIntoText() {
        let (nav, layout) = navigator(vertical.all)
        #expect(nav.verticalHead(from: NotePosition(vertical.b.id, 2), up: false, x: 20, layout: layout) == NotePosition(vertical.c.id, 2))
    }
}
