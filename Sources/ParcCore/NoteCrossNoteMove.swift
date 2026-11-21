import Foundation

@MainActor
package final class NoteCrossNoteMove {
    package typealias Access = @MainActor (_ body: (NotePageSession) -> Void) -> Bool

    private enum Side { case source, target }

    private let reachSource: Access
    private let reachTarget: Access
    private var seen: [Side: NotePageSession] = [:]
    private let name: String
    private let schedule: @Sendable (@escaping @Sendable () -> Void) -> Void
    private var originals: [NoteBlock]
    private var placements: [NoteInsertion]
    private var copies: [NoteBlock]
    package private(set) var isApplied = false

    package var originalIDs: [NoteBlockID] { originals.map(\.id) }
    package var copyIDs: [NoteBlockID] { copies.map(\.id) }

    private init(name: String, originals: [NoteBlock], placements: [NoteInsertion], source: @escaping Access, target: @escaping Access,
                 schedule: @escaping @Sendable (@escaping @Sendable () -> Void) -> Void) {
        self.name = name
        self.schedule = schedule
        self.originals = originals
        self.placements = placements
        self.copies = originals.map { $0.withFreshIDs() }
        self.reachSource = source
        self.reachTarget = target
    }

    private func source(_ body: (NotePageSession) -> Void) -> Bool { reach(.source, body) }
    private func target(_ body: (NotePageSession) -> Void) -> Bool { reach(.target, body) }

    private func reach(_ side: Side, _ body: (NotePageSession) -> Void) -> Bool {
        let access = side == .source ? reachSource : reachTarget
        return access { session in
            if let previous = seen[side], previous !== session { rekey(side, from: previous.page, to: session.page) }
            seen[side] = session
            body(session)
        }
    }

    private func rekey(_ side: Side, from old: NotePage, to new: NotePage) {
        let carried = NoteFileReconciler.preservingIdentity(of: old, in: new)
        var current: [NoteBlockID: NoteBlockID] = [:]
        for (kept, fresh) in zip(carried.allBlocks(), new.allBlocks()) where kept.id != fresh.id { current[kept.id] = fresh.id }
        guard !current.isEmpty else { return }
        func swap(_ id: NoteBlockID) -> NoteBlockID { current[id] ?? id }
        func swapped(_ block: NoteBlock) -> NoteBlock {
            var block = block
            block.id = swap(block.id)
            return block
        }
        switch side {
        case .target:
            copies = copies.map(swapped)
        case .source:
            originals = originals.map(swapped)
            placements = placements.map { placement in
                switch placement {
                case .after(let id): .after(swap(id))
                case .before(let id): .before(swap(id))
                case .firstChild(let id): .firstChild(of: swap(id))
                case .lastChild(let id): .lastChild(of: swap(id))
                case .top(let index): .top(index)
                }
            }
        }
    }

    package static func perform(_ ids: [NoteBlockID], from session: NotePageSession, name: String,
                        target: @escaping Access, source: Access? = nil,
                        schedule: @escaping @Sendable (@escaping @Sendable () -> Void) -> Void = { DispatchQueue.main.async(execute: $0) }) -> NoteCrossNoteMove? {
        let page = session.page
        let top = page.topLevelSelection(ids)
        let blocks = top.compactMap { page.block($0) }
        guard !blocks.isEmpty, !session.isReadOnly else { return nil }
        let sourceAccess: Access = source ?? { [weak session] body in
            guard let session else { return false }
            body(session)
            return true
        }
        let move = NoteCrossNoteMove(name: name, originals: blocks, placements: top.map { placement(of: $0, in: page) },
                                     source: sourceAccess, target: target, schedule: schedule)
        move.seen[.source] = session
        var landed = false
        let reached = move.target { other in
            guard other !== session else { return }
            move.append(to: other, label: "Move Here")
            landed = move.copyIDs.allSatisfy(other.page.contains)
        }
        guard reached, landed else { return nil }
        move.isApplied = true
        move.removeOriginals(from: session, label: name, caret: true)
        return move
    }

    private func effect(_ side: Side) -> NoteUndoEffect {
        NoteUndoEffect(undo: { [self] in reverse(by: side) }, redo: { [self] in reapply(by: side) }, owner: ObjectIdentifier(self))
    }

    private func reversal(_ side: Side) -> NoteUndoEffect {
        NoteUndoEffect(undo: { [self] in reapply(by: side) }, redo: { [self] in reverse(by: side) }, owner: ObjectIdentifier(self))
    }

    private func reverse(by side: Side) {
        guard isApplied else { return }
        isApplied = false
        switch side {
        case .source:
            _ = target { other in
                if !retrace(other, undoing: true) { removeCopies(from: other) }
            }
        case .target:
            var restored = false
            _ = source { other in
                if !retrace(other, undoing: true) { restoreOriginals(in: other) }
                restored = originalIDs.allSatisfy(other.page.contains)
            }
            guard !restored else { return }
            isApplied = true
            settle { move in
                guard move.isApplied else { return }
                _ = move.target { other in move.append(to: other, label: "Move Here") }
            }
        }
    }

    private func reapply(by side: Side) {
        guard !isApplied else { return }
        isApplied = true
        switch side {
        case .source:
            var landed = false
            _ = target { other in
                if !retrace(other, undoing: false) { append(to: other, label: "Move Here") }
                landed = copyIDs.allSatisfy(other.page.contains)
            }
            guard !landed else { return }
            isApplied = false
            settle { move in
                guard !move.isApplied else { return }
                _ = move.source { other in move.restoreOriginals(in: other) }
            }
        case .target:
            _ = source { other in
                if !retrace(other, undoing: false) { removeOriginals(from: other, label: name, caret: false) }
            }
        }
    }

    private func retrace(_ session: NotePageSession, undoing: Bool) -> Bool {
        let owner = ObjectIdentifier(self)
        return undoing ? session.undo(ifTopBelongsTo: owner) || session.redo(ifTopBelongsTo: owner)
            : session.redo(ifTopBelongsTo: owner) || session.undo(ifTopBelongsTo: owner)
    }

    private func settle(_ body: @escaping @MainActor (NoteCrossNoteMove) -> Void) {
        schedule { [self] in
            MainActor.assumeIsolated { body(self) }
        }
    }

    private func append(to session: NotePageSession, label: String) {
        let missing = copies.filter { !session.page.contains($0.id) }
        guard !missing.isEmpty else { return }
        let blocks = session.page.blocks
        let lone = blocks.count == 1 && blocks[0].kind == .paragraph && blocks[0].text.isEmpty && blocks[0].children.isEmpty
        session.edit(label, selection: lone ? NotePageSelection.none : session.selection, effect: effect(.target)) { page in
            if lone { page.blocks = missing } else { page.blocks.append(contentsOf: missing) }
        }
    }

    private func removeCopies(from session: NotePageSession) {
        let present = copyIDs.filter(session.page.contains)
        guard !present.isEmpty else { return }
        copies = copies.map { session.page.block($0.id) ?? $0 }
        session.edit("Undo Move", selection: session.selection, effect: reversal(.target)) { page in
            page.removeBlocks(present)
            page.collapseEmptyColumns()
        }
    }

    private func restoreOriginals(in session: NotePageSession) {
        let missing = Array(zip(originals, placements)).filter { !session.page.contains($0.0.id) }
        guard !missing.isEmpty else { return }
        session.edit("Undo Move", selection: session.selection, effect: reversal(.source)) { page in
            for (block, placement) in missing where !page.insert([block], placement) {
                page.insert([block], .top(page.blocks.count))
            }
        }
    }

    private func removeOriginals(from session: NotePageSession, label: String, caret: Bool) {
        let page = session.page
        let present = originalIDs.filter(page.contains)
        guard !present.isEmpty else { return }
        originals = originals.map { page.block($0.id) ?? $0 }
        let removed = Set(present)
        let neighbour = caret ? Self.survivingNeighbour(of: present, removed: removed, in: page) : nil
        session.edit(label, selecting: { next in
            guard caret else { return nil }
            if let neighbour, next.contains(neighbour.id) {
                return neighbour.before ? next.caretSelection(atEndOf: neighbour.id) : next.caretSelection(atStartOf: neighbour.id)
            }
            return next.blocks.first.map { next.caretSelection(atStartOf: $0.id) } ?? NotePageSelection.none
        }, effect: effect(.source)) { next in
            next.removeBlocks(present)
            next.collapseEmptyColumns()
        }
    }

    private static func placement(of id: NoteBlockID, in page: NotePage) -> NoteInsertion {
        if let parent = page.parent(of: id), let siblings = page.block(parent)?.children {
            guard let index = siblings.firstIndex(where: { $0.id == id }) else { return .lastChild(of: parent) }
            return index == 0 ? .firstChild(of: parent) : .after(siblings[index - 1].id)
        }
        guard let index = page.blocks.firstIndex(where: { $0.id == id }) else { return .top(page.blocks.count) }
        return index == 0 ? .top(0) : .after(page.blocks[index - 1].id)
    }

    private static func survivingNeighbour(of ids: [NoteBlockID], removed: Set<NoteBlockID>,
                                           in page: NotePage) -> (id: NoteBlockID, before: Bool)? {
        let order = page.index.visibleIDs
        guard let first = ids.first, let start = page.visiblePosition(of: first) else { return nil }
        func usable(_ id: NoteBlockID) -> Bool {
            page.block(id)?.kind.isColumnStructure == false && !removed.contains(id)
                && !page.ancestors(of: id).contains(where: removed.contains)
        }
        if let before = order[..<min(start, order.count)].last(where: usable) { return (before, true) }
        if start + 1 < order.count, let after = order[(start + 1)...].first(where: usable) { return (after, false) }
        return nil
    }
}
