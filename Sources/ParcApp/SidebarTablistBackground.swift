import AppKit

///
///
/// empty area while the left button is down.
enum SidebarTablistBackground {
    enum Press: Equatable { case dragWindow, waitForRelease, passThrough }

    ///
    /// superclass press, a first click posts NSWindowWillMoveNotification and
    /// drags the window, and a later click of a multi-click does nothing until
    /// mouseUp.
    static func press(clickCount: Int, modifiers: NSEvent.ModifierFlags) -> Press {
        if modifiers.contains(.control) { return .passThrough }
        return clickCount == 1 ? .dragWindow : .waitForRelease
    }

    ///
    ///
    /// row's cell frame (`frameOfCellAtColumn:row:` for `numberOfRows - 1`) and
    /// acts only at or below it; an empty list has no row to clear.
    static func opensCommandBar(clickCount: Int, modifiers: NSEvent.ModifierFlags, y: CGFloat, lastRowMaxY: CGFloat?) -> Bool {
        clickCount == 2 && !modifiers.contains(.control) && y >= (lastRowMaxY ?? 0)
    }
}
