import AppKit
import ParcEngine
import ParcEngineDoubles
import Testing
@testable import Parc
@testable import ParcCore
@testable import ParcNotes
@testable import ParcEasels

struct EaselPagePoolTestsSnapshot {
    private typealias Board = EaselPagePoolTestsSupport.Board

    @MainActor @Test
    func snapshotCollectionKeepsThePageGeometry() throws {
        let board = try Board()
        defer { board.close() }
        let (surface, engine, _) = try board.open()
        var collected: [UUID: EaselPageSnapshot]?
        try #require(board.canvas.collectExportPages { collected = $0 })
        let image = NSImage(size: NSSize(width: 480, height: 288))
        engine.reply(withSnapshot: image)
        let snapshots = try #require(collected)
        let snapshot = try #require(snapshots[board.item.id])
        #expect(engine.snapshotRequests == 1)
        #expect(snapshot.image === image)
        #expect(snapshot.pageFrame == surface.pageArea.page && snapshot.visibleFrame == surface.pageArea.visible)
        #expect(snapshot.pageFrame.minY == EmbeddedPageHeader.height)
    }

    @MainActor @Test
    func snapshotCollectionRejectsASecondCollection() throws {
        let board = try Board()
        defer { board.close() }
        let (_, engine, _) = try board.open()
        try #require(board.canvas.collectExportPages { _ in })
        #expect(!board.canvas.collectExportPages { _ in Issue.record("Unexpected second snapshot delivery") })
        let image = NSImage(size: NSSize(width: 480, height: 288))
        engine.reply(withSnapshot: image)
        #expect(engine.snapshotRequests == 1)
    }

    @MainActor @Test
    func snapshotExportDrawsPagePixelsBelowTheControls() throws {
        let board = try Board()
        defer { board.close() }
        let (_, engine, _) = try board.open()
        board.canvas.appearance = NSAppearance(named: .aqua)
        let red = NSImage(size: NSSize(width: 480, height: 288), flipped: false) { rect in
            NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 1).setFill()
            rect.fill()
            return true
        }
        var collected: [UUID: EaselPageSnapshot]?
        try #require(board.canvas.collectExportPages { collected = $0 })
        engine.reply(withSnapshot: red)
        let pages = try #require(collected)
        let image = try #require(board.canvas.exportImage(backingScale: 1, pages: pages))
        let provider = try #require(image.dataProvider)
        let bytes = try #require(provider.data) as Data
        func rgb(x: Int, y: Int) -> [UInt8] {
            let position = y * image.bytesPerRow + x * 4
            return Array(bytes[position..<(position + 3)])
        }
        #expect(rgb(x: 280, y: 200) == [255, 0, 0])
        #expect(rgb(x: 280, y: 30) == [255, 255, 255])
    }

    @MainActor @Test
    func aSnapshotReplyWithoutPixelsLeavesThatPageOutOfTheCollection() throws {
        let board = try Board()
        defer { board.close() }
        let (_, first, _) = try board.open()
        let secondItem = try board.appendWebpage()
        let (_, second, _) = try board.open(secondItem)
        var collected: [UUID: EaselPageSnapshot]?
        try #require(board.canvas.collectExportPages { collected = $0 })
        first.reply(withSnapshot: NSImage(size: NSSize(width: 10, height: 10)))
        second.reply(withSnapshot: nil)
        let pages = try #require(collected)
        #expect(Set(pages.keys) == [board.item.id])
    }

    @MainActor @Test(arguments: [false, true])
    func anUnsupportedOrRefusedSnapshotLeavesTheSavedCard(_ supports: Bool) throws {
        let board = try Board()
        defer { board.close() }
        let (_, engine, _) = try board.open()
        engine.supportsSnapshot = supports
        engine.refusesSnapshot = true
        var snapshots: [UUID: EaselPageSnapshot]?
        try #require(board.canvas.collectExportPages { snapshots = $0 })
        #expect(snapshots?.isEmpty == true)
        #expect(engine.snapshotRequests == (supports ? 1 : 0))
    }

    @MainActor @Test
    func aSnapshotDeadlineDeliversRepliesReceivedSoFar() throws {
        let board = try Board()
        defer { board.close() }
        let (_, first, _) = try board.open()
        let secondItem = try board.appendWebpage()
        _ = try board.open(secondItem)
        var replies: [[UUID: EaselPageSnapshot]] = []
        try #require(board.canvas.collectExportPages { replies.append($0) })
        first.reply(withSnapshot: NSImage(size: NSSize(width: 10, height: 10)))
        #expect(replies.isEmpty)

        board.deadlines.runPending()
        let snapshots = try #require(replies.first)
        #expect(Set(snapshots.keys) == [board.item.id])
    }

    @MainActor @Test
    func aSnapshotDeadlineIgnoresLateReplies() throws {
        let board = try Board()
        defer { board.close() }
        let (_, first, _) = try board.open()
        let secondItem = try board.appendWebpage()
        let (_, second, _) = try board.open(secondItem)
        var replies: [[UUID: EaselPageSnapshot]] = []
        try #require(board.canvas.collectExportPages { replies.append($0) })
        first.reply(withSnapshot: NSImage(size: NSSize(width: 10, height: 10)))
        board.deadlines.runPending()
        second.reply(withSnapshot: NSImage(size: NSSize(width: 10, height: 10)))
        #expect(replies.count == 1)
    }
}
