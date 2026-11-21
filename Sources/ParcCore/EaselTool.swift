import Foundation

struct EaselKey: Hashable {
    enum Base: Hashable {
        case character(Character)
        case physical(UInt16, label: String)
    }
    let base: Base
    let shift: Bool

    init(_ character: Character, shift: Bool = false) {
        base = .character(character)
        self.shift = shift
    }

    init(keyCode: UInt16, label: String, shift: Bool) {
        base = .physical(keyCode, label: label)
        self.shift = shift
    }

    var label: String {
        let key: String
        switch base {
        case .character(let character): key = String(character).uppercased()
        case .physical(_, let label): key = label
        }
        return (shift ? "⇧" : "") + key
    }
}

enum EaselTool: String, CaseIterable, Equatable {
    case select, hand, sticky, rectangle, ellipse, elbowConnector, curvedConnector, straightConnector, text, section, table,
         marker, highlighter, washi, eraser, stamp, codeBlock

    var title: String {
        switch self {
        case .select: return "Select"
        case .hand: return "Hand"
        case .sticky: return "Sticky note"
        case .rectangle: return "Rectangle"
        case .ellipse: return "Ellipse"
        case .elbowConnector: return "Elbow connector"
        case .curvedConnector: return "Curved connector"
        case .straightConnector: return "Straight connector"
        case .text: return "Text"
        case .section: return "Section"
        case .table: return "Table"
        case .marker: return "Marker"
        case .highlighter: return "Highlighter"
        case .washi: return "Washi tape"
        case .eraser: return "Eraser"
        case .stamp: return "Stamp"
        case .codeBlock: return "Code block"
        }
    }

    var isAvailable: Bool {
        switch self {
        case .highlighter: return false
        case .washi: return false
        case .eraser: return false
        case .stamp: return false
        default: return true
        }
    }

    var keys: [EaselKey] { EaselKeyCommands.bindings.filter { $0.command == .tool(self) }.map(\.key) }
    var key: EaselKey? { keys.first }

    var routing: EaselConnectorRouting? {
        switch self {
        case .straightConnector: return .straight
        case .elbowConnector: return .elbow
        case .curvedConnector: return .curved
        default: return nil
        }
    }

    static func connector(_ routing: EaselConnectorRouting) -> EaselTool {
        switch routing {
        case .straight: return .straightConnector
        case .elbow: return .elbowConnector
        case .curved: return .curvedConnector
        }
    }

    var brush: EaselBrush? {
        switch self {
        case .marker: return .marker
        case .highlighter: return .highlighter
        case .washi: return .washi
        default: return nil
        }
    }

    var createsObjects: Bool { self != .select && self != .hand && self != .eraser }
    var draws: Bool { brush != nil }
    var drawsConnector: Bool { routing != nil }
    var placesObjects: Bool { createsObjects && !draws && !drawsConnector }
    var returnsToSelect: Bool { placesObjects && self != .stamp }
    var staysArmed: Bool { !returnsToSelect }

    var kind: EaselItemKind? {
        switch self {
        case .select, .hand, .eraser, .stamp: return nil
        case .table: return .table
        case .codeBlock: return .code
        case .marker, .highlighter, .washi: return .freehand
        case .sticky: return .sticky
        case .rectangle: return .rectangle
        case .ellipse: return .circle
        case .text: return .text
        case .straightConnector, .elbowConnector, .curvedConnector: return .arrow
        case .section: return .section
        }
    }

    var defaultSize: (width: Double, height: Double) {
        switch self {
        case .sticky: return (EaselBoardObjects.stickySide, EaselBoardObjects.stickySide)
        case .rectangle: return EaselShapeGeometry.defaultSize(.rectangle)
        case .ellipse: return EaselShapeGeometry.defaultSize(.ellipse)
        case .text: return (280, 28)
        case .straightConnector, .elbowConnector, .curvedConnector: return (160, 0)
        case .section: return (EaselBoardObjects.sectionWidth, EaselBoardObjects.sectionHeight)
        case .table: return (360, 160)
        case .stamp: return (48, 48)
        case .codeBlock: return (EaselCodeBlock.defaultWidth, EaselCodeBlock.height(lines: EaselCodeBlock.starterLineCount))
        case .select, .hand, .marker, .highlighter, .washi, .eraser: return (0, 0)
        }
    }
}

