import AppKit
import ParcCore

@MainActor
final class SidebarSplitDrag {
    static let pasteboardType = NSPasteboard.PasteboardType("org.parc.sidebar-split-drag")
    let identifier = UUID()
    let tabID: UUID
    weak var window: NSWindow?
    let validate: () -> Bool
    let commit: (SplitDropTarget, SplitOrientation) -> Bool
    let finish: () -> Void
    private(set) var ended = false
    private var endHandlers: [() -> Void] = []
    init(tabID: UUID, window: NSWindow, validate: @escaping () -> Bool,
         commit: @escaping (SplitDropTarget, SplitOrientation) -> Bool, finish: @escaping () -> Void) {
        self.tabID = tabID; self.window = window; self.validate = validate; self.commit = commit; self.finish = finish
    }
    var isValid: Bool { !ended && validate() }
    func onEnd(_ handler: @escaping () -> Void) {
        if ended { handler() } else { endHandlers.append(handler) }
    }
    func end() {
        guard !ended else { return }
        ended = true; finish()
        let handlers = endHandlers; endHandlers = []
        handlers.forEach { $0() }
    }
}

@MainActor
protocol SplitDropCardSource: AnyObject {
    var splitDrag: SidebarSplitDrag? { get }
    var splitDropCardContent: (icon: NSImage?, title: String) { get }
    var splitDragImage: NSImage? { get }
}
