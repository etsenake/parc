import AppKit

@MainActor
protocol EaselHostedObjects: AnyObject {
    func hostedView(for item: EaselItem) -> NSView?
    func synchronizeHosted(items: [EaselItem], selection: Set<UUID>, interacting: Bool)
    func hosts(_ item: EaselItem) -> Bool
}

extension EaselHostedObjects {
    func hosts(_ item: EaselItem) -> Bool { hostedView(for: item) != nil }
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

    func synchronizeHostedObjects(interacting: Bool) {
        for provider in hostedObjects { provider.synchronizeHosted(items: items, selection: selection, interacting: interacting) }
    }

    @discardableResult
    func placeEmptyObject(_ kind: EaselItemKind, beside target: EaselRect? = nil) -> UUID? {
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
