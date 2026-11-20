import CoreGraphics
import Foundation

@main @MainActor
struct NoteCanvasLayoutTests {
    static func expect(_ value: Bool, _ message: String, line: UInt = #line) {
        if !value { failTest(message, line: line) }
    }

    static let measure = NoteCanvasMeasure(
        height: { block, _ in
            switch block.kind {
            case .heading: return 40
            case .divider: return 13
            case .callout: return 54
            default: return 26
            }
        },
        childIndent: { block in
            switch block.kind {
            case .callout: return 46
            case .quote: return 17
            default: return 26
            }
        })

    static func layout(_ blocks: [NoteBlock], width: CGFloat = 1000, header: CGFloat = 100, fullWidth: Bool = false,
                       overrides: [NoteBlockID: [CGFloat]] = [:]) -> NoteCanvasLayout {
        var metrics = NoteCanvasMetrics()
        metrics.fullWidth = fullWidth
        return NoteCanvasLayout(page: NotePage(blocks: blocks), width: width, headerHeight: header, metrics: metrics,
                                columnFractions: overrides, measure: measure)
    }

    static func main() {
        stacking()
        nesting()
        toggles()
        columns()
        callouts()
        drops()
        columnDrops()
        washes()
        decorations()
        transitions()
        fractions()
        bigPage()
        print("NoteCanvasLayoutTests passed")
    }

    static func stacking() {
        let a = NoteBlock.paragraph("a"), b = NoteBlock.paragraph("b"), h = NoteBlock.heading(1, "h"), c = NoteBlock.paragraph("c")
        let result = layout([a, b, h, c])
        expect(result.columnX == 140 && result.columnWidth == 720, "the page column is 720 wide and centred")
        expect(result.frame(of: a.id) == CGRect(x: 140, y: 104, width: 720, height: 26), "the first block sits under the header")
        expect(result.frame(of: b.id)?.minY == 132, "paragraphs keep a two-point gap")
        expect(result.frame(of: h.id)?.minY == 170, "a heading takes its own breathing room")
        expect(result.frame(of: c.id)?.minY == 214, "the block after a heading gets the heading's after-space")
        expect(result.contentBottom == 240, "content ends at the last block")
        let wide = layout([a], width: 1400, fullWidth: true)
        expect(wide.columnWidth == 1208 && wide.columnX == 96, "full width keeps 96 point margins")
        let narrow = layout([a], width: 600)
        expect(narrow.columnWidth == 544 && narrow.columnX == 28, "narrow panes shrink the margins first")
        let bare = layout([a], header: 0)
        expect(bare.frame(of: a.id)?.minY == NoteCanvasMetrics().topInset, "no header means the top inset")
        expect(result.documentHeight(viewportHeight: 800) == 800, "short pages fill the viewport")
        expect(result.documentHeight(viewportHeight: 100) == 400, "long pages get bottom room")
    }

