import AppKit
import QuartzCore
import Testing
@testable import Parc
@testable import ParcCore

@MainActor
struct SplitDividerTestsAnnouncements {
    private typealias SplitScaleWindow = SplitDividerTestsSupport.SplitScaleWindow

    private struct Post {
        let element: AnyObject
        let notification: NSAccessibility.Notification
        let elements: [AnyObject]
    }

    @MainActor private final class Rig {
        let window = SplitScaleWindow.make(width: 1610, height: 800)
        let split = ParcSplitView(frame: NSRect(x: 0, y: 0, width: 1210, height: 800))
        let panes = (0..<3).map { _ in NSView() }
        var posts: [Post] = []
        var settling: (@MainActor () -> Void)?

        init() {
            split.postAccessibilityNotification = { [weak self] element, notification, info in
                self?.posts.append(Post(element: element as AnyObject, notification: notification,
                                  elements: (info?[.uiElements] as? [Any] ?? []).map { $0 as AnyObject }))
            }
            split.scheduleDividerSettle = { [weak self] settle in
                self?.settling = settle
                return Timer(timeInterval: 3600, repeats: false) { _ in }
            }
            window.contentView!.addSubview(split)
        }

        deinit { MainActor.assumeIsolated { window.close() } }

        func taken() -> [Post] { defer { posts = [] }; return posts }
        var splitters: [ParcSplitView.DividerAccessibilityElement] {
            (split.accessibilitySplitters() ?? []).compactMap { $0 as? ParcSplitView.DividerAccessibilityElement }
        }
        func value(_ index: Int) -> Double { (splitters[index].accessibilityValue() as? NSNumber)?.doubleValue ?? -1 }
        func changed(_ list: [Post]) -> [AnyObject] { list.filter { $0.notification == .valueChanged }.map(\.element) }
        func settle() { let pending = settling; settling = nil; pending?() }
        func dividerPoint(_ x: CGFloat = 0) -> NSPoint { NSPoint(x: panes[0].frame.maxX + 5 + x, y: 300) }
        func doubleClick() {
            split.mouseDown(with: NSEvent.mouseEvent(with: .leftMouseDown,
                location: split.convert(NSPoint(x: panes[0].frame.maxX + 3, y: 300), to: nil), modifierFlags: [],
                timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 2, pressure: 1)!)
        }
        var windowCommit: () -> (([Double]) -> Bool)? {
            { [weak split] in
                { factors in
                    guard let split, let saved = BrowserSplitLayout.normalized(factors, count: factors.count) else { return false }
                    split.configure(orientation: .horizontal, factors: saved.map { $0 * 2 })
                    return true
                }
            }
        }

        func twoPanes() {
            _ = split.reconcileArrangedSubviews(Array(panes[..<2]))
            split.configure(orientation: .horizontal, factors: [1, 1])
        }

        func settled() {
            twoPanes()
            _ = taken()
            split.prepareDividerResize = windowCommit
        }

        func shrinkAfterExpand() {
            split.configure(orientation: .horizontal, factors: [980, 220])
            _ = taken()
            for width in [1160.0, 1110, 1060, 1010] { split.setFrameSize(NSSize(width: width, height: 800)) }
        }
    }

    @Test func aNewSplitsSplitterAnnouncesItselfAndTheLayoutChangeWithNoValueChange() {
        let rig = Rig()
        let parent = NSAccessibility.unignoredAncestor(of: rig.split) as AnyObject?
        rig.twoPanes()
        let list = rig.taken()
        let first = rig.splitters[0]
        #expect(parent != nil && list.count == 2)
        #expect(list[0].notification == .created && list[0].element === first)
        #expect(list[1].notification == .layoutChanged && list[1].element === parent)
        #expect(list[1].elements.count == 1 && list[1].elements[0] === first)
        #expect(rig.value(0) == 50)
    }

    @Test func layingOutTheSameSplitAgainAnnouncesNothing() {
        let rig = Rig()
        rig.twoPanes()
        _ = rig.taken()
        rig.split.configure(orientation: .horizontal, factors: [1, 1])
        #expect(rig.taken().isEmpty)
    }

    @Test func aVoiceOverStepMovesTheDividerAndPostsItsValueChangeExactlyOnce() {
        let rig = Rig()
        rig.settled()
        let first = rig.splitters[0]
        #expect(first.accessibilityPerformIncrement())
        #expect(rig.value(0) == 60)
        let list = rig.taken()
        #expect(list.count == 1)
        #expect(rig.changed(list).count == 1 && rig.changed(list)[0] === first)
    }

