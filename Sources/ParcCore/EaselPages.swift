import Foundation

extension EaselPages {
    package static func merging(_ view: EaselDocument, page: UUID?, into document: EaselDocument) -> EaselDocument {
        guard document.pages != nil else {
            var next = view
            next.pages = nil
            for index in next.items.indices where next.items[index].page != nil { next.items[index].page = nil }
            return next
        }
        let target = resolvedPage(page, in: document)
        let first = firstPageID(document)
        var incoming = view.items
        for index in incoming.indices where incoming[index].page != target { incoming[index].page = target }
        var next = view
        next.pages = document.pages
        let onPage = document.items.filter { isOnPage($0, target, first: first) }
        if onPage == incoming, view.items == incoming {
            next.items = document.items
            return next
        }
        let incomingIDs = Set(incoming.map(\.id))
        let kept = onPage.map(\.id).filter(incomingIDs.contains)
        let originalIDs = Set(onPage.map(\.id))
        let survivingOrder = incoming.map(\.id).filter(originalIDs.contains)
        var items: [EaselItem] = []
        items.reserveCapacity(document.items.count + incoming.count)
        if kept == survivingOrder {
            var replacements: [UUID: EaselItem] = [:]
            for item in incoming where replacements[item.id] == nil { replacements[item.id] = item }
            var used = Set<UUID>()
            for item in document.items {
                if !isOnPage(item, target, first: first) { items.append(item); continue }
                guard let replacement = replacements[item.id], !used.contains(item.id) else { continue }
                used.insert(item.id)
                items.append(replacement)
            }
            for item in incoming where !used.contains(item.id) { items.append(item) }
        } else {
            items = document.items.filter { !isOnPage($0, target, first: first) } + incoming
        }
        next.items = items
        return next
    }

    package static func cleanName(_ raw: String) -> String? {
        let flattened = raw.components(separatedBy: .newlines).joined(separator: " ")
        var scalars = String.UnicodeScalarView()
        scalars.append(contentsOf: flattened.unicodeScalars.filter { $0.properties.generalCategory != .control })
        let trimmed = String(scalars).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let capped = String(trimmed.prefix(EaselPage.maximumNameLength)).trimmingCharacters(in: .whitespacesAndNewlines)
        return capped.utf8.count <= EaselPage.maximumNameBytes ? capped : nil
    }

    package static func materialized(_ document: EaselDocument) -> EaselDocument {
        var next = document
        if next.pages == nil { next.pages = [EaselPage(id: UUID(), name: firstPageName)] }
        return pinned(next)
    }

    package static func pinned(_ document: EaselDocument) -> EaselDocument {
        guard let first = firstPageID(document), document.items.contains(where: { $0.page == nil }) else { return document }
        var next = document
        for index in next.items.indices where next.items[index].page == nil { next.items[index].page = first }
        return next
    }

    package static func collapsed(_ document: EaselDocument) -> EaselDocument {
        guard let pages = document.pages, pages.count == 1, pages[0].name == firstPageName else { return document }
        var next = document
        next.pages = nil
        for index in next.items.indices where next.items[index].page != nil { next.items[index].page = nil }
        return next
    }

    package static func nextName(in document: EaselDocument) -> String {
        let taken = Set(pages(in: document).map { $0.name.lowercased() })
        var number = max(1, contentPages(document).count + (document.pages == nil ? 1 : 0)) + 1
        while taken.contains("page \(number)") { number += 1 }
        return "Page \(number)"
    }

    package static func copyName(_ name: String, in document: EaselDocument) -> String {
        let taken = Set(pages(in: document).map { $0.name.lowercased() })
        let base = String(name.prefix(EaselPage.maximumNameLength - 8))
        var candidate = base + " copy", number = 2
        while taken.contains(candidate.lowercased()) && number < 1000 {
            candidate = base + " copy \(number)"
            number += 1
        }
        return candidate
    }

    private static func insertionIndex(after page: UUID?, in pages: [EaselPage]) -> Int {
        guard let page, let index = pages.firstIndex(where: { $0.id == page }) else { return pages.count }
        return index + 1
    }