    static func nesting() {
        let child = NoteBlock(.bulletedItem, text: "child")
        let grandchild = NoteBlock(.bulletedItem, text: "grandchild")
        var middle = child
        middle.children = [grandchild]
        let parent = NoteBlock(.bulletedItem, text: "parent", children: [middle])
        let after = NoteBlock.paragraph("after")
        let result = layout([parent, after])
        expect(result.frame(of: middle.id)?.minX == 166, "children indent by the indent width")
        expect(result.frame(of: grandchild.id)?.minX == 192 && result.frame(of: grandchild.id)?.width == 668,
               "grandchildren indent again and keep the right edge")
        expect(result.frame(of: middle.id)?.minY == 132, "children follow their parent row")
        expect(result.outerFrame(of: parent.id)?.maxY == 186, "the outer frame wraps the descendants")
        expect(result.frame(of: after.id)?.minY == 188, "the next sibling follows the subtree")
        expect(result.blockID(at: CGPoint(x: 150, y: 140)) == middle.id, "hit testing finds the deepest row")
        expect(result.blockID(at: CGPoint(x: 20, y: 110)) == parent.id, "rows reach into the margins")
        expect(result.blockID(at: CGPoint(x: 300, y: 50)) == nil, "the header is not a block")
        expect(result.blockID(at: CGPoint(x: 300, y: 600)) == nil, "the space below the last block is empty")
        expect(result.gutterRect(for: middle.id) == CGRect(x: 120, y: 132, width: 46, height: 26), "the gutter sits left of the row")
        expect(result.ancestors(of: grandchild.id) == [middle.id, parent.id], "ancestors walk up")
        expect(result.blockIDs(in: CGRect(x: 0, y: 131, width: 1000, height: 31)) == [middle.id, grandchild.id],
               "a marquee picks rows it touches")
        let numbered = (1...3).map { NoteBlock(.numberedItem, text: NoteText("n\($0)")) }
        var started = numbered
        started[0].props.listStart = 4
        let list = layout(started + [NoteBlock.paragraph("x"), NoteBlock(.numberedItem, text: "again")])
        expect(list.entries.compactMap(\.listOrdinal) == [4, 5, 6, 1], "numbering counts runs and restarts after a break")
    }

    static func toggles() {
        let inner = NoteBlock.paragraph("inner")
        var toggle = NoteBlock(.toggle, text: "toggle", children: [inner])
        let after = NoteBlock.paragraph("after")
        let open = layout([toggle, after])
        expect(open.entry(inner.id) != nil, "open toggles show children")
        toggle.props.expanded = false
        let closed = layout([toggle, after])
        expect(closed.entry(inner.id) == nil, "collapsed toggles hide their descendants")
        expect(closed.frame(of: after.id)?.minY == 132, "following blocks close the gap")
        expect(closed.entry(toggle.id)?.isCollapsed == true, "the entry knows it is collapsed")
    }

    static func columns() {
        let left = NoteBlock.paragraph("left")
        let rightTop = NoteBlock.paragraph("right top"), rightBottom = NoteBlock.paragraph("right bottom")
        let columnA = NoteBlock(.column, children: [left])
        let columnB = NoteBlock(.column, children: [rightTop, rightBottom])
        var weighted = columnA
        weighted.props.width = 0.25
        var heavy = columnB
        heavy.props.width = 0.75
        let row = NoteBlock(.columns, children: [weighted, heavy])
        let after = NoteBlock.paragraph("after")
        let result = layout([NoteBlock.paragraph("before"), row, after])
        let available: CGFloat = 720 - 46
        let rowFrame = result.frame(of: row.id)!
        expect(rowFrame.minY == 134 && rowFrame.height == 54, "the row is as tall as its tallest column")
        let leftFrame = result.frame(of: left.id)!
        expect(leftFrame.minX == 140 && leftFrame.width == (available * 0.25).rounded(), "widths follow the column fractions")
        let topFrame = result.frame(of: rightTop.id)!
        expect(abs(topFrame.minX - (140 + (available * 0.25).rounded() + 46)) < 0.5 && topFrame.maxX == 860,
               "the second column starts after the gap and ends at the page edge")
        expect(result.frame(of: rightBottom.id)?.minY == 162, "columns stack their own children")
        expect(result.frame(of: after.id)?.minY == 192, "the next block clears the row")
        expect(result.frame(of: columnA.id) == CGRect(x: 140, y: 134, width: (available * 0.25).rounded(), height: 54),
               "column entries span the row")
        expect(result.blockID(at: CGPoint(x: 700, y: 165)) == rightBottom.id, "x picks the column, y the row")
        expect(result.blockID(at: CGPoint(x: 150, y: 175)) == nil, "short columns leave empty room")
        let rowInfo = result.columnsRows[row.id]!
        expect(rowInfo.gapRect(after: 0).width == 46, "gaps sit between columns")
        let overridden = layout([row], overrides: [row.id: [0.5, 0.5]])
        expect(overridden.frame(of: left.id)?.width == (available * 0.5).rounded(), "live overrides win over stored widths")
    }

