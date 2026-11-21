import Foundation

enum EaselToolbarSubject: String, CaseIterable, Equatable {
    case text, sticky, shape, connector, section, image, drawing, page

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
                ? [[.typeface, .textSize], [.bold, .italic, .underline, .strikethrough], [.paragraph],
                   [.color, .textFill], [.alignment], [.link]]
                : [[.typeface, .textSize, .smaller, .larger], [.color, .textFill], [.alignment], [.link]]
        case .sticky:
            return [[.color], [.textSize, .bold, .paragraph], [.link], [.stickyShape]]
        case .shape:
            return [[.shape], [.color, .outline], [.textSize, .bold, .paragraph], [.alignment], [.link]]
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
        }
    }

    static func available(_ groups: [[EaselToolbarControl]], where supported: (EaselToolbarControl) -> Bool) -> [[EaselToolbarControl]] {
        groups.map { $0.filter(supported) }.filter { !$0.isEmpty }
    }
}
