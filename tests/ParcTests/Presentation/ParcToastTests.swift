import AppKit
import Testing
import ParcCore
@testable import Parc

struct ParcToastTests {
    @MainActor private final class Clock {
        var tick: (@MainActor () -> Void)?
        var interval: TimeInterval?
        var delayed: [@MainActor () -> Void] = []

        var toastClock: ParcToastClock {
            ParcToastClock(repeating: { [self] interval, work in
                self.interval = interval
                self.tick = work
                return { [weak self] in self?.tick = nil }
            }, after: { [self] _, work in
                self.delayed.append(work)
                return { [weak self] in self?.delayed.removeAll() }
            })
        }
    }

    @MainActor private func window() -> NSWindow {
        _ = NSApplication.shared
        let parent = NSWindow(contentRect: NSRect(x: 20, y: 30, width: 800, height: 600),
                              styleMask: .borderless, backing: .buffered, defer: true)
        parent.isReleasedWhenClosed = false
        return parent
    }

    @MainActor private func toast(content: ParcToastContent = .copiedImage, clock: Clock? = nil,
                                  tap: (() -> Void)? = nil, retry: (() -> Void)? = nil,
                                  share: @escaping @MainActor ([URL], NSPoint?) -> Void = { _, _ in }) -> ParcToastPresentation {
        _ = NSApplication.shared
        return ParcToastPresentation(content: content, theme: SpaceTheme(), onTap: tap,
                                     onRetry: retry, share: share, clock: (clock ?? Clock()).toastClock)
    }

    @MainActor private func presenter() -> ParcToastPresenter {
        ParcToastPresenter(clock: Clock().toastClock, present: { _, _, _ in true })
    }

    @Test func aWindowToastUsesTheTopRightOfTheParent() {
        let parent = NSRect(x: 100, y: 120, width: 900, height: 800)
        #expect(ParcToastPlacement.windowFrame(for: parent) == NSRect(x: 400, y: 320, width: 600, height: 600))
    }

    @Test func aContentToastUsesTheUpperHalfOfThePane() {
        let pane = NSRect(x: 100, y: 120, width: 500, height: 800)
        #expect(ParcToastPlacement.contentFrame(for: pane) == NSRect(x: 100, y: 520, width: 500, height: 400))
    }

    @Test(arguments: [false, true])
    @MainActor func onlyAVisiblePaneAnchorsAContentToast(hidden: Bool) {
        let parent = window()
        let pane = NSView(frame: NSRect(x: 250, y: 30, width: 500, height: 480))
        parent.contentView?.addSubview(pane)
        pane.isHidden = hidden
        let expected = hidden ? ParcToastPlacement.windowFrame(for: parent.frame)
            : ParcToastPlacement.contentFrame(for: parent.convertToScreen(pane.convert(pane.bounds, to: nil)))
        #expect(ParcToastPresentation.frame(in: parent, over: pane) == expected)
    }

    @Test @MainActor func aHiddenWindowCannotAdmitAToast() {
        let presentation = toast()
        #expect(!presentation.present(in: window(), over: nil))
    }

    @Test @MainActor func theDismissalClockRetiresAnIdleToastAtItsFirstTick() {
        let clock = Clock()
        let presentation = toast(clock: clock)
        var finished: Bool?
        presentation.onRetire = { finished = $0 }
        presentation.startDismissalTimer { false }
        #expect(clock.interval == ParcToastTiming.duration)
        #expect(!presentation.isRetiring)
        clock.tick?()
        #expect(presentation.isRetiring)
        #expect(finished == true)
        #expect(clock.tick == nil)
    }

    @Test @MainActor func theDismissalClockKeepsAHoveredToastUntilThePointerLeaves() {
        let clock = Clock()
        let presentation = toast(clock: clock)
        var hovered = true
        presentation.startDismissalTimer { hovered }
        clock.tick?()
        #expect(!presentation.isRetiring)
        hovered = false
        clock.tick?()
        #expect(presentation.isRetiring)
    }

    @Test @MainActor func theDismissalClockKeepsAKeyboardFocusedToast() {
        let clock = Clock()
        let presentation = toast(clock: clock, tap: {})
        presentation.state.focused = .card
        presentation.startDismissalTimer { false }
        clock.tick?()
        #expect(!presentation.isRetiring)
        presentation.state.focused = nil
        clock.tick?()
        #expect(presentation.isRetiring)
    }

    @Test(arguments: [false, true])
    @MainActor func anActionRetiresTheToastBeforeItsCallbackAndRunsOnce(retry: Bool) {
        var order: [String] = []
        let action = { order.append("action") }
        let presentation = toast(content: .standard("Couldn’t add", buttons: [.retry]),
                                 tap: retry ? nil : action, retry: retry ? action : nil)
        presentation.onRetire = { finished in if finished { order.append("retired") } }
        let press = retry ? presentation.performRetry : presentation.performTap
        press()
        press()
        #expect(order == ["retired", "action"])
    }

    @Test @MainActor func aNewToastRetiresTheOldOneWithoutSendingAnIdleSignal() throws {
        let parent = window()
        let presenter = presenter()
        presenter.onIdle = { Issue.record("Replacement reported an idle window") }
        let first = try #require(presenter.show(.copiedImage, in: parent, over: nil, theme: SpaceTheme()))
        let second = try #require(presenter.show(.copiedBuildInfo, in: parent, over: nil, theme: SpaceTheme()))
        #expect(first.isRetiring)
        #expect(presenter.current === second)
    }