    static func callouts() {
        let child = NoteBlock.paragraph("inside")
        let callout = NoteBlock(.callout, text: "note", children: [child])
        let after = NoteBlock.paragraph("after")
        let result = layout([callout, after])
        expect(result.frame(of: callout.id) == CGRect(x: 140, y: 104, width: 720, height: 54), "the callout row spans the box")
        expect(result.frame(of: child.id) == CGRect(x: 186, y: 160, width: 720 - 46 - 18, height: 26),
               "callout children line up with its text and keep the right padding")
        expect(result.outerFrame(of: callout.id)?.maxY == 200, "the box closes 14 points under its last child")
        expect(result.frame(of: after.id)?.minY == 206, "the block after a callout clears the box")
        let quoteChild = NoteBlock.paragraph("quoted")
        let quote = NoteBlock(.quote, text: "q", children: [quoteChild])
        let quoted = layout([quote])
        expect(quoted.frame(of: quoteChild.id)?.minX == 157, "quote children align with the quote text")
    }

    static func drops() {
        let a = NoteBlock(.bulletedItem, text: "a")
        let nested = NoteBlock(.bulletedItem, text: "nested")
        let b = NoteBlock(.bulletedItem, text: "b", children: [nested])
        let c = NoteBlock.paragraph("c")
        let moving = NoteBlock.paragraph("moving")
        let result = layout([a, b, c, moving])
        let aFrame = result.frame(of: a.id)!
        let above = result.dropTarget(at: CGPoint(x: 300, y: aFrame.minY + 4), dragging: [moving.id], leadingX: 140)
        expect(above?.action == .move(.before(a.id)), "the top half drops before")
        if case .horizontal(let x, let y, let width)? = above?.indicator {
            expect(x == 140 && width == 720 && y < aFrame.minY, "the line sits above the block at its depth")
        } else { failTest("expected a horizontal line") }
        let below = result.dropTarget(at: CGPoint(x: 300, y: aFrame.maxY - 4), dragging: [moving.id], leadingX: 140)
        expect(below?.action == .move(.after(a.id)), "the bottom half drops after")
        let nest = result.dropTarget(at: CGPoint(x: 300, y: aFrame.maxY - 4), dragging: [moving.id], leadingX: 168)
        expect(nest?.action == .move(.firstChild(of: a.id)) && nest?.depth == 1, "moving right nests under list items")
        let bFrame = result.frame(of: b.id)!
        let intoParent = result.dropTarget(at: CGPoint(x: 300, y: bFrame.maxY - 2), dragging: [moving.id], leadingX: 140)
        expect(intoParent?.action == .move(.firstChild(of: b.id)), "a parent with children takes drops as its first child")
        let nestedFrame = result.frame(of: nested.id)!
        let outdent = result.dropTarget(at: CGPoint(x: 300, y: nestedFrame.maxY - 2), dragging: [moving.id], leadingX: 138)
        expect(outdent?.action == .move(.after(b.id)), "moving left from the last child climbs out")
        let stay = result.dropTarget(at: CGPoint(x: 300, y: nestedFrame.maxY - 2), dragging: [moving.id], leadingX: 166)
        expect(stay?.action == .move(.after(nested.id)), "staying at the child depth stays a sibling")
        let cFrame = result.frame(of: c.id)!
        let paragraph = result.dropTarget(at: CGPoint(x: 300, y: cFrame.maxY - 2), dragging: [moving.id], leadingX: 220)
        expect(paragraph?.action == .move(.after(c.id)), "paragraphs never take children")
        expect(result.dropTarget(at: CGPoint(x: 300, y: nestedFrame.midY), dragging: [b.id]) == nil,
               "nothing drops into its own descendants")
        expect(result.dropTarget(at: CGPoint(x: 300, y: bFrame.midY - 2), dragging: [b.id]) == nil, "nothing drops onto itself")
        let bottom = result.dropTarget(at: CGPoint(x: 300, y: 900), dragging: [a.id], leadingX: 140)
        expect(bottom?.action == .move(.after(moving.id)), "below everything drops at the end")
        let top = result.dropTarget(at: CGPoint(x: 300, y: 10), dragging: [moving.id], leadingX: 140)
        expect(top?.action == .move(.before(a.id)), "above everything drops at the start")
        var closed = NoteBlock(.toggle, text: "closed", children: [NoteBlock.paragraph("hidden")])
        closed.props.expanded = false
        let toggled = layout([closed, moving])
        let closedFrame = toggled.frame(of: closed.id)!
        let intoClosed = toggled.dropTarget(at: CGPoint(x: 300, y: closedFrame.maxY - 2), dragging: [moving.id], leadingX: 168)
        expect(intoClosed?.action == .move(.lastChild(of: closed.id)), "closed toggles take drops as their last child")
        let emptyToggle = NoteBlock(.toggle, text: "empty")
        let hinted = NoteCanvasLayout(page: NotePage(blocks: [emptyToggle, moving]), width: 1000, headerHeight: 100,
                                      metrics: NoteCanvasMetrics(),
                                      measure: NoteCanvasMeasure(height: { block, _ in block.kind == .toggle ? 54 : 26 },
                                                                 childIndent: { _ in 26 }))
        let hintFrame = hinted.frame(of: emptyToggle.id)!
        let intoHint = hinted.dropTarget(at: CGPoint(x: 300, y: hintFrame.maxY - 6), dragging: [moving.id], leadingX: 140)
        expect(intoHint?.action == .move(.firstChild(of: emptyToggle.id)), "the empty toggle hint takes drops inside")
    }

