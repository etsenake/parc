import AppKit
import Testing
@testable import ParcCore
@testable import ParcLibrary
@testable import ParcNotes

@MainActor
struct CaptureSubmenuTests {
    private final class FlippedHost: NSView { override var isFlipped: Bool { true } }

    private func presented() throws -> (CapturePalette, () -> DispatchWorkItem?) {
        _ = NSApplication.shared
        let palette = CapturePalette()
        var scheduled: [DispatchWorkItem] = []
        palette.scheduleSwitch = { _, work in scheduled.append(work) }
        palette.update {
            $0.easels = [CaptureEaselDestination(id: UUID(), title: "Board", lastActive: nil)]
            $0.notesAvailable = true
            $0.notes = [CaptureNoteDestination(url: URL(fileURLWithPath: "/fixture/Journal.md"), title: "Journal",
                                               icon: nil, lastActive: nil, modifiedAt: Date(timeIntervalSince1970: 0))]
        }
        let host = FlippedHost(frame: NSRect(x: 0, y: 0, width: 1400, height: 900))
        palette.place(NSRect(x: 700, y: 20, width: 273, height: 700), image: NSRect(x: 20, y: 20, width: 660, height: 500), in: host)
        palette.view.layoutSubtreeIfNeeded()
        return (palette, { scheduled.last })
    }

    private func hover(_ id: String, in palette: CapturePalette) throws {
        let item = try #require(palette.view.list.items.first { $0.id == id })
        palette.view.list.highlight(id: id, animated: false)
        palette.view.list.onHighlight?(item)
    }

    @Test func crossingTheNoteRowOnTheWayIntoTheEaselListKeepsIt() throws {
        let (palette, lastScheduled) = try presented()
        try hover("easels", in: palette)
        #expect(palette.openSubmenu == .easels)
        try hover("notes", in: palette)
        #expect(palette.openSubmenu == .easels)
        let pending = try #require(lastScheduled())
        palette.submenuView?.onPointerInside?()
        #expect(pending.isCancelled)
        pending.perform()
        #expect(palette.openSubmenu == .easels)
        #expect(palette.view.list.highlightedItem?.id == "easels")
    }

    @Test func crossingRetakeOnTheWayInDoesNotCloseTheList() throws {
        let (palette, lastScheduled) = try presented()
        try hover("easels", in: palette)
        try hover("retake", in: palette)
        let pending = try #require(lastScheduled())
        palette.submenuView?.onPointerInside?()
        pending.perform()
        #expect(palette.openSubmenu == .easels)
    }

    @Test func restingOnAnotherRowSwitchesAfterThePause() throws {
        let (palette, lastScheduled) = try presented()
        try hover("easels", in: palette)
        try hover("notes", in: palette)
        try #require(lastScheduled()).perform()
        #expect(palette.openSubmenu == .notes)
        try hover("copy", in: palette)
        try #require(lastScheduled()).perform()
        #expect(palette.openSubmenu == nil)
    }

    @Test func aFailureShowsProminentlyInsideTheOpenList() throws {
        let (palette, _) = try presented()
        try hover("easels", in: palette)
        let plain = palette.view.naturalHeight
        palette.setError("That picture is a bit big for an Easel.")
        #expect(palette.view.errorText == "That picture is a bit big for an Easel.")
        #expect(palette.submenuView?.errorText == "That picture is a bit big for an Easel.")
        #expect(palette.view.naturalHeight > plain)
        palette.closeSubmenu()
        try hover("notes", in: palette)
        #expect(palette.submenuView?.errorText == "That picture is a bit big for an Easel.")
        palette.reset()
        #expect(palette.view.errorText == nil)
        try hover("easels", in: palette)
        #expect(palette.submenuView?.errorText == nil)
    }
}
