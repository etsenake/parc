import Foundation

enum EaselSlashObject: String, CaseIterable, Hashable {
    case sticky, shape, image, video, audio, file, pdf, embed, bookmark, equation, table, code
}

struct EaselSlashContext: Hashable {
    var checklist = false
    var divider = false
    var mention = false
    var date = false
    var inlineEquation = false
    var objects = true
}

enum EaselSlashPlacement {
    static let gap = 32.0

    static func frame(size: (width: Double, height: Double), beside text: EaselRect, occupied: [EaselRect]) -> EaselRect {
        guard [text.x, text.y, text.width, text.height, size.width, size.height].allSatisfy(\.isFinite) else {
            return EaselRect(x: 0, y: 0, width: size.width, height: size.height)
        }
        let right = EaselRect(x: text.x + text.width + gap, y: text.y, width: size.width, height: size.height)
        let below = EaselRect(x: text.x, y: text.y + text.height + gap, width: size.width, height: size.height)
        let left = EaselRect(x: text.x - gap - size.width, y: text.y, width: size.width, height: size.height)
        for candidate in [right, below, left] where candidate.x >= 0 && candidate.y >= 0 && !occupied.contains(where: { overlaps($0, candidate) }) {
            return candidate
        }
        return right
    }

    private static func overlaps(_ a: EaselRect, _ b: EaselRect) -> Bool {
        a.x < b.x + b.width && b.x < a.x + a.width && a.y < b.y + b.height && b.y < a.y + a.height
    }
}
