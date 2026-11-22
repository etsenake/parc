import CoreGraphics
import Foundation
import Testing
@testable import Parc
@testable import ParcCore

@MainActor
struct NoteSelectionModelTestsSelectionCommandsAndDragging {
    private struct AnnouncementCase: Sendable, CustomTestStringConvertible {
        let count: Int
        let text: String

        var testDescription: String { "\(count)" }
    }

    private typealias Block = NoteSelectionModelTestsSupport.Layout.Block

    private let a = Block(text: "first"), b = Block(text: "second")

    @MainActor private struct SelectAll {
        let a = Block(text: "hello"), empty = Block(text: ""), parent = Block(text: "p")
        let child: Block
        let nav: NoteSelectionNavigator
        let layout: NoteSelectionModelTestsSupport.Layout

        init() {
            child = Block(text: "c", depth: 1, parent: parent.id)
            layout = NoteSelectionModelTestsSupport.Layout([a, empty, parent, child])
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

    @MainActor private struct Escape {
        let a = Block(text: "hello"), image = Block(role: .object), b = Block(text: "world")
        var nav: NoteSelectionNavigator { NoteSelectionNavigator(items: NoteSelectionModelTestsSupport.Layout([a, image, b]).items) }
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

    @MainActor private struct Drag {
        let a = Block(text: "hello"), divider = Block(role: .decoration), b = Block(text: "world"), image = Block(role: .object)
        let layout: NoteSelectionModelTestsSupport.Layout
        let nav: NoteSelectionNavigator

        init() {
            layout = NoteSelectionModelTestsSupport.Layout([a, divider, b, image])
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

    private func nearest(_ point: CGPoint) -> (NoteBlockID?, NoteSelectionModelTestsSupport.Layout.Block, NoteSelectionModelTestsSupport.Layout.Block, CGFloat) {
        let first = Block(text: "hello"), second = Block(text: "world")
        let layout = NoteSelectionModelTestsSupport.Layout([first, second])
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

    @Test(arguments: [
        AnnouncementCase(count: 1, text: "1 block selected"),
        AnnouncementCase(count: 3, text: "3 blocks selected"),
    ])
    private func announcementsReadNaturally(sample: AnnouncementCase) {
        #expect(NoteSelectionAnnouncement.blocks(sample.count) == sample.text)
    }
}
