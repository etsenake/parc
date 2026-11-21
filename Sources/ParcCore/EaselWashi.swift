import Foundation

package enum EaselWashiPattern: String, CaseIterable {
    case stripes, dots, grid, zigzag, gingham, confetti, kraft

    package var title: String {
        switch self {
        case .stripes: return "Stripes"
        case .dots: return "Polka dots"
        case .grid: return "Grid"
        case .zigzag: return "Zigzag"
        case .gingham: return "Gingham"
        case .confetti: return "Confetti"
        case .kraft: return "Kraft"
        }
    }

    package var family: NoteColor {
        switch self {
        case .stripes: return .pink
        case .dots: return .blue
        case .grid: return .blue
        case .zigzag: return .yellow
        case .gingham: return .red
        case .confetti: return .purple
        case .kraft: return .brown
        }
    }
}

package struct EaselWashiMark: Equatable {
    package enum Shape: Equatable {
        case rect(EaselRect)
        case circle(EaselPoint, radius: Double)
        case polygon([EaselPoint])
    }

    package var shape: Shape
    package var color: String
    package var opacity: Double
}

package struct EaselWashiTile: Equatable {
    package var width: Double
    package var height: Double
    package var base: String
    package var marks: [EaselWashiMark]

    package init(width: Double, height: Double, base: String, marks: [EaselWashiMark]) {
        self.width = width
        self.height = height
        self.base = base
        self.marks = marks
    }
}

package struct EaselWashiPlacement: Equatable {
    package var origin: EaselPoint
    package var angle: Double
    package var length: Double

    package init(origin: EaselPoint, angle: Double, length: Double) {
        self.origin = origin
        self.angle = angle
        self.length = length
    }
}

