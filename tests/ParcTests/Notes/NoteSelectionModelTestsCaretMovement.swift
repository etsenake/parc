import CoreGraphics
import Foundation
import Testing
@testable import Parc
@testable import ParcCore
@testable import ParcNotes

@MainActor
struct NoteSelectionModelTestsCaretMovement {
    private typealias Block = NoteSelectionModelTestsSupport.Layout.Block

    private func navigator(_ blocks: [Block]) -> (NoteSelectionNavigator, NoteSelectionModelTestsSupport.Layout) {
        let layout = NoteSelectionModelTestsSupport.Layout(blocks)
        return (NoteSelectionNavigator(items: layout.items), layout)
    }

    private let a = Block(text: "first"), b = Block(text: "second")

    @MainActor private struct Vertical {
        let a = Block(text: "abcdefghijklmnopqrstuvwxy"), divider = Block(role: .decoration)
        let b = Block(text: "short"), image = Block(role: .object), c = Block(text: "last block")
        var all: [Block] { [a, divider, b, image, c] }
    }

    private let vertical = Vertical()

    @MainActor
    private final class CaptionLayout: NoteSelectionLayout {
        var items: [NoteSelectionItem] { [] }
        func length(of position: NotePosition) -> Int { 0 }
        func caretX(at position: NotePosition) -> CGFloat? { 0 }
        func lineOffset(from position: NotePosition, up: Bool, x: CGFloat) -> Int? { nil }
        func entryOffset(in block: NoteBlockID, x: CGFloat, fromAbove: Bool) -> Int { 0 }
        func characterOffset(from position: NotePosition, forward: Bool) -> Int? { nil }
        func wordOffset(from position: NotePosition, forward: Bool) -> Int? { nil }
        func paragraphOffset(from position: NotePosition, forward: Bool) -> Int? { nil }
        func lineEdgeOffset(from position: NotePosition, forward: Bool) -> Int { 0 }
        func wordRange(at position: NotePosition) -> Range<Int> { 0..<0 }
    }

    @Test func upFromACaptionSelectsItsBlock() {
        let (nav, _) = navigator(vertical.all)
        let caption = nav.verticalLanding(from: NotePosition(vertical.b.id, 0, field: .caption), up: true, x: 0, layout: CaptionLayout())
        #expect(caption == .block(vertical.b.id))
    }

    @MainActor private struct Horizontal {
        let a = Block(text: "one two"), image = Block(role: .object), b = Block(text: "three four")
        var all: [Block] { [a, image, b] }
    }

    private let horizontal = Horizontal()

    private func horizontalLanding(_ position: NotePosition, forward: Bool) -> NoteSelectionLanding? {
        let (nav, layout) = navigator(horizontal.all)
        return nav.horizontalLanding(from: position, forward: forward, unit: .character, layout: layout)
    }

    private func horizontalHead(_ position: NotePosition, forward: Bool, unit: NoteSelectionHorizontalUnit) -> NotePosition {
        let (nav, layout) = navigator(horizontal.all)
        return nav.horizontalHead(from: position, forward: forward, unit: unit, layout: layout)
    }

    @Test func rightAtTheEndLandsOnAnImageAsABlock() {
        #expect(horizontalLanding(NotePosition(horizontal.a.id, 7), forward: true) == .block(horizontal.image.id))
    }

    @Test func leftAtTheStartLandsOnAnImageAsABlock() {
        #expect(horizontalLanding(NotePosition(horizontal.b.id, 0), forward: false) == .block(horizontal.image.id))
    }

    @Test func leftAtThePageStartStaysPut() {
        #expect(horizontalLanding(NotePosition(horizontal.a.id, 0), forward: false) == nil)
    }

    @Test func shiftRightCrossesIntoTheNextTextBlock() {
        #expect(horizontalHead(NotePosition(horizontal.a.id, 7), forward: true, unit: .character) == NotePosition(horizontal.b.id, 0))
    }

    @Test func shiftOptionRightCrossesAndTakesTheNextWord() {
        #expect(horizontalHead(NotePosition(horizontal.a.id, 7), forward: true, unit: .word) == NotePosition(horizontal.b.id, 5))
    }

    @Test func shiftOptionLeftCrossesBackAndTakesThePreviousWord() {
        #expect(horizontalHead(NotePosition(horizontal.b.id, 0), forward: false, unit: .word) == NotePosition(horizontal.a.id, 4))
    }

    @Test func extendingPastThePageEndStaysPut() {
        #expect(horizontalHead(NotePosition(horizontal.b.id, 10), forward: true, unit: .character) == NotePosition(horizontal.b.id, 10))
    }

    @Test func aWordStepInsideABlock() {
        #expect(horizontalHead(NotePosition(horizontal.b.id, 3), forward: true, unit: .word) == NotePosition(horizontal.b.id, 5))
    }

    @MainActor private struct Paragraphs {
        let a = Block(text: "line one\nline two"), image = Block(role: .object), b = Block(text: "alpha\nbeta")
        var all: [Block] { [image, a, b] }
    }

    private let paragraphs = Paragraphs()

    private func paragraphHead(_ position: NotePosition, forward: Bool) -> NotePosition {
        let (nav, layout) = navigator(paragraphs.all)
        return nav.paragraphHead(from: position, forward: forward, layout: layout)
    }

    @Test func aCaretMovesToTheParagraphEnd() {
        #expect(paragraphHead(NotePosition(paragraphs.a.id, 2), forward: true) == NotePosition(paragraphs.a.id, 8))
    }

    @Test func aCaretMovesToTheNextParagraphEnd() {
        #expect(paragraphHead(NotePosition(paragraphs.a.id, 8), forward: true) == NotePosition(paragraphs.a.id, 17))
    }

    @Test func crossesToTheNextBlocksFirstParagraphEnd() {
        #expect(paragraphHead(NotePosition(paragraphs.a.id, 17), forward: true) == NotePosition(paragraphs.b.id, 5))
    }

    @Test func crossesBackToThePreviousBlocksLastParagraphStart() {
        #expect(paragraphHead(NotePosition(paragraphs.b.id, 0), forward: false) == NotePosition(paragraphs.a.id, 9))
    }

    @Test func documentStartSkipsTheLeadingImage() {
        #expect(navigator(paragraphs.all).0.documentStart == NotePosition(paragraphs.a.id, 0))
    }

    @Test func documentEndIsTheLastTextEnd() {
        let (nav, layout) = navigator(paragraphs.all)
        #expect(nav.documentEnd(layout) == NotePosition(paragraphs.b.id, 10))
    }
}
