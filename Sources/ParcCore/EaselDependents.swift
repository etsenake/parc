import Foundation

package struct EaselSettleContext {
    package let previous: EaselDocument
    private let positions: [UUID: Int]

    package init(previous: EaselDocument) {
        self.previous = previous
        var positions: [UUID: Int] = [:]
        for (index, item) in previous.items.enumerated() where positions[item.id] == nil { positions[item.id] = index }
        self.positions = positions
    }

    package func before(_ id: UUID) -> EaselItem? {
        guard let index = positions[id], previous.items.indices.contains(index) else { return nil }
        return previous.items[index]
    }

    package func item(_ id: UUID, in document: EaselDocument) -> EaselItem? {
        if let index = positions[id], document.items.indices.contains(index), document.items[index].id == id { return document.items[index] }
        return document.items.first { $0.id == id }
    }
}

package enum EaselDependents {
    package static func settle(_ next: EaselDocument, previous: EaselDocument, moved: Set<UUID>) -> EaselDocument {
        settle(next, context: EaselSettleContext(previous: previous), moved: moved)
    }

    package static func settle(_ next: EaselDocument, context: EaselSettleContext, moved: Set<UUID>, tidy: Bool = true) -> EaselDocument {
        let mindMaps = EaselMindMap.settling(next, previous: context.previous, moved: moved, tidy: tidy)
        let sections = carrySectionContents(mindMaps.document, previous: context.previous, moved: mindMaps.moved)
        let attached = followAttachments(sections.document, previous: context.previous, moved: sections.moved)
        return rerouteConnectors(attached.document, context: context, moved: attached.moved).document
    }

    package static func removing(_ ids: Set<UUID>, from document: EaselDocument, keepingSectionContents: Bool = false) -> EaselDocument {
        let removed = removalClosure(ids, in: document, keepingSectionContents: keepingSectionContents)
        var next = document
        next.items.removeAll { removed.contains($0.id) }
        return detachConnectors(EaselMindMap.detaching(removed, from: document, in: next), from: removed)
    }

    package static func removalClosure(_ ids: Set<UUID>, in document: EaselDocument, keepingSectionContents: Bool = false) -> Set<UUID> {
        let present = Set(document.items.map(\.id))
        var followers: [UUID: [UUID]] = [:]
        for item in document.items {
            if let target = item.attachedTo, target != item.id { followers[target, default: []].append(item.id) }
        }
        var removed = ids.intersection(present)
        var frontier = removed
        while !frontier.isEmpty {
            var reached = Set<UUID>()
            for id in frontier { reached.formUnion(followers[id] ?? []) }
            reached.formUnion(attachedDependents(of: frontier, in: document))
            reached.formUnion(EaselMindMap.removalDependents(of: frontier, in: document))
            if !keepingSectionContents { reached.formUnion(sectionContents(of: frontier, in: document)) }
            frontier = reached.intersection(present).subtracting(removed)
            removed.formUnion(frontier)
        }
        return removed
    }

    private static func carrySectionContents(_ next: EaselDocument, previous: EaselDocument,
                                             moved: Set<UUID>) -> (document: EaselDocument, moved: Set<UUID>) {
        EaselBoardObjects.carryingSectionContents(next, previous: previous, moved: moved)
    }

    private static func followAttachments(_ next: EaselDocument, previous: EaselDocument,
                                          moved: Set<UUID>) -> (document: EaselDocument, moved: Set<UUID>) {
        EaselAttachments.carrying(next, previous: previous, moved: moved)
    }

    private static func attachedDependents(of ids: Set<UUID>, in document: EaselDocument) -> Set<UUID> {
        EaselAttachments.dependents(of: ids, in: document)
    }

    private static func sectionContents(of ids: Set<UUID>, in document: EaselDocument) -> Set<UUID> {
        EaselBoardObjects.deletion(ids, in: document).subtracting(ids)
    }

    private static func rerouteConnectors(_ next: EaselDocument, context: EaselSettleContext,
                                          moved: Set<UUID>) -> (document: EaselDocument, moved: Set<UUID>) {
        guard next.items.contains(where: { $0.kind == .arrow }) else { return (next, moved) }
        var changed = moved
        for item in next.items {
            guard let old = context.before(item.id) else { changed.insert(item.id); continue }
            if placementChanged(old, item) || old.shape != item.shape || old.kind != item.kind { changed.insert(item.id) }
        }
        let current: (UUID) -> EaselItem? = { context.item($0, in: next) }
        var document = next, rerouted = moved
        for index in document.items.indices where document.items[index].kind == .arrow {
            var item = document.items[index]
            let old = context.before(item.id)
            let targets = [item.startConnection?.itemID, item.endConnection?.itemID].compactMap { $0 }
            let touched = old != item || changed.contains(item.id) || targets.contains { changed.contains($0) || current($0) == nil }
            guard touched else { continue }
            if let old, let shifted = translatedTogether(item, from: old, targets: targets, context: context, current: current, moved: moved) {
                document.items[index] = shifted
                continue
            }
            if moved.contains(item.id), let old, let waypoints = item.waypoints, targets.count < 2 || targets.allSatisfy(moved.contains) {
                item.waypoints = EaselConnectorPath.mapped(waypoints, from: old.frame, to: item.frame)
            }
            let settled = EaselConnectorRouter.settled(item, lookup: current)
            if settled.frame != document.items[index].frame || settled.points != document.items[index].points { rerouted.insert(item.id) }
            document.items[index] = settled
        }
        return (document, rerouted)
    }

    private static func translatedTogether(_ item: EaselItem, from old: EaselItem, targets: [UUID], context: EaselSettleContext,
                                           current: (UUID) -> EaselItem?, moved: Set<UUID>) -> EaselItem? {
        guard moved.contains(item.id), old.frame.width == item.frame.width, old.frame.height == item.frame.height else { return nil }
        let dx = item.frame.x - old.frame.x, dy = item.frame.y - old.frame.y
        guard dx != 0 || dy != 0, dx.isFinite, dy.isFinite else { return nil }
        var unmoved = item
        unmoved.frame = old.frame
        guard unmoved == old else { return nil }
        for id in targets {
            guard let was = context.before(id), let now = current(id), EaselConnectorAttachment.resolves(now),
                  now.kind == was.kind, now.shape == was.shape, now.frame.width == was.frame.width, now.frame.height == was.frame.height,
                  abs(now.frame.x - was.frame.x - dx) < 1e-9, abs(now.frame.y - was.frame.y - dy) < 1e-9,
                  now.resolvedRotation == was.resolvedRotation, (now.flipHorizontal == true) == (was.flipHorizontal == true),
                  (now.flipVertical == true) == (was.flipVertical == true) else { return nil }
        }
        var shifted = item
        shifted.waypoints = item.waypoints.map { points in points.map { EaselPoint(x: $0.x + dx, y: $0.y + dy) } }
        return shifted
    }

    private static func detachConnectors(_ document: EaselDocument, from removed: Set<UUID>) -> EaselDocument {
        guard !removed.isEmpty, document.items.contains(where: { $0.kind == .arrow }) else { return document }
        var lookup: [UUID: EaselItem]?
        var next = document
        for index in next.items.indices where next.items[index].kind == .arrow {
            let item = next.items[index]
            let freed = EaselConnectorRouter.detached(item, from: removed)
            guard freed != item else { continue }
            let table = lookup ?? Dictionary(document.items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            lookup = table
            next.items[index] = EaselConnectorRouter.settled(freed) { table[$0] }
        }
        return next
    }

    private static func placementChanged(_ old: EaselItem, _ new: EaselItem) -> Bool {
        old.frame != new.frame || old.points != new.points || old.resolvedRotation != new.resolvedRotation
            || (old.flipHorizontal == true) != (new.flipHorizontal == true) || (old.flipVertical == true) != (new.flipVertical == true)
    }
}
