import AppKit

/// The native renderer's real NSDraggingInfo is handed to this ancestor before
/// Chromium sees a claimed gesture. It remains the one drop owner across preview.
@MainActor
final class ExternalSplitDropHost: LayoutView, PCNativeContentDropDestination, LocalContentDropHosting {
    func contentDropRouter(for view: NSView) -> any LocalContentDropRouting {
        NativeLocalContentDropRouter(view: view)
    }
    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.URL, .string])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    private var handoffRouter: PCNativeContentDropRouting?
    var makeSession: ((NSView, NSDraggingInfo) -> ExternalSplitDropSession?)?
    private var session: ExternalSplitDropSession?
    private weak var sourceView: NSView?
    ///
    ///
    /// re-entries and the per-entry sessions and leases do not end it. A
    /// content router left on exit stays claimed so its view's terminal
    /// draggingEnded/conclude still reaches `contentViewDidEndDrop`; while no
    /// session or handoff has the drag, the edit's button-release fallback
    /// guarantees the end if that terminal never arrives.
    private var edit: ParcSplitView.InteractivePaneEdit?
    private var editSequence = 0
    /// The host's own router ends are not terminal callbacks of the drag.
    private var endingRouter = false
    private func endEdit() { let old = edit; edit = nil; old?.end() }
    private func syncEditPresence() { edit?.isDragInside = session != nil || handoffRouter != nil }
    func contentView(_ view: NSView, beginDrop info: NSDraggingInfo) -> NSDragOperation {
        defer { syncEditPresence() }
        tearDown(animated: true)
        guard let next = makeSession?(view, info) else { return [] }
        sourceView = view; session = next
        if edit?.ended != false || editSequence != info.draggingSequenceNumber {
            edit = next.beginInteractivePaneEdit(); editSequence = info.draggingSequenceNumber
        }
        next.presentPlaceholderCard()
        return next.update(info)
    }
    func contentView(_ view: NSView, updateDrop info: NSDraggingInfo) -> NSDragOperation { view === sourceView ? session?.update(info) ?? [] : [] }
    func contentView(_ view: NSView, prepareDrop info: NSDraggingInfo) -> Bool { view === sourceView && !(session?.update(info).isEmpty ?? true) }
    func contentView(_ view: NSView, performDrop info: NSDraggingInfo) -> Bool { view === sourceView && (session?.perform(info) ?? false) }
    /// Reached from a content router's end: its view's terminal draggingEnded
    /// or conclude, a completed perform, an invalid recipient, or the
    /// router's own restart when the drag re-enters that view, whose
    /// beginDrop follows synchronously and begins the drag's edit again
    /// before any layout runs.
    func contentViewDidEndDrop(_ view: NSView) {
        defer { syncEditPresence() }
        if view === sourceView { tearDown(animated: true) }
        if !endingRouter { endEdit() }
    }
    func contentView(_ view: NSView, handoffDrop info: NSDraggingInfo, router: PCNativeContentDropRouting) -> Bool {
        defer { syncEditPresence() }
        guard view === sourceView, router.claimed else { return false }
        if session?.canHandoff(info) == true, handoffRouter == nil || handoffRouter === router {
            handoffRouter = router
            return true
        }
        // Leaving the page ends its preview, not the drag's edit: keep the
        // router claimed as the witness of the drag's terminal callback.
        guard let edit, !edit.ended, editSequence == info.draggingSequenceNumber else { return false }
        if handoffRouter === router { handoffRouter = nil }
        endSession(animated: true)
        return true
    }
    // The host can only continue an accepted original content gesture. A URL
    // over an unclaimed gap or the empty content cannot manufacture a new page owner.
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { updateHandoff(sender) }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { updateHandoff(sender) }
    private func updateHandoff(_ sender: NSDraggingInfo) -> NSDragOperation {
        defer { syncEditPresence() }
        guard let router = handoffRouter, router.claimed, session?.canHandoff(sender) == true else { tearDown(animated: false); return [] }
        return router.update(sender)
    }
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        !updateHandoff(sender).isEmpty && handoffRouter?.prepare(sender) == true
    }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard prepareForDragOperation(sender), let router = handoffRouter else { cancelDrop(animated: false); return false }
        return router.perform(sender)
    }
    /// Leaving the host's handoff area ends the preview; the handed-off router
    /// stays claimed as the terminal witness, as on a page exit.
    override func draggingExited(_ sender: NSDraggingInfo?) {
        handoffRouter = nil; endSession(animated: true); syncEditPresence()
    }
    override func draggingEnded(_ sender: NSDraggingInfo) { cancelDrop(); endEdit() }
    override func concludeDragOperation(_ sender: NSDraggingInfo?) { cancelDrop(); endEdit() }
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow !== window { cancelDrop(animated: false); endEdit() }
        super.viewWillMove(toWindow: newWindow)
    }
    private func endSession(animated: Bool) {
        let old = session
        session = nil; sourceView = nil
        old?.end(animated: animated)
    }
    /// Ends the current session and handoff without ending the drag's edit.
    func cancelDrop(animated: Bool = true) { tearDown(animated: animated); syncEditPresence() }
    private func tearDown(animated: Bool) {
        let router = handoffRouter
        handoffRouter = nil
        endSession(animated: animated)
        endingRouter = true; router?.end(); endingRouter = false
    }
    func refreshDropAppearance() { session?.refreshAppearance() }
    func validateDrop() { if session?.isValid == false { cancelDrop(animated: false) } }
}

