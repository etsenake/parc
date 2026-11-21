import CoreGraphics
import Foundation
import Testing
@testable import Parc
@testable import ParcCore

struct NoteCanvasLayoutTests {
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

    func layout(_ blocks: [NoteBlock], width: CGFloat = 1000, header: CGFloat = 100, fullWidth: Bool = false,
                overrides: [NoteBlockID: [CGFloat]] = [:]) -> NoteCanvasLayout {
        var metrics = NoteCanvasMetrics()
        metrics.fullWidth = fullWidth
        return NoteCanvasLayout(page: NotePage(blocks: blocks), width: width, headerHeight: header, metrics: metrics,
                                columnFractions: overrides, measure: Self.measure)
    }

    struct Stack {
        let a = NoteBlock.paragraph("a"), b = NoteBlock.paragraph("b"), h = NoteBlock.heading(1, "h"), c = NoteBlock.paragraph("c")
    }

    func stacked() -> (Stack, NoteCanvasLayout) {
        let stack = Stack()
        return (stack, layout([stack.a, stack.b, stack.h, stack.c]))
    }

    @Test func thePageColumnIs720WideAndCentred() {
        let (_, result) = stacked()
        #expect(result.columnX == 140)
        #expect(result.columnWidth == 720)
    }

    @Test func theFirstBlockSitsUnderTheHeader() {
        let (stack, result) = stacked()
        #expect(result.frame(of: stack.a.id) == CGRect(x: 140, y: 104, width: 720, height: 26))
    }

    @Test func paragraphsKeepATwoPointGap() {
        let (stack, result) = stacked()
        #expect(result.frame(of: stack.b.id)?.minY == 132)
    }

    @Test func aHeadingTakesItsOwnBreathingRoom() {
        let (stack, result) = stacked()
        #expect(result.frame(of: stack.h.id)?.minY == 170)
    }

    @Test func theBlockAfterAHeadingGetsTheHeadingsAfterSpace() {
        let (stack, result) = stacked()
        #expect(result.frame(of: stack.c.id)?.minY == 214)
    }

    @Test func contentEndsAtTheLastBlock() {
        #expect(stacked().1.contentBottom == 240)
    }

    @Test func fullWidthKeeps96PointMargins() {
        let wide = layout([.paragraph("a")], width: 1400, fullWidth: true)
        #expect(wide.columnWidth == 1208)
        #expect(wide.columnX == 96)
    }

    @Test func narrowPanesShrinkTheMarginsFirst() {
        let narrow = layout([.paragraph("a")], width: 600)
        #expect(narrow.columnWidth == 544)
        #expect(narrow.columnX == 28)
    }

    @Test func noHeaderMeansTheTopInset() {
        let block = NoteBlock.paragraph("a")
        #expect(layout([block], header: 0).frame(of: block.id)?.minY == NoteCanvasMetrics().topInset)
    }

    @Test func shortPagesFillTheViewport() {
        #expect(stacked().1.documentHeight(viewportHeight: 800) == 800)
    }

    @Test func longPagesGetBottomRoom() {
        #expect(stacked().1.documentHeight(viewportHeight: 100) == 400)
    }

    struct Nest {
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

    func nested() -> (Nest, NoteCanvasLayout) {
        let nest = Nest()
        return (nest, layout([nest.parent, nest.after]))
    }

    @Test func childrenIndentByTheIndentWidth() {
        let (nest, result) = nested()
        #expect(result.frame(of: nest.middle.id)?.minX == 166)
    }

    @Test func grandchildrenIndentAgainAndKeepTheRightEdge() {
        let (nest, result) = nested()
        #expect(result.frame(of: nest.grandchild.id)?.minX == 192)
        #expect(result.frame(of: nest.grandchild.id)?.width == 668)
    }

    @Test func childrenFollowTheirParentRow() {
        let (nest, result) = nested()
        #expect(result.frame(of: nest.middle.id)?.minY == 132)
    }

    @Test func theOuterFrameWrapsTheDescendants() {
        let (nest, result) = nested()
        #expect(result.outerFrame(of: nest.parent.id)?.maxY == 186)
    }

