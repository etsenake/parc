import Foundation

extension NotePage {
    package func canTurnIntoSynced(_ ids: [NoteBlockID]) -> Bool {
        let top = topLevelSelection(ids)
        guard !top.isEmpty else { return false }
        return top.allSatisfy { id in
            guard let block = block(id) else { return false }
            return block.kind != .column && !block.containsSynced && syncedSite(containing: id) == nil
        }
    }

    func syncedPlacement(of id: NoteBlockID) -> NoteInsertion {
        if let parent = parent(of: id), let siblings = block(parent)?.children {
            guard let index = siblings.firstIndex(where: { $0.id == id }) else { return .lastChild(of: parent) }
            return index == 0 ? .firstChild(of: parent) : .after(siblings[index - 1].id)
        }
        guard let index = blocks.firstIndex(where: { $0.id == id }) else { return .top(blocks.count) }
        return .top(index)
    }
}

extension NotePageSession {
    @discardableResult
    package func turnIntoSynced(_ ids: [NoteBlockID]) -> NoteBlockID? {
        guard !isReadOnly, !isFlat, page.canTurnIntoSynced(ids) else { return nil }
        let top = page.topLevelSelection(ids)
        let blocks = top.compactMap { page.block($0) }
        guard let first = top.first, !blocks.isEmpty else { return nil }
        let placement = page.syncedPlacement(of: first)
        let synced = NoteBlock(.synced, children: blocks)
        edit("Turn into Synced Block", selection: .blocks([synced.id])) { page in
            page.removeBlocks(top)
            if !page.insert([synced], placement) { page.insert([synced], .top(page.blocks.count)) }
            page.collapseEmptyColumns()
        }
        return page.contains(synced.id) ? synced.id : nil
    }

    @discardableResult
    func insertSyncedBlock(replacing id: NoteBlockID) -> NoteBlockID? {
        guard !isReadOnly, !isFlat, let block = page.block(id), page.syncedSite(containing: id) == nil else { return nil }
        let inner = NoteBlock.paragraph()
        let synced = NoteBlock(.synced, children: [inner])
        let replaces = block.kind == .paragraph && block.text.isEmpty && block.children.isEmpty
        edit("Synced Block", selection: .caret(NotePosition(inner.id, 0))) { page in
            page.insert([synced], .after(id))
            if replaces { page.remove(id) }
        }
        return page.contains(synced.id) ? synced.id : nil
    }

    @discardableResult
    package func unsync(_ id: NoteBlockID, name: String = "Unsync", effect: NoteUndoEffect? = nil) -> Bool {
        guard !isReadOnly, let block = page.block(id), block.kind == .synced else { return false }
        let children = block.children.isEmpty ? [NoteBlock.paragraph()] : block.children
        let landing: NotePageSelection = .blocks(children.map(\.id))
        let placement = page.syncedPlacement(of: id)
        edit(name, selection: landing, effect: effect) { page in
            page.remove(id)
            if !page.insert(children, placement) { page.insert(children, .top(page.blocks.count)) }
        }
        return !page.contains(id)
    }

    package func syncedClipboardBlocks(_ blocks: [NoteBlock], documentURL: URL?) -> [NoteBlock] {
        let folder = documentURL?.deletingLastPathComponent()
        return blocks.map { block in
            block.referencingSyncedOriginals { anchor in
                NoteSyncedReference.portableTarget(anchor: anchor, original: documentURL, folder: folder)
            }.portableSyncedTargets(documentURL: documentURL)
        }
    }
}

extension NoteBlock {
    package func portableSyncedTargets(documentURL: URL?) -> NoteBlock {
        var copy = self
        if isSyncedCopy, let target = props.target, let reference = NoteSyncedReference(target), reference.path == nil {
            copy.props.target = NoteSyncedReference.portableTarget(anchor: reference.anchor, original: documentURL,
                                                                   folder: documentURL?.deletingLastPathComponent())
        }
        guard !children.isEmpty, kind != .synced else { return copy }
        copy.children = children.map { $0.portableSyncedTargets(documentURL: documentURL) }
        return copy
    }

    package func localizingSyncedTargets(documentURL: URL?) -> NoteBlock {
        var copy = self
        if isSyncedCopy, let target = props.target, let reference = NoteSyncedReference(target), reference.path != nil,
           let documentURL, let url = reference.url(relativeTo: documentURL),
           NoteFilePaths.key(for: url) == NoteFilePaths.key(for: documentURL) {
            copy.props.target = "#" + NoteFilePaths.encodedSegment(reference.anchor)
        }
        guard !children.isEmpty, kind != .synced else { return copy }
        copy.children = children.map { $0.localizingSyncedTargets(documentURL: documentURL) }
        return copy
    }
}

extension NoteSyncedReference {
    static func portableTarget(anchor: String, original: URL?, folder: URL?) -> String {
        let fragment = "#" + NoteFilePaths.encodedSegment(anchor)
        guard let original else { return fragment }
        let file = URL(fileURLWithPath: original.path)
        if let folder, let relative = NoteFilePaths.relativePath(from: folder, to: file) { return relative + fragment }
        return file.absoluteString + fragment
    }
}
