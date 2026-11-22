import CoreGraphics
import Foundation

package struct NoteImageCrop: Hashable, Codable {
    package var x: Double
    package var y: Double
    package var width: Double
    package var height: Double

    package static let full = NoteImageCrop(x: 0, y: 0, width: 1, height: 1)
    package static let minimumSide = 0.01
    package static let precision = 10_000.0

    package init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    package init(_ rect: CGRect, in bounds: CGRect) {
        guard bounds.width > 0, bounds.height > 0 else { self = .full; return }
        self = NoteImageCrop(x: Double((rect.minX - bounds.minX) / bounds.width), y: Double((rect.minY - bounds.minY) / bounds.height),
                             width: Double(rect.width / bounds.width), height: Double(rect.height / bounds.height)).normalized
    }

    package init?(attribute: String) {
        let parts = attribute.split(separator: ",", omittingEmptySubsequences: false)
            .map { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard parts.count == 4, let x = parts[0], let y = parts[1], let width = parts[2], let height = parts[3],
              x.isFinite, y.isFinite, width.isFinite, height.isFinite, width > 0, height > 0 else { return nil }
        self = NoteImageCrop(x: x, y: y, width: width, height: height).normalized
    }

    package var normalized: NoteImageCrop {
        func value(_ number: Double, _ fallback: Double) -> Double { number.isFinite ? number : fallback }
        let width = Self.rounded(min(1, max(Self.minimumSide, value(width, 1))))
        let height = Self.rounded(min(1, max(Self.minimumSide, value(height, 1))))
        let x = Self.rounded(min(max(0, value(x, 0)), 1 - width))
        let y = Self.rounded(min(max(0, value(y, 0)), 1 - height))
        return NoteImageCrop(x: x, y: y, width: width, height: height)
    }

    package var isFull: Bool {
        let tolerance = 0.5 / Self.precision
        return abs(x) <= tolerance && abs(y) <= tolerance && abs(width - 1) <= tolerance && abs(height - 1) <= tolerance
    }

    package var attribute: String { [x, y, width, height].map(Self.format).joined(separator: ",") }

    package func rect(in bounds: CGRect) -> CGRect {
        CGRect(x: bounds.minX + CGFloat(x) * bounds.width, y: bounds.minY + CGFloat(y) * bounds.height,
               width: CGFloat(width) * bounds.width, height: CGFloat(height) * bounds.height)
    }

    package func croppedSize(of natural: CGSize) -> CGSize {
        CGSize(width: natural.width * CGFloat(width), height: natural.height * CGFloat(height))
    }

    package func fullRect(forFrame frame: CGRect) -> CGRect {
        let fullWidth = frame.width / CGFloat(max(width, Self.minimumSide))
        let fullHeight = frame.height / CGFloat(max(height, Self.minimumSide))
        return CGRect(x: frame.minX - CGFloat(x) * fullWidth, y: frame.minY - CGFloat(y) * fullHeight, width: fullWidth, height: fullHeight)
    }

    package static func rounded(_ value: Double) -> Double { (value * precision).rounded() / precision }

    package static func format(_ value: Double) -> String {
        var text = String(format: "%.4f", rounded(value))
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text == "-0" ? "0" : text
    }
}

package enum NoteImageMask: String, Hashable, Codable, CaseIterable {
    case rounded, circle, squircle, arch, diamond, hexagon, star, heart

    package var title: String {
        switch self {
        case .rounded: return "Rounded"
        case .circle: return "Circle"
        case .squircle: return "Squircle"
        case .arch: return "Arch"
        case .diamond: return "Diamond"
        case .hexagon: return "Hexagon"
        case .star: return "Star"
        case .heart: return "Heart"
        }
    }

    package static let noneTitle = "Original"

    package var isSquare: Bool { self != .rounded && self != .arch }

    static func roundedRadius(for size: CGSize) -> CGFloat { max(0, min(size.width, size.height)) * 0.1 }

    static func archRadius(for size: CGSize) -> CGFloat { max(0, min(size.width / 2, size.height)) }

    package func path(in rect: CGRect) -> CGPath {
        guard rect.width > 0, rect.height > 0 else { return CGPath(rect: rect, transform: nil) }
        switch self {
        case .rounded:
            let radius = min(Self.roundedRadius(for: rect.size), rect.width / 2, rect.height / 2)
            return CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
        case .circle:
            return CGPath(ellipseIn: rect, transform: nil)
        case .arch:
            let radius = Self.archRadius(for: rect.size)
            let path = CGMutablePath()
            path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + radius))
            path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.minY), tangent2End: CGPoint(x: rect.minX + radius, y: rect.minY), radius: radius)
            path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
            path.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.minY), tangent2End: CGPoint(x: rect.maxX, y: rect.minY + radius), radius: radius)
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.closeSubpath()
            return path
        default:
            var transform = CGAffineTransform(translationX: rect.minX, y: rect.minY).scaledBy(x: rect.width, y: rect.height)
            return unitPath.copy(using: &transform) ?? unitPath
        }
    }

    var unitPath: CGPath {
        switch self {
        case .rounded, .circle, .arch: return path(in: CGRect(x: 0, y: 0, width: 1, height: 1))
        case .squircle: return Self.squirclePath
        case .diamond: return Self.diamondPath
        case .hexagon: return Self.hexagonPath
        case .star: return Self.starPath
        case .heart: return Self.heartPath
        }
    }

    private static let squirclePath: CGPath = {
        let path = CGMutablePath()
        let exponent = 5.0, steps = 160
        for step in 0..<steps {
            let angle = Double(step) / Double(steps) * 2 * Double.pi
            let c = cos(angle), s = sin(angle)
            let x = 0.5 + 0.5 * copysign(pow(abs(c), 2 / exponent), c)
            let y = 0.5 + 0.5 * copysign(pow(abs(s), 2 / exponent), s)
            let point = CGPoint(x: x, y: y)
            if step == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }()

    private static func roundedPolygon(_ points: [CGPoint], radius: CGFloat) -> CGPath {
        let path = CGMutablePath()
        let count = points.count
        guard count > 2 else { return path }
        let start = CGPoint(x: (points[count - 1].x + points[0].x) / 2, y: (points[count - 1].y + points[0].y) / 2)
        path.move(to: start)
        for index in 0..<count {
            let corner = points[index], next = points[(index + 1) % count]
            path.addArc(tangent1End: corner, tangent2End: next, radius: radius)
        }
        path.closeSubpath()
        return path
    }

    private static let diamondPath = roundedPolygon([CGPoint(x: 0.5, y: 0), CGPoint(x: 1, y: 0.5), CGPoint(x: 0.5, y: 1), CGPoint(x: 0, y: 0.5)],
                                                    radius: 0.06)

    private static let hexagonPath: CGPath = {
        let points = (0..<6).map { index -> CGPoint in
            let angle = (Double(index) * 60 - 90) * Double.pi / 180
            return CGPoint(x: 0.5 + 0.5 * cos(angle), y: 0.5 + 0.5 * sin(angle))
        }
        return roundedPolygon(points, radius: 0.05)
    }()

    private static let starPath: CGPath = {
        let outer = 0.5 / sin(72 * Double.pi / 180)
        let inner = outer * 0.5
        let height = outer * (1 + cos(36 * Double.pi / 180))
        let center = CGPoint(x: 0.5, y: (1 - height) / 2 + outer)
        let points = (0..<10).map { index -> CGPoint in
            let radius = index % 2 == 0 ? outer : inner
            let angle = (Double(index) * 36 - 90) * Double.pi / 180
            return CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
        }
        return roundedPolygon(points, radius: 0.035)
    }()

    private static let heartPath: CGPath = {
        let lift = (1 - 0.9175) / 2
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y + lift) }
        let path = CGMutablePath()
        path.move(to: p(0.5, 0.9175))
        path.addLine(to: p(0.4275, 0.8515))
        path.addCurve(to: p(0, 0.275), control1: p(0.17, 0.618), control2: p(0, 0.464))
        path.addCurve(to: p(0.275, 0), control1: p(0, 0.121), control2: p(0.121, 0))
        path.addCurve(to: p(0.5, 0.1045), control1: p(0.362, 0), control2: p(0.4455, 0.0405))
        path.addCurve(to: p(0.725, 0), control1: p(0.5545, 0.0405), control2: p(0.638, 0))
        path.addCurve(to: p(1, 0.275), control1: p(0.879, 0), control2: p(1, 0.121))
        path.addCurve(to: p(0.5725, 0.852), control1: p(1, 0.464), control2: p(0.83, 0.618))
        path.closeSubpath()
        return path
    }()

    var svgPathData: String { Self.svgData(unitPath) }

    static func svgData(_ path: CGPath) -> String {
        var parts: [String] = []
        func point(_ value: CGPoint) -> String { NoteImageCrop.format(Double(value.x)) + " " + NoteImageCrop.format(Double(value.y)) }
        path.applyWithBlock { element in
            let points = element.pointee.points
            switch element.pointee.type {
            case .moveToPoint: parts.append("M" + point(points[0]))
            case .addLineToPoint: parts.append("L" + point(points[0]))
            case .addQuadCurveToPoint: parts.append("Q" + point(points[0]) + " " + point(points[1]))
            case .addCurveToPoint: parts.append("C" + point(points[0]) + " " + point(points[1]) + " " + point(points[2]))
            case .closeSubpath: parts.append("Z")
            @unknown default: break
            }
        }
        return parts.joined()
    }

    var maskImageURL: String {
        let svg = "<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 1 1' preserveAspectRatio='none'><path d='" + svgPathData + "'/></svg>"
        return "data:image/svg+xml," + svg.replacingOccurrences(of: "<", with: "%3C").replacingOccurrences(of: ">", with: "%3E")
    }

    func borderRadius(frameAspect: Double?) -> String? {
        switch self {
        case .circle: return "50%"
        case .arch: return "9999px 9999px 0 0"
        case .rounded:
            guard let aspect = frameAspect, aspect.isFinite, aspect > 0 else { return "16px" }
            let horizontal = 10 * min(1, aspect), vertical = 10 * min(1, 1 / aspect)
            return NoteImageCrop.format(horizontal) + "%/" + NoteImageCrop.format(vertical) + "%"
        default: return nil
        }
    }
}

