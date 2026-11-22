import Foundation
import Testing
@testable import ParcCore

@MainActor struct PageStructurePageIndexTests: NoteFixtures {
    private func bigPage() -> [NoteBlock] {
        var blocks: [NoteBlock] = []
        for index in 0..<2000 {
            switch index % 10 {
            case 3: blocks.append(bullet("item \(index)", [bullet("child \(index)")]))
            case 6: blocks.append(toggle("toggle \(index)", expanded: index % 20 == 6, [para("inside \(index)")]))
            case 9: blocks.append(numbered("number \(index)"))
            default: blocks.append(para("line \(index)"))
            }
        }
        return blocks
    }

    private func editBigPage(_ session: NotePageSession, afterEdit: (NotePage) -> Void = { _ in }) {
        var generator = SeededGenerator(seed: 2026)
        for round in 0..<150 {
            let order = session.page.documentOrder(includingCollapsed: false)
            let pick = order[Int.random(in: 0..<order.count, using: &generator)]
            let block = session.page.block(pick)!
            switch round % 9 {
            case 0: if block.kind.hasRichText { session.splitBlock(at: NotePosition(pick, min(2, block.text.length))) }
            case 1: if block.kind.hasText { session.mergeBackward(pick) }
            case 2: session.indent([pick])
            case 3: session.outdent([pick])
            case 4: session.moveBlocks([pick], round % 2 == 0 ? .up : .down)
            case 5: session.turnInto([pick], kind: [.bulletedItem, .toggle, .paragraph, .numberedItem][round % 4])
            case 6: session.duplicateBlocks([pick])
            case 7: session.deleteBlocks([pick])
            default:
                if block.kind.hasText {
                    session.setSelection(.caret(NotePosition(pick, 0)))
                    session.type("x")
                }
            }

            afterEdit(session.page)
            if round % 25 == 0 {
                session.undo()
                afterEdit(session.page)
                session.redo()
                afterEdit(session.page)
            }
        }
    }

    private struct SeededGenerator: RandomNumberGenerator {
        private var state: UInt64
        init(seed: UInt64) { state = seed }
        mutating func next() -> UInt64 {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return state ^ (state >> 33)
        }
    }

    @Test func theIndexMatchesANewLargePage() {
        let session = makeSession(bigPage())
        verifyIndex(session.page)
    }

    @Test func theIndexStaysConsistentThroughEditingUndoAndRedo() {
        let session = makeSession(bigPage())
        editBigPage(session) { verifyIndex($0) }
    }

    @Test func numberedItemsKeepLabelsAfterEditingALargePage() {
        let session = makeSession(bigPage())
        editBigPage(session)
        var labels = 0
        for id in session.page.documentOrder() where session.page.block(id)?.kind == .numberedItem {
            #expect(session.page.numberLabel(for: id) != nil, "every numbered item has a label")
            labels += 1
        }
        #expect(labels > 0, "the big page still has numbered items")
    }

    @Test func undoingAllEditsRestoresTheLargePageAndItsIndex() {
        let blocks = bigPage()
        let session = makeSession(blocks)
        editBigPage(session)
        while session.canUndo { session.undo() }
        #expect(session.page.blocks == blocks, "undoing everything returns the original page")
        verifyIndex(session.page)
    }
}