    package static func adding(to document: EaselDocument, after page: UUID? = nil, name: String? = nil) -> EaselPageChange? {
        guard (document.pages?.count ?? 1) < EaselPage.maximumCount else { return nil }
        let resolvedName: String
        if let name {
            guard let clean = cleanName(name) else { return nil }
            resolvedName = clean
        } else {
            resolvedName = nextName(in: document)
        }
        var next = materialized(document)
        var pages = next.pages ?? []
        let created = EaselPage(id: UUID(), name: resolvedName)
        pages.insert(created, at: insertionIndex(after: page, in: pages))
        next.pages = pages
        return EaselPageChange(document: next, page: resolvedName == EaselPage.dividerName ? resolvedPage(page, in: next) : created.id)
    }

    package static func addingDivider(to document: EaselDocument, after page: UUID? = nil) -> EaselPageChange? {
        adding(to: document, after: page, name: EaselPage.dividerName)
    }

    package static func renaming(_ page: UUID, to name: String, in document: EaselDocument) -> EaselDocument? {
        guard let clean = cleanName(name), let index = document.pages?.firstIndex(where: { $0.id == page }),
              let pages = document.pages, pages[index].name != clean else { return nil }
        var next = document
        next.pages?[index].name = clean
        if clean == EaselPage.dividerName {
            guard itemCount(on: page, in: document) == 0, contentPages(next).contains(where: { $0.id != page }) else { return nil }
        }
        return validationProblem(next) == nil ? next : nil
    }

    package static func moving(_ page: UUID, to index: Int, in document: EaselDocument) -> EaselDocument? {
        guard var pages = document.pages, let from = pages.firstIndex(where: { $0.id == page }) else { return nil }
        let target = min(max(index, 0), pages.count - 1)
        guard target != from else { return nil }
        var next = pinned(document)
        let moved = pages.remove(at: from)
        pages.insert(moved, at: target)
        next.pages = pages
        return next
    }

    package static func reordered(_ document: EaselDocument, order: [UUID]) -> EaselDocument? {
        guard let pages = document.pages, order.count == pages.count, Set(order) == Set(pages.map(\.id)),
              order != pages.map(\.id) else { return nil }
        var byID: [UUID: EaselPage] = [:]
        for page in pages where byID[page.id] == nil { byID[page.id] = page }
        var next = pinned(document)
        next.pages = order.compactMap { byID[$0] }
        return next
    }

    package static func duplicating(_ page: UUID?, in document: EaselDocument) -> EaselPageChange? {
        guard (document.pages?.count ?? 1) < EaselPage.maximumCount else { return nil }
        let base = materialized(document)
        guard let source = self.page(page, in: base) else { return nil }
        let originals = EaselArrange.paintOrder(view(base, page: source.id))
        guard base.items.count + originals.count <= 10_000 else { return nil }
        let created = EaselPage(id: UUID(), name: copyName(source.name, in: base))
        var copies = EaselArrange.copies(of: originals, offset: EaselPoint(x: 0, y: 0), firstZIndex: 0)
        for index in copies.indices {
            copies[index].page = created.id
            copies[index].zIndex = originals[index].zIndex
            copies[index].movedToFrontAt = originals[index].movedToFrontAt
        }
        var next = base
        var pages = next.pages ?? []
        pages.insert(created, at: insertionIndex(after: source.id, in: pages))
        next.pages = pages
        next.items.append(contentsOf: copies)
        return EaselPageChange(document: next, page: created.id, items: Set(copies.map(\.id)))
    }

    package static func deleting(_ page: UUID, in document: EaselDocument) -> EaselPageChange? {
        guard let pages = document.pages, pages.count > 1, let index = pages.firstIndex(where: { $0.id == page }) else { return nil }
        let divider = isDivider(pages[index], in: document)
        guard divider || contentPages(document).contains(where: { $0.id != page }) else { return nil }
        var next = pinned(document)
        let removed = Set(next.items.filter { $0.page == page }.map(\.id))
        next.items.removeAll { removed.contains($0.id) }
        next.pages?.remove(at: index)
        next = scrubbing(removed, in: next)
        let remaining = next.pages ?? []
        let after = remaining[index...].first { !isDivider($0, in: next) }
        let before = remaining[..<index].last { !isDivider($0, in: next) }
        let collapsedDocument = collapsed(next)
        let destination = collapsedDocument.pages == nil ? nil : (after ?? before)?.id
        return EaselPageChange(document: collapsedDocument, page: destination, items: removed)
    }

