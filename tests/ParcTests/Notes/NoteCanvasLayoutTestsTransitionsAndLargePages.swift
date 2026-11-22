import CoreGraphics
import Foundation
import Testing
@testable import Parc
@testable import ParcCore

struct NoteCanvasLayoutTestsTransitionsAndLargePages {
    private struct Moves {
        let a = NoteBlock.paragraph("a"), b = NoteBlock.paragraph("b"), c = NoteBlock.paragraph("c")
    }

    @Test func insertionsAreFound() {
        let moves = Moves()
        let inserted = NoteBlock.paragraph("new")
        let insert = NoteCanvasTransition(from: NoteCanvasLayoutTestsSupport.layout([moves.a, moves.b, moves.c]), to: NoteCanvasLayoutTestsSupport.layout([moves.a, inserted, moves.b, moves.c]))
        #expect(insert.isStructural)
        #expect(insert.inserted == [inserted.id])
    }

    @Test func shiftedBlocksSlideFromWhereTheyWere() {
        let moves = Moves()
        let insert = NoteCanvasTransition(from: NoteCanvasLayoutTestsSupport.layout([moves.a, moves.b, moves.c]), to: NoteCanvasLayoutTestsSupport.layout([moves.a, .paragraph("new"), moves.b, moves.c]))
        #expect(insert.moved[moves.b.id] == CGVector(dx: 0, dy: -28))
        #expect(insert.moved[moves.a.id] == nil)
    }

    @Test func removalsAreFound() {
        let moves = Moves()
        let remove = NoteCanvasTransition(from: NoteCanvasLayoutTestsSupport.layout([moves.a, moves.b, moves.c]), to: NoteCanvasLayoutTestsSupport.layout([moves.a, moves.c]))
        #expect(remove.removed == [moves.b.id])
        #expect(remove.merged.isEmpty)
    }

    @Test func mergingIntoThePreviousBlockSkipsTheFade() {
        let moves = Moves()
        let merged = NoteCanvasTransition(from: NoteCanvasLayoutTestsSupport.layout([moves.a, moves.b, moves.c]),
                                          to: NoteCanvasLayoutTestsSupport.layout([NoteBlock(.paragraph, text: "ab", id: moves.a.id), moves.c]))
        #expect(merged.merged == [moves.b.id])
    }

    @Test func heightOnlyChangesNeverAnimate() {
        let moves = Moves()
        let taller = NoteCanvasLayout(page: NotePage(blocks: [moves.a, moves.b, moves.c]), width: 1000, headerHeight: 100, metrics: NoteCanvasMetrics(),
                                      measure: NoteCanvasMeasure(height: { block, _ in block.id == moves.a.id ? 52 : 26 }, childIndent: { _ in 26 }))
        #expect(!NoteCanvasTransition(from: NoteCanvasLayoutTestsSupport.layout([moves.a, moves.b, moves.c]), to: taller).isStructural)
    }

    private struct Collapsing {
        let child = NoteBlock.paragraph("child")
        let after = NoteBlock.paragraph("c")
        let toggleID: NoteBlockID
        let open: NoteCanvasLayout
        let closed: NoteCanvasLayout

        init(layout: ([NoteBlock]) -> NoteCanvasLayout) {
            var toggle = NoteBlock(.toggle, text: "t", children: [child])
            toggleID = toggle.id
            open = NoteCanvasLayoutTestsSupport.layout([toggle, after])
            toggle.props.expanded = false
            closed = NoteCanvasLayoutTestsSupport.layout([toggle, after])
        }
    }

    @Test func collapsingConcealsInsteadOfRemoving() {
        let collapsing = Collapsing { NoteCanvasLayoutTestsSupport.layout($0) }
        let collapse = NoteCanvasTransition(from: collapsing.open, to: collapsing.closed)
        #expect(collapse.concealed.first?.ids == [collapsing.child.id])
        #expect(collapse.removed.isEmpty)
    }

    @Test func theConcealedGroupRemembersItsHeight() {
        let collapsing = Collapsing { NoteCanvasLayoutTestsSupport.layout($0) }
        #expect(NoteCanvasTransition(from: collapsing.open, to: collapsing.closed).concealed.first?.height == 28)
    }

