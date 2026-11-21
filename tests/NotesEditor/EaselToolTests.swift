import Foundation

@main
struct EaselToolTests {
    static func expect(_ value: Bool, _ message: String) {
        if !value { failTest(message) }
    }

    static func near(_ a: Double, _ b: Double, _ tolerance: Double = 1e-6) -> Bool { abs(a - b) <= tolerance }

    static func command(_ characters: String?, _ keyCode: UInt16, _ modifiers: EaselKeyModifiers = []) -> EaselKeyCommand? {
        EaselKeyCommands.command(characters: characters, keyCode: keyCode, modifiers: modifiers)
    }

    static let ansi: [Character: UInt16] = [
        "v": 9, "h": 4, "m": 46, "s": 1, "r": 15, "o": 31, "t": 17, "l": 37, "x": 7,
    ]

    static func main() {
        toolKeys()
        modifiersAndLayouts()
        zoomKeys()
        toolBehaviour()
        placementGeometry()
        connectorGeometry()
        zoomSteps()
        zoomFitting()
        print("EaselToolTests passed")
    }

    static func toolKeys() {
        var seen: [EaselToolKey: EaselTool] = [:]
        for tool in EaselTool.allCases {
            for key in tool.keys {
                expect(seen[key] == nil, "\(key.label) belongs to one tool only")
                seen[key] = tool
                guard let code = ansi[key.character] else { failTest("Missing physical key for \(key.label)") }
                let typed = key.shift ? String(key.character).uppercased() : String(key.character)
                expect(command(typed, code, key.shift ? [.shift] : []) == .tool(tool), "\(key.label) picks \(tool.title)")
            }
        }
        expect(EaselTool.select.key?.label == "V" && EaselTool.hand.key?.label == "H" && EaselTool.pen.key?.label == "M",
               "Select, hand and pen answer to V, H and M")
        expect(EaselTool.sticky.key?.label == "S" && EaselTool.section.key?.label == "⇧S", "S is a sticky and Shift-S a section")
        expect(EaselTool.rectangle.key?.label == "R" && EaselTool.ellipse.key?.label == "O" && EaselTool.text.key?.label == "T",
               "R, O and T make rectangles, ellipses and text")
        expect(EaselTool.straightConnector.key?.label == "L" && EaselTool.elbowConnector.key?.label == "X",
               "L draws straight connectors and X elbow ones")
        expect(command("L", 37, [.shift]) == .tool(.elbowConnector), "Shift-L is the other elbow connector key")
        expect(EaselTool.curvedConnector.key == nil, "Curved connectors have no key and come from the picker")
    }

    static func modifiersAndLayouts() {
        for flags: EaselKeyModifiers in [[.command], [.control], [.option], [.command, .shift], [.control, .shift], [.option, .shift]] {
            expect(command("v", 9, flags) == nil, "Tool letters never fire with Command, Control or Option held")
            expect(command("r", 15, flags) == nil, "Rectangle stays quiet under shortcut modifiers")
        }
        expect(command("V", 9, [.shift]) == nil, "Shift-V is not a tool key")
        expect(command("V", 9) == .tool(.select), "Caps Lock letters still pick their tool")
        expect(command("м", 9) == .tool(.select), "A non-Latin layout falls back to the key's position")
        expect(command("ы", 1) == .tool(.sticky), "Cyrillic layouts reach the sticky tool by position")
        expect(command(",", 46) == nil, "A layout that types punctuation there keeps the key for itself")
        expect(command("m", 41) == .tool(.pen), "AZERTY's M picks the pen wherever the layout puts it")
        expect(command("é", 19) == nil, "Accented letters with no tool stay unbound")
        expect(command("", 4) == .tool(.hand), "An empty character string falls back to the key's position")
        expect(command("q", 12) == nil, "Unused letters stay free for later tools")
        expect(EaselKeyCommands.spaceKeyCode == 49, "Space is the temporary hand")
    }

