import AppKit
import ParcCore
import ParcTestSupport
import Testing
@testable import Parc
@testable import ParcKit
@testable import ParcCommandBar

struct LiveBindingTests {
    @MainActor private final class Fixture {
        let menu = NSMenu(title: "View")
        let registry: KeyboardShortcuts
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let copyDefault = KeyboardShortcut(key: "c", flags: [.command, .shift])

        init() throws {
            _ = NSApplication.shared
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let root = menu
            registry = KeyboardShortcuts(mainMenu: { root }, observesKeyboardLayout: false)
            register("toggleSidebar:", chord: KeyboardShortcut(key: "s", flags: .command))
            register("copyCurrentURL:", chord: copyDefault)
            registry.configure(directory: directory)
        }

        deinit { try? FileManager.default.removeItem(at: directory) }

        func register(_ id: String, chord: KeyboardShortcut) {
            let item = NSMenuItem(title: id, action: NSSelectorFromString(id), keyEquivalent: chord.key)
            item.keyEquivalentModifierMask = chord.flags
            menu.addItem(item)
            registry.register(item, group: "View")
        }

        func copyItem() -> NSMenuItem {
            let item = NSMenuItem(title: "Copy URL", action: nil, keyEquivalent: "")
            registry.showBinding(on: item, for: "copyCurrentURL:")
            return item
        }
    }

    @Test @MainActor func accessibilityHelpUsesTheLatestTitleAndSpokenKey() throws {
        let fixture = try Fixture()
        let toggle = NSButton()
        fixture.registry.bindHelp(toggle, title: "Hide sidebar", commandID: "toggleSidebar:")
        fixture.registry.bindHelp(toggle, title: "Lock sidebar", commandID: "toggleSidebar:")
        try fixture.registry.set(KeyboardShortcut(key: " ", flags: [.control, .command]), for: "toggleSidebar:")
        #expect(toggle.accessibilityHelp() == "Lock sidebar ⌃⌘Space")
        #expect(toggle.cell?.accessibilityHelp() == toggle.accessibilityHelp())
        #expect(toggle.toolTip == nil)
    }

    @Test(arguments: [false, true])
    @MainActor func disabledHelpIsShownOnlyWhenItDoesNotRequireABinding(requiresBinding: Bool) throws {
        let fixture = try Fixture()
        let button = NSButton()
        fixture.registry.bindHelp(button, title: "Copy URL", commandID: "copyCurrentURL:", requiresBinding: requiresBinding)
        try fixture.registry.set(nil, for: "copyCurrentURL:")
        #expect(button.accessibilityHelp() == (requiresBinding ? nil : "Copy URL"))
    }

    @Test @MainActor func retainedMenuItemsRemoveConflictsAndRestoreTheBinding() throws {
        let fixture = try Fixture()
        let item = fixture.copyItem()
        try fixture.registry.set(fixture.copyDefault, for: "toggleSidebar:")
        #expect(item.keyEquivalent.isEmpty)
        try fixture.registry.reset("toggleSidebar:")
        #expect(item.keyEquivalent == fixture.copyDefault.key)
    }

    @Test @MainActor func theDiscoveryCallbackSeesTheCommittedMenuBinding() throws {
        let fixture = try Fixture()
        let item = fixture.copyItem()
        var discovered: String?
        fixture.registry.onDiscoveryChange = { discovered = item.keyEquivalent }
        try fixture.registry.set(KeyboardShortcut(key: "y", flags: [.command, .shift]), for: "copyCurrentURL:")
        #expect(discovered == "y")
    }

    @Test @MainActor func bindingHelpDoesNotRetainItsMenuItem() throws {
        let fixture = try Fixture()
        weak var released: NSMenuItem?
        do {
            let item = fixture.copyItem()
            released = item
            #expect(item.keyEquivalent == fixture.copyDefault.key)
        }
        #expect(released == nil)
    }

    @Test @MainActor func aRetiredCommandKeepsItsSavedChordUntilReregistered() throws {
        let fixture = try Fixture()
        let item = fixture.copyItem()
        let chord = KeyboardShortcut(key: "y", flags: [.command, .shift])
        try fixture.registry.set(chord, for: "copyCurrentURL:")
        fixture.registry.retireCommands(["copyCurrentURL:"])
        #expect(fixture.registry.shortcut(for: "copyCurrentURL:") == chord)
        #expect(item.keyEquivalent.isEmpty)
        fixture.register("copyCurrentURL:", chord: fixture.copyDefault)
        #expect(item.keyEquivalent == chord.key)
    }
}

