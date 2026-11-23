import AppKit
import ParcEngine
import ParcEngineDoubles
import Testing
@testable import ParcCore
@testable import ParcNotes
@testable import ParcEasels

struct EaselPageBoardZoomTests {
    private typealias Board = EaselPagePoolTestsSupport.Board

    @MainActor private func settle(_ surface: NoteEmbedSurface, at scale: CGFloat) {
        surface.setBoardScale(scale)
        surface.needsLayout = true
        surface.layoutSubtreeIfNeeded()
    }

    @MainActor @Test(arguments: [0.25, 0.5, 1, 2, 3] as [CGFloat])
    func thePageHolderMeasuresScreenPointsAtEveryBoardZoom(_ scale: CGFloat) throws {
        let board = try Board(.webpage)
        defer { board.close() }
        let (surface, _, _) = try board.open()
        settle(surface, at: scale)
        let frame = surface.frame.size
        #expect(surface.bounds.size == NSSize(width: frame.width * scale, height: frame.height * scale))
        #expect(surface.convert(NSRect(origin: .zero, size: surface.bounds.size), to: surface.superview).size == frame)
        surface.setFrameSize(NSSize(width: 600, height: 400))
        #expect(surface.bounds.size == NSSize(width: 600 * scale, height: 400 * scale))
        let area = surface.pageArea
        #expect(abs(area.visible.width - 600) < 0.001)
        #expect(abs(area.visible.height - (400 - NoteEmbedSurface.headerHeight / scale)) < 0.001)
    }

    @MainActor @Test
    func aWebpageKeepsItsLayoutWidthByZoomingWithTheBoard() throws {
        let board = try Board(.webpage)
        defer { board.close() }
        let (surface, engine, _) = try board.open()
        surface.layoutSubtreeIfNeeded()
        #expect(engine.liveDisplayZoom == 0)
        settle(surface, at: 0.5)
        #expect(engine.liveDisplayZoom == 0.5)
        engine.siteZoom = 1.25
        settle(surface, at: 2)
        #expect(engine.liveDisplayZoom == 2.5)
        settle(surface, at: 1)
        #expect(engine.liveDisplayZoom == 1.25)
        #expect(surface.browser.frame.width == surface.bounds.width)
    }

    @MainActor @Test(arguments: [0.5, 2] as [CGFloat])
    func aFullPageCaptureKeepsItsCapturedLayoutAtEveryBoardZoom(_ scale: CGFloat) throws {
        let layout = try #require(EaselCaptureGeometry.captured(viewport: .init(x: 1280, y: 800), scroll: .init(x: 0, y: 0),
            region: .init(x: 0, y: 0, width: 1280, height: 800), scrollContainers: [], fullPage: true))
        let board = try Board(.capture, layout: layout)
        defer { board.close() }
        let (surface, engine, _) = try board.open()
        board.select()
        settle(surface, at: scale)
        #expect(abs(engine.liveDisplayZoom - 480 * Double(scale) / 1280) < 0.000001)
        #expect(abs(surface.pageArea.visible.width - 480) < 0.001)
    }

    @MainActor @Test(arguments: [0.5, 2] as [CGFloat])
    func aRegionCaptureFramesTheSameRegionAtEveryBoardZoom(_ scale: CGFloat) throws {
        let board = try Board(.capture)
        defer { board.close() }
        let (surface, engine, _) = try board.open()
        board.select()
        surface.needsLayout = true
        surface.layoutSubtreeIfNeeded()
        let width = engine.positionedWidth, visible = surface.pageArea.visible
        try #require(width > 0)
        settle(surface, at: scale)
        #expect(abs(engine.positionedWidth - width * Double(scale)) < 0.001)
        #expect(engine.positionedRegion == NSRect(x: 20, y: 40, width: 300, height: 200))
        #expect(surface.browser.frame.size == NSSize(width: 1000, height: 700))
        #expect(engine.liveDisplayZoom == 0)
        let next = surface.pageArea.visible
        #expect(abs(next.width / next.height - visible.width / visible.height) < 0.01)
    }
}
