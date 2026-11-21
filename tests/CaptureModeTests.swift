import Foundation

@main
struct CaptureModeTests {
    static var assertions = 0

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        assertions += 1
        if !condition() { fatalError(message) }
    }

    static func main() {
        exitOnFailure {
            items()
            keys()
            hints()
            readout()
            placement()
            bar()
            print("CaptureModeTests: \(assertions) assertions passed")
        }
    }

    static func items() {
        expect(CaptureModeItem.allCases == [.element, .region, .visibleArea, .fullPage, .cancel], "The bar reads Element, Region, Visible Area, Full Page, Cancel")
        expect(CaptureModeItem.allCases.map(\.mode) == [.element, .region, nil, nil, nil], "Only Element and Region are selection modes")
        expect(CaptureModeItem.allCases.map(\.group) == [0, 0, 1, 1, 2], "Modes, one-click captures and Cancel form three groups")
        expect(Set(CaptureModeItem.allCases.map(\.key)).count == 5, "Every item has its own key")
        expect(CaptureModeItem.visibleArea.title == "Visible Area" && CaptureModeItem.visibleArea.key == "V", "Visible Area is labelled with its key")
        expect(CaptureModeItem.cancel.key == "esc", "Cancel shows Escape")
        expect(CaptureModeItem.allCases.allSatisfy { !$0.symbol.isEmpty && !$0.toolTip.isEmpty && !$0.title.isEmpty }, "Every item has an icon, a title and a tooltip")
    }

    static func keys() {
        expect(CaptureModeKeys.item(typed: "e", keyCode: 14) == .element, "E chooses Element")
        expect(CaptureModeKeys.item(typed: "r", keyCode: 15) == .region, "R chooses Region")
        expect(CaptureModeKeys.item(typed: "v", keyCode: 9) == .visibleArea, "V captures the visible area")
        expect(CaptureModeKeys.item(typed: "f", keyCode: 3) == .fullPage, "F captures the full page")
        expect(CaptureModeKeys.item(typed: "V", keyCode: 9) == .visibleArea, "Caps Lock still reaches the item")
        expect(CaptureModeKeys.item(typed: "e", keyCode: 2) == .element, "Latin layouts follow the typed letter, wherever the key sits")
        expect(CaptureModeKeys.item(typed: ".", keyCode: 14) == nil, "A typed punctuation key never falls back to the physical E")
        expect(CaptureModeKeys.item(typed: "x", keyCode: 7) == nil, "Unassigned letters do nothing")
        expect(CaptureModeKeys.item(typed: "у", keyCode: 14) == .element, "Non-Latin layouts use the physical E position")
        expect(CaptureModeKeys.item(typed: "м", keyCode: 9) == .visibleArea, "Non-Latin layouts use the physical V position")
        expect(CaptureModeKeys.item(typed: "", keyCode: 3) == .fullPage, "Dead keys fall back to the physical position")
        expect(CaptureModeKeys.item(typed: nil, keyCode: 49) == nil, "Space is not a capture item")
        expect(CaptureModeKeys.item(typed: "ef", keyCode: 14) == nil, "Multi-character input is ignored")
    }

    static func hints() {
        let element = CaptureModeHint.text(mode: .element, targeted: false, dragging: false)
        let targeted = CaptureModeHint.text(mode: .element, targeted: true, dragging: false)
        let region = CaptureModeHint.text(mode: .region, targeted: false, dragging: false)
        let dragging = CaptureModeHint.text(mode: .element, targeted: true, dragging: true)
        expect(Set([element, targeted, region, dragging]).count == 4, "Each state explains itself differently")
        expect(targeted.hasPrefix("Click"), "A highlighted target says what a click does")
        expect(element.contains("drag") && targeted.contains("drag"), "Element mode still mentions dragging out a region")
        expect(region.hasPrefix("Drag") && !region.contains("Click"), "Region mode only drags")
        expect(CaptureModeHint.text(mode: .region, targeted: true, dragging: true) == dragging, "Dragging reads the same in both modes")
        expect([element, targeted, region, dragging].allSatisfy { $0.count <= 48 && !$0.hasSuffix(".") }, "Hints stay short single lines")
        expect(CaptureModeHint.accessibilityValue(mode: .element, targeted: true).contains("Return"), "VoiceOver hears how to capture the target")
        expect(CaptureModeHint.accessibilityValue(mode: .region, targeted: false).contains("Region"), "VoiceOver hears the current mode")
    }

    static func readout() {
        expect(CaptureSizeReadout.text(CGSize(width: 320, height: 180)) == "320 × 180", "Sizes read width × height")
        expect(CaptureSizeReadout.text(CGSize(width: 319.6, height: -4)) == "320 × 0", "Readouts round and never go negative")
        let viewport = CGSize(width: 1000, height: 800)
        let scaled = CaptureSizeReadout.viewportRect(CGRect(x: 50, y: 40, width: 250, height: 200),
                                                     overlay: CGSize(width: 500, height: 400), viewport: viewport)
        expect(scaled == CGRect(x: 100, y: 80, width: 500, height: 400), "Overlay drags convert to page points")
        expect(CaptureSizeReadout.viewportRect(.zero, overlay: .zero, viewport: viewport) == nil, "A collapsed overlay has no readout")
        expect(CaptureSizeReadout.pointSize(CGRect(x: 10.4, y: 0.5, width: 99.2, height: 20)) == CGSize(width: 100, height: 21),
               "Readouts round outward like the capture bounds")
        expect(CaptureSizeReadout.pointSize(CGRect(x: 10, y: 10, width: 100, height: 50)) == CGSize(width: 100, height: 50),
               "Whole-point rectangles keep their exact size")
        expect(CaptureSizeReadout.pointSize(.null) == .zero && CaptureSizeReadout.pointSize(.zero) == .zero, "Empty selections read zero")
    }

    static func placement() {
        let bounds = CGRect(x: 0, y: 0, width: 800, height: 600)
        let size = CGSize(width: 80, height: 22)
        let below = CaptureSizeReadout.placement(for: CGRect(x: 100, y: 100, width: 200, height: 100), size: size, in: bounds)
        expect(below == CGRect(x: 220, y: 206, width: 80, height: 22), "The readout sits under the frame's trailing corner")
        let bottom = CaptureSizeReadout.placement(for: CGRect(x: 100, y: 450, width: 200, height: 140), size: size, in: bounds)
        expect(bottom.maxY <= 450 - 6 && bottom.minY >= 8, "Frames near the bottom put the readout above them")
        let full = CaptureSizeReadout.placement(for: bounds, size: size, in: bounds)
        expect(bounds.insetBy(dx: 8, dy: 8).contains(full), "A full-page frame keeps the readout inside the page")
        let bar = CGRect(x: 200, y: 540, width: 400, height: 44)
        let avoided = CaptureSizeReadout.placement(for: CGRect(x: 300, y: 400, width: 200, height: 120), size: size, in: bounds, avoiding: bar)
        expect(!avoided.intersects(bar), "The readout never hides under the mode bar")
        let edge = CaptureSizeReadout.placement(for: CGRect(x: 0, y: 100, width: 40, height: 40), size: size, in: bounds)
        expect(edge.minX >= 8, "Narrow frames at the edge keep the readout on the page")
        let tiny = CaptureSizeReadout.placement(for: CGRect(x: 0, y: 0, width: 30, height: 20), size: size,
                                                in: CGRect(x: 0, y: 0, width: 60, height: 30))
        expect(tiny.width == size.width && tiny.height == size.height, "Tiny panes still get a whole readout")
    }

    static func bar() {
        expect(CaptureModeBarLayout.density(available: 600, full: 560, labels: 420) == .full, "Wide pages show labels and keys")
        expect(CaptureModeBarLayout.density(available: 500, full: 560, labels: 420) == .labels, "Medium panes drop the keycaps first")
        expect(CaptureModeBarLayout.density(available: 300, full: 560, labels: 420) == .icons, "Narrow panes fall back to icons")
        let bounds = CGRect(x: 0, y: 0, width: 1000, height: 700)
        let frame = CaptureModeBarLayout.frame(size: CGSize(width: 540, height: 44), in: bounds)
        expect(frame == CGRect(x: 230, y: 640, width: 540, height: 44), "The bar floats centred 16 points above the bottom")
        let narrow = CaptureModeBarLayout.frame(size: CGSize(width: 540, height: 44), in: CGRect(x: 0, y: 0, width: 300, height: 200))
        expect(narrow.minX >= 0 && narrow.maxX <= 300 && narrow.maxY <= 200, "The bar never leaves a narrow pane")
        let hint = CaptureModeBarLayout.hintFrame(size: CGSize(width: 300, height: 30), above: frame, in: bounds)
        expect(hint == CGRect(x: 350, y: 602, width: 300, height: 30), "The hint floats eight points above the bar")
        let squeezed = CaptureModeBarLayout.hintFrame(size: CGSize(width: 300, height: 30), above: CGRect(x: 0, y: 10, width: 100, height: 20),
                                                      in: CGRect(x: 0, y: 0, width: 200, height: 40))
        expect(squeezed.minY >= 0 && squeezed.width <= 200, "Short panes keep the hint on the page")
    }
}
