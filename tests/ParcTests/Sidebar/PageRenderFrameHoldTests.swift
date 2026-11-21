import AppKit
import ParcEngine
import ParcEngineDoubles
import Testing
@testable import Parc
@testable import ParcCore

@MainActor
struct PageRenderFrameHoldTests {
    @MainActor final class Renderer: NSView {
        private(set) var sentSizes: [CGSize] = []
        override func setFrameSize(_ newSize: NSSize) {
            if newSize != frame.size { sentSizes.append(newSize) }
            super.setFrameSize(newSize)
        }
    }

    @MainActor final class Content: NSView {
        var onLayout: (() -> Void)?
        override var isFlipped: Bool { true }
        override func layout() {
            super.layout()
            onLayout?()
        }
    }

    @MainActor final class Page {
        let renderer = Renderer(frame: .zero)
        let fixture: RenderFrameTestPage
        let browser: PCBrowserView
        let pane: PCNativeDevToolsPaneView

        init(reportsFrames: Bool = true, infobar: CGFloat = 0, docked: CGFloat = 0) {
            fixture = RenderFrameTestPage(renderer: renderer, reportsFrames: reportsFrames)
            fixture.infobarHeight = infobar
            browser = PCBrowserView(frame: .zero, adoptingNativePage: fixture.page as! PCNativePage)
            pane = PCNativeDevToolsPaneView(frame: browser.bounds)
            pane.autoresizingMask = [.width, .height]
            browser.addSubview(pane)
            fixture.host.frame = pane.bounds
            pane.addSubview(fixture.host)
            pane.inspected = fixture.host
            pane.dockedWidth = docked
        }

        func draw(_ viewport: CGSize? = nil) { fixture.draw(viewport ?? renderer.frame.size) }
    }

