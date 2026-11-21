import Foundation
import Testing
@testable import ParcCore

@MainActor struct NoteEmbedInputTests {
    @Test func theFirstClickOnASleepingPageActivates() {
        let a = UUID(), b = UUID()
        #expect(NoteEmbedPointerDecision.decide(pageUnderPointer: a, active: nil, insideActive: false) == .activate(a), "the first click on a sleeping page activates it")
        #expect(NoteEmbedPointerDecision.decide(pageUnderPointer: b, active: a, insideActive: false) == .activate(b), "clicking another page hands activation over")
        #expect(NoteEmbedPointerDecision.decide(pageUnderPointer: a, active: a, insideActive: true) == .none, "clicks inside the active page just reach the page")
        #expect(NoteEmbedPointerDecision.decide(pageUnderPointer: nil, active: a, insideActive: false) == .finish, "clicking the note leaves the page")
        #expect(NoteEmbedPointerDecision.decide(pageUnderPointer: nil, active: a, insideActive: true) == .none, "the active page's header keeps it active")
        #expect(NoteEmbedPointerDecision.decide(pageUnderPointer: nil, active: nil, insideActive: false) == .none, "ordinary note clicks change nothing")
    }

    @Test func gesturesOverTheNoteScrollTheNote() {
        let page = UUID()
        var latch = NoteEmbedScrollLatch()
        #expect(latch.receive(.began, deltaX: 0, deltaY: 0, time: 1, pageUnderPointer: nil) == .native, "gestures over the note scroll the note")
        #expect(latch.receive(.changed, deltaX: 0, deltaY: -8, time: 1.01, pageUnderPointer: page) == .native, "a page sliding under the pointer doesn't steal the note's gesture")
        #expect(latch.latchedPage == nil, "the note gesture isn't latched to a page")
        #expect(latch.receive(.momentum, deltaX: 0, deltaY: -4, time: 1.1, pageUnderPointer: page) == .native, "momentum stays with the note")
        #expect(latch.receive(.began, deltaX: 0, deltaY: 0, time: 2, pageUnderPointer: page) == .page, "gestures starting on a page go to the page")
        #expect(latch.receive(.changed, deltaX: 0, deltaY: -8, time: 2.01, pageUnderPointer: nil) == .page, "the page keeps its gesture")
        #expect(latch.latchedPage == page, "the gesture is latched to the page under the pointer")
    }

    @Test func acknowledgementsFromThePreviousGestureAreIgnored() {
        let page = UUID()
        var latch = NoteEmbedScrollLatch()
        _ = latch.receive(.began, deltaX: 0, deltaY: 0, time: 1, pageUnderPointer: page)
        _ = latch.receive(.changed, deltaX: 0, deltaY: -10, time: 1.01, pageUnderPointer: nil)
        let hoisted33 = !latch.pageScrollUpdated(consumed: false)
        #expect(hoisted33, "acknowledgements from the previous gesture are ignored")
        latch.pageScrollBegan(momentum: false)
        let hoisted35 = !latch.pageScrollUpdated(consumed: true)
        #expect(hoisted35, "a page that scrolls keeps the gesture")
        #expect(latch.receive(.changed, deltaX: 0, deltaY: -10, time: 1.02, pageUnderPointer: nil) == .page, "still the page's")
        let hoisted37 = latch.pageScrollUpdated(consumed: false)
        #expect(hoisted37, "the page reaching its edge chains to the note")
        #expect(latch.receive(.changed, deltaX: 0, deltaY: -10, time: 1.03, pageUnderPointer: nil) == .note, "the rest scrolls the note")
        #expect(latch.receive(.ended, deltaX: 0, deltaY: 0, time: 1.04, pageUnderPointer: nil) == .page, "the page still hears the gesture end")
        #expect(latch.receive(.momentum, deltaX: 0, deltaY: -6, time: 1.05, pageUnderPointer: nil) == .note, "momentum keeps scrolling the note")
        #expect(latch.receive(.momentumEnded, deltaX: 0, deltaY: 0, time: 1.2, pageUnderPointer: nil) == .note, "momentum ends on the note")
        #expect(latch.receive(.began, deltaX: 0, deltaY: 0, time: 2, pageUnderPointer: page) == .page && !latch.handedOver, "a new gesture on the page starts with the page again")

        var sideways = NoteEmbedScrollLatch()
        _ = sideways.receive(.began, deltaX: 0, deltaY: 0, time: 1, pageUnderPointer: page)
        sideways.pageScrollBegan(momentum: false)
        _ = sideways.receive(.changed, deltaX: -12, deltaY: 1, time: 1.01, pageUnderPointer: nil)
        let hoisted48 = !sideways.pageScrollUpdated(consumed: false)
        #expect(hoisted48, "sideways overscroll stays with the page")
    }

    @Test func scrollingDownMovesAFlippedNoteDown() {
        #expect(NoteEmbedScrollLatch.noteOffset(100, delta: -10, flipped: true) == 110, "scrolling down moves a flipped note down")
        #expect(NoteEmbedScrollLatch.noteOffset(100, delta: -10, flipped: false) == 90, "scrolling down moves an unflipped note up")
        #expect(NoteEmbedScrollLatch.noteOffset(100, delta: .nan, flipped: true) == 100, "broken deltas change nothing")
    }

    @Test func aWheelClickOnAPageGoes() {
        let page = UUID()
        var latch = NoteEmbedScrollLatch()
        #expect(latch.receive(.discrete, deltaX: 0, deltaY: -1, time: 1, pageUnderPointer: page) == .page, "a wheel click on a page goes to it")
        let hoisted61 = latch.pageScrollUpdated(consumed: false)
        #expect(hoisted61, "wheel runs don't wait for a gesture start")
        #expect(latch.receive(.discrete, deltaX: 0, deltaY: -1, time: 1.1, pageUnderPointer: page) == .note, "the rest of the run scrolls the note")
        #expect(!latch.startsGesture(.discrete, time: 1.3), "quick clicks continue the run")
        #expect(latch.startsGesture(.discrete, time: 1.7), "a pause starts a new run")
        #expect(latch.receive(.discrete, deltaX: 0, deltaY: 1, time: 1.7, pageUnderPointer: page) == .page, "the new run tries the page first")
    }

    @Test func anEscapeThePageDidntUseGoesBack() {
        var confirmation = NoteEmbedEscapeConfirmation()
        let hoisted70 = confirmation.receive(prefersConfirmation: false, now: 1)
        #expect(hoisted70, "an Escape the page didn't use goes back to the note")
        let hoisted71 = !confirmation.receive(prefersConfirmation: true, now: 2)
        #expect(hoisted71, "an Escape in a field asks for another press")
        let hoisted72 = confirmation.receive(prefersConfirmation: true, now: 2.5)
        #expect(hoisted72, "a second press within a second goes back")
        let hoisted73 = !confirmation.receive(prefersConfirmation: true, now: 4)
        #expect(hoisted73, "the next field Escape asks again")
        let hoisted74 = !confirmation.receive(prefersConfirmation: true, now: 5.5)
        #expect(hoisted74, "a slow second press asks again")
    }
}
