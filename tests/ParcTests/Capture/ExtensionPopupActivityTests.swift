import CoreGraphics
import Foundation
import Testing
@testable import Parc

struct ExtensionPopupActivityTests {
    private final class Thing {}

    private func same(_ changes: [ExtensionPopupActivityChange], _ expected: [(AnyObject, ExtensionPopupActivityPhase?)]) -> Bool {
        changes.count == expected.count && zip(changes, expected).allSatisfy { $0.control === $1.0 && $0.phase == $1.1 }
    }

    @Test func aPopupImmediatelyLightsItsButton() {
        let first = Thing(), clicked = Thing()
        var tracker = ExtensionPopupActivityTracker()
        #expect(same(tracker.place(popup: first, control: clicked), [(clicked, .loading)]))
    }

    @Test func placingTheSamePopupTwiceDoesNotRelightIt() {
        let first = Thing(), clicked = Thing()
        var tracker = ExtensionPopupActivityTracker()
        _ = tracker.place(popup: first, control: clicked)
        #expect(same(tracker.place(popup: first, control: clicked), []))
    }

    @Test func revealingThePopupLightsTheButtonAsOpen() {
        let first = Thing(), clicked = Thing()
        var tracker = ExtensionPopupActivityTracker()
        _ = tracker.place(popup: first, control: clicked)
        #expect(same(tracker.reveal(popup: first), [(clicked, .open)]))
    }

    @Test func revealingTheSamePopupTwiceDoesNotRelightIt() {
        let first = Thing(), clicked = Thing()
        var tracker = ExtensionPopupActivityTracker()
        _ = tracker.place(popup: first, control: clicked)
        _ = tracker.reveal(popup: first)
        #expect(same(tracker.reveal(popup: first), []))
    }

    @Test func aReplacingPopupMovesTheLightToItsOwnButton() {
        let first = Thing(), second = Thing(), clicked = Thing(), toolbar = Thing()
        var tracker = ExtensionPopupActivityTracker()
        _ = tracker.place(popup: first, control: clicked)
        #expect(same(tracker.place(popup: second, control: toolbar), [(clicked, nil), (toolbar, .loading)]))
        #expect(tracker.tracks(second) && !tracker.tracks(first))
    }

    @Test func replacedPopupsNeverChangeAnotherButtonsLight() {
        let first = Thing(), second = Thing(), clicked = Thing(), toolbar = Thing()
        var tracker = ExtensionPopupActivityTracker()
        _ = tracker.place(popup: first, control: clicked)
        _ = tracker.place(popup: second, control: toolbar)
        #expect(same(tracker.reveal(popup: first), []) && same(tracker.end(popup: first), []))
        #expect(same(tracker.place(popup: first, control: clicked), []))
    }

    @Test func aRefusedReplacementDoesNotLetTheOriginalPopupRelightItsButton() {
        let clicked = Thing(), toolbar = Thing()
        var fading = ExtensionPopupActivityTracker()
        let fadingPopup = Thing(), refusedPopup = Thing()
        #expect(same(fading.place(popup: fadingPopup, control: clicked), [(clicked, .loading)])
                  && same(fading.place(popup: refusedPopup, control: toolbar), [(clicked, nil), (toolbar, .loading)])
                  && same(fading.end(popup: refusedPopup), [(toolbar, nil)]))
        #expect(same(fading.place(popup: fadingPopup, control: clicked), []))
    }

    @Test func movingALoadingPopupMovesItsLoadingLight() {
        let second = Thing(), toolbar = Thing(), pinned = Thing()
        var tracker = ExtensionPopupActivityTracker()
        _ = tracker.place(popup: second, control: toolbar)
        #expect(same(tracker.place(popup: second, control: pinned), [(toolbar, nil), (pinned, .loading)]))
    }

    @Test func movingAnOpenPopupKeepsItsNewButtonOpen() {
        let second = Thing(), pinned = Thing(), siteControls = Thing()
        var tracker = ExtensionPopupActivityTracker()
        _ = tracker.place(popup: second, control: pinned)
        _ = tracker.reveal(popup: second)
        #expect(same(tracker.place(popup: second, control: siteControls), [(pinned, nil), (siteControls, .open)]))
    }

    @Test func reanchoringWithoutAButtonClearsTheOldLight() {
        let second = Thing(), siteControls = Thing()
        var tracker = ExtensionPopupActivityTracker()
        _ = tracker.place(popup: second, control: siteControls)
        #expect(same(tracker.place(popup: second, control: nil), [(siteControls, nil)]))
    }

    @Test func anOpenPopupRelightsWhenItGetsAnAnchor() {
        let second = Thing(), pinned = Thing()
        var tracker = ExtensionPopupActivityTracker()
        _ = tracker.place(popup: second, control: nil)
        _ = tracker.reveal(popup: second)
        #expect(same(tracker.place(popup: second, control: pinned), [(pinned, .open)]))
    }

    @Test func closingThePopupClearsItsButton() {
        let second = Thing(), pinned = Thing()
        var tracker = ExtensionPopupActivityTracker()
        _ = tracker.place(popup: second, control: pinned)
        #expect(same(tracker.end(popup: second), [(pinned, nil)]))
    }

    @Test func aClosedPopupCannotRelightItsButton() {
        let second = Thing(), pinned = Thing()
        var tracker = ExtensionPopupActivityTracker()
        _ = tracker.place(popup: second, control: pinned)
        _ = tracker.end(popup: second)
        #expect(!tracker.tracks(second) && same(tracker.end(popup: second), []))
        #expect(same(tracker.place(popup: second, control: pinned), []) && same(tracker.reveal(popup: second), []))
    }

    @Test func aNewPopupFromTheSameButtonRestartsItsLoadingLight() {
        let third = Thing(), fourth = Thing(), clicked = Thing()
        var tracker = ExtensionPopupActivityTracker()
        _ = tracker.place(popup: third, control: clicked)
        _ = tracker.reveal(popup: third)
        #expect(same(tracker.place(popup: fourth, control: clicked), [(clicked, .loading)]))
    }

    @Test func closingBeforeRevealClearsTheLoadingLight() {
        let fourth = Thing(), clicked = Thing()
        var tracker = ExtensionPopupActivityTracker()
        _ = tracker.place(popup: fourth, control: clicked)
        #expect(same(tracker.end(popup: fourth), [(clicked, nil)]))
    }

    @Test func anUnanchoredPopupNeverLightsAButton() {
        var tracker = ExtensionPopupActivityTracker()
        let unanchored = Thing()
        #expect(same(tracker.place(popup: unanchored, control: nil), []))
        #expect(same(tracker.reveal(popup: unanchored), []) && same(tracker.end(popup: unanchored), []))
    }

    @Test func aRemovedButtonIsNeverTouchedAgain() {
        var tracker = ExtensionPopupActivityTracker()
        let fleeting = Thing()
        do {
            let removed = Thing()
            #expect(same(tracker.place(popup: fleeting, control: removed), [(removed, .loading)]))
        }
        #expect(same(tracker.end(popup: fleeting), []))
    }
}