    @MainActor final class Stage {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1200, height: 700), styleMask: [.borderless], backing: .buffered, defer: true)
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 1200, height: 700))
        let content: Content
        let resizer = PageContentResizer()
        let page: Page

        init(width: CGFloat = 800, page: Page) {
            window.isReleasedWhenClosed = false
            root.wantsLayer = true
            window.contentView = root
            content = Content(frame: NSRect(x: 0, y: 0, width: width, height: 600))
            root.addSubview(content)
            self.page = page
            attach(page.browser, to: content, resizer)
            layout()
        }

        func pane(_ width: CGFloat) -> (Content, PageContentResizer) {
            let other = Content(frame: NSRect(x: 0, y: 0, width: width, height: 600))
            root.addSubview(other)
            return (other, PageContentResizer())
        }

        func attach(_ browser: PCBrowserView, to content: Content, _ resizer: PageContentResizer) {
            content.addSubview(browser)
            content.onLayout = { [weak resizer, weak browser, weak content] in
                guard let resizer, let browser, let content else { return }
                resizer.place(browser, in: content)
            }
            resizer.place(browser, in: content)
        }

        func layout() { root.layoutSubtreeIfNeeded() }

        func resize(_ width: CGFloat) {
            content.frame.size.width = width
            layout()
        }

        var hold: PageContentResizeHold { resizer.hold }
        var renderer: Renderer { page.renderer }
    }

    private static func size(_ width: CGFloat, _ height: CGFloat = 600) -> CGSize { CGSize(width: width, height: height) }
    private func size(_ width: CGFloat, _ height: CGFloat = 600) -> CGSize { Self.size(width, height) }

    private func docked() -> Stage { Stage(page: Page(infobar: 40, docked: 300)) }

    private func dragStarted() -> Stage {
        let stage = docked()
        stage.page.draw()
        stage.resizer.mode = .throttle
        stage.layout()
        return stage
    }

    private func firstReportArrived() -> Stage {
        let stage = dragStarted()
        stage.resize(790)
        stage.resize(780)
        stage.resize(770)
        stage.page.draw()
        return stage
    }

    private func secondReportArrived() -> Stage {
        let stage = firstReportArrived()
        stage.layout()
        stage.page.draw()
        stage.layout()
        return stage
    }

    private func olderReportArrived() -> Stage {
        let stage = secondReportArrived()
        stage.resize(770.5)
        stage.resize(760)
        stage.resize(750)
        stage.page.draw(size(480, 560))
        return stage
    }

    @Test func theRendererSitsBesideDevToolsBelowTheShelf() {
        let stage = docked()
        #expect(stage.page.browser.frame.size == size(800))
        #expect(stage.renderer.frame.size == size(500, 560))
    }

    @Test func anUnchangedPageSizeDoesNotRelayoutDockedToolsOrTheRenderer() {
        let stage = docked()
        let layouts = stage.page.pane.layouts
        stage.resizer.place(stage.page.browser, in: stage.content)
        #expect(stage.page.pane.layouts == layouts)
        #expect(stage.renderer.frame.size == size(500, 560))
    }

    @Test func anIntrinsicSizeChangeFlushesTheHostedSurfaceInTheSamePass() {
        let stage = docked()
        let layouts = stage.page.pane.layouts
        stage.resize(820)
        #expect(stage.page.browser.frame.size == size(820))
        #expect(stage.renderer.frame.size == size(520, 560))
        #expect(stage.page.pane.layouts == layouts + 1)
    }

    @Test func restoringTheIntrinsicSizeReturnsTheRendererToTheDockedSurface() {
        let stage = docked()
        stage.resize(820)
        stage.resize(800)
        #expect(stage.page.browser.frame.size == size(800))
        #expect(stage.renderer.frame.size == size(500, 560))
    }

    @Test func aDrawnPageHoldsNothingWhenTheDragStarts() {
        let stage = dragStarted()
        #expect(stage.page.fixture.liveObservations == 1)
        #expect(stage.hold.lockedSize == nil)
        #expect(stage.hold.pendingFrames.isEmpty)
    }

    @Test func theFirstStepReachesTheRendererAndHolds() {
        let stage = dragStarted()
        stage.resize(790)
        #expect(stage.hold.lockedSize == size(790))
        #expect(stage.renderer.frame.size == size(490, 560))
    }

    @Test func laterStepsWaitForTheRenderersFrame() {
        let stage = dragStarted()
        let sent = stage.renderer.sentSizes.count
        stage.resize(790)
        stage.resize(780)
        stage.resize(770)
        #expect(stage.renderer.sentSizes.count == sent + 1)
        #expect(stage.page.browser.frame.size == size(790))
    }

    @Test func aHeldSizeDoesNotRelayoutDockedTools() {
        let stage = dragStarted()
        stage.resize(790)
        let layouts = stage.page.pane.layouts
        stage.resize(780)
        stage.resize(770)
        #expect(stage.page.pane.layouts == layouts)
    }

    @Test func thatFramesReportMatchesAndReleases() {
        let stage = firstReportArrived()
        #expect(stage.hold.lockedSize == nil)
        #expect(stage.hold.pendingFrames.isEmpty)
    }

    @Test func theLatestSizeFollowsAndHolds() {
        let stage = firstReportArrived()
        stage.layout()
        #expect(stage.hold.lockedSize == size(770))
        #expect(stage.renderer.frame.size == size(470, 560))
    }

    @Test func eachReportSendsOneSizeAndNothingStaysQueued() {
        let before = dragStarted().renderer.sentSizes.count
        let stage = secondReportArrived()
        #expect(stage.hold.lockedSize == nil)
        #expect(stage.hold.pendingFrames.isEmpty)
        #expect(stage.renderer.sentSizes.count == before + 2)
    }

    @Test func aChangeWithinAPointFollowsLive() {
        let stage = secondReportArrived()
        stage.resize(770.5)
        #expect(stage.hold.lockedSize == nil)
        #expect(stage.page.browser.frame.size.width == 770.5)
    }

    @Test func anOlderFramesReportStillReleases() {
        let stage = olderReportArrived()
        #expect(stage.hold.lockedSize == nil)
        #expect(stage.hold.pendingFrames.isEmpty)
    }

    @Test func theLatestSizeIsHeldAfterAnOlderReport() {
        let stage = olderReportArrived()
        stage.layout()
        #expect(stage.hold.lockedSize == size(750))
    }

    @Test func theDragsEndFillsTheContent() {
        let stage = olderReportArrived()
        stage.layout()
        stage.resizer.mode = .intrinsic
        stage.layout()
        #expect(stage.page.fixture.liveObservations == 0)
        #expect(stage.page.browser.frame == stage.content.bounds)
        #expect(stage.renderer.frame.size == size(450, 560))
    }

    private func shelvedDragStarted() -> Stage {
        let stage = Stage(page: Page(infobar: 40))
        stage.page.draw()
        stage.resizer.mode = .throttle
        stage.layout()
        return stage
    }

    @Test func theShelfsHeightIsAddedBackToTheReport() {
        let stage = shelvedDragStarted()
        #expect(stage.hold.lockedSize == nil)
        #expect(stage.hold.pendingFrames.isEmpty)
    }

    @Test func aShelvedPagesFirstStepHolds() {
        let stage = shelvedDragStarted()
        stage.resize(760)
        #expect(stage.hold.lockedSize == size(760))
        #expect(stage.renderer.frame.size == size(760, 560))
    }

    @Test func aShelvedPagesReportReleasesIt() {
        let stage = shelvedDragStarted()
        stage.resize(760)
        stage.page.draw()
        stage.layout()
        #expect(stage.hold.lockedSize == nil)
        #expect(stage.page.browser.frame.size == size(760))
    }

    private func moved() -> (Stage, Content, PageContentResizer) {
        let stage = docked()
        let (target, targetResizer) = stage.pane(700)
        targetResizer.mode = .throttle
        stage.content.onLayout = nil
        stage.page.browser.removeFromSuperview()
        stage.layout()
        stage.page.draw()
        stage.attach(stage.page.browser, to: target, targetResizer)
        return (stage, target, targetResizer)
    }

    @Test func aMovedPageHoldsItsNewSizeUntilItsRendererDrawsIt() {
        let (stage, _, targetResizer) = moved()
        #expect(stage.page.fixture.liveObservations == 1)
        #expect(stage.renderer.frame.size == size(400, 560))
        #expect(targetResizer.hold.lockedSize == size(700))
    }

    @Test func aMovedPagesFirstReportReleasesIt() {
        let (stage, _, targetResizer) = moved()
        stage.page.draw()
        stage.layout()
        #expect(targetResizer.hold.lockedSize == nil)
        #expect(stage.page.browser.frame.size == size(700))
    }

    @Test func theOldPanesNextModeChangeDoesNotObserveTheMovedPage() {
        let (stage, _, _) = moved()
        stage.page.draw()
        stage.layout()
        stage.resizer.mode = .throttle
        #expect(stage.page.fixture.liveObservations == 1)
    }

    @Test func aPageWithoutFrameReportsStaysIntrinsic() {
        let stage = Stage(page: Page(reportsFrames: false))
        stage.resizer.mode = .throttle
        #expect(stage.hold.mode == .intrinsic)
        #expect(stage.page.fixture.liveObservations == 0)
    }

    @Test func everySizeReachesARendererWithoutFrameReports() {
        let stage = Stage(page: Page(reportsFrames: false))
        stage.resizer.mode = .throttle
        let before = stage.renderer.sentSizes.count
        for width in stride(from: 790, through: 750, by: -10) { stage.resize(CGFloat(width)) }
        #expect(stage.renderer.sentSizes.count == before + 5)
        #expect(stage.page.browser.frame.size == size(750))
    }
}
