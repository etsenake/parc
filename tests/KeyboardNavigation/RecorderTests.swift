import AppKit
import QuartzCore

@MainActor private final class RecorderPresentationWindow: NSWindow {
    override var isKeyWindow: Bool { true }
    override var isVisible: Bool { true }
}

@MainActor private final class ConflictDispatchTarget: NSObject, NSMenuItemValidation {
    var delivered = 0
    func validateMenuItem(_ item: NSMenuItem) -> Bool { true }
    @objc func alpha(_ sender: Any?) { delivered += 1 }
    @objc func beta(_ sender: Any?) { delivered += 1 }
    @objc func gamma(_ sender: Any?) { delivered += 1 }
}

@main struct RecorderTests {
    @MainActor static func main() { exitOnFailure(runChecks) }
    @MainActor static func runChecks() throws {
        _ = NSApplication.shared
        var checks = 0
        func expect(_ value: @autoclosure () -> Bool, _ message: String) { checks += 1; precondition(value(), message) }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("keyboard-shortcuts.json")
        let registry = KeyboardShortcuts(); registry.configure(directory: directory)
        var items: [NSMenuItem] = []
        func register(_ id: String, _ key: String, _ flags: NSEvent.ModifierFlags = [.command, .option]) {
            let item = NSMenuItem(title: id, action: NSSelectorFromString(id), keyEquivalent: key)
            item.keyEquivalentModifierMask = flags; items.append(item); registry.register(item, group: "Test")
        }
        register("alpha:", "a"); register("beta:", "b"); register("gamma:", "b"); register("copy:", "c", [.command])
        let a = registry.shortcut(for: "alpha:")!, b = registry.shortcut(for: "beta:")!
        try registry.setPriority(.useBoth, for: "alpha:"); try registry.setPriority(.preferParc, for: "beta:")
        let saved = try Data(contentsOf: file), revision = registry.revision
        let proposal = try registry.conflictProposal(for: b, commandID: "alpha:")!
        expect(proposal.conflicts.map(\.id) == ["beta:", "gamma:"], "Proposal identifies every effective owner")
        let unchanged = try Data(contentsOf: file)
        expect(unchanged == saved && registry.revision == revision, "Proposal makes no durable or active change")
        expect(items[0].keyEquivalent == "a" && items[1].keyEquivalent.isEmpty && items[2].keyEquivalent.isEmpty, "Existing duplicate defaults disable only the conflicting menus")
        try registry.resolveConflict(proposal)
        expect(registry.shortcut(for: "alpha:") == b, "Explicit resolution assigns target")
        expect(registry.shortcut(for: "beta:") == nil && registry.shortcut(for: "gamma:") == nil, "Every conflicting assignment is explicitly disabled")
        expect(items[0].keyEquivalent == "b" && items[1].keyEquivalent.isEmpty && items[2].keyEquivalent.isEmpty, "Actual menus update together")
        expect(registry.revision == revision + 1, "One resolution publishes one new revision")
        expect(registry.priority(for: "alpha:") == .useBoth && registry.priority(for: "beta:") == .preferParc, "Resolution preserves unrelated priorities")
        registry.configure(directory: directory)
        expect(registry.shortcut(for: "alpha:") == b && registry.shortcut(for: "beta:") == nil, "Resolved binding and disabled owner survive reload")
        do { try registry.resolveConflict(proposal); preconditionFailure("Stale revision accepted") } catch { checks += 1 }
        let reserved = KeyboardShortcut(key: "c", flags: [.command])
        do { _ = try registry.conflictProposal(for: reserved, commandID: "alpha:"); preconditionFailure("Protected editing shortcut accepted") } catch { checks += 1 }
        do { _ = try registry.conflictProposal(for: a, commandID: "copy:"); preconditionFailure("Editing target accepted") } catch { checks += 1 }
        let uncontested = try registry.conflictProposal(for: a, commandID: "alpha:")
        expect(uncontested == nil, "Uncontested chord does not need resolution")
        try registry.set(a, for: "beta:")
        let reset = try registry.conflictProposal(for: a, commandID: "alpha:", resetsPriority: true)!
        try registry.resolveConflict(reset)
        expect(registry.shortcut(for: "alpha:") == a && !registry.isCustomized("alpha:"), "Reset resolution restores default binding and priority")
        expect(registry.priority(for: "beta:") == .preferParc, "Reset resolution retains the displaced owner's priority")
        let blocked = try registry.conflictProposal(for: a, commandID: "gamma:")!
        let beforeFailure = registry.revision
        try FileManager.default.removeItem(at: file)
        try FileManager.default.createDirectory(at: file, withIntermediateDirectories: false)
        do { try registry.resolveConflict(blocked); preconditionFailure("Directory write unexpectedly succeeded") } catch { checks += 1 }
        expect(registry.revision == beforeFailure && registry.shortcut(for: "alpha:") == a && registry.shortcut(for: "gamma:") == nil, "Failed write preserves every active binding and revision")
        expect(items[0].keyEquivalent == "a" && items[2].keyEquivalent.isEmpty, "Failed write preserves actual menu bindings")
        try FileManager.default.removeItem(at: file)
        try registry.resolveConflict(blocked)
        expect(registry.shortcut(for: "gamma:") == a, "Same proposal can retry after a storage failure without revision drift")
        try registry.resetAll()
        expect(registry.shortcut(for: "alpha:") == a && registry.shortcut(for: "beta:") == b && !registry.hasOverrides, "Reset All restores shipped bindings and clears all overrides")

        let target = ConflictDispatchTarget(), menu = NSMenu()
        NSApp.mainMenu = menu
        for item in items { item.target = target; menu.addItem(item) }
        try registry.set(nil, for: "gamma:")
        let key = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.command, .option], timestamp: 0,
            windowNumber: 0, context: nil, characters: "b", charactersIgnoringModifiers: "b", isARepeat: false, keyCode: 11)!
        let prior = registry.nativeCommand(for: key, editable: false)!
        expect(prior.item === items[1], "Uncontested binding reaches its actual native menu target")
        try registry.set(b, for: "alpha:")
        expect(registry.isConflicting("alpha:") && registry.isConflicting("beta:"), "Both saved assignments carry conflict state")
        expect(items[0].keyEquivalent.isEmpty && items[1].keyEquivalent.isEmpty,
               "Actual conflicting menu equivalents are both cleared")
        expect(registry.nativeCommand(for: key, editable: false) == nil && !registry.perform(prior, event: key, editable: false),
               "Native query and retained prior command cannot bypass the saved conflict")
        expect(!menu.performKeyEquivalent(with: key) && target.delivered == 0, "AppKit fallback cannot dispatch an arbitrary conflicting action")
        let queryWindow = NSWindow(contentRect: .zero, styleMask: [], backing: .buffered, defer: false)
        let commands = registry.menuCommands(in: queryWindow)
        expect(commands.filter { ["alpha:", "beta:"].contains($0.id) }.count == 2 &&
               commands.filter { ["alpha:", "beta:"].contains($0.id) }.allSatisfy { $0.shortcut == nil },
               "Commands remain discoverable without advertising an inactive key equivalent")
        queryWindow.close()
        let conflictData = try Data(contentsOf: file)
        registry.configure(directory: directory)
        expect((try? Data(contentsOf: file)) == conflictData && registry.isConflicting("alpha:") && registry.isConflicting("beta:"),
               "Conflict persists across configure without rewriting or discarding either saved choice")
        try registry.set(b, for: "gamma:")
        expect(registry.conflictingCommands(for: "alpha:").map(\.id) == ["beta:", "gamma:"], "Three owners expose the exact two other assignments")
        let beforeClearFailure = registry.revision
        try FileManager.default.removeItem(at: file)
        try FileManager.default.createDirectory(at: file, withIntermediateDirectories: false)
        do { try registry.set(nil, for: "alpha:"); preconditionFailure("Failed write was accepted") } catch { checks += 1 }
        expect(registry.revision == beforeClearFailure && registry.isConflicting("alpha:") && registry.nativeCommand(for: key, editable: false) == nil,
               "Failed durable clear cannot publish partial conflict resolution or enable a chord")
        try FileManager.default.removeItem(at: file)
        try registry.set(nil, for: "alpha:")
        expect(registry.isConflicting("beta:") && registry.isConflicting("gamma:"), "Clearing one of three owners keeps remaining ambiguity inert")
        try registry.set(nil, for: "gamma:")
        expect(!registry.isConflicting("beta:") && registry.nativeCommand(for: key, editable: false)?.item === items[1] && items[1].keyEquivalent == "b",
               "Clearing the final conflict restores the surviving original native menu owner")
        var stored = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as! [String: Any]
        var assignments = stored["overrides"] as! [String: Any]
        assignments["alpha:"] = ["shortcut": ["key": "c", "modifiers": NSEvent.ModifierFlags.command.rawValue]]
        stored["overrides"] = assignments
        try JSONSerialization.data(withJSONObject: stored).write(to: file)
        registry.configure(directory: directory)
        expect(registry.activeShortcut(for: "alpha:") == nil && registry.shortcut(for: "alpha:") == reserved,
               "Legacy collision remains saved but cannot override native editing")
        expect(registry.activeShortcut(for: "copy:") == reserved && items[3].keyEquivalent == "c",
               "Native Copy keeps its original menu binding despite a legacy conflicting override")
        try registry.resetAll()

        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 260, height: 100), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let recorder = ShortcutRecorderView(frame: NSRect(x: 0, y: 0, width: 80, height: 26))
        let next = NSButton(title: "Next", target: nil, action: nil)
        window.contentView?.addSubview(recorder); window.contentView?.addSubview(next)
        recorder.nextKeyView = next; next.nextKeyView = recorder
        var begins = 0, ends = 0, changes = 0, previews: [[String]] = [], accepted = true
        recorder.shortcut = a
        recorder.onBegin = { begins += 1 }; recorder.onEnd = { ends += 1 }
        recorder.onPreview = { previews.append($0) }
        recorder.onChange = { _ in changes += 1; return accepted }
        func event(_ key: UInt16, _ flags: NSEvent.ModifierFlags = [], type: NSEvent.EventType = .keyDown, repeatKey: Bool = false) -> NSEvent {
            NSEvent.keyEvent(with: type, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: window.windowNumber,
                            context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: repeatKey, keyCode: key)!
        }
        func begin() { expect(window.makeFirstResponder(recorder) && recorder.isRecording, "Recorder becomes first responder") }
        begin(); recorder.flagsChanged(with: event(55, [.command, .shift], type: .flagsChanged))
        expect(previews.last == ["⇧", "⌘"] && changes == 0 && recorder.shortcut == a, "Held modifiers preview without committing")
        recorder.keyDown(with: event(53))
        expect(!recorder.isRecording && ends == 1 && changes == 0 && recorder.shortcut == a, "Escape cancels without changing binding")
        begin(); recorder.keyDown(with: event(0, [.command, .option], repeatKey: true))
        expect(recorder.isRecording && changes == 0, "Held key repeat cannot commit")
        recorder.keyDown(with: event(51))
        expect(!recorder.isRecording && changes == 1 && recorder.shortcut == nil, "Delete clears once and relinquishes focus")
        recorder.shortcut = a; accepted = false
        begin(); recorder.keyDown(with: event(0, [.command, .option]))
        expect(!recorder.isRecording && recorder.shortcut == a && changes == 2, "Owner rejection keeps binding and ends capture")
        accepted = true
        begin(); recorder.keyDown(with: event(0))
        expect(!recorder.isRecording && changes == 2, "Unsupported printable key ends capture without commit")
        begin(); recorder.keyDown(with: event(0, [.command, .option]))
        expect(!recorder.isRecording && changes == 3, "Valid completed chord commits exactly once")
        begin(); window.makeFirstResponder(next)
        expect(!recorder.isRecording, "Focus transfer removes capture")
        begin(); NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: window)
        expect(!recorder.isRecording, "Window deactivation removes capture")
        begin(); recorder.isEnabled = false
        expect(!recorder.isRecording && !recorder.acceptsFirstResponder && !recorder.accessibilityPerformPress(), "Disabled recorder cancels and rejects focus and accessibility press")
        recorder.isEnabled = true; begin(); recorder.removeFromSuperview()
        expect(!recorder.isRecording && begins == ends, "Removal ends each capture exactly once")
        let settings = ShortcutsSettingsView(shortcuts: registry)
        window.contentView = settings
        func descendant<T: NSView>(_ type: T.Type, in parent: NSView) -> T? {
            if let value = parent as? T { return value }
            return parent.subviews.lazy.compactMap { descendant(type, in: $0) }.first
        }
        let table = descendant(NSTableView.self, in: settings)!
        let cell = table.view(atColumn: 0, row: 1, makeIfNecessary: true)!
        let input = descendant(ShortcutRecorderView.self, in: cell)!
        table.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)
        input.onBegin?()
        let detailCaps = descendant(ShortcutKeycapView.self, in: settings)!
        let originalSymbols = detailCaps.symbols
        let originalFrame = detailCaps.frame
        expect(window.makeFirstResponder(input) && input.isRecording, "Settings recorder takes actual first responder without replacing its row")
        input.flagsChanged(with: event(55, [.control, .option, .shift, .command], type: .flagsChanged))
        expect(detailCaps.symbols == ["⌃", "⌥", "⇧", "⌘"], "Focused detail shows the actual held-modifier sequence")
        expect(detailCaps.frame == originalFrame && detailCaps.frame.width == 200, "Long modifier preview preserves the original detail container")
        expect(window.firstResponder === input && !detailCaps.acceptsFirstResponder, "Passive detail update preserves native recorder focus")
        input.flagsChanged(with: event(55, [.command], type: .flagsChanged))
        expect(detailCaps.symbols == ["⌘"] && detailCaps.frame == originalFrame, "Short modifier preview keeps the same column and original action")
        input.keyDown(with: event(53))
        expect(!input.isRecording && detailCaps.symbols == originalSymbols && detailCaps.frame == originalFrame, "Cancel restores the actual saved chord in the same detail region")
        expect(registry.shortcut(for: "alpha:") == a, "Focus and modifier-only detail updates never write a binding")
        let settingsRevision = registry.revision
        expect(input.onChange?(b) == true && input.isConflicting, "Editor displays the actual saved conflict")
        expect(registry.revision == settingsRevision + 1 && registry.shortcut(for: "alpha:") == b && registry.activeShortcut(for: "alpha:") == nil, "Saved conflict advances revision and disables ambiguous dispatch")
        settings.endRecording()
        expect(input.isConflicting && input.shortcut == b && registry.revision == settingsRevision + 1, "Pane departure preserves the saved binding and conflict")
        let presentationWindow = RecorderPresentationWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 100),
            styleMask: [.titled], backing: .buffered, defer: false)
        presentationWindow.isReleasedWhenClosed = false
        let field = ShortcutRecorderView(frame: NSRect(x: 20, y: 20, width: 66, height: 24))
        presentationWindow.contentView?.addSubview(field)
        field.shortcut = KeyboardShortcut(key: "=", flags: [.control, .shift])
        field.appearance = NSAppearance(named: .aqua)
        let oldAppearance = NSApp.appearance
        NSApp.appearance = NSAppearance(named: .aqua)
        defer { NSApp.appearance = oldAppearance }
        field.refreshPresentation(reduceMotion: false)
        let border = field.layer!.sublayers![0], halo = field.layer!.sublayers![1]
        let label = field.subviews.compactMap { $0 as? NSTextField }.first!
        func equalColor(_ color: CGColor?, _ expected: NSColor) -> Bool {
            guard let color, let value = NSColor(cgColor: color)?.usingColorSpace(.sRGB),
                  let expected = NSColor(cgColor: expected.cgColor(in: field.effectiveAppearance))?.usingColorSpace(.sRGB) else { return false }
            return abs(value.redComponent - expected.redComponent) < 0.002 && abs(value.greenComponent - expected.greenComponent) < 0.002 &&
                abs(value.blueComponent - expected.blueComponent) < 0.002 && abs(value.alphaComponent - expected.alphaComponent) < 0.002
        }
        expect(border.frame == field.bounds && border.cornerRadius == 6 && border.cornerCurve == .continuous && border.borderWidth == 1, "Original layer geometry is independent of native input")
        expect(equalColor(border.backgroundColor, .white) && equalColor(border.borderColor, NSColor(srgbRed: 0.93, green: 0.93, blue: 0.93, alpha: 1)), "Unfocused light field uses actual named Gray4 and white")
        expect(label.font?.pointSize == 12 && label.alignment == .center && !label.isSelectable && !label.isEditable && !label.isAccessibilityElement() && label.isAccessibilityHidden() && field.accessibilityChildren()?.isEmpty == true, "Native label is centered passive content, not a second text editor or AX target")
        expect(halo.borderWidth == 0 && halo.animationKeys() == nil, "Unfocused field does not keep invisible pulse work")
        for flags: NSEvent.ModifierFlags in [[.control, .command], [.control, .option, .shift, .command]] {
            field.shortcut = KeyboardShortcut(key: " ", flags: flags)
            field.refreshPresentation(reduceMotion: false)
            expect(label.stringValue == field.shortcut?.display && label.cell!.cellSize.width <= label.frame.width,
                   "Complete Space chord fits its actual native cell, including text insets: \(label.stringValue), cell \(label.cell!.cellSize.width), frame \(label.frame.width), font \(label.font!.pointSize)")
            expect(label.font!.pointSize >= 8 && label.font!.pointSize <= 12 && field.frame.width == 66,
                   "Native fitting preserves the original recorder bounds and font range")
            expect(field.accessibilityValue() as? String == field.shortcut?.spokenDisplay
                   && (field.accessibilityValue() as? String)?.hasSuffix("Space") == true, "The recorder speaks Space, not the ⎵ symbol name")
        }
        field.shortcut = KeyboardShortcut(key: "=", flags: [.control, .shift])
        field.refreshPresentation(reduceMotion: false)
        expect(label.font?.pointSize == 12, "A short chord restores the original twelve-point label")
        field.mouseEntered(with: event(0)); field.refreshPresentation(reduceMotion: false)
        expect(equalColor(border.borderColor, NSColor.controlAccentColor.withAlphaComponent(0.4)), "Hover exposes only the recovered translucent accent border")
        field.mouseExited(with: event(0)); field.rowSelected = true; field.refreshPresentation(reduceMotion: false)
        expect(equalColor(border.borderColor, NSColor(srgbRed: 0.93, green: 0.93, blue: 0.93, alpha: 1)), "Selection alone does not impersonate recorder focus")
        expect(presentationWindow.makeFirstResponder(field), "Actual original responder enters presentation")
        field.refreshPresentation(reduceMotion: false)
        expect(equalColor(border.borderColor, .controlAccentColor) && equalColor(label.textColor?.cgColor(in: field.effectiveAppearance), .controlAccentColor), "Focused field and text use actual accent")
        expect(halo.borderWidth == 1 && Set(halo.animationKeys() ?? []) == Set(["transform.scale.x", "transform.scale.y", "opacity", "cornerRadius"]), "Focus owns exactly four genuine layer animations")
        let pulse = halo.animation(forKey: "transform.scale.x") as! CABasicAnimation
        let opacity = halo.animation(forKey: "opacity") as! CABasicAnimation
        expect(pulse.duration == 1.5 && pulse.repeatDuration.isInfinite && pulse.fromValue as? Double == 1 && pulse.toValue as? Double == 1.175, "Recovered pulse duration and horizontal extent")
        expect(opacity.fromValue as? Double == 1 && opacity.toValue as? Double == 0 && opacity.beginTime == pulse.beginTime, "Halo fades with the same delayed origin")
        let initialTime = pulse.beginTime
        field.refreshPresentation(reduceMotion: false)
        expect(halo.animation(forKey: "opacity")?.beginTime == initialTime, "Unchanged preview/layout preserves the active pulse phase")
        field.isConflicting = true; field.refreshPresentation(reduceMotion: false)
        expect(equalColor(border.borderColor, .systemRed) && equalColor(halo.borderColor, .systemRed), "Focused conflict uses its original red layer tint")
        field.refreshPresentation(reduceMotion: true)
        expect(halo.animationKeys() == nil && border.borderWidth == 1, "Reduce Motion removes the halo while preserving focus information")
        field.refreshPresentation(reduceMotion: false)
        field.setFrameSize(NSSize(width: 80, height: 24)); field.refreshPresentation(reduceMotion: false)
        expect(border.frame.width == 80 && halo.frame.width == 80, "Resizing updates both actual layers")
        field.cancelRecording(); field.refreshPresentation(reduceMotion: false)
        expect(halo.animationKeys() == nil && !field.isRecording, "Cancel retires the original layer pulse and monitor")
        NSApp.appearance = NSAppearance(named: .darkAqua)
        field.appearance = NSAppearance(named: .darkAqua); field.refreshPresentation(reduceMotion: false)
        expect(equalColor(border.backgroundColor, NSColor.white.withAlphaComponent(0.1)) && equalColor(border.borderColor, NSColor.white.withAlphaComponent(0.1)), "Explicit dark application selected field uses white ten-percent layers")
        field.rowSelected = false; field.refreshPresentation(reduceMotion: false)
        expect(equalColor(border.borderColor, NSColor(srgbRed: 0.243, green: 0.243, blue: 0.243, alpha: 1)), "Explicit dark unselected field uses actual Gray7")
        expect(presentationWindow.makeFirstResponder(field), "Second original focus can start")
        field.refreshPresentation(reduceMotion: false); field.isHidden = true
        expect(!field.isRecording && halo.animationKeys() == nil, "Hiding cancels input and motion together")
        field.isHidden = false; expect(presentationWindow.makeFirstResponder(field), "Visible original field accepts focus again")
        field.refreshPresentation(reduceMotion: false); field.removeFromSuperview()
        expect(!field.isRecording && halo.animationKeys() == nil, "Detaching retires pulse and exact input owner")
        presentationWindow.close()
        window.close()
        print("PASS: \(checks) shortcut conflict and recorder assertions")
    }
}
