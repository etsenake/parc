import Foundation

enum EaselToolbarSubject: String, CaseIterable, Equatable {
    case text, sticky, shape, connector, section, image, drawing, page, table, code

    init(_ kind: EaselItemKind) {
        switch kind {
        case .text: self = .text
        case .sticky: self = .sticky
        case .rectangle, .circle: self = .shape
        case .arrow: self = .connector
        case .section: self = .section
        case .image: self = .image
        case .freehand: self = .drawing
        case .webCard, .browser, .link: self = .page
        case .table: self = .table
        case .code: self = .code
        }
    }
}

enum EaselToolbarControl: String, CaseIterable, Hashable {
    case unlock, sectionTitle, shape, connectorLabel
    case typeface, textSize, smaller, larger
    case bold, italic, underline, strikethrough, paragraph
    case color, textFill, outline, connectorStyle, startHead, endHead, routing
    case stickyShape, brushWidth, pattern
    case crop, replaceImage, altText
    case codeLanguage
    case alignment, link
    case arrange, tidyUp, group, createSection, lock
    case sectionOptions, more
}

enum EaselSelectionToolbarPlan {
    static func groups(for subjects: [EaselToolbarSubject], editingText: Bool, locked: Bool) -> [[EaselToolbarControl]] {
        guard let first = subjects.first else { return [] }
        let distinct = Set(subjects)
        if subjects.count == 1, first == .page { return [] }
        if locked { return [[.unlock], [.more]] }
        var groups: [[EaselToolbarControl]]
        if distinct.count == 1 {
            groups = controls(for: first, editingText: editingText && subjects.count == 1)
        } else {
            let sets = distinct.map { Set(controls(for: $0, editingText: false).joined()) }
            let shared = EaselToolbarControl.allCases.filter { control in sets.allSatisfy { $0.contains(control) } }
            groups = [shared]
        }
        if subjects.count > 1 { groups += [[.arrange, .tidyUp], [.group, .createSection, .lock]] }
        groups.append([.more])
        return groups.filter { !$0.isEmpty }
    }

    static func controls(for subject: EaselToolbarSubject, editingText: Bool) -> [[EaselToolbarControl]] {
        switch subject {
        case .text:
            return editingText
                ? [[.typeface, .textSize, .smaller, .larger], [.bold, .italic, .underline, .strikethrough], [.paragraph],
                   [.color, .textFill], [.alignment], [.link]]
                : [[.typeface, .textSize, .smaller, .larger], [.color, .textFill], [.alignment], [.link]]
        case .sticky:
            return [[.color], [.textSize, .bold, .paragraph], [.link], [.stickyShape]]
        case .shape:
            return [[.shape], [.color, .outline], [.typeface, .textSize, .bold, .paragraph], [.alignment], [.link]]
        case .connector:
            return [[.connectorLabel], [.color, .connectorStyle], [.startHead, .endHead], [.routing]]
        case .section:
            return [[.sectionTitle], [.color], [.sectionOptions]]
        case .image:
            return [[.crop, .replaceImage, .altText]]
        case .drawing:
            return [[.color, .brushWidth, .pattern]]
        case .page:
            return []
        case .table:
            return editingText
                ? [[.typeface, .textSize], [.bold, .italic, .underline, .strikethrough], [.paragraph], [.color], [.alignment], [.link]]
                : [[.typeface, .textSize], [.bold, .strikethrough], [.color], [.alignment]]
        case .code:
            return [[.codeLanguage]]
        }
    }

    static func available(_ groups: [[EaselToolbarControl]], where supported: (EaselToolbarControl) -> Bool) -> [[EaselToolbarControl]] {
        groups.map { $0.filter(supported) }.filter { !$0.isEmpty }
    }
}

struct EaselSelectionToolbarPlacement: Equatable {
    enum Edge: Equatable { case above, below, inside }

    static let gap = 8.0
    static let margin = 8.0

    var frame: EaselRect
    var edge: Edge

    static func place(selection: EaselRect, width: Double, height: Double, visible: EaselRect,
                      gap: Double = gap, margin: Double = margin) -> EaselSelectionToolbarPlacement? {
        guard width > 0, height > 0, let shown = intersection(selection, visible) else { return nil }
        let minX = visible.x + margin, maxX = max(minX, visible.x + visible.width - margin - width)
        let minY = visible.y + margin, maxY = max(minY, visible.y + visible.height - margin - height)
        func clampedX(_ x: Double) -> Double { min(max(x, minX), maxX).rounded() }
        func placed(_ x: Double, _ y: Double) -> EaselRect { EaselRect(x: clampedX(x), y: y.rounded(), width: width, height: height) }
        let centre = shown.x + shown.width / 2 - width / 2
        let top = selection.y - gap - height
        if top >= minY { return .init(frame: placed(centre, top), edge: .above) }
        let bottom = selection.y + selection.height + gap
        if bottom <= maxY { return .init(frame: placed(centre, bottom), edge: .below) }
        var candidates: [EaselRect] = []
        for y in [minY, maxY] {
            candidates.append(placed(centre, y))
            let left = selection.x - gap - width
            if left >= minX { candidates.append(placed(left, y)) }
            let right = selection.x + selection.width + gap
            if right <= maxX { candidates.append(placed(right, y)) }
        }
        let best = candidates.enumerated().min { first, second in
            let a = overlap(first.element, selection), b = overlap(second.element, selection)
            return a != b ? a < b : first.offset < second.offset
        }
        guard let frame = best?.element else { return nil }
        return .init(frame: frame, edge: .inside)
    }

    private static func intersection(_ a: EaselRect, _ b: EaselRect) -> EaselRect? {
        let x = max(a.x, b.x), y = max(a.y, b.y)
        let right = min(a.x + a.width, b.x + b.width), bottom = min(a.y + a.height, b.y + b.height)
        guard right > x, bottom > y else { return nil }
        return EaselRect(x: x, y: y, width: right - x, height: bottom - y)
    }

    private static func overlap(_ a: EaselRect, _ b: EaselRect) -> Double {
        intersection(a, b).map { $0.width * $0.height } ?? 0
    }
}
