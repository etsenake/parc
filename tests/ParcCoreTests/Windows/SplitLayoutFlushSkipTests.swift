import Testing
@testable import ParcCore

struct SplitLayoutFlushSkipTests {
    @Test func identicalFramesWithACleanSubtreeSkipTheFlush() {
        #expect(!SplitLayoutFlushSkip.shouldFlush(frameChanged: false, needsLayout: false, subtreeNeedsLayout: false))
    }

    @Test func aMovedFrameStillFlushes() {
        #expect(SplitLayoutFlushSkip.shouldFlush(frameChanged: true, needsLayout: false, subtreeNeedsLayout: false))
    }

    @Test func anAlreadyDirtyViewStillFlushes() {
        #expect(SplitLayoutFlushSkip.shouldFlush(frameChanged: false, needsLayout: true, subtreeNeedsLayout: false))
    }

    @Test func aDirtyChildStillFlushes() {
        #expect(SplitLayoutFlushSkip.shouldFlush(frameChanged: false, needsLayout: false, subtreeNeedsLayout: true))
    }

    @Test func theDropPathOwnerFlushDefaultsFrameChangedToFalse() {
        #expect(SplitLayoutFlushSkip.shouldFlush(needsLayout: false, subtreeNeedsLayout: false) == false)
    }

    @Test func theDropPathOwnerFlushStillRunsWhenTheSplitNeedsLayout() {
        #expect(SplitLayoutFlushSkip.shouldFlush(needsLayout: true, subtreeNeedsLayout: false))
    }

    @Test func theFirstDividerPanUpdateAppliesEvenWhenFactorsAreUnchanged() {
        #expect(SplitLayoutFlushSkip.shouldApplyDividerMove(factorsChanged: false, alreadyMoved: false))
    }

    @Test func laterIdenticalFactorMovesSkipApplyingFrames() {
        #expect(!SplitLayoutFlushSkip.shouldApplyDividerMove(factorsChanged: false, alreadyMoved: true))
    }

    @Test func aRealFactorChangeAppliesFramesAfterTheFirstMove() {
        #expect(SplitLayoutFlushSkip.shouldApplyDividerMove(factorsChanged: true, alreadyMoved: true))
    }

    @Test func theFirstRealFactorChangeAppliesFrames() {
        #expect(SplitLayoutFlushSkip.shouldApplyDividerMove(factorsChanged: true, alreadyMoved: false))
    }
}
