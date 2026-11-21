import AppKit
import Testing
@testable import Parc

struct BrowserCommandAdmissionTests {
    enum Command: CaseIterable { case clearToday, closeWindow, exit, find, fullscreen }
    enum Obstacle: CaseIterable { case hidden, minimized, sheet, otherKeyWindow, retiredOwner }

    @MainActor private final class Window: NSWindow {
        var shown = true
        var minimized = false
        var key = true
        var testSheet: NSWindow?
        var testResponder: NSResponder?
        var requests = 0
        var fullscreenAvailable = true
        var inFullscreen = false
        var canClose = true

        override var isVisible: Bool { shown }
        override var isMiniaturized: Bool { minimized }
        override var isKeyWindow: Bool { key }
        override var attachedSheet: NSWindow? { testSheet }
        override var firstResponder: NSResponder? { testResponder }
        override var styleMask: NSWindow.StyleMask {
            get { canClose ? [.closable] : .borderless }
            set { super.styleMask = newValue }
        }

        override func performClose(_ sender: Any?) { requests += 1 }
        override func toggleFullScreen(_ sender: Any?) { requests += 1 }
        override func validateMenuItem(_ item: NSMenuItem) -> Bool {
            item.title = inFullscreen ? "Exit Full Screen" : "Enter Full Screen"
            return fullscreenAvailable
        }

        init() {
            _ = NSApplication.shared
            super.init(contentRect: NSRect(x: 0, y: 0, width: 300, height: 200),
                       styleMask: .borderless, backing: .buffered, defer: false)
            isReleasedWhenClosed = false
        }
    }

    @MainActor private final class ComposingEditor: NSTextView {
        override func hasMarkedText() -> Bool { true }
    }

    @MainActor private final class Fixture {
        let window = Window()
        var available = true
        var exitResult = true

        func request(_ kind: Command, prepare: @escaping () -> Void = {}) -> () -> Bool {
            let available = { [weak self] in self?.available == true }
            let execute: () -> Void = { [weak self] in self?.window.requests += 1 }
            switch kind {
            case .clearToday:
                let command = BrowserClearTodayCommand(window: window, ownerIsAvailable: available, prepare: prepare, clear: execute)
                return command.perform
            case .exit:
                let command = BrowserExitCommand(window: window, targetIsAvailable: available, prepare: prepare) {
                    execute()
                    return self.exitResult
                }
                return command.perform
            case .find:
                let command = BrowserFindCommand(action: .next, window: window, available: available, prepare: prepare, execute: execute)
                return command.perform
            case .closeWindow:
                let command = BrowserWindowCloseCommand(window: window, ownerIsAvailable: available, prepare: prepare)
                return { command.perform(nil) }
            case .fullscreen:
                let command = BrowserWindowFullscreenCommand(window: window, ownerIsAvailable: available, prepare: prepare)
                return { command.perform(nil) }
            }
        }
    }

    @Test(arguments: Command.allCases)
    @MainActor func aCommandRunsOnlyOnceInItsOriginalWindow(kind: Command) {
        let fixture = Fixture(), other = Window()
        let perform = fixture.request(kind)
        #expect(perform())
        #expect(!perform())
        #expect(fixture.window.requests == 1)
        #expect(other.requests == 0)
    }

    @Test(arguments: Command.allCases, Obstacle.allCases)
    @MainActor func aWindowThatCannotAcceptTheCommandDoesNotRunIt(kind: Command, obstacle: Obstacle) {
        let fixture = Fixture()
        switch obstacle {
        case .hidden: fixture.window.shown = false
        case .minimized: fixture.window.minimized = true
        case .sheet: fixture.window.testSheet = Window()
        case .otherKeyWindow: fixture.window.key = false
        case .retiredOwner: fixture.available = false
        }
        #expect(!fixture.request(kind)())
        #expect(fixture.window.requests == 0)
    }

    @Test(arguments: Command.allCases)
    @MainActor func aCommandRechecksOwnershipAfterPreparing(kind: Command) {
        let fixture = Fixture()
        let perform = fixture.request(kind) { fixture.available = false }
        #expect(!perform())
        #expect(fixture.window.requests == 0)
    }

    @Test(arguments: Command.allCases)
    @MainActor func preparationCanRestoreTheOriginalKeyWindow(kind: Command) {
        let fixture = Fixture()
        fixture.window.key = false
        let perform = fixture.request(kind) { fixture.window.key = true }
        #expect(perform())
        #expect(fixture.window.requests == 1)
    }

    @Test(arguments: [Command.clearToday, .exit, .find])
    @MainActor func aNativeCompositionKeepsOwnership(kind: Command) {
        let fixture = Fixture()
        fixture.window.testResponder = ComposingEditor()
        #expect(!fixture.request(kind)())
        #expect(fixture.window.requests == 0)
    }

