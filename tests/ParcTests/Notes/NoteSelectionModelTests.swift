import CoreGraphics
import Foundation
import Testing
@testable import Parc
@testable import ParcCore

@MainActor
final class NoteEditorFakeSelectionLayout: NoteSelectionLayout {
    @MainActor struct Block {
        var id = NoteBlockID()
        var text = ""
        var role = NoteSelectionRole.text
        var depth = 0
        var parent: NoteBlockID?
        var x: CGFloat = 0
    }

    static let perLine = 10
    static let charWidth: CGFloat = 10
    static let lineHeight: CGFloat = 20

    var blocks: [Block]
    private(set) var items: [NoteSelectionItem] = []

    init(_ blocks: [Block]) {
        self.blocks = blocks
        var y: CGFloat = 0
        for block in blocks {
            let lines = block.role == .text ? max(1, (block.text.utf16.count + Self.perLine - 1) / Self.perLine) : 2
            let height = block.role == .layout || block.role == .column ? 0 : CGFloat(lines) * Self.lineHeight
            let frame = CGRect(x: block.x, y: y, width: 400 - block.x, height: height)
            items.append(NoteSelectionItem(id: block.id, parent: block.parent, depth: block.depth, role: block.role, frame: frame))
            y += height + 2
        }
    }

    func setFrame(_ index: Int, _ frame: CGRect) { items[index].frame = frame }

    private func block(_ id: NoteBlockID) -> Block { blocks.first { $0.id == id }! }
    private func frame(_ id: NoteBlockID) -> CGRect { items.first { $0.id == id }!.frame }
    private func text(_ id: NoteBlockID) -> [UInt16] { Array(block(id).text.utf16) }

    func length(of position: NotePosition) -> Int { text(position.block).count }

    private func lastLine(_ id: NoteBlockID) -> Int { max(0, (text(id).count - 1) / Self.perLine) }
    private func line(of position: NotePosition) -> Int { min(position.offset / Self.perLine, lastLine(position.block)) }
    private func lineLength(_ id: NoteBlockID, _ line: Int) -> Int { min(Self.perLine, text(id).count - line * Self.perLine) }

    func caretX(at position: NotePosition) -> CGFloat? {
        let line = line(of: position)
        return frame(position.block).minX + CGFloat(position.offset - line * Self.perLine) * Self.charWidth
    }

    private func offset(in id: NoteBlockID, line: Int, x: CGFloat) -> Int {
        let column = Int(((x - frame(id).minX) / Self.charWidth).rounded())
        return line * Self.perLine + min(max(0, column), lineLength(id, line))
    }

    func lineOffset(from position: NotePosition, up: Bool, x: CGFloat) -> Int? {
        let current = line(of: position)
        if up && current == 0 { return nil }
        if !up && current == lastLine(position.block) { return nil }
        return offset(in: position.block, line: current + (up ? -1 : 1), x: x)
    }

    func entryOffset(in block: NoteBlockID, x: CGFloat, fromAbove: Bool) -> Int {
        offset(in: block, line: fromAbove ? 0 : lastLine(block), x: x)
    }

    func characterOffset(from position: NotePosition, forward: Bool) -> Int? {
        if forward { return position.offset < length(of: position) ? position.offset + 1 : nil }
        return position.offset > 0 ? position.offset - 1 : nil
    }

    private static let space = UInt16(32), newline = UInt16(10)

    func wordOffset(from position: NotePosition, forward: Bool) -> Int? {
        let chars = text(position.block)
        var offset = position.offset
        if forward {
            guard offset < chars.count else { return nil }
            while offset < chars.count, chars[offset] == Self.space { offset += 1 }
            while offset < chars.count, chars[offset] != Self.space { offset += 1 }
        } else {
            guard offset > 0 else { return nil }
            while offset > 0, chars[offset - 1] == Self.space { offset -= 1 }
            while offset > 0, chars[offset - 1] != Self.space { offset -= 1 }
        }
        return offset
    }

