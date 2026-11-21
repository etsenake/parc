import Testing
@testable import ParcCore

struct SidebarOutlineLayoutFlushSkipTests {
    typealias Skip = SidebarOutlineLayoutFlushSkip

    @Test func identicalFramesWithACleanSubtreeSkipTheFlush() {
        #expect(!Skip.shouldFlush(frameChanged: false, needsLayout: false, subtreeNeedsLayout: false))
    }

    @Test func aMovedFrameStillFlushes() {
        #expect(Skip.shouldFlush(frameChanged: true, needsLayout: false, subtreeNeedsLayout: false))
    }

    @Test func anAlreadyDirtyOutlineStillFlushes() {
        #expect(Skip.shouldFlush(frameChanged: false, needsLayout: true, subtreeNeedsLayout: false))
    }

    @Test func aDirtyOutlineChildStillFlushes() {
        #expect(Skip.shouldFlush(frameChanged: false, needsLayout: false, subtreeNeedsLayout: true))
    }

    @Test func thePostFrameAssignFlushDefaultsFrameChangedToFalse() {
        #expect(Skip.shouldFlush(needsLayout: false, subtreeNeedsLayout: false) == false)
    }

    @Test func thePostFrameAssignFlushStillRunsWhenTheOutlineNeedsLayout() {
        #expect(Skip.shouldFlush(needsLayout: true, subtreeNeedsLayout: false))
    }
}
