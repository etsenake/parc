import AppKit
import Testing
@testable import ParcCore
@testable import ParcKit
@testable import ParcSidebar

@MainActor
struct AutoArchiveEducationViewTests {
    @MainActor
    private final class KeyWindow: NSWindow {
        override var isKeyWindow: Bool { true }
    }

    struct Layout: Sendable, CustomTestStringConvertible {
        let width: CGFloat
        let dark: Bool
        var testDescription: String { "\(Int(width)) wide, \(dark ? "dark" : "light")" }
    }

    nonisolated static let layouts = [144, 228, 500].flatMap { width in
        [false, true].map { Layout(width: CGFloat(width), dark: $0) }
    }

    private static func message(of view: AutoArchiveEducationView) -> NSTextView {
        view.keyViewControls.compactMap { $0 as? NSTextView }.first!
    }

    private static func button(of view: AutoArchiveEducationView) -> NSButton {
        view.keyViewControls.compactMap { $0 as? NSButton }.first!
    }

    private static func attached(_ view: AutoArchiveEducationView) -> NSWindow {
        _ = NSApplication.shared
        let window = KeyWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 300),
                               styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView?.addSubview(view)
        return window
    }

    @Test func onlySettingsAndGotItJoinTheKeyLoop() {
        _ = NSApplication.shared
        #expect(AutoArchiveEducationView(frame: .zero).keyViewControls.count == 2)
    }

    @Test func theRecoveredContentIsRetained() {
        _ = NSApplication.shared
        let view = AutoArchiveEducationView(frame: .zero)
        #expect(Self.message(of: view).string.contains("12 hours"))
        #expect(Self.button(of: view).title == "Got it")
    }

    @Test func detachedNativeActionsCannotReachTheOriginalOwner() {
        _ = NSApplication.shared
        let view = AutoArchiveEducationView(frame: .zero)
        var actions = 0
        view.onDismiss = { actions += 1 }
        view.onSettings = { actions += 1 }
        let button = Self.button(of: view)
        _ = button.sendAction(button.action, to: button.target)
        #expect(actions == 0)
    }

    @Test func gotItDismissesWhileTheWindowIsKey() {
        _ = NSApplication.shared
        let view = AutoArchiveEducationView(frame: NSRect(x: 0, y: 0, width: 228, height: 160))
        let window = Self.attached(view)
        defer { window.close() }
        var dismissals = 0
        view.onDismiss = { dismissals += 1 }
        let button = Self.button(of: view)
        _ = button.sendAction(button.action, to: button.target)
        #expect(dismissals == 1)
    }

    @Test func exitingControlsCannotAcceptFocusOrAction() {
        _ = NSApplication.shared
        let view = AutoArchiveEducationView(frame: .zero)
        view.setInteractionEnabled(false)
        #expect(!Self.message(of: view).acceptsFirstResponder)
        #expect(!Self.button(of: view).isEnabled)
    }

    @Test func reenablingInteractionRestoresFocusAndAction() {
        _ = NSApplication.shared
        let view = AutoArchiveEducationView(frame: .zero)
        view.setInteractionEnabled(false)
        view.setInteractionEnabled(true)
        #expect(Self.message(of: view).acceptsFirstResponder)
        #expect(Self.button(of: view).isEnabled)
    }

    @Test(arguments: layouts)
    func wrappedInformationFitsItsFrame(layout: Layout) throws {
        _ = NSApplication.shared
        let view = AutoArchiveEducationView(frame: .zero)
        view.appearance = NSAppearance(named: layout.dark ? .darkAqua : .aqua)
        view.applyPalette(ThemeChromePalette(theme: .singleColor(ThemeColor(hex: "B9B5D4")!), isDark: layout.dark))
        view.frame = NSRect(x: 0, y: 0, width: layout.width, height: view.preferredHeight(for: layout.width))
        view.layoutSubtreeIfNeeded()
        let message = Self.message(of: view)
        let container = try #require(message.textContainer)
        let manager = try #require(message.layoutManager)
        manager.ensureLayout(for: container)
        #expect(manager.usedRect(for: container).height <= message.bounds.height + 1)
    }

    @Test(arguments: layouts)
    func theBodyAndGotItStayInsideTheCardAndSeparate(layout: Layout) {
        _ = NSApplication.shared
        let view = AutoArchiveEducationView(frame: .zero)
        view.appearance = NSAppearance(named: layout.dark ? .darkAqua : .aqua)
        view.applyPalette(ThemeChromePalette(theme: .singleColor(ThemeColor(hex: "B9B5D4")!), isDark: layout.dark))
        view.frame = NSRect(x: 0, y: 0, width: layout.width, height: view.preferredHeight(for: layout.width))
        view.layoutSubtreeIfNeeded()
        let message = Self.message(of: view), button = Self.button(of: view)
        #expect(button.frame.minY >= message.frame.maxY)
        #expect(button.frame.maxY <= view.bounds.maxY)
    }
}