struct EaselKeyModifiers: OptionSet, Hashable {
    let rawValue: Int
    static let shift = EaselKeyModifiers(rawValue: 1)
    static let control = EaselKeyModifiers(rawValue: 2)
    static let option = EaselKeyModifiers(rawValue: 4)
    static let command = EaselKeyModifiers(rawValue: 8)
}

enum EaselZoomCommand: String, CaseIterable, Equatable {
    case zoomIn, zoomOut, actualSize, fit, selection

    var title: String {
        switch self {
        case .zoomIn: return "Zoom in"
        case .zoomOut: return "Zoom out"
        case .actualSize: return "Zoom to 100%"
        case .fit: return "Zoom to fit"
        case .selection: return "Zoom to selection"
        }
    }

    var shortcut: String {
        switch self {
        case .zoomIn: return "⌘="
        case .zoomOut: return "⌘-"
        case .actualSize: return "⌘0"
        case .fit: return "⇧1"
        case .selection: return "⇧2"
        }
    }
}

enum EaselKeyCommand: Equatable {
    case tool(EaselTool)
    case zoom(EaselZoomCommand)
    case flip(horizontal: Bool)
    case layer(EaselLayerMove)
}

enum EaselKeyCommands {
    static let spaceKeyCode: UInt16 = 49

    static let bindings: [(key: EaselKey, command: EaselKeyCommand)] = [
        (EaselKey("v"), .tool(.select)),
        (EaselKey("h"), .tool(.hand)),
        (EaselKey("s"), .tool(.sticky)),
        (EaselKey("r"), .tool(.rectangle)),
        (EaselKey("o"), .tool(.ellipse)),
        (EaselKey("x"), .tool(.elbowConnector)),
        (EaselKey("l", shift: true), .tool(.elbowConnector)),
        (EaselKey("l"), .tool(.straightConnector)),
        (EaselKey("t"), .tool(.text)),
        (EaselKey("s", shift: true), .tool(.section)),
        (EaselKey("t", shift: true), .tool(.table)),
        (EaselKey("m"), .tool(.marker)),
        (EaselKey("m", shift: true), .tool(.highlighter)),
        (EaselKey("w"), .tool(.washi)),
        (EaselKey(keyCode: 51, label: "⌫", shift: true), .tool(.eraser)),
        (EaselKey(keyCode: 117, label: "⌦", shift: true), .tool(.eraser)),
        (EaselKey("e"), .tool(.stamp)),
        (EaselKey("`"), .tool(.codeBlock)),
        (EaselKey("`", shift: true), .tool(.codeBlock)),
        (EaselKey("h", shift: true), .flip(horizontal: true)),
        (EaselKey("v", shift: true), .flip(horizontal: false)),
        (EaselKey(keyCode: 18, label: "1", shift: true), .zoom(.fit)),
        (EaselKey(keyCode: 19, label: "2", shift: true), .zoom(.selection)),
        (EaselKey(keyCode: 29, label: "0", shift: true), .zoom(.actualSize)),
        (EaselKey("="), .zoom(.zoomIn)),
        (EaselKey("+"), .zoom(.zoomIn)),
        (EaselKey("+", shift: true), .zoom(.zoomIn)),
        (EaselKey("-"), .zoom(.zoomOut)),
        (EaselKey("_", shift: true), .zoom(.zoomOut)),
    ]

    private static let positionKeyCodes: [UInt16: Character] = [
        0: "a", 1: "s", 2: "d", 3: "f", 4: "h", 5: "g", 6: "z", 7: "x", 8: "c", 9: "v", 11: "b", 12: "q", 13: "w",
        14: "e", 15: "r", 16: "y", 17: "t", 30: "]", 31: "o", 32: "u", 33: "[", 34: "i", 35: "p", 37: "l", 38: "j",
        40: "k", 45: "n", 46: "m", 50: "`",
    ]

