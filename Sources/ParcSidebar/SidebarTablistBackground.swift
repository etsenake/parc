import AppKit

package enum SidebarTablistBackground {
    package enum Press: Equatable { case dragWindow, waitForRelease, passThrough }

    package static func press(clickCount: Int, modifiers: NSEvent.ModifierFlags) -> Press {
        if modifiers.contains(.control) { return .passThrough }
        return clickCount == 1 ? .dragWindow : .waitForRelease
    }

    static func opensCommandBar(clickCount: Int, modifiers: NSEvent.ModifierFlags, y: CGFloat, lastRowMaxY: CGFloat?) -> Bool {
        clickCount == 2 && !modifiers.contains(.control) && y >= (lastRowMaxY ?? 0)
    }
}
