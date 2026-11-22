import CoreGraphics
import Foundation
import Testing
@testable import ParcCore
@testable import ParcNotes

struct NoteCanvasLayoutTestsDecorations {
    private struct Washes {
        let a = NoteBlock.paragraph("a"), b = NoteBlock.paragraph("b"), c = NoteBlock.paragraph("c")
        let child = NoteBlock(.bulletedItem, text: "child")
        let parent: NoteBlock

        init() { parent = NoteBlock(.bulletedItem, text: "parent", children: [child]) }
    }

    private func washed() -> (Washes, NoteCanvasLayout) {
        let washes = Washes()
        return (washes, NoteCanvasLayoutTestsSupport.layout([washes.a, washes.b, washes.c, washes.parent]))
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

    private struct Decorated {
        let inside = NoteBlock.paragraph("inside")
        let quote: NoteBlock
        let callout = NoteBlock(.callout, text: "c", color: .background(.blue))
        var colored = NoteBlock.paragraph("tinted")

        init() {
            quote = NoteBlock(.quote, text: "q", color: .text(.red), children: [inside])
            colored.color = .background(.yellow)
        }
    }

    private func decorated() -> (Decorated, NoteCanvasLayout) {
        let decorated = Decorated()
        return (decorated, NoteCanvasLayoutTestsSupport.layout([decorated.quote, decorated.callout, decorated.colored]))
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

    private func embed(height: Double? = nil, source: String? = "https://www.youtube.com/watch?v=abc") -> NoteBlock {
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

    private func alert(_ name: String?, color: NoteColorStyle? = nil) -> NoteBlock {
        var callout = NoteBlock(.callout, text: "c", color: color)
        callout.props.alert = name
        return callout
    }

    @Test func aTipCalloutIsGreenByDefault() {
        let tip = alert("TIP")
        #expect(NoteCanvasLayoutTestsSupport.layout([tip]).decorations(of: [tip.id]).first?.style == .callout(.background(.green)))
    }

    @Test func alertNamesMatchInAnyCase() {
        let caution = alert("caution")
        #expect(NoteCanvasLayoutTestsSupport.layout([caution]).decorations(of: [caution.id]).first?.style == .callout(.background(.red)))
    }

    @Test func aChosenColourBeatsTheAlertDefault() {
        let warning = alert("WARNING", color: .background(.pink))
        #expect(NoteCanvasLayoutTestsSupport.layout([warning]).decorations(of: [warning.id]).first?.style == .callout(.background(.pink)))
    }

    @Test func aPlainCalloutKeepsTheHouseFill() {
        let plain = alert(nil)
        #expect(NoteCanvasLayoutTestsSupport.layout([plain]).decorations(of: [plain.id]).first?.style == .callout(nil))
    }
}
