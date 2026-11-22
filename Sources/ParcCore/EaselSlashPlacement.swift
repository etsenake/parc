import Foundation

package enum EaselSlashObject: String, CaseIterable, Hashable {
    case sticky, shape, image, video, audio, file, pdf, embed, bookmark, equation, table, code
}

package struct EaselSlashContext: Hashable {
    package var checklist = false
    package var divider = false
    package var mention = false
    package var date = false
    package var inlineEquation = false
    package var objects = true
    package init(checklist: Bool = false, divider: Bool = false, mention: Bool = false, date: Bool = false, inlineEquation: Bool = false, objects: Bool = true) {
        self.checklist = checklist
        self.divider = divider
        self.mention = mention
        self.date = date
        self.inlineEquation = inlineEquation
        self.objects = objects
    }
}

package enum EaselSlashPlacement {
    static let gap = 32.0

    package static func frame(size: (width: Double, height: Double), beside text: EaselRect, occupied: [EaselRect]) -> EaselRect {
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
