import Combine
import Foundation

package struct NotePageChange {
    package enum Kind: Equatable { case text, structure, settings, selection, replaced }
    package var kind: Kind
    package var blocks: Set<NoteBlockID>
    package var origin: ObjectIdentifier?
    package var isUndoRedo = false
    package var revision: UInt64

    package init(kind: Kind, blocks: Set<NoteBlockID>, origin: ObjectIdentifier? = nil, isUndoRedo: Bool = false, revision: UInt64) {
        self.kind = kind
        self.blocks = blocks
        self.origin = origin
        self.isUndoRedo = isUndoRedo
        self.revision = revision
    }
}

package struct NoteUndoEffect {
    package var undo: @MainActor () -> Void
    package var redo: @MainActor () -> Void
    package var owner: ObjectIdentifier? = nil

    package init(undo: @escaping @MainActor () -> Void, redo: @escaping @MainActor () -> Void, owner: ObjectIdentifier? = nil) {
        self.undo = undo
        self.redo = redo
        self.owner = owner
    }
}

package enum NoteEditCoalescing: Hashable {
    case none
    case typing(NoteBlockID, NoteTextField)
    case deleting(NoteBlockID, NoteTextField)
    case adjusting(NoteBlockID)
    case lasting(NoteBlockID, UUID)

    var outlivesPauses: Bool {
        if case .lasting = self { return true }
        return false
    }
}

