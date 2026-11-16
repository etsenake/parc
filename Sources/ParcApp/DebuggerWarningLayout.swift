import AppKit

enum DebuggerWarningLayout {
    static let rowHeight: CGFloat = DeveloperToolbarLayout.height
    static let leadingInset: CGFloat = 12
    static let trailingInset: CGFloat = 6
    static let iconSide: CGFloat = 16
    static let iconSpacing: CGFloat = 8
    static let messageSpacing: CGFloat = 12
    static let cancelHeight: CGFloat = 26
    static let cancelPadding: CGFloat = 10
    static let closeSpacing: CGFloat = 4
    static let closeSide: CGFloat = DeveloperToolbarLayout.buttonSize
    static let messageMinWidth: CGFloat = 40
    static let revealOffset: CGFloat = -6
    static let cornerRadius: CGFloat = 6
    static let symbol = "puzzlepiece.extension.fill"
    static let label = "Extension Debugging"
    static let cancelHelp = "Stop this extension from debugging the browser"
    static let closeTitle = "Close"
    static let closeHelp = "Stop this extension from debugging the browser and close the warning"

    struct Frames: Equatable {
        var icon: NSRect
        var message: NSRect
        var cancel: NSRect
        var close: NSRect
        var showsIcon: Bool
    }

    static func height(rows: Int) -> CGFloat { CGFloat(max(0, rows)) * rowHeight }

    static func frames(in bounds: NSRect, cancelWidth: CGFloat) -> Frames {
        let midY = bounds.midY
        let close = NSRect(x: bounds.maxX - trailingInset - closeSide, y: midY - closeSide / 2,
                           width: closeSide, height: closeSide)
        let cancel = NSRect(x: close.minX - closeSpacing - cancelWidth, y: midY - cancelHeight / 2,
                            width: cancelWidth, height: cancelHeight)
        let iconX = bounds.minX + leadingInset
        let withIcon = iconX + iconSide + iconSpacing
        let showsIcon = cancel.minX - messageSpacing - withIcon >= messageMinWidth
        let messageX = showsIcon ? withIcon : iconX
        let messageWidth = max(0, cancel.minX - messageSpacing - messageX)
        return Frames(icon: showsIcon ? NSRect(x: iconX, y: midY - iconSide / 2, width: iconSide, height: iconSide) : .zero,
                      message: NSRect(x: messageX, y: bounds.minY, width: messageWidth, height: bounds.height),
                      cancel: cancel, close: close, showsIcon: showsIcon)
    }

    static func appeared<Item: AnyObject>(_ next: [Item], previous: [Item]) -> [Item] {
        next.filter { item in !previous.contains { $0 === item } }
    }
}
