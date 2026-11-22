import AppKit
import Testing
@testable import Parc

struct EssentialsTests {
    @MainActor private final class Owner: NSWindow {
        var key = true
        var shown = true
        var testSheet: NSWindow?
        override var isKeyWindow: Bool { key }
        override var isVisible: Bool { shown }
        override var attachedSheet: NSWindow? { testSheet }

        init() {
            super.init(contentRect: NSRect(x: 0, y: 0, width: 475, height: 388), styleMask: .borderless,
                       backing: .buffered, defer: false)
            isReleasedWhenClosed = false
        }
    }

    @MainActor private final class Fixture {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let menu = NSMenu(title: "Commands")
        let registry: KeyboardShortcuts
        let controller: ShortcutEssentialsWindow

        init() throws {
            _ = NSApplication.shared
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let root = menu
            registry = KeyboardShortcuts(mainMenu: { root }, observesKeyboardLayout: false)
            let bindings: [(String, String, NSEvent.ModifierFlags)] = [
                ("newTab:", "t", .command), ("cycleToNextRecentTab:", "\t", .control),
                ("copyCurrentURL:", "c", [.command, .shift]), ("split:", "=", [.control, .shift]),
            ]
            for (id, key, flags) in bindings {
                let item = NSMenuItem(title: id, action: NSSelectorFromString(id), keyEquivalent: key)
                item.keyEquivalentModifierMask = flags
                menu.addItem(item)
                registry.register(item, group: menu.title)
            }
            registry.configure(directory: directory)
            controller = ShortcutEssentialsWindow(shortcuts: registry)
        }

        deinit { try? FileManager.default.removeItem(at: directory) }

        func surface() throws -> NSView { try #require(controller.window?.contentView) }

        func summary() throws -> NSAccessibilityElement {
            try #require(surface().accessibilityChildren()?.compactMap { $0 as? NSAccessibilityElement }.first)
        }

        func cap(for id: String) throws -> ShortcutKeycapView {
            let index = try #require(ShortcutEssentialsWindow.commandIDs.firstIndex(of: id))
            let caps = try surface().subviews.compactMap { $0 as? ShortcutKeycapView }
            try #require(caps.indices.contains(index))
            return caps[index]
        }
    }

    static let commands = ["newTab:", "cycleToNextRecentTab:", "copyCurrentURL:", "split:"]

    @Test(arguments: commands)
    @MainActor func eachLessonShowsItsLiveShortcut(id: String) throws {
        let fixture = try Fixture()
        let cap = try fixture.cap(for: id)
        let expected = try #require(fixture.registry.activeShortcut(for: id)?.spokenDisplay)
        #expect(cap.accessibilityValue() as? String == expected)
        #expect(!cap.acceptsFirstResponder)
    }

    @Test @MainActor func theRecentTabLessonSpellsOutTab() throws {
        let fixture = try Fixture()
        let cap = try fixture.cap(for: "cycleToNextRecentTab:")
        #expect(cap.symbols == ["⌃", "TAB"])
    }

    @Test @MainActor func aChangedShortcutUpdatesTheOpenLessonAndItsInstructions() throws {
        let fixture = try Fixture()
        let cap = try fixture.cap(for: "newTab:")
        let summary = try fixture.summary()
        try fixture.registry.set(KeyboardShortcut(key: " ", flags: .control), for: "newTab:")
        #expect(cap.accessibilityValue() as? String == "⌃Space")
        #expect((summary.accessibilityValue() as? String)?.contains("⌃Space") == true)
    }

    @Test @MainActor func aDisabledShortcutLeavesNoMisleadingInstruction() throws {
        let fixture = try Fixture()
        try fixture.registry.set(nil, for: "newTab:")
        let cap = try fixture.cap(for: "newTab:")
        let summary = try fixture.summary()
        #expect(cap.isHidden)
        #expect((summary.accessibilityValue() as? String)?.contains("Open a New Tab") == false)
    }

