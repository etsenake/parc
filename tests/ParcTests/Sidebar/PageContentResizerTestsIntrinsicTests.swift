import AppKit
import QuartzCore
import Testing
@testable import ParcCore
@testable import Parc

@MainActor
struct PageContentResizerTestsIntrinsicTests {
    private typealias Support = PageContentResizerTestsSupport
    private typealias Resizing = Support.Resizing

    private final class FillingChild: NSView {
        var layouts = 0
        override func layout() {
            super.layout()
            layouts += 1
            frame = superview?.bounds ?? frame
        }
    }

    @Test func intrinsicFillsTheContent() {
        let r = Resizing()
        #expect(r.page.autoresizingMask == [.width, .height])
        #expect(r.page.frame == r.content.bounds)
    }

    @Test func intrinsicResizesAtOnce() {
        let r = Resizing()
        r.resize(760)
        #expect(r.page.frame.size == Support.size(760))
        #expect(r.resizer.hold.pendingFrames.isEmpty)
    }

    @Test func hostedViewsThatSizeInLayoutFollowThePageImmediately() {
        let r = Resizing()
        let filler = FillingChild(frame: NSRect(x: 0, y: 0, width: 1, height: 1))
        r.page.addSubview(filler)
        r.resizer.place(r.page, in: r.content)
        #expect(filler.frame.size == r.page.frame.size)
    }

    @Test func anUnchangedPageSizeDoesNotRelayoutTheHostedSubtree() {
        let r = Resizing()
        let filler = FillingChild(frame: NSRect(x: 0, y: 0, width: 1, height: 1))
        r.page.addSubview(filler)
        r.resizer.place(r.page, in: r.content)
        let hostedLayouts = filler.layouts
        r.resizer.place(r.page, in: r.content)
        #expect(filler.layouts == hostedLayouts)
        #expect(filler.frame.size == r.page.frame.size)
    }

    @Test func aDirectHostedChildThatNoLongerFillsStillFlushesInTheSamePass() {
        let r = Resizing()
        let filler = FillingChild(frame: NSRect(x: 0, y: 0, width: 1, height: 1))
        r.page.addSubview(filler)
        r.resizer.place(r.page, in: r.content)
        let hostedLayouts = filler.layouts
        filler.frame = NSRect(x: 0, y: 0, width: 1, height: 1)
        filler.needsLayout = false
        r.resizer.place(r.page, in: r.content)
        #expect(filler.frame.size == r.page.frame.size)
        #expect(filler.layouts == hostedLayouts + 1)
    }

    @Test func aLaterSizeIsPushedIntoTheHostedSubtreeInTheSamePass() {
        let r = Resizing()
        let filler = FillingChild(frame: NSRect(x: 0, y: 0, width: 1, height: 1))
        r.page.addSubview(filler)
        r.resizer.place(r.page, in: r.content)
        let afterFill = filler.layouts
        r.content.frame.size.width = 740
        r.resizer.place(r.page, in: r.content)
        #expect(filler.frame.width == 740)
        #expect(filler.frame.size == r.page.frame.size)
        #expect(filler.layouts == afterFill + 1)
    }

    @Test func noReportKeepsThePageIntrinsic() {
        let r = Resizing()
        r.page.reports = false
        r.resizer.mode = .throttle
        #expect(r.resizer.hold.mode == .intrinsic)
        #expect(r.page.leases.isEmpty)
    }

    @Test func withoutTheReportEverySizeReachesThePage() {
        let r = Resizing()
        r.page.reports = false
        r.resizer.mode = .throttle
        let before = r.page.sentSizes.count
        for width in stride(from: 750, through: 700, by: -10) { r.resize(CGFloat(width)) }
        #expect(r.page.sentSizes.count == before + 6)
        #expect(r.page.frame.size == Support.size(700))
    }
}