@MainActor
package final class NotePageSession {
    private struct HistoryStep {
        var page: NotePage
        var selectionBefore: NotePageSelection
        var selectionAfter: NotePageSelection
        var name: String
        var effects: [NoteUndoEffect] = []
        var serial = 0
    }

    private struct OpenGroup {
        var name: String
        var page: NotePage
        var selection: NotePageSelection
        var changed = false
        var continuing: NoteEditCoalescing = .none
        var effects: [NoteUndoEffect] = []
        var serial = 0
    }

    package private(set) var page: NotePage
    package private(set) var selection: NotePageSelection = .none
    package private(set) var revision: UInt64 = 0
    package let changes = PassthroughSubject<NotePageChange, Never>()
    package let settled = PassthroughSubject<NotePageChange, Never>()
    package var isReadOnly = false
    package var isFlat = false
    package var now: () -> Date = Date.init
    var undoLimit = 300
    var typingCoalesceInterval: TimeInterval = 1.5
    private var undoStack: [HistoryStep] = []
    private var redoStack: [HistoryStep] = []
    private var lastCoalescing: NoteEditCoalescing = .none
    private var lastEditTime = Date.distantPast
    private var openGroup: OpenGroup?
    private var lastSerial = 0

    package init(page: NotePage) {
        self.page = page.blocks.isEmpty ? NotePage(settings: page.settings, blocks: [.paragraph()]) : page
    }

    package var canUndo: Bool { !undoStack.isEmpty }
    package var canRedo: Bool { !redoStack.isEmpty }
    package var undoActionName: String? { undoStack.last?.name }
    package var redoActionName: String? { redoStack.last?.name }
    var undoDepth: Int { undoStack.count }
    var redoDepth: Int { redoStack.count }
    var isGrouping: Bool { openGroup != nil }
    var historyToken: Int? { openGroup?.serial ?? undoStack.last?.serial }

    func replacePage(_ value: NotePage, selection next: NotePageSelection = .none, keepHistory: Bool = false) {
        page = value.blocks.isEmpty ? NotePage(settings: value.settings, blocks: [.paragraph()]) : value
        selection = next
        if !keepHistory {
            undoStack.removeAll()
            redoStack.removeAll()
            if openGroup != nil { openGroup?.page = page; openGroup?.selection = next; openGroup?.changed = false }
        }
        breakCoalescing()
        revision &+= 1
        publish(NotePageChange(kind: .replaced, blocks: Set(page.documentOrder()), origin: nil, revision: revision))
    }

    package func setSelection(_ value: NotePageSelection, origin: AnyObject? = nil) {
        guard value != selection else { return }
        if Self.coalescingTarget(lastCoalescing) != Self.typingTarget(of: value) { breakCoalescing() }
        selection = value
        publish(NotePageChange(kind: .selection, blocks: [], origin: origin.map(ObjectIdentifier.init), revision: revision))
    }

    package func breakCoalescing() { lastCoalescing = .none }

    package func edit(_ name: String, kind: NotePageChange.Kind = .structure, coalescing: NoteEditCoalescing = .none,
              affected: Set<NoteBlockID>? = nil, origin: AnyObject? = nil, selection after: NotePageSelection? = nil,
              effect: NoteUndoEffect? = nil, _ body: (inout NotePage) throws -> Void) rethrows {
        try edit(name, kind: kind, coalescing: coalescing, affected: affected, origin: origin, selecting: { _ in after },
                 effect: effect, body)
    }

    package func edit(_ name: String, kind: NotePageChange.Kind = .structure, coalescing: NoteEditCoalescing = .none,
              affected: Set<NoteBlockID>? = nil, origin: AnyObject? = nil,
              selecting: (NotePage) -> NotePageSelection?, effect: NoteUndoEffect? = nil,
              _ body: (inout NotePage) throws -> Void) rethrows {
        guard !isReadOnly else { return }
        var next = page
        try body(&next)
        if next.blocks.isEmpty { next.blocks = [.paragraph()] }
        let after = selecting(next)
        let changed = next != page
        guard changed || (after != nil && after != selection) else { return }
        let time = now()
        if changed {
            record(name, coalescing: coalescing, time: time)
            if let effect { attach(effect) }
        }
        lastCoalescing = coalescing
        lastEditTime = time
        let changedBlocks = changed ? (affected ?? Self.changedBlocks(from: page, to: next)) : []
        page = next
        if let after { selection = after }
        if changed, openGroup == nil, !undoStack.isEmpty { undoStack[undoStack.count - 1].selectionAfter = selection }
        revision &+= 1
        publish(NotePageChange(kind: changed ? kind : .selection, blocks: changedBlocks,
                               origin: origin.map(ObjectIdentifier.init), revision: revision))
    }

    @discardableResult
    package func group<Result>(_ name: String, _ body: () throws -> Result) rethrows -> Result {
        try group(name, continuing: .none, body)
    }

    @discardableResult
    package func group<Result>(_ name: String, continuing: NoteEditCoalescing, _ body: () throws -> Result) rethrows -> Result {
        if openGroup != nil { return try body() }
        breakCoalescing()
        openGroup = OpenGroup(name: name, page: page, selection: selection, continuing: continuing, serial: nextSerial())
        defer { closeGroup() }
        return try body()
    }

    private func closeGroup() {
        guard let group = openGroup else { return }
        openGroup = nil
        if group.changed {
            pushUndo(HistoryStep(page: group.page.withoutIndex, selectionBefore: group.selection, selectionAfter: selection,
                                 name: group.name, effects: group.effects, serial: group.serial))
            redoStack.removeAll()
        }
        if group.changed && group.continuing != .none {
            lastCoalescing = group.continuing
            lastEditTime = now()
        } else {
            breakCoalescing()
        }
    }

    package func undo() {
        guard openGroup == nil, !isReadOnly, let step = undoStack.popLast() else { return }
        redoStack.append(HistoryStep(page: page.withoutIndex, selectionBefore: step.selectionBefore,
                                     selectionAfter: step.selectionAfter, name: step.name, effects: step.effects, serial: step.serial))
        let change = restore(step.page, selection: step.selectionBefore)
        for effect in step.effects.reversed() { effect.undo() }
        settled.send(change)
    }

    package func redo() {
        guard openGroup == nil, !isReadOnly, let step = redoStack.popLast() else { return }
        for effect in step.effects { effect.redo() }
        pushUndo(HistoryStep(page: page.withoutIndex, selectionBefore: step.selectionBefore,
                             selectionAfter: step.selectionAfter, name: step.name, effects: step.effects, serial: step.serial))
        let change = restore(step.page, selection: step.selectionAfter)
        settled.send(change)
    }

    @discardableResult
    func attachToLastStep(_ effect: NoteUndoEffect) -> Bool {
        if openGroup != nil {
            guard openGroup?.effects.contains(where: { $0.owner != nil && $0.owner == effect.owner }) != true else { return false }
            openGroup?.effects.append(effect)
            return true
        }
        guard !undoStack.isEmpty, !undoStack[undoStack.count - 1].effects.contains(where: { $0.owner != nil && $0.owner == effect.owner })
        else { return false }
        undoStack[undoStack.count - 1].effects.append(effect)
        return true
    }

    @discardableResult
    func applyLinked(_ name: String, owner: ObjectIdentifier, effect: () -> NoteUndoEffect, origin: AnyObject? = nil,
                     _ body: (inout NotePage) -> Void) -> Bool {
        guard !isReadOnly else { return false }
        var next = page
        body(&next)
        if next.blocks.isEmpty { next.blocks = [.paragraph()] }
        guard next != page else { return true }
        if openGroup != nil {
            openGroup?.changed = true
            if openGroup?.effects.contains(where: { $0.owner == owner }) != true { openGroup?.effects.append(effect()) }
        } else if undoStack.last?.effects.contains(where: { $0.owner == owner }) == true {
            redoStack.removeAll()
        } else {
            pushUndo(HistoryStep(page: page.withoutIndex, selectionBefore: selection, selectionAfter: selection, name: name,
                                 effects: [effect()], serial: nextSerial()))
            redoStack.removeAll()
            breakCoalescing()
        }
        commit(next, origin: origin)
        return true
    }

    func applyUntracked(origin: AnyObject? = nil, _ body: (inout NotePage) -> Void) {
        guard !isReadOnly else { return }
        var next = page
        body(&next)
        if next.blocks.isEmpty { next.blocks = [.paragraph()] }
        guard next != page else { return }
        commit(next, origin: origin)
    }

    private func commit(_ next: NotePage, origin: AnyObject?) {
        let changed = Self.changedBlocks(from: page, to: next)
        page = next
        selection = next.clamped(selection)
        revision &+= 1
        publish(NotePageChange(kind: .structure, blocks: changed, origin: origin.map(ObjectIdentifier.init), revision: revision))
    }

    private func publish(_ change: NotePageChange) {
        changes.send(change)
        settled.send(change)
    }

    private func nextSerial() -> Int {
        lastSerial += 1
        return lastSerial
    }

    @discardableResult
    package func undo(ifTopBelongsTo owner: ObjectIdentifier) -> Bool {
        guard openGroup == nil, !isReadOnly, undoStack.last?.effects.contains(where: { $0.owner == owner }) == true else { return false }
        undo()
        return true
    }

    @discardableResult
    package func redo(ifTopBelongsTo owner: ObjectIdentifier) -> Bool {
        guard openGroup == nil, !isReadOnly, redoStack.last?.effects.contains(where: { $0.owner == owner }) == true else { return false }
        redo()
        return true
    }

    package func updateBlockMetadata(_ id: NoteBlockID, kind: NotePageChange.Kind = .text, _ transform: (inout NoteBlock) -> Void) {
        guard !isReadOnly, page.block(id) != nil else { return }
        var next = page
        next.update(id, transform)
        guard next != page else { return }
        page = next
        for index in undoStack.indices where undoStack[index].page.contains(id) {
            undoStack[index].page.update(id, transform)
            undoStack[index].page = undoStack[index].page.withoutIndex
        }
        for index in redoStack.indices where redoStack[index].page.contains(id) {
            redoStack[index].page.update(id, transform)
            redoStack[index].page = redoStack[index].page.withoutIndex
        }
        if var group = openGroup {
            group.page.update(id, transform)
            openGroup = group
        }
        revision &+= 1
        publish(NotePageChange(kind: kind, blocks: [id], origin: nil, revision: revision))
    }

    func updateAllPagesMetadata(_ transform: (NotePage) -> NotePage) {
        let next = transform(page)
        for index in undoStack.indices { undoStack[index].page = transform(undoStack[index].page).withoutIndex }
        for index in redoStack.indices { redoStack[index].page = transform(redoStack[index].page).withoutIndex }
        if var group = openGroup {
            group.page = transform(group.page)
            openGroup = group
        }
        guard next != page else { return }
        let changed = Self.changedBlocks(from: page, to: next)
        page = next
        revision &+= 1
        changes.send(NotePageChange(kind: .text, blocks: changed, origin: nil, revision: revision))
    }

    func updateSettingsMetadata(_ transform: (inout NotePageSettings) -> Void) {
        guard !isReadOnly else { return }
        for index in undoStack.indices { transform(&undoStack[index].page.settings) }
        for index in redoStack.indices { transform(&redoStack[index].page.settings) }
        if var group = openGroup {
            transform(&group.page.settings)
            openGroup = group
        }
        var settings = page.settings
        transform(&settings)
        guard settings != page.settings else { return }
        page.settings = settings
        revision &+= 1
        publish(NotePageChange(kind: .settings, blocks: [], origin: nil, revision: revision))
    }

    package func ensureSyncedAnchors(within ids: some Sequence<NoteBlockID>) {
        for id in page.syncedOriginals(within: ids) where page.block(id)?.props.anchor == nil { ensureAnchor(for: id) }
    }

    @discardableResult
    package func ensureAnchor(for id: NoteBlockID) -> String? {
        var generator = SystemRandomNumberGenerator()
        return ensureAnchor(for: id, using: &generator)
    }

    @discardableResult
    package func ensureAnchor<Generator: RandomNumberGenerator>(for id: NoteBlockID, using generator: inout Generator) -> String? {
        guard let block = page.block(id) else { return nil }
        if let existing = block.props.anchor, !existing.isEmpty { return existing }
        guard !isReadOnly else { return nil }
        var history = Set<String>()
        for step in undoStack + redoStack { history.formUnion(step.page.blockAnchors) }
        let anchor = page.uniqueAnchor(using: &generator, avoiding: history)
        updateBlockMetadata(id) { block in
            if block.props.anchor == nil { block.props.anchor = anchor }
        }
        return page.block(id)?.props.anchor
    }

    func clearHistory() {
        undoStack.removeAll()
        redoStack.removeAll()
        breakCoalescing()
    }

    private func record(_ name: String, coalescing: NoteEditCoalescing, time: Date) {
        if openGroup != nil {
            openGroup?.changed = true
            return
        }
        let coalesce = coalescing != .none && coalescing == lastCoalescing && !undoStack.isEmpty
            && (coalescing.outlivesPauses || time.timeIntervalSince(lastEditTime) < typingCoalesceInterval)
        if !coalesce {
            pushUndo(HistoryStep(page: page.withoutIndex, selectionBefore: selection, selectionAfter: selection, name: name, serial: nextSerial()))
        }
        redoStack.removeAll()
    }

    private func attach(_ effect: NoteUndoEffect) {
        if openGroup != nil {
            openGroup?.effects.append(effect)
        } else if !undoStack.isEmpty {
            undoStack[undoStack.count - 1].effects.append(effect)
        }
    }

    private func pushUndo(_ step: HistoryStep) {
        undoStack.append(step)
        if undoStack.count > undoLimit { undoStack.removeFirst(undoStack.count - undoLimit) }
    }

    private func restore(_ target: NotePage, selection next: NotePageSelection) -> NotePageChange {
        let changed = Self.changedBlocks(from: page, to: target)
        page = target
        selection = next
        breakCoalescing()
        revision &+= 1
        let change = NotePageChange(kind: .structure, blocks: changed, origin: nil, isUndoRedo: true, revision: revision)
        changes.send(change)
        return change
    }

    private static func coalescingTarget(_ value: NoteEditCoalescing) -> NotePosition? {
        switch value {
        case .typing(let block, let field), .deleting(let block, let field): return NotePosition(block, 0, field: field)
        case .none, .adjusting, .lasting: return nil
        }
    }

    private static func typingTarget(of selection: NotePageSelection) -> NotePosition? {
        guard let caret = selection.caret else { return nil }
        return NotePosition(caret.block, 0, field: caret.field)
    }

    static func changedBlocks(from old: NotePage, to new: NotePage) -> Set<NoteBlockID> {
        var result = Set<NoteBlockID>()
        func insertSubtree(_ list: [NoteBlock]) {
            for block in list {
                result.insert(block.id)
                insertSubtree(block.children)
            }
        }
        func previousSibling(of id: NoteBlockID, in page: NotePage) -> NoteBlockID? {
            guard let index = page.path(of: id)?.last, index > 0 else { return nil }
            let siblings = page.siblings(of: id)
            return siblings.indices.contains(index - 1) ? siblings[index - 1].id : nil
        }
        func scan(_ list: [NoteBlock], parent: NoteBlockID?, against other: NotePage, reportsContent: Bool) {
            for (index, block) in list.enumerated() {
                guard let counterpart = other.block(block.id) else {
                    result.insert(block.id)
                    insertSubtree(block.children)
                    continue
                }
                if reportsContent && (other.parent(of: block.id) != parent
                    || previousSibling(of: block.id, in: other) != (index > 0 ? list[index - 1].id : nil)) {
                    result.insert(block.id)
                }
                if counterpart == block { continue }
                if reportsContent && !block.sameContent(as: counterpart) { result.insert(block.id) }
                scan(block.children, parent: block.id, against: other, reportsContent: reportsContent)
            }
        }
        scan(new.blocks, parent: nil, against: old, reportsContent: true)
        scan(old.blocks, parent: nil, against: new, reportsContent: false)
        return result
    }
}