@MainActor
final class ExternalSplitDropSession {
    let url: URL
    let validate: () -> Bool
    private let sequence: Int
    private let pasteboard: NSPasteboard
    private let changeCount: Int
    private weak var window: NSWindow?
    private weak var host: NSView?
    private let frames: [NSRect]
    private let orientation: SplitOrientation
    private let canPropose: (SplitDropTarget, SplitOrientation) -> Bool
    private let commit: (SplitDropTarget, SplitOrientation) -> Bool
    private let reservation: ParcSplitView.DropReservation?
    private var proposal: (SplitDropTarget, SplitOrientation, NSRect)?
    /// Proposed-target owner: replacement presentation and haptic feedback.
    let targets = SplitDropTargetTracker()
    private weak var info: NSDraggingInfo?
    /// The link's own images the placeholder card replaced, put back when the
    /// session ends without a drop.
    private var replacedImages: [Int: SplitDropPlaceholderCard.ItemImage] = [:]
    private(set) var ended = false
    var isValid: Bool { !ended && validate() && host?.window === window && window != nil }

    static func readURL(_ pasteboard: NSPasteboard) -> URL? {
        guard let items = pasteboard.pasteboardItems, items.count == 1,
              // Internal drags retain their original identity/transaction owner.
              !items[0].types.contains(SidebarSplitDrag.pasteboardType),
              !items[0].types.contains(SidebarMoveSession.pasteboardType),
              !items[0].types.contains(.fileURL) else { return nil }
        if let value = items[0].string(forType: .URL), let url = ExternalSplitDrop.url(value) { return url }
        return items[0].string(forType: .string).flatMap(ExternalSplitDrop.url)
    }
    init?(host: NSView, info: NSDraggingInfo, frames: [NSRect], orientation: SplitOrientation,
          reservation: ParcSplitView.DropReservation? = nil, validate: @escaping () -> Bool, insertionColor: @escaping () -> NSColor,
          canPropose: @escaping (SplitDropTarget, SplitOrientation) -> Bool,
          commit: @escaping (SplitDropTarget, SplitOrientation) -> Bool) {
        guard let window = host.window, info.draggingDestinationWindow === window,
              info.draggingSourceOperationMask.contains(.copy), let url = Self.readURL(info.draggingPasteboard) else { return nil }
        self.reservation = reservation
        self.host = host; self.window = window; self.url = url; self.frames = frames; self.orientation = orientation
        sequence = info.draggingSequenceNumber; pasteboard = info.draggingPasteboard; changeCount = pasteboard.changeCount
        self.validate = validate; self.canPropose = canPropose; self.commit = commit; self.info = info
        reservation?.setInsertionColor(insertionColor)
    }
    ///
    ///
    ///
    /// for the incoming pane.
    static let linkGlyph = String(Character(Unicode.Scalar(0xE98A)!))
    func presentPlaceholderCard() {
        guard replacedImages.isEmpty, let info, matches(info), let reservation, reservation.isCurrent,
              let image = SplitDropPlaceholderCard.image(icon: SidebarIconCatalog.emojiImage(Self.linkGlyph, size: 22),
                  title: url.absoluteString, incomingPane: reservation.incomingPaneSize) else { return }
        replacedImages = SplitDropPlaceholderCard.present(image, on: info) { _ in true }
    }
    private func restoreImages() {
        let images = replacedImages; replacedImages = [:]
        if let info { SplitDropPlaceholderCard.restore(images, on: info) }
    }
    /// The drag's interactive pane edit begins with this admitted session; its
    /// host keeps it after the session ends.
    func beginInteractivePaneEdit() -> ParcSplitView.InteractivePaneEdit? { reservation?.beginInteractivePaneEdit() }
    private func matches(_ info: NSDraggingInfo) -> Bool {
        isValid && info.draggingDestinationWindow === window && info.draggingSequenceNumber == sequence &&
        info.draggingPasteboard === pasteboard && pasteboard.changeCount == changeCount &&
        info.draggingSourceOperationMask.contains(.copy) && Self.readURL(pasteboard) == url
    }
    /// The host continues the content's gesture over the reserved region and
    ///
    func canHandoff(_ info: NSDraggingInfo) -> Bool {
        guard matches(info), let host, let reservation else { return false }
        return reservation.containsHandoffPoint(host.convert(info.draggingLocation, from: nil))
    }
    func update(_ info: NSDraggingInfo) -> NSDragOperation {
        guard matches(info), let host else { end(animated: false); return [] }
        let point = host.convert(info.draggingLocation, from: nil)
        if let reservation {
            proposal = reservation.proposal(at: point, canPropose: canPropose)
        } else {
            proposal = SplitDropGeometry.proposal(at: point, frames: frames,
                orientation: orientation, canPropose: canPropose)
        }
        guard matches(info) else { end(animated: false); return [] }
        targets.update(proposal?.0, reusedRegion: reservation?.reusedRegion ?? false)
        return proposal == nil ? [] : .copy
    }
    func refreshAppearance() { reservation?.refreshAppearance() }
    func perform(_ info: NSDraggingInfo) -> Bool {
        guard !update(info).isEmpty, let p = proposal, matches(info) else { end(animated: false); return false }
        // Consume first: model/native publication can synchronously reenter layout.
        reservation?.clear()
        guard matches(info) else { end(animated: false); return false }
        ended = true; proposal = nil; replacedImages = [:]
        targets.reset()
        let result = commit(p.0, p.1)
        reservation?.end()
        return result
    }
    func end(animated: Bool = true) {
        guard !ended else { return }
        let attached = window != nil && host?.window === window
        // Validation is an external owner callback and may retire this session.
        // Revoke first so terminal reentry cannot validate or finish twice.
        ended = true; proposal = nil
        targets.reset()
        restoreImages()
        let animate = animated && attached && validate()
        reservation?.end(animated: animate)
    }

    static func proposal(at point: NSPoint, frames: [NSRect], orientation: SplitOrientation) -> (SplitDropTarget, SplitOrientation, NSRect)? {
        SplitDropGeometry.proposal(at: point, frames: frames, orientation: orientation)
    }

}

/// Only an API adapter: the original native ancestor/gesture/window/pasteboard
/// lease remains authoritative for both renderer and local document receivers.
@MainActor
private final class NativeLocalContentDropRouter: LocalContentDropRouting {
    private let router: PCNativeContentDropRouting
    init(view: NSView) { router = PCCreateNativeContentDropRouter(view) }
    var claimed: Bool { router.claimed }
    func begin(_ info: NSDraggingInfo) -> NSDragOperation { _ = router.begin(info); return router.operation }
    func update(_ info: NSDraggingInfo) -> NSDragOperation { router.update(info) }
    func prepare(_ info: NSDraggingInfo) -> Bool { router.prepare(info) }
    func perform(_ info: NSDraggingInfo) -> Bool { router.perform(info) }
    func exit(_ info: NSDraggingInfo?) { router.exit(info) }
    func end() { router.end() }
}
