import Foundation

enum EaselDependents {
    static func settle(_ next: EaselDocument, previous: EaselDocument, moved: Set<UUID>) -> EaselDocument {
        let sections = carrySectionContents(next, previous: previous, moved: moved)
        let attached = followAttachments(sections.document, previous: previous, moved: sections.moved)
        return rerouteConnectors(attached.document, previous: previous, moved: attached.moved)
    }

    static func removing(_ ids: Set<UUID>, from document: EaselDocument, keepingSectionContents: Bool = false) -> EaselDocument {
        let doomed = keepingSectionContents ? ids : EaselBoardObjects.deletion(ids, in: document)
        let removed = doomed.union(attachedDependents(of: doomed, in: document))
        var next = document
        next.items.removeAll { removed.contains($0.id) }
        return detachConnectors(next, from: removed)
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

    private static func rerouteConnectors(_ next: EaselDocument, previous: EaselDocument, moved: Set<UUID>) -> EaselDocument {
        next
    }

    private static func detachConnectors(_ document: EaselDocument, from removed: Set<UUID>) -> EaselDocument {
        document
    }
}
