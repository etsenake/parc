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
        "v": 9, "h": 4, "m": 46, "s": 1, "r": 15, "o": 31, "t": 17, "l": 37, "x": 7, "w": 13, "e": 14,
        "`": 50, "[": 33, "]": 30, "=": 24, "+": 24, "-": 27, "_": 27,
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
        zoomAnchor()
        print("EaselToolTests passed")
    }

    static func toolKeys() {
        var seen: Set<EaselKey> = []
        for binding in EaselKeyCommands.bindings {
            expect(seen.insert(binding.key).inserted, "\(binding.key.label) is bound once")
            let flags: EaselKeyModifiers = binding.key.shift ? [.shift] : []
            switch binding.key.base {
            case .character(let character):
                guard let code = ansi[character] else { failTest("Missing physical key for \(binding.key.label)") }
                let typed = binding.key.shift ? String(character).uppercased() : String(character)
                expect(command(typed, code, flags) == binding.command, "\(binding.key.label) runs its command")
            case .physical(let code, _):
                expect(command(nil, code, flags) == binding.command, "\(binding.key.label) runs its command by position")
            }
        }
        let labels = Dictionary(EaselTool.allCases.map { ($0, $0.keys.map(\.label)) }, uniquingKeysWith: { first, _ in first })
        expect(labels[.select] == ["V"] && labels[.hand] == ["H"] && labels[.marker] == ["M"], "Select, hand and marker answer to V, H and M")
        expect(labels[.highlighter] == ["⇧M"] && labels[.washi] == ["W"] && labels[.eraser] == ["⇧⌫", "⇧⌦"],
               "Highlighter, washi tape and eraser keys match the drawing menu")
        expect(labels[.sticky] == ["S"] && labels[.section] == ["⇧S"] && labels[.table] == ["⇧T"], "Stickies, sections and tables")
        expect(labels[.rectangle] == ["R"] && labels[.ellipse] == ["O"] && labels[.text] == ["T"], "R, O and T make rectangles, ellipses and text")
        expect(labels[.straightConnector] == ["L"] && labels[.elbowConnector] == ["X", "⇧L"] && labels[.curvedConnector] == [],
               "L draws straight connectors, X or Shift-L elbow ones, and curved ones come from the picker")
        expect(labels[.stamp] == ["E"] && labels[.codeBlock] == ["`", "⇧`"], "E stamps and backtick drops a code block")
        expect(command("H", 4, [.shift]) == .flip(horizontal: true) && command("V", 9, [.shift]) == .flip(horizontal: false),
               "Shift-H and Shift-V flip")
        expect(command("]", 30) == .layer(.front) && command("[", 33) == .layer(.back), "] and [ change the layer order")
        expect(command("]", 30, [.shift]) == nil, "Shift-] is not a layer key")
        expect(command(nil, 51) == nil && command(nil, 117) == nil, "Plain Delete stays the canvas delete")
    }

    static func modifiersAndLayouts() {
        for flags: EaselKeyModifiers in [[.command], [.control], [.option], [.command, .shift], [.control, .shift], [.option, .shift]] {
            expect(command("v", 9, flags) == nil, "Tool letters never fire with Command, Control or Option held")
            expect(command("r", 15, flags) == nil, "Rectangle stays quiet under shortcut modifiers")
        }
        expect(command("R", 15, [.shift]) == nil, "Shift-R is not a tool key")
        expect(command("V", 9) == .tool(.select), "Caps Lock letters still pick their tool")
        expect(command("м", 9) == .tool(.select), "A non-Latin layout falls back to the key's position")
        expect(command("ы", 1) == .tool(.sticky), "Cyrillic layouts reach the sticky tool by position")
        expect(command(",", 46) == nil, "A layout that types punctuation there keeps the key for itself")
        expect(command("m", 41) == .tool(.marker), "AZERTY's M picks the marker wherever the layout puts it")
        expect(command("ü", 33) == .layer(.back), "A layout with a letter on the bracket key reaches it by position")
        expect(command("`", 50) == .tool(.codeBlock), "Backtick drops a code block")
        expect(command("é", 19) == nil, "Accented letters with no tool stay unbound")
        expect(command("", 4) == .tool(.hand), "An empty character string falls back to the key's position")
        expect(command("q", 12) == nil && command("1", 18) == nil, "Unused keys stay free for later tools")
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
        expect(command("=", 24) == .zoom(.zoomIn) && command("-", 27) == .zoom(.zoomOut), "Bare = and − zoom like their Shift versions")
        expect(command("+", 30) == .zoom(.zoomIn), "German's own + key zooms in")
        expect(command("?", 27, [.shift]) == nil, "German Shift-ß types ? and stays free")
        expect(command("`", 24, [.shift]) == .tool(.codeBlock), "German Shift-´ types a backtick and drops a code block, not a zoom")
        expect(command("?", 27, [.command, .shift]) == nil, "⇧⌘? stays the Help menu's search on German layouts")
        expect(command("¿", 24, [.command, .shift]) == nil, "⇧⌘¿ on Spanish layouts is not a zoom")
        expect(command("ß", 27, [.command]) == .zoom(.zoomOut), "German ⌘ß zooms out by position")
        expect(command("1", 18) == nil && command("2", 19) == nil, "Plain digits are not zoom keys")
        expect(EaselZoomCommand.allCases.map(\.title) == ["Zoom in", "Zoom out", "Zoom to 100%", "Zoom to fit", "Zoom to selection"],
               "Zoom commands read in the Notes menus' sentence case")
        expect(EaselZoomCommand.allCases.allSatisfy { !$0.shortcut.isEmpty && !$0.shortcut.contains("+") },
               "Zoom shortcut labels avoid the plus sign the keycap renderer uses as a separator")
    }

    static func toolBehaviour() {
        expect(!EaselTool.select.createsObjects && !EaselTool.hand.createsObjects && !EaselTool.eraser.createsObjects,
               "Select, hand and eraser never create objects")
        expect(EaselTool.sticky.kind == .sticky && EaselTool.section.kind == .section && EaselTool.ellipse.kind == .circle
               && EaselTool.rectangle.kind == .rectangle && EaselTool.text.kind == .text, "Tools create the matching kinds")
        expect([EaselTool.marker, .highlighter, .washi].allSatisfy { $0.kind == .freehand && $0.draws }, "Brushes draw doodles")
        expect(EaselTool.marker.brush == .marker && EaselTool.highlighter.brush == .highlighter && EaselTool.washi.brush == .washi
               && EaselTool.eraser.brush == nil && EaselTool.sticky.brush == nil, "Each brush tool carries its brush")
        expect([EaselTool.straightConnector, .elbowConnector, .curvedConnector].allSatisfy { $0.kind == .arrow && $0.drawsConnector },
               "Connector tools draw arrows")
        expect(EaselTool.straightConnector.routing == .straight && EaselTool.elbowConnector.routing == .elbow
               && EaselTool.curvedConnector.routing == .curved, "Connector tools carry their routing")
        expect(EaselConnectorRouting.allCases.allSatisfy { EaselTool.connector($0).routing == $0 }, "Routing maps back to its tool")
        expect([EaselTool.sticky, .rectangle, .ellipse, .text, .section, .table, .codeBlock].allSatisfy { $0.placesObjects && $0.returnsToSelect },
               "Stickies, shapes, text, sections, tables and code go back to Select after one placement")
        expect(EaselTool.stamp.placesObjects && EaselTool.stamp.staysArmed, "Stamps keep stamping until V or Escape")
        expect([EaselTool.marker, .highlighter, .washi, .eraser, .straightConnector, .elbowConnector, .curvedConnector, .hand, .select]
               .allSatisfy { $0.staysArmed && !$0.returnsToSelect }, "Drawing tools, connectors and the hand stay armed until V or Escape")
        expect([EaselTool.select, .hand, .marker, .sticky, .rectangle, .ellipse, .text, .section, .straightConnector,
                .elbowConnector, .curvedConnector].allSatisfy(\.isAvailable), "The core tools are ready")
        let section = EaselTool.section.defaultSize
        expect(section.width > 0 && section.height > 0, "A clicked section has a size")
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

    static func zoomAnchor() {
        let origin = EaselPoint(x: 100, y: 50)
        let anchor = EaselPoint(x: 300, y: 250)
        let zoomedIn = EaselZoom.anchoredOrigin(anchor: anchor, visibleOrigin: origin, before: 1, after: 2)
        expect(near(zoomedIn.x, 200) && near(zoomedIn.y, 150), "Zooming in keeps the point under the pointer still")
        let zoomedOut = EaselZoom.anchoredOrigin(anchor: anchor, visibleOrigin: origin, before: 2, after: 1)
        expect(near(zoomedOut.x, -100) && near(zoomedOut.y, -150), "Zooming out keeps the point under the pointer still")
        expect(EaselZoom.anchoredOrigin(anchor: anchor, visibleOrigin: origin, before: 1, after: 1) == origin, "No zoom change leaves the view alone")
        expect(EaselZoom.anchoredOrigin(anchor: anchor, visibleOrigin: origin, before: 1, after: 0) == origin, "Nonsense zoom leaves the view alone")
        expect(EaselZoom.anchoredOrigin(anchor: EaselPoint(x: .nan, y: 0), visibleOrigin: origin, before: 1, after: 2) == origin,
               "A nonsense pointer leaves the view alone")
        let clampedAfter = EaselZoom.clamped(10, minimum: 0.3333, maximum: 4)
        let atLimit = EaselZoom.anchoredOrigin(anchor: anchor, visibleOrigin: origin, before: 4, after: clampedAfter)
        expect(atLimit == origin, "Wheeling past the zoom limit does not drift the view")
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
        expect(EaselZoom.stepped(from: .nan, zoomingIn: true, minimum: 2, maximum: 4) == 2, "Nonsense zoom resets inside the allowed range")
        var value = 1.0, steps = 0
        while value < 4, steps < 20 { value = EaselZoom.stepped(from: value, zoomingIn: true, minimum: 0.3333, maximum: 4); steps += 1 }
        expect(value == 4 && steps <= 8, "Zooming in walks to the maximum in a handful of steps")
        expect(EaselZoom.presets == [0.5, 1, 2], "The zoom menu offers 50%, 100% and 200%")
        expect(EaselZoom.percent(0.3333) == 33 && EaselZoom.percent(1) == 100 && EaselZoom.percent(1.499) == 150, "Percentages round")
        expect(EaselZoom.percent(.greatestFiniteMagnitude) == 100_000, "Huge magnifications never overflow the percentage")
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
        expect(EaselZoom.wheelFactor(deviceDelta: 10_000, precise: false) == EaselZoom.wheelFactor(deviceDelta: 3, precise: false),
               "A runaway wheel burst is limited")
        for delta in [-10_000.0, -10, -1, 1, 10, 10_000] {
            for precise in [true, false] {
                let factor = EaselZoom.wheelFactor(deviceDelta: delta, precise: precise)
                expect(factor >= 0.5 && factor <= 2, "One wheel event never more than halves or doubles the zoom")
            }
        }
        expect(EaselZoom.wheelFactor(deviceDelta: 10, precise: false) < 1.8, "An accelerated flick zooms a step, not across the range")
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