    @Test func theNextSiblingFollowsTheSubtree() {
        let (nest, result) = nested()
        #expect(result.frame(of: nest.after.id)?.minY == 188)
    }

    @Test func hitTestingFindsTheDeepestRow() {
        let (nest, result) = nested()
        #expect(result.blockID(at: CGPoint(x: 150, y: 140)) == nest.middle.id)
    }

    @Test func rowsReachIntoTheMargins() {
        let (nest, result) = nested()
        #expect(result.blockID(at: CGPoint(x: 20, y: 110)) == nest.parent.id)
    }

    @Test func theHeaderIsNotABlock() {
        #expect(nested().1.blockID(at: CGPoint(x: 300, y: 50)) == nil)
    }

    @Test func theSpaceBelowTheLastBlockIsEmpty() {
        #expect(nested().1.blockID(at: CGPoint(x: 300, y: 600)) == nil)
    }

    @Test func theGutterSitsLeftOfTheRow() {
        let (nest, result) = nested()
        #expect(result.gutterRect(for: nest.middle.id) == CGRect(x: 120, y: 132, width: 46, height: 26))
    }

    @Test func ancestorsWalkUp() {
        let (nest, result) = nested()
        #expect(result.ancestors(of: nest.grandchild.id) == [nest.middle.id, nest.parent.id])
    }

    @Test func aMarqueePicksRowsItTouches() {
        let (nest, result) = nested()
        #expect(result.blockIDs(in: CGRect(x: 0, y: 131, width: 1000, height: 31)) == [nest.middle.id, nest.grandchild.id])
    }

    @Test func numberingCountsRunsAndRestartsAfterABreak() {
        var numbered = (1...3).map { NoteBlock(.numberedItem, text: NoteText("n\($0)")) }
        numbered[0].props.listStart = 4
        let list = layout(numbered + [NoteBlock.paragraph("x"), NoteBlock(.numberedItem, text: "again")])
        #expect(list.entries.compactMap(\.listOrdinal) == [4, 5, 6, 1])
    }

    struct Toggled {
        let inner = NoteBlock.paragraph("inner")
        let after = NoteBlock.paragraph("after")
        var toggle: NoteBlock

        init(expanded: Bool) {
            toggle = NoteBlock(.toggle, text: "toggle", children: [inner])
            toggle.props.expanded = expanded
        }
    }

    @Test func openTogglesShowChildren() {
        let open = Toggled(expanded: true)
        #expect(layout([open.toggle, open.after]).entry(open.inner.id) != nil)
    }

    @Test func collapsedTogglesHideTheirDescendants() {
        let closed = Toggled(expanded: false)
        #expect(layout([closed.toggle, closed.after]).entry(closed.inner.id) == nil)
    }

    @Test func followingBlocksCloseTheGapUnderACollapsedToggle() {
        let closed = Toggled(expanded: false)
        #expect(layout([closed.toggle, closed.after]).frame(of: closed.after.id)?.minY == 132)
    }

    @Test func aCollapsedEntryKnowsItIsCollapsed() {
        let closed = Toggled(expanded: false)
        #expect(layout([closed.toggle, closed.after]).entry(closed.toggle.id)?.isCollapsed == true)
    }

    struct Columned {
        let left = NoteBlock.paragraph("left")
        let rightTop = NoteBlock.paragraph("right top"), rightBottom = NoteBlock.paragraph("right bottom")
        let after = NoteBlock.paragraph("after")
        let columnA: NoteBlock
        let row: NoteBlock

        init() {
            columnA = NoteBlock(.column, children: [left])
            var weighted = columnA
            weighted.props.width = 0.25
            var heavy = NoteBlock(.column, children: [rightTop, rightBottom])
            heavy.props.width = 0.75
            row = NoteBlock(.columns, children: [weighted, heavy])
        }

        static let available: CGFloat = 720 - 46
    }

    func columned() -> (Columned, NoteCanvasLayout) {
        let columned = Columned()
        return (columned, layout([NoteBlock.paragraph("before"), columned.row, columned.after]))
    }

