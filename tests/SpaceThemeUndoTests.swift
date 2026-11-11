import AppKit
import Combine

private final class ThemeGestureEvent: NSEvent {
    let eventPhase: NSEvent.Phase
    let eventMomentum: NSEvent.Phase
    let time: TimeInterval
    let location: NSPoint
    init(over view: NSView? = nil, phase: NSEvent.Phase = [], momentum: NSEvent.Phase = [],
         time: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        eventPhase = phase; eventMomentum = momentum; self.time = time
        location = view.map { $0.convert(NSPoint(x: $0.bounds.midX, y: $0.bounds.midY), to: nil) } ?? .zero
        super.init()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override var locationInWindow: NSPoint { location }
    override var phase: NSEvent.Phase { eventPhase }
    override var momentumPhase: NSEvent.Phase { eventMomentum }
    override var timestamp: TimeInterval { time }
    override var rotation: Float { 45 }
    override var scrollingDeltaY: CGFloat { 1 }
}

@main @MainActor struct SpaceThemeUndoTests {
    static var assertions = 0
    static func expect(_ condition: @autoclosure () throws -> Bool, _ message: String, line: Int = #line) throws {
        assertions += 1
        if try !condition() { throw NSError(domain: "Line \(line): \(message)", code: assertions) }
    }
    static func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
    static func control(_ label: String, in editor: SpaceThemeEditorView) -> NSView {
        descendants(editor).first { $0.accessibilityLabel() == label }!
    }
    static func click(_ label: String, in editor: SpaceThemeEditorView) {
        (control(label, in: editor) as! NSButton).performClick(nil)
    }
    static func event(_ type: NSEvent.EventType, x: CGFloat, y: CGFloat) -> NSEvent {
        NSEvent.mouseEvent(with: type, location: NSPoint(x: x, y: y), modifierFlags: [], timestamp: 0,
                          windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 0)!
    }
    @MainActor final class Owner {
        let store: BrowserStore
        let history = FolderUndoManager()
        let spaceID: UUID, profileID: UUID
        var available = true, errors = 0, commits = 0
        var editor: SpaceThemeEditorView?
        init(store: BrowserStore, spaceID: UUID) {
            self.store = store; self.spaceID = spaceID
            profileID = store.state.spaces.first { $0.id == spaceID }!.profileID
        }
        var saved: SpaceTheme { store.state.spaces.first { $0.id == spaceID }!.theme }
        func open() {
            let view = SpaceThemeEditorView(theme: saved, performHapticFeedback: {})
            editor = view; view.windowThemeUndo = history
            view.onCommitChange = { [weak self, weak view] previous, theme in
                guard let self, let view, self.editor === view, !self.history.isBusy else { return previous }
                do {
                    if let change = try self.store.saveSpaceTheme(spaceID: self.spaceID, profileID: self.profileID,
                                                                 previous: previous, theme: theme) {
                        self.commits += 1
                        self.history.appendSpaceThemeChange(change, store: self.store,
                            available: { [weak self] in self?.available == true },
                            onApplied: { [weak self] in self?.synchronize() },
                            onError: { [weak self] _ in self?.errors += 1 })
                    }
                } catch { self.errors += 1 }
                return self.saved
            }
            view.layoutSubtreeIfNeeded()
        }
        func synchronize() { editor?.synchronizeTheme(saved) }
        func close() { editor?.finishEditing(); editor = nil }
    }
    static func interruptedNoiseGestures() throws {
        var baseline = SpaceTheme.singleColor(ThemeColor(hex: "6688AA")!)
        baseline.noise = 0.2
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("parc-noise-undo-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try BrowserStore(directory: directory)
        let id = store.activeSpace.id
        store.setSpaceTheme(id, theme: baseline)
        let owner = Owner(store: store, spaceID: id)
        owner.open()
        let originalNoise = control("Theme texture and noise", in: owner.editor!)
        originalNoise.rotate(with: ThemeGestureEvent(over: originalNoise, phase: .began))
        owner.editor!.undo(nil)
        try expect(owner.saved == baseline && owner.history.canRedo, "Actual Undo commits and restores an active rotation")
        originalNoise.rotate(with: ThemeGestureEvent(over: originalNoise, phase: .changed))
        originalNoise.rotate(with: ThemeGestureEvent(over: originalNoise, phase: .ended))
        owner.editor!.finishEditing()
        try expect(owner.saved == baseline && owner.history.canRedo && owner.commits == 1,
                   "Inherited rotation cannot overwrite the restored theme or clear actual Redo")
        owner.close()
        let view = SpaceThemeEditorView(theme: baseline, performHapticFeedback: {})
        view.layoutSubtreeIfNeeded()
        let noise = control("Theme texture and noise", in: view)
        var commits = 0
        view.onCommit = { _ in commits += 1 }
        noise.rotate(with: ThemeGestureEvent(over: noise, phase: .began))
        var restored = baseline; restored.noise = 0.4
        view.synchronizeTheme(restored)
        noise.rotate(with: ThemeGestureEvent(over: noise, phase: .changed))
        noise.rotate(with: ThemeGestureEvent(over: noise, phase: .ended))
        view.finishEditing()
        try expect(view.theme == restored && commits == 0, "Parent replacement rejects remaining rotation phases")
        noise.rotate(with: ThemeGestureEvent(over: noise, phase: .began))
        noise.rotate(with: ThemeGestureEvent(over: noise, phase: .ended))
        try expect(view.theme != restored && commits == 1, "A fresh rotation works after the cancelled sequence ends")
        let center = noise.convert(NSPoint(x: noise.bounds.midX, y: noise.bounds.midY), to: nil)
        noise.mouseMoved(with: event(.mouseMoved, x: center.x, y: center.y))
        noise.scrollWheel(with: ThemeGestureEvent(phase: .began))
        view.synchronizeTheme(baseline)
        noise.scrollWheel(with: ThemeGestureEvent(phase: .changed))
        noise.scrollWheel(with: ThemeGestureEvent(phase: .ended))
        noise.scrollWheel(with: ThemeGestureEvent(momentum: .began))
        noise.scrollWheel(with: ThemeGestureEvent(momentum: .changed, time: ProcessInfo.processInfo.systemUptime + 1))
        noise.scrollWheel(with: ThemeGestureEvent(momentum: .ended))
        view.finishEditing()
        try expect(view.theme == baseline && commits == 1, "Cancelled phased scroll rejects physical end and delayed momentum")
        noise.scrollWheel(with: ThemeGestureEvent(phase: .began))
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.035))
        view.finishEditing()
        try expect(view.theme != baseline && commits == 2, "A fresh physical scroll releases the cancellation barrier")
        view.synchronizeTheme(restored)
        let start = ProcessInfo.processInfo.systemUptime + 1
        noise.scrollWheel(with: ThemeGestureEvent(time: start))
        view.synchronizeTheme(baseline)
        noise.scrollWheel(with: ThemeGestureEvent(time: ProcessInfo.processInfo.systemUptime))
        noise.scrollWheel(with: ThemeGestureEvent(time: ProcessInfo.processInfo.systemUptime + 0.1))
        view.finishEditing()
        try expect(view.theme == baseline && commits == 2, "Cancelled unphased wheel burst cannot restart immediately")
        noise.scrollWheel(with: ThemeGestureEvent(time: ProcessInfo.processInfo.systemUptime + 1))
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.035))
        view.finishEditing()
        try expect(view.theme != baseline && commits == 3, "An unphased wheel burst after idle starts a new edit")
    }
    static func main() throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("parc-theme-undo-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try BrowserStore(directory: directory)
        let space = store.activeSpace.id
        var initial = SpaceTheme.singleColor(ThemeColor(hex: "4C6688")!)
        initial.noise = 0.35; initial.texture = .tweed; initial.intensity = 0.3
        store.setSpaceTheme(space, theme: initial)
        let owner = Owner(store: store, spaceID: space), other = Owner(store: store, spaceID: space)
        var publications = 0
        let subscription = store.statePublisher.dropFirst().sink { _ in publications += 1 }
        weak var retired: SpaceThemeEditorView?
        var second = initial
        try autoreleasepool {
            owner.open()
            try expect(owner.editor!.undoManager === owner.history, "Popover responder exposes its original window history")
            click("Add color", in: owner.editor!)
            second = owner.saved
            try expect(second.colorCount == 2 && owner.commits == 1 && publications == 1, "Discrete edit commits once")
            try expect(owner.history.undoMenuItemTitle == "Undo Update Theme" && !other.history.canUndo, "Reference label and original window ownership")
            retired = owner.editor
            owner.close()
        }
        try expect(retired == nil, "Undo records do not retain a closed editor")
        owner.history.undo()
        try expect(owner.saved == initial && owner.history.canRedo, "Undo survives popover destruction")
        try expect(try BrowserStore(directory: directory).state.spaces.first { $0.id == space }!.theme == initial, "Inverse is durably saved")
        owner.open(); owner.editor!.redo(nil)
        try expect(owner.saved == second && owner.editor!.theme == second, "A reopened editor routes Redo to original window history and refreshes")
        owner.editor!.undo(nil)
        try expect(owner.saved == initial && owner.editor!.theme == initial, "Open editor receives the inverse without registering an extra transaction")
        try expect(owner.commits == 1 && !owner.history.canUndo && owner.history.canRedo, "One complete change remains one history step")
        let unchanged = try store.saveSpaceTheme(spaceID: space, profileID: owner.profileID, previous: initial, theme: initial)
        try expect(unchanged == nil && owner.history.canRedo, "A no-op preserves the Redo branch")
        owner.editor!.redo(nil)
        click("Add color", in: owner.editor!)
        let third = owner.saved
        try expect(third.colorCount == 3 && owner.commits == 2, "New popover edit shares the original history")
        owner.close(); owner.history.undo(); owner.history.undo()
        try expect(owner.saved == initial, "Consecutive popovers undo in order")
        owner.history.redo(); owner.history.redo()
        try expect(owner.saved == third, "Consecutive popovers redo in order")
        store.renameSpace(space, name: "New name")
        let destination = store.createSpace(name: "Unrelated Space"), before = store.state
        owner.history.undo()
        var expected = before
        expected.spaces[expected.spaces.firstIndex { $0.id == space }!].theme = second
        try expect(store.state == expected && store.activeSpace.id == destination, "Inverse follows original Space without changing current selection, names or siblings")
        owner.available = false
        try expect(!owner.history.canRedo, "Temporary original-window unavailability blocks inverse")
        owner.available = true
        try expect(owner.history.canRedo, "Temporary unavailability retains inverse")
        owner.history.redo(); owner.open()
        let intensity = control("Theme intensity", in: owner.editor!)
        let revision = owner.history.revision
        intensity.mouseDown(with: event(.leftMouseDown, x: 60, y: 20))
        intensity.mouseDragged(with: event(.leftMouseDragged, x: 120, y: 20))
        intensity.mouseDragged(with: event(.leftMouseDragged, x: 150, y: 20))
        try expect(owner.history.revision == revision && owner.saved == third, "Gesture preview does not commit intermediate values")
        let gestureTheme = owner.editor!.theme
        owner.close()
        try expect(owner.saved == gestureTheme && owner.commits == 3, "Closing commits the complete pending gesture once")
        owner.history.undo()
        try expect(owner.saved == third, "One inverse restores the complete pregesture theme")
        owner.open()
        _ = intensity.accessibilityPerformIncrement()
        owner.editor!.finishEditing()
        try expect(owner.commits == 3 && owner.saved == third, "Retained old control cannot edit the replacement popover")
        owner.editor!.redo(nil)
        owner.editor!.undo(nil)
        _ = control("Theme intensity", in: owner.editor!).accessibilityPerformDecrement()
        try expect(!owner.history.canRedo && owner.commits == 4, "A new edit after Undo replaces the original Redo branch")
        let branched = owner.saved
        other.open(); click("Remove color", in: other.editor!)
        let competing = other.saved
        try expect(competing != branched && !owner.history.canUndo, "Competing window change invalidates stale window inverse")
        click("Remove color", in: owner.editor!)
        try expect(owner.saved == competing && owner.editor!.theme == competing, "Stale editor commit cannot overwrite newer shared theme")
        try expect(owner.errors == 1, "Stale compare-and-swap is rejected")
        owner.history.removeAllActions(); other.history.removeAllActions()
        owner.open()
        let pad = control("Theme color pad", in: owner.editor!)
        pad.mouseDown(with: event(.leftMouseDown, x: 140, y: 160))
        let external = SpaceTheme.singleColor(ThemeColor(hex: "DDAACC")!)
        _ = try store.saveSpaceTheme(spaceID: space, profileID: owner.profileID, previous: competing, theme: external)
        owner.synchronize()
        pad.mouseDragged(with: event(.leftMouseDragged, x: 240, y: 210)); pad.mouseUp(with: event(.leftMouseUp, x: 240, y: 210))
        try expect(owner.saved == external && owner.editor!.theme == external && !owner.history.canUndo, "External parent replacement retires an old in-flight gesture")
        click("Add color", in: owner.editor!)
        let beforeFailure = store.state, committed = owner.commits
        try FileManager.default.removeItem(at: directory); try Data().write(to: directory)
        owner.history.undo()
        try expect(store.state == beforeFailure && owner.history.canUndo && !owner.history.canRedo, "Failed inverse preserves actual model and retryable history")
        click("Add color", in: owner.editor!)
        try expect(store.state == beforeFailure && owner.editor!.theme == owner.saved && owner.commits == committed, "Failed editor commit restores authoritative theme and registers nothing")
        try FileManager.default.removeItem(at: directory); try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        owner.history.undo()
        try expect(owner.saved == external && owner.history.canRedo, "Failed inverse can be retried successfully")
        owner.history.redo()
        let change = SpaceThemeChange(spaceID: space, profileID: owner.profileID, previousTheme: external, theme: owner.saved)
        var reassigned = store.state
        reassigned.spaces[reassigned.spaces.firstIndex { $0.id == space }!].profileID = UUID()
        try expect(change.target(in: reassigned, undo: true) == nil, "Original profile reassignment rejects inverse")
        var removed = store.state; removed.spaces.removeAll { $0.id == space }
        try expect(change.target(in: removed, undo: true) == nil, "Deleted original Space is not recreated by Undo")
        let newProfile = store.createProfile(name: "Different profile")
        store.assignProfile(newProfile, toSpace: space)
        try expect(!owner.history.canUndo, "Actual profile reassignment invalidates retained history")
        let local = SpaceThemeEditorView(theme: initial, performHapticFeedback: {})
        var draftCommits = 0
        local.onCommit = { _ in draftCommits += 1 }
        click("Add color", in: local); local.undo(nil); local.redo(nil)
        try expect(local.theme.colorCount == 2 && draftCommits == 3, "Setup and uncommitted Space drafts retain local history")
        try interruptedNoiseGestures()
        _ = subscription
        print("Space theme Undo: \(assertions) assertions passed")
    }
}