    @Test func aRefusedStepChangesNothingAndPostsNothing() {
        let rig = Rig()
        rig.settled()
        rig.split.prepareDividerResize = { { _ in false } }
        #expect(!rig.splitters[0].accessibilityPerformIncrement())
        #expect(rig.value(0) == 50)
        #expect(rig.taken().isEmpty)
    }

    @Test func steppingBackPostsOnce() {
        let rig = Rig()
        rig.settled()
        _ = rig.splitters[0].accessibilityPerformIncrement()
        _ = rig.taken()
        #expect(rig.splitters[0].accessibilityPerformDecrement())
        #expect(rig.value(0) == 50)
        #expect(rig.changed(rig.taken()).count == 1)
    }

    @Test func aLiveMouseDragNeverPostsWhileItMoves() {
        let rig = Rig()
        rig.settled()
        let start = rig.dividerPoint()
        #expect(rig.split.beginDividerResize(at: start))
        for offset in [40.0, 80.0, 120.0] {
            rig.split.updateDividerResize(at: NSPoint(x: start.x + offset, y: start.y), velocity: 200)
        }
        #expect(rig.taken().isEmpty)
        rig.split.finishDividerResize(commit: false)
    }

    @Test func aFinishedMouseDragPostsItsNewValueExactlyOnce() {
        let rig = Rig()
        rig.settled()
        let first = rig.splitters[0]
        let start = rig.dividerPoint()
        rig.split.beginDividerResize(at: start)
        for offset in [40.0, 80.0, 120.0] {
            rig.split.updateDividerResize(at: NSPoint(x: start.x + offset, y: start.y), velocity: 200)
        }
        rig.split.finishDividerResize(commit: true)
        let list = rig.taken()
        #expect(rig.value(0) == 60)
        #expect(list.count == 1 && rig.changed(list)[0] === first)
    }

    @Test func aCancelledDragReturnsToTheSameValueAndPostsNothing() {
        let rig = Rig()
        rig.settled()
        #expect(rig.split.beginDividerResize(at: rig.dividerPoint()))
        rig.split.updateDividerResize(at: rig.dividerPoint(-80), velocity: 200)
        rig.split.finishDividerResize(commit: false)
        #expect(rig.value(0) == 50)
        #expect(rig.taken().isEmpty)
    }

    @Test func aDoubleClickEqualizePostsOnce() {
        let rig = Rig()
        rig.settled()
        rig.split.configure(orientation: .horizontal, factors: [3, 1])
        _ = rig.taken()
        rig.doubleClick()
        #expect(rig.value(0) == 50)
        #expect(rig.changed(rig.taken()).count == 1)
    }

    @Test func equalizingAnAlreadyEvenPairPostsNothing() {
        let rig = Rig()
        rig.settled()
        rig.doubleClick()
        #expect(rig.value(0) == 50)
        #expect(rig.taken().isEmpty)
    }

    @Test func aDragTooSmallToChangeTheReportedPercentagePostsNothing() {
        let rig = Rig()
        rig.settled()
        #expect(rig.split.beginDividerResize(at: rig.dividerPoint()))
        rig.split.updateDividerResize(at: rig.dividerPoint(2), velocity: 200)
        rig.split.finishDividerResize(commit: true)
        #expect(rig.value(0) == 50)
        #expect(rig.taken().isEmpty)
    }

    @Test func anExpandFromTheWindowPostsOnce() {
        let rig = Rig()
        rig.settled()
        rig.split.configure(orientation: .horizontal, factors: [980, 220])
        #expect(rig.value(0) == 82)
        #expect(rig.changed(rig.taken()).count == 1)
    }

    @Test func repeatingTheSameLayoutPostsNothing() {
        let rig = Rig()
        rig.settled()
        rig.split.configure(orientation: .horizontal, factors: [980, 220])
        _ = rig.taken()
        rig.split.configure(orientation: .horizontal, factors: [980, 220])
        #expect(rig.taken().isEmpty)
    }

    @Test func aWindowResizeThatMovesTheSharesWaitsForTheSizeToSettle() {
        let rig = Rig()
        rig.settled()
        rig.shrinkAfterExpand()
        #expect(rig.value(0) == 78)
        #expect(rig.taken().isEmpty)
    }