@MainActor
package final class NoteCreatedFile {
    package let url: URL
    package let contents: Data
    private let trash: (URL) throws -> URL?
    private var withdrawn = false
    private var trashedURL: URL?

    package init(url: URL, contents: Data, trash: @escaping (URL) throws -> URL? = NoteCreatedFile.moveToTrash) {
        self.url = url
        self.contents = contents
        self.trash = trash
    }

    package nonisolated static func moveToTrash(_ url: URL) throws -> URL? {
        var resulting: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &resulting)
        return resulting as URL?
    }

    var isWithdrawn: Bool { withdrawn }

    package var effect: NoteUndoEffect {
        NoteUndoEffect(undo: { [self] in withdraw() }, redo: { [self] in restore() })
    }

    package func withdraw() {
        guard !withdrawn, FileManager.default.contents(atPath: url.path) == contents else { return }
        do {
            trashedURL = try trash(url)
            withdrawn = true
        } catch {
            trashedURL = nil
        }
    }

    package func restore() {
        guard withdrawn else { return }
        withdrawn = false
        let manager = FileManager.default
        defer { trashedURL = nil }
        guard !manager.fileExists(atPath: url.path) else { return }
        if let trashedURL, manager.fileExists(atPath: trashedURL.path), (try? manager.moveItem(at: trashedURL, to: url)) != nil { return }
        try? contents.write(to: url, options: .withoutOverwriting)
    }
}
