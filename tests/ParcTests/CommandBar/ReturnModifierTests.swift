import AppKit
import Testing
@testable import Parc

@MainActor
struct ReturnModifierTests {
    final class ReturnEditor: NSTextView {
        var commands: [Selector] = []
        override func doCommand(by selector: Selector) { commands.append(selector) }
        override func insertText(_ insertString: Any, replacementRange: NSRange) {}
    }

    final class ReturnFieldDelegate: NSObject, NSTextFieldDelegate {
        var event: NSEvent?
        var commands: [String] = []
        var submissions: [CommandBarSubmission] = []
        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            commands.append(NSStringFromSelector(selector))
            guard let submission = CommandBarSubmission.resolveTextCommand(selector, event: event,
                hasMarkedText: textView.hasMarkedText()) else { return false }
            submissions.append(submission)
            return true
        }
    }

    struct ReturnKey: Sendable, CustomTestStringConvertible {
        let keyCode: UInt16
        let flags: NSEvent.ModifierFlags
        let selector: String
        let expected: CommandBarSubmission?
        var characters: String { keyCode == 76 ? "\u{3}" : "\r" }
        var testDescription: String { "key \(keyCode) flags \(flags.rawValue)" }
    }

    nonisolated static let returnKeys: [ReturnKey] = [UInt16(36), 76].flatMap { key in
        [
            ReturnKey(keyCode: key, flags: [], selector: "insertNewline:", expected: .ordinary),
            ReturnKey(keyCode: key, flags: .option, selector: "insertNewlineIgnoringFieldEditor:", expected: .split),
            ReturnKey(keyCode: key, flags: .command, selector: "noop:", expected: .background),
            ReturnKey(keyCode: key, flags: .shift, selector: "insertNewline:", expected: nil),
            ReturnKey(keyCode: key, flags: .control, selector: "insertLineBreak:", expected: nil),
            ReturnKey(keyCode: key, flags: [.command, .shift], selector: "noop:", expected: nil),
        ]
    }

    func event(_ key: ReturnKey, window: NSWindow? = nil) -> NSEvent {
        CommandBarTestSupport.keyEvent(key.keyCode, key.flags, characters: key.characters, window: window)
    }

    @Test(arguments: returnKeys)
    func appKitMapsEachReturnToItsTextCommand(key: ReturnKey) {
        let window = CommandBarTestSupport.borderlessWindow(width: 180, height: 80)
        let editor = ReturnEditor(frame: window.contentView!.bounds)
        window.contentView = editor
        editor.interpretKeyEvents([event(key, window: window)])
        #expect(editor.commands.map(NSStringFromSelector) == [key.selector])
    }

    @Test(arguments: returnKeys)
    func theTextCommandRoutesOnlyTheIncludedReturnOperations(key: ReturnKey) {
        let resolved = CommandBarSubmission.resolveTextCommand(NSSelectorFromString(key.selector), event: event(key), hasMarkedText: false)
        #expect(resolved == key.expected)
    }

    @Test(arguments: returnKeys)
    func markedTextKeepsItsInputMethodOwner(key: ReturnKey) {
        let resolved = CommandBarSubmission.resolveTextCommand(NSSelectorFromString(key.selector), event: event(key), hasMarkedText: true)
        #expect(resolved == nil)
    }

    @Test(arguments: [UInt16(36), 76])
    func returnAndKeypadEnterKeepCommandWithDeviceFlags(keyCode: UInt16) {
        let key = ReturnKey(keyCode: keyCode, flags: [.command, .capsLock, .numericPad, .function], selector: "noop:", expected: .background)
        let resolved = CommandBarSubmission.resolveTextCommand(NSSelectorFromString("noop:"), event: event(key), hasMarkedText: false)
        #expect(resolved == .background)
    }

    @Test func anUnattributedNoopNeverSubmits() {
        #expect(CommandBarSubmission.resolveTextCommand(NSSelectorFromString("noop:"), event: nil, hasMarkedText: false) == nil)
    }

    @Test func aKeyReleaseCannotDuplicateAnOperation() {
        let release = CommandBarTestSupport.keyEvent(36, .command, type: .keyUp)
        #expect(CommandBarSubmission.resolveTextCommand(NSSelectorFromString("noop:"), event: release, hasMarkedText: false) == nil)
    }

    @Test func anUnrelatedCommandKeyIsNotReturn() {
        let other = CommandBarTestSupport.keyEvent(40, .command)
        #expect(CommandBarSubmission.resolveTextCommand(NSSelectorFromString("noop:"), event: other, hasMarkedText: false) == nil)
    }

    @Test func aNativeEditingCommandIsNotReinterpretedFromModifiers() {
        let command = CommandBarTestSupport.keyEvent(36, .command)
        #expect(CommandBarSubmission.resolveTextCommand(NSSelectorFromString("moveLeft:"), event: command, hasMarkedText: false) == nil)
    }

    @Test func nativeReturnWithoutACurrentEventStaysOrdinary() {
        #expect(CommandBarSubmission.resolveTextCommand(NSSelectorFromString("insertNewline:"), event: nil, hasMarkedText: false) == .ordinary)
    }

    @Test func nativeOptionCommandWithoutACurrentEventStaysSplit() {
        let selector = NSSelectorFromString("insertNewlineIgnoringFieldEditor:")
        #expect(CommandBarSubmission.resolveTextCommand(selector, event: nil, hasMarkedText: false) == .split)
    }

    static func flags(forMask mask: Int) -> NSEvent.ModifierFlags {
        let semantic: [NSEvent.ModifierFlags] = [.command, .option, .control, .shift]
        return semantic.enumerated().reduce(into: NSEvent.ModifierFlags()) { value, entry in
            if mask & (1 << entry.offset) != 0 { value.insert(entry.element) }
        }
    }

    static func expectedReturn(_ flags: NSEvent.ModifierFlags) -> CommandBarSubmission? {
        if flags.isEmpty { return .ordinary }
        if flags == .option { return .split }
        if flags == .command || flags == [.command, .option] { return .background }
        return nil
    }

    @Test(arguments: 0..<16)
    func theReturnMatrixAdmitsExactlyTheIncludedRoutes(mask: Int) {
        let flags = Self.flags(forMask: mask)
        #expect(CommandBarSubmission.resolveReturn(flags) == Self.expectedReturn(flags))
    }

    @Test(arguments: 0..<16)
    func pointerAndKeyEquivalentMappingsKeepCommandOut(mask: Int) {
        let flags = Self.flags(forMask: mask)
        let expected = flags == .command ? nil : Self.expectedReturn(flags)
        #expect(CommandBarSubmission.resolve(flags) == expected)
    }

    @Test func forceOpenWinsOverTheSplitBit() {
        #expect(CommandBarSubmission.resolveReturn([.option, .command]) == .background)
    }

    @Test(arguments: [
        [.option, .command, .capsLock, .numericPad, .function], [.command, .capsLock, .numericPad, .function],
    ] as [NSEvent.ModifierFlags])
    func deviceFlagsDoNotChangeForceOpen(flags: NSEvent.ModifierFlags) {
        #expect(CommandBarSubmission.resolveReturn(flags) == .background)
    }

    @Test func commandReturnSharesTheForceOpenRoute() {
        #expect(CommandBarSubmission.resolveReturn(.command) == .background)
    }

    @Test(arguments: [
        .shift, .control, [.command, .shift], [.option, .shift], [.command, .option, .shift], [.command, .option, .control],
    ] as [NSEvent.ModifierFlags])
    func unsupportedModifiersKeepResponderOwnership(flags: NSEvent.ModifierFlags) {
        #expect(CommandBarSubmission.resolveReturn(flags) == nil)
    }

    @Test(arguments: [UInt16(36), 76])
    func commandReturnReachesTheRealFieldDelegate(keyCode: UInt16) throws {
        let window = CommandBarTestSupport.borderlessWindow(width: 180, height: 80)
        let field = NSTextField(frame: window.contentView!.bounds)
        let delegate = ReturnFieldDelegate()
        window.contentView = field
        field.delegate = delegate
        #expect(window.makeFirstResponder(field))
        let fieldEditor = try #require(field.currentEditor() as? NSTextView)
        let input = CommandBarTestSupport.keyEvent(keyCode, .command, characters: keyCode == 76 ? "\u{3}" : "\r", window: window)
        delegate.event = input
        fieldEditor.interpretKeyEvents([input])
        #expect(delegate.commands == ["noop:"])
        #expect(delegate.submissions == [.background])
    }
}
