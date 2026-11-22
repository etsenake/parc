import CoreGraphics
import Foundation
import Testing
@testable import Parc
@testable import ParcCore

struct NoteCanvasLayoutTestsDropTargets {
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

    private struct Drops {
        let a = NoteBlock(.bulletedItem, text: "a")
        let nested = NoteBlock(.bulletedItem, text: "nested")
        let b: NoteBlock
        let c = NoteBlock.paragraph("c")
        let moving = NoteBlock.paragraph("moving")

        init() { b = NoteBlock(.bulletedItem, text: "b", children: [nested]) }
    }

    private func dropLayout() -> (Drops, NoteCanvasLayout) {
        let drops = Drops()
        return (drops, NoteCanvasLayoutTestsSupport.layout([drops.a, drops.b, drops.c, drops.moving]))
    }

    private func target(_ result: NoteCanvasLayout, y: CGFloat, dragging: [NoteBlockID], leadingX: CGFloat? = nil) -> NoteCanvasDropTarget? {
        guard let leadingX else { return result.dropTarget(at: CGPoint(x: 300, y: y), dragging: dragging) }
        return result.dropTarget(at: CGPoint(x: 300, y: y), dragging: dragging, leadingX: leadingX)
    }

    @Test func theTopHalfDropsBefore() throws {
        let (drops, result) = dropLayout()
        let frame = try #require(result.frame(of: drops.a.id))
        #expect(target(result, y: frame.minY + 4, dragging: [drops.moving.id], leadingX: 140)?.action == .move(.before(drops.a.id)))
    }

    @Test func theLineSitsAboveTheBlockAtItsDepth() throws {
        let (drops, result) = dropLayout()
        let frame = try #require(result.frame(of: drops.a.id))
        let above = target(result, y: frame.minY + 4, dragging: [drops.moving.id], leadingX: 140)
        guard case .horizontal(let x, let y, let width)? = above?.indicator else {
            Issue.record("expected a horizontal line")
            return
        }
        #expect(x == 140)
        #expect(width == 720)
        #expect(y < frame.minY)
    }

    @Test func theBottomHalfDropsAfter() throws {
        let (drops, result) = dropLayout()
        let frame = try #require(result.frame(of: drops.a.id))
        #expect(target(result, y: frame.maxY - 4, dragging: [drops.moving.id], leadingX: 140)?.action == .move(.after(drops.a.id)))
    }

    @Test func movingRightNestsUnderListItems() throws {
        let (drops, result) = dropLayout()
        let frame = try #require(result.frame(of: drops.a.id))
        let nest = target(result, y: frame.maxY - 4, dragging: [drops.moving.id], leadingX: 168)
        #expect(nest?.action == .move(.firstChild(of: drops.a.id)))
        #expect(nest?.depth == 1)
    }

    @Test func aParentWithChildrenTakesDropsAsItsFirstChild() throws {
        let (drops, result) = dropLayout()
        let frame = try #require(result.frame(of: drops.b.id))
        #expect(target(result, y: frame.maxY - 2, dragging: [drops.moving.id], leadingX: 140)?.action == .move(.firstChild(of: drops.b.id)))
    }

    @Test func movingLeftFromTheLastChildClimbsOut() throws {
        let (drops, result) = dropLayout()
        let frame = try #require(result.frame(of: drops.nested.id))
        #expect(target(result, y: frame.maxY - 2, dragging: [drops.moving.id], leadingX: 138)?.action == .move(.after(drops.b.id)))
    }

    @Test func stayingAtTheChildDepthStaysASibling() throws {
        let (drops, result) = dropLayout()
        let frame = try #require(result.frame(of: drops.nested.id))
        #expect(target(result, y: frame.maxY - 2, dragging: [drops.moving.id], leadingX: 166)?.action == .move(.after(drops.nested.id)))
    }