    @Test func aColumnRowIsAsTallAsItsTallestColumn() throws {
        let (columned, result) = columned()
        let frame = try #require(result.frame(of: columned.row.id))
        #expect(frame.minY == 134)
        #expect(frame.height == 54)
    }

    @Test func columnWidthsFollowTheFractions() throws {
        let (columned, result) = columned()
        let frame = try #require(result.frame(of: columned.left.id))
        #expect(frame.minX == 140)
        #expect(frame.width == (Columned.available * 0.25).rounded())
    }

    @Test func theSecondColumnStartsAfterTheGapAndEndsAtThePageEdge() throws {
        let (columned, result) = columned()
        let frame = try #require(result.frame(of: columned.rightTop.id))
        #expect(abs(frame.minX - (140 + (Columned.available * 0.25).rounded() + 46)) < 0.5)
        #expect(frame.maxX == 860)
    }

    @Test func columnsStackTheirOwnChildren() {
        let (columned, result) = columned()
        #expect(result.frame(of: columned.rightBottom.id)?.minY == 162)
    }

    @Test func theNextBlockClearsTheRow() {
        let (columned, result) = columned()
        #expect(result.frame(of: columned.after.id)?.minY == 192)
    }

    @Test func columnEntriesSpanTheRow() {
        let (columned, result) = columned()
        #expect(result.frame(of: columned.columnA.id) == CGRect(x: 140, y: 134, width: (Columned.available * 0.25).rounded(), height: 54))
    }

    @Test func xPicksTheColumnAndYTheRow() {
        let (columned, result) = columned()
        #expect(result.blockID(at: CGPoint(x: 700, y: 165)) == columned.rightBottom.id)
    }

    @Test func shortColumnsLeaveEmptyRoom() {
        #expect(columned().1.blockID(at: CGPoint(x: 150, y: 175)) == nil)
    }

    @Test func gapsSitBetweenColumns() throws {
        let (columned, result) = columned()
        #expect(try #require(result.columnsRows[columned.row.id]).gapRect(after: 0).width == 46)
    }

    @Test func liveOverridesWinOverStoredWidths() {
        let columned = Columned()
        let overridden = layout([columned.row], overrides: [columned.row.id: [0.5, 0.5]])
        #expect(overridden.frame(of: columned.left.id)?.width == (Columned.available * 0.5).rounded())
    }

    struct Calloutd {
        let child = NoteBlock.paragraph("inside")
        let callout: NoteBlock
        let after = NoteBlock.paragraph("after")

        init() { callout = NoteBlock(.callout, text: "note", children: [child]) }
    }

    @Test func theCalloutRowSpansTheBox() {
        let callouts = Calloutd()
        #expect(layout([callouts.callout, callouts.after]).frame(of: callouts.callout.id) == CGRect(x: 140, y: 104, width: 720, height: 54))
    }

    @Test func calloutChildrenLineUpWithItsTextAndKeepTheRightPadding() {
        let callouts = Calloutd()
        #expect(layout([callouts.callout, callouts.after]).frame(of: callouts.child.id) == CGRect(x: 186, y: 160, width: 720 - 46 - 18, height: 26))
    }

    @Test func theBoxClosesUnderItsLastChild() {
        let callouts = Calloutd()
        #expect(layout([callouts.callout, callouts.after]).outerFrame(of: callouts.callout.id)?.maxY == 200)
    }

    @Test func theBlockAfterACalloutClearsTheBox() {
        let callouts = Calloutd()
        #expect(layout([callouts.callout, callouts.after]).frame(of: callouts.after.id)?.minY == 206)
    }

    @Test func quoteChildrenAlignWithTheQuoteText() {
        let quoteChild = NoteBlock.paragraph("quoted")
        let quote = NoteBlock(.quote, text: "q", children: [quoteChild])
        #expect(layout([quote]).frame(of: quoteChild.id)?.minX == 157)
    }

