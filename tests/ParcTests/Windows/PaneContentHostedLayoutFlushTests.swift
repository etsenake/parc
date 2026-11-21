import Testing
@testable import Parc

struct PaneContentHostedLayoutFlushTests {
    @Test func anIdenticalFrameWithCleanContentSkipsTheContentLayout() {
        #expect(!PaneContentHostedLayoutFlush.shouldLayoutContent(frameChanged: false, needsLayout: false))
    }

    @Test func aMovedContentFrameStillRunsTheContentLayout() {
        #expect(PaneContentHostedLayoutFlush.shouldLayoutContent(frameChanged: true, needsLayout: false))
    }

    @Test func anAlreadyDirtyContentStillRunsTheContentLayout() {
        #expect(PaneContentHostedLayoutFlush.shouldLayoutContent(frameChanged: false, needsLayout: true))
    }

    @Test func aCleanDirectChildSkipsItsSubtreeLayout() {
        #expect(!PaneContentHostedLayoutFlush.shouldLayoutChild(needsLayout: false))
    }

    @Test func aDirtyDirectChildStillFlushes() {
        #expect(PaneContentHostedLayoutFlush.shouldLayoutChild(needsLayout: true))
    }
}
