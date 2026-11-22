import AppKit
import ParcCore
import ParcEngine

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
    var peekStepScale: CGFloat = 1
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let superview, PeekWindowLayout.pageAcceptsHit(at: convert(point, from: superview), in: bounds,
                                                             scale: peekStepScale) else { return nil }
        return super.hitTest(point)
    }
    var makeSession: ((NSView, NSDraggingInfo) -> ExternalSplitDropSession?)?
    private var session: ExternalSplitDropSession?
    private weak var sourceView: NSView?
    private var edit: ParcSplitView.InteractivePaneEdit?
    private var editSequence = 0
    private var endingRouter = false
    private weak var releasedSession: ExternalSplitDropSession?
    private func endEdit() { let old = edit; edit = nil; old?.end() }
    private func syncEditPresence() { edit?.isDragInside = session != nil || handoffRouter != nil }
    func contentView(_ view: NSView, beginDrop info: NSDraggingInfo) -> NSDragOperation {
        defer { syncEditPresence() }
        if let session, session.continues(info, into: view) {
            let router = view === sourceView ? nil : handoffRouter
            handoffRouter = nil; sourceView = view; releasedSession = nil
            endingRouter = true; router?.end(); endingRouter = false
            if edit?.ended != false || editSequence != info.draggingSequenceNumber {
                edit = session.beginInteractivePaneEdit(); editSequence = info.draggingSequenceNumber
                session.targets.republish()
            }
            return session.update(info)
        }
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
    func contentView(_ view: NSView, prepareDrop info: NSDraggingInfo) -> Bool {
        view === sourceView && !(session?.update(info, presenting: false).isEmpty ?? true)
    }
    func contentView(_ view: NSView, performDrop info: NSDraggingInfo) -> Bool { view === sourceView && (session?.perform(info) ?? false) }
    func contentViewDidEndDrop(_ view: NSView) {
        defer { syncEditPresence() }
        if view === sourceView, deferRelease(endingEdit: !endingRouter) { return }
        if view === sourceView { tearDown(animated: true) }
        if !endingRouter, view === sourceView || session == nil { endEdit() }
    }
    private func deferRelease(endingEdit: Bool) -> Bool {
        guard let session, session.canContinue else { return false }
        releasedSession = session
        DispatchQueue.main.async { [weak self, weak session] in
            guard let self, let session, self.session === session, self.releasedSession === session else { return }
            self.tearDown(animated: true)
            if endingEdit { self.endEdit() }
            self.syncEditPresence()
        }
        return true
    }
    func contentView(_ view: NSView, handoffDrop info: NSDraggingInfo, router: PCNativeContentDropRouting) -> Bool {
        defer { syncEditPresence() }
        guard view === sourceView, router.claimed else { return false }
        if session?.canHandoff(info) == true, handoffRouter == nil || handoffRouter === router {
            handoffRouter = router; releasedSession = nil
            return true
        }
        if handoffRouter == nil || handoffRouter === router, entersAnotherPage(info, leaving: view),
           deferRelease(endingEdit: false) {
            handoffRouter = router
            return true
        }
        guard let edit, !edit.ended, editSequence == info.draggingSequenceNumber else { return false }
        if handoffRouter === router { handoffRouter = nil }
        endSession(animated: true)
        return true
    }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { updateHandoff(sender) }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { updateHandoff(sender) }
    private func updateHandoff(_ sender: NSDraggingInfo) -> NSDragOperation {
        defer { syncEditPresence() }
        guard let router = handoffRouter, router.claimed, session?.canHandoff(sender) == true else { tearDown(animated: false); return [] }
        releasedSession = nil
        return router.update(sender)
    }
    private func entersAnotherPage(_ info: NSDraggingInfo, leaving view: NSView) -> Bool {
        session?.entersContent(info, outside: view) == true
    }
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        !updateHandoff(sender).isEmpty && handoffRouter?.prepare(sender) == true
    }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard prepareForDragOperation(sender), let router = handoffRouter else { cancelDrop(animated: false); return false }
        return router.perform(sender)
    }
    override func draggingExited(_ sender: NSDraggingInfo?) {
        defer { syncEditPresence() }
        if let sender, handoffRouter?.claimed == true, session?.entersContent(sender) == true,
           deferRelease(endingEdit: false) { return }
        handoffRouter = nil; endSession(animated: true)
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
    func cancelDrop(animated: Bool = true) { tearDown(animated: animated); syncEditPresence() }
    private func tearDown(animated: Bool) {
        let router = handoffRouter
        handoffRouter = nil; releasedSession = nil
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
    private let slotSizes: [Int]?
    private let canPropose: (SplitDropTarget, SplitOrientation) -> Bool
    private let commit: (SplitDropTarget, SplitOrientation) -> Bool
    private let reservation: ParcSplitView.DropReservation?
    private var proposal: (SplitDropTarget, SplitOrientation, NSRect)?
    let targets = SplitDropTargetTracker()
    private weak var info: NSDraggingInfo?
    private var replacedImages: [Int: SplitDropPlaceholderCard.ItemImage] = [:]
    private var cardSize: NSSize?
    private(set) var ended = false
    var isValid: Bool { !ended && validate() && host?.window === window && window != nil }
    var admitsReceiver: ((NSView, NSDraggingInfo) -> Bool)?
    var canContinue: Bool { reservation != nil && admitsReceiver != nil && isValid }
    func continues(_ info: NSDraggingInfo, into view: NSView) -> Bool {
        guard canContinue, matches(info), let admitsReceiver else { return false }
        return admitsReceiver(view, info)
    }

    static func readURL(_ pasteboard: NSPasteboard) -> URL? {
        guard let items = pasteboard.pasteboardItems, items.count == 1,
              !items[0].types.contains(SidebarSplitDrag.pasteboardType),
              !items[0].types.contains(SidebarMoveSession.pasteboardType),
              !items[0].types.contains(.fileURL) else { return nil }
        if let value = items[0].string(forType: .URL), let url = ExternalSplitDrop.url(value) { return url }
        return items[0].string(forType: .string).flatMap(ExternalSplitDrop.url)
    }
    init?(host: NSView, info: NSDraggingInfo, frames: [NSRect], orientation: SplitOrientation, slotSizes: [Int]? = nil,
          reservation: ParcSplitView.DropReservation? = nil, validate: @escaping () -> Bool, insertionColor: @escaping () -> NSColor,
          canPropose: @escaping (SplitDropTarget, SplitOrientation) -> Bool,
          commit: @escaping (SplitDropTarget, SplitOrientation) -> Bool) {
        guard let window = host.window, info.draggingDestinationWindow === window,
              info.draggingSourceOperationMask.contains(.copy), let url = Self.readURL(info.draggingPasteboard) else { return nil }
        self.reservation = reservation
        self.host = host; self.window = window; self.url = url; self.frames = frames; self.orientation = orientation
        self.slotSizes = slotSizes
        sequence = info.draggingSequenceNumber; pasteboard = info.draggingPasteboard; changeCount = pasteboard.changeCount
        self.validate = validate; self.canPropose = canPropose; self.commit = commit; self.info = info
        reservation?.setInsertionColor(insertionColor)
        reservation?.onIntentDue = { [weak self] in
            guard let self, let info = self.intentInfo else { return }
            _ = self.update(info, refreshingCard: false)
        }
    }
    static let linkGlyph = String(Character(Unicode.Scalar(0xE98A)!))
    func presentPlaceholderCard() {
        guard replacedImages.isEmpty, let info, matches(info), let image = placeholderCard() else { return }
        replacedImages = SplitDropPlaceholderCard.present(image, on: info) { _ in true }
    }
    private func placeholderCard() -> NSImage? {
        guard let reservation, reservation.isCurrent,
              let image = SplitDropPlaceholderCard.image(icon: SidebarIconCatalog.emojiImage(Self.linkGlyph, size: 22),
                  title: url.absoluteString, incomingPane: reservation.incomingPaneSize) else { return nil }
        cardSize = image.size
        return image
    }
    private func refreshPlaceholderCard(_ info: NSDraggingInfo) {
        guard !replacedImages.isEmpty, let reservation,
              let size = SplitDropPlaceholderCard.size(forIncomingPane: reservation.incomingPaneSize), size != cardSize,
              let image = placeholderCard() else { return }
        SplitDropPlaceholderCard.present(image, on: info) { _ in true }
    }
    private func restoreImages() {
        let images = replacedImages; replacedImages = [:]
        if let info { SplitDropPlaceholderCard.restore(images, on: info) }
    }
    func beginInteractivePaneEdit() -> ParcSplitView.InteractivePaneEdit? { reservation?.beginInteractivePaneEdit() }
    private func matches(_ info: NSDraggingInfo) -> Bool {
        isValid && info.draggingDestinationWindow === window && info.draggingSequenceNumber == sequence &&
        info.draggingPasteboard === pasteboard && pasteboard.changeCount == changeCount &&
        info.draggingSourceOperationMask.contains(.copy) && Self.readURL(pasteboard) == url
    }
    func canHandoff(_ info: NSDraggingInfo) -> Bool {
        guard matches(info), let host, let reservation else { return false }
        return reservation.containsHandoffPoint(host.convert(info.draggingLocation, from: nil))
    }
    func entersContent(_ info: NSDraggingInfo, outside view: NSView? = nil) -> Bool {
        guard matches(info), let host, let reservation else { return false }
        return reservation.containsContentPoint(host.convert(info.draggingLocation, from: nil), outside: view)
    }
    private var intentInfo: NSDraggingInfo?
    func update(_ info: NSDraggingInfo, presenting: Bool = true, refreshingCard: Bool = true) -> NSDragOperation {
        guard matches(info), let host else { end(animated: false); return [] }
        let point = host.convert(info.draggingLocation, from: nil)
        if let reservation {
            proposal = reservation.proposal(at: point, canPropose: canPropose, presenting: presenting)
        } else {
            proposal = SplitDropGeometry.proposal(at: point, frames: frames,
                orientation: orientation, slotSizes: slotSizes, canPropose: canPropose)
        }
        guard matches(info) else { end(animated: false); return [] }
        guard presenting else { return proposal == nil ? [] : .copy }
        self.info = info; intentInfo = info
        if let reservation {
            targets.update(reservation.shownTarget, feedback: reservation.appeared)
        } else {
            let next = proposal?.0
            targets.update(next, feedback: next != nil && next != targets.target)
        }
        if refreshingCard { refreshPlaceholderCard(info) }
        return proposal == nil ? [] : .copy
    }
    func refreshAppearance() { reservation?.refreshAppearance() }
    func perform(_ info: NSDraggingInfo) -> Bool {
        guard !update(info, presenting: false).isEmpty, let p = proposal, matches(info) else { end(animated: false); return false }
        reservation?.clear()
        guard matches(info) else { end(animated: false); return false }
        ended = true; proposal = nil; replacedImages = [:]; intentInfo = nil
        targets.reset()
        let result = commit(p.0, p.1)
        reservation?.end()
        return result
    }
    func end(animated: Bool = true) {
        guard !ended else { return }
        let attached = window != nil && host?.window === window
        ended = true; proposal = nil; intentInfo = nil
        targets.reset()
        restoreImages()
        let animate = animated && attached && validate()
        reservation?.end(animated: animate)
    }

    static func proposal(at point: NSPoint, frames: [NSRect], orientation: SplitOrientation,
                         slotSizes: [Int]? = nil) -> (SplitDropTarget, SplitOrientation, NSRect)? {
        SplitDropGeometry.proposal(at: point, frames: frames, orientation: orientation, slotSizes: slotSizes)
    }

}

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
