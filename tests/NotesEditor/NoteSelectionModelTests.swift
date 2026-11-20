import CoreGraphics
import Foundation

@MainActor
final class FakeSelectionLayout: NoteSelectionLayout {
    struct Block {
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

@main @MainActor
struct NoteSelectionModelTests {
    static func expect(_ value: Bool, _ message: String, line: UInt = #line) {
        if !value { failTest(message, line: line) }
    }

    typealias Block = FakeSelectionLayout.Block

    static func main() {
        ordering()
        marks()
        granularity()
        goalColumn()
        verticalNavigation()
        horizontalNavigation()
        paragraphAndDocument()
        blockStepping()
        blockExtension()
        rangesAndLayouts()
        toggling()
        marquee()
        selectAll()
        escape()
        dragTargets()
        nearest()
        announcements()
        print("NoteSelectionModelTests passed")
    }

    static func ordering() {
        let a = Block(text: "first"), b = Block(text: "second")
        let layout = FakeSelectionLayout([a, b])
        let nav = NoteSelectionNavigator(items: layout.items)
        expect(nav.precedes(NotePosition(a.id, 4), NotePosition(b.id, 0)), "earlier block precedes")
        expect(!nav.precedes(NotePosition(b.id, 0), NotePosition(a.id, 4)), "later block follows")
        expect(nav.precedes(NotePosition(a.id, 1), NotePosition(a.id, 2)), "same block compares offsets")
        let ends = nav.ordered(NotePosition(b.id, 2), NotePosition(a.id, 3))
        expect(ends.start == NotePosition(a.id, 3) && ends.end == NotePosition(b.id, 2), "ordered swaps backward ends")
    }

    static func marks() {
        let a = Block(text: "hello there"), image = Block(role: .object), divider = Block(role: .decoration)
        let b = Block(text: "middle"), c = Block(text: "the end")
        let layout = FakeSelectionLayout([a, image, b, divider, c])
        let nav = NoteSelectionNavigator(items: layout.items)
        let marks = nav.marks(from: NotePosition(c.id, 3), to: NotePosition(a.id, 6)) { layout.length(of: NotePosition($0, 0)) }
        expect(marks[a.id] == .text(6..<11), "anchor block highlights its tail")
        expect(marks[image.id] == .wash && marks[divider.id] == .wash, "objects in the middle get the wash")
        expect(marks[b.id] == .text(0..<6), "middle text is fully highlighted")
        expect(marks[c.id] == .text(0..<3), "head block highlights its start")
        let single = nav.marks(from: NotePosition(b.id, 4), to: NotePosition(b.id, 1)) { _ in 0 }
        expect(single == [b.id: .text(1..<4)], "single block range is ordered")
        expect(nav.marks(from: NotePosition(b.id, 2), to: NotePosition(b.id, 2)) { _ in 0 }.isEmpty, "a caret draws nothing")
        let touching = nav.marks(from: NotePosition(a.id, 11), to: NotePosition(c.id, 0)) { layout.length(of: NotePosition($0, 0)) }
        expect(touching[a.id] == .text(11..<11) && touching[c.id] == nil, "the start keeps its line end and a touched end block draws nothing")
        expect(nav.covered(from: NotePosition(a.id, 2), to: NotePosition(b.id, 1)) == [a.id, image.id, b.id], "covered blocks")
    }

    static func granularity() {
        let a = Block(text: "one two three"), b = Block(text: "four five")
        let layout = FakeSelectionLayout([a, b])
        let nav = NoteSelectionNavigator(items: layout.items)
        let word = nav.granularRange(at: NotePosition(a.id, 5), granularity: .word, layout: layout)
        expect(word == 4..<7, "word range")
        let down = nav.span(anchor: a.id, anchorRange: word, head: b.id, headRange: 5..<9)
        expect(down.anchor == NotePosition(a.id, 4) && down.head == NotePosition(b.id, 9), "forward word span")
        let up = nav.span(anchor: b.id, anchorRange: 5..<9, head: a.id, headRange: word)
        expect(up.anchor == NotePosition(b.id, 9) && up.head == NotePosition(a.id, 4), "backward word span")
        let same = nav.span(anchor: a.id, anchorRange: 4..<7, head: a.id, headRange: 4..<7)
        expect(same.anchor == NotePosition(a.id, 4) && same.head == NotePosition(a.id, 7), "same word keeps the word")
        let back = nav.span(anchor: a.id, anchorRange: 4..<7, head: a.id, headRange: 0..<3)
        expect(back.anchor == NotePosition(a.id, 7) && back.head == NotePosition(a.id, 0), "same block backward word span")
        let paragraph = nav.granularRange(at: NotePosition(b.id, 2), granularity: .paragraph, layout: layout)
        expect(paragraph == 0..<9, "paragraph granularity is the whole block")
    }