    func paragraphOffset(from position: NotePosition, forward: Bool) -> Int? {
        let chars = text(position.block)
        var offset = position.offset
        if forward {
            guard offset < chars.count else { return nil }
            if chars[offset] == Self.newline { offset += 1 }
            while offset < chars.count, chars[offset] != Self.newline { offset += 1 }
        } else {
            guard offset > 0 else { return nil }
            if chars[offset - 1] == Self.newline { offset -= 1 }
            while offset > 0, chars[offset - 1] != Self.newline { offset -= 1 }
        }
        return offset
    }

    func lineEdgeOffset(from position: NotePosition, forward: Bool) -> Int {
        let line = line(of: position)
        return forward ? line * Self.perLine + lineLength(position.block, line) : line * Self.perLine
    }

    func wordRange(at position: NotePosition) -> Range<Int> {
        let chars = text(position.block)
        var lower = position.offset, upper = position.offset
        while lower > 0, chars[lower - 1] != Self.space { lower -= 1 }
        while upper < chars.count, chars[upper] != Self.space { upper += 1 }
        return lower..<upper
    }
}

@MainActor
struct NoteSelectionModelTests {
    typealias Block = NoteEditorFakeSelectionLayout.Block

    func navigator(_ blocks: [Block]) -> (NoteSelectionNavigator, NoteEditorFakeSelectionLayout) {
        let layout = NoteEditorFakeSelectionLayout(blocks)
        return (NoteSelectionNavigator(items: layout.items), layout)
    }

    let a = Block(text: "first"), b = Block(text: "second")

    @Test func anEarlierBlockPrecedes() {
        let (nav, _) = navigator([a, b])
        #expect(nav.precedes(NotePosition(a.id, 4), NotePosition(b.id, 0)))
    }

    @Test func aLaterBlockFollows() {
        let (nav, _) = navigator([a, b])
        #expect(!nav.precedes(NotePosition(b.id, 0), NotePosition(a.id, 4)))
    }

    @Test func theSameBlockComparesOffsets() {
        let (nav, _) = navigator([a, b])
        #expect(nav.precedes(NotePosition(a.id, 1), NotePosition(a.id, 2)))
    }

    @Test func orderedSwapsBackwardEnds() {
        let (nav, _) = navigator([a, b])
        let ends = nav.ordered(NotePosition(b.id, 2), NotePosition(a.id, 3))
        #expect(ends.start == NotePosition(a.id, 3))
        #expect(ends.end == NotePosition(b.id, 2))
    }

    @Test func theBodyComesBeforeTheCaptionWhateverTheOffsets() {
        let (nav, _) = navigator([a, b])
        let caption = NotePosition(a.id, 0, field: .caption), body = NotePosition(a.id, 4)
        #expect(nav.precedes(body, caption))
        #expect(!nav.precedes(caption, body))
    }

    @Test func cellsRunRowByRowAndSitBeforeTheCaption() {
        let (nav, _) = navigator([a, b])
        let cell = NotePosition(a.id, 9, field: .cell(row: 0, column: 1)), later = NotePosition(a.id, 0, field: .cell(row: 1, column: 0))
        #expect(nav.precedes(cell, later))
        #expect(nav.precedes(later, NotePosition(a.id, 0, field: .caption)))
    }

    @Test func orderingASameBlockSpanLooksAtTheFieldFirst() {
        let (nav, _) = navigator([a, b])
        #expect(nav.ordered(NotePosition(a.id, 0, field: .caption), NotePosition(a.id, 4)).start == NotePosition(a.id, 4))
    }

    @MainActor struct MarkBlocks {
        let a = Block(text: "hello there"), image = Block(role: .object), divider = Block(role: .decoration)
        let b = Block(text: "middle"), c = Block(text: "the end")
        var all: [Block] { [a, image, b, divider, c] }
    }

    func marksAcross() -> (MarkBlocks, [NoteBlockID: NoteSelectionMark]) {
        let blocks = MarkBlocks()
        let (nav, layout) = navigator(blocks.all)
        return (blocks, nav.marks(from: NotePosition(blocks.c.id, 3), to: NotePosition(blocks.a.id, 6)) { layout.length(of: NotePosition($0, 0)) })
    }

