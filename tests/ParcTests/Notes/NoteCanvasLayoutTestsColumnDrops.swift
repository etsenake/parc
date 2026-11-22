import CoreGraphics
import Foundation
import Testing
@testable import Parc
@testable import ParcCore
@testable import ParcNotes

struct NoteCanvasLayoutTestsColumnDrops {
    private struct Nest {
        let grandchild = NoteBlock(.bulletedItem, text: "grandchild")
        let middle: NoteBlock
        let parent: NoteBlock
        let after = NoteBlock.paragraph("after")

        init() {
            var child = NoteBlock(.bulletedItem, text: "child")
            child.children = [grandchild]
            middle = child
            parent = NoteBlock(.bulletedItem, text: "parent", children: [child])
        }
    }

    private func nested() -> (Nest, NoteCanvasLayout) {
        let nest = Nest()
        return (nest, NoteCanvasLayoutTestsSupport.layout([nest.parent, nest.after]))
    }

    private struct Plain {
        let a = NoteBlock.paragraph("a"), b = NoteBlock.paragraph("b"), moving = NoteBlock.paragraph("moving")
    }

    private func plainLayout() -> (Plain, NoteCanvasLayout) {
        let plain = Plain()
        return (plain, NoteCanvasLayoutTestsSupport.layout([plain.a, plain.b, plain.moving]))
    }

    @Test func theFarLeftMarginMakesAColumn() throws {
        let (plain, result) = plainLayout()
        let frame = try #require(result.frame(of: plain.a.id))
        let left = result.dropTarget(at: CGPoint(x: 60, y: frame.midY), dragging: [plain.moving.id])
        #expect(left?.action == .placeBeside(plain.a.id, .left))
        #expect(left?.isVertical == true)
    }

    @Test func theRightEdgeMakesAColumn() throws {
        let (plain, result) = plainLayout()
        let frame = try #require(result.frame(of: plain.a.id))
        #expect(result.dropTarget(at: CGPoint(x: 820, y: frame.midY), dragging: [plain.moving.id])?.action == .placeBeside(plain.a.id, .right))
    }

    @Test func theMiddleStaysAPlainMove() throws {
        let (plain, result) = plainLayout()
        let frame = try #require(result.frame(of: plain.a.id))
        #expect(result.dropTarget(at: CGPoint(x: 400, y: frame.midY + 2), dragging: [plain.moving.id], leadingX: 140)?.action == .move(.after(plain.a.id)))
    }

    @Test func nestedBlocksNeverBecomeColumns() throws {
        let moving = NoteBlock.paragraph("moving")
        let child = NoteBlock(.bulletedItem, text: "child")
        let nested = NoteCanvasLayoutTestsSupport.layout([NoteBlock(.bulletedItem, text: "parent", children: [child]), moving])
        let frame = try #require(nested.frame(of: child.id))
        #expect(nested.dropTarget(at: CGPoint(x: 840, y: frame.midY + 2), dragging: [moving.id])?.isVertical == false)
    }

    private struct Columns {
        let x = NoteBlock.paragraph("x"), y = NoteBlock.paragraph("y"), moving = NoteBlock.paragraph("moving")
        let row: NoteBlock

        init() { row = NoteBlock(.columns, children: [NoteBlock(.column, children: [x]), NoteBlock(.column, children: [y])]) }
    }

    @Test func aColumnChildsEdgeAddsAColumn() throws {
        let columns = Columns()
        let result = NoteCanvasLayoutTestsSupport.layout([columns.row, columns.moving])
        let frame = try #require(result.frame(of: columns.x.id))
        #expect(result.dropTarget(at: CGPoint(x: frame.maxX - 10, y: frame.midY), dragging: [columns.moving.id])?.action == .placeBeside(columns.x.id, .right))
    }

    @Test func theColumnLineSitsInTheGapAndSpansTheRow() throws {
        let columns = Columns()
        let result = NoteCanvasLayoutTestsSupport.layout([columns.row, columns.moving])
        let frame = try #require(result.frame(of: columns.x.id))
        let between = result.dropTarget(at: CGPoint(x: frame.maxX - 10, y: frame.midY), dragging: [columns.moving.id])
        guard case .vertical(let lineX, _, let height)? = between?.indicator else {
            Issue.record("expected a vertical line")
            return
        }
        #expect(abs(lineX - (frame.maxX + 23)) < 0.5)
        #expect(height == result.frame(of: columns.row.id)?.height)
    }

    @Test func fiveColumnsIsTheLimit() throws {
        let moving = NoteBlock.paragraph("moving")
        let full = NoteBlock(.columns, children: (0..<5).map { NoteBlock(.column, children: [NoteBlock.paragraph(NoteText("c\($0)"))]) })
        let crowded = NoteCanvasLayoutTestsSupport.layout([full, moving])
        let frame = try #require(crowded.frame(of: full.children[0].children[0].id))
        #expect(crowded.dropTarget(at: CGPoint(x: frame.maxX - 2, y: frame.midY), dragging: [moving.id])?.isVertical == false)
    }

    @Test func columnsNeverNestInsideColumns() throws {
        let columns = Columns()
        let result = NoteCanvasLayoutTestsSupport.layout([columns.row, columns.moving])
        let frame = try #require(result.frame(of: columns.moving.id))
        #expect(result.dropTarget(at: CGPoint(x: 60, y: frame.midY), dragging: [columns.row.id])?.isVertical == false)
    }

    @Test func plainTextPagesNeverMakeColumns() throws {
        let plain = Plain()
        let flat = NoteCanvasLayout(page: NotePage(blocks: [plain.a, plain.b, plain.moving]), width: 1000, headerHeight: 100,
                                    metrics: NoteCanvasMetrics(), flat: true, measure: NoteCanvasLayoutTestsSupport.measure)
        let frame = try #require(flat.frame(of: plain.a.id))
        #expect(flat.dropTarget(at: CGPoint(x: 60, y: frame.midY), dragging: [plain.moving.id])?.isVertical == false)
    }

    @Test func plainTextPagesNeverNestLines() throws {
        let plain = Plain()
        let flat = NoteCanvasLayout(page: NotePage(blocks: [plain.a, plain.b, plain.moving]), width: 1000, headerHeight: 100,
                                    metrics: NoteCanvasMetrics(), flat: true, measure: NoteCanvasLayoutTestsSupport.measure)
        let frame = try #require(flat.frame(of: plain.a.id))
        #expect(flat.dropTarget(at: CGPoint(x: 820, y: frame.maxY - 2), dragging: [plain.moving.id], leadingX: 220)?.action == .move(.after(plain.a.id)))
    }
}