package enum NoteImageCropHandle: CaseIterable, Hashable {
    case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left

    package var movesLeft: Bool { self == .topLeft || self == .left || self == .bottomLeft }
    package var movesRight: Bool { self == .topRight || self == .right || self == .bottomRight }
    package var movesTop: Bool { self == .topLeft || self == .top || self == .topRight }
    package var movesBottom: Bool { self == .bottomLeft || self == .bottom || self == .bottomRight }
    package var isCorner: Bool { (movesLeft || movesRight) && (movesTop || movesBottom) }

    package var title: String {
        switch self {
        case .topLeft: return "top left corner"
        case .top: return "top edge"
        case .topRight: return "top right corner"
        case .right: return "right edge"
        case .bottomRight: return "bottom right corner"
        case .bottom: return "bottom edge"
        case .bottomLeft: return "bottom left corner"
        case .left: return "left edge"
        }
    }
}

package enum NoteImageCropAspect: Hashable, CaseIterable {
    case free, original, square, landscape43, portrait34, wide169, tall916

    package var id: String {
        switch self {
        case .free: return "free"
        case .original: return "original"
        case .square: return "square"
        case .landscape43: return "4:3"
        case .portrait34: return "3:4"
        case .wide169: return "16:9"
        case .tall916: return "9:16"
        }
    }

    package var title: String {
        switch self {
        case .free: return "Freeform"
        case .original: return "Original"
        case .square: return "Square"
        case .landscape43: return "4:3"
        case .portrait34: return "3:4"
        case .wide169: return "16:9"
        case .tall916: return "9:16"
        }
    }

    package func ratio(natural: CGSize?) -> CGFloat? {
        switch self {
        case .free: return nil
        case .original:
            guard let natural, natural.width > 0, natural.height > 0 else { return nil }
            return natural.width / natural.height
        case .square: return 1
        case .landscape43: return 4.0 / 3.0
        case .portrait34: return 3.0 / 4.0
        case .wide169: return 16.0 / 9.0
        case .tall916: return 9.0 / 16.0
        }
    }
}