package enum EaselWashi {
    package static let width = 28.0
    package static let opacity = 0.9
    package static let defaultPattern = EaselWashiPattern.stripes
    package static let tooth = 1.6

    package static func pattern(_ item: EaselItem) -> EaselWashiPattern { pattern(named: item.pattern) }

    package static func pattern(named name: String?) -> EaselWashiPattern {
        name.flatMap(EaselWashiPattern.init(rawValue:)) ?? defaultPattern
    }

    package static func storedName(_ pattern: EaselWashiPattern) -> String? { pattern == defaultPattern ? nil : pattern.rawValue }

    package static func placement(_ item: EaselItem) -> EaselWashiPlacement? {
        guard let first = item.points.first, let last = item.points.last else { return nil }
        let start = EaselPoint(x: item.frame.x + first.x, y: item.frame.y + first.y)
        let end = EaselPoint(x: item.frame.x + last.x, y: item.frame.y + last.y)
        let length = hypot(end.x - start.x, end.y - start.y)
        guard length.isFinite else { return nil }
        return EaselWashiPlacement(origin: start, angle: length > 0 ? atan2(end.y - start.y, end.x - start.x) : 0, length: length)
    }

    package static func seed(_ id: UUID) -> UInt64 {
        let bytes = id.uuid
        return [bytes.0, bytes.1, bytes.2, bytes.3, bytes.4, bytes.5, bytes.6, bytes.7]
            .reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
    }

    package static func outline(length: Double, seed: UInt64) -> [EaselPoint] {
        var random = Generator(seed: seed)
        let half = width / 2, teeth = 7
        func edge(at x: Double) -> [EaselPoint] {
            (0...teeth).map { index in
                let jitter = index == 0 || index == teeth ? 0 : (index.isMultiple(of: 2) ? -1.0 : 1.0) * tooth * (0.55 + 0.45 * random.next())
                return EaselPoint(x: x + jitter, y: -half + width * Double(index) / Double(teeth))
            }
        }
        let end = max(0, length.isFinite ? length : 0)
        let left = edge(at: 0), right = edge(at: end)
        return right + left.reversed()
    }

    package static func tile(_ pattern: EaselWashiPattern, color: String) -> EaselWashiTile {
        let white = EaselPalette.neutralLight, h = width
        var note = pattern.family, custom: String?
        switch tint(color) {
        case .automatic: break
        case .palette(let value): note = value
        case .custom(let value): custom = value
        }
        let chosen = tint(color) != .automatic
        let sticky = custom ?? hex(note, .sticky), ink = custom ?? hex(note, .ink), fill = custom ?? hex(note, .fill)
        switch pattern {
        case .stripes:
            let bands = stride(from: 0.0, through: 14 + h, by: 7).enumerated().compactMap { index, x -> EaselWashiMark? in
                guard index.isMultiple(of: 2) else { return nil }
                let band = clipped([EaselPoint(x: x, y: 0), EaselPoint(x: x + 4, y: 0), EaselPoint(x: x + 4 - h, y: h), EaselPoint(x: x - h, y: h)],
                                   to: EaselRect(x: 0, y: 0, width: 14, height: h))
                return band.count >= 3 ? EaselWashiMark(shape: .polygon(band), color: white, opacity: 0.55) : nil
            }
            return EaselWashiTile(width: 14, height: h, base: sticky, marks: bands)
        case .dots:
            let dots = [EaselPoint(x: 4, y: 5), EaselPoint(x: 12, y: 14), EaselPoint(x: 4, y: 23)].map {
                EaselWashiMark(shape: .circle($0, radius: 2.4), color: white, opacity: 0.9)
            }
            return EaselWashiTile(width: 16, height: h, base: sticky, marks: dots)
        case .grid:
            let lines = [EaselWashiMark(shape: .rect(EaselRect(x: 0, y: 0, width: 0.75, height: h)), color: ink, opacity: 0.32)]
                + stride(from: 0.0, to: h, by: 7).map {
                    EaselWashiMark(shape: .rect(EaselRect(x: 0, y: $0, width: 7, height: 0.75)), color: ink, opacity: 0.32)
                }
            return EaselWashiTile(width: 7, height: h, base: white, marks: lines)
        case .zigzag:
            func zigzag(_ center: Double, _ color: String, _ opacity: Double) -> EaselWashiMark {
                let a = 3.5, t = 3.2
                return EaselWashiMark(shape: .polygon([EaselPoint(x: 0, y: center - a), EaselPoint(x: 7, y: center + a), EaselPoint(x: 14, y: center - a),
                                                       EaselPoint(x: 14, y: center - a + t), EaselPoint(x: 7, y: center + a + t), EaselPoint(x: 0, y: center - a + t)]),
                                      color: color, opacity: opacity)
            }
            return EaselWashiTile(width: 14, height: h, base: sticky, marks: [zigzag(7, white, 0.8), zigzag(17, ink, 0.3)])
        case .gingham:
            let marks = [EaselWashiMark(shape: .rect(EaselRect(x: 0, y: 0, width: 7, height: h)), color: ink, opacity: 0.26),
                         EaselWashiMark(shape: .rect(EaselRect(x: 0, y: 0, width: 14, height: 7)), color: ink, opacity: 0.26),
                         EaselWashiMark(shape: .rect(EaselRect(x: 0, y: 14, width: 14, height: 7)), color: ink, opacity: 0.26)]
            return EaselWashiTile(width: 14, height: h, base: white, marks: marks)
        case .confetti:
            let colors: [NoteColor] = [.red, .blue, .orange, .green, .purple, .pink, .yellow, .blue, .red]
            let pieces: [(EaselPoint, Double, Double)] = [(EaselPoint(x: 6, y: 6), 0, 0), (EaselPoint(x: 17, y: 7), 6, 30),
                (EaselPoint(x: 27, y: 5), 0, 0), (EaselPoint(x: 36, y: 10), 5, -40), (EaselPoint(x: 9, y: 18), 5, 75),
                (EaselPoint(x: 21, y: 17), 0, 0), (EaselPoint(x: 31, y: 21), 6, 65), (EaselPoint(x: 39, y: 22), 0, 0),
                (EaselPoint(x: 14, y: 24), 5, -15)]
            let marks = zip(pieces, colors).map { piece, color -> EaselWashiMark in
                let (center, length, degrees) = piece
                let paint = hex(color, .ink)
                guard length > 0 else { return EaselWashiMark(shape: .circle(center, radius: 1.8), color: paint, opacity: 0.9) }
                return EaselWashiMark(shape: .polygon(dash(center, length: length, thickness: 2, degrees: degrees)), color: paint, opacity: 0.9)
            }
            return EaselWashiTile(width: 42, height: h, base: chosen ? fill : white, marks: marks)
        case .kraft:
            var random = Generator(seed: 0x6B72_6166_74)
            let fibres = (0..<16).map { index -> EaselWashiMark in
                let center = EaselPoint(x: 3 + random.next() * 42, y: 3 + random.next() * (h - 6))
                let shape = dash(center, length: 2 + random.next() * 3, thickness: 0.6 + random.next() * 0.4, degrees: random.next() * 180)
                return EaselWashiMark(shape: .polygon(shape), color: index.isMultiple(of: 3) ? white : ink, opacity: index.isMultiple(of: 3) ? 0.4 : 0.28)
            }
            return EaselWashiTile(width: 48, height: h, base: sticky, marks: fibres)
        }
    }

    package enum Tint: Equatable {
        case automatic
        case palette(NoteColor)
        case custom(String)
    }

    package static func tint(_ color: String) -> Tint {
        guard let value = EaselPalette.normalized(color), value != EaselPalette.automaticInk else { return .automatic }
        for role in EaselColorRole.allCases {
            if case .note(let note)? = EaselPalette.color(for: value, role: role) { return .palette(note) }
        }
        return .custom(value)
    }

    package static func dash(_ center: EaselPoint, length: Double, thickness: Double, degrees: Double) -> [EaselPoint] {
        let radians = degrees * Double.pi / 180
        return [EaselPoint(x: -length / 2, y: -thickness / 2), EaselPoint(x: length / 2, y: -thickness / 2),
                EaselPoint(x: length / 2, y: thickness / 2), EaselPoint(x: -length / 2, y: thickness / 2)].map {
            let turned = EaselDrawing.rotated($0, by: radians)
            return EaselPoint(x: center.x + turned.x, y: center.y + turned.y)
        }
    }

    package static func clipped(_ polygon: [EaselPoint], to rect: EaselRect) -> [EaselPoint] {
        var result = polygon
        let edges: [(EaselPoint) -> Double] = [{ $0.x - rect.x }, { rect.x + rect.width - $0.x },
                                               { $0.y - rect.y }, { rect.y + rect.height - $0.y }]
        for inside in edges {
            guard let last = result.last else { break }
            var output: [EaselPoint] = [], previous = last
            for point in result {
                let a = inside(previous), b = inside(point)
                if b >= 0 {
                    if a < 0 { output.append(crossing(previous, point, a, b)) }
                    output.append(point)
                } else if a >= 0 {
                    output.append(crossing(previous, point, a, b))
                }
                previous = point
            }
            result = output
        }
        return result
    }

    private static func crossing(_ p: EaselPoint, _ q: EaselPoint, _ a: Double, _ b: Double) -> EaselPoint {
        let t = a / (a - b)
        return EaselPoint(x: p.x + (q.x - p.x) * t, y: p.y + (q.y - p.y) * t)
    }

    private static func hex(_ color: NoteColor, _ role: EaselColorRole) -> String {
        EaselPalette.hex(.note(color), role: role) ?? EaselPalette.neutralLight
    }

    private struct Generator {
        var state: UInt64
        init(seed: UInt64) { state = seed &+ 0x9E37_79B9_7F4A_7C15 }
        mutating func next() -> Double {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Double(state >> 11) / Double(UInt64(1) << 53)
        }
    }
}
