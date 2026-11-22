import AppKit
import Testing
@testable import Parc
@testable import ParcSidebar

@MainActor
struct SidebarBannerHostTests {
    @MainActor
    private final class Fixture {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 400),
                              styleMask: [.titled], backing: .buffered, defer: false)
        let root: NSView
        let field = NSTextField(string: "Original editor")
        let card = NSButton(title: "Got it", target: nil, action: nil)
        let host: SidebarBannerHost
        var scheduled: [(delay: TimeInterval, work: DispatchWorkItem)] = []
        var interactionChanges: [Bool] = []
        var relinquished = 0
        var reducesMotion = false

        init() {
            _ = NSApplication.shared
            window.isReleasedWhenClosed = false
            root = NSView(frame: window.contentView!.bounds)
            window.contentView = root
            field.frame = NSRect(x: 250, y: 20, width: 180, height: 30)
            root.addSubview(field)
            host = SidebarBannerHost(card: card)
            host.frame = NSRect(x: 8, y: 20, width: 220, height: 180)
            host.scheduleWork = { [weak self] delay, work in self?.scheduled.append((delay, work)) }
            host.reduceMotion = { [weak self] in self?.reducesMotion ?? false }
            host.onInteractionChanged = { [weak self] in self?.interactionChanges.append($0) }
            host.onRelinquishFocus = { [weak self] in
                guard let self else { return }
                relinquished += 1
                window.makeFirstResponder(field)
            }
            root.addSubview(host)
            window.makeFirstResponder(field)
        }

        deinit {
            MainActor.assumeIsolated { window.close() }
        }

        func runScheduled() {
            let pending = scheduled
            scheduled.removeAll()
            for entry in pending { entry.work.perform() }
        }

        func appeared() -> Fixture {
            host.show(true)
            runScheduled()
            return self
        }
    }

    @Test func entryStartsWithNoInteractiveCard() {
        let fixture = Fixture()
        fixture.host.show(true)
        #expect(fixture.host.phase == .initial)
        #expect(!fixture.host.isInteractive)
    }

    @Test func entryCompletesOnTheCurrentWindow() {
        let fixture = Fixture().appeared()
        #expect(fixture.host.phase == .appeared)
        #expect(fixture.host.isInteractive)
    }

    @Test func appearancePreservesTheOriginalNativeResponder() {
        let fixture = Fixture()
        let original = fixture.window.firstResponder
        _ = fixture.appeared()
        #expect(fixture.window.firstResponder === original)
    }

    @Test func anUnrelatedStateRefreshDoesNotReplayEntry() {
        let fixture = Fixture().appeared()
        fixture.host.show(true)
        #expect(fixture.scheduled.isEmpty)
        #expect(fixture.host.phase == .appeared)
        #expect(fixture.interactionChanges == [true])
    }

    @Test func theHostedCardJoinsTheOriginalWindow() {
        let fixture = Fixture().appeared()
        fixture.host.layoutSubtreeIfNeeded()
        fixture.root.layoutSubtreeIfNeeded()
        #expect(fixture.card.window === fixture.window)
    }

    @Test func disablingAFocusedCardRelinquishesOnlyItsOwnResponder() {
        let fixture = Fixture().appeared()
        fixture.host.addSubview(fixture.card)
        #expect(fixture.window.makeFirstResponder(fixture.card))
        fixture.host.setInteractionAllowed(false)
        #expect(fixture.relinquished == 1)
        #expect(fixture.window.firstResponder !== fixture.card)
    }

    @Test func disablingInteractionWithoutAFocusedCardRelinquishesNothing() {
        let fixture = Fixture().appeared()
        fixture.host.setInteractionAllowed(false)
        #expect(fixture.relinquished == 0)
    }

    @Test func aHiddenSidebarBypassesControlsWithoutConsumingSharedState() {
        let fixture = Fixture().appeared()
        fixture.host.setInteractionAllowed(false)
        #expect(!fixture.host.isInteractive)
        #expect(fixture.host.phase == .appeared)
    }

    @Test func aVisibleSidebarRestoresControls() {
        let fixture = Fixture().appeared()
        fixture.host.setInteractionAllowed(false)
        fixture.host.setInteractionAllowed(true)
        #expect(fixture.host.isInteractive)
    }

    @Test func exitRetainsGeometryButDisablesControls() {
        let fixture = Fixture().appeared()
        fixture.host.show(false)
        #expect(fixture.host.phase == .dismissing)
        #expect(!fixture.host.isInteractive)
        #expect(fixture.host.occupiesSpace)
    }

    @Test func reducedMotionExitSettlesImmediately() {
        let fixture = Fixture().appeared()
        fixture.reducesMotion = true
        fixture.host.show(false)
        #expect(fixture.host.phase == .absent)
        #expect(!fixture.host.isInteractive)
    }

    @Test func aBackgroundDismissalDoesNotChangeFocus() {
        let fixture = Fixture().appeared()
        let before = fixture.window.firstResponder
        fixture.host.show(false)
        #expect(fixture.relinquished == 0)
        #expect(fixture.window.firstResponder === before)
    }

    @Test func aNewPresentationSupersedesAnOldExit() {
        let fixture = Fixture().appeared()
        fixture.host.show(false)
        fixture.host.show(true)
        fixture.runScheduled()
        #expect(fixture.host.phase == .appeared)
        #expect(fixture.host.isInteractive)
    }

    @Test func aStaleExitCannotRemoveANewerPresentation() {
        let fixture = Fixture().appeared()
        fixture.host.show(false)
        let staleExit = fixture.scheduled
        fixture.scheduled.removeAll()
        fixture.host.show(true)
        fixture.runScheduled()
        for entry in staleExit { entry.work.perform() }
        #expect(fixture.host.phase == .appeared)
    }

    @Test func theExitIsScheduledForItsDismissalLifetime() {
        let fixture = Fixture().appeared()
        fixture.host.show(false)
        #expect(fixture.scheduled.map(\.delay) == [SidebarBannerHost.dismissalLifetime])
    }

    @Test func aCompletedExitReleasesLayoutSpace() {
        let fixture = Fixture().appeared()
        fixture.host.show(false)
        fixture.runScheduled()
        #expect(fixture.host.phase == .absent)
        #expect(fixture.host.isHidden)
    }

    @Test func aWindowResetEndsTheLifetimeImmediately() {
        let fixture = Fixture().appeared()
        fixture.host.reset()
        #expect(fixture.host.phase == .absent)
        #expect(!fixture.host.occupiesSpace)
        #expect(!fixture.host.isInteractive)
    }

    @Test func aCancelledEntryCannotAppearLater() {
        let fixture = Fixture()
        fixture.host.show(true)
        fixture.host.reset()
        fixture.runScheduled()
        #expect(fixture.host.phase == .absent)
    }

    @Test func detachingTheOriginalWindowInvalidatesCardActions() {
        let fixture = Fixture().appeared()
        fixture.host.removeFromSuperview()
        fixture.runScheduled()
        #expect(fixture.host.phase == .absent)
        #expect(!fixture.host.isInteractive)
    }

    @Test func aPendingCardCanAttachToItsOwnWindowAgain() {
        let fixture = Fixture().appeared()
        fixture.host.removeFromSuperview()
        fixture.root.addSubview(fixture.host)
        fixture.runScheduled()
        #expect(fixture.host.phase == .appeared)
    }
}
