import AppKit
import ParcCore

@MainActor
package final class SidebarSplitDrag {
    package static let pasteboardType = NSPasteboard.PasteboardType("org.parc.sidebar-split-drag")
    package let identifier = UUID()
    package let tabID: UUID
    package weak var window: NSWindow?
    let validate: () -> Bool
    package let commit: (SplitDropTarget, SplitOrientation) -> Bool
    let finish: () -> Void
    private(set) var ended = false
    private var endHandlers: [() -> Void] = []
    package init(tabID: UUID, window: NSWindow, validate: @escaping () -> Bool,
         commit: @escaping (SplitDropTarget, SplitOrientation) -> Bool, finish: @escaping () -> Void) {
        self.tabID = tabID; self.window = window; self.validate = validate; self.commit = commit; self.finish = finish
    }
    package var isValid: Bool { !ended && validate() }
    package func onEnd(_ handler: @escaping () -> Void) {
        if ended { handler() } else { endHandlers.append(handler) }
    }
    package func end() {
        guard !ended else { return }
        ended = true; finish()
        let handlers = endHandlers; endHandlers = []
        handlers.forEach { $0() }
    }
}

@MainActor
package protocol SplitDropCardSource: AnyObject {
    var splitDrag: SidebarSplitDrag? { get }
    var splitDropCardContent: (icon: NSImage?, title: String) { get }
    var splitDragImage: NSImage? { get }
}