    static func goalColumn() {
        var goal = NoteGoalColumn()
        let id = NoteBlockID()
        var calls = 0
        let first = goal.value(for: NotePosition(id, 3)) { calls += 1; return 30 }
        expect(first == 30 && calls == 1, "goal starts at the caret x")
        goal.moved(to: NotePosition(id, 13))
        let second = goal.value(for: NotePosition(id, 13)) { calls += 1; return 99 }
        expect(second == 30 && calls == 1, "goal survives a vertical move")
        let third = goal.value(for: NotePosition(id, 5)) { calls += 1; return 50 }
        expect(third == 50 && calls == 2, "goal resets after the caret moved elsewhere")
        goal.reset()
        expect(goal.x == nil && goal.head == nil, "reset clears the goal")
    }

    static func verticalNavigation() {
        let a = Block(text: "abcdefghijklmnopqrstuvwxy"), divider = Block(role: .decoration)
        let b = Block(text: "short"), image = Block(role: .object), c = Block(text: "last block")
        let layout = FakeSelectionLayout([a, divider, b, image, c])
        let nav = NoteSelectionNavigator(items: layout.items)
        let inside = nav.verticalLanding(from: NotePosition(a.id, 3), up: false, x: 30, layout: layout)
        expect(inside == .caret(NotePosition(a.id, 13)), "down inside a block keeps the column")
        let cross = nav.verticalLanding(from: NotePosition(a.id, 23), up: false, x: 30, layout: layout)
        expect(cross == .caret(NotePosition(b.id, 3)), "down from the last line skips the divider and keeps x")
        let clamp = nav.verticalLanding(from: NotePosition(a.id, 29 - 4), up: false, x: 90, layout: layout)
        expect(clamp == .caret(NotePosition(b.id, 5)), "goal x past the line end clamps to the end")
        let object = nav.verticalLanding(from: NotePosition(b.id, 2), up: false, x: 20, layout: layout)
        expect(object == .block(image.id), "down into an image selects it")
        let upward = nav.verticalLanding(from: NotePosition(b.id, 2), up: true, x: 20, layout: layout)
        expect(upward == .caret(NotePosition(a.id, 22)), "up enters the previous block's last line")
        let top = nav.verticalLanding(from: NotePosition(a.id, 4), up: true, x: 40, layout: layout)
        expect(top == .caret(NotePosition(a.id, 0)), "up on the first line of the page goes to the start")
        let bottom = nav.verticalLanding(from: NotePosition(c.id, 2), up: false, x: 20, layout: layout)
        expect(bottom == .caret(NotePosition(c.id, 10)), "down on the last line of the page goes to the end")
        let extended = nav.verticalHead(from: NotePosition(b.id, 2), up: false, x: 20, layout: layout)
        expect(extended == NotePosition(c.id, 2), "extending skips over the image into text")
        let caption = nav.verticalLanding(from: NotePosition(image.id, 0, field: .caption), up: true, x: 0, layout: CaptionLayout())
        expect(caption == .block(image.id), "up from a caption selects its block")
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

    static func horizontalNavigation() {
        let a = Block(text: "one two"), image = Block(role: .object), b = Block(text: "three four")
        let layout = FakeSelectionLayout([a, image, b])
        let nav = NoteSelectionNavigator(items: layout.items)
        expect(nav.horizontalLanding(from: NotePosition(a.id, 7), forward: true, unit: .character, layout: layout) == .block(image.id),
               "right at the end lands on an image as a block")
        expect(nav.horizontalLanding(from: NotePosition(b.id, 0), forward: false, unit: .character, layout: layout) == .block(image.id),
               "left at the start lands on an image as a block")
        expect(nav.horizontalLanding(from: NotePosition(a.id, 0), forward: false, unit: .character, layout: layout) == nil,
               "left at the page start stays put")
        expect(nav.horizontalHead(from: NotePosition(a.id, 7), forward: true, unit: .character, layout: layout) == NotePosition(b.id, 0),
               "shift-right crosses into the next text block")
        expect(nav.horizontalHead(from: NotePosition(a.id, 7), forward: true, unit: .word, layout: layout) == NotePosition(b.id, 5),
               "shift-option-right crosses and takes the next word")
        expect(nav.horizontalHead(from: NotePosition(b.id, 0), forward: false, unit: .word, layout: layout) == NotePosition(a.id, 4),
               "shift-option-left crosses back and takes the previous word")
        expect(nav.horizontalHead(from: NotePosition(b.id, 10), forward: true, unit: .character, layout: layout) == NotePosition(b.id, 10),
               "extending past the page end stays put")
        expect(nav.horizontalHead(from: NotePosition(b.id, 3), forward: true, unit: .word, layout: layout) == NotePosition(b.id, 5),
               "word step inside a block")
    }

    static func paragraphAndDocument() {
        let a = Block(text: "line one\nline two"), image = Block(role: .object), b = Block(text: "alpha\nbeta")
        let layout = FakeSelectionLayout([image, a, b])
        let nav = NoteSelectionNavigator(items: layout.items)
        expect(nav.paragraphHead(from: NotePosition(a.id, 2), forward: true, layout: layout) == NotePosition(a.id, 8), "to paragraph end")
        expect(nav.paragraphHead(from: NotePosition(a.id, 8), forward: true, layout: layout) == NotePosition(a.id, 17), "to next paragraph end")
        expect(nav.paragraphHead(from: NotePosition(a.id, 17), forward: true, layout: layout) == NotePosition(b.id, 5),
               "crosses to the next block's first paragraph end")
        expect(nav.paragraphHead(from: NotePosition(b.id, 0), forward: false, layout: layout) == NotePosition(a.id, 9),
               "crosses back to the previous block's last paragraph start")
        expect(nav.documentStart == NotePosition(a.id, 0), "document start skips the leading image")
        expect(nav.documentEnd(layout) == NotePosition(b.id, 10), "document end is the last text end")
    }

    static func blockStepping() {
        let a = Block(text: "a"), parent = Block(text: "parent")
        let child1 = Block(text: "c1", depth: 1, parent: parent.id), child2 = Block(text: "c2", depth: 1, parent: parent.id)
        let columns = Block(role: .layout)
        let left = Block(role: .column, depth: 1, parent: columns.id)
        let inLeft = Block(text: "left", depth: 2, parent: left.id)
        let right = Block(role: .column, depth: 1, parent: columns.id)
        let inRight = Block(text: "right", depth: 2, parent: right.id)
        let z = Block(text: "z")
        let layout = FakeSelectionLayout([a, parent, child1, child2, columns, left, inLeft, right, inRight, z])
        let nav = NoteSelectionNavigator(items: layout.items)
        expect(nav.step(from: [a.id], forward: true) == parent.id, "down to the next block")
        expect(nav.step(from: [parent.id], forward: true) == inLeft.id, "down skips a selected parent's children and layout containers")
        expect(nav.step(from: [child2.id], forward: false) == child1.id, "up steps into siblings")
        expect(nav.step(from: [z.id], forward: false) == inRight.id, "up from below columns lands in the last column")
        expect(nav.step(from: [z.id], forward: true) == z.id, "down at the end stays")
        expect(nav.step(from: [a.id], forward: false) == a.id, "up at the start stays")
        expect(nav.step(from: [a.id, child1.id], forward: true) == child2.id, "down from a multi selection goes past the last block")
        expect(nav.step(from: [a.id, child1.id], forward: false) == a.id, "up from a multi selection at the start stays on the first")
    }

    static func blockExtension() {
        let a = Block(text: "a"), parent = Block(text: "parent")
        let child1 = Block(text: "c1", depth: 1, parent: parent.id), child2 = Block(text: "c2", depth: 1, parent: parent.id)
        let x = Block(text: "x")
        let layout = FakeSelectionLayout([a, parent, child1, child2, x])
        let nav = NoteSelectionNavigator(items: layout.items)
        var range = NoteBlockRange(anchor: a.id, head: a.id)
        range = nav.extend(range, forward: true)
        expect(range.head == parent.id && nav.blocks(from: range.anchor, to: range.head) == [a.id, parent.id], "extend down")
        range = nav.extend(range, forward: true)
        expect(range.head == x.id, "extending down skips the parent's children")
        range = nav.extend(range, forward: false)
        expect(range.head == parent.id, "shrinking up returns to the parent, not its last child")
        range = nav.extend(range, forward: false)
        expect(range.head == a.id && nav.blocks(from: range.anchor, to: range.head) == [a.id], "shrink back to the anchor")
        var upward = NoteBlockRange(anchor: x.id, head: x.id)
        upward = nav.extend(upward, forward: false)
        expect(upward.head == child2.id && nav.blocks(from: upward.anchor, to: upward.head) == [child2.id, x.id], "extend up into children")
        upward = nav.extend(upward, forward: false)
        upward = nav.extend(upward, forward: false)
        expect(upward.head == parent.id && nav.blocks(from: upward.anchor, to: upward.head) == [parent.id, x.id], "reaching the parent folds children in")
        upward = nav.extend(upward, forward: true)
        expect(upward.head == x.id, "shrinking down skips the parent's children")
        let nested = NoteBlockRange(anchor: child1.id, head: x.id)
        expect(nav.extend(nested, forward: false).head == child1.id, "shrinking stops at a nested anchor")
        let edge = NoteBlockRange(anchor: a.id, head: a.id)
        expect(nav.extend(edge, forward: false) == edge, "extending past the start does nothing")
    }

    static func rangesAndLayouts() {
        let a = Block(text: "a"), columns = Block(role: .layout)
        let left = Block(role: .column, depth: 1, parent: columns.id)
        let inLeft = Block(text: "left", depth: 2, parent: left.id)
        let right = Block(role: .column, depth: 1, parent: columns.id)
        let inRight = Block(text: "right", depth: 2, parent: right.id)
        let z = Block(text: "z")
        let layout = FakeSelectionLayout([a, columns, left, inLeft, right, inRight, z])
        let nav = NoteSelectionNavigator(items: layout.items)
        expect(nav.blocks(from: a.id, to: z.id) == [a.id, columns.id, z.id], "a range covering every column picks the column list")
        expect(nav.blocks(from: inRight.id, to: z.id) == [inRight.id, z.id], "a partial range keeps blocks, never a lone column")
        expect(nav.blocks(from: inLeft.id, to: inRight.id) == [columns.id], "covering every column's blocks picks the column list")
        expect(nav.normalized([left.id]) == [], "a column alone is never selected")
        expect(nav.expanded([columns.id]) == [columns.id, left.id, inLeft.id, right.id, inRight.id], "expanded walks the subtree")
        expect(nav.topLevel == [a.id, columns.id, z.id], "top level")
    }

    static func toggling() {
        let a = Block(text: "a"), parent = Block(text: "parent")
        let child1 = Block(text: "c1", depth: 1, parent: parent.id), child2 = Block(text: "c2", depth: 1, parent: parent.id)
        let x = Block(text: "x")
        let layout = FakeSelectionLayout([a, parent, child1, child2, x])
        let nav = NoteSelectionNavigator(items: layout.items)
        expect(nav.toggling(x.id, in: [a.id]) == [a.id, x.id], "cmd-click adds")
        expect(nav.toggling(a.id, in: [a.id, x.id]) == [x.id], "cmd-click removes")
        expect(nav.toggling(child1.id, in: [parent.id]) == [child2.id], "cmd-click on a child of a selected parent keeps its siblings")
        expect(nav.toggling(child1.id, in: [child2.id]) == [child1.id, child2.id], "children stay children without their parent")
    }

    static func marquee() {
        let a = Block(text: "a"), parent = Block(text: "parent")
        let child = Block(text: "child", depth: 1, parent: parent.id, x: 26)
        let x = Block(text: "x")
        let layout = FakeSelectionLayout([a, parent, child, x])
        let parentFrame = layout.items[1].frame, childFrame = layout.items[2].frame
        layout.setFrame(1, CGRect(x: parentFrame.minX, y: parentFrame.minY, width: parentFrame.width, height: childFrame.maxY - parentFrame.minY))
        let nav = NoteSelectionNavigator(items: layout.items)
        expect(nav.ownFrame(at: 1).height == childFrame.minY - parentFrame.minY, "a parent's own row stops at its first child")
        let childOnly = CGRect(x: 100, y: childFrame.midY, width: 20, height: 1)
        expect(nav.marquee(childOnly) == [child.id], "a marquee over the child row picks the child only")
        let both = CGRect(x: 100, y: parentFrame.midY - 5, width: 20, height: childFrame.minY - parentFrame.midY + 10)
        expect(nav.marquee(both) == [parent.id], "touching the parent row selects the parent with its children")
        let margin = CGRect(x: -80, y: 0, width: 30, height: layout.items[1].frame.minY + 2)
        expect(nav.marquee(margin) == [], "a margin rectangle alone touches nothing")
        expect(nav.marquee(margin, column: 0...400) == [a.id, parent.id], "a margin rectangle selects the rows beside it")
    }

    static func selectAll() {
        let a = Block(text: "hello"), empty = Block(text: ""), parent = Block(text: "p")
        let child = Block(text: "c", depth: 1, parent: parent.id)
        let layout = FakeSelectionLayout([a, empty, parent, child])
        let nav = NoteSelectionNavigator(items: layout.items)
        let all = NotePageSelection.blocks([a.id, empty.id, parent.id])
        let first = nav.selectAllStep(.caret(NotePosition(a.id, 2)), layout: layout)
        expect(first == .text(anchor: NotePosition(a.id, 0), head: NotePosition(a.id, 5)), "first press selects the block's text")
        let second = nav.selectAllStep(first, layout: layout)
        expect(second == .blocks([a.id]), "second press selects the block")
        expect(nav.selectAllStep(second, layout: layout) == all, "third press selects every block")
        expect(nav.selectAllStep(all, layout: layout) == all, "all stays all")
        expect(nav.selectAllStep(.caret(NotePosition(empty.id, 0)), layout: layout) == .blocks([empty.id]), "an empty block skips straight to the block")
        let cross = NotePageSelection.text(anchor: NotePosition(a.id, 1), head: NotePosition(child.id, 1))
        expect(nav.selectAllStep(cross, layout: layout) == all, "a cross-block selection jumps to every block")
        expect(nav.selectAllStep(.none, layout: layout) == all, "nothing selected selects everything")
        let caption = nav.selectAllStep(.caret(NotePosition(a.id, 1, field: .caption)), layout: layout)
        expect(caption == .text(anchor: NotePosition(a.id, 0, field: .caption), head: NotePosition(a.id, 5, field: .caption)), "captions select their own text")
    }

    static func escape() {
        let a = Block(text: "hello"), image = Block(role: .object), b = Block(text: "world")
        let layout = FakeSelectionLayout([a, image, b])
        let nav = NoteSelectionNavigator(items: layout.items)
        expect(nav.escapeStep(.caret(NotePosition(b.id, 2))) == .blocks([b.id]), "escape from a caret selects the block")
        expect(nav.escapeStep(.text(anchor: NotePosition(a.id, 1), head: NotePosition(b.id, 2))) == .blocks([a.id, image.id, b.id]),
               "escape from a cross-block selection selects the covered blocks")
        expect(nav.escapeStep(.blocks([a.id])) == .none, "escape clears a block selection")
        let table = NoteBlockID()
        expect(nav.escapeStep(.cells(table: table, anchor: NoteTableCell(row: 0, column: 0), head: NoteTableCell(row: 1, column: 1))) == .blocks([table]),
               "escape from cells selects the table")
    }

    static func dragTargets() {
        let a = Block(text: "hello"), divider = Block(role: .decoration), b = Block(text: "world"), image = Block(role: .object)
        let layout = FakeSelectionLayout([a, divider, b, image])
        let nav = NoteSelectionNavigator(items: layout.items)
        let items = layout.items
        expect(nav.dragTarget(anchor: a.id, pointer: items[2], outsideColumn: false, layout: layout) == .text(b.id), "text stays text")
        expect(nav.dragTarget(anchor: a.id, pointer: items[1], outsideColumn: false, layout: layout) == .position(NotePosition(b.id, 0)),
               "a divider maps forward to the next text start")
        expect(nav.dragTarget(anchor: b.id, pointer: items[1], outsideColumn: false, layout: layout) == .position(NotePosition(a.id, 5)),
               "a divider maps backward to the previous text end")
        expect(nav.dragTarget(anchor: a.id, pointer: items[3], outsideColumn: false, layout: layout) == .blocks([a.id, divider.id, b.id, image.id]),
               "dragging onto an image switches to blocks")
        expect(nav.dragTarget(anchor: a.id, pointer: items[2], outsideColumn: true, layout: layout) == .blocks([a.id, divider.id, b.id]),
               "leaving the column switches to blocks")
        expect(nav.dragTarget(anchor: a.id, pointer: nil, outsideColumn: false, layout: layout) == .text(a.id), "no pointer keeps the anchor")
    }

    static func nearest() {
        let a = Block(text: "hello"), b = Block(text: "world")
        let layout = FakeSelectionLayout([a, b])
        let nav = NoteSelectionNavigator(items: layout.items)
        expect(nav.nearestItem(to: CGPoint(x: 50, y: -40))?.id == a.id, "above the page picks the first block")
        expect(nav.nearestItem(to: CGPoint(x: 50, y: 900))?.id == b.id, "below the page picks the last block")
        expect(nav.nearestItem(to: CGPoint(x: 900, y: layout.items[1].frame.midY))?.id == b.id, "the margin picks the row beside it")
    }

    static func announcements() {
        expect(NoteSelectionAnnouncement.blocks(1) == "1 block selected", "singular")
        expect(NoteSelectionAnnouncement.blocks(3) == "3 blocks selected", "plural")
    }
}
