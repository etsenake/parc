import AppKit

extension EaselCanvasView {
    var isDocumentLocked: Bool { session.document.isLocked }

    func lockedMouseDown(_ event: NSEvent) {
        stopZoomAnimation()
        hoveredObjectID = nil
        let point = convert(event.locationInWindow, from: nil)
        if let linked = EaselObjectLink.item(at: .init(x: point.x, y: point.y), in: items, scale: canvasScale),
           let url = EaselObjectLink.link(of: linked), let onOpenURL {
            onOpenURL(url)
            return
        }
        guard let clip = enclosingScrollView?.contentView else { return }
        toolState.pan = (event.locationInWindow, clip.bounds.origin)
        hidePlacementPreview()
        refreshToolCursor()
    }

    func documentLockDidChange() {
        guard isDocumentLocked else { return }
        cancelPointerInteraction()
        if !selection.isEmpty { selection = [] }
        invalidateIncrementalDisplay(layout: true)
    }

    func lockedAllows(_ action: Selector?) -> Bool {
        guard let action else { return false }
        return [#selector(copy(_:)), #selector(undo(_:)), #selector(redo(_:))].contains(action)
    }
}