package enum NoteImageCropGeometry {
    package static func move(_ rect: CGRect, by delta: CGSize, within bounds: CGRect) -> CGRect {
        let x = min(max(bounds.minX, rect.minX + delta.width), bounds.maxX - rect.width)
        let y = min(max(bounds.minY, rect.minY + delta.height), bounds.maxY - rect.height)
        return CGRect(x: x, y: y, width: rect.width, height: rect.height)
    }

    package static func resize(_ start: CGRect, handle: NoteImageCropHandle, by delta: CGSize, within bounds: CGRect,
                       minimum: CGFloat, aspect: CGFloat?) -> CGRect {
        let floor = min(minimum, bounds.width, bounds.height)
        guard let aspect, aspect.isFinite, aspect > 0 else {
            var minX = start.minX, maxX = start.maxX, minY = start.minY, maxY = start.maxY
            if handle.movesLeft { minX = min(max(bounds.minX, start.minX + delta.width), maxX - floor) }
            if handle.movesRight { maxX = max(min(bounds.maxX, start.maxX + delta.width), minX + floor) }
            if handle.movesTop { minY = min(max(bounds.minY, start.minY + delta.height), maxY - floor) }
            if handle.movesBottom { maxY = max(min(bounds.maxY, start.maxY + delta.height), minY + floor) }
            return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        }
        let minimumWidth = max(floor, floor * aspect)
        if handle.isCorner {
            let anchor = CGPoint(x: handle.movesLeft ? start.maxX : start.minX, y: handle.movesTop ? start.maxY : start.minY)
            let proposedWidth = start.width + (handle.movesLeft ? -delta.width : delta.width)
            let proposedHeight = start.height + (handle.movesTop ? -delta.height : delta.height)
            var width = max(proposedWidth, proposedHeight * aspect)
            let roomX = handle.movesLeft ? anchor.x - bounds.minX : bounds.maxX - anchor.x
            let roomY = handle.movesTop ? anchor.y - bounds.minY : bounds.maxY - anchor.y
            width = min(max(width, minimumWidth), roomX, roomY * aspect)
            let height = width / aspect
            return CGRect(x: handle.movesLeft ? anchor.x - width : anchor.x, y: handle.movesTop ? anchor.y - height : anchor.y,
                          width: width, height: height)
        }
        if handle.movesLeft || handle.movesRight {
            let anchorX = handle.movesLeft ? start.maxX : start.minX
            let room = handle.movesLeft ? anchorX - bounds.minX : bounds.maxX - anchorX
            let proposed = start.width + (handle.movesLeft ? -delta.width : delta.width)
            let width = min(max(proposed, minimumWidth), room, bounds.height * aspect)
            let height = width / aspect
            let y = min(max(bounds.minY, start.midY - height / 2), bounds.maxY - height)
            return CGRect(x: handle.movesLeft ? anchorX - width : anchorX, y: y, width: width, height: height)
        }
        let anchorY = handle.movesTop ? start.maxY : start.minY
        let room = handle.movesTop ? anchorY - bounds.minY : bounds.maxY - anchorY
        let proposed = start.height + (handle.movesTop ? -delta.height : delta.height)
        let height = min(max(proposed, minimumWidth / aspect), room, bounds.width / aspect)
        let width = height * aspect
        let x = min(max(bounds.minX, start.midX - width / 2), bounds.maxX - width)
        return CGRect(x: x, y: handle.movesTop ? anchorY - height : anchorY, width: width, height: height)
    }

    package static func fitted(aspect: CGFloat, around rect: CGRect, within bounds: CGRect) -> CGRect {
        guard aspect.isFinite, aspect > 0, bounds.width > 0, bounds.height > 0 else { return rect }
        var size = bounds.width / bounds.height > aspect ? CGSize(width: bounds.height * aspect, height: bounds.height)
            : CGSize(width: bounds.width, height: bounds.width / aspect)
        let area = rect.width * rect.height
        if area > 0, size.width * size.height > area * 1.0001 {
            let shrink = sqrt(area / (size.width * size.height))
            size = CGSize(width: size.width * shrink, height: size.height * shrink)
        }
        let x = min(max(bounds.minX, rect.midX - size.width / 2), bounds.maxX - size.width)
        let y = min(max(bounds.minY, rect.midY - size.height / 2), bounds.maxY - size.height)
        return CGRect(x: x, y: y, width: size.width, height: size.height)
    }

    package static func matches(_ rect: CGRect, aspect: CGFloat?) -> Bool {
        guard let aspect, rect.height > 0 else { return true }
        return abs(rect.width / rect.height - aspect) < 0.01
    }
}

package enum NoteImageFraming {
    static func squareCrop(_ crop: NoteImageCrop?, natural: CGSize?) -> NoteImageCrop? {
        guard let natural, natural.width > 0, natural.height > 0 else { return crop }
        let bounds = CGRect(origin: .zero, size: natural)
        let current = (crop ?? .full).rect(in: bounds)
        guard abs(current.width - current.height) > 0.5 else { return crop }
        let side = min(current.width, current.height)
        let square = CGRect(x: current.midX - side / 2, y: current.midY - side / 2, width: side, height: side)
        let result = NoteImageCrop(square, in: bounds)
        return result.isFull ? nil : result
    }

    package static func applying(_ mask: NoteImageMask?, to props: NoteBlockProps, natural: CGSize?) -> NoteBlockProps {
        var next = props
        next.mask = mask
        if mask?.isSquare == true { next.crop = squareCrop(props.crop, natural: natural) }
        return next
    }

    static func frameAspect(crop: NoteImageCrop?, natural: CGSize?) -> Double? {
        guard let natural, natural.width > 0, natural.height > 0 else { return nil }
        let size = (crop ?? .full).croppedSize(of: natural)
        guard size.width > 0 else { return nil }
        return Double(size.height / size.width)
    }
}