    static func zoomKeys() {
        expect(command("=", 24, [.command]) == .zoom(.zoomIn), "⌘= zooms in")
        expect(command("+", 24, [.command, .shift]) == .zoom(.zoomIn), "⌘+ zooms in")
        expect(command("+", 69, [.command]) == .zoom(.zoomIn), "Keypad plus zooms in")
        expect(command("-", 27, [.command]) == .zoom(.zoomOut), "⌘− zooms out")
        expect(command("_", 27, [.command, .shift]) == .zoom(.zoomOut), "⇧⌘− zooms out like the View menu's alternate")
        expect(command("-", 78, [.command]) == .zoom(.zoomOut), "Keypad minus zooms out")
        expect(command("0", 29, [.command]) == .zoom(.actualSize), "⌘0 returns to 100%")
        expect(command("à", 29, [.command]) == .zoom(.actualSize), "French layouts reach 100% by the zero key")
        expect(command("0", 29, [.command, .shift]) == nil, "⇧⌘0 is not a zoom key")
        expect(command("=", 24, [.command, .option]) == nil, "Option keeps ⌥⌘= for the system")
        expect(command("=", 24, [.command, .control]) == nil, "Control keeps ⌃⌘= for the system")
        expect(command("!", 18, [.shift]) == .zoom(.fit), "⇧1 zooms to fit")
        expect(command("1", 18, [.shift]) == .zoom(.fit), "⇧1 zooms to fit on layouts with symbols on the number row")
        expect(command("@", 19, [.shift]) == .zoom(.selection), "⇧2 zooms to the selection")
        expect(command(")", 29, [.shift]) == .zoom(.actualSize), "⇧0 returns to 100%")
        expect(command("+", 24, [.shift]) == .zoom(.zoomIn) && command("_", 27, [.shift]) == .zoom(.zoomOut),
               "⇧+ and ⇧− zoom in and out")
        expect(command("1", 18) == nil && command("2", 19) == nil, "Plain digits are not zoom keys")
        expect(EaselZoomCommand.allCases.map(\.title) == ["Zoom In", "Zoom Out", "Zoom to 100%", "Zoom to Fit", "Zoom to Selection"],
               "Zoom commands read like the menu")
        expect(EaselZoomCommand.allCases.allSatisfy { !$0.shortcut.isEmpty && !$0.shortcut.contains("+") },
               "Zoom shortcut labels avoid the plus sign the keycap renderer uses as a separator")
    }

    static func toolBehaviour() {
        expect(!EaselTool.select.createsObjects && !EaselTool.hand.createsObjects, "Select and hand never create objects")
        expect(EaselTool.allCases.filter(\.createsObjects).allSatisfy { $0.kind != nil }, "Every creation tool names its object kind")
        expect(EaselTool.sticky.kind == .sticky && EaselTool.section.kind == .section && EaselTool.ellipse.kind == .circle
               && EaselTool.rectangle.kind == .rectangle && EaselTool.text.kind == .text && EaselTool.pen.kind == .freehand,
               "Tools create the matching kinds")
        expect([EaselTool.straightConnector, .elbowConnector, .curvedConnector].allSatisfy { $0.kind == .arrow && $0.drawsConnector },
               "Connector tools draw arrows")
        expect(EaselTool.straightConnector.routing == .straight && EaselTool.elbowConnector.routing == .elbow
               && EaselTool.curvedConnector.routing == .curved, "Connector tools carry their routing")
        expect(EaselConnectorRouting.allCases.allSatisfy { EaselTool.connector($0).routing == $0 }, "Routing maps back to its tool")
        expect([EaselTool.sticky, .rectangle, .ellipse, .text, .section].allSatisfy { $0.placesObjects && $0.returnsToSelect },
               "Stickies, shapes, text and sections go back to Select after one placement")
        expect([EaselTool.pen, .straightConnector, .elbowConnector, .curvedConnector, .hand, .select].allSatisfy { !$0.returnsToSelect },
               "The pen, connectors and hand stay armed until V or Escape")
        let section = EaselTool.section.defaultSize
        expect(section.width == section.height, "A clicked section is square")
    }