extension LiveBindingTests {
    @MainActor private final class ToastParent: NSWindow {
        private var children: [NSWindow] = []
        var recordedVisibility = true

        override var isKeyWindow: Bool { true }
        override var isVisible: Bool { recordedVisibility }
        override var childWindows: [NSWindow]? { children }

        override func addChildWindow(_ childWin: NSWindow, ordered place: NSWindow.OrderingMode) {
            children.append(childWin)
            childWin.parent = self
        }

        override func removeChildWindow(_ childWin: NSWindow) {
            children.removeAll { $0 === childWin }
            childWin.parent = nil
        }
    }

    @MainActor private final class ToastChild: ParcToastWindow {
        private weak var owner: NSWindow?

        override var isVisible: Bool { owner != nil }
        override var parent: NSWindow? {
            get { owner }
            set { owner = newValue }
        }

        override func setFrame(_ frameRect: NSRect, display flag: Bool) {
            super.setFrame(frameRect, display: false)
        }
    }

    @MainActor private struct ToastFixture {
        let parent: ToastParent
        let anchor = NSView(frame: NSRect(x: 20, y: 10, width: 260, height: 160))
        let presenter = ParcToastPresenter(clock: ParcToastClock(repeating: { _, _ in {} }, after: { _, _ in {} }),
                                           present: { toast, parent, anchor in
            toast.present(in: parent, over: anchor, makeWindow: {
                ToastChild(contentRect: $0, styleMask: .borderless, backing: .buffered, defer: true)
            })
        })

        init() {
            parent = ToastParent(contentRect: NSRect(x: 100, y: 100, width: 300, height: 200),
                                 styleMask: .borderless, backing: .buffered, defer: true)
            parent.isReleasedWhenClosed = false
            parent.contentView?.addSubview(anchor)
        }

        func showUpsell() -> ParcToastPresentation? {
            presenter.show(.superCopyUpsell(shortcut: "⇧⌘C", message: "Copy links faster by pressing ⇧⌘C"),
                           in: parent, over: anchor, theme: SpaceTheme())
        }
    }

    @Test @MainActor func theCopyUpsellAttachesToItsOriginalWindow() throws {
        _ = NSApplication.shared
        let fixture = ToastFixture()
        defer { fixture.presenter.dismiss(animated: false) }
        let toast = try #require(fixture.showUpsell())
        let children = try #require(fixture.parent.childWindows)
        try #require(children.count == 1)
        #expect(children[0].parent === fixture.parent)
        #expect(children[0].contentView === toast)
    }

    @Test @MainActor func aHiddenWindowCannotAttachTheCopyUpsell() {
        _ = NSApplication.shared
        let fixture = ToastFixture()
        fixture.parent.recordedVisibility = false
        defer { fixture.presenter.dismiss(animated: false) }
        #expect(fixture.showUpsell() == nil)
        #expect(fixture.parent.childWindows?.isEmpty == true)
    }

    @Test @MainActor func theCopyUpsellPreservesTheWindowsFieldEditor() throws {
        _ = NSApplication.shared
        let fixture = ToastFixture()
        defer { fixture.presenter.dismiss(animated: false) }
        let field = NSTextField(string: "https://example.test/")
        fixture.anchor.addSubview(field)
        try #require(fixture.parent.makeFirstResponder(field))
        let fieldEditor = try #require(field.currentEditor())
        try #require(fixture.showUpsell() != nil)
        #expect(fixture.parent.firstResponder === fieldEditor)
    }
}

extension LiveBindingTests {
    @MainActor private final class PeekWindow: NSWindow {
        var key = true
        override var isKeyWindow: Bool { key }
        override var isVisible: Bool { true }
    }

