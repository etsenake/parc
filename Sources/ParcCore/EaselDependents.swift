import Foundation

enum EaselDependents {
    static func settle(_ next: EaselDocument, previous: EaselDocument, moved: Set<UUID>) -> EaselDocument {
        let sections = carrySectionContents(next, previous: previous, moved: moved)
        let attached = followAttachments(sections.document, previous: previous)
        return rerouteConnectors(attached, previous: previous, moved: sections.moved)
    }

    static func removing(_ ids: Set<UUID>, from document: EaselDocument) -> EaselDocument {
        let removed = ids.union(attachedDependents(of: ids, in: document))
        var next = document
        next.items.removeAll { removed.contains($0.id) }
        return detachConnectors(next, from: removed)
    }

    private static func carrySectionContents(_ next: EaselDocument, previous: EaselDocument,
                                             moved: Set<UUID>) -> (document: EaselDocument, moved: Set<UUID>) {
        (next, moved)
    }

    private static func followAttachments(_ next: EaselDocument, previous: EaselDocument) -> EaselDocument {
        next
    }

    private static func attachedDependents(of ids: Set<UUID>, in document: EaselDocument) -> Set<UUID> {
        []
    }

    private static func rerouteConnectors(_ next: EaselDocument, previous: EaselDocument, moved: Set<UUID>) -> EaselDocument {
        next
    }

    private static func detachConnectors(_ document: EaselDocument, from removed: Set<UUID>) -> EaselDocument {
        document
    }
}
