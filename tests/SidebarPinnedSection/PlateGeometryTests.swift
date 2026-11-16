import AppKit

@MainActor final class PlateCanvas: NSView {
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        NSColor(srgbRed: 99 / 255, green: 175 / 255, blue: 129 / 255, alpha: 1).setFill()
        bounds.fill()
    }
}

struct MeasuredPlate {
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

@main @MainActor struct PinnedPlateGeometryTests {
    static var count = 0
    static func check(_ value: @autoclosure () -> Bool, _ message: String) {
        count += 1; precondition(value(), message)
    }

    static let scale: CGFloat = 2
    static let listX: CGFloat = 8, listY: CGFloat = 10, listWidth: CGFloat = 212
    static let probeX: CGFloat = 150

    static func main() { exitOnFailure(runChecks) }

    static func measure(_ content: NSView, row: SidebarChromeLayout.TablistRow,
                        prepare: (NSView) -> Void) -> (plate: MeasuredPlate?, slot: NSRect) {
        let canvas = PlateCanvas(frame: NSRect(x: 0, y: 0, width: listX * 2 + listWidth, height: 80))
        canvas.appearance = NSAppearance(named: .aqua)
        let outline = SidebarOutlineView(frame: NSRect(x: listX, y: listY, width: listWidth, height: 60))
        canvas.addSubview(outline)
        outline.reload([SidebarOutlineEntry(key: "subject", content: content, row: row)])
        outline.layoutSubtreeIfNeeded()
        prepare(content)
        let slot = canvas.convert(outline.rowFrames()["subject"] ?? .zero, from: outline)
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(canvas.bounds.width * scale),
                                      pixelsHigh: Int(canvas.bounds.height * scale), bitsPerSample: 8, samplesPerPixel: 4,
                                      hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        bitmap.size = canvas.bounds.size
        canvas.cacheDisplay(in: canvas.bounds, to: bitmap)
        func pixel(_ x: Int, _ y: Int) -> [CGFloat] {
            let color = bitmap.colorAt(x: x, y: y) ?? .clear
            return [color.redComponent, color.greenComponent, color.blueComponent]
        }
        let ground = pixel(1, 1)
        func delta(_ x: Int, _ y: Int) -> CGFloat {
            zip(pixel(x, y), ground).map { abs($0 - $1) }.max() ?? 0
        }
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
                              leading: CGFloat(leading) / scale - listX, trailing: CGFloat(trailing + 1) / scale - listX,
                              corner: corner), slot)
    }

    static func press(_ view: NSView) {
        let event = NSEvent.mouseEvent(with: .leftMouseDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
                                       context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        view.mouseDown(with: event)
    }

    static func pinnedHeader(collapsed: Bool = false) -> SidebarPinnedHeaderView {
        let header = SidebarPinnedHeaderView()
        header.applyStyle(dark: false, accent: nil)
        header.update(.init(collapsed: collapsed, showsIcons: false, count: collapsed ? 6 : 0), fallbacks: [:], animated: false)
        return header
    }

    static func hoveredNewTab(_ view: NSView) {
        (view.subviews.first { $0 is SidebarRowBackgroundView } as? SidebarRowBackgroundView)?.appearanceState.hovered = true
    }

    static func runChecks() {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let slotRow = SidebarChromeLayout.TablistSlot.pinnedSectionHeader.row
        let standard = measure(SidebarNewTabRow(dark: false) {}, row: SidebarChromeLayout.TablistSlot.newTab.row, prepare: hoveredNewTab)
        guard let reference = standard.plate else { preconditionFailure("the New Tab row painted no hover plate") }
        check(reference.height == SidebarChromeLayout.tablistVisibleRowHeight && reference.leading == 0 && reference.trailing == listWidth,
              "the measured New Tab plate is the standard 36-point row, edge to edge")

        let pressed = measure(pinnedHeader(), row: slotRow, prepare: press)
        guard let plate = pressed.plate else { preconditionFailure("a pressed Pinned header painted no plate") }
        check(plate.height == reference.height, "the Pinned header's plate is exactly as tall as the New Tab row's")
        check(plate.matches(reference), "the Pinned header's plate sits, spans and rounds exactly like the New Tab row's")
        check(pressed.slot.height == standard.slot.height, "the Pinned header takes a standard row slot")

        let folded = measure(pinnedHeader(collapsed: true), row: slotRow, prepare: press)
        check(folded.plate.map { $0.matches(reference) } == true, "a folded header with its count keeps the standard plate")

        check(measure(pinnedHeader(), row: slotRow) { _ in }.plate == nil, "a resting header paints no plate")

        let short = measure(pinnedHeader(), row: .accessory(height: 26), prepare: press)
        check(short.plate.map { $0.height != reference.height && !$0.matches(reference) } == true,
              "negative control: a header squeezed into a 26-point slot is caught as off-standard")
        let sharp = measure(pinnedHeader(), row: slotRow) { view in press(view); view.layer?.cornerRadius = 6 }
        check(sharp.plate.map { $0.height == reference.height && !$0.matches(reference) } == true,
              "negative control: a full-height plate with the wrong corners is caught")
        print("Pinned plate geometry checks passed: \(count)")
    }
}