    @Test(arguments: [true, false])
    @MainActor func onlyAFinishedActionSignalsThatTheWindowIsIdle(tap: Bool) throws {
        let presenter = presenter()
        var idle = 0
        presenter.onIdle = { idle += 1 }
        let shown = try #require(presenter.show(.copiedImage, in: window(), over: nil, theme: SpaceTheme(), onTap: {}))
        if tap { shown.performTap() } else { presenter.dismiss(animated: false) }
        #expect(presenter.current == nil)
        #expect(idle == (tap ? 1 : 0))
    }

    @Test(arguments: [true, false])
    @MainActor func aBindingChangeDismissesOnlyToastsDisplayingAShortcut(shortcut: Bool) throws {
        let presenter = presenter()
        let content: ParcToastContent = shortcut ? .clearedTabs : .copiedImage
        let shown = try #require(presenter.show(content, in: window(), over: nil, theme: SpaceTheme()))
        presenter.dismissShortcutToasts()
        #expect(shown.isRetiring == shortcut)
    }

    @Test(arguments: [(CGFloat(0), false), (CGFloat(2), true), (CGFloat(-2), true)])
    @MainActor func realScrollMotionInTheParentDismissesTheToast(example: (CGFloat, Bool)) {
        let parent = window()
        #expect(ParcToastScroll.dismisses(window: parent, deltaX: 0, deltaY: example.0, owners: [parent]) == example.1)
    }

    @Test @MainActor func scrollingAnotherWindowDoesNotDismissTheToast() {
        let parent = window()
        let other = window()
        #expect(!ParcToastScroll.dismisses(window: other, deltaX: 2, deltaY: 0, owners: [parent]))
    }

    @Test(arguments: [(UInt16(48), ParcToastKeyboard.Action.next), (124, .next), (125, .next),
                      (123, .previous), (126, .previous), (36, .activate), (76, .activate), (49, .activate), (53, .dismiss)])
    func unmodifiedKeysNavigateOrActivateTheToast(binding: (UInt16, ParcToastKeyboard.Action)) {
        #expect(ParcToastKeyboard.action(keyCode: binding.0, characters: nil, modifiers: []) == binding.1)
    }

    @Test func shiftTabMovesBackwardThroughTheActions() {
        #expect(ParcToastKeyboard.action(keyCode: 48, characters: "\t", modifiers: .shift) == .previous)
    }

    @Test func thePopupChordCanFocusAToast() {
        #expect(ParcToastKeyboard.action(keyCode: 0, characters: "A", modifiers: [.command, .option, .shift]) == .focus)
    }

    @Test func controlF6CanFocusAToast() {
        #expect(ParcToastKeyboard.action(keyCode: 97, characters: nil, modifiers: [.control, .function]) == .focus)
    }

    @Test @MainActor func voiceOverCanShareTheExactCopiedLinks() throws {
        let urls = [try #require(URL(string: "https://example.test/first")), try #require(URL(string: "https://example.test/next"))]
        var shared = [URL]()
        let presentation = toast(content: .copiedLinks(urls), share: { urls, _ in shared = urls })
        let shareButton = try #require(presentation.subviews.first { $0.accessibilityLabel() == "Share" })
        #expect(shareButton.accessibilityRole() == .button)
        #expect(shareButton.accessibilityPerformPress())
        #expect(shared == urls)
        #expect(!presentation.isRetiring)
    }

    @Test @MainActor func aToastWithoutActionsHasNoFocusTargets() {
        #expect(toast().keyboardTargets.isEmpty)
    }

    @Test @MainActor func aRetryButtonWithoutAnActionIsOmittedFromTheFocusLoop() {
        let presentation = toast(content: .standard("Couldn’t add", buttons: [.retry]))
        #expect(presentation.keyboardTargets.isEmpty)
    }

    @Test @MainActor func tabWrapsFromTheLastActionToTheFirst() throws {
        let url = try #require(URL(string: "https://example.test/"))
        let presentation = toast(content: .standard("Copied", buttons: [.share([url]), .retry]), tap: {}, retry: {})
        presentation.state.focused = .button(1)
        let tab = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                                              windowNumber: 0, context: nil, characters: "\t",
                                              charactersIgnoringModifiers: "\t", isARepeat: false, keyCode: 48))
        presentation.keyDown(with: tab)
        #expect(presentation.state.focused == .card)
    }

    @Test func aFailedInstallationNamesItsRestrictionAndRetryAction() {
        let content = ParcToastContent.extensionsNotApplied(
            added: [.init(name: "Helper", profile: "Work", reason: .administrator)], removed: [], retry: true)
        #expect(content == .standard("Couldn’t add Helper to Work", subLabel: "Blocked by your administrator", buttons: [.retry]))
    }

    @Test(arguments: [false, true])
    @MainActor func anIdleNoticeOnlyRunsForTheFrontWindow(front: Bool) {
        let presenter = presenter()
        var scheduled: (@MainActor () -> Void)?
        var requests = 0
        let queue = ParcToastQueue(presenter: presenter, next: { requests += 1; return nil },
                                   present: { _ in nil }, schedule: { scheduled = $0 })
        queue.isFront = { front }
        queue.showNextWhenIdle()
        scheduled?()
        #expect(requests == (front ? 1 : 0))
    }

    @Test(arguments: [false, true])
    @MainActor func aNoticeIsRestoredWhenTheWindowCannotPresentIt(canShow: Bool) {
        let presenter = presenter()
        var restored = false
        let queue = ParcToastQueue(presenter: presenter, next: { .init(content: .importFailed, restore: { restored = true }) },
                                   present: { _ in nil })
        queue.canShow = { canShow }
        queue.showNext()
        #expect(restored == canShow)
    }
}