    @Test(arguments: [(false, true), (true, false), (true, true)])
    @MainActor func onlyTheOriginalKeyPeekCanBeOpened(current: Bool, key: Bool) {
        _ = NSApplication.shared
        let window = PeekWindow(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
                                styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.key = key
        var promotions = 0
        let command = PeekOpenCommand(window: window, targetIsAvailable: { current }, execute: { promotions += 1 })
        #expect(command.perform() == (current && key))
        #expect(!command.perform())
        #expect(promotions == (current && key ? 1 : 0))
    }

    enum Copy: CaseIterable { case address, selectedText, noPage, noBinding }

    @Test(arguments: Copy.allCases)
    func theCopyCueRequiresTheCurrentPagesExactURLAndAnActiveChord(copy: Copy) throws {
        let defaults = try #require(TestDefaults("Parc.LiveBinding."))
        let upsell = SuperCopyUpsell(defaults: defaults)
        let url = "https://example.test/a?b=1"
        let chord = KeyboardShortcut(key: "c", flags: [.command, .shift])
        let message = upsell.message(copied: copy == .selectedText ? "example" : url,
                                    pageURL: copy == .noPage ? nil : url, shortcut: copy == .noBinding ? nil : chord,
                                    now: .distantPast)
        #expect(message == (copy == .address ? "Copy links faster by pressing ⇧⌘C" : nil))
    }

    @Test(arguments: [(1, false), (2, true)])
    func theCopyCueUsesCalendarDaysForItsCooldown(days: Int, offers: Bool) throws {
        let defaults = try #require(TestDefaults("Parc.LiveBinding."))
        var upsell = SuperCopyUpsell(defaults: defaults)
        upsell.calendar = Calendar(identifier: .gregorian)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let later = try #require(upsell.calendar.date(byAdding: .day, value: days, to: now))
        let address = "https://example.test/"
        let chord = KeyboardShortcut(key: "c", flags: [.command, .shift])
        upsell.recordShown(now: now)
        #expect((upsell.message(copied: address, pageURL: address, shortcut: chord, now: later) != nil) == offers)
    }
}

extension LiveBindingTests {
    @MainActor private final class PeekTarget: NSObject, NSMenuItemValidation {
        var enabled = false
        func validateMenuItem(_ item: NSMenuItem) -> Bool { enabled }
        @objc func openInCurrentSpace(_ sender: NSMenuItem) {}
    }

    @MainActor private final class PeekBench {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let root = NSMenu()
        let menu = NSMenu(title: "Tabs")
        let target = PeekTarget()
        let open = NSMenuItem(title: "Open Peek in Current Space", action: #selector(PeekTarget.openInCurrentSpace), keyEquivalent: "")
        let registry: KeyboardShortcuts
        let chord = KeyboardShortcut(key: "o", flags: .command)

        init() throws {
            _ = NSApplication.shared
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let parent = NSMenuItem()
            parent.submenu = menu
            root.addItem(parent)
            let root = root
            registry = KeyboardShortcuts(mainMenu: { root }, observesKeyboardLayout: false)
            open.target = target
            open.isHidden = true
            open.allowsKeyEquivalentWhenHidden = true
            menu.addItem(open)
            registry.configure(directory: directory)
            registry.register(open, group: "Tabs", discoverable: false)
        }

        deinit { try? FileManager.default.removeItem(at: directory) }

        var event: NSEvent { CommandBarTestSupport.keyEvent(31, .command, characters: "o") }

        func writeSettings(_ overrides: [String: Any]) throws -> URL {
            let file = directory.appendingPathComponent("keyboard-shortcuts.json")
            try JSONSerialization.data(withJSONObject: ["version": 3, "overrides": overrides]).write(to: file)
            return file
        }
    }

    @MainActor private func help(_ button: NSButton) -> String? {
        #expect(button.toolTip == nil)
        #expect(button.cell?.accessibilityHelp() == button.accessibilityHelp())
        return button.accessibilityHelp()
    }

    @Test @MainActor func aTooltipAppendsTheBindingWhenThereIsOne() {
        #expect(KeyboardShortcuts.toolTip("Hide sidebar", shortcut: KeyboardShortcut(key: "s", flags: .command)) == "Hide sidebar ⌘S")
        #expect(KeyboardShortcuts.toolTip("Hide sidebar", shortcut: nil) == "Hide sidebar")
    }