    @Test func onceTheSizeSettlesARunOfResizesPostsExactlyOnce() {
        let rig = Rig()
        rig.settled()
        let first = rig.splitters[0]
        rig.shrinkAfterExpand()
        rig.settle()
        let list = rig.taken()
        #expect(list.count == 1 && rig.changed(list).count == 1 && rig.changed(list)[0] === first)
    }

    @Test func aDraggedPairReportsItsDisplayedSizes() {
        let rig = Rig()
        rig.settled()
        rig.shrinkAfterExpand()
        rig.settle()
        _ = rig.taken()
        #expect(rig.split.beginDividerResize(at: rig.dividerPoint()))
        rig.split.updateDividerResize(at: rig.dividerPoint(-100), velocity: 200)
        #expect(rig.value(0) == 68)
    }

    @Test func pausingDuringADragDoesNotPostAValue() {
        let rig = Rig()
        rig.settled()
        rig.shrinkAfterExpand()
        rig.settle()
        _ = rig.taken()
        _ = rig.split.beginDividerResize(at: rig.dividerPoint())
        rig.split.updateDividerResize(at: rig.dividerPoint(-100), velocity: 200)
        rig.settle()
        #expect(rig.taken().isEmpty)
    }

    @Test func releasingTheHeldDragPostsTheNewValueExactlyOnceThroughTheWindowsCommit() {
        let rig = Rig()
        rig.settled()
        rig.shrinkAfterExpand()
        rig.settle()
        _ = rig.taken()
        rig.split.beginDividerResize(at: rig.dividerPoint())
        rig.split.updateDividerResize(at: rig.dividerPoint(-100), velocity: 200)
        rig.split.finishDividerResize(commit: true)
        let list = rig.taken()
        #expect(rig.value(0) == 68)
        #expect(list.count == 1 && rig.changed(list).count == 1)
    }

    @Test func expandingAgainPostsOnce() {
        let rig = Rig()
        rig.settled()
        rig.shrinkAfterExpand()
        rig.settle()
        rig.split.beginDividerResize(at: rig.dividerPoint())
        rig.split.updateDividerResize(at: rig.dividerPoint(-100), velocity: 200)
        rig.split.finishDividerResize(commit: true)
        _ = rig.taken()
        rig.split.configure(orientation: .horizontal, factors: [980, 220])
        #expect(rig.value(0) == 78)
        #expect(rig.changed(rig.taken()).count == 1)
    }

    @Test func growingBackWaitsToPostTheUpdatedShare() {
        let rig = Rig()
        rig.settled()
        rig.shrinkAfterExpand()
        rig.settle()
        _ = rig.taken()
        rig.split.setFrameSize(NSSize(width: 1210, height: 800))
        #expect(rig.value(0) == 82)
        #expect(rig.taken().isEmpty)
    }

    @Test func theEndOfALiveResizePostsTheUpdatedShareAtOnce() {
        let rig = Rig()
        rig.settled()
        rig.shrinkAfterExpand()
        rig.settle()
        _ = rig.taken()
        rig.split.setFrameSize(NSSize(width: 1210, height: 800))
        rig.split.viewDidEndLiveResize()
        #expect(rig.changed(rig.taken()).count == 1)
    }

    @Test func theSettledValueIsNotPostedAgain() {
        let rig = Rig()
        rig.settled()
        rig.shrinkAfterExpand()
        rig.settle()
        rig.split.setFrameSize(NSSize(width: 1210, height: 800))
        rig.split.viewDidEndLiveResize()
        _ = rig.taken()
        rig.settle()
        #expect(rig.taken().isEmpty)
    }

    @Test func returningToEvenPanesPostsOnce() {
        let rig = Rig()
        rig.settled()
        rig.split.configure(orientation: .horizontal, factors: [980, 220])
        _ = rig.taken()
        rig.split.configure(orientation: .horizontal, factors: [1, 1])
        #expect(rig.changed(rig.taken()).count == 1)
    }

    @Test func aWindowResizeThatKeepsTheSharesPostsNothing() {
        let rig = Rig()
        rig.settled()
        rig.split.setFrameSize(NSSize(width: 1010, height: 800))
        rig.settle()
        rig.split.setFrameSize(NSSize(width: 1210, height: 800))
        rig.settle()
        #expect(rig.value(0) == 50)
        #expect(rig.taken().isEmpty)
    }

