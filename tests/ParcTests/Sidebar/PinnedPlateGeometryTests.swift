import AppKit
import Testing
@testable import Parc
@testable import ParcKit
@testable import ParcSidebar

private final class PlateCanvas: NSView {
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        NSColor(srgbRed: 99 / 255, green: 175 / 255, blue: 129 / 255, alpha: 1).setFill()
        bounds.fill()
    }
}

private struct MeasuredPlate {
    var top: CGFloat
    var bottom: CGFloat
    var leading: CGFloat
    var trailing: CGFloat
    var corner: [CGFloat]
    var height: CGFloat { bottom - top }

    func matches(_ other: MeasuredPlate) -> Bool {
        let close = { (a: CGFloat, b: CGFloat) in abs(a - b) <= 0.5 }
        return close(top, other.top) && close(bottom, other.bottom) && close(leading, other.leading)
            && close(trailing, other.trailing) && corner.count == other.corner.count
            && zip(corner, other.corner).allSatisfy { abs($0 - $1) <= 0.25 }
    }
}

@MainActor
struct PinnedPlateGeometryTests {
    private let scale: CGFloat = 2
    private let listX: CGFloat = 8
    private let listY: CGFloat = 10
    private let listWidth: CGFloat = 212
    private let probeX: CGFloat = 150

    private func measure(_ content: NSView, row: SidebarChromeLayout.TablistRow, prepare: (NSView) -> Void) -> (plate: MeasuredPlate?, slot: NSRect) {
        let canvas = PlateCanvas(frame: NSRect(x: 0, y: 0, width: listX * 2 + listWidth, height: 80))
        canvas.appearance = NSAppearance(named: .aqua)
        let outline = SidebarOutlineView(frame: NSRect(x: listX, y: listY, width: listWidth, height: 60))
        canvas.addSubview(outline)
        outline.reload([SidebarOutlineEntry(key: "subject", content: content, row: row)])
        outline.layoutSubtreeIfNeeded()
        prepare(content)
        let slot = canvas.convert(outline.rowFrames()["subject"] ?? .zero, from: outline)
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(canvas.bounds.width * scale), pixelsHigh: Int(canvas.bounds.height * scale),
                                      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                      bytesPerRow: 0, bitsPerPixel: 0)!
        bitmap.size = canvas.bounds.size
        canvas.cacheDisplay(in: canvas.bounds, to: bitmap)
        func pixel(_ x: Int, _ y: Int) -> [CGFloat] {
            let color = bitmap.colorAt(x: x, y: y) ?? .clear
            return [color.redComponent, color.greenComponent, color.blueComponent]
        }
        let ground = pixel(1, 1)
        func delta(_ x: Int, _ y: Int) -> CGFloat { zip(pixel(x, y), ground).map { abs($0 - $1) }.max() ?? 0 }
        let marked: (Int, Int) -> Bool = { delta($0, $1) >= 2 / 255 }
        let column = Int((listX + probeX) * scale)
        let rows = (0..<bitmap.pixelsHigh).filter { marked(column, $0) }
        guard let first = rows.first, let last = rows.last else { return (nil, slot) }
        let middle = (first + last) / 2
        let columns = (0..<bitmap.pixelsWide).filter { marked($0, middle) }
        guard let leading = columns.first, let trailing = columns.last else { return (nil, slot) }
        let radius = Int(SidebarRowAppearance.cornerRadius * scale)
        let corner: [CGFloat] = (first..<min(last, first + radius)).map { y in
            let full = delta(column, y)
            guard full > 0 else { return CGFloat(radius) / scale }
            let uncovered = (leading..<(leading + radius)).reduce(CGFloat(0)) { sum, x in sum + max(0, 1 - delta(x, y) / full) }
            return uncovered / scale
        }
        return (MeasuredPlate(top: CGFloat(first) / scale - slot.minY, bottom: CGFloat(last + 1) / scale - slot.minY,
                              leading: CGFloat(leading) / scale - listX, trailing: CGFloat(trailing + 1) / scale - listX, corner: corner), slot)
    }

    private func press(_ view: NSView) {
        let event = NSEvent.mouseEvent(with: .leftMouseDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
                                       context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        view.mouseDown(with: event)
    }

    private func pinnedHeader(collapsed: Bool = false) -> SidebarPinnedHeaderView {
        let header = SidebarPinnedHeaderView()
        header.applyStyle(dark: false, accent: nil)
        header.update(.init(collapsed: collapsed, showsIcons: false, count: collapsed ? 6 : 0), fallbacks: [:], animated: false)
        return header
    }

    private func hoveredNewTab(_ view: NSView) {
        (view.subviews.first { $0 is SidebarRowBackgroundView } as? SidebarRowBackgroundView)?.appearanceState.hovered = true
    }

    private var slotRow: SidebarChromeLayout.TablistRow { SidebarChromeLayout.TablistSlot.pinnedSectionHeader.row }

    private func standard() -> (plate: MeasuredPlate?, slot: NSRect) {
        measure(SidebarNewTabRow(dark: false) {}, row: SidebarChromeLayout.TablistSlot.newTab.row, prepare: hoveredNewTab)
    }

    @Test func theMeasuredNewTabPlateIsTheStandardThirtySixPointRowEdgeToEdge() throws {
        let reference = try #require(standard().plate)
        #expect(reference.height == SidebarChromeLayout.tablistVisibleRowHeight)
        #expect(reference.leading == 0)
        #expect(reference.trailing == listWidth)
    }

    @Test func thePinnedHeadersPlateIsExactlyAsTallAsTheNewTabRows() throws {
        let reference = try #require(standard().plate)
        let plate = try #require(measure(pinnedHeader(), row: slotRow, prepare: press).plate)
        #expect(plate.height == reference.height)
    }

    @Test func thePinnedHeadersPlateSitsSpansAndRoundsLikeTheNewTabRows() throws {
        let reference = try #require(standard().plate)
        let plate = try #require(measure(pinnedHeader(), row: slotRow, prepare: press).plate)
        #expect(plate.matches(reference))
    }

    @Test func thePinnedHeaderTakesAStandardRowSlot() {
        let pressed = measure(pinnedHeader(), row: slotRow, prepare: press)
        #expect(pressed.slot.height == standard().slot.height)
    }

    @Test func aFoldedHeaderWithItsCountKeepsTheStandardPlate() throws {
        let reference = try #require(standard().plate)
        let folded = measure(pinnedHeader(collapsed: true), row: slotRow, prepare: press)
        #expect(folded.plate.map { $0.matches(reference) } == true)
    }

    @Test func aRestingHeaderPaintsNoPlate() {
        #expect(measure(pinnedHeader(), row: slotRow) { _ in }.plate == nil)
    }

    @Test func negativeControlAHeaderSqueezedIntoATwentySixPointSlotIsCaught() throws {
        let reference = try #require(standard().plate)
        let short = measure(pinnedHeader(), row: .accessory(height: 26), prepare: press)
        #expect(short.plate.map { $0.height != reference.height && !$0.matches(reference) } == true)
    }

    @Test func negativeControlAFullHeightPlateWithTheWrongCornersIsCaught() throws {
        let reference = try #require(standard().plate)
        let sharp = measure(pinnedHeader(), row: slotRow) { view in press(view); view.layer?.cornerRadius = 6 }
        #expect(sharp.plate.map { $0.height == reference.height && !$0.matches(reference) } == true)
    }
}
