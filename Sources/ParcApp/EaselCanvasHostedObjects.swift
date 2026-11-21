import AppKit

enum EaselHostedAction: Equatable {
    case play, pause, stopAll, quickLook, fullScreen, download, replace, upload, unsplash, embedLink, viewOriginal
}

@MainActor
protocol EaselHostedObjects: AnyObject {
    func hostedView(for item: EaselItem) -> NSView?
    func synchronizeHosted(items: [EaselItem], selection: Set<UUID>, interacting: Bool)
    func hosts(_ item: EaselItem) -> Bool
    func hostedFillDidChange(_ id: UUID, pending: Bool)
    func canPerformHosted(_ action: EaselHostedAction, on item: EaselItem) -> Bool
    func performHosted(_ action: EaselHostedAction, on id: UUID?, from anchor: NSView?) -> Bool
    func hostedPlayingVideo() -> UUID?
    func fillHosted(_ id: UUID, link url: URL) -> Bool
}

extension EaselHostedObjects {
    func hosts(_ item: EaselItem) -> Bool { hostedView(for: item) != nil }
    func hostedFillDidChange(_ id: UUID, pending: Bool) {}
    func canPerformHosted(_ action: EaselHostedAction, on item: EaselItem) -> Bool { false }
    func performHosted(_ action: EaselHostedAction, on id: UUID?, from anchor: NSView?) -> Bool { false }
    func hostedPlayingVideo() -> UUID? { nil }
    func fillHosted(_ id: UUID, link url: URL) -> Bool { false }
}

extension EaselCanvasView {
    var hostsObjectViews: Bool {
        guard !hostedObjects.isEmpty else { return false }
        return items.contains { item in hostedObjects.contains { $0.hosts(item) } }
    }

    func hostedObjectView(for item: EaselItem) -> NSView? {
        for provider in hostedObjects { if let view = provider.hostedView(for: item) { return view } }
        return nil
    }

    func canPerformHostedAction(_ action: EaselHostedAction, on item: EaselItem) -> Bool {
        hostedObjects.contains { $0.canPerformHosted(action, on: item) }
    }

    @discardableResult
    func performHostedAction(_ action: EaselHostedAction, on id: UUID?, from anchor: NSView? = nil) -> Bool {
        var performed = false
        for provider in hostedObjects where provider.performHosted(action, on: id, from: anchor) { performed = true }
        return performed
    }

    var playingHostedVideo: UUID? {
        for provider in hostedObjects { if let id = provider.hostedPlayingVideo() { return id } }
        return nil
    }

    func isPlayingVideo(_ id: UUID) -> Bool { playingHostedVideo == id }

    func hostedObjectHit(_ hit: NSView) -> Bool {
        guard selection.count == 1, let id = selection.first, let view = artwork[id], hit !== view, hit.isDescendant(of: view),
              let item = items.first(where: { $0.id == id }) else { return false }
        return hostedObjects.contains { $0.hosts(item) }
    }

    func noteHostedFill(_ id: UUID, pending: Bool) {
        for provider in hostedObjects { provider.hostedFillDidChange(id, pending: pending) }
    }

    func synchronizeHostedObjects(interacting: Bool) {
        for provider in hostedObjects { provider.synchronizeHosted(items: items, selection: selection, interacting: interacting) }
    }

    @discardableResult
    func placeEmptyObject(_ kind: EaselItemKind, beside target: EaselRect? = nil) -> UUID? {
        if kind == .equation { return placeEmptyEquation(beside: target) }
        guard fixedCanvasSize == nil, !session.isClosed, EaselMediaPlacement.placesEmpty(kind) else { return nil }
        cancelPointerInteraction()
        guard finishEditing() else { return nil }
        drawing = false
        let shown = uncoveredVisibleRect
        let visible = EaselRect(x: shown.minX, y: shown.minY, width: shown.width, height: shown.height)
        let top = session.document.items.map(\.zIndex).max() ?? 0
        guard top < Int.max,
              let placed = EaselMediaPlacement.placeholderFrame(for: kind, visible: visible, occupied: session.document.items.map(\.frame)) else { return nil }
        let frame = target ?? placed
        let item = EaselItem(kind: kind, frame: frame, zIndex: top + 1, color: insertionColor)
        guard withObjectMotion(.appear, { commit(EaselMediaPlacement.addName(for: kind), { $0.items.append(item) }) }) else { return nil }
        selection = [item.id]
        window?.makeFirstResponder(self)
        needsLayout = true
        NSAccessibility.post(element: self, notification: .layoutChanged)
        return item.id
    }
}
