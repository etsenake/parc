import AppKit

@MainActor private final class ReturnEditor: NSTextView {
    var commands: [Selector] = []
    override func doCommand(by selector: Selector) { commands.append(selector) }
    override func insertText(_ insertString: Any, replacementRange: NSRange) {}
}

@MainActor private final class ReturnFieldDelegate: NSObject, NSTextFieldDelegate {
    var event: NSEvent?
    var commands: [String] = []
    var submissions: [CommandBarSubmission] = []
    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        commands.append(NSStringFromSelector(selector))
        guard let submission = CommandBarSubmission.resolveTextCommand(selector, event: event,
            hasMarkedText: textView.hasMarkedText()) else { return false }
        submissions.append(submission); return true
    }
}

@main @MainActor
struct ReturnModifierTests {
    static var assertions = 0
    static func expect(_ value: @autoclosure () -> Bool, _ message: String) {
        assertions += 1; precondition(value(), message)
    }
    static func main() { exitOnFailure(runChecks) }
    static func runChecks() {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 180, height: 80),
                              styleMask: [], backing: .buffered, defer: false)
        let editor = ReturnEditor(frame: window.contentView!.bounds); window.contentView = editor
        func event(_ key: UInt16, _ flags: NSEvent.ModifierFlags, type: NSEvent.EventType = .keyDown) -> NSEvent {
            let chars = key == 76 ? "\u{3}" : "\r"
            return NSEvent.keyEvent(with: type, location: .zero, modifierFlags: flags, timestamp: 0,
                windowNumber: window.windowNumber, context: nil, characters: chars,
                charactersIgnoringModifiers: chars, isARepeat: false, keyCode: key)!
        }
        for key: UInt16 in [36, 76] {
            for (flags, selector, expected): (NSEvent.ModifierFlags, String, CommandBarSubmission?) in [
                ([], "insertNewline:", .ordinary), (.option, "insertNewlineIgnoringFieldEditor:", .split),
                (.command, "noop:", .background), (.shift, "insertNewline:", nil),
                (.control, "insertLineBreak:", nil), ([.command, .shift], "noop:", nil)
            ] {
                let input = event(key, flags)
                editor.commands = []; editor.interpretKeyEvents([input])
                expect(editor.commands.map(NSStringFromSelector) == [selector], "Actual AppKit selector for key \(key) / \(flags.rawValue)")
                expect(CommandBarSubmission.resolveTextCommand(editor.commands[0], event: input, hasMarkedText: false) == expected,
                       "Actual selector routes only the recovered Return operation")
                expect(CommandBarSubmission.resolveTextCommand(editor.commands[0], event: input, hasMarkedText: true) == nil,
                       "Marked text retains its native input-method owner")
            }
            let command = event(key, [.command, .capsLock, .numericPad, .function])
            expect(CommandBarSubmission.resolveTextCommand(NSSelectorFromString("noop:"), event: command, hasMarkedText: false) == .background,
                   "Return and keypad Enter keep their action with device flags")
        }
        let noop = NSSelectorFromString("noop:")
        expect(CommandBarSubmission.resolveTextCommand(noop, event: nil, hasMarkedText: false) == nil,
               "Unattributed noop never submits a result")
        expect(CommandBarSubmission.resolveTextCommand(noop, event: event(36, .command, type: .keyUp), hasMarkedText: false) == nil,
               "Key release cannot duplicate an operation")
        expect(CommandBarSubmission.resolveTextCommand(noop, event: event(40, .command), hasMarkedText: false) == nil,
               "An unrelated Command key is not Return")
        expect(CommandBarSubmission.resolveTextCommand(NSSelectorFromString("moveLeft:"), event: event(36, .command), hasMarkedText: false) == nil,
               "A native editing command cannot be reinterpreted from modifiers")
        let semantic: [NSEvent.ModifierFlags] = [.command, .option, .control, .shift]
        for mask in 0..<16 {
            let flags = semantic.enumerated().reduce(into: NSEvent.ModifierFlags()) { value, entry in
                if mask & (1 << entry.offset) != 0 { value.insert(entry.element) }
            }
            let expected: CommandBarSubmission? = flags.isEmpty ? .ordinary : flags == .option ? .split
                : flags == .command || flags == [.command, .option] ? .background : nil
            expect(CommandBarSubmission.resolveReturn(flags) == expected,
                   "The Return matrix admits exactly the recovered included routes")
            let pointer = flags == .command ? nil : expected
            expect(CommandBarSubmission.resolve(flags) == pointer,
                   "Pointer and original key-equivalent mappings remain unchanged")
        }
        expect(CommandBarSubmission.resolveTextCommand(NSSelectorFromString("insertNewline:"), event: nil, hasMarkedText: false) == .ordinary,
               "Existing native Return without a current event remains ordinary")
        expect(CommandBarSubmission.resolveTextCommand(NSSelectorFromString("insertNewlineIgnoringFieldEditor:"), event: nil, hasMarkedText: false) == .split,
               "Existing native Option command without a current event remains split")
        let field = NSTextField(frame: editor.bounds), delegate = ReturnFieldDelegate()
        window.contentView = field; field.delegate = delegate
        expect(window.makeFirstResponder(field), "Native field becomes the isolated first responder")
        guard let fieldEditor = field.currentEditor() as? NSTextView else { fatalError("Missing native field editor") }
        expect(fieldEditor.isFieldEditor, "The native shared field editor owns input")
        for key: UInt16 in [36, 76] {
            delegate.event = event(key, .command); delegate.commands = []; delegate.submissions = []
            fieldEditor.interpretKeyEvents([delegate.event!])
            expect(delegate.commands == ["noop:"], "Command-Return reaches the real control delegate")
            expect(delegate.submissions == [.background], "The original delegate phase produces one submission")
        }
        print("Return modifier/native field-editor: \(assertions) assertions passed")
    }
}
