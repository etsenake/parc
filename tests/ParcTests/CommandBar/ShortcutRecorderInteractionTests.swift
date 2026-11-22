import AppKit
import Testing
@testable import Parc
@testable import ParcKit
@testable import ParcCommandBar

struct ShortcutRecorderInteractionTests {
    @MainActor private final class Window: NSWindow {
        override var isVisible: Bool { true }
        override var isKeyWindow: Bool { true }
    }

    @MainActor private final class Fixture {
        let window: Window
        let recorder: ShortcutRecorderView
        var changes: [KeyboardShortcut?] = []
        var previews: [[String]] = []
        var accepts = true

        init() throws {
            _ = NSApplication.shared
            let frame = NSRect(x: 0, y: 0, width: 100, height: 30)
            window = Window(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            recorder = ShortcutRecorderView(frame: frame)
            recorder.shortcut = KeyboardShortcut(key: "j", flags: [.command, .option])
            window.contentView = recorder
            recorder.onChange = { [weak self] value in
                self?.changes.append(value)
                return self?.accepts == true
            }
            recorder.onPreview = { [weak self] in self?.previews.append($0) }
            try #require(window.makeFirstResponder(recorder))
            try #require(recorder.isRecording)
        }

        func press(_ code: UInt16, text: String = "", flags: NSEvent.ModifierFlags = [], repeats: Bool = false) throws {
            let event = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
                windowNumber: 0, context: nil, characters: text, charactersIgnoringModifiers: text,
                isARepeat: repeats, keyCode: code))
            recorder.keyDown(with: event)
        }
    }

    @Test(arguments: [UInt16(51), UInt16(117)])
    @MainActor func eitherDeleteKeyClearsTheBinding(code: UInt16) throws {
        let fixture = try Fixture()
        try fixture.press(code)
        #expect(fixture.changes == [nil])
        #expect(fixture.recorder.shortcut == nil)
        #expect(!fixture.recorder.isRecording)
    }

    @Test @MainActor func escapeCancelsWithoutWriting() throws {
        let fixture = try Fixture()
        let original = fixture.recorder.shortcut
        try fixture.press(53)
        #expect(fixture.changes.isEmpty)
        #expect(fixture.recorder.shortcut == original)
        #expect(!fixture.recorder.isRecording)
    }

    @Test @MainActor func aRepeatedKeyDoesNotEndRecording() throws {
        let fixture = try Fixture()
        defer { fixture.recorder.cancelRecording() }
        try fixture.press(51, repeats: true)
        #expect(fixture.changes.isEmpty)
        #expect(fixture.recorder.isRecording)
    }

    @Test(arguments: [false, true])
    @MainActor func aChordReplacesTheKeycapOnlyAfterTheChangeIsAccepted(accepts: Bool) throws {
        let fixture = try Fixture()
        fixture.accepts = accepts
        let original = fixture.recorder.shortcut
        let chord = KeyboardShortcut(key: "p", flags: [.control, .option])
        try fixture.press(35, text: "p", flags: chord.flags)
        #expect(fixture.changes == [chord])
        #expect(fixture.recorder.shortcut == (accepts ? chord : original))
        #expect(!fixture.recorder.isRecording)
    }

    @Test @MainActor func modifierChangesPreviewWithoutWriting() throws {
        let fixture = try Fixture()
        defer { fixture.recorder.cancelRecording() }
        let event = try #require(NSEvent.keyEvent(with: .flagsChanged, location: .zero, modifierFlags: [.command, .shift],
            timestamp: 0, windowNumber: 0, context: nil, characters: "", charactersIgnoringModifiers: "",
            isARepeat: false, keyCode: 55))
        fixture.recorder.flagsChanged(with: event)
        #expect(fixture.previews == [["⇧", "⌘"]])
        #expect(fixture.changes.isEmpty)
    }

    enum Retirement: CaseIterable { case hidden, disabled, detached, keyLoss }

    @Test(arguments: Retirement.allCases)
    @MainActor func retiringTheRecorderCancelsAnUnfinishedChange(reason: Retirement) throws {
        let fixture = try Fixture()
        switch reason {
        case .hidden: fixture.recorder.isHidden = true
        case .disabled: fixture.recorder.isEnabled = false
        case .detached: fixture.window.contentView = nil
        case .keyLoss: NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: fixture.window)
        }
        #expect(!fixture.recorder.isRecording)
        #expect(fixture.changes.isEmpty)
    }

    @Test(arguments: [false, true])
    @MainActor func theRecordingPulseRespectsReduceMotion(reduceMotion: Bool) throws {
        let fixture = try Fixture()
        defer { fixture.recorder.cancelRecording() }
        fixture.recorder.refreshPresentation(reduceMotion: reduceMotion)
        let pulse = fixture.recorder.layer?.sublayers?.contains { $0.animation(forKey: "opacity") != nil }
        #expect(pulse == !reduceMotion)
    }
}

extension ShortcutRecorderInteractionTests {
    @Test @MainActor func anUnsupportedPrintableKeyEndsCaptureWithoutACommit() throws {
        let fixture = try Fixture()
        try fixture.press(0)
        #expect(fixture.changes.isEmpty)
        #expect(!fixture.recorder.isRecording)
    }

    @Test @MainActor func movingFocusAwayEndsCapture() throws {
        let fixture = try Fixture()
        let next = NSButton(title: "Next", target: nil, action: nil)
        fixture.recorder.addSubview(next)
        #expect(fixture.window.makeFirstResponder(next))
        #expect(!fixture.recorder.isRecording)
        #expect(fixture.changes.isEmpty)
    }

    @Test @MainActor func aDisabledRecorderRefusesFocusAndAccessibilityPress() throws {
        let fixture = try Fixture()
        fixture.recorder.isEnabled = false
        #expect(!fixture.recorder.isRecording)
        #expect(!fixture.recorder.acceptsFirstResponder)
        #expect(!fixture.recorder.accessibilityPerformPress())
    }

    @Test @MainActor func removingTheRecorderEndsEachCaptureExactlyOnce() throws {
        let fixture = try Fixture()
        fixture.recorder.cancelRecording()
        var begins = 0, ends = 0
        fixture.recorder.onBegin = { begins += 1 }
        fixture.recorder.onEnd = { ends += 1 }
        #expect(fixture.window.makeFirstResponder(fixture.recorder))
        fixture.window.contentView = nil
        #expect(!fixture.recorder.isRecording)
        #expect(begins == 1)
        #expect(ends == 1)
    }
}
