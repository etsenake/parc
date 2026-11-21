import AppKit
import Testing
@testable import Parc
@testable import ParcCore

struct ShortcutHintPresentationTests {
    @MainActor private final class Window: NSWindow {
        var key = true
        var recordedVisibility = true
        private weak var testParent: NSWindow?
        private var testChildren: [NSWindow] = []
        var testSheet: NSWindow?
        var minimized = false

        override var isKeyWindow: Bool { key }
        override var isVisible: Bool { recordedVisibility }
        override var isMiniaturized: Bool { minimized }
        override var attachedSheet: NSWindow? { testSheet }
        override var childWindows: [NSWindow]? { testChildren }
        override var parent: NSWindow? {
            get { testParent }
            set { testParent = newValue }
        }

        override func addChildWindow(_ childWin: NSWindow, ordered place: NSWindow.OrderingMode) {
            testChildren.append(childWin)
            childWin.parent = self
        }

        override func removeChildWindow(_ childWin: NSWindow) {
            testChildren.removeAll { $0 === childWin }
            childWin.parent = nil
        }

        override func setFrame(_ frameRect: NSRect, display flag: Bool) {
            super.setFrame(frameRect, display: false)
        }

        override func orderOut(_ sender: Any?) { recordedVisibility = false }
    }

    @MainActor private final class Clock {
        private final class Entry {
            let delay: TimeInterval
            let work: @MainActor () -> Void
            var cancelled = false
            init(_ delay: TimeInterval, _ work: @escaping @MainActor () -> Void) {
                self.delay = delay; self.work = work
            }
        }

        private var entries: [Entry] = []
        var clock: ParcToastClock {
            ParcToastClock(repeating: { _, _ in {} }, after: { [weak self] delay, work in
                let entry = Entry(delay, work)
                self?.entries.append(entry)
                return { entry.cancelled = true }
            })
        }

        func fire(_ delay: TimeInterval) {
            let ready = entries.filter { $0.delay == delay }
            entries.removeAll { $0.delay == delay }
            ready.filter { !$0.cancelled }.forEach { $0.work() }
        }
    }

    @MainActor private final class Fixture {
        let parent: Window
        let hint: ShortcutPriorityHintView
        let clock = Clock()

        init(editable: Bool = true, reduceMotion: Bool = false) {
            _ = NSApplication.shared
            parent = Window(contentRect: CGRect(x: 80, y: 80, width: 900, height: 650), styleMask: .borderless,
                            backing: .buffered, defer: false)
            parent.isReleasedWhenClosed = false
            hint = ShortcutPriorityHintView(title: "New Tab", shortcut: "⌘T", canEdit: editable, theme: SpaceTheme(),
                basicBackground: nil, clock: clock.clock, makeWindow: { frame in
                    let child = Window(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
                    child.key = false
                    return child
                }, reduceMotion: { reduceMotion })
        }
    }

    @Test @MainActor func theCueIsPlacedInItsOriginalWindowsScreenFrame() {
        let frame = NSRect(x: 100, y: 200, width: 1000, height: 800)
        #expect(ShortcutPriorityHintView.frame(for: frame) == NSRect(x: 500, y: 400, width: 600, height: 600))
    }

    @Test @MainActor func theCueRetainsTheOriginalParentAndResponder() throws {
        let fixture = Fixture()
        let field = NSTextField()
        fixture.parent.contentView?.addSubview(field)
        _ = fixture.parent.makeFirstResponder(field)
        let original = fixture.parent.firstResponder
        try #require(fixture.hint.present(in: fixture.parent))
        defer { fixture.hint.dismiss(animated: false) }
        let child = try #require(fixture.parent.childWindows?.first)
        #expect(child.parent === fixture.parent)
        #expect(child.contentView === fixture.hint)
        #expect(fixture.parent.firstResponder === original)
        #expect(!fixture.hint.acceptsFirstResponder)
    }

    @Test(arguments: [(false, true, false, false), (true, false, false, false),
                      (true, true, true, false), (true, true, false, true)])
    @MainActor func anUnavailableParentCannotAttachTheCue(key: Bool, recordedVisibility: Bool, minimized: Bool, sheet: Bool) {
        let fixture = Fixture()
        fixture.parent.key = key
        fixture.parent.recordedVisibility = recordedVisibility
        fixture.parent.minimized = minimized
        if sheet { fixture.parent.testSheet = CommandBarTestSupport.borderlessWindow() }
        #expect(!fixture.hint.present(in: fixture.parent))
        #expect(fixture.parent.childWindows?.isEmpty == true)
    }

    @Test @MainActor func aCueCanOnlyBePresentedOnce() throws {
        let fixture = Fixture()
        try #require(fixture.hint.present(in: fixture.parent))
        defer { fixture.hint.dismiss(animated: false) }
        #expect(!fixture.hint.present(in: fixture.parent))
        #expect(fixture.parent.childWindows?.count == 1)
    }

    @Test @MainActor func theEditAccessoryFollowsItsScheduledReveal() throws {
        let fixture = Fixture()
        try #require(fixture.hint.present(in: fixture.parent))
        defer { fixture.hint.dismiss(animated: false) }
        #expect(!fixture.hint.state.showAccessory)
        fixture.clock.fire(ParcToastTiming.accessoryDelay)
        #expect(fixture.hint.state.showAccessory)
    }

    @Test @MainActor func dismissingBeforeRevealCannotReviveTheAccessory() throws {
        let fixture = Fixture()
        try #require(fixture.hint.present(in: fixture.parent))
        fixture.hint.dismiss(animated: false)
        fixture.clock.fire(ParcToastTiming.accessoryDelay)
        #expect(!fixture.hint.state.showAccessory)
        #expect(fixture.hint.originalWindow == nil)
    }

    @Test(arguments: [true, false])
    @MainActor func retiringAlwaysRevokesInputAndHonorsReduceMotion(reduceMotion: Bool) throws {
        let fixture = Fixture(reduceMotion: reduceMotion)
        try #require(fixture.hint.present(in: fixture.parent))
        let original = try #require(fixture.parent.childWindows?.first)
        fixture.hint.dismiss(animated: true)
        #expect(original.ignoresMouseEvents)
        #expect(fixture.hint.isRetiring)
        #expect((original.parent == nil) == reduceMotion)
        fixture.clock.fire(ParcToastTiming.retirement)
        #expect(original.parent == nil)
        #expect(!fixture.hint.present(in: fixture.parent))
    }

    @Test @MainActor func keyLossRetiresTheOriginalCueImmediately() throws {
        let fixture = Fixture()
        try #require(fixture.hint.present(in: fixture.parent))
        fixture.parent.key = false
        NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: fixture.parent)
        #expect(fixture.hint.isRetiring)
        #expect(fixture.parent.childWindows?.isEmpty == true)
    }

    @Test @MainActor func fullscreenConsumesAndRetiresTheOriginalCue() throws {
        let fixture = Fixture()
        try #require(fixture.hint.present(in: fixture.parent))
        var dismissals = 0
        fixture.hint.onDismiss = { dismissals += 1 }
        NotificationCenter.default.post(name: NSWindow.willEnterFullScreenNotification, object: fixture.parent)
        #expect(dismissals == 1)
        #expect(fixture.hint.isRetiring)
        #expect(fixture.parent.childWindows?.isEmpty == true)
    }

    @Test @MainActor func aCommandWithoutAnEditorHasNoEditAccessory() {
        let fixture = Fixture(editable: false)
        #expect(fixture.hint.state.accessory == nil)
    }
}
