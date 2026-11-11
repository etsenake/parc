enum PaneContentHostedLayoutFlush {
    static func shouldLayoutContent(frameChanged: Bool, needsLayout: Bool) -> Bool {
        frameChanged || needsLayout
    }

    static func shouldLayoutChild(needsLayout: Bool) -> Bool {
        needsLayout
    }
}

@main
struct PaneContentHostedLayoutFlushTests {
    static var assertions = 0
    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        assertions += 1
        precondition(condition(), message)
    }

    static func main() {
        expect(!PaneContentHostedLayoutFlush.shouldLayoutContent(
            frameChanged: false, needsLayout: false),
               "Identical content frame with clean content skips content.layout")
        expect(PaneContentHostedLayoutFlush.shouldLayoutContent(
            frameChanged: true, needsLayout: false),
               "A moved content frame must still run content.layout / place")
        expect(PaneContentHostedLayoutFlush.shouldLayoutContent(
            frameChanged: false, needsLayout: true),
               "An already-dirty content must still run content.layout / place")

        expect(!PaneContentHostedLayoutFlush.shouldLayoutChild(needsLayout: false),
               "A clean direct child skips layoutSubtree (no Chromium walk)")
        expect(PaneContentHostedLayoutFlush.shouldLayoutChild(needsLayout: true),
               "A dirty direct child (page after size change, start/error) still flushes")

        print("\(assertions) pane-content hosted layout flush skip assertions passed")
    }
}
