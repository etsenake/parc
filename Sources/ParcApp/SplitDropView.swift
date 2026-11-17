import AppKit

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

@MainActor
final class SplitDropView: NSView {
    let drag: SidebarSplitDrag
    private let reservation: ParcSplitView.DropReservation
    private var proposal: (SplitDropTarget, SplitOrientation, NSRect)?
    let targets = SplitDropTargetTracker()
    private let perform: ((SplitDropTarget, SplitOrientation) -> Bool)?
    private(set) var showsCard = false
    private var cardSize: NSSize?
    override var isFlipped: Bool { true }
    init(frame: NSRect, drag: SidebarSplitDrag, reservation: ParcSplitView.DropReservation,
         perform: ((SplitDropTarget, SplitOrientation) -> Bool)? = nil, insertionColor: @escaping () -> NSColor) {
        self.reservation = reservation; self.perform = perform; self.drag = drag
        reservation.setInsertionColor(insertionColor)
        super.init(frame: frame)
        registerForDraggedTypes([SidebarSplitDrag.pasteboardType])
        setAccessibilityElement(false)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    private func accepts(_ sender: NSDraggingInfo) -> Bool {
        guard drag.isValid, (perform == nil) == (window === drag.window), window != nil,
              let source = sender.draggingSource as? SplitDropCardSource,
              source.splitDrag === drag,
              sender.draggingPasteboard.string(forType: SidebarSplitDrag.pasteboardType) == drag.identifier.uuidString else { return false }
        return true
    }
    private func update(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard accepts(sender), frame.size == superview?.bounds.size else { proposal = nil; targets.reset(); reservation.end(); return [] }
        proposal = reservation.proposal(at: convert(sender.draggingLocation, from: nil), canPropose: canPropose)
        targets.update(proposal?.0, reusedRegion: reservation.reusedRegion)
        if showsCard, let size = SplitDropPlaceholderCard.size(forIncomingPane: reservation.incomingPaneSize),
           size != cardSize { _ = presentPlaceholderCard(sender) }
        return proposal == nil ? [] : .move
    }
    var canPropose: (SplitDropTarget, SplitOrientation) -> Bool = { _, _ in false }
    private var edit: ParcSplitView.InteractivePaneEdit?
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let admitted = accepts(sender)
        if edit == nil, admitted { edit = reservation.beginInteractivePaneEdit() }
        edit?.isDragInside = true
        if admitted { showsCard = presentPlaceholderCard(sender) }
        return update(sender)
    }
    private func ownsItem(_ item: NSPasteboardItem) -> Bool {
        item.string(forType: SidebarSplitDrag.pasteboardType) == drag.identifier.uuidString
    }
    private func presentPlaceholderCard(_ sender: NSDraggingInfo) -> Bool {
        guard reservation.isCurrent, let row = sender.draggingSource as? SplitDropCardSource,
              let image = SplitDropPlaceholderCard.image(icon: row.splitDropCardContent.icon,
                  title: row.splitDropCardContent.title, incomingPane: reservation.incomingPaneSize),
              !SplitDropPlaceholderCard.present(image, on: sender, admits: ownsItem).isEmpty else { return false }
        cardSize = image.size
        return true
    }
    private func restoreRowImage(_ sender: NSDraggingInfo?) {
        guard let sender, let image = (sender.draggingSource as? SplitDropCardSource)?.splitDragImage else { return }
        SplitDropPlaceholderCard.present(image, on: sender, admits: ownsItem)
    }
    override func draggingEnded(_ sender: NSDraggingInfo) { showsCard = false; endEdit() }
    private func endEdit() { let old = edit; edit = nil; old?.end() }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { update(sender) }
    override func draggingExited(_ sender: NSDraggingInfo?) {
        proposal = nil; targets.reset(); reservation.clear(animated: true)
        edit?.isDragInside = false
        if showsCard { showsCard = false; restoreRowImage(sender) }
    }
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { !update(sender).isEmpty }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        showsCard = false
        guard !update(sender).isEmpty, let proposal, accepts(sender) else { return false }
        reservation.clear()
        let result = (perform ?? drag.commit)(proposal.0, proposal.1)
        drag.end()
        return result
    }
    override func viewWillMove(toSuperview newSuperview: NSView?) {
        if superview != nil, newSuperview !== superview { reservation.end(); endEdit() }
        super.viewWillMove(toSuperview: newSuperview)
    }
    func refreshAppearance() { reservation.refreshAppearance() }
}