    static func placementGeometry() {
        let sticky = EaselToolGeometry.placedFrame(.sticky, at: EaselPoint(x: 300, y: 200))
        expect(near(sticky.x + sticky.width / 2, 300) && near(sticky.y + sticky.height / 2, 200), "A clicked sticky is centred on the click")
        let text = EaselToolGeometry.placedFrame(.text, at: EaselPoint(x: 300, y: 200))
        expect(text.x == 300 && text.y == 186 && text.width == 280 && text.height == 28, "Clicked text matches the double-click text box")
        let plain = EaselToolGeometry.draggedFrame(from: EaselPoint(x: 10, y: 20), to: EaselPoint(x: 110, y: 70), square: false, centered: false)
        expect(plain == EaselRect(x: 10, y: 20, width: 100, height: 50), "A drag sizes the object between start and end")
        let reversed = EaselToolGeometry.draggedFrame(from: EaselPoint(x: 110, y: 70), to: EaselPoint(x: 10, y: 20), square: false, centered: false)
        expect(reversed == plain, "Dragging up and left sizes the same box")
        let square = EaselToolGeometry.draggedFrame(from: EaselPoint(x: 100, y: 100), to: EaselPoint(x: 40, y: 130), square: true, centered: false)
        expect(square == EaselRect(x: 40, y: 100, width: 60, height: 60), "Shift keeps the drag square in the drag's direction")
        let centred = EaselToolGeometry.draggedFrame(from: EaselPoint(x: 100, y: 100), to: EaselPoint(x: 130, y: 110), square: false, centered: true)
        expect(centred == EaselRect(x: 70, y: 90, width: 60, height: 20), "Option draws from the centre")
        let both = EaselToolGeometry.draggedFrame(from: EaselPoint(x: 100, y: 100), to: EaselPoint(x: 130, y: 110), square: true, centered: true)
        expect(both == EaselRect(x: 70, y: 70, width: 60, height: 60), "Shift-Option draws a square from the centre")
        let tiny = EaselToolGeometry.draggedFrame(from: EaselPoint(x: 5, y: 5), to: EaselPoint(x: 5, y: 5), square: false, centered: false)
        expect(tiny.width >= 1 && tiny.height >= 1, "Sizes never collapse below one point")
        let bounds = EaselRect(x: 0, y: 0, width: 300, height: 200)
        let kept = EaselToolGeometry.constrained(EaselRect(x: 250, y: -20, width: 100, height: 100), to: bounds)
        expect(kept == EaselRect(x: 200, y: 0, width: 100, height: 100), "Fixed canvases keep new objects inside")
        let shrunk = EaselToolGeometry.constrained(EaselRect(x: 0, y: 0, width: 500, height: 500), to: bounds)
        expect(shrunk == EaselRect(x: 0, y: 0, width: 300, height: 200), "Objects larger than a fixed canvas shrink to fit")
        expect(EaselToolGeometry.clamped(EaselPoint(x: -5, y: 400), to: bounds) == EaselPoint(x: 0, y: 200), "Points clamp to a fixed canvas")
    }

    static func connectorGeometry() {
        let start = EaselPoint(x: 100, y: 100)
        let flat = EaselToolGeometry.snappedLineEnd(from: start, to: EaselPoint(x: 200, y: 108))
        expect(near(flat.y, 100) && flat.x > 199, "Shift turns a nearly flat drag into a flat line")
        let diagonal = EaselToolGeometry.snappedLineEnd(from: start, to: EaselPoint(x: 170, y: 166))
        expect(near(diagonal.x - 100, diagonal.y - 100), "Shift snaps to 45°")
        expect(near(hypot(diagonal.x - 100, diagonal.y - 100), hypot(70, 66)), "Snapping keeps the drag's length")
        let up = EaselToolGeometry.snappedLineEnd(from: start, to: EaselPoint(x: 103, y: 20))
        expect(near(up.x, 100) && up.y < 100, "Shift snaps a steep drag straight up")
        expect(EaselToolGeometry.snappedLineEnd(from: start, to: start) == start, "A zero-length drag stays put")
        let line = EaselToolGeometry.lineItemGeometry(from: EaselPoint(x: 200, y: 50), to: EaselPoint(x: 120, y: 90))
        expect(line.frame == EaselRect(x: 120, y: 50, width: 80, height: 40), "Connector frames wrap both ends")
        expect(line.points == [EaselPoint(x: 80, y: 0), EaselPoint(x: 0, y: 40)], "Connector points are relative to the frame and keep their order")
        let flatLine = EaselToolGeometry.lineItemGeometry(from: EaselPoint(x: 0, y: 10), to: EaselPoint(x: 50, y: 10))
        expect(flatLine.frame.height == 1, "A flat connector keeps a valid one-point frame")
    }