    static func columnDrops() {
        let a = NoteBlock.paragraph("a"), b = NoteBlock.paragraph("b")
        let moving = NoteBlock.paragraph("moving")
        let result = layout([a, b, moving])
        let aFrame = result.frame(of: a.id)!
        let left = result.dropTarget(at: CGPoint(x: 60, y: aFrame.midY), dragging: [moving.id])
        expect(left?.action == .placeBeside(a.id, .left) && left?.isVertical == true, "the far left margin makes a column")
        let right = result.dropTarget(at: CGPoint(x: 820, y: aFrame.midY), dragging: [moving.id])
        expect(right?.action == .placeBeside(a.id, .right), "the right edge makes a column")
        let middle = result.dropTarget(at: CGPoint(x: 400, y: aFrame.midY + 2), dragging: [moving.id])
        expect(middle?.action == .move(.after(a.id)), "the middle stays a plain move")
        let child = NoteBlock(.bulletedItem, text: "child")
        let parent = NoteBlock(.bulletedItem, text: "parent", children: [child])
        let nested = layout([parent, moving])
        let childFrame = nested.frame(of: child.id)!
        let nestedRight = nested.dropTarget(at: CGPoint(x: 840, y: childFrame.midY + 2), dragging: [moving.id])
        expect(nestedRight?.isVertical == false, "nested blocks never become columns")
        let x = NoteBlock.paragraph("x"), y = NoteBlock.paragraph("y")
        let row = NoteBlock(.columns, children: [NoteBlock(.column, children: [x]), NoteBlock(.column, children: [y])])
        let inColumns = layout([row, moving])
        let xFrame = inColumns.frame(of: x.id)!
        let between = inColumns.dropTarget(at: CGPoint(x: xFrame.maxX - 10, y: xFrame.midY), dragging: [moving.id])
        expect(between?.action == .placeBeside(x.id, .right), "a column child's edge adds a column")
        if case .vertical(let lineX, _, let height)? = between?.indicator {
            expect(abs(lineX - (xFrame.maxX + 23)) < 0.5 && height == inColumns.frame(of: row.id)!.height,
                   "the column line sits in the gap and spans the row")
        } else { failTest("expected a vertical line") }
        let full = NoteBlock(.columns, children: (0..<5).map { NoteBlock(.column, children: [NoteBlock.paragraph(NoteText("c\($0)"))]) })
        let crowded = layout([full, moving])
        let first = full.children[0].children[0].id
        let crowdedFrame = crowded.frame(of: first)!
        let refused = crowded.dropTarget(at: CGPoint(x: crowdedFrame.maxX - 2, y: crowdedFrame.midY), dragging: [moving.id])
        expect(refused?.isVertical == false, "five columns is the limit")
        let refusedRow = inColumns.dropTarget(at: CGPoint(x: 60, y: inColumns.frame(of: moving.id)!.midY), dragging: [row.id])
        expect(refusedRow?.isVertical == false, "columns never nest inside columns")
    }

