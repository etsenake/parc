import Foundation

enum EaselDependents {
    static func settle(_ next: EaselDocument, previous: EaselDocument, moved: Set<UUID>) -> EaselDocument {
        let sections = carrySectionContents(next, previous: previous, moved: moved)
        let attached = followAttachments(sections.document, previous: previous, moved: sections.moved)
        return rerouteConnectors(attached.document, previous: previous, moved: attached.moved).document
    }

    static func removing(_ ids: Set<UUID>, from document: EaselDocument, keepingSectionContents: Bool = false) -> EaselDocument {
        let removed = removalClosure(ids, in: document, keepingSectionContents: keepingSectionContents)
        var next = document
        next.items.removeAll { removed.contains($0.id) }
        return detachConnectors(next, from: removed)
    }

    static func removalClosure(_ ids: Set<UUID>, in document: EaselDocument, keepingSectionContents: Bool = false) -> Set<UUID> {
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

    private static func rerouteConnectors(_ next: EaselDocument, previous: EaselDocument,
                                          moved: Set<UUID>) -> (document: EaselDocument, moved: Set<UUID>) {
        guard next.items.contains(where: { $0.kind == .arrow }) else { return (next, moved) }
        let before = Dictionary(previous.items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var changed = moved
        for item in next.items {
            guard let old = before[item.id] else { changed.insert(item.id); continue }
            if placementChanged(old, item) || old.shape != item.shape || old.kind != item.kind { changed.insert(item.id) }
        }
        let current = Dictionary(next.items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var document = next, rerouted = moved
        for index in document.items.indices where document.items[index].kind == .arrow {
            var item = document.items[index]
            let targets = [item.startConnection?.itemID, item.endConnection?.itemID].compactMap { $0 }
            let touched = before[item.id] != item || changed.contains(item.id)
                || targets.contains { changed.contains($0) || current[$0] == nil }
            guard touched else { continue }
            if moved.contains(item.id), let old = before[item.id], let waypoints = item.waypoints,
               targets.count < 2 || targets.allSatisfy(moved.contains) {
                item.waypoints = EaselConnectorPath.mapped(waypoints, from: old.frame, to: item.frame)
            }
            let settled = EaselConnectorRouter.settled(item) { current[$0] }
            if settled.frame != document.items[index].frame || settled.points != document.items[index].points { rerouted.insert(item.id) }
            document.items[index] = settled
        }
        return (document, rerouted)
    }

    private static func detachConnectors(_ document: EaselDocument, from removed: Set<UUID>) -> EaselDocument {
        guard !removed.isEmpty else { return document }
        var next = document
        for index in next.items.indices where next.items[index].kind == .arrow {
            next.items[index] = EaselConnectorRouter.detached(next.items[index], from: removed)
        }
        return next
    }

    private static func placementChanged(_ old: EaselItem, _ new: EaselItem) -> Bool {
        old.frame != new.frame || old.points != new.points || old.resolvedRotation != new.resolvedRotation
            || (old.flipHorizontal == true) != (new.flipHorizontal == true) || (old.flipVertical == true) != (new.flipVertical == true)
    }
}