    private static func scrubbing(_ removed: Set<UUID>, in document: EaselDocument) -> EaselDocument {
        guard !removed.isEmpty else { return document }
        var next = document
        for index in next.items.indices {
            if let target = next.items[index].attachedTo, removed.contains(target) { next.items[index].attachedTo = nil }
        }
        let freed = next.items.indices.filter { next.items[$0].kind == .arrow && EaselConnectorRouter.detached(next.items[$0], from: removed) != next.items[$0] }
        if !freed.isEmpty {
            var table: [UUID: EaselItem] = [:]
            for item in next.items where table[item.id] == nil { table[item.id] = item }
            for index in freed {
                next.items[index] = EaselConnectorRouter.settled(EaselConnectorRouter.detached(next.items[index], from: removed)) { table[$0] }
            }
        }
        return EaselArrange.dissolvingSingletonGroups(next)
    }

    package static func moveSet(_ ids: Set<UUID>, in view: EaselDocument) -> Set<UUID> {
        let present = Set(view.items.map(\.id))
        var moving = ids.intersection(present)
        guard !moving.isEmpty else { return [] }
        let arrows = view.items.filter { $0.kind == .arrow }
        let tree = view.items.contains { $0.mindMap != nil } ? EaselMindMap.tree(of: view.items) : nil
        while true {
            var grown = EaselBoardObjects.withContents(moving, in: view)
            grown.formUnion(EaselAttachments.dependents(of: grown, in: view))
            if let tree { for id in grown where tree.nodes[id] != nil { grown.formUnion(tree.descendants(of: id)) } }
            for arrow in arrows where !grown.contains(arrow.id) {
                let ends = [arrow.startConnection?.itemID, arrow.endConnection?.itemID].compactMap { $0 }
                if !ends.isEmpty, ends.allSatisfy(grown.contains) { grown.insert(arrow.id) }
            }
            grown.formIntersection(present)
            if grown == moving { return moving }
            moving = grown
        }
    }

    package static func movingItems(_ ids: Set<UUID>, to target: UUID, in document: EaselDocument) -> EaselPageChange? {
        guard let destination = document.pages?.first(where: { $0.id == target }), !isDivider(destination, in: document) else { return nil }
        var next = pinned(document)
        guard let anchor = next.items.first(where: { ids.contains($0.id) && $0.page != target }), let source = anchor.page else { return nil }
        let sourceView = view(next, page: source)
        let moving = moveSet(ids, in: sourceView)
        guard !moving.isEmpty else { return nil }
        let cut = Set(sourceView.items.filter { item in
            EaselMindMap.isBranch(item) && !moving.contains(item.id) && item.endConnection.map { moving.contains($0.itemID) } == true
        }.map(\.id))
        next.items.removeAll { cut.contains($0.id) }
        let staying = Set(sourceView.items.map(\.id)).subtracting(moving).subtracting(cut)

        var groupCounts: [UUID: (moving: Int, staying: Int)] = [:]
        for item in sourceView.items {
            guard let group = item.groupID else { continue }
            var count = groupCounts[group] ?? (0, 0)
            if moving.contains(item.id) { count.moving += 1 } else { count.staying += 1 }
            groupCounts[group] = count
        }
        var freshGroups: [UUID: UUID] = [:]
        for (group, count) in groupCounts where count.moving > 0 && count.staying > 0 { freshGroups[group] = UUID() }

        var top = (items(on: target, in: next).map(\.zIndex).max() ?? 0)
        let order = EaselArrange.paintOrder(sourceView).filter { moving.contains($0.id) }.map(\.id)
        var rank: [UUID: Int] = [:]
        let overflow = top > Int.max - order.count - 1
        if overflow { top = 0 }
        for (offset, id) in order.enumerated() where rank[id] == nil { rank[id] = top + offset + 1 }

        var freed = Set<UUID>()
        for index in next.items.indices {
            let id = next.items[index].id
            let isMoving = moving.contains(id)
            guard isMoving || staying.contains(id) else { continue }
            let other = isMoving ? staying : moving
            if isMoving {
                next.items[index].page = target
                if let group = next.items[index].groupID, let fresh = freshGroups[group] { next.items[index].groupID = fresh }
                if let value = rank[id] { next.items[index].zIndex = value }
                if EaselMindMap.isNode(next.items[index]), let parent = next.items[index].mindMap?.parent, !moving.contains(parent) {
                    next.items[index].mindMap = EaselMindMapLink()
                }
            }
            if next.items[index].kind == .arrow {
                var detached = EaselConnectorRouter.detached(next.items[index], from: other)
                if detached != next.items[index] {
                    if EaselMindMap.isBranch(detached) { detached.mindMap = nil }
                    next.items[index] = detached
                    freed.insert(id)
                }
            }
            if let attached = next.items[index].attachedTo, other.contains(attached) { next.items[index].attachedTo = nil }
        }
        if overflow {
            let targetItems = EaselArrange.paintOrder(view(next, page: target))
            var ranks: [UUID: Int] = [:]
            for (offset, item) in targetItems.enumerated() where ranks[item.id] == nil { ranks[item.id] = offset }
            for index in next.items.indices where next.items[index].page == target {
                if let value = ranks[next.items[index].id] { next.items[index].zIndex = value }
            }
        }
        next = settling(freed, in: next)
        return EaselPageChange(document: EaselArrange.dissolvingSingletonGroups(next), page: target, items: moving)
    }

