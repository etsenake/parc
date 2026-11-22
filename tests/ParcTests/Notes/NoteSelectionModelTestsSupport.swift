import CoreGraphics
import Foundation
import Testing
@testable import ParcCore
@testable import ParcNotes

enum NoteSelectionModelTestsSupport {
    @MainActor
    final class Layout: NoteSelectionLayout {
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
}
