import AppKit
import CoreText

@MainActor private final class EssentialsMenuTarget: NSObject {
    var copyCount = 0
    @objc func copyCurrentURL(_ sender: NSMenuItem) { copyCount += 1 }
}

@main @MainActor struct EssentialsTests {
    static var assertions = 0
    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        assertions += 1; precondition(condition(), message)
    }
    static func main() throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        if CommandLine.arguments.count > 1 {
            CTFontManagerRegisterFontsForURL(URL(fileURLWithPath: CommandLine.arguments[1]) as CFURL, .process, nil)
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let registry = KeyboardShortcuts(); registry.configure(directory: directory)
        let menu = NSMenu(); NSApp.mainMenu = menu
        let values: [(String, String, NSEvent.ModifierFlags)] = [
            ("newTab:", "t", .command), ("cycleToNextRecentTab:", "\t", .control),
            ("copyCurrentURL:", "c", [.command, .shift]), ("split:", "=", [.control, .shift])]
        for (id, key, flags) in values {
            let item = NSMenuItem(title: id, action: NSSelectorFromString(id), keyEquivalent: key)
            item.keyEquivalentModifierMask = flags; menu.addItem(item); registry.register(item, group: "Test")
        }
        var controller: ShortcutEssentialsWindow? = ShortcutEssentialsWindow(shortcuts: registry)
        let window = controller!.window!, surface = window.contentView!
        expect(window.level == .floating, "Education keeps its actual floating window owner")
        expect(window.collectionBehavior.contains(.fullScreenAuxiliary), "Education may accompany the original fullscreen window")
        expect(window.styleMask.contains(.fullSizeContentView) && window.styleMask.contains(.closable), "Native close and full-size content remain")
        expect(!window.isOpaque && window.titleVisibility == .hidden && window.titlebarAppearsTransparent, "Original transparent titlebar composition")
        expect(window.isMovableByWindowBackground && !window.isReleasedWhenClosed, "Native drag and retained education controller")
        expect(window.frame.size == NSSize(width: 475, height: 388), "Fixed included-row size, with the excluded mini browser window row removed")
        expect(ShortcutEssentialsWindow.origin(parent: NSRect(x: 100, y: 50, width: 1200, height: 800), education: window.frame.size)
            == NSPoint(x: 815, y: 452), "Final placement uses the original physical window's top-right ten-point inset")
        let fields = surface.subviews.compactMap { $0 as? NSTextField }
        let headline = fields.first { $0.stringValue == "Essential Keyboard Shortcuts" }!
        expect(headline.font?.fontName == "Nunito-ExtraBold", "Bundled Nunito ExtraBold is used when available")
        expect(headline.font?.pointSize == 20, "Recovered headline size")
        expect(headline.attributedStringValue.attribute(.kern, at: 0, effectiveRange: nil) as? Double == -0.8, "Recovered headline tracking")
        expect(fields.filter { $0.font?.pointSize == 15 }.count == 4, "Included rows use the original 15-point title style")
        expect(surface.subviews.compactMap { $0 as? NSBox }.count == 3, "Native divider ownership remains between included rows")
        let button = surface.subviews.compactMap { $0 as? EssentialsViewAllControl }.first!
        expect(button.superview === surface, "View All retains its original native Button presentation owner")
        let caps = surface.subviews.filter { $0.accessibilityLabel()?.hasSuffix(" shortcut") == true }
        expect(caps.count == 4, "Each included command has a named accessible binding")
        let summary = surface.accessibilityChildren()!.compactMap { $0 as? NSAccessibilityElement }.first!
        expect(summary.accessibilityRole() == .staticText && summary.accessibilityChildren()?.isEmpty == true,
               "Original passive instructions expose one static element with no duplicate label/keycap tree")
        expect(summary.accessibilityParent() as? NSView === surface && summary.accessibilityWindow() as? NSWindow === window,
               "Instruction accessibility retains the exact window through its weak surface owner")
        expect((summary.accessibilityValue() as? String)?.hasPrefix("Open a New Tab ") == true,
               "Combined reading order starts with the first actual visible row")
        let instructionValue = summary.accessibilityValue() as! String
        expect(ShortcutEssentialsWindow.commandIDs.allSatisfy { instructionValue.contains(registry.activeShortcut(for: $0)!.spokenDisplay) },
               "Combined instructions contain every current active binding")
        expect(!instructionValue.contains("without trackers"), "Instructions describe the actual Copy capability")
        expect(!summary.accessibilityPerformPress(), "Instruction text never introduces an activation action")
        let summaryFrame = summary.accessibilityFrame()
        expect(!summaryFrame.isEmpty && surface.accessibilityHitTest(NSPoint(x: summaryFrame.midX, y: summaryFrame.midY)) as? NSAccessibilityElement === summary,
               "Native AX hit testing returns the same instruction group, not a decorative child")
        let originalResponder = window.firstResponder
        for (cap, id) in zip(caps, ShortcutEssentialsWindow.commandIDs) {
            expect(cap.accessibilityValue() as? String == registry.shortcut(for: id)?.spokenDisplay, "Live displayed binding matches its actual command")
        }
        let recent = zip(caps, ShortcutEssentialsWindow.commandIDs).first { $0.1 == "cycleToNextRecentTab:" }!.0 as! ShortcutKeycapView
        expect(recent.symbols == ["⌃", "TAB"], "Essentials keycaps spell Tab out")
        let custom = KeyboardShortcut(key: "k", flags: [.command, .control])
        try registry.set(custom, for: "newTab:")
        expect(caps[0].accessibilityValue() as? String == custom.spokenDisplay, "A saved custom binding updates the open panel")
        try registry.set(custom, for: "copyCurrentURL:")
        expect(!(summary.accessibilityValue() as! String).contains("Open a New Tab")
               && !(summary.accessibilityValue() as! String).contains("Copy Page URL"),
               "Conflicting optional rows disappear from the original combined AX value too")
        expect(caps[0].isHidden && caps[2].isHidden, "Conflicting saved shortcuts do not advertise two active education rows")
        try registry.reset("copyCurrentURL:")
        expect(!caps[0].isHidden && !caps[2].isHidden && caps[0].accessibilityValue() as? String == custom.spokenDisplay,
               "Resolving the other assignment restores the original live education bindings")
        try registry.set(nil, for: "newTab:")
        expect(caps[0].isHidden, "Disabled binding removes its optional education row")
        expect(fields.first { $0.stringValue == "Open a New Tab" }?.isHidden == true,
               "Disabled binding does not leave a misleading description")
        expect(fields.first { $0.stringValue == "Switch to a Recent Tab" }?.frame.minY == 102,
               "Remaining original rows close the disabled-row gap")
        let wide = KeyboardShortcut(key: "k", flags: [.control, .option, .shift, .command])
        try registry.set(wide, for: "newTab:")
        let cap = caps[0] as! ShortcutKeycapView
        surface.layoutSubtreeIfNeeded(); cap.layoutSubtreeIfNeeded()
        expect(cap.frame.maxX == 445 && cap.frame.width > 103, "Long actual bindings keep the right edge and expand without clipping the original keycaps")
        expect(!cap.acceptsFirstResponder && cap.hitTest(.zero) == nil, "Passive keycaps cannot steal native recorder or keyboard focus")
        expect(cap.accessibilityValue() as? String == wide.spokenDisplay, "Custom modifier binding keeps an accessible semantic value")
        try registry.reset("newTab:")
        expect(caps[0].accessibilityValue() as? String == registry.shortcut(for: "newTab:")?.spokenDisplay, "Reset refreshes the same production presentation")
        try registry.set(KeyboardShortcut(key: " ", flags: .control), for: "newTab:")
        expect(caps[0].accessibilityValue() as? String == "⌃Space" && (summary.accessibilityValue() as! String).contains("⌃Space"),
               "A Space binding is spoken as Space in its keycaps and the instructions")
        try registry.reset("newTab:")
        expect(window.firstResponder === originalResponder, "Live binding layout/AX updates do not claim keyboard focus")
        expect(surface.accessibilityChildren()!.contains { ($0 as? NSAccessibilityElement) === summary },
               "Binding updates preserve the exact passive accessibility element")
        for id in ShortcutEssentialsWindow.commandIDs { try registry.set(nil, for: id) }
        expect(!summary.isAccessibilityElement() && summary.accessibilityValue() == nil && summary.accessibilityFrame().isEmpty,
               "No active bindings means no stale instructional content or geometry")
        expect(!surface.accessibilityChildren()!.contains { ($0 as? NSAccessibilityElement) === summary },
               "The empty passive row group is removed without replacing the View All owner")
        for id in ShortcutEssentialsWindow.commandIDs { try registry.reset(id) }
        expect(summary.isAccessibilityElement() && (summary.accessibilityValue() as! String).hasPrefix("Open a New Tab"),
               "Explicit reset restores the same ordered instruction element")
        surface.isHidden = true
        expect(!summary.isAccessibilityElement() && summary.accessibilityWindow() == nil,
               "A hidden original surface cannot leave a separately accessible instruction tree")
        surface.isHidden = false
        surface.appearance = NSAppearance(named: .darkAqua)
        surface.viewDidChangeEffectiveAppearance(); surface.updateLayer()
        let darkBackground = NSColor(cgColor: surface.layer!.backgroundColor!)!.usingColorSpace(.sRGB)!
        expect(abs(darkBackground.redComponent - 21/255) < 0.0001 && abs(darkBackground.blueComponent - 48/255) < 0.0001, "Dark PopoverBackground is independent of Space theme")
        let detail = fields.first { $0.font?.pointSize == 12 }!
        let darkMessage = detail.textColor!.usingColorSpace(.sRGB)!
        expect(abs(darkMessage.redComponent - 238/255) < 0.0001 && darkMessage.alphaComponent == 0.75, "Dark PopoverMessage resource")
        surface.appearance = NSAppearance(named: .aqua)
        surface.viewDidChangeEffectiveAppearance(); surface.updateLayer()
        let lightMessage = detail.textColor!.usingColorSpace(.sRGB)!
        expect(abs(lightMessage.redComponent - 6/255) < 0.0001 && lightMessage.alphaComponent == 0.75, "Light PopoverMessage resource")
        expect(headline.textColor!.usingColorSpace(.sRGB)!.blueComponent == 0.17, "Light headline foreground resource")
        var commands = 0, settings = 0, escapes = 0
        controller!.onCommand = { _, _ in commands += 1 }
        controller!.onEscape = { escapes += 1 }
        controller!.onViewAll = { settings += 1 }
        controller!.isOwnerAvailable = { true }
        expect(!controller!.activateCommand("newTab:"), "Hidden/non-key education cannot execute a background browser command")
        window.cancelOperation(nil)
        button.rootView.onPress()
        expect(commands == 0 && settings == 0 && escapes == 0, "Hidden presentation cannot retarget its parent or Settings")
        controller!.isOwnerAvailable = { false }
        expect(!controller!.canActivateCommand("newTab:"), "Lost original owner refuses command availability")
        expect(!controller!.activateCommand("unknown:"), "Unrelated commands cannot enter education dispatch")
        let target = EssentialsMenuTarget(), copyItem = menu.items[2]
        copyItem.target = target
        func copyEvent(repeating: Bool, flags: NSEvent.ModifierFlags = [.command, .shift],
                       key: String = "c", code: UInt16 = 8) -> NSEvent {
            NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags,
                timestamp: 1, windowNumber: 0, context: nil,
                characters: flags.contains(.shift) ? key.uppercased() : key,
                charactersIgnoringModifiers: key, isARepeat: repeating, keyCode: code)!
        }
        for repeated in [false, true, true] {
            expect(menu.performKeyEquivalent(with: copyEvent(repeating: repeated)),
                   "Native menu accepts each delivered initial/repeated education chord")
        }
        expect(target.copyCount == 3, "Each native delivery invokes its original selector exactly once")
        try registry.set(nil, for: "copyCurrentURL:")
        expect(!menu.performKeyEquivalent(with: copyEvent(repeating: true)) && target.copyCount == 3,
               "Disabled command cannot reappear through repeated native delivery")
        try registry.set(KeyboardShortcut(key: "k", flags: [.command, .option]), for: "copyCurrentURL:")
        expect(!menu.performKeyEquivalent(with: copyEvent(repeating: true)),
               "Customized command does not retain the old repeated default")
        expect(menu.performKeyEquivalent(with: copyEvent(repeating: true, flags: [.command, .option], key: "k", code: 40))
               && target.copyCount == 4, "Repeated delivery uses the actual saved chord")
        try registry.reset("copyCurrentURL:")
        expect(menu.performKeyEquivalent(with: copyEvent(repeating: true)) && target.copyCount == 5,
               "Explicit reset restores native repeated default dispatch")
        let saved = try Data(contentsOf: directory.appendingPathComponent("keyboard-shortcuts.json"))
        surface.viewDidChangeEffectiveAppearance(); controller!.close(); controller = nil
        let savedAfter = try Data(contentsOf: directory.appendingPathComponent("keyboard-shortcuts.json"))
        expect(savedAfter == saved, "Presentation and closure never rewrite bindings")
        window.contentView = nil
        expect(!summary.isAccessibilityElement() && summary.accessibilityParent() == nil
               && summary.accessibilityWindow() == nil && summary.accessibilityFrame().isEmpty,
               "A retained AX element cannot retain or retarget a detached original surface")
        print("Essentials production component: \(assertions) assertions passed")
    }
}