    func calloutChildX(alert: String?, icon: String?) -> CGFloat? {
        let metrics = NoteCanvasMetrics()
        let byIcon = NoteCanvasMeasure(height: Self.measure.height, childIndent: { metrics.childIndent(of: $0) })
        let child = NoteBlock.paragraph("inside")
        var callout = NoteBlock(.callout, text: "note", children: [child])
        callout.props.alert = alert
        callout.props.icon = icon
        let result = NoteCanvasLayout(page: NotePage(blocks: [callout]), width: 1000, headerHeight: 100, metrics: metrics,
                                      columnFractions: [:], measure: byIcon)
        return result.frame(of: child.id)?.minX
    }

    @Test(arguments: [
        ("TIP", nil, 186.0), ("NOTE", nil, 186), (nil, "🔥", 186), (nil, nil, 154), ("TIP", "", 154), ("mystery", nil, 154),
    ] as [(String?, String?, CGFloat)])
    func aCalloutIconPushesItsChildrenPastIt(alert: String?, icon: String?, x: CGFloat) {
        #expect(calloutChildX(alert: alert, icon: icon) == x)
    }

    @Test func quotesAndListsKeepTheirIndents() {
        let metrics = NoteCanvasMetrics()
        #expect(metrics.childIndent(of: NoteBlock(.quote)) == metrics.quoteChildIndent)
        #expect(metrics.childIndent(of: NoteBlock(.bulletedItem)) == metrics.indentWidth)
    }

    struct Drops {
        let a = NoteBlock(.bulletedItem, text: "a")
        let nested = NoteBlock(.bulletedItem, text: "nested")
        let b: NoteBlock
        let c = NoteBlock.paragraph("c")
        let moving = NoteBlock.paragraph("moving")

        init() { b = NoteBlock(.bulletedItem, text: "b", children: [nested]) }
    }

    func dropLayout() -> (Drops, NoteCanvasLayout) {
        let drops = Drops()
        return (drops, layout([drops.a, drops.b, drops.c, drops.moving]))
    }

    func target(_ result: NoteCanvasLayout, y: CGFloat, dragging: [NoteBlockID], leadingX: CGFloat? = nil) -> NoteCanvasDropTarget? {
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
        #expect(layout([heading, .paragraph("moving")]).frame(of: kid.id)?.minX == 166)
    }

