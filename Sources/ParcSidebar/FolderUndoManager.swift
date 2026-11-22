import AppKit
import ParcCore

@MainActor
package final class FolderUndoManager: UndoManager {
    package override init() { super.init() }
    package enum Direction { case undo, redo }
    package final class Entry {
        let id = UUID()
        let name: (Direction) -> String
        let isValid: (Direction) -> Bool
        let isAvailable: (Direction) -> Bool
        let perform: (Direction, @escaping (Bool) -> Void) -> Void
        init(names: @escaping (Direction) -> String, isValid: @escaping (Direction) -> Bool,
             isAvailable: @escaping (Direction) -> Bool,
             perform: @escaping (Direction, @escaping (Bool) -> Void) -> Void) {
            name = names; self.isValid = isValid; self.isAvailable = isAvailable; self.perform = perform
        }
        package convenience init(name: String, isValid: @escaping (Direction) -> Bool,
                         isAvailable: @escaping (Direction) -> Bool,
                         perform: @escaping (Direction, @escaping (Bool) -> Void) -> Void) {
            self.init(names: { _ in name }, isValid: isValid, isAvailable: isAvailable, perform: perform)
        }
    }
    private var undoEntries: [Entry] = []
    private var redoEntries: [Entry] = []
    private var pending: (id: UUID, direction: Direction)?
    private var waiting: [(entry: Entry, appended: () -> Void)] = []
    private var epoch: UInt64 = 0
    package private(set) var revision: UInt64 = 0
    var changed: (() -> Void)?
    package var isBusy: Bool { pending != nil }
    @MainActor package final class Command: NSObject {
        fileprivate weak var manager: FolderUndoManager?
        fileprivate let entryID: UUID
        fileprivate let revision: UInt64
        let direction: Direction
        package let name: String
        fileprivate init(manager: FolderUndoManager, entry: Entry, direction: Direction) {
            self.manager = manager; entryID = entry.id; revision = manager.revision
            name = entry.name(direction); self.direction = direction
        }
    }
    package func command(_ direction: Direction) -> Command? {
        guard let entry = top(direction), entry.isAvailable(direction) else { return nil }
        return Command(manager: self, entry: entry, direction: direction)
    }
    package func canPerform(_ command: Command) -> Bool {
        command.manager === self && command.revision == revision && top(command.direction)?.id == command.entryID
            && top(command.direction)?.isAvailable(command.direction) == true
    }
    @discardableResult package func perform(_ command: Command) -> Bool {
        guard canPerform(command) else { return false }
        perform(command.direction); return true
    }
    private func notify() { revision &+= 1; changed?() }

    @discardableResult
    package func append(_ entry: Entry) -> Bool {
        guard pending == nil else { return false }
        undoEntries.append(entry); redoEntries.removeAll(); notify()
        return true
    }

    func appendWhenIdle(_ entry: Entry, appended: @escaping () -> Void) {
        guard pending != nil else {
            if append(entry) { appended() }
            return
        }
        waiting.append((entry, appended))
    }

    private func top(_ direction: Direction) -> Entry? {
        guard pending == nil else { return nil }
        switch direction {
        case .undo:
            while let entry = undoEntries.last, !entry.isValid(direction) { undoEntries.removeLast(); revision &+= 1 }
            return undoEntries.last
        case .redo:
            while let entry = redoEntries.last, !entry.isValid(direction) { redoEntries.removeLast(); revision &+= 1 }
            return redoEntries.last
        }
    }

    package override var canUndo: Bool { top(.undo)?.isAvailable(.undo) == true }
    package override var canRedo: Bool { top(.redo)?.isAvailable(.redo) == true }
    package override var undoActionName: String { top(.undo)?.name(.undo) ?? "" }
    package override var redoActionName: String { top(.redo)?.name(.redo) ?? "" }
    package override var undoMenuItemTitle: String { undoActionName.isEmpty ? "Undo" : "Undo \(undoActionName)" }
    package override var redoMenuItemTitle: String { redoActionName.isEmpty ? "Redo" : "Redo \(redoActionName)" }
    package override var isUndoing: Bool { pending?.direction == .undo }
    package override var isRedoing: Bool { pending?.direction == .redo }
    package override func undo() { perform(.undo) }
    package override func redo() { perform(.redo) }

    private func perform(_ direction: Direction) {
        guard let entry = top(direction), entry.isAvailable(direction) else { return }
        let request = UUID(), version = epoch
        pending = (request, direction); notify()
        entry.perform(direction) { [weak self, weak entry] committed in
            guard let self, let entry, self.epoch == version, self.pending?.id == request else { return }
            self.pending = nil
            let undone = committed && direction == .undo && self.undoEntries.last === entry
            var redone: Entry?
            if committed, direction == .redo, self.redoEntries.last === entry { self.redoEntries.removeLast(); redone = entry }
            let waiting = self.waiting
            self.waiting.removeAll()
            for item in waiting { self.undoEntries.append(item.entry); self.redoEntries.removeAll() }
            if undone, let index = self.undoEntries.lastIndex(where: { $0 === entry }) {
                self.undoEntries.remove(at: index); self.redoEntries.append(entry)
            }
            if let redone { self.undoEntries.append(redone) }
            self.notify()
            for item in waiting { item.appended() }
        }
    }

    package override func removeAllActions() {
        epoch &+= 1; pending = nil; waiting.removeAll(); undoEntries.removeAll(); redoEntries.removeAll()
        super.removeAllActions(); notify()
    }
}

@MainActor
package final class FolderUndoOperation {
    package var record: FolderDeletionUndo
    package init(_ record: FolderDeletionUndo) { self.record = record }
}
