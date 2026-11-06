/// Split drop layoutSubtree gates plus divider-drag identical-factor move skip.
@main
struct SplitLayoutFlushSkipTests {
    static var assertions = 0
    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        assertions += 1
        precondition(condition(), message)
    }

    static func main() {
        expect(!SplitLayoutFlushSkip.shouldFlush(
            frameChanged: false, needsLayout: false, subtreeNeedsLayout: false),
               "Identical frames with a clean subtree are a true no-op skip")
        expect(SplitLayoutFlushSkip.shouldFlush(
            frameChanged: true, needsLayout: false, subtreeNeedsLayout: false),
               "A moved pane/host frame must still flush layoutSubtree")
        expect(SplitLayoutFlushSkip.shouldFlush(
            frameChanged: false, needsLayout: true, subtreeNeedsLayout: false),
               "An already-dirty view must still flush layoutSubtree")
        expect(SplitLayoutFlushSkip.shouldFlush(
            frameChanged: false, needsLayout: false, subtreeNeedsLayout: true),
               "A dirty child must still flush layoutSubtree")
        expect(SplitLayoutFlushSkip.shouldFlush(
            needsLayout: false, subtreeNeedsLayout: false) == false,
               "Drop-path owner flush defaults frameChanged to false")
        expect(SplitLayoutFlushSkip.shouldFlush(
            needsLayout: true, subtreeNeedsLayout: false),
               "Drop-path owner flush still runs when the split needs layout")

        expect(SplitLayoutFlushSkip.shouldApplyDividerMove(
            factorsChanged: false, alreadyMoved: false),
               "First pan update materializes factors even when unchanged")
        expect(!SplitLayoutFlushSkip.shouldApplyDividerMove(
            factorsChanged: false, alreadyMoved: true),
               "Later identical-factor moves skip applyFrames")
        expect(SplitLayoutFlushSkip.shouldApplyDividerMove(
            factorsChanged: true, alreadyMoved: true),
               "A real factor change must still applyFrames")
        expect(SplitLayoutFlushSkip.shouldApplyDividerMove(
            factorsChanged: true, alreadyMoved: false),
               "The first real factor change must still applyFrames")

        print("\(assertions) split layout flush skip assertions passed")
    }
}
