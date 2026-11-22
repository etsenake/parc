import CoreGraphics
import Foundation
import Testing
@testable import ParcCore

struct NotePDFBlockTestsInteractionTests {
    private let middle = NotePDFScrollLatch.Room(up: true, down: true)
    private let bottom = NotePDFScrollLatch.Room(up: true, down: false)

    private func handedOverLatch() -> NotePDFScrollLatch {
        var latch = NotePDFScrollLatch()
        _ = latch.receive(.began, deltaX: 0, deltaY: -4, time: 0, room: middle)
        _ = latch.receive(.changed, deltaX: 0, deltaY: -8, time: 0.01, room: middle)
        _ = latch.receive(.changed, deltaX: 0, deltaY: -8, time: 0.02, room: bottom)
        _ = latch.receive(.changed, deltaX: 0, deltaY: 8, time: 0.03, room: middle)
        _ = latch.receive(.momentum, deltaX: 0, deltaY: -3, time: 0.1, room: bottom)
        return latch
    }

    @Test
    func aPDFKeepsScrollingUntilTheNoteTakesOver() {
        var latch = NotePDFScrollLatch()
        #expect(latch.receive(.began, deltaX: 0, deltaY: -4, time: 0, room: middle) == .pdf, "scrolling over a PDF scrolls the PDF")
        #expect(latch.receive(.changed, deltaX: 0, deltaY: -8, time: 0.01, room: middle) == .pdf, "and keeps doing so")
        #expect(latch.receive(.changed, deltaX: 0, deltaY: -8, time: 0.02, room: bottom) == .noteHandedOver, "at the last page the note takes over")
        #expect(latch.receive(.changed, deltaX: 0, deltaY: 8, time: 0.03, room: middle) == .noteHandedOver, "the rest of the gesture stays with the note")
        #expect(latch.receive(.momentum, deltaX: 0, deltaY: -3, time: 0.1, room: bottom) == .noteHandedOver, "momentum carries on in the note")
    }

    @Test
    func aNewGestureAtTheBottomStaysWithTheNote() {
        var latch = handedOverLatch()
        #expect(latch.receive(.began, deltaX: 0, deltaY: -4, time: 1, room: bottom) == .note, "a new gesture at the bottom scrolls the note natively")
        #expect(latch.receive(.changed, deltaX: 0, deltaY: 4, time: 1.01, room: middle) == .note, "once latched, it stays with the note")
    }

    @Test
    func aGestureWaitsForDirectionBeforeScrollingTheNote() {
        let fits = NotePDFScrollLatch.Room()
        var latch = handedOverLatch()
        _ = latch.receive(.began, deltaX: 0, deltaY: -4, time: 1, room: bottom)
        _ = latch.receive(.changed, deltaX: 0, deltaY: 4, time: 1.01, room: middle)
        #expect(latch.receive(.began, deltaX: 0, deltaY: 0, time: 2, room: fits) == .pdf, "no delta yet decides nothing")
        #expect(latch.target == nil, "the latch waits for a direction")
        #expect(latch.receive(.changed, deltaX: 0, deltaY: -2, time: 2.01, room: fits) == .note, "a PDF that fits hands scrolling to the note")
    }

    @Test
    func aZoomedPDFPansSideways() {
        var latch = NotePDFScrollLatch()
        #expect(latch.receive(.began, deltaX: 6, deltaY: 1, time: 3, room: .init(up: true, down: true, left: true, right: true)) == .pdf, "zoomed PDFs pan sideways")
    }

    @Test
    func anUnzoomedPDFLetsSidewaysSwipesThrough() {
        var latch = NotePDFScrollLatch()
        _ = latch.receive(.began, deltaX: 6, deltaY: 1, time: 3, room: .init(up: true, down: true, left: true, right: true))
        #expect(latch.receive(.began, deltaX: 6, deltaY: 1, time: 4, room: middle) == .note, "unzoomed PDFs let sideways swipes through")
    }

    @Test
    func aWheelRunHandsOverAtTheEndAndResetsAfterAPause() {
        var wheel = NotePDFScrollLatch()
        #expect(wheel.receive(.discrete, deltaX: 0, deltaY: -1, time: 10, room: middle) == .pdf, "wheel ticks scroll the PDF")
        #expect(wheel.receive(.discrete, deltaX: 0, deltaY: -1, time: 10.1, room: bottom) == .noteHandedOver, "a wheel run hands over at the end")
        #expect(wheel.receive(.discrete, deltaX: 0, deltaY: 1, time: 10.2, room: middle) == .noteHandedOver, "the run stays handed over")
        #expect(wheel.receive(.discrete, deltaX: 0, deltaY: 1, time: 11, room: middle) == .pdf, "a pause starts a fresh run")
    }

    @Test
    func aGestureEndsWhereItStarted() {
        var ending = NotePDFScrollLatch()
        _ = ending.receive(.began, deltaX: 0, deltaY: -2, time: 0, room: middle)
        #expect(ending.receive(.ended, deltaX: 0, deltaY: 0, time: 0.1, room: bottom) == .pdf, "the end of a gesture goes where it started")
    }

    @Test
    func resetForgetsTheScrollTarget() {
        var ending = NotePDFScrollLatch()
        _ = ending.receive(.began, deltaX: 0, deltaY: -2, time: 0, room: middle)
        _ = ending.receive(.ended, deltaX: 0, deltaY: 0, time: 0.1, room: bottom)
        ending.reset()
        #expect(ending.target == nil, "reset forgets the latch")
    }

    @Test @MainActor
    func turningAFileIntoAPDFKeepsItsProperties() {
        var file = NoteBlock(.file)
        file.props.source = "Attachments/report.pdf"
        file.props.caption = NoteText("Numbers")
        file.props.width = 0.5
        file.props.alignment = .left
        let session = NotePageSession(page: NotePage(blocks: [file]))
        session.turnInto([file.id], kind: .pdf)
        let turned = session.page.blocks[0]
        #expect(turned.kind == .pdf && turned.props.source == file.props.source && turned.props.caption == file.props.caption
               && turned.props.width == 0.5 && turned.props.alignment == .left, "a file turns into a PDF and keeps everything")
    }

    @Test @MainActor
    func undoRestoresTheFileAfterTurningItIntoAPDF() {
        var file = NoteBlock(.file)
        file.props.source = "Attachments/report.pdf"
        file.props.caption = NoteText("Numbers")
        file.props.width = 0.5
        file.props.alignment = .left
        let session = NotePageSession(page: NotePage(blocks: [file]))
        session.turnInto([file.id], kind: .pdf)
        session.undo()
        #expect(session.page.blocks[0].kind == .file, "undo turns it back")
    }

    @Test
    func aPDFIsCaptionedMedia() {
        #expect(NoteBlockKind.pdf.isMedia && NoteBlockKind.pdf.hasCaption && !NoteBlockKind.pdf.hasText, "PDFs are captioned media")
    }
}
