import AppKit

@MainActor private final class CueParent: NSWindow {
    var key = true
    override var isKeyWindow: Bool { key }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

@main struct ShortcutHintPresentationTests {
    @MainActor static func main() {
        let app = NSApplication.shared
        let appearanceOnly = CommandLine.arguments.contains("--appearance")
        app.setActivationPolicy(appearanceOnly ? .regular : .prohibited)
        app.finishLaunching()
        Task { @MainActor in
            if appearanceOnly { await showAppearance() }
            else { await run() }
            exit(0)
        }
        app.run()
    }
    @MainActor static func run() async {
        var assertions = 0
        func check(_ condition: @autoclosure () -> Bool, _ message: String) {
            precondition(condition(), message); assertions += 1
        }
        func drain(_ interval: TimeInterval) async {
            try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
        }
        func parent() -> CueParent {
            let window = CueParent(contentRect: NSRect(x: 80, y: 80, width: 900, height: 650),
                styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false; window.isRestorable = false
            window.orderBack(nil)
            return window
        }
        func hint(_ title: String = "New Tab", editable: Bool = true) -> ShortcutPriorityHintView {
            ShortcutPriorityHintView(title: title, shortcut: "⌘T", canEdit: editable, theme: SpaceTheme(), basicBackground: nil)
        }
        check(ShortcutPriorityHintView.frame(for: NSRect(x: 100, y: 200, width: 1000, height: 800)) ==
            NSRect(x: 500, y: 400, width: 600, height: 600), "original parent screen frame, not page bounds")
        let black = ParcToastPalette(colors: [.black])
        let white = ParcToastPalette(colors: [.white])
        check(abs(black.background.redComponent - 0.3) < 0.0001 && black.isDark && black.foreground == .white,
              "neutral dark HSL adjustment and original threshold")
        check(abs(white.background.redComponent - 0.95) < 0.0001 && !white.isDark && white.foreground == .black,
              "neutral light HSL adjustment and original threshold")
        let red = ParcToastPalette(colors: [NSColor(displayP3Red: 1, green: 0, blue: 0, alpha: 1)])
        check(abs(red.background.greenComponent - 0.2) < 0.0001 && abs(red.background.blueComponent - 0.2) < 0.0001,
              "saturated middle-lightness adjustment retains hue")
        let averaged = ParcToastPalette(colors: [.black, .white])
        check(abs(averaged.background.redComponent - 0.625) < 0.0001, "gradient averages adjusted original colors")
        let pale = ParcToastPalette(colors: [NSColor(displayP3Red: 0.85, green: 0.85, blue: 0.85, alpha: 1)])
        check(abs(pale.background.redComponent - 0.6) < 0.0001, "lightness 0.8–0.95 steps down 0.25")
        let basic = NSColor(displayP3Red: 0.054, green: 0.06, blue: 0.075, alpha: 1)
        let incognito = ParcToastPalette(theme: .singleColor(ThemeColor(hex: "202020")!), isDark: true, basicBackground: basic)
        check(abs(incognito.background.redComponent - 0.1594) < 0.001 && abs(incognito.background.greenComponent - 0.2766) < 0.001
              && abs(incognito.background.blueComponent - 0.5696) < 0.001 && incognito.isDark && incognito.foreground == .white,
              "the incognito basic colour replaces the Space's colours")
        let grey = ParcToastPalette(theme: .singleColor(ThemeColor(hex: "202020")!), isDark: true)
        check(abs(grey.background.redComponent - grey.background.blueComponent) < 0.0001, "without it the private Space's grey is used")
        let privateCue = ShortcutPriorityHintView(title: "New Tab", shortcut: "⌘T", canEdit: true,
                                                  theme: .singleColor(ThemeColor(hex: "202020")!), basicBackground: basic)
        check(privateCue.state.basicBackground === basic, "a private window's cue starts on the incognito basic colour")
        privateCue.update(theme: .singleColor(ThemeColor(hex: "303030")!), basicBackground: basic)
        check(privateCue.state.basicBackground === basic && privateCue.state.theme == .singleColor(ThemeColor(hex: "303030")!),
              "a theme refresh keeps it while taking the new Space theme")
        privateCue.update(theme: SpaceTheme(), basicBackground: nil)
        check(privateCue.state.basicBackground == nil, "an ordinary window's refresh clears it")
        let window = parent()
        let editor = NSTextField(frame: NSRect(x: 20, y: 20, width: 200, height: 24))
        window.contentView?.addSubview(editor); window.makeFirstResponder(editor)
        let originalResponder = window.firstResponder
        let cue = hint()
        check(cue.present(in: window), "original visible parent admits native child")
        guard let panel = window.childWindows?.first else { preconditionFailure("missing native toast child") }
        check(panel.parent === window && cue.originalWindow === window && panel.contentView === cue, "exact original child ownership")
        check(panel.frame == ShortcutPriorityHintView.frame(for: window.frame), "actual native frame")
        check(!panel.canBecomeKey && !panel.canBecomeMain && !cue.acceptsFirstResponder, "no new keyboard owner")
        check(window.firstResponder === originalResponder, "original native editor retained")
        check(!cue.present(in: window), "single presentation identity")
        await drain(0.2)
        check(cue.accessoryRect.isEmpty, "original accessory delay")
        check(cue.hitTest(NSPoint(x: 20, y: 400)) == nil, "empty host has no view input target")
        await drain(0.8)
        check(cue.bodyRect.width > 0 && cue.bodyRect.height >= 42, "real SwiftUI body lays out")
        check(cue.accessoryRect.width > 0 && cue.accessoryRect.minY >= cue.bodyRect.maxY - 1, "accessory appears below original body")
        let moved = window.frame.offsetBy(dx: 20, dy: 20)
        window.setFrame(moved, display: false)
        check(panel.frame == ShortcutPriorityHintView.frame(for: moved), "the child moves with its original parent")
        let placed = panel.frame
        window.setFrame(NSRect(origin: moved.origin, size: NSSize(width: moved.width + 100, height: moved.height + 50)), display: false)
        check(panel.frame == placed, "the cue is framed once; resizing the parent does not re-place it")
        cue.dismiss(animated: true)
        check(cue.isRetiring && panel.ignoresMouseEvents, "retirement revokes input before animation")
        check(cue.hitTest(NSPoint(x: cue.bodyRect.midX, y: cue.bodyRect.midY)) == nil, "retiring child refuses input")
        let replacement = hint("Close Tab")
        check(replacement.present(in: window), "new exact command can replace passive old child")
        await drain(1.1)
        check(panel.parent == nil && panel.contentView == nil && !panel.isVisible, "old passive child closes after original delay")
        check(replacement.originalWindow === window && replacement.window?.parent === window, "old completion cannot retire replacement")
        replacement.dismiss(animated: false)
        check(window.childWindows?.isEmpty != false, "immediate retirement removes original child")
        check(!replacement.present(in: window), "retired identity cannot be resurrected")
        let early = hint()
        check(early.present(in: window), "early child admitted")
        early.dismiss(animated: false); await drain(0.6)
        check(early.accessoryRect.isEmpty && early.window == nil, "cancelled delayed accessory cannot revive child")
        let hidden = hint(); check(hidden.present(in: window), "hide owner admitted")
        var hiddenDismissals = 0
        hidden.onDismiss = { hiddenDismissals += 1 }
        hidden.isHidden = true
        check(hiddenDismissals == 1, "hidden owner requests exact native cue consumption")
        check(hidden.isRetiring && hidden.window == nil, "native hiding retires presentation")
        let detached = hint(); check(detached.present(in: window), "detach owner admitted")
        detached.removeFromSuperview()
        check(detached.isRetiring && detached.window == nil, "native detachment retires presentation")
        let lost = hint(); check(lost.present(in: window), "key owner admitted")
        window.key = false
        NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: window)
        check(lost.window == nil && lost.isRetiring, "original key loss immediately retires child")
        let refused = hint()
        check(!refused.present(in: window), "foreign key ownership refuses cue")
        window.key = true
        let fullScreen = hint(); check(fullScreen.present(in: window), "full-screen owner admitted")
        var fullScreenDismissals = 0
        fullScreen.onDismiss = { fullScreenDismissals += 1 }
        NotificationCenter.default.post(name: NSWindow.willEnterFullScreenNotification, object: window)
        check(fullScreenDismissals == 1 && fullScreen.isRetiring && fullScreen.window == nil,
              "a full-screen transition consumes the cue and retires its child")
        let noAccessory = hint(editable: false); check(noAccessory.present(in: window), "noneditable native cue admitted")
        await drain(0.6); check(noAccessory.accessoryRect.isEmpty, "missing registered command has no Edit control")
        noAccessory.dismiss(animated: false)
        window.close()
        print("Shortcut hint presentation: \(assertions) assertions passed")
    }
    @MainActor private static func showAppearance() async {
        let window = NSWindow(contentRect: NSRect(x: 140, y: 140, width: 1000, height: 650),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Parc Shortcut Hint Component — inert"
        window.isReleasedWhenClosed = false; window.isRestorable = false
        window.appearance = NSAppearance(named: CommandLine.arguments.contains("--dark") ? .darkAqua : .aqua)
        let editor = NSTextField(string: "Original native editor — no browser or command execution")
        editor.frame = NSRect(x: 32, y: 290, width: 530, height: 26)
        window.contentView?.addSubview(editor)
        window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
        window.makeFirstResponder(editor)
        try? await Task.sleep(nanoseconds: 200_000_000)
        let hint = ShortcutPriorityHintView(title: "New Tab", shortcut: "⌘T", canEdit: true,
            theme: SpaceTheme.singleColor(ThemeColor(hex: "568AC5")!), basicBackground: nil)
        hint.onEdit = { hint.dismiss(animated: true) }
        hint.onDismiss = { hint.dismiss(animated: true) }
        precondition(hint.present(in: window))
        try? await Task.sleep(nanoseconds: 35_000_000_000)
        hint.dismiss(animated: false); window.close()
    }

}
