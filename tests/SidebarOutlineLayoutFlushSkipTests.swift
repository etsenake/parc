/// 797f2a55 leftover: forced sidebar outline/list layoutSubtree flushes only
/// when geometry moved or the subtree is already dirty. Identical frames with
/// a clean tree stay a true no-op.
///
/// Compiles against Sources/ParcCore/SidebarOutlineLayoutFlushSkip.swift;
/// `tests/SidebarOutlineLayoutFlushSkip/check.py` locks production call sites.
@main
struct SidebarOutlineLayoutFlushSkipTests {
    static var assertions = 0
    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        assertions += 1
        precondition(condition(), message)
    }

    static func main() {
        expect(!SidebarOutlineLayoutFlushSkip.shouldFlush(
            frameChanged: false, needsLayout: false, subtreeNeedsLayout: false),
               "Identical outline frames with a clean subtree are a true no-op skip")
        expect(SidebarOutlineLayoutFlushSkip.shouldFlush(
            frameChanged: true, needsLayout: false, subtreeNeedsLayout: false),
               "A moved outline/list frame must still flush layoutSubtree")
        expect(SidebarOutlineLayoutFlushSkip.shouldFlush(
            frameChanged: false, needsLayout: true, subtreeNeedsLayout: false),
               "An already-dirty outline must still flush layoutSubtree")
        expect(SidebarOutlineLayoutFlushSkip.shouldFlush(
            frameChanged: false, needsLayout: false, subtreeNeedsLayout: true),
               "A dirty outline child must still flush layoutSubtree")
        expect(SidebarOutlineLayoutFlushSkip.shouldFlush(
            needsLayout: false, subtreeNeedsLayout: false) == false,
               "Post-frame-assign flush defaults frameChanged to false")
        expect(SidebarOutlineLayoutFlushSkip.shouldFlush(
            needsLayout: true, subtreeNeedsLayout: false),
               "Post-frame-assign flush still runs when the outline needs layout")

        print("\(assertions) sidebar outline layout flush skip assertions passed")
    }
}
