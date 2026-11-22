import AppKit
import ParcKit

extension NSView {
    package func setEaselTooltip(_ title: String, shortcut: String? = nil) {
        toolTip = nil
        parcTooltip = TooltipConfiguration(title, shortcut: shortcut.flatMap(NoteControlButton.keyboardShortcut(from:)).map { .fixed($0) })
    }
}