    @Test func movingRightNestsUnderParagraphs() throws {
        let (drops, result) = dropLayout()
        let frame = try #require(result.frame(of: drops.c.id))
        let paragraph = target(result, y: frame.maxY - 2, dragging: [drops.moving.id], leadingX: 220)
        #expect(paragraph?.action == .move(.firstChild(of: drops.c.id)))
        #expect(paragraph?.depth == 1)
    }

    @Test func stayingLeftBesideAParagraphKeepsASibling() throws {
        let (drops, result) = dropLayout()
        let frame = try #require(result.frame(of: drops.c.id))
        #expect(target(result, y: frame.maxY - 2, dragging: [drops.moving.id], leadingX: 140)?.action == .move(.after(drops.c.id)))
    }

    @Test func aPlainHeadingsChildrenSitOneIndentInAlwaysShown() throws {
        let kid = NoteBlock.paragraph("kid")
        var heading = NoteBlock.heading(2, "head")
        heading.children = [kid]
        #expect(NoteCanvasLayoutTestsSupport.layout([heading, .paragraph("moving")]).frame(of: kid.id)?.minX == 166)
    }

    @Test func aHeadingWithChildrenTakesDropsAsItsFirstChild() throws {
        let moving = NoteBlock.paragraph("moving")
        var heading = NoteBlock.heading(2, "head")
        heading.children = [.paragraph("kid")]
        let headed = NoteCanvasLayoutTestsSupport.layout([heading, moving])
        let frame = try #require(headed.frame(of: heading.id))
        #expect(target(headed, y: frame.maxY - 2, dragging: [moving.id], leadingX: 140)?.action == .move(.firstChild(of: heading.id)))
    }

    @Test func nothingDropsIntoItsOwnDescendants() throws {
        let (drops, result) = dropLayout()
        let frame = try #require(result.frame(of: drops.nested.id))
        #expect(target(result, y: frame.midY, dragging: [drops.b.id]) == nil)
    }

    @Test func nothingDropsOntoItself() throws {
        let (drops, result) = dropLayout()
        let frame = try #require(result.frame(of: drops.b.id))
        #expect(target(result, y: frame.midY - 2, dragging: [drops.b.id]) == nil)
    }

    @Test func belowEverythingDropsAtTheEnd() {
        let (drops, result) = dropLayout()
        #expect(target(result, y: 900, dragging: [drops.a.id], leadingX: 140)?.action == .move(.after(drops.moving.id)))
    }

    @Test func aboveEverythingDropsAtTheStart() {
        let (drops, result) = dropLayout()
        #expect(target(result, y: 10, dragging: [drops.moving.id], leadingX: 140)?.action == .move(.before(drops.a.id)))
    }

    @Test func closedTogglesTakeDropsAsTheirLastChild() throws {
        let moving = NoteBlock.paragraph("moving")
        var closed = NoteBlock(.toggle, text: "closed", children: [.paragraph("hidden")])
        closed.props.expanded = false
        let toggled = NoteCanvasLayoutTestsSupport.layout([closed, moving])
        let frame = try #require(toggled.frame(of: closed.id))
        #expect(target(toggled, y: frame.maxY - 2, dragging: [moving.id], leadingX: 168)?.action == .move(.lastChild(of: closed.id)))
    }

    @Test func theEmptyToggleHintTakesDropsInside() throws {
        let moving = NoteBlock.paragraph("moving")
        let emptyToggle = NoteBlock(.toggle, text: "empty")
        let hinted = NoteCanvasLayout(page: NotePage(blocks: [emptyToggle, moving]), width: 1000, headerHeight: 100,
                                      metrics: NoteCanvasMetrics(),
                                      measure: NoteCanvasMeasure(height: { block, _ in block.kind == .toggle ? 54 : 26 },
                                                                 childIndent: { _ in 26 }))
        let frame = try #require(hinted.frame(of: emptyToggle.id))
        #expect(target(hinted, y: frame.maxY - 6, dragging: [moving.id], leadingX: 140)?.action == .move(.firstChild(of: emptyToggle.id)))
    }
}
