import AppKit
import Testing
@testable import Parc
@testable import ParcCore
@testable import ParcKit
@testable import ParcCommandBar

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
            let deadline: TimeInterval
            let work: @MainActor () -> Void
            var cancelled = false
            init(_ deadline: TimeInterval, _ work: @escaping @MainActor () -> Void) {
                self.deadline = deadline; self.work = work
            }
        }

        private var now: TimeInterval = 0
        private var entries: [Entry] = []
        var clock: ParcToastClock {
            ParcToastClock(repeating: { _, _ in {} }, after: { [weak self] delay, work in
                guard let self else { return {} }
                let entry = Entry(now + delay, work)
                entries.append(entry)
                return { entry.cancelled = true }
            })
        }

        func advance(to time: TimeInterval) {
            while let next = entries.min(by: { $0.deadline < $1.deadline }), next.deadline <= time {
                entries.removeAll { $0 === next }
                now = next.deadline
                if !next.cancelled { next.work() }
            }
            now = time
        }
    }

    @MainActor private final class ShowQueue {
        var work: (@MainActor () -> Void)?

        func run() throws {
            let show = try #require(work)
            work = nil
            show()
        }
    }

    @MainActor private final class Fixture {
        let parent: Window
        let hint: ShortcutPriorityHintView
        let clock = Clock()
        let show = ShowQueue()

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
                }, reduceMotion: { reduceMotion }, scheduleShow: { [show] in show.work = $0 })
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
        fixture.clock.advance(to: 0.499)
        #expect(!fixture.hint.state.showAccessory)
        fixture.clock.advance(to: 0.5)
        #expect(fixture.hint.state.showAccessory)
    }

    @Test @MainActor func dismissingBeforeRevealCannotReviveTheAccessory() throws {
        let fixture = Fixture()
        try #require(fixture.hint.present(in: fixture.parent))
        fixture.hint.dismiss(animated: false)
        fixture.clock.advance(to: 0.5)
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
        fixture.clock.advance(to: 1)
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

extension ShortcutHintPresentationTests {
    @Test(arguments: [(0.0, 0.3, true), (0.85, 0.6, false), (1.0, 0.95, false)])
    @MainActor func theCuePaletteAdjustsItsSpaceColorForLegibility(gray: Double, expected: Double, dark: Bool) {
        let color = NSColor(displayP3Red: gray, green: gray, blue: gray, alpha: 1)
        let palette = ParcToastPalette(colors: [color])
        #expect(abs(palette.background.redComponent - expected) < 0.0001)
        #expect(palette.isDark == dark)
        #expect(palette.foreground == (dark ? .white : .black))
    }

    @Test(arguments: [false, true])
    @MainActor func refreshingACueUsesItsCurrentPrivateWindowColor(isPrivate: Bool) throws {
        let fixture = Fixture()
        let basic = NSColor(displayP3Red: 0.054, green: 0.06, blue: 0.075, alpha: 1)
        let theme = SpaceTheme.singleColor(try #require(ThemeColor(hex: "303030")))
        fixture.hint.update(theme: theme, basicBackground: isPrivate ? basic : nil)
        #expect(fixture.hint.state.theme == theme)
        #expect(fixture.hint.state.basicBackground === (isPrivate ? basic : nil))
    }
}

extension ShortcutHintPresentationTests {
    @Test @MainActor func aSaturatedColorKeepsItsHueWhileItsLightnessAdjusts() {
        let palette = ParcToastPalette(colors: [NSColor(displayP3Red: 1, green: 0, blue: 0, alpha: 1)])
        #expect(abs(palette.background.greenComponent - 0.2) < 0.0001)
        #expect(abs(palette.background.blueComponent - 0.2) < 0.0001)
    }

    @Test @MainActor func aGradientAveragesItsAdjustedColors() {
        let palette = ParcToastPalette(colors: [.black, .white])
        #expect(abs(palette.background.redComponent - 0.625) < 0.0001)
    }

    @Test @MainActor func theIncognitoBasicColorReplacesTheSpacesColors() throws {
        let basic = NSColor(displayP3Red: 0.054, green: 0.06, blue: 0.075, alpha: 1)
        let theme = SpaceTheme.singleColor(try #require(ThemeColor(hex: "202020")))
        let incognito = ParcToastPalette(theme: theme, isDark: true, basicBackground: basic)
        #expect(abs(incognito.background.redComponent - 0.1594) < 0.001)
        #expect(abs(incognito.background.greenComponent - 0.2766) < 0.001)
        #expect(abs(incognito.background.blueComponent - 0.5696) < 0.001)
        #expect(incognito.isDark && incognito.foreground == .white)
        let grey = ParcToastPalette(theme: theme, isDark: true)
        #expect(abs(grey.background.redComponent - grey.background.blueComponent) < 0.0001)
    }

    @Test @MainActor func aPrivateWindowsCueStartsOnTheBasicColorAndKeepsItAcrossThemeRefreshes() throws {
        _ = NSApplication.shared
        let basic = NSColor(displayP3Red: 0.054, green: 0.06, blue: 0.075, alpha: 1)
        let cue = ShortcutPriorityHintView(title: "New Tab", shortcut: "⌘T", canEdit: true,
            theme: .singleColor(try #require(ThemeColor(hex: "202020"))), basicBackground: basic)
        #expect(cue.state.basicBackground === basic)
        let next = SpaceTheme.singleColor(try #require(ThemeColor(hex: "303030")))
        cue.update(theme: next, basicBackground: basic)
        #expect(cue.state.basicBackground === basic && cue.state.theme == next)
        cue.update(theme: SpaceTheme(), basicBackground: nil)
        #expect(cue.state.basicBackground == nil)
    }

    @Test @MainActor func thePresentedChildIsPassiveAndFramedOverTheParent() throws {
        let fixture = Fixture()
        try #require(fixture.hint.present(in: fixture.parent))
        defer { fixture.hint.dismiss(animated: false) }
        let child = try #require(fixture.parent.childWindows?.first)
        #expect(fixture.hint.originalWindow === fixture.parent)
        #expect(child.frame == ShortcutPriorityHintView.frame(for: fixture.parent.frame))
        #expect(!child.canBecomeKey && !child.canBecomeMain)
    }

    @Test @MainActor func resizingTheParentKeepsTheHintsOriginalPlacement() throws {
        let fixture = Fixture()
        try #require(fixture.hint.present(in: fixture.parent))
        defer { fixture.hint.dismiss(animated: false) }
        let child = try #require(fixture.parent.childWindows?.first)
        let original = child.frame
        let size = fixture.parent.frame.size
        fixture.parent.setContentSize(NSSize(width: size.width + 100, height: size.height + 50))
        try #require(fixture.parent.frame.size != size)
        #expect(child.frame == original)
    }

    @Test @MainActor func anEmptyHostHasNoInputTarget() throws {
        let fixture = Fixture()
        try #require(fixture.hint.present(in: fixture.parent))
        defer { fixture.hint.dismiss(animated: false) }
        #expect(fixture.hint.accessoryRect.isEmpty)
        #expect(fixture.hint.hitTest(NSPoint(x: 20, y: 400)) == nil)
    }

    @Test @MainActor func theShownHintLaysOutItsSwiftUIBody() throws {
        let fixture = Fixture(reduceMotion: true)
        try #require(fixture.hint.present(in: fixture.parent))
        defer { fixture.hint.dismiss(animated: false) }
        try fixture.show.run()
        fixture.hint.layoutSubtreeIfNeeded()
        #expect(fixture.hint.bodyRect.width > 0)
        #expect(fixture.hint.bodyRect.height >= 42)
    }

    @Test(arguments: [false, true])
    @MainActor func onlyAnEditableHintLaysOutAnAccessoryBelowItsBody(editable: Bool) throws {
        let fixture = Fixture(editable: editable, reduceMotion: true)
        try #require(fixture.hint.present(in: fixture.parent))
        defer { fixture.hint.dismiss(animated: false) }
        try fixture.show.run()
        fixture.clock.advance(to: 0.499)
        fixture.hint.layoutSubtreeIfNeeded()
        #expect(fixture.hint.accessoryRect.isEmpty)
        fixture.clock.advance(to: 0.5)
        fixture.hint.layoutSubtreeIfNeeded()
        try #require(!fixture.hint.bodyRect.isEmpty)
        let accessory = fixture.hint.accessoryRect
        #expect(accessory.isEmpty == !editable)
        if editable { #expect(accessory.minY >= fixture.hint.bodyRect.maxY - 1) }
    }

    @Test @MainActor func aRetiringChildRefusesInput() throws {
        let fixture = Fixture()
        try #require(fixture.hint.present(in: fixture.parent))
        fixture.hint.dismiss(animated: true)
        #expect(fixture.hint.hitTest(NSPoint(x: fixture.hint.bodyRect.midX, y: fixture.hint.bodyRect.midY)) == nil)
    }

    @Test @MainActor func anImmediateDismissalRemovesTheChildAndAnOldCompletionCannotRetireAReplacement() throws {
        let fixture = Fixture()
        try #require(fixture.hint.present(in: fixture.parent))
        let first = try #require(fixture.parent.childWindows?.first)
        defer { fixture.hint.dismiss(animated: false) }
        try fixture.show.run()
        try #require(fixture.hint.state.showing)
        fixture.hint.dismiss(animated: true)
        #expect(!fixture.hint.state.showing)
        let showReplacement = ShowQueue()
        let replacement = ShortcutPriorityHintView(title: "Close Tab", shortcut: "⌘W", canEdit: true, theme: SpaceTheme(),
            basicBackground: nil, clock: fixture.clock.clock, makeWindow: { frame in
                let child = Window(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
                child.key = false
                return child
            }, reduceMotion: { false }, scheduleShow: { showReplacement.work = $0 })
        try #require(replacement.present(in: fixture.parent))
        defer { replacement.dismiss(animated: false) }
        try showReplacement.run()
        fixture.clock.advance(to: 0.999)
        #expect(first.parent === fixture.parent && first.contentView === fixture.hint)
        fixture.clock.advance(to: 1)
        #expect(first.parent == nil && first.contentView == nil && !first.isVisible)
        #expect(replacement.originalWindow === fixture.parent && replacement.window?.parent === fixture.parent)
        #expect(replacement.state.showing)
        replacement.dismiss(animated: false)
        #expect(fixture.parent.childWindows?.isEmpty == true)
        #expect(!replacement.present(in: fixture.parent))
    }

    @Test @MainActor func hidingTheHostConsumesTheCueOnceAndRetiresIt() throws {
        let fixture = Fixture()
        try #require(fixture.hint.present(in: fixture.parent))
        var dismissals = 0
        fixture.hint.onDismiss = { dismissals += 1 }
        fixture.hint.isHidden = true
        #expect(dismissals == 1)
        #expect(fixture.hint.isRetiring && fixture.hint.window == nil)
    }

    @Test @MainActor func detachingTheHostRetiresTheCue() throws {
        let fixture = Fixture()
        try #require(fixture.hint.present(in: fixture.parent))
        fixture.hint.removeFromSuperview()
        #expect(fixture.hint.isRetiring && fixture.hint.window == nil)
    }
}
