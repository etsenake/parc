import AppKit

private final class Token {}

@main
struct DebuggerWarningTests {
    static func main() {
        var assertions = 0
        func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
            assertions += 1
            precondition(condition(), message)
        }

        expect(DebuggerWarningLayout.rowHeight == DeveloperToolbarLayout.height, "Rows share the Developer Mode strip height")
        expect(DebuggerWarningLayout.height(rows: 0) == 0, "No warning takes no room")
        expect(DebuggerWarningLayout.height(rows: 2) == 80, "Each extension's warning gets its own row")

        let wide = DebuggerWarningLayout.frames(in: NSRect(x: 0, y: 0, width: 800, height: 40), cancelWidth: 66)
        expect(wide.close == NSRect(x: 766, y: 6, width: 28, height: 28), "Hide sits 6 in at the trailing edge, centred")
        expect(wide.cancel == NSRect(x: 696, y: 7, width: 66, height: 26), "Cancel sits 4 before Hide, 26 high and centred")
        expect(wide.showsIcon && wide.icon == NSRect(x: 12, y: 12, width: 16, height: 16), "The icon leads 12 in")
        expect(wide.message.minX == 36 && wide.message.maxX == 684, "The message fills the room between icon and Cancel")

        let narrow = DebuggerWarningLayout.frames(in: NSRect(x: 0, y: 0, width: 150, height: 40), cancelWidth: 66)
        expect(!narrow.showsIcon && narrow.icon == .zero, "A narrow pane drops the icon before the message")
        expect(narrow.message.minX == 12 && narrow.message.width >= 0, "The message then starts at the leading inset")
        expect(narrow.cancel.width == 66 && narrow.close.width == 28, "Cancel and Hide never shrink")

        let tiny = DebuggerWarningLayout.frames(in: NSRect(x: 0, y: 0, width: 60, height: 40), cancelWidth: 66)
        expect(tiny.message.width == 0, "The message never takes a negative width")

        let first = Token(), second = Token(), third = Token()
        expect(DebuggerWarningLayout.appeared([first, second], previous: [first]).elementsEqual([second], by: ===),
               "Only a newly added warning counts as appeared")
        expect(DebuggerWarningLayout.appeared([first], previous: [first, third]).isEmpty, "Removing a warning announces nothing")

        expect(DeveloperChromeGeometry.paneIsCurrent(bounds: NSRect(x: 0, y: 0, width: 500, height: 400),
            developerHeight: 0, browserHeight: 40,
            developerFrame: NSRect(x: 0, y: 0, width: 500, height: 0),
            browserFrame: NSRect(x: 0, y: 0, width: 500, height: 40),
            contentFrame: NSRect(x: 0, y: 80, width: 500, height: 320), warningHeight: 40),
               "A pane's page starts below its warning row")
        expect(!DeveloperChromeGeometry.paneIsCurrent(bounds: NSRect(x: 0, y: 0, width: 500, height: 400),
            developerHeight: 0, browserHeight: 40,
            developerFrame: NSRect(x: 0, y: 0, width: 500, height: 0),
            browserFrame: NSRect(x: 0, y: 0, width: 500, height: 40),
            contentFrame: NSRect(x: 0, y: 40, width: 500, height: 360), warningHeight: 40),
               "A page still under the warning row needs layout")
        expect(DeveloperChromeGeometry.peekIsCurrent(card: NSRect(x: 0, y: 0, width: 500, height: 60),
            developerHeight: 40, browserHeight: 0,
            developerFrame: NSRect(x: 0, y: 0, width: 500, height: 40),
            browserFrame: NSRect(x: 0, y: 0, width: 500, height: 0),
            contentFrame: NSRect(x: 0, y: 60, width: 500, height: 0), warningHeight: 40),
               "A short Peek card clamps the warning to the room it has")
        print("debugger-warning: \(assertions) assertions passed")
    }
}