    private static func settling(_ arrows: Set<UUID>, in document: EaselDocument) -> EaselDocument {
        guard !arrows.isEmpty else { return document }
        var next = document
        var tables: [UUID?: [UUID: EaselItem]] = [:]
        for item in next.items where tables[item.page]?[item.id] == nil { tables[item.page, default: [:]][item.id] = item }
        for index in next.items.indices where arrows.contains(next.items[index].id) {
            let table = tables[next.items[index].page] ?? [:]
            next.items[index] = EaselConnectorRouter.settled(next.items[index]) { table[$0] }
        }
        return next
    }
}

extension EaselPages {
    package static func followedPage(from original: EaselDocument, to after: EaselDocument, showing current: UUID?) -> UUID? {
        guard after.pages != nil else { return nil }
        var before = original
        var shown = current
        if before.pages == nil, let first = after.pages?.first {
            before.pages = [first]
            for index in before.items.indices { before.items[index].page = first.id }
            shown = first.id
        }
        let pageIDs = Set(after.pages?.map(\.id) ?? [])
        if let shown, pageIDs.contains(shown), view(before, page: shown).items == view(after, page: shown).items {
            var old: [UUID: EaselItem] = [:]
            for item in before.items where old[item.id] == nil { old[item.id] = item }
            var seen = Set<UUID>()
            for item in after.items {
                seen.insert(item.id)
                guard old[item.id] != item, let page = pageID(of: item, in: after), page != shown else { continue }
                return page
            }
            for item in before.items where !seen.contains(item.id) {
                guard let page = pageID(of: item, in: before), pageIDs.contains(page), page != shown else { continue }
                return page
            }
            if before.pages != after.pages, let added = after.pages?.first(where: { page in
                !(before.pages ?? []).contains { $0.id == page.id } && !isDivider(page, in: after)
            }) { return added.id }
            return shown
        }
        return resolvedPage(shown, in: after)
    }
}

extension EaselPages {
    package static func pageDocuments(_ document: EaselDocument) -> [EaselDocument] {
        guard let pages = document.pages else { return [document] }
        return pages.map { page in
            var view = document
            view.items = items(on: page.id, in: document)
            return view
        }
    }
}

extension EaselPages {
    package static func exportedPages(_ document: EaselDocument) -> [(id: UUID, name: String, items: [EaselItem])] {
        guard let pages = document.pages else { return [] }
        let content = pages.filter { !isDivider($0, in: document) }
        let filled = content.filter { itemCount(on: $0.id, in: document) > 0 }
        return (filled.isEmpty ? Array(content.prefix(1)) : filled).map { ($0.id, $0.name, items(on: $0.id, in: document)) }
    }
}
