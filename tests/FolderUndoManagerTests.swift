import AppKit

@main @MainActor
struct FolderUndoManagerTests {
    static func main() { exitOnFailure(runChecks) }
    static func runChecks() {
        var assertions = 0
        func expect(_ value: @autoclosure () -> Bool, _ message: String) {
            assertions += 1; precondition(value(), message)
        }
        let manager = FolderUndoManager()
        var valid = true, available = true, operations: [FolderUndoManager.Direction] = []
        var finish: ((Bool) -> Void)?
        let entry = FolderUndoManager.Entry(name: "Archive Tabs", isValid: { _ in valid },
            isAvailable: { _ in available }, perform: { direction, done in operations.append(direction); finish = done })
        expect(manager.append(entry) && manager.canUndo && !manager.canRedo, "Native Undo becomes available after committed close")
        expect(manager.undoMenuItemTitle == "Undo Archive Tabs", "Native menu receives recorded prompt")
        let command = manager.command(.undo)!
        available = false
        expect(!manager.canUndo && !manager.canPerform(command), "Transient owner refusal preserves group without authorizing command")
        available = true
        expect(manager.canPerform(command), "Same exact group is retryable after transient refusal")
        manager.undo()
        expect(manager.isUndoing && manager.isBusy && !manager.canUndo && !manager.canRedo, "Pending action blocks both native history directions")
        expect(!manager.append(entry) && operations == [.undo], "Busy history cannot accept an unrelated registration")
        manager.redo(); manager.undo()
        expect(operations == [.undo], "Repeated invocation while pending cannot run a second transaction")
        let firstCompletion = finish!
        firstCompletion(false)
        expect(manager.canUndo && !manager.canRedo && !manager.isBusy, "Failed Undo preserves stack position")
        manager.undo(); finish?(true)
        expect(!manager.canUndo && manager.canRedo && manager.redoMenuItemTitle == "Redo Archive Tabs", "Committed Undo alone advances native history")
        expect(!manager.canPerform(command), "Earlier Undo command cannot consume the now-redo group")
        manager.redo()
        expect(manager.isRedoing && manager.isBusy, "Redo awaits real consent")
        finish?(false)
        expect(manager.canRedo && !manager.canUndo, "Cancelled beforeunload retains Redo")
        manager.redo(); let redoCompletion = finish!; redoCompletion(true)
        expect(manager.canUndo && !manager.canRedo, "Committed Redo restores Undo capability")
        expect(!manager.canPerform(command), "A prior cycle's menu capability cannot authorize the same group after Redo")
        redoCompletion(true); firstCompletion(true)
        expect(manager.canUndo && !manager.canRedo, "Duplicate and stale completions cannot alter stack")
        let staleCommand = manager.command(.undo)!
        let newer = FolderUndoManager.Entry(name: "Archive Tab", isValid: { _ in true }, isAvailable: { _ in true }, perform: { _, done in done(true) })
        expect(manager.append(newer), "Next close records a distinct group")
        expect(!manager.canPerform(staleCommand), "Exact top groupID is required")
        manager.undo()
        expect(manager.canUndo && manager.canRedo, "LIFO Undo preserves earlier group and next Redo")
        expect(manager.append(newer) && !manager.canRedo, "New close discards old redo branch")
        manager.undo(); valid = false
        expect(!manager.canUndo && manager.canRedo, "Invalid underlying original is discarded without erasing valid opposite history")
        manager.redo(); manager.undo(); manager.removeAllActions()
        expect(!manager.canUndo && !manager.canRedo && manager.undoMenuItemTitle == "Undo", "Window closure drops cache and prompts")
        valid = true; _ = manager.append(entry); manager.undo(); let late = finish!
        manager.removeAllActions(); late(true)
        expect(!manager.canUndo && !manager.canRedo && !manager.isBusy, "Late close callback cannot resurrect a closed window's cache")
        var joined = 0
        manager.appendWhenIdle(newer) { joined += 1 }
        expect(joined == 1 && manager.canUndo, "An idle stack takes a close group at once")
        manager.removeAllActions(); _ = manager.append(entry); manager.undo()
        manager.appendWhenIdle(newer) { joined += 1 }
        expect(joined == 1 && manager.isBusy, "A close group waits while an Undo is pending")
        finish?(true)
        expect(joined == 2 && manager.undoMenuItemTitle == "Undo Archive Tab" && manager.redoMenuItemTitle == "Redo Archive Tabs",
               "It committed first, so it joins Undo and the Undo that finished after it keeps its Redo")
        manager.removeAllActions(); _ = manager.append(entry); manager.undo()
        manager.appendWhenIdle(newer) { joined += 1 }
        let closing = finish!
        manager.removeAllActions(); closing(true)
        expect(joined == 2 && !manager.canUndo, "Closing the window drops a waiting group")
        let editing = UndoManager()
        let target = NSObject()
        editing.registerUndo(withTarget: target) { _ in }
        expect(editing.canUndo && !manager.canUndo, "Native text editing uses an independent ordinary AppKit stack")
        print("FolderUndoManagerTests: \(assertions) assertions passed")
    }
}