    @Test @MainActor func conflictingShortcutsDisappearFromTheLesson() throws {
        let fixture = try Fixture()
        let chord = try #require(fixture.registry.activeShortcut(for: "copyCurrentURL:"))
        try fixture.registry.set(chord, for: "newTab:")
        let newTab = try fixture.cap(for: "newTab:")
        let copy = try fixture.cap(for: "copyCurrentURL:")
        #expect(newTab.isHidden && copy.isHidden)
    }

    @Test @MainActor func theInstructionSummaryIsPassive() throws {
        let fixture = try Fixture()
        let summary = try fixture.summary()
        #expect(summary.accessibilityRole() == .staticText)
        #expect(summary.accessibilityChildren()?.isEmpty == true)
        #expect(!summary.accessibilityPerformPress())
    }

    @Test(arguments: [(false, false, true, EssentialsCopyRoute.unavailable), (true, false, true, .commandWindow),
                      (true, true, true, .currentURL), (true, false, false, .currentURL)])
    func theCopyRouteUsesTheOriginalAddressSource(url: Bool, bar: Bool, page: Bool, expected: EssentialsCopyRoute) {
        #expect(EssentialsCopyRoute(hasURL: url, commandBarOpen: bar, hasNativePage: page) == expected)
    }

    @Test(arguments: commands, [true, false])
    @MainActor func anEssentialsCommandRequiresTheSameWindowAdmission(id: String, admitted: Bool) {
        _ = NSApplication.shared
        let registry = KeyboardShortcuts(mainMenu: { nil }, observesKeyboardLayout: false)
        let controller = ShortcutEssentialsWindow(shortcuts: registry)
        let original = Owner()
        controller.window = original
        controller.isOwnerAvailable = { admitted }
        var invoked: [String] = []
        controller.onCommand = { invoked.append($0); _ = $1 }
        #expect(controller.canActivateCommand(id) == admitted)
        #expect(controller.activateCommand(id) == admitted)
        #expect(invoked == (admitted ? [id] : []))
    }

    @Test(arguments: [true, false])
    @MainActor func copyChecksItsCommandWindowCapabilityAfterItOwnsThePresentation(canCopy: Bool) {
        _ = NSApplication.shared
        let controller = ShortcutEssentialsWindow(shortcuts: KeyboardShortcuts(mainMenu: { nil }, observesKeyboardLayout: false))
        let original = Owner()
        controller.window = original
        var checks: [String] = []
        controller.isOwnerAvailable = { true }
        controller.canPerformCommand = { checks.append($0); return canCopy }
        #expect(controller.activateCommand("copyCurrentURL:") == canCopy)
        #expect(checks == ["copyCurrentURL:"])
    }

    @MainActor private final class CopyTarget: NSObject {
        var copyCount = 0
        @objc func copyCurrentURL(_ sender: NSMenuItem) { copyCount += 1 }
    }

