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

@MainActor
protocol SplitContentDropTarget: NSView {
    func acceptsSplitContentDrop(_ info: NSDraggingInfo) -> Bool
}

@MainActor
final class SplitDropView: NSView {
    let drag: SidebarSplitDrag
    var contentTarget: (NSDraggingInfo) -> SplitContentDropTarget? = { _ in nil }
    private weak var contentDrop: SplitContentDropTarget?
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
        reservation.onIntentDue = { [weak self] in self?.refreshIntent() }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    private func accepts(_ sender: NSDraggingInfo) -> Bool {
        guard drag.isValid, (perform == nil) == (window === drag.window), window != nil,
              let source = sender.draggingSource as? SplitDropCardSource,
              source.splitDrag === drag,
              sender.draggingPasteboard.string(forType: SidebarSplitDrag.pasteboardType) == drag.identifier.uuidString else { return false }
        return true
    }
    private func update(_ sender: NSDraggingInfo, presenting: Bool = true, refreshingCard: Bool = true) -> NSDragOperation {
        guard accepts(sender), frame.size == superview?.bounds.size else {
            leaveContent(sender); proposal = nil; targets.reset(); reservation.end(); return []
        }
        if let operation = routeToContent(sender, presenting: presenting) { return operation }
        proposal = reservation.proposal(at: convert(sender.draggingLocation, from: nil), canPropose: canPropose, presenting: presenting)
        guard presenting else { return proposal == nil ? [] : .move }
        lastSender = sender
        targets.update(reservation.shownTarget, feedback: reservation.appeared)
        if refreshingCard, showsCard, let size = SplitDropPlaceholderCard.size(forIncomingPane: reservation.incomingPaneSize),
           size != cardSize { _ = presentPlaceholderCard(sender) }
        return proposal == nil ? [] : .move
    }
    private var lastSender: NSDraggingInfo?
    private func refreshIntent() {
        guard let lastSender, contentDrop == nil else { return }
        _ = update(lastSender, refreshingCard: false)
    }
    private func routeToContent(_ sender: NSDraggingInfo, presenting: Bool) -> NSDragOperation? {
        guard let content = contentTarget(sender) else {
            if contentDrop != nil {
                leaveContent(sender)
                if presenting { showsCard = presentPlaceholderCard(sender) }
            }
            return nil
        }
        if contentDrop !== content {
            leaveContent(sender)
            contentDrop = content
            proposal = nil; targets.reset(); reservation.clear(animated: true)
            if showsCard { showsCard = false; restoreRowImage(sender) }
        }
        return content.draggingUpdated(sender)
    }
    private func leaveContent(_ sender: NSDraggingInfo?) {
        guard let content = contentDrop else { return }
        contentDrop = nil
        content.draggingExited(sender)
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
    override func draggingEnded(_ sender: NSDraggingInfo) { leaveContent(sender); showsCard = false; lastSender = nil; endEdit() }
    private func endEdit() { let old = edit; edit = nil; old?.end() }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { update(sender) }
    override func draggingExited(_ sender: NSDraggingInfo?) {
        leaveContent(sender)
        proposal = nil; lastSender = nil; targets.reset(); reservation.clear(animated: true)
        edit?.isDragInside = false
        if showsCard { showsCard = false; restoreRowImage(sender) }
    }
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { !update(sender, presenting: false).isEmpty }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        showsCard = false; lastSender = nil
        if accepts(sender), let content = contentTarget(sender) {
            contentDrop = nil
            reservation.clear()
            let result = content.performDragOperation(sender)
            drag.end()
            return result
        }
        guard !update(sender, presenting: false).isEmpty, let proposal, accepts(sender) else { return false }
        reservation.clear()
        let result = (perform ?? drag.commit)(proposal.0, proposal.1)
        drag.end()
        return result
    }
    override func viewWillMove(toSuperview newSuperview: NSView?) {
        if superview != nil, newSuperview !== superview { lastSender = nil; reservation.end(); endEdit() }
        super.viewWillMove(toSuperview: newSuperview)
    }
    func refreshAppearance() { reservation.refreshAppearance() }
}