    @Test func aHeadingWithChildrenTakesDropsAsItsFirstChild() throws {
        let moving = NoteBlock.paragraph("moving")
        var heading = NoteBlock.heading(2, "head")
        heading.children = [.paragraph("kid")]
        let headed = layout([heading, moving])
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
        let toggled = layout([closed, moving])
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

    struct Plain {
        let a = NoteBlock.paragraph("a"), b = NoteBlock.paragraph("b"), moving = NoteBlock.paragraph("moving")
    }

    func plainLayout() -> (Plain, NoteCanvasLayout) {
        let plain = Plain()
        return (plain, layout([plain.a, plain.b, plain.moving]))
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
        let nested = layout([NoteBlock(.bulletedItem, text: "parent", children: [child]), moving])
        let frame = try #require(nested.frame(of: child.id))
        #expect(nested.dropTarget(at: CGPoint(x: 840, y: frame.midY + 2), dragging: [moving.id])?.isVertical == false)
    }

    struct Columns {
        let x = NoteBlock.paragraph("x"), y = NoteBlock.paragraph("y"), moving = NoteBlock.paragraph("moving")
        let row: NoteBlock

        init() { row = NoteBlock(.columns, children: [NoteBlock(.column, children: [x]), NoteBlock(.column, children: [y])]) }
    }

    @Test func aColumnChildsEdgeAddsAColumn() throws {
        let columns = Columns()
        let result = layout([columns.row, columns.moving])
        let frame = try #require(result.frame(of: columns.x.id))
        #expect(result.dropTarget(at: CGPoint(x: frame.maxX - 10, y: frame.midY), dragging: [columns.moving.id])?.action == .placeBeside(columns.x.id, .right))
    }

    @Test func theColumnLineSitsInTheGapAndSpansTheRow() throws {
        let columns = Columns()
        let result = layout([columns.row, columns.moving])
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
        let crowded = layout([full, moving])
        let frame = try #require(crowded.frame(of: full.children[0].children[0].id))
        #expect(crowded.dropTarget(at: CGPoint(x: frame.maxX - 2, y: frame.midY), dragging: [moving.id])?.isVertical == false)
    }

    @Test func columnsNeverNestInsideColumns() throws {
        let columns = Columns()
        let result = layout([columns.row, columns.moving])
        let frame = try #require(result.frame(of: columns.moving.id))
        #expect(result.dropTarget(at: CGPoint(x: 60, y: frame.midY), dragging: [columns.row.id])?.isVertical == false)
    }

    @Test func plainTextPagesNeverMakeColumns() throws {
        let plain = Plain()
        let flat = NoteCanvasLayout(page: NotePage(blocks: [plain.a, plain.b, plain.moving]), width: 1000, headerHeight: 100,
                                    metrics: NoteCanvasMetrics(), flat: true, measure: Self.measure)
        let frame = try #require(flat.frame(of: plain.a.id))
        #expect(flat.dropTarget(at: CGPoint(x: 60, y: frame.midY), dragging: [plain.moving.id])?.isVertical == false)
    }

    @Test func plainTextPagesNeverNestLines() throws {
        let plain = Plain()
        let flat = NoteCanvasLayout(page: NotePage(blocks: [plain.a, plain.b, plain.moving]), width: 1000, headerHeight: 100,
                                    metrics: NoteCanvasMetrics(), flat: true, measure: Self.measure)
        let frame = try #require(flat.frame(of: plain.a.id))
        #expect(flat.dropTarget(at: CGPoint(x: 820, y: frame.maxY - 2), dragging: [plain.moving.id], leadingX: 220)?.action == .move(.after(plain.a.id)))
    }

    struct Washes {
        let a = NoteBlock.paragraph("a"), b = NoteBlock.paragraph("b"), c = NoteBlock.paragraph("c")
        let child = NoteBlock(.bulletedItem, text: "child")
        let parent: NoteBlock

        init() { parent = NoteBlock(.bulletedItem, text: "parent", children: [child]) }
    }

    func washed() -> (Washes, NoteCanvasLayout) {
        let washes = Washes()
        return (washes, layout([washes.a, washes.b, washes.c, washes.parent]))
    }

    @Test func neighboursShareOneWash() {
        let (washes, result) = washed()
        let joined = result.washRects(for: [washes.a.id, washes.b.id])
        #expect(joined.count == 1)
        #expect(joined.first?.key == washes.a.id)
    }

    @Test func theWashCoversBothBlocksPlusItsOutset() {
        let (washes, result) = washed()
        #expect(result.washRects(for: [washes.a.id, washes.b.id]).first?.rect == CGRect(x: 136, y: 103, width: 728, height: 56))
    }

    @Test func aGapSplitsTheWash() {
        let (washes, result) = washed()
        #expect(result.washRects(for: [washes.a.id, washes.c.id]).count == 2)
    }

    @Test func selectingAParentWashesItsChildrenOnce() {
        let (washes, result) = washed()
        let family = result.washRects(for: [washes.parent.id, washes.child.id])
        #expect(family.count == 1)
        #expect(family.first?.rect.maxY == (result.outerFrame(of: washes.parent.id)?.maxY ?? 0) + 1)
    }

    @Test func unknownIDsWashNothing() {
        #expect(washed().1.washRects(for: [NoteBlockID()]).isEmpty)
    }

    struct Decorated {
        let inside = NoteBlock.paragraph("inside")
        let quote: NoteBlock
        let callout = NoteBlock(.callout, text: "c", color: .background(.blue))
        var colored = NoteBlock.paragraph("tinted")

        init() {
            quote = NoteBlock(.quote, text: "q", color: .text(.red), children: [inside])
            colored.color = .background(.yellow)
        }
    }

    func decorated() -> (Decorated, NoteCanvasLayout) {
        let decorated = Decorated()
        return (decorated, layout([decorated.quote, decorated.callout, decorated.colored]))
    }

    @Test func quoteBarsTakeTheQuotesTextColour() {
        let (decorated, result) = decorated()
        let bar = result.decorations(in: CGRect(x: 0, y: 0, width: 1000, height: 2000)).first { $0.key == .init(owner: decorated.quote.id, slot: 1) }
        #expect(bar?.style == .quoteBar(.red))
    }

    @Test func theBarContinuesBesideTheQuotesChildren() {
        let (decorated, result) = decorated()
        let bar = result.decorations(in: CGRect(x: 0, y: 0, width: 1000, height: 2000)).first { $0.key == .init(owner: decorated.quote.id, slot: 1) }
        #expect(bar?.rect.minY == result.frame(of: decorated.quote.id)?.maxY)
        #expect(bar?.rect.maxY == result.outerFrame(of: decorated.quote.id)?.maxY)
    }

    @Test func calloutsGetTheirBox() {
        let (decorated, result) = decorated()
        let all = result.decorations(in: CGRect(x: 0, y: 0, width: 1000, height: 2000))
        #expect(all.contains { $0.style == .callout(.background(.blue)) && $0.rect == result.outerFrame(of: decorated.callout.id) })
    }

    @Test func backgroundColoursGetAFill() {
        let all = decorated().1.decorations(in: CGRect(x: 0, y: 0, width: 1000, height: 2000))
        #expect(all.contains { $0.style == .background(.yellow) })
    }

    @Test func barsDrawAboveFills() {
        #expect(decorated().1.decorations(in: CGRect(x: 0, y: 0, width: 1000, height: 2000)).last?.key.slot == 1)
    }

    @Test func regionsFilterDecorations() {
        #expect(decorated().1.decorations(in: CGRect(x: 0, y: 1500, width: 10, height: 10)).isEmpty)
    }

    @Test func oneBlocksDecorationsOnRequest() {
        let (decorated, result) = decorated()
        #expect(result.decorations(of: [decorated.callout.id]).map(\.style) == [.callout(.background(.blue))])
    }

    @Test func plainBlocksHaveNoDecorations() {
        let (decorated, result) = decorated()
        #expect(result.decorations(of: [decorated.inside.id]).isEmpty)
    }

    func embed(height: Double? = nil, source: String? = "https://www.youtube.com/watch?v=abc") -> NoteBlock {
        var embed = NoteBlock(.embed)
        embed.props.source = source
        embed.props.height = height
        return embed
    }

    @Test func anUnshownEmbedIsGuessedAtItsRealDefaultHeight() {
        #expect(NoteCanvasEstimate.height(of: embed(), width: 720, metrics: NoteCanvasMetrics()) == 458)
    }

    @Test func anEmbedWithAStoredHeightIsGuessedAtIt() {
        #expect(NoteCanvasEstimate.height(of: embed(height: 600), width: 720, metrics: NoteCanvasMetrics()) == 638)
    }

    @Test func anEmptyEmbedIsJustItsLinkField() {
        #expect(NoteCanvasEstimate.height(of: NoteBlock(.embed), width: 720, metrics: NoteCanvasMetrics()) == 60)
    }

    func alert(_ name: String?, color: NoteColorStyle? = nil) -> NoteBlock {
        var callout = NoteBlock(.callout, text: "c", color: color)
        callout.props.alert = name
        return callout
    }

    @Test func aTipCalloutIsGreenByDefault() {
        let tip = alert("TIP")
        #expect(layout([tip]).decorations(of: [tip.id]).first?.style == .callout(.background(.green)))
    }

    @Test func alertNamesMatchInAnyCase() {
        let caution = alert("caution")
        #expect(layout([caution]).decorations(of: [caution.id]).first?.style == .callout(.background(.red)))
    }

    @Test func aChosenColourBeatsTheAlertDefault() {
        let warning = alert("WARNING", color: .background(.pink))
        #expect(layout([warning]).decorations(of: [warning.id]).first?.style == .callout(.background(.pink)))
    }

    @Test func aPlainCalloutKeepsTheHouseFill() {
        let plain = alert(nil)
        #expect(layout([plain]).decorations(of: [plain.id]).first?.style == .callout(nil))
    }

    struct Moves {
        let a = NoteBlock.paragraph("a"), b = NoteBlock.paragraph("b"), c = NoteBlock.paragraph("c")
    }

    @Test func insertionsAreFound() {
        let moves = Moves()
        let inserted = NoteBlock.paragraph("new")
        let insert = NoteCanvasTransition(from: layout([moves.a, moves.b, moves.c]), to: layout([moves.a, inserted, moves.b, moves.c]))
        #expect(insert.isStructural)
        #expect(insert.inserted == [inserted.id])
    }

    @Test func shiftedBlocksSlideFromWhereTheyWere() {
        let moves = Moves()
        let insert = NoteCanvasTransition(from: layout([moves.a, moves.b, moves.c]), to: layout([moves.a, .paragraph("new"), moves.b, moves.c]))
        #expect(insert.moved[moves.b.id] == CGVector(dx: 0, dy: -28))
        #expect(insert.moved[moves.a.id] == nil)
    }

    @Test func removalsAreFound() {
        let moves = Moves()
        let remove = NoteCanvasTransition(from: layout([moves.a, moves.b, moves.c]), to: layout([moves.a, moves.c]))
        #expect(remove.removed == [moves.b.id])
        #expect(remove.merged.isEmpty)
    }

    @Test func mergingIntoThePreviousBlockSkipsTheFade() {
        let moves = Moves()
        let merged = NoteCanvasTransition(from: layout([moves.a, moves.b, moves.c]),
                                          to: layout([NoteBlock(.paragraph, text: "ab", id: moves.a.id), moves.c]))
        #expect(merged.merged == [moves.b.id])
    }

    @Test func heightOnlyChangesNeverAnimate() {
        let moves = Moves()
        let taller = NoteCanvasLayout(page: NotePage(blocks: [moves.a, moves.b, moves.c]), width: 1000, headerHeight: 100, metrics: NoteCanvasMetrics(),
                                      measure: NoteCanvasMeasure(height: { block, _ in block.id == moves.a.id ? 52 : 26 }, childIndent: { _ in 26 }))
        #expect(!NoteCanvasTransition(from: layout([moves.a, moves.b, moves.c]), to: taller).isStructural)
    }

    struct Collapsing {
        let child = NoteBlock.paragraph("child")
        let after = NoteBlock.paragraph("c")
        let toggleID: NoteBlockID
        let open: NoteCanvasLayout
        let closed: NoteCanvasLayout

        init(layout: ([NoteBlock]) -> NoteCanvasLayout) {
            var toggle = NoteBlock(.toggle, text: "t", children: [child])
            toggleID = toggle.id
            open = layout([toggle, after])
            toggle.props.expanded = false
            closed = layout([toggle, after])
        }
    }

    @Test func collapsingConcealsInsteadOfRemoving() {
        let collapsing = Collapsing { layout($0) }
        let collapse = NoteCanvasTransition(from: collapsing.open, to: collapsing.closed)
        #expect(collapse.concealed.first?.ids == [collapsing.child.id])
        #expect(collapse.removed.isEmpty)
    }

    @Test func theConcealedGroupRemembersItsHeight() {
        let collapsing = Collapsing { layout($0) }
        #expect(NoteCanvasTransition(from: collapsing.open, to: collapsing.closed).concealed.first?.height == 28)
    }

    @Test func expandingRevealsInsteadOfInserting() {
        let collapsing = Collapsing { layout($0) }
        let expand = NoteCanvasTransition(from: collapsing.closed, to: collapsing.open)
        #expect(expand.revealed.first?.ids == [collapsing.child.id])
        #expect(expand.inserted.isEmpty)
    }

    @Test func revealsGrowFromTheToggleRow() {
        let collapsing = Collapsing { layout($0) }
        let expand = NoteCanvasTransition(from: collapsing.closed, to: collapsing.open)
        #expect(expand.revealed.first?.top == collapsing.open.frame(of: collapsing.toggleID)?.maxY)
    }

    @Test func reordersSlide() {
        let moves = Moves()
        let moved = NoteCanvasTransition(from: layout([moves.a, moves.b, moves.c]), to: layout([moves.c, moves.a, moves.b]))
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

    func bigPage() -> NoteCanvasLayout {
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