    @Test @MainActor func anUnregisteredCommandShowsItsTitleAlone() throws {
        let fixture = try Fixture()
        #expect(fixture.registry.toolTip("Go back", for: "goBack:") == "Go back")
    }

    @Test @MainActor func initialHelpCarriesTheLiveBindingOrNone() throws {
        let fixture = try Fixture()
        fixture.register("resetTab:", chord: KeyboardShortcut(key: "r", flags: [.command, .shift]))
        let toggle = NSButton(), reset = NSButton(), plain = NSButton()
        fixture.registry.bindHelp(toggle, title: "Hide sidebar", commandID: "toggleSidebar:")
        fixture.registry.bindHelp(reset, title: "Reset Tab", commandID: "resetTab:", requiresBinding: true)
        fixture.registry.bindHelp(plain, title: "Site Control Center", commandID: nil)
        #expect(help(toggle) == "Hide sidebar ⌘S")
        #expect(help(reset) == "Reset Tab ⇧⌘R")
        #expect(help(plain) == "Site Control Center")
    }

    @Test @MainActor func aChangedClearedAndResetBindingFollowsIntoTheHelp() throws {
        let fixture = try Fixture()
        fixture.register("resetTab:", chord: KeyboardShortcut(key: "r", flags: [.command, .shift]))
        let toggle = NSButton(), reset = NSButton()
        fixture.registry.bindHelp(toggle, title: "Hide sidebar", commandID: "toggleSidebar:")
        fixture.registry.bindHelp(reset, title: "Reset Tab", commandID: "resetTab:", requiresBinding: true)
        try fixture.registry.set(KeyboardShortcut(key: "b", flags: [.command, .option]), for: "toggleSidebar:")
        #expect(help(toggle) == "Hide sidebar ⌥⌘B")
        try fixture.registry.set(nil, for: "resetTab:")
        #expect(help(reset) == nil)
        try fixture.registry.reset("resetTab:")
        #expect(help(reset) == "Reset Tab ⇧⌘R")
    }

    @Test @MainActor func aConflictingBindingIsNotAdvertisedUntilResolved() throws {
        let fixture = try Fixture()
        let toggle = NSButton()
        fixture.registry.bindHelp(toggle, title: "Hide sidebar", commandID: "toggleSidebar:")
        try fixture.registry.set(fixture.copyDefault, for: "toggleSidebar:")
        #expect(help(toggle) == "Hide sidebar")
        try fixture.registry.reset("toggleSidebar:")
        #expect(help(toggle) == "Hide sidebar ⌘S")
    }

    @Test @MainActor func aMenuEntryShowsTheBindingHidesItWhenClearedAndRestoresIt() throws {
        let fixture = try Fixture()
        let item = fixture.copyItem()
        #expect(item.keyEquivalent == "c" && item.keyEquivalentModifierMask == [.command, .shift])
        try fixture.registry.set(nil, for: "copyCurrentURL:")
        #expect(item.keyEquivalent.isEmpty && item.keyEquivalentModifierMask.isEmpty)
        try fixture.registry.reset("copyCurrentURL:")
        #expect(item.keyEquivalent == "c")
    }

    @Test @MainActor func reregisteringARetiredCommandRestoresTheSavedBindingAndRetainedMenu() throws {
        let fixture = try Fixture()
        let item = fixture.copyItem()
        let custom = KeyboardShortcut(key: "y", flags: [.command, .shift])
        try fixture.registry.set(custom, for: "copyCurrentURL:")
        fixture.registry.retireCommands(["copyCurrentURL:"])
        #expect(fixture.registry.activeShortcut(for: "copyCurrentURL:") == nil)
        fixture.register("copyCurrentURL:", chord: fixture.copyDefault)
        #expect(fixture.registry.activeShortcut(for: "copyCurrentURL:") == custom)
        #expect(item.keyEquivalent == "y")
    }

    @Test @MainActor func aReleasedViewLeavesOtherBindingsAlone() throws {
        let fixture = try Fixture()
        fixture.register("reload:", chord: KeyboardShortcut(key: "r", flags: .command))
        let toggle = NSButton()
        fixture.registry.bindHelp(toggle, title: "Lock sidebar", commandID: "toggleSidebar:")
        do {
            let transient = NSButton()
            fixture.registry.bindHelp(transient, title: "Reload this page", commandID: "reload:")
            #expect(help(transient) == "Reload this page ⌘R")
        }
        try fixture.registry.set(KeyboardShortcut(key: "r", flags: [.command, .option]), for: "reload:")
        #expect(help(toggle) == "Lock sidebar ⌘S")
    }