    @Test func theAnchorBlockHighlightsItsTail() {
        let (blocks, marks) = marksAcross()
        #expect(marks[blocks.a.id] == .text(6..<11))
    }

    @Test func objectsInTheMiddleGetTheWash() {
        let (blocks, marks) = marksAcross()
        #expect(marks[blocks.image.id] == .wash)
        #expect(marks[blocks.divider.id] == .wash)
    }

    @Test func middleTextIsFullyHighlighted() {
        let (blocks, marks) = marksAcross()
        #expect(marks[blocks.b.id] == .text(0..<6))
    }

    @Test func theHeadBlockHighlightsItsStart() {
        let (blocks, marks) = marksAcross()
        #expect(marks[blocks.c.id] == .text(0..<3))
    }

    @Test func highlightsNameTheirField() {
        let (blocks, marks) = marksAcross()
        #expect(marks[blocks.a.id]?.highlight?.field == .body)
    }

    @Test func aSingleBlockRangeIsOrdered() {
        let blocks = MarkBlocks()
        let (nav, _) = navigator(blocks.all)
        #expect(nav.marks(from: NotePosition(blocks.b.id, 4), to: NotePosition(blocks.b.id, 1)) { _ in 0 } == [blocks.b.id: .text(1..<4)])
    }

    @Test func aCaretDrawsNothing() {
        let blocks = MarkBlocks()
        let (nav, _) = navigator(blocks.all)
        #expect(nav.marks(from: NotePosition(blocks.b.id, 2), to: NotePosition(blocks.b.id, 2)) { _ in 0 }.isEmpty)
    }

    @Test func theStartKeepsItsLineEndAndATouchedEndBlockDrawsNothing() {
        let blocks = MarkBlocks()
        let (nav, layout) = navigator(blocks.all)
        let touching = nav.marks(from: NotePosition(blocks.a.id, 11), to: NotePosition(blocks.c.id, 0)) { layout.length(of: NotePosition($0, 0)) }
        #expect(touching[blocks.a.id] == .text(11..<11))
        #expect(touching[blocks.c.id] == nil)
    }

    @Test func coveredBlocksAreListed() {
        let blocks = MarkBlocks()
        let (nav, _) = navigator(blocks.all)
        #expect(nav.covered(from: NotePosition(blocks.a.id, 2), to: NotePosition(blocks.b.id, 1)) == [blocks.a.id, blocks.image.id, blocks.b.id])
    }

    @Test func aSpanAcrossTwoFieldsOfOneBlockWashesIt() {
        let blocks = MarkBlocks()
        let (nav, _) = navigator(blocks.all)
        #expect(nav.marks(from: NotePosition(blocks.b.id, 4, field: .caption), to: NotePosition(blocks.b.id, 1)) { _ in 6 } == [blocks.b.id: .wash])
    }

    @Test func aCaptionSpanPaintsTheCaption() {
        let blocks = MarkBlocks()
        let (nav, _) = navigator(blocks.all)
        let marks = nav.marks(from: NotePosition(blocks.b.id, 5, field: .caption), to: NotePosition(blocks.b.id, 2, field: .caption)) { _ in 6 }
        #expect(marks == [blocks.b.id: .field(.caption, 2..<5)])
        #expect(marks[blocks.b.id]?.highlight?.field == .caption)
    }

    @Test func aCaptionStartNeverPaintsItsOffsetsOntoTheBody() {
        let blocks = MarkBlocks()
        let (nav, layout) = navigator(blocks.all)
        let marks = nav.marks(from: NotePosition(blocks.a.id, 3, field: .caption), to: NotePosition(blocks.b.id, 2)) { layout.length(of: NotePosition($0, 0)) }
        #expect(marks[blocks.a.id] == .wash)
        #expect(marks[blocks.b.id] == .text(0..<2))
    }