    @Test func aDropPreviewHidesTheSplitterWithoutPosting() {
        let rig = Rig()
        rig.settled()
        let reservation = rig.split.prepareDropReservation(in: rig.window.contentView!, contents: Array(rig.panes[..<2]))
        reservation?.hoverIntent = SplitDropIntent(dwell: 0)
        let preview = reservation?.proposal(at: rig.split.convert(NSPoint(x: 10, y: 300), to: rig.window.contentView!)) { _, _ in true }
        #expect(preview != nil)
        #expect(rig.splitters.isEmpty)
        #expect(rig.taken().isEmpty)
    }

    @Test func endingADropPreviewRestoresTheSameValueWithoutPosting() {
        let rig = Rig()
        rig.settled()
        let reservation = rig.split.prepareDropReservation(in: rig.window.contentView!, contents: Array(rig.panes[..<2]))
        reservation?.hoverIntent = SplitDropIntent(dwell: 0)
        _ = reservation?.proposal(at: rig.split.convert(NSPoint(x: 10, y: 300), to: rig.window.contentView!)) { _, _ in true }
        _ = rig.taken()
        reservation?.end()
        #expect(rig.value(0) == 50)
        #expect(rig.taken().isEmpty)
    }

    @Test func voiceOverAskingMidUpdatePostsNothing() {
        let rig = Rig()
        rig.settled()
        _ = rig.split.reconcileArrangedSubviews(rig.panes)
        #expect(rig.splitters.count == 2)
        #expect(rig.taken().isEmpty)
    }

    @Test func addingAPaneAnnouncesItsNewSplitterAndTheLayoutAndPostsTheMovedDividerOnce() {
        let rig = Rig()
        rig.settled()
        let first = rig.splitters[0]
        let parent = NSAccessibility.unignoredAncestor(of: rig.split) as AnyObject?
        _ = rig.split.reconcileArrangedSubviews(rig.panes)
        rig.split.configure(orientation: .horizontal, factors: [1, 1, 1])
        let list = rig.taken()
        let added = rig.splitters
        #expect(added.count == 2 && added[0] === first)
        #expect(rig.value(0) == 33 && rig.value(1) == 67)
        #expect(list.count == 3)
        let created = list.filter { $0.notification == .created }.map(\.element)
        #expect(created.count == 1 && created[0] === added[1])
        #expect(list.contains { $0.notification == .layoutChanged && $0.element === parent && $0.elements.count == 1 && $0.elements[0] === added[1] })
        #expect(rig.changed(list).count == 1 && rig.changed(list)[0] === first)
    }

    @Test func removingAPaneRetiresItsSplitterAnnouncesTheLayoutAndPostsTheSurvivingDividerOnce() {
        let rig = Rig()
        rig.settled()
        _ = rig.split.reconcileArrangedSubviews(rig.panes)
        rig.split.configure(orientation: .horizontal, factors: [1, 1, 1])
        let first = rig.splitters[0], second = rig.splitters[1]
        let parent = NSAccessibility.unignoredAncestor(of: rig.split) as AnyObject?
        _ = rig.taken()
        _ = rig.split.reconcileArrangedSubviews(Array(rig.panes[..<2]))
        rig.split.configure(orientation: .horizontal, factors: [1, 1])
        let list = rig.taken()
        #expect(rig.splitters.count == 1 && rig.value(0) == 50 && list.count == 3)
        let destroyed = list.filter { $0.notification == .uiElementDestroyed }.map(\.element)
        #expect(destroyed.count == 1 && destroyed[0] === second)
        #expect(list.contains { $0.notification == .layoutChanged && $0.element === parent && $0.elements.isEmpty })
        #expect(rig.changed(list).count == 1 && rig.changed(list)[0] === first)
    }

    @Test func endingTheSplitRetiresTheLastSplitterWithoutAValueChange() {
        let rig = Rig()
        rig.settled()
        let first = rig.splitters[0]
        _ = rig.split.reconcileArrangedSubviews([rig.panes[0]])
        rig.split.configure(orientation: .horizontal, factors: [1])
        let list = rig.taken()
        #expect(rig.splitters.isEmpty && list.count == 2)
        #expect(list[0].notification == .uiElementDestroyed && list[0].element === first)
        #expect(list[1].notification == .layoutChanged)
        #expect(rig.changed(list).isEmpty)
    }
}