    static func command(characters: String?, keyCode: UInt16, modifiers: EaselKeyModifiers) -> EaselKeyCommand? {
        if modifiers.contains(.command) {
            guard modifiers.isDisjoint(with: [.control, .option]) else { return nil }
            return zoomChord(characters: characters, keyCode: keyCode, shift: modifiers.contains(.shift)).map(EaselKeyCommand.zoom)
        }
        guard modifiers.isDisjoint(with: [.control, .option]) else { return nil }
        let shift = modifiers.contains(.shift)
        if !shift, let move = EaselChords.bareLayerMove(characters: characters, keyCode: keyCode) { return .layer(move) }
        if let binding = bindings.first(where: { binding in
            if case .physical(let code, _) = binding.key.base { return code == keyCode && binding.key.shift == shift }
            return false
        }) { return binding.command }
        guard let character = keyCharacter(characters: characters, keyCode: keyCode) else { return nil }
        return bindings.first { $0.key == EaselKey(character, shift: shift) }?.command
    }

    static func letter(characters: String?, keyCode: UInt16) -> Character? {
        guard let character = keyCharacter(characters: characters, keyCode: keyCode), character.isLetter else { return nil }
        return character
    }

    static func keyCharacter(characters: String?, keyCode: UInt16) -> Character? {
        let typed = (characters ?? "").lowercased()
        if typed.count == 1, let character = typed.first {
            if character.isASCII { return character.isLetter || "[]`=+-_".contains(character) ? character : nil }
            guard character.isLetter else { return nil }
        } else if !typed.isEmpty {
            return nil
        }
        return positionKeyCodes[keyCode]
    }

    static func zoomChord(characters: String?, keyCode: UInt16, shift: Bool) -> EaselZoomCommand? {
        let typed = characters ?? ""
        switch typed {
        case "=", "+": return .zoomIn
        case "-", "_": return .zoomOut
        case "0": return shift ? nil : .actualSize
        default: break
        }
        guard !shift, typed.isEmpty || typed.unicodeScalars.contains(where: { !$0.isASCII }) else { return nil }
        switch keyCode {
        case 24, 69: return .zoomIn
        case 27, 78: return .zoomOut
        case 29, 82: return shift ? nil : .actualSize
        default: return nil
        }
    }
}

enum EaselToolGeometry {
    static let dragThreshold = 3.0

    static func placedFrame(_ tool: EaselTool, at point: EaselPoint) -> EaselRect {
        let size = tool.defaultSize
        if tool == .text { return EaselRect(x: point.x, y: point.y - 14, width: size.width, height: size.height) }
        return EaselRect(x: point.x - size.width / 2, y: point.y - size.height / 2,
                         width: max(1, size.width), height: max(1, size.height))
    }

    static func draggedFrame(from start: EaselPoint, to end: EaselPoint, square: Bool, centered: Bool) -> EaselRect {
        var dx = end.x - start.x, dy = end.y - start.y
        if square {
            let side = max(abs(dx), abs(dy))
            dx = dx < 0 ? -side : side
            dy = dy < 0 ? -side : side
        }
        if centered {
            return EaselRect(x: start.x - abs(dx), y: start.y - abs(dy), width: max(1, abs(dx) * 2), height: max(1, abs(dy) * 2))
        }
        return EaselRect(x: min(start.x, start.x + dx), y: min(start.y, start.y + dy), width: max(1, abs(dx)), height: max(1, abs(dy)))
    }

    static func snappedLineEnd(from start: EaselPoint, to end: EaselPoint) -> EaselPoint {
        let dx = end.x - start.x, dy = end.y - start.y
        let length = hypot(dx, dy)
        guard length > 0 else { return end }
        let step = Double.pi / 4
        let angle = (atan2(dy, dx) / step).rounded() * step
        let snapped = EaselPoint(x: start.x + cos(angle) * length, y: start.y + sin(angle) * length)
        return EaselPoint(x: abs(snapped.x - start.x) < 1e-9 ? start.x : snapped.x,
                          y: abs(snapped.y - start.y) < 1e-9 ? start.y : snapped.y)
    }

