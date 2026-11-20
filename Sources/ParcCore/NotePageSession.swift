import Combine
import Foundation

struct NotePageChange {
    enum Kind: Equatable { case text, structure, settings, selection, replaced }
    var kind: Kind
    var blocks: Set<NoteBlockID>
    var origin: ObjectIdentifier?
    var isUndoRedo = false
    var revision: UInt64
}

enum NoteEditCoalescing: Hashable {
    case none
    case typing(NoteBlockID, NoteTextField)
}

@MainActor
final class NotePageSession {
    private struct Snapshot {
        var page: NotePage
        var selection: NotePageSelection
        var name: String
        var coalescing: NoteEditCoalescing
        var time: Date
    }

    private(set) var page: NotePage
    private(set) var selection: NotePageSelection = .none
    private(set) var revision: UInt64 = 0
    let changes = PassthroughSubject<NotePageChange, Never>()
    var isReadOnly = false
    var now: () -> Date = Date.init
    var undoLimit = 300
    var typingCoalesceInterval: TimeInterval = 1.5
    private var undoStack: [Snapshot] = []
    private var redoStack: [Snapshot] = []
    private var lastCoalescing: NoteEditCoalescing = .none
    private var lastEditTime = Date.distantPast

    init(page: NotePage) {
        self.page = page.blocks.isEmpty ? NotePage(settings: page.settings, blocks: [.paragraph()]) : page
    }

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }
    var undoActionName: String? { undoStack.last?.name }
    var redoActionName: String? { redoStack.last?.name }

    func replacePage(_ value: NotePage, selection next: NotePageSelection = .none, keepHistory: Bool = false) {
        page = value.blocks.isEmpty ? NotePage(settings: value.settings, blocks: [.paragraph()]) : value
        selection = next
        if !keepHistory { undoStack.removeAll(); redoStack.removeAll() }
        breakCoalescing()
        revision &+= 1
        changes.send(NotePageChange(kind: .replaced, blocks: Set(page.documentOrder()), origin: nil, revision: revision))
    }

    func setSelection(_ value: NotePageSelection, origin: AnyObject? = nil) {
        guard value != selection else { return }
        if case .text(_, let head) = value, case .typing(let block, let field) = lastCoalescing,
           head.block != block || head.field != field { breakCoalescing() }
        selection = value
        changes.send(NotePageChange(kind: .selection, blocks: [], origin: origin.map(ObjectIdentifier.init), revision: revision))
    }

    func breakCoalescing() { lastCoalescing = .none }

    func edit(_ name: String, kind: NotePageChange.Kind = .structure, coalescing: NoteEditCoalescing = .none,
              affected: Set<NoteBlockID>? = nil, origin: AnyObject? = nil, selection after: NotePageSelection? = nil,
              _ body: (inout NotePage) throws -> Void) rethrows {
        guard !isReadOnly else { return }
        var next = page
        try body(&next)
        if next.blocks.isEmpty { next.blocks = [.paragraph()] }
        guard next != page || (after != nil && after != selection) else { return }
        let time = now()
        let coalesce = coalescing != .none && coalescing == lastCoalescing
            && time.timeIntervalSince(lastEditTime) < typingCoalesceInterval && !undoStack.isEmpty
        if next != page && !coalesce {
            undoStack.append(Snapshot(page: page, selection: selection, name: name, coalescing: coalescing, time: time))
            if undoStack.count > undoLimit { undoStack.removeFirst(undoStack.count - undoLimit) }
        }
        if next != page { redoStack.removeAll() }
        lastCoalescing = coalescing
        lastEditTime = time
        let changed = affected ?? Self.changedBlocks(from: page, to: next)
        page = next
        if let after { selection = after }
        revision &+= 1
        changes.send(NotePageChange(kind: kind, blocks: changed, origin: origin.map(ObjectIdentifier.init), revision: revision))
    }

    func undo() {
        guard let snapshot = undoStack.popLast() else { return }
        redoStack.append(Snapshot(page: page, selection: selection, name: snapshot.name, coalescing: .none, time: now()))
        restore(snapshot)
    }

    func redo() {
        guard let snapshot = redoStack.popLast() else { return }
        undoStack.append(Snapshot(page: page, selection: selection, name: snapshot.name, coalescing: .none, time: now()))
        restore(snapshot)
    }

    private func restore(_ snapshot: Snapshot) {
        let changed = Self.changedBlocks(from: page, to: snapshot.page)
        page = snapshot.page
        selection = snapshot.selection
        breakCoalescing()
        revision &+= 1
        changes.send(NotePageChange(kind: .structure, blocks: changed, origin: nil, isUndoRedo: true, revision: revision))
    }

    static func changedBlocks(from old: NotePage, to new: NotePage) -> Set<NoteBlockID> {
        var before: [NoteBlockID: NoteBlock] = [:]
        for block in old.allBlocks() { before[block.id] = block }
        var result = Set<NoteBlockID>()
        for block in new.allBlocks() {
            guard let previous = before.removeValue(forKey: block.id) else { result.insert(block.id); continue }
            if previous.kind != block.kind || previous.text != block.text || previous.props != block.props
                || previous.color != block.color || previous.children.map(\.id) != block.children.map(\.id) {
                result.insert(block.id)
            }
        }
        result.formUnion(before.keys)
        return result
    }
}
