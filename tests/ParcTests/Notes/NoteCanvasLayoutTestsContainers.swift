import CoreGraphics
import Foundation
import Testing
@testable import ParcCore
@testable import ParcNotes

struct NoteCanvasLayoutTestsContainers {
    private struct CalloutIndentCase: Sendable, CustomTestStringConvertible {
        let alert: String?
        let icon: String?
        let x: CGFloat

        var testDescription: String { "alert \(alert ?? "none"), icon \(icon ?? "none")" }
    }

    private struct Toggled {
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
        #expect(NoteCanvasLayoutTestsSupport.layout([open.toggle, open.after]).entry(open.inner.id) != nil)
    }

    @Test func collapsedTogglesHideTheirDescendants() {
        let closed = Toggled(expanded: false)
        #expect(NoteCanvasLayoutTestsSupport.layout([closed.toggle, closed.after]).entry(closed.inner.id) == nil)
    }

    @Test func followingBlocksCloseTheGapUnderACollapsedToggle() {
        let closed = Toggled(expanded: false)
        #expect(NoteCanvasLayoutTestsSupport.layout([closed.toggle, closed.after]).frame(of: closed.after.id)?.minY == 132)
    }

    @Test func aCollapsedEntryKnowsItIsCollapsed() {
        let closed = Toggled(expanded: false)
        #expect(NoteCanvasLayoutTestsSupport.layout([closed.toggle, closed.after]).entry(closed.toggle.id)?.isCollapsed == true)
    }

    private struct Columned {
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

    private func columned() -> (Columned, NoteCanvasLayout) {
        let columned = Columned()
        return (columned, NoteCanvasLayoutTestsSupport.layout([NoteBlock.paragraph("before"), columned.row, columned.after]))
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
        let overridden = NoteCanvasLayoutTestsSupport.layout([columned.row], overrides: [columned.row.id: [0.5, 0.5]])
        #expect(overridden.frame(of: columned.left.id)?.width == (Columned.available * 0.5).rounded())
    }

    private struct Calloutd {
        let child = NoteBlock.paragraph("inside")
        let callout: NoteBlock
        let after = NoteBlock.paragraph("after")

        init() { callout = NoteBlock(.callout, text: "note", children: [child]) }
    }

    @Test func theCalloutRowSpansTheBox() {
        let callouts = Calloutd()
        #expect(NoteCanvasLayoutTestsSupport.layout([callouts.callout, callouts.after]).frame(of: callouts.callout.id) == CGRect(x: 140, y: 104, width: 720, height: 54))
    }

    @Test func calloutChildrenLineUpWithItsTextAndKeepTheRightPadding() {
        let callouts = Calloutd()
        #expect(NoteCanvasLayoutTestsSupport.layout([callouts.callout, callouts.after]).frame(of: callouts.child.id) == CGRect(x: 186, y: 160, width: 720 - 46 - 18, height: 26))
    }

    @Test func theBoxClosesUnderItsLastChild() {
        let callouts = Calloutd()
        #expect(NoteCanvasLayoutTestsSupport.layout([callouts.callout, callouts.after]).outerFrame(of: callouts.callout.id)?.maxY == 200)
    }

    @Test func theBlockAfterACalloutClearsTheBox() {
        let callouts = Calloutd()
        #expect(NoteCanvasLayoutTestsSupport.layout([callouts.callout, callouts.after]).frame(of: callouts.after.id)?.minY == 206)
    }

    @Test func quoteChildrenAlignWithTheQuoteText() {
        let quoteChild = NoteBlock.paragraph("quoted")
        let quote = NoteBlock(.quote, text: "q", children: [quoteChild])
        #expect(NoteCanvasLayoutTestsSupport.layout([quote]).frame(of: quoteChild.id)?.minX == 157)
    }

    private func calloutChildX(alert: String?, icon: String?) -> CGFloat? {
        let metrics = NoteCanvasMetrics()
        let byIcon = NoteCanvasMeasure(height: NoteCanvasLayoutTestsSupport.measure.height, childIndent: { metrics.childIndent(of: $0) })
        let child = NoteBlock.paragraph("inside")
        var callout = NoteBlock(.callout, text: "note", children: [child])
        callout.props.alert = alert
        callout.props.icon = icon
        let result = NoteCanvasLayout(page: NotePage(blocks: [callout]), width: 1000, headerHeight: 100, metrics: metrics,
                                      columnFractions: [:], measure: byIcon)
        return result.frame(of: child.id)?.minX
    }

    @Test(arguments: [
        CalloutIndentCase(alert: "TIP", icon: nil, x: 186.0),
        CalloutIndentCase(alert: "NOTE", icon: nil, x: 186),
        CalloutIndentCase(alert: nil, icon: "🔥", x: 186),
        CalloutIndentCase(alert: nil, icon: nil, x: 154),
        CalloutIndentCase(alert: "TIP", icon: "", x: 154),
        CalloutIndentCase(alert: "mystery", icon: nil, x: 154),
    ])
    private func aCalloutIconPushesItsChildrenPastIt(sample: CalloutIndentCase) {
        #expect(calloutChildX(alert: sample.alert, icon: sample.icon) == sample.x)
    }

    @Test func quotesAndListsKeepTheirIndents() {
        let metrics = NoteCanvasMetrics()
        #expect(metrics.childIndent(of: NoteBlock(.quote)) == metrics.quoteChildIndent)
        #expect(metrics.childIndent(of: NoteBlock(.bulletedItem)) == metrics.indentWidth)
    }

    private func alert(_ name: String?, color: NoteColorStyle? = nil) -> NoteBlock {
        var callout = NoteBlock(.callout, text: "c", color: color)
        callout.props.alert = name
        return callout
    }
}