    @Test @MainActor func peeksDefaultSurvivesAnInitiallyHiddenMenuAndKeepsItsPriority() throws {
        let bench = try PeekBench()
        #expect(bench.registry.activeShortcut(for: "openInCurrentSpace:") == bench.chord)
        #expect(bench.open.keyEquivalent == "o")
        #expect(bench.registry.priority(for: "openInCurrentSpace:") == .useBoth)
    }

    @Test(arguments: [false, true])
    @MainActor func theHiddenPeekEntryRevalidatesAgainstTheModal(available: Bool) throws {
        let bench = try PeekBench()
        bench.target.enabled = available
        let command = bench.registry.nativeCommand(for: bench.event, editable: true)
        #expect((command?.item === bench.open) == available)
        #expect(available || command == nil)
    }

    @Test @MainActor func removingPeeksBindingClearsTheMenuAndExpandHintAndResetRestoresThem() throws {
        let bench = try PeekBench()
        let expand = NSButton()
        bench.registry.bindHelp(expand, title: "Open Peek as Tab", commandID: "openInCurrentSpace:")
        try bench.registry.set(nil, for: "openInCurrentSpace:")
        #expect(help(expand) == "Open Peek as Tab")
        #expect(bench.open.keyEquivalent.isEmpty)
        try bench.registry.reset("openInCurrentSpace:")
        #expect(help(expand) == "Open Peek as Tab ⌘O")
    }

    @Test @MainActor func peeksNewDefaultNeverStealsASavedChordAndMigratesIndependently() throws {
        let bench = try PeekBench()
        let file = try bench.writeSettings(["other:": ["shortcut": ["key": "o", "modifiers": NSEvent.ModifierFlags.command.rawValue]]])
        bench.registry.configure(directory: bench.directory)
        #expect(bench.registry.activeShortcut(for: "openInCurrentSpace:") == nil)
        #expect(bench.registry.shortcut(for: "other:") == bench.chord)
        let migrated = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        #expect(migrated["peekOpenShortcutDefaults"] as? Int == 1)
    }

    @Test @MainActor func peeksSavedDisableAndCustomChordSurviveIntroduction() throws {
        let bench = try PeekBench()
        _ = try bench.writeSettings(["openInCurrentSpace:": [:]])
        bench.registry.configure(directory: bench.directory)
        #expect(bench.registry.activeShortcut(for: "openInCurrentSpace:") == nil)
        let flags = NSEvent.ModifierFlags([.command, .shift])
        _ = try bench.writeSettings(["openInCurrentSpace:": ["shortcut": ["key": "o", "modifiers": flags.rawValue]]])
        bench.registry.configure(directory: bench.directory)
        #expect(bench.registry.activeShortcut(for: "openInCurrentSpace:") == .init(key: "o", flags: flags))
    }

    @Test @MainActor func untouchedOldSettingsReceiveThePeekDefaultAndPriority() throws {
        let bench = try PeekBench()
        _ = try bench.writeSettings([:])
        bench.registry.configure(directory: bench.directory)
        #expect(bench.registry.activeShortcut(for: "openInCurrentSpace:") == bench.chord)
        #expect(bench.registry.priority(for: "openInCurrentSpace:") == .useBoth)
    }

    @Test @MainActor func theOriginalPeekTargetIsAdmitted() {
        _ = NSApplication.shared
        let window = PeekWindow(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
                                styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let command = PeekOpenCommand(window: window, targetIsAvailable: { true }, execute: {})
        #expect(command.isAvailable)
    }

    @Test func theUpsellToastIsShortcutContentWithItsOwnText() {
        let toast = ParcToastContent.superCopyUpsell(shortcut: "⇧⌘C", message: "Copy links faster by pressing ⇧⌘C")
        #expect(toast.body == .shortcut(leading: SuperCopyUpsell.prefix, shortcut: "⇧⌘C", trailing: nil))
        #expect(toast.showsShortcut)
    }
}