    static func washes() {
        let a = NoteBlock.paragraph("a"), b = NoteBlock.paragraph("b"), c = NoteBlock.paragraph("c")
        let child = NoteBlock(.bulletedItem, text: "child")
        let parent = NoteBlock(.bulletedItem, text: "parent", children: [child])
        let result = layout([a, b, c, parent])
        let joined = result.washRects(for: [a.id, b.id])
        expect(joined.count == 1 && joined[0].key == a.id, "neighbours share one wash")
        expect(joined[0].rect == CGRect(x: 136, y: 103, width: 728, height: 56), "the wash covers both blocks plus its outset")
        expect(result.washRects(for: [a.id, c.id]).count == 2, "a gap splits the wash")
        let family = result.washRects(for: [parent.id, child.id])
        expect(family.count == 1 && family[0].rect.maxY == result.outerFrame(of: parent.id)!.maxY + 1,
               "selecting a parent washes its children once")
        expect(result.washRects(for: [NoteBlockID()]).isEmpty, "unknown ids wash nothing")
    }

    static func decorations() {
        let inside = NoteBlock.paragraph("inside")
        let quote = NoteBlock(.quote, text: "q", color: .text(.red), children: [inside])
        let callout = NoteBlock(.callout, text: "c", color: .background(.blue))
        let tinted = NoteBlock.paragraph("tinted")
        var colored = tinted
        colored.color = .background(.yellow)
        let result = layout([quote, callout, colored])
        let all = result.decorations(in: CGRect(x: 0, y: 0, width: 1000, height: 2000))
        let bar = all.first { $0.key == .init(owner: quote.id, slot: 1) }
        expect(bar?.style == .quoteBar(.red), "quote bars take the quote's text colour")
        expect(bar?.rect.minY == result.frame(of: quote.id)!.maxY && bar?.rect.maxY == result.outerFrame(of: quote.id)!.maxY,
               "the bar continues beside the quote's children")
        expect(all.contains { $0.style == .callout(.background(.blue)) && $0.rect == result.outerFrame(of: callout.id)! },
               "callouts get their box")
        expect(all.contains { $0.style == .background(.yellow) }, "background colours get a fill")
        expect(all.last?.key.slot == 1, "bars draw above fills")
        expect(result.decorations(in: CGRect(x: 0, y: 1500, width: 10, height: 10)).isEmpty, "regions filter decorations")
    }