    @Test(arguments: [Command.clearToday, .exit, .closeWindow, .fullscreen])
    @MainActor func aReentrantRequestCannotExecuteTwice(kind: Command) {
        let fixture = Fixture()
        var perform: (() -> Bool)?
        var nested: Bool?
        perform = fixture.request(kind) { nested = perform?() }
        #expect(perform?() == true)
        #expect(nested == false)
        #expect(fixture.window.requests == 1)
        perform = nil
    }

    @Test @MainActor func exitReturnsTheOriginalOwnerResult() {
        let fixture = Fixture()
        fixture.exitResult = false
        #expect(!fixture.request(.exit)())
        #expect(fixture.window.requests == 1)
    }

    @Test @MainActor func aWindowThatCannotCloseRefusesTheCommand() {
        let fixture = Fixture()
        fixture.window.canClose = false
        #expect(!fixture.request(.closeWindow)())
        #expect(fixture.window.requests == 0)
    }

    @Test @MainActor func fullscreenRequiresTheOriginallyValidatedMenuAction() {
        let fixture = Fixture()
        let command = BrowserWindowFullscreenCommand(window: fixture.window, ownerIsAvailable: { true })
        let other = NSMenuItem(title: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "")
        #expect(!command.validate(other))
    }

    @Test @MainActor func fullscreenValidationUsesTheOriginalWindowPhase() {
        let fixture = Fixture()
        fixture.window.inFullscreen = true
        let command = BrowserWindowFullscreenCommand(window: fixture.window, ownerIsAvailable: { true })
        let item = NSMenuItem(title: "", action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "")
        #expect(command.validate(item))
        #expect(item.title == "Exit Full Screen")
    }

    @Test @MainActor func fullscreenRevalidatesAfterPreparation() {
        let fixture = Fixture()
        let perform = fixture.request(.fullscreen) { fixture.window.fullscreenAvailable = false }
        #expect(!perform())
        #expect(fixture.window.requests == 0)
    }

    @Test(arguments: [("insertNewline:", false, BrowserFindAction.next), ("insertNewline:", true, .previous),
                      ("moveUp:", false, .previous), ("moveDown:", false, .next)])
    func findFieldKeysSelectTheDirection(selector: String, shift: Bool, expected: BrowserFindAction) {
        #expect(BrowserFindAction.fieldAction(NSSelectorFromString(selector), shift: shift, composing: false) == expected)
    }

    @Test func markedFindTextDoesNotDispatchReturn() {
        #expect(BrowserFindAction.fieldAction(NSSelectorFromString("insertNewline:"), shift: false, composing: true) == nil)
    }

    @Test @MainActor func aFindReplyBelongsOnlyToItsOriginalDocument() {
        var owner: NSObject? = NSObject()
        let other = NSObject()
        let state = BrowserFindState(owner: owner!, revision: 4)
        #expect(state.matches(owner, revision: 4))
        #expect(!state.matches(owner, revision: 5))
        #expect(!state.matches(other, revision: 4))
        owner = nil
        #expect(!state.matches(nil, revision: 4))
    }
}

extension BrowserCommandAdmissionTests {
    @Test(arguments: Command.allCases, [false, true])
    @MainActor func aNewModalOrFocusChangeDuringPreparationCancelsTheCommand(kind: Command, opensSheet: Bool) {
        let fixture = Fixture()
        let command = fixture.request(kind) {
            if opensSheet { fixture.window.testSheet = Window() }
            else { fixture.window.key = false }
        }
        #expect(!command())
        #expect(fixture.window.requests == 0)
    }

    @Test(arguments: BrowserFindAction.allCases)
    func findKeepsTheNativeEditingActionsInTheResponderChain(action: BrowserFindAction) {
        let expectsNativeText = action == .jumpToSelection || action == .replace
        #expect(action.isNativeTextOnly == expectsNativeText)
    }
}

extension BrowserCommandAdmissionTests {
    @Test(arguments: [Command.clearToday, .exit, .closeWindow, .fullscreen, .find])
    @MainActor func aCommandReceiptDoesNotKeepItsClosedWindowAlive(command: Command) throws {
        _ = NSApplication.shared
        weak var owner: Window?
        let perform: () -> Bool = autoreleasepool {
            let window = Window()
            owner = window
            switch command {
            case .clearToday:
                return BrowserClearTodayCommand(window: window, ownerIsAvailable: { true }, clear: {}).perform
            case .exit:
                return BrowserExitCommand(window: window, targetIsAvailable: { true }, execute: { true }).perform
            case .closeWindow:
                let command = BrowserWindowCloseCommand(window: window, ownerIsAvailable: { true })
                return { command.perform(nil) }
            case .fullscreen:
                let command = BrowserWindowFullscreenCommand(window: window, ownerIsAvailable: { true })
                return { command.perform(nil) }
            case .find:
                return BrowserFindCommand(action: .next, window: window, available: { true }, execute: {}).perform
            }
        }
        #expect(owner == nil)
        #expect(!perform())
    }
}
