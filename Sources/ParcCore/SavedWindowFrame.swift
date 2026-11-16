import CoreGraphics
import Foundation

struct SavedWindowFrame: Codable, Equatable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double

    init?(_ rect: CGRect) {
        self.init(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height)
    }

    init?(x: Double, y: Double, width: Double, height: Double) {
        guard [x, y, width, height].allSatisfy({ $0.isFinite && abs($0) <= 1e7 }), width > 0, height > 0 else { return nil }
        self.x = x; self.y = y; self.width = width; self.height = height
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        guard let frame = Self(x: try values.decode(Double.self, forKey: .x), y: try values.decode(Double.self, forKey: .y),
                               width: try values.decode(Double.self, forKey: .width),
                               height: try values.decode(Double.self, forKey: .height)) else {
            throw DecodingError.dataCorruptedError(forKey: .width, in: values, debugDescription: "Not a usable window frame")
        }
        self = frame
    }

    var rect: CGRect { CGRect(x: x, y: y, width: width, height: height) }

    func placed(minimumSize: CGSize, screens: [CGRect]) -> CGRect? {
        let usable = screens.filter { screen in
            [screen.minX, screen.minY, screen.width, screen.height].allSatisfy(\.isFinite)
                && screen.width > 0 && screen.height > 0
        }
        guard !usable.isEmpty else { return nil }
        let grown = CGSize(width: max(width, minimumSize.width), height: max(height, minimumSize.height))
        let wanted = CGRect(x: x, y: y + height - grown.height, width: grown.width, height: grown.height)
        if usable.contains(where: { $0.contains(wanted) }) { return wanted }
        let screen = Self.nearestScreen(to: wanted, in: usable)
        let size = CGSize(width: min(grown.width, screen.width), height: min(grown.height, screen.height))
        return CGRect(x: min(max(wanted.minX, screen.minX), screen.maxX - size.width),
                      y: min(max(wanted.maxY - size.height, screen.minY), screen.maxY - size.height),
                      width: size.width, height: size.height)
    }

    private static func nearestScreen(to frame: CGRect, in screens: [CGRect]) -> CGRect {
        func overlap(_ screen: CGRect) -> CGFloat {
            let shared = screen.intersection(frame)
            return shared.isNull ? 0 : shared.width * shared.height
        }
        func distance(_ screen: CGRect) -> CGFloat {
            let dx = max(screen.minX - frame.midX, 0, frame.midX - screen.maxX)
            let dy = max(screen.minY - frame.midY, 0, frame.midY - screen.maxY)
            return dx * dx + dy * dy
        }
        var best = screens[0]
        for screen in screens.dropFirst() {
            let (current, candidate) = (overlap(best), overlap(screen))
            if candidate > current || (candidate == current && current == 0 && distance(screen) < distance(best)) {
                best = screen
            }
        }
        return best
    }
}