    @MainActor struct Words {
        let a = Block(text: "one two three"), b = Block(text: "four five")
    }

    func wordRange() -> (NoteSelectionNavigator, Words, Range<Int>) {
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

    @MainActor struct Vertical {
        let a = Block(text: "abcdefghijklmnopqrstuvwxy"), divider = Block(role: .decoration)
        let b = Block(text: "short"), image = Block(role: .object), c = Block(text: "last block")
        var all: [Block] { [a, divider, b, image, c] }
    }

    let vertical = Vertical()

    func landing(from position: NotePosition, up: Bool, x: CGFloat) -> NoteSelectionLanding? {
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

    @MainActor
    final class CaptionLayout: NoteSelectionLayout {
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

    @MainActor struct Horizontal {
        let a = Block(text: "one two"), image = Block(role: .object), b = Block(text: "three four")
        var all: [Block] { [a, image, b] }
    }

    let horizontal = Horizontal()

    func horizontalLanding(_ position: NotePosition, forward: Bool) -> NoteSelectionLanding? {
        let (nav, layout) = navigator(horizontal.all)
        return nav.horizontalLanding(from: position, forward: forward, unit: .character, layout: layout)
    }

    func horizontalHead(_ position: NotePosition, forward: Bool, unit: NoteSelectionHorizontalUnit) -> NotePosition {
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

    @MainActor struct Paragraphs {
        let a = Block(text: "line one\nline two"), image = Block(role: .object), b = Block(text: "alpha\nbeta")
        var all: [Block] { [image, a, b] }
    }

    let paragraphs = Paragraphs()

    func paragraphHead(_ position: NotePosition, forward: Bool) -> NotePosition {
        let (nav, layout) = navigator(paragraphs.all)
        return nav.paragraphHead(from: position, forward: forward, layout: layout)
    }

    @Test func toParagraphEnd() {
        #expect(paragraphHead(NotePosition(paragraphs.a.id, 2), forward: true) == NotePosition(paragraphs.a.id, 8))
    }

    @Test func toTheNextParagraphEnd() {
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

    @MainActor struct Stepping {
        let a = Block(text: "a"), parent = Block(text: "parent")
        let child1: Block, child2: Block, columns = Block(role: .layout)
        let left: Block, inLeft: Block, right: Block, inRight: Block
        let z = Block(text: "z")

        init() {
            child1 = Block(text: "c1", depth: 1, parent: parent.id)
            child2 = Block(text: "c2", depth: 1, parent: parent.id)
            left = Block(role: .column, depth: 1, parent: columns.id)
            inLeft = Block(text: "left", depth: 2, parent: left.id)
            right = Block(role: .column, depth: 1, parent: columns.id)
            inRight = Block(text: "right", depth: 2, parent: right.id)
        }

        var all: [Block] { [a, parent, child1, child2, columns, left, inLeft, right, inRight, z] }
    }

    let stepping = Stepping()

    func step(from ids: [NoteBlockID], forward: Bool) -> NoteBlockID? {
        navigator(stepping.all).0.step(from: ids, forward: forward)
    }

    @Test func downGoesToTheNextBlock() {
        #expect(step(from: [stepping.a.id], forward: true) == stepping.parent.id)
    }

    @Test func downSkipsASelectedParentsChildrenAndLayoutContainers() {
        #expect(step(from: [stepping.parent.id], forward: true) == stepping.inLeft.id)
    }

    @Test func upStepsIntoSiblings() {
        #expect(step(from: [stepping.child2.id], forward: false) == stepping.child1.id)
    }

    @Test func upFromBelowColumnsLandsInTheLastColumn() {
        #expect(step(from: [stepping.z.id], forward: false) == stepping.inRight.id)
    }

    @Test func downAtTheEndStays() {
        #expect(step(from: [stepping.z.id], forward: true) == stepping.z.id)
    }

    @Test func upAtTheStartStays() {
        #expect(step(from: [stepping.a.id], forward: false) == stepping.a.id)
    }

    @Test func downFromAMultiSelectionGoesPastTheLastBlock() {
        #expect(step(from: [stepping.a.id, stepping.child1.id], forward: true) == stepping.child2.id)
    }

    @Test func upFromAMultiSelectionAtTheStartStaysOnTheFirst() {
        #expect(step(from: [stepping.a.id, stepping.child1.id], forward: false) == stepping.a.id)
    }

    @MainActor struct Extension {
        let a = Block(text: "a"), parent = Block(text: "parent")
        let child1: Block, child2: Block
        let x = Block(text: "x")

        init() {
            child1 = Block(text: "c1", depth: 1, parent: parent.id)
            child2 = Block(text: "c2", depth: 1, parent: parent.id)
        }

        var all: [Block] { [a, parent, child1, child2, x] }
    }

    let extending = Extension()

    func extend(_ range: NoteBlockRange, _ steps: [Bool]) -> NoteBlockRange {
        let nav = navigator(extending.all).0
        return steps.reduce(range) { nav.extend($0, forward: $1) }
    }

    func covering(_ range: NoteBlockRange) -> [NoteBlockID] {
        navigator(extending.all).0.blocks(from: range.anchor, to: range.head)
    }

    @Test func extendDown() {
        let range = extend(NoteBlockRange(anchor: extending.a.id, head: extending.a.id), [true])
        #expect(range.head == extending.parent.id)
        #expect(covering(range) == [extending.a.id, extending.parent.id])
    }

    @Test func extendingDownSkipsTheParentsChildren() {
        #expect(extend(NoteBlockRange(anchor: extending.a.id, head: extending.a.id), [true, true]).head == extending.x.id)
    }

    @Test func shrinkingUpReturnsToTheParentNotItsLastChild() {
        #expect(extend(NoteBlockRange(anchor: extending.a.id, head: extending.a.id), [true, true, false]).head == extending.parent.id)
    }

    @Test func shrinkBackToTheAnchor() {
        let range = extend(NoteBlockRange(anchor: extending.a.id, head: extending.a.id), [true, true, false, false])
        #expect(range.head == extending.a.id)
        #expect(covering(range) == [extending.a.id])
    }

    @Test func extendUpIntoChildren() {
        let range = extend(NoteBlockRange(anchor: extending.x.id, head: extending.x.id), [false])
        #expect(range.head == extending.child2.id)
        #expect(covering(range) == [extending.child2.id, extending.x.id])
    }

    @Test func reachingTheParentFoldsChildrenIn() {
        let range = extend(NoteBlockRange(anchor: extending.x.id, head: extending.x.id), [false, false, false])
        #expect(range.head == extending.parent.id)
        #expect(covering(range) == [extending.parent.id, extending.x.id])
    }

    @Test func shrinkingDownSkipsTheParentsChildren() {
        #expect(extend(NoteBlockRange(anchor: extending.x.id, head: extending.x.id), [false, false, false, true]).head == extending.x.id)
    }

    @Test func shrinkingStopsAtANestedAnchor() {
        let nested = NoteBlockRange(anchor: extending.child1.id, head: extending.x.id)
        #expect(extend(nested, [false]).head == extending.child1.id)
    }

    @Test func extendingPastTheStartDoesNothing() {
        let edge = NoteBlockRange(anchor: extending.a.id, head: extending.a.id)
        #expect(extend(edge, [false]) == edge)
    }

    @MainActor struct Layouts {
        let a = Block(text: "a"), columns = Block(role: .layout)
        let left: Block, inLeft: Block, right: Block, inRight: Block
        let z = Block(text: "z")

        init() {
            left = Block(role: .column, depth: 1, parent: columns.id)
            inLeft = Block(text: "left", depth: 2, parent: left.id)
            right = Block(role: .column, depth: 1, parent: columns.id)
            inRight = Block(text: "right", depth: 2, parent: right.id)
        }

        var all: [Block] { [a, columns, left, inLeft, right, inRight, z] }
    }

    let layouts = Layouts()

    @Test func aRangeCoveringEveryColumnPicksTheColumnList() {
        #expect(navigator(layouts.all).0.blocks(from: layouts.a.id, to: layouts.z.id) == [layouts.a.id, layouts.columns.id, layouts.z.id])
    }

    @Test func aPartialRangeKeepsBlocksNeverALoneColumn() {
        #expect(navigator(layouts.all).0.blocks(from: layouts.inRight.id, to: layouts.z.id) == [layouts.inRight.id, layouts.z.id])
    }

    @Test func coveringEveryColumnsBlocksPicksTheColumnList() {
        #expect(navigator(layouts.all).0.blocks(from: layouts.inLeft.id, to: layouts.inRight.id) == [layouts.columns.id])
    }

    @Test func aColumnAloneIsNeverSelected() {
        #expect(navigator(layouts.all).0.normalized([layouts.left.id]) == [])
    }

    @Test func expandedWalksTheSubtree() {
        #expect(navigator(layouts.all).0.expanded([layouts.columns.id])
                == [layouts.columns.id, layouts.left.id, layouts.inLeft.id, layouts.right.id, layouts.inRight.id])
    }

    @Test func topLevelListsOnlyTopLevelBlocks() {
        #expect(navigator(layouts.all).0.topLevel == [layouts.a.id, layouts.columns.id, layouts.z.id])
    }

    func toggle(_ id: NoteBlockID, in ids: [NoteBlockID]) -> [NoteBlockID] {
        navigator(extending.all).0.toggling(id, in: ids)
    }

    @Test func commandClickAdds() {
        #expect(toggle(extending.x.id, in: [extending.a.id]) == [extending.a.id, extending.x.id])
    }

    @Test func commandClickRemoves() {
        #expect(toggle(extending.a.id, in: [extending.a.id, extending.x.id]) == [extending.x.id])
    }

    @Test func commandClickOnAChildOfASelectedParentKeepsItsSiblings() {
        #expect(toggle(extending.child1.id, in: [extending.parent.id]) == [extending.child2.id])
    }

    @Test func childrenStayChildrenWithoutTheirParent() {
        #expect(toggle(extending.child1.id, in: [extending.child2.id]) == [extending.child1.id, extending.child2.id])
    }

    @MainActor struct Marquee {
        let a = Block(text: "a"), parent = Block(text: "parent")
        let child: Block
        let x = Block(text: "x")
        let nav: NoteSelectionNavigator
        let layout: NoteEditorFakeSelectionLayout

        init() {
            child = Block(text: "child", depth: 1, parent: parent.id, x: 26)
            layout = NoteEditorFakeSelectionLayout([a, parent, child, x])
            let parentFrame = layout.items[1].frame, childFrame = layout.items[2].frame
            layout.setFrame(1, CGRect(x: parentFrame.minX, y: parentFrame.minY, width: parentFrame.width, height: childFrame.maxY - parentFrame.minY))
            nav = NoteSelectionNavigator(items: layout.items)
        }

        var parentFrame: CGRect { layout.items[1].frame }
        var childFrame: CGRect { layout.items[2].frame }
    }

    @Test func aParentsOwnRowStopsAtItsFirstChild() {
        let marquee = Marquee()
        #expect(marquee.nav.ownFrame(at: 1).height == marquee.childFrame.minY - marquee.parentFrame.minY)
    }

    @Test func aMarqueeOverTheChildRowPicksTheChildOnly() {
        let marquee = Marquee()
        #expect(marquee.nav.marquee(CGRect(x: 100, y: marquee.childFrame.midY, width: 20, height: 1)) == [marquee.child.id])
    }

    @Test func touchingTheParentRowSelectsTheParentWithItsChildren() {
        let marquee = Marquee()
        let both = CGRect(x: 100, y: marquee.parentFrame.midY - 5, width: 20, height: marquee.childFrame.minY - marquee.parentFrame.midY + 10)
        #expect(marquee.nav.marquee(both) == [marquee.parent.id])
    }

    @Test func aMarginRectangleAloneTouchesNothing() {
        let marquee = Marquee()
        #expect(marquee.nav.marquee(CGRect(x: -80, y: 0, width: 30, height: marquee.layout.items[1].frame.minY + 2)) == [])
    }

    @Test func aMarginRectangleSelectsTheRowsBesideIt() {
        let marquee = Marquee()
        let rect = CGRect(x: -80, y: 0, width: 30, height: marquee.layout.items[1].frame.minY + 2)
        #expect(marquee.nav.marquee(rect, column: 0...400) == [marquee.a.id, marquee.parent.id])
    }

    @MainActor struct SelectAll {
        let a = Block(text: "hello"), empty = Block(text: ""), parent = Block(text: "p")
        let child: Block
        let nav: NoteSelectionNavigator
        let layout: NoteEditorFakeSelectionLayout

        init() {
            child = Block(text: "c", depth: 1, parent: parent.id)
            layout = NoteEditorFakeSelectionLayout([a, empty, parent, child])
            nav = NoteSelectionNavigator(items: layout.items)
        }

        var everything: NotePageSelection { .blocks([a.id, empty.id, parent.id]) }
    }

    @Test func theFirstSelectAllPressSelectsTheBlocksText() {
        let all = SelectAll()
        #expect(all.nav.selectAllStep(.caret(NotePosition(all.a.id, 2)), layout: all.layout)
                == .text(anchor: NotePosition(all.a.id, 0), head: NotePosition(all.a.id, 5)))
    }

    @Test func theSecondPressSelectsTheBlock() {
        let all = SelectAll()
        let first = all.nav.selectAllStep(.caret(NotePosition(all.a.id, 2)), layout: all.layout)
        #expect(all.nav.selectAllStep(first, layout: all.layout) == .blocks([all.a.id]))
    }

    @Test func theThirdPressSelectsEveryBlock() {
        let all = SelectAll()
        #expect(all.nav.selectAllStep(.blocks([all.a.id]), layout: all.layout) == all.everything)
    }

    @Test func allStaysAll() {
        let all = SelectAll()
        #expect(all.nav.selectAllStep(all.everything, layout: all.layout) == all.everything)
    }

    @Test func anEmptyBlockSkipsStraightToTheBlock() {
        let all = SelectAll()
        #expect(all.nav.selectAllStep(.caret(NotePosition(all.empty.id, 0)), layout: all.layout) == .blocks([all.empty.id]))
    }

    @Test func aCrossBlockSelectionJumpsToEveryBlock() {
        let all = SelectAll()
        let cross = NotePageSelection.text(anchor: NotePosition(all.a.id, 1), head: NotePosition(all.child.id, 1))
        #expect(all.nav.selectAllStep(cross, layout: all.layout) == all.everything)
    }

    @Test func nothingSelectedSelectsEverything() {
        let all = SelectAll()
        #expect(all.nav.selectAllStep(.none, layout: all.layout) == all.everything)
    }

    @Test func captionsSelectTheirOwnText() {
        let all = SelectAll()
        #expect(all.nav.selectAllStep(.caret(NotePosition(all.a.id, 1, field: .caption)), layout: all.layout)
                == .text(anchor: NotePosition(all.a.id, 0, field: .caption), head: NotePosition(all.a.id, 5, field: .caption)))
    }

    @MainActor struct Escape {
        let a = Block(text: "hello"), image = Block(role: .object), b = Block(text: "world")
        var nav: NoteSelectionNavigator { NoteSelectionNavigator(items: NoteEditorFakeSelectionLayout([a, image, b]).items) }
    }

    @Test func escapeFromACaretSelectsTheBlock() {
        let escape = Escape()
        #expect(escape.nav.escapeStep(.caret(NotePosition(escape.b.id, 2))) == .blocks([escape.b.id]))
    }

    @Test func escapeFromACrossBlockSelectionSelectsTheCoveredBlocks() {
        let escape = Escape()
        #expect(escape.nav.escapeStep(.text(anchor: NotePosition(escape.a.id, 1), head: NotePosition(escape.b.id, 2)))
                == .blocks([escape.a.id, escape.image.id, escape.b.id]))
    }

    @Test func escapeClearsABlockSelection() {
        let escape = Escape()
        #expect(escape.nav.escapeStep(.blocks([escape.a.id])) == .none)
    }

    @Test func escapeFromCellsSelectsTheTable() {
        let table = NoteBlockID()
        #expect(Escape().nav.escapeStep(.cells(table: table, anchor: NoteTableCell(row: 0, column: 0), head: NoteTableCell(row: 1, column: 1))) == .blocks([table]))
    }

    @MainActor struct Drag {
        let a = Block(text: "hello"), divider = Block(role: .decoration), b = Block(text: "world"), image = Block(role: .object)
        let layout: NoteEditorFakeSelectionLayout
        let nav: NoteSelectionNavigator

        init() {
            layout = NoteEditorFakeSelectionLayout([a, divider, b, image])
            nav = NoteSelectionNavigator(items: layout.items)
        }

        func target(anchor: NoteBlockID, pointer index: Int?, outsideColumn: Bool = false) -> NoteSelectionDragTarget {
            nav.dragTarget(anchor: anchor, pointer: index.map { layout.items[$0] }, outsideColumn: outsideColumn, layout: layout)
        }
    }

    @Test func textStaysText() {
        let drag = Drag()
        #expect(drag.target(anchor: drag.a.id, pointer: 2) == .text(drag.b.id))
    }

    @Test func aDividerMapsForwardToTheNextTextStart() {
        let drag = Drag()
        #expect(drag.target(anchor: drag.a.id, pointer: 1) == .position(NotePosition(drag.b.id, 0)))
    }

    @Test func aDividerMapsBackwardToThePreviousTextEnd() {
        let drag = Drag()
        #expect(drag.target(anchor: drag.b.id, pointer: 1) == .position(NotePosition(drag.a.id, 5)))
    }

    @Test func draggingOntoAnImageSwitchesToBlocks() {
        let drag = Drag()
        #expect(drag.target(anchor: drag.a.id, pointer: 3) == .blocks([drag.a.id, drag.divider.id, drag.b.id, drag.image.id]))
    }

    @Test func leavingTheColumnSwitchesToBlocks() {
        let drag = Drag()
        #expect(drag.target(anchor: drag.a.id, pointer: 2, outsideColumn: true) == .blocks([drag.a.id, drag.divider.id, drag.b.id]))
    }

    @Test func noPointerKeepsTheAnchor() {
        let drag = Drag()
        #expect(drag.target(anchor: drag.a.id, pointer: nil) == .text(drag.a.id))
    }

    func nearest(_ point: CGPoint) -> (NoteBlockID?, NoteEditorFakeSelectionLayout.Block, NoteEditorFakeSelectionLayout.Block, CGFloat) {
        let first = Block(text: "hello"), second = Block(text: "world")
        let layout = NoteEditorFakeSelectionLayout([first, second])
        let nav = NoteSelectionNavigator(items: layout.items)
        let probe = point.y == 0 ? CGPoint(x: point.x, y: layout.items[1].frame.midY) : point
        return (nav.nearestItem(to: probe)?.id, first, second, 0)
    }

    @Test func aboveThePagePicksTheFirstBlock() {
        let result = nearest(CGPoint(x: 50, y: -40))
        #expect(result.0 == result.1.id)
    }

    @Test func belowThePagePicksTheLastBlock() {
        let result = nearest(CGPoint(x: 50, y: 900))
        #expect(result.0 == result.2.id)
    }

    @Test func theMarginPicksTheRowBesideIt() {
        let result = nearest(CGPoint(x: 900, y: 0))
        #expect(result.0 == result.2.id)
    }

    @Test(arguments: [(1, "1 block selected"), (3, "3 blocks selected")])
    func announcementsReadNaturally(count: Int, text: String) {
        #expect(NoteSelectionAnnouncement.blocks(count) == text)
    }
}