    private func chordEvent(repeating: Bool, flags: NSEvent.ModifierFlags = [.command, .shift],
                            key: String = "c", code: UInt16 = 8) throws -> NSEvent {
        try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags,
            timestamp: 1, windowNumber: 0, context: nil,
            characters: flags.contains(.shift) ? key.uppercased() : key,
            charactersIgnoringModifiers: key, isARepeat: repeating, keyCode: code))
    }

    private func fields(_ surface: NSView) -> [NSTextField] { surface.subviews.compactMap { $0 as? NSTextField } }

    @Test @MainActor func theWindowKeepsItsFloatingTransparentFixedSizeComposition() throws {
        let fixture = try Fixture()
        let window = try #require(fixture.controller.window)
        #expect(window.level == .floating)
        #expect(window.collectionBehavior.contains(.fullScreenAuxiliary))
        #expect(window.styleMask.contains(.fullSizeContentView) && window.styleMask.contains(.closable))
        #expect(!window.isOpaque && window.titleVisibility == .hidden && window.titlebarAppearsTransparent)
        #expect(window.isMovableByWindowBackground && !window.isReleasedWhenClosed)
        #expect(window.frame.size == NSSize(width: 475, height: 388))
    }

    @Test @MainActor func theWindowSitsInTheParentsTopRightInset() throws {
        let fixture = try Fixture()
        let window = try #require(fixture.controller.window)
        #expect(ShortcutEssentialsWindow.origin(parent: NSRect(x: 100, y: 50, width: 1200, height: 800),
                                                education: window.frame.size) == NSPoint(x: 815, y: 452))
    }

    @Test @MainActor func theHeadlineAndRowsUseTheRecoveredTypeStyle() throws {
        let fixture = try Fixture()
        let surface = try fixture.surface()
        let headline = try #require(fields(surface).first { $0.stringValue == "Essential Keyboard Shortcuts" })
        #expect(headline.font?.pointSize == 20)
        #expect(headline.attributedStringValue.attribute(.kern, at: 0, effectiveRange: nil) as? Double == -0.8)
        #expect(fields(surface).filter { $0.font?.pointSize == 15 }.count == 4)
        #expect(surface.subviews.compactMap { $0 as? NSBox }.count == 3)
        #expect(try #require(surface.subviews.compactMap { $0 as? EssentialsViewAllControl }.first).superview === surface)
    }

    @Test @MainActor func eachIncludedCommandHasANamedAccessibleBinding() throws {
        let fixture = try Fixture()
        let caps = try fixture.surface().subviews.filter { $0.accessibilityLabel()?.hasSuffix(" shortcut") == true }
        #expect(caps.count == 4)
    }

    @Test @MainActor func theInstructionSummaryIsOneOrderedElementOwnedByTheSurface() throws {
        let fixture = try Fixture()
        let surface = try fixture.surface()
        let window = try #require(fixture.controller.window)
        let summary = try fixture.summary()
        #expect(summary.accessibilityParent() as? NSView === surface)
        #expect(summary.accessibilityWindow() as? NSWindow === window)
        let value = try #require(summary.accessibilityValue() as? String)
        #expect(value.hasPrefix("Open a New Tab "))
        #expect(!value.contains("without trackers"))
        for id in ShortcutEssentialsWindow.commandIDs {
            #expect(value.contains(try #require(fixture.registry.activeShortcut(for: id)).spokenDisplay))
        }
    }

    @Test @MainActor func accessibilityHitTestingReturnsTheInstructionGroup() throws {
        let fixture = try Fixture()
        let surface = try fixture.surface()
        let summary = try fixture.summary()
        let frame = summary.accessibilityFrame()
        #expect(!frame.isEmpty)
        #expect(surface.accessibilityHitTest(NSPoint(x: frame.midX, y: frame.midY)) as? NSAccessibilityElement === summary)
    }

    @Test @MainActor func resolvingAConflictRestoresTheHiddenRowsAndTheInstructions() throws {
        let fixture = try Fixture()
        let summary = try fixture.summary()
        let custom = KeyboardShortcut(key: "k", flags: [.command, .control])
        try fixture.registry.set(custom, for: "newTab:")
        try fixture.registry.set(custom, for: "copyCurrentURL:")
        let value = try #require(summary.accessibilityValue() as? String)
        #expect(!value.contains("Open a New Tab") && !value.contains("Copy Page URL"))
        try fixture.registry.reset("copyCurrentURL:")
        let newTab = try fixture.cap(for: "newTab:")
        let copy = try fixture.cap(for: "copyCurrentURL:")
        #expect(!newTab.isHidden && !copy.isHidden)
        #expect(newTab.accessibilityValue() as? String == custom.spokenDisplay)
    }

    @Test @MainActor func aDisabledRowHidesItsDescriptionAndClosesTheGap() throws {
        let fixture = try Fixture()
        let surface = try fixture.surface()
        try fixture.registry.set(nil, for: "newTab:")
        #expect(fields(surface).first { $0.stringValue == "Open a New Tab" }?.isHidden == true)
        #expect(fields(surface).first { $0.stringValue == "Switch to a Recent Tab" }?.frame.minY == 102)
    }

    @Test @MainActor func aLongBindingKeepsTheRightEdgeAndExpands() throws {
        let fixture = try Fixture()
        let surface = try fixture.surface()
        let wide = KeyboardShortcut(key: "k", flags: [.control, .option, .shift, .command])
        try fixture.registry.set(wide, for: "newTab:")
        let cap = try fixture.cap(for: "newTab:")
        surface.layoutSubtreeIfNeeded()
        cap.layoutSubtreeIfNeeded()
        #expect(cap.frame.maxX == 445 && cap.frame.width > 103)
        #expect(!cap.acceptsFirstResponder && cap.hitTest(.zero) == nil)
        #expect(cap.accessibilityValue() as? String == wide.spokenDisplay)
        try fixture.registry.reset("newTab:")
        #expect(cap.accessibilityValue() as? String == fixture.registry.shortcut(for: "newTab:")?.spokenDisplay)
    }

    @Test @MainActor func bindingUpdatesNeverClaimKeyboardFocusOrReplaceTheElement() throws {
        let fixture = try Fixture()
        let window = try #require(fixture.controller.window)
        let summary = try fixture.summary()
        let responder = window.firstResponder
        try fixture.registry.set(KeyboardShortcut(key: " ", flags: .control), for: "newTab:")
        try fixture.registry.reset("newTab:")
        #expect(window.firstResponder === responder)
        #expect(try fixture.surface().accessibilityChildren()?.contains { ($0 as? NSAccessibilityElement) === summary } == true)
    }

    @Test @MainActor func noActiveBindingsRemoveTheInstructionElementUntilReset() throws {
        let fixture = try Fixture()
        let surface = try fixture.surface()
        let summary = try fixture.summary()
        for id in ShortcutEssentialsWindow.commandIDs { try fixture.registry.set(nil, for: id) }
        #expect(!summary.isAccessibilityElement() && summary.accessibilityValue() == nil && summary.accessibilityFrame().isEmpty)
        #expect(surface.accessibilityChildren()?.contains { ($0 as? NSAccessibilityElement) === summary } == false)
        for id in ShortcutEssentialsWindow.commandIDs { try fixture.registry.reset(id) }
        #expect(summary.isAccessibilityElement())
        #expect((summary.accessibilityValue() as? String)?.hasPrefix("Open a New Tab") == true)
    }

    @Test @MainActor func aHiddenSurfaceLeavesNoAccessibleInstructionTree() throws {
        let fixture = try Fixture()
        let surface = try fixture.surface()
        let summary = try fixture.summary()
        surface.isHidden = true
        #expect(!summary.isAccessibilityElement() && summary.accessibilityWindow() == nil)
    }

    @Test @MainActor func aDetachedSurfaceLeavesNoRetainedAccessibilityTarget() throws {
        let fixture = try Fixture()
        let summary = try fixture.summary()
        fixture.controller.window?.contentView = nil
        #expect(!summary.isAccessibilityElement() && summary.accessibilityParent() == nil)
        #expect(summary.accessibilityWindow() == nil && summary.accessibilityFrame().isEmpty)
    }

    @Test @MainActor func theSurfaceFollowsTheAppearanceResources() throws {
        let fixture = try Fixture()
        let surface = try fixture.surface()
        let detail = try #require(fields(surface).first { $0.font?.pointSize == 12 })
        let headline = try #require(fields(surface).first { $0.stringValue == "Essential Keyboard Shortcuts" })
        surface.appearance = NSAppearance(named: .darkAqua)
        surface.viewDidChangeEffectiveAppearance()
        surface.updateLayer()
        let background = try #require(NSColor(cgColor: try #require(surface.layer?.backgroundColor))?.usingColorSpace(.sRGB))
        #expect(abs(background.redComponent - 21 / 255) < 0.0001 && abs(background.blueComponent - 48 / 255) < 0.0001)
        let dark = try #require(detail.textColor?.usingColorSpace(.sRGB))
        #expect(abs(dark.redComponent - 238 / 255) < 0.0001 && dark.alphaComponent == 0.75)
        surface.appearance = NSAppearance(named: .aqua)
        surface.viewDidChangeEffectiveAppearance()
        surface.updateLayer()
        let light = try #require(detail.textColor?.usingColorSpace(.sRGB))
        #expect(abs(light.redComponent - 6 / 255) < 0.0001 && light.alphaComponent == 0.75)
        #expect(try #require(headline.textColor?.usingColorSpace(.sRGB)).blueComponent == 0.17)
    }

    @Test @MainActor func aPresentationWithoutItsOwnerCannotRetargetItsParentOrSettings() throws {
        let fixture = try Fixture()
        let window = try #require(fixture.controller.window)
        let button = try #require(fixture.surface().subviews.compactMap { $0 as? EssentialsViewAllControl }.first)
        var commands = 0, settings = 0, escapes = 0
        fixture.controller.onCommand = { _, _ in commands += 1 }
        fixture.controller.onEscape = { escapes += 1 }
        fixture.controller.onViewAll = { settings += 1 }
        fixture.controller.isOwnerAvailable = { true }
        #expect(!fixture.controller.activateCommand("newTab:"))
        window.cancelOperation(nil)
        button.rootView.onPress()
        #expect(commands == 0 && settings == 0 && escapes == 0)
    }

    @Test @MainActor func aLostOwnerRefusesAvailabilityAndUnknownCommandsNeverEnterDispatch() throws {
        let fixture = try Fixture()
        fixture.controller.isOwnerAvailable = { false }
        #expect(!fixture.controller.canActivateCommand("newTab:"))
        #expect(!fixture.controller.activateCommand("unknown:"))
    }

    @Test @MainActor func nativeDeliveryInvokesTheCopyItemOncePerInitialAndRepeatedChord() throws {
        let fixture = try Fixture()
        let target = CopyTarget()
        fixture.menu.items[2].target = target
        for repeated in [false, true, true] {
            #expect(fixture.menu.performKeyEquivalent(with: try chordEvent(repeating: repeated)))
        }
        #expect(target.copyCount == 3)
    }

    @Test @MainActor func repeatedNativeDeliveryFollowsDisableCustomizeAndReset() throws {
        let fixture = try Fixture()
        let target = CopyTarget()
        fixture.menu.items[2].target = target
        try fixture.registry.set(nil, for: "copyCurrentURL:")
        #expect(!fixture.menu.performKeyEquivalent(with: try chordEvent(repeating: true)))
        #expect(target.copyCount == 0)
        try fixture.registry.set(KeyboardShortcut(key: "k", flags: [.command, .option]), for: "copyCurrentURL:")
        #expect(!fixture.menu.performKeyEquivalent(with: try chordEvent(repeating: true)))
        #expect(fixture.menu.performKeyEquivalent(
            with: try chordEvent(repeating: true, flags: [.command, .option], key: "k", code: 40)))
        #expect(target.copyCount == 1)
        try fixture.registry.reset("copyCurrentURL:")
        #expect(fixture.menu.performKeyEquivalent(with: try chordEvent(repeating: true)))
        #expect(target.copyCount == 2)
    }

    @Test @MainActor func presentingAndClosingNeverRewriteTheBindings() throws {
        let fixture = try Fixture()
        try fixture.registry.set(KeyboardShortcut(key: "k", flags: [.command, .control]), for: "newTab:")
        let file = fixture.directory.appendingPathComponent("keyboard-shortcuts.json")
        let saved = try Data(contentsOf: file)
        try fixture.surface().viewDidChangeEffectiveAppearance()
        fixture.controller.close()
        #expect(try Data(contentsOf: file) == saved)
    }
}