    static func transitions() {
        let a = NoteBlock.paragraph("a"), b = NoteBlock.paragraph("b"), c = NoteBlock.paragraph("c")
        let before = layout([a, b, c])
        let inserted = NoteBlock.paragraph("new")
        let after = layout([a, inserted, b, c])
        let insert = NoteCanvasTransition(from: before, to: after)
        expect(insert.isStructural && insert.inserted == [inserted.id], "insertions are found")
        expect(insert.moved[b.id] == CGVector(dx: 0, dy: -28) && insert.moved[a.id] == nil, "shifted blocks slide from where they were")
        let remove = NoteCanvasTransition(from: before, to: layout([a, c]))
        expect(remove.removed == [b.id] && remove.merged.isEmpty, "removals are found")
        let merged = NoteCanvasTransition(from: before, to: layout([NoteBlock(.paragraph, text: "ab", id: a.id), c]))
        expect(merged.merged == [b.id], "merging into the previous block skips the fade")
        let taller = NoteCanvasLayout(page: NotePage(blocks: [a, b, c]), width: 1000, headerHeight: 100, metrics: NoteCanvasMetrics(),
                                      measure: NoteCanvasMeasure(height: { block, _ in block.id == a.id ? 52 : 26 },
                                                                 childIndent: { _ in 26 }))
        expect(!NoteCanvasTransition(from: before, to: taller).isStructural, "height-only changes never animate")
        let child = NoteBlock.paragraph("child")
        var toggle = NoteBlock(.toggle, text: "t", children: [child])
        let open = layout([toggle, c])
        toggle.props.expanded = false
        let closed = layout([toggle, c])
        let collapse = NoteCanvasTransition(from: open, to: closed)
        expect(collapse.concealed.first?.ids == [child.id] && collapse.removed.isEmpty, "collapsing conceals instead of removing")
        expect(collapse.concealed.first?.height == 28, "the concealed group remembers its height")
        let expand = NoteCanvasTransition(from: closed, to: open)
        expect(expand.revealed.first?.ids == [child.id] && expand.inserted.isEmpty, "expanding reveals instead of inserting")
        expect(expand.revealed.first?.top == open.frame(of: toggle.id)!.maxY, "reveals grow from the toggle row")
        let moved = NoteCanvasTransition(from: before, to: layout([c, a, b]))
        expect(moved.moved[c.id]?.dy == 56 && moved.inserted.isEmpty && moved.removed.isEmpty, "reorders slide")
    }

    static func fractions() {
        let even = NoteCanvasLayout.normalizedFractions([nil, nil], count: 2)
        expect(even == [0.5, 0.5], "missing widths split evenly")
        let mixed = NoteCanvasLayout.normalizedFractions([0.2, nil, 0.4], count: 3)
        expect(abs(mixed[0] - 0.2 / 0.9) < 0.0001 && abs(mixed.reduce(0, +) - 1) < 0.0001, "partial widths fill with the average")
        expect(NoteCanvasLayout.normalizedFractions([60, 40], count: 2) == [0.6, 0.4], "percentages normalize too")
        let resized = NoteCanvasLayout.resizedFractions([0.5, 0.5], divider: 0, delta: 100, available: 500, minimumWidth: 64)
        expect(abs(resized[0] - 0.7) < 0.0001 && abs(resized[1] - 0.3) < 0.0001, "dragging moves width between neighbours")
        let clamped = NoteCanvasLayout.resizedFractions([0.5, 0.5], divider: 0, delta: 1000, available: 500, minimumWidth: 64)
        expect(abs(clamped[1] - 64.0 / 500) < 0.0001, "columns keep a minimum width")
    }

    static func bigPage() {
        var blocks: [NoteBlock] = []
        for index in 0..<2000 {
            switch index % 7 {
            case 0: blocks.append(.heading(2, NoteText("Heading \(index)")))
            case 3: blocks.append(NoteBlock(.bulletedItem, text: NoteText("item \(index)"),
                                            children: [NoteBlock(.todo, text: NoteText("todo \(index)"))]))
            default: blocks.append(.paragraph(NoteText(String(repeating: "word ", count: index % 40))))
            }
        }
        let metrics = NoteCanvasMetrics()
        let result = NoteCanvasLayout(page: NotePage(blocks: blocks), width: 1100, headerHeight: 200, metrics: metrics,
                                      measure: NoteCanvasMeasure(height: { NoteCanvasEstimate.height(of: $0, width: $1, metrics: metrics) },
                                                                 childIndent: { _ in 26 }))
        expect(result.entries.count == 2000 + 2000 / 7 + 1, "every visible block gets an entry")
        var last: CGFloat = 0
        for row in result.flows[0] {
            let frame = result.entries[row].frame
            expect(frame.minY >= last && frame.height > 0, "rows stack downward without overlap")
            last = frame.maxY
        }
        let probe = result.entries[1500]
        expect(result.blockID(at: CGPoint(x: 500, y: probe.frame.midY)) == probe.id, "hit testing works deep in the page")
    }
}