    static func zoomSteps() {
        expect(EaselZoom.stepped(from: 1, zoomingIn: true, minimum: 0.3333, maximum: 4) == 1.5, "Zoom in from 100% goes to 150%")
        expect(EaselZoom.stepped(from: 1, zoomingIn: false, minimum: 0.3333, maximum: 4) == 0.75, "Zoom out from 100% goes to 75%")
        expect(EaselZoom.stepped(from: 0.8, zoomingIn: true, minimum: 0.3333, maximum: 4) == 1, "Off-step zoom in lands on the next level")
        expect(EaselZoom.stepped(from: 0.8, zoomingIn: false, minimum: 0.3333, maximum: 4) == 0.75, "Off-step zoom out lands on the previous level")
        expect(EaselZoom.stepped(from: 4, zoomingIn: true, minimum: 0.3333, maximum: 4) == 4, "Zoom in stops at the maximum")
        expect(EaselZoom.stepped(from: 0.3333, zoomingIn: false, minimum: 0.3333, maximum: 4) == 0.3333, "Zoom out stops at the minimum")
        expect(EaselZoom.stepped(from: 0.12, zoomingIn: false, minimum: 0.01, maximum: 4) == 0.06, "Below the levels zoom out halves")
        expect(EaselZoom.stepped(from: 0.12, zoomingIn: true, minimum: 0.01, maximum: 4) == 0.25, "From a tiny fit, zoom in finds the first level")
        expect(EaselZoom.stepped(from: .nan, zoomingIn: true, minimum: 0.3333, maximum: 4) == 1, "Nonsense zoom resets to 100%")
        var value = 1.0, steps = 0
        while value < 4, steps < 20 { value = EaselZoom.stepped(from: value, zoomingIn: true, minimum: 0.3333, maximum: 4); steps += 1 }
        expect(value == 4 && steps <= 8, "Zooming in walks to the maximum in a handful of steps")
        expect(EaselZoom.presets == [0.5, 1, 2], "The zoom menu offers 50%, 100% and 200%")
        expect(EaselZoom.percent(0.3333) == 33 && EaselZoom.percent(1) == 100 && EaselZoom.percent(1.499) == 150, "Percentages round")
        expect(EaselZoom.clamped(9, minimum: 0.3333, maximum: 4) == 4 && EaselZoom.clamped(-1, minimum: 0.3333, maximum: 4) == 1,
               "Clamping keeps zoom in range and refuses nonsense")
        let mid = EaselZoom.interpolated(from: 1, to: 4, progress: 0.5)
        expect(near(mid, 2), "Animated zoom moves evenly in scale")
        expect(EaselZoom.eased(0) == 0 && EaselZoom.eased(1) == 1 && EaselZoom.eased(0.5) > 0.5, "Zoom eases out")
        expect(EaselZoom.wheelFactor(deviceDelta: 0, precise: true) == 1, "No scroll, no zoom")
        expect(EaselZoom.wheelFactor(deviceDelta: 10, precise: true) > 1 && EaselZoom.wheelFactor(deviceDelta: -10, precise: true) < 1,
               "Scrolling up zooms in and down zooms out")
        expect(EaselZoom.wheelFactor(deviceDelta: 1, precise: false) > EaselZoom.wheelFactor(deviceDelta: 1, precise: true),
               "A mouse wheel notch zooms further than a trackpad pixel")
        expect(EaselZoom.wheelFactor(deviceDelta: 10_000, precise: false) == EaselZoom.wheelFactor(deviceDelta: 40, precise: false),
               "A runaway wheel burst is limited")
    }

    static func zoomFitting() {
        let content = EaselRect(x: 0, y: 0, width: 2000, height: 1000)
        let fit = EaselZoom.fitting(content, viewport: (1096, 896), minimum: 0.3333, maximum: 4)
        expect(fit.map { near($0, 0.5) } == true, "A board twice the viewport's width fits at 50%")
        let small = EaselZoom.fitting(EaselRect(x: 10, y: 10, width: 20, height: 20), viewport: (1000, 800), minimum: 0.3333, maximum: 4)
        expect(small == 4, "A tiny selection zooms in only to the maximum")
        let huge = EaselZoom.fitting(EaselRect(x: 0, y: 0, width: 100_000, height: 100), viewport: (1000, 800), minimum: 0.3333, maximum: 4)
        expect(huge == 0.3333, "A giant board stops at the minimum")
        expect(EaselZoom.fitting(EaselRect(x: 0, y: 0, width: 0, height: 10), viewport: (1000, 800), minimum: 0.3333, maximum: 4) == nil,
               "Empty content has nothing to fit")
        expect(EaselZoom.fitting(content, viewport: (0, 800), minimum: 0.3333, maximum: 4) == nil, "A hidden viewport has nothing to fit")
        let bounds = EaselZoom.bounds(of: [EaselRect(x: 10, y: 20, width: 30, height: 40), EaselRect(x: -5, y: 50, width: 10, height: 100)])
        expect(bounds == EaselRect(x: -5, y: 20, width: 45, height: 130), "Fit bounds wrap every object")
        expect(EaselZoom.bounds(of: []) == nil, "No objects, no bounds")
    }
}
