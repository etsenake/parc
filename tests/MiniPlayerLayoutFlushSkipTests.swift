enum MiniPlayerLayoutFlushSkip {
    static func shouldFlush(
        frameChanged: Bool = false,
        needsLayout: Bool,
        subtreeNeedsLayout: Bool
    ) -> Bool {
        frameChanged || needsLayout || subtreeNeedsLayout
    }
}

@main
struct MiniPlayerLayoutFlushSkipTests {
    static var assertions = 0
    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        assertions += 1
        precondition(condition(), message)
    }

    @MainActor static func main() { exitOnFailure(runChecks) }
    @MainActor static func runChecks() {
        expect(!MiniPlayerLayoutFlushSkip.shouldFlush(
            frameChanged: false, needsLayout: false, subtreeNeedsLayout: false),
               "Identical frames with a clean subtree are a true no-op skip")
        expect(MiniPlayerLayoutFlushSkip.shouldFlush(
            frameChanged: true, needsLayout: false, subtreeNeedsLayout: false),
               "A moved mini-player frame must still flush layoutSubtree")
        expect(MiniPlayerLayoutFlushSkip.shouldFlush(
            frameChanged: false, needsLayout: true, subtreeNeedsLayout: false),
               "An already-dirty deck/row must still flush layoutSubtree")
        expect(MiniPlayerLayoutFlushSkip.shouldFlush(
            frameChanged: false, needsLayout: false, subtreeNeedsLayout: true),
               "A dirty child must still flush layoutSubtree")
        expect(MiniPlayerLayoutFlushSkip.shouldFlush(
            needsLayout: false, subtreeNeedsLayout: false) == false,
               "Post-sidebar flush defaults frameChanged to false")
        expect(MiniPlayerLayoutFlushSkip.shouldFlush(
            needsLayout: true, subtreeNeedsLayout: false),
               "Post-sidebar flush still runs when the deck/row needs layout")

        print("\(assertions) mini-player layout flush skip assertions passed")
    }
}
