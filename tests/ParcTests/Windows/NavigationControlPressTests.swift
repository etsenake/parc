import AppKit
import Testing
@testable import ParcSidebar

@MainActor private final class Recorder {
    let anchor = NSView()
    var actions: [Bool] = []
    var menus = 0
    var anchors: [NSView] = []

    lazy var interaction = NavigationControlInteraction(activate: { [unowned self] in actions.append($0) },
                                                        showHistory: { [unowned self] received in anchors.append(received); menus += 1 })

    func press(_ modifiers: NSEvent.ModifierFlags = [], middle: Bool = false, number: Int = 1) -> NavigationControlPress {
        NavigationControlPress(event: Recorder.event(modifiers, middle: middle, number: number), interaction: interaction)
    }

    static func event(_ modifiers: NSEvent.ModifierFlags = [], middle: Bool = false, number: Int = 1) -> NSEvent {
        if middle {
            let source = CGEvent(mouseEventSource: nil, mouseType: .otherMouseDown, mouseCursorPosition: .zero, mouseButton: .center)!
            source.flags = CGEventFlags(rawValue: UInt64(modifiers.rawValue))
            source.setIntegerValueField(.mouseEventNumber, value: Int64(number))
            return NSEvent(cgEvent: source)!
        }
        return NSEvent.mouseEvent(with: .leftMouseDown, location: .zero, modifierFlags: modifiers, timestamp: 1,
                                  windowNumber: 0, context: nil, eventNumber: number, clickCount: 1, pressure: 1)!
    }
}

struct NavigationControlPressTests {
    @MainActor @Test func aNewInteractionIsLive() {
        let r = Recorder()
        let normal = r.press()
        #expect(normal.hasHistory)
        #expect(!normal.finished)
    }

    @MainActor @Test func anOrdinaryPressCommitsExactlyOnce() {
        let r = Recorder()
        let normal = r.press()
        normal.activate()
        normal.activate()
        normal.showHistory(from: r.anchor)
        #expect(r.actions == [false])
        #expect(r.menus == 0)
    }

    @MainActor @Test func aCommitDropsTheCapturedClosures() {
        let r = Recorder()
        let normal = r.press()
        normal.activate()
        #expect(normal.finished)
        #expect(!normal.hasHistory)
    }

    @MainActor @Test func commandIsCapturedAtPointerDown() {
        let r = Recorder()
        let command = r.press([.command], number: 2)
        _ = Recorder.event([], number: 3)
        command.activate()
        #expect(r.actions == [true])
    }

    @MainActor @Test func shiftAloneDoesNotRequestAnAlternateDestination() {
        let r = Recorder()
        r.press([.shift]).activate()
        #expect(r.actions == [false])
    }

    @MainActor @Test func shiftDoesNotInvertTheRecoveredCommandAlternateFlag() {
        let r = Recorder()
        r.press([.command, .shift]).activate()
        #expect(r.actions == [true])
    }

    @MainActor @Test func anIsolatedMiddleEventHasTheActualButtonIdentity() {
        #expect(Recorder.event(middle: true).buttonNumber == 2)
    }

    @MainActor @Test func theMiddleButtonRequestsTheAlternateAction() {
        let r = Recorder()
        r.press(middle: true).activate()
        #expect(r.actions == [true])
    }

    @MainActor @Test(arguments: [0, 1, 2, 3])
    func historyConsumesTheReleaseEvenWithAModifier(_ index: Int) {
        let flags: [NSEvent.ModifierFlags] = [[], [.command], [.option], [.shift]]
        let r = Recorder()
        let hold = r.press(flags[index])
        hold.showHistory(from: r.anchor)
        hold.showHistory(from: r.anchor)
        hold.activate()
        #expect(r.actions.isEmpty)
        #expect(r.menus == 1)
        #expect(hold.finished)
        #expect(!hold.hasHistory)
    }

    @MainActor @Test func historyKeepsTheOriginalAnchor() {
        let r = Recorder()
        r.press().showHistory(from: r.anchor)
        #expect(r.anchors.first === r.anchor)
    }

    @MainActor @Test func cancelNeverDispatchesOrOpensHistory() {
        let r = Recorder()
        let cancelled = r.press([.command])
        cancelled.cancel()
        cancelled.activate()
        cancelled.showHistory(from: r.anchor)
        #expect(r.actions.isEmpty)
        #expect(r.menus == 0)
    }

    @MainActor @Test func cancelClearsTheOriginalOwnersClosures() {
        let r = Recorder()
        let cancelled = r.press([.command])
        cancelled.cancel()
        #expect(cancelled.finished)
        #expect(!cancelled.hasHistory)
    }

    @MainActor @Test func consumptionPrecedesReentrantActionDispatch() {
        let r = Recorder()
        var recursive: NavigationControlPress!
        var calls = 0
        var reentrantMenus = 0
        recursive = NavigationControlPress(event: Recorder.event(), interaction: .init(activate: { _ in
            calls += 1
            recursive.activate()
            recursive.showHistory(from: r.anchor)
        }, showHistory: { _ in reentrantMenus += 1 }))
        recursive.activate()
        #expect(calls == 1)
        #expect(reentrantMenus == 0)
    }

    @MainActor @Test func consumptionPrecedesReentrantMenuDispatch() {
        let r = Recorder()
        var recursive: NavigationControlPress!
        var menus = 0
        var reentrantActions = 0
        recursive = NavigationControlPress(event: Recorder.event(), interaction: .init(activate: { _ in reentrantActions += 1 }, showHistory: { _ in
            menus += 1
            recursive.activate()
            recursive.showHistory(from: r.anchor)
        }))
        recursive.showHistory(from: r.anchor)
        #expect(menus == 1)
        #expect(reentrantActions == 0)
    }

    @MainActor @Test func refreshHasNoHistoryOwner() {
        var actions: [Bool] = []
        let noHistory = NavigationControlPress(event: Recorder.event(), interaction: .init(activate: { actions.append($0) }))
        #expect(!noHistory.hasHistory)
    }

    @MainActor @Test func unsupportedHistoryCannotConsumeAnOrdinaryAction() {
        let r = Recorder()
        var actions: [Bool] = []
        let noHistory = NavigationControlPress(event: Recorder.event(), interaction: .init(activate: { actions.append($0) }))
        noHistory.showHistory(from: r.anchor)
        #expect(!noHistory.finished)
        noHistory.activate()
        #expect(actions == [false])
    }

    @MainActor @Test func theOriginalInteractionIsRetainedUntilResolutionAndReleasedByCancel() {
        final class Owner { var invoked = false }
        var original: Owner? = Owner()
        weak let capturedOwner = original
        let owned = NavigationControlPress(event: Recorder.event(), interaction: .init(activate: { [original] _ in original?.invoked = true }))
        original = nil
        #expect(capturedOwner != nil)
        owned.cancel()
        #expect(capturedOwner == nil)
    }

    @MainActor @Test func theRecoveredNativeHoldDuration() {
        #expect(NavigationControlPress.historyHoldDuration == 0.3)
    }
}