    static func lineItemGeometry(from start: EaselPoint, to end: EaselPoint) -> (frame: EaselRect, points: [EaselPoint]) {
        let minX = min(start.x, end.x), minY = min(start.y, end.y)
        let frame = EaselRect(x: minX, y: minY, width: max(1, abs(end.x - start.x)), height: max(1, abs(end.y - start.y)))
        return (frame, [EaselPoint(x: start.x - minX, y: start.y - minY), EaselPoint(x: end.x - minX, y: end.y - minY)])
    }

    static func constrained(_ frame: EaselRect, to bounds: EaselRect) -> EaselRect {
        let width = min(frame.width, bounds.width), height = min(frame.height, bounds.height)
        return EaselRect(x: min(max(frame.x, bounds.x), bounds.x + bounds.width - width),
                         y: min(max(frame.y, bounds.y), bounds.y + bounds.height - height),
                         width: max(1, width), height: max(1, height))
    }

    static func clamped(_ point: EaselPoint, to bounds: EaselRect) -> EaselPoint {
        EaselPoint(x: min(max(point.x, bounds.x), bounds.x + bounds.width),
                   y: min(max(point.y, bounds.y), bounds.y + bounds.height))
    }
}

enum EaselZoom {
    static let levels: [Double] = [0.25, 0.3333, 0.5, 0.75, 1, 1.5, 2, 3, 4]
    static let presets: [Double] = [0.5, 1, 2]
    static let fitPadding = 48.0
    static let animationDuration = 0.24

    static func stepped(from current: Double, zoomingIn: Bool, minimum: Double, maximum: Double) -> Double {
        guard minimum.isFinite, maximum.isFinite, minimum > 0, maximum >= minimum else { return 1 }
        guard current.isFinite, current > 0 else { return min(maximum, max(minimum, 1)) }
        let tolerance = 0.005
        let candidates = levels.filter { $0 >= minimum - tolerance && $0 <= maximum + tolerance }
        let next = zoomingIn ? candidates.first { $0 > current * (1 + tolerance) } : candidates.last { $0 < current * (1 - tolerance) }
        return min(maximum, max(minimum, next ?? (zoomingIn ? current * 2 : current / 2)))
    }

    static func clamped(_ value: Double, minimum: Double, maximum: Double) -> Double {
        guard value.isFinite, value > 0 else { return min(maximum, max(minimum, 1)) }
        return min(maximum, max(minimum, value))
    }

    static func fitting(_ content: EaselRect, viewport: (width: Double, height: Double), padding: Double = fitPadding,
                        minimum: Double, maximum: Double) -> Double? {
        guard content.width > 0, content.height > 0, viewport.width > 0, viewport.height > 0,
              [content.width, content.height, viewport.width, viewport.height].allSatisfy(\.isFinite) else { return nil }
        let room = (width: max(1, viewport.width - 2 * padding), height: max(1, viewport.height - 2 * padding))
        return clamped(min(room.width / content.width, room.height / content.height), minimum: minimum, maximum: maximum)
    }

    static func bounds(of frames: [EaselRect]) -> EaselRect? {
        guard let first = frames.first else { return nil }
        var minX = first.x, minY = first.y, maxX = first.x + first.width, maxY = first.y + first.height
        for frame in frames.dropFirst() {
            minX = min(minX, frame.x); minY = min(minY, frame.y)
            maxX = max(maxX, frame.x + frame.width); maxY = max(maxY, frame.y + frame.height)
        }
        return EaselRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    static func wheelFactor(deviceDelta: Double, precise: Bool) -> Double {
        guard deviceDelta.isFinite, deviceDelta != 0 else { return 1 }
        let factor = precise ? exp(max(-40, min(40, deviceDelta)) * 0.0125) : pow(1.2, max(-3, min(3, deviceDelta)))
        return max(0.5, min(2, factor))
    }

    static func percent(_ magnification: Double) -> Int {
        guard magnification.isFinite, magnification > 0 else { return 100 }
        return Int((min(magnification, 1000) * 100).rounded())
    }

    static func interpolated(from start: Double, to end: Double, progress: Double) -> Double {
        guard start > 0, end > 0 else { return end }
        let t = min(1, max(0, progress))
        return start * pow(end / start, t)
    }

    static func eased(_ progress: Double) -> Double {
        let t = min(1, max(0, progress))
        return 1 - pow(1 - t, 3)
    }
}