    @Test func expandingRevealsInsteadOfInserting() {
        let collapsing = Collapsing { NoteCanvasLayoutTestsSupport.layout($0) }
        let expand = NoteCanvasTransition(from: collapsing.closed, to: collapsing.open)
        #expect(expand.revealed.first?.ids == [collapsing.child.id])
        #expect(expand.inserted.isEmpty)
    }

    @Test func revealsGrowFromTheToggleRow() {
        let collapsing = Collapsing { NoteCanvasLayoutTestsSupport.layout($0) }
        let expand = NoteCanvasTransition(from: collapsing.closed, to: collapsing.open)
        #expect(expand.revealed.first?.top == collapsing.open.frame(of: collapsing.toggleID)?.maxY)
    }

    @Test func reordersSlide() {
        let moves = Moves()
        let moved = NoteCanvasTransition(from: NoteCanvasLayoutTestsSupport.layout([moves.a, moves.b, moves.c]), to: NoteCanvasLayoutTestsSupport.layout([moves.c, moves.a, moves.b]))
        #expect(moved.moved[moves.c.id]?.dy == 56)
        #expect(moved.inserted.isEmpty)
        #expect(moved.removed.isEmpty)
    }

    @Test func missingWidthsSplitEvenly() {
        #expect(NoteCanvasLayout.normalizedFractions([nil, nil], count: 2) == [0.5, 0.5])
    }

    @Test func partialWidthsFillWithTheAverage() {
        let mixed = NoteCanvasLayout.normalizedFractions([0.2, nil, 0.4], count: 3)
        #expect(abs(mixed[0] - 0.2 / 0.9) < 0.0001)
        #expect(abs(mixed.reduce(0, +) - 1) < 0.0001)
    }

    @Test func percentagesNormalizeToo() {
        #expect(NoteCanvasLayout.normalizedFractions([60, 40], count: 2) == [0.6, 0.4])
    }

    @Test func draggingMovesWidthBetweenNeighbours() {
        let resized = NoteCanvasLayout.resizedFractions([0.5, 0.5], divider: 0, delta: 100, available: 500, minimumWidth: 64)
        #expect(abs(resized[0] - 0.7) < 0.0001)
        #expect(abs(resized[1] - 0.3) < 0.0001)
    }

    @Test func columnsKeepAMinimumWidth() {
        let clamped = NoteCanvasLayout.resizedFractions([0.5, 0.5], divider: 0, delta: 1000, available: 500, minimumWidth: 64)
        #expect(abs(clamped[1] - 64.0 / 500) < 0.0001)
    }

    private func bigPage() -> NoteCanvasLayout {
        var blocks: [NoteBlock] = []
        for index in 0..<2000 {
            switch index % 7 {
            case 0: blocks.append(.heading(2, NoteText("Heading \(index)")))
            case 3: blocks.append(NoteBlock(.bulletedItem, text: NoteText("item \(index)"), children: [NoteBlock(.todo, text: NoteText("todo \(index)"))]))
            default: blocks.append(.paragraph(NoteText(String(repeating: "word ", count: index % 40))))
            }
        }
        let metrics = NoteCanvasMetrics()
        return NoteCanvasLayout(page: NotePage(blocks: blocks), width: 1100, headerHeight: 200, metrics: metrics,
                                measure: NoteCanvasMeasure(height: { NoteCanvasEstimate.height(of: $0, width: $1, metrics: metrics) },
                                                           childIndent: { _ in 26 }))
    }

    @Test func everyVisibleBlockOfABigPageGetsAnEntry() {
        #expect(bigPage().entries.count == 2000 + 2000 / 7 + 1)
    }

    @Test func rowsOfABigPageStackDownwardWithoutOverlap() {
        let result = bigPage()
        var last: CGFloat = 0
        var overlapping = 0
        for row in result.flows[0] {
            let frame = result.entries[row].frame
            if frame.minY < last || frame.height <= 0 { overlapping += 1 }
            last = frame.maxY
        }
        #expect(overlapping == 0)
    }

    @Test func hitTestingWorksDeepInABigPage() {
        let result = bigPage()
        let probe = result.entries[1500]
        #expect(result.blockID(at: CGPoint(x: 500, y: probe.frame.midY)) == probe.id)
    }
}
