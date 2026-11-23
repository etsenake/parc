import Foundation
import Testing
@testable import ParcCore

struct NoteRangeDeletionTests {
    @Test func aSelectionEndingPastTheEndOfItsLastBlockStillDeletes() {
        var page = NotePage(blocks: [.paragraph("one"), .paragraph("two"), .paragraph("three")])
        let ids = page.blocks.map(\.id)
        let deleted = page.deleteRange(from: NotePosition(ids[0], 2), to: NotePosition(ids[2], 99))
        #expect(deleted)
        #expect(page.plainText == "on")
    }

    @Test func aSelectionStartingPastTheEndOfItsFirstBlockStillDeletes() {
        var page = NotePage(blocks: [.paragraph("one"), .paragraph("two"), .paragraph("three")])
        let ids = page.blocks.map(\.id)
        let deleted = page.deleteRange(from: NotePosition(ids[0], 99), to: NotePosition(ids[2], 2))
        #expect(deleted)
        #expect(page.plainText == "oneree")
    }

    @Test func offsetsPastTheEndOfCaptionsAreClamped() {
        var image = NoteBlock(.image)
        var props = image.props
        props.caption = NoteText("caption")
        image.props = props
        var page = NotePage(blocks: [image, .paragraph("two"), .paragraph("three")])
        let ids = page.blocks.map(\.id)
        let deleted = page.deleteRange(from: NotePosition(ids[0], 99, field: .caption), to: NotePosition(ids[2], 99))
        #expect(deleted)
        #expect(page.block(ids[0])?.props.caption.plainText == "caption")
    }

    @Test func negativeOffsetsAreClampedToTheStart() {
        var page = NotePage(blocks: [.paragraph("one"), .paragraph("two")])
        let ids = page.blocks.map(\.id)
        let deleted = page.deleteRange(from: NotePosition(ids[0], -5), to: NotePosition(ids[1], -5))
        #expect(deleted)
        #expect(page.plainText == "two")
    }
}
