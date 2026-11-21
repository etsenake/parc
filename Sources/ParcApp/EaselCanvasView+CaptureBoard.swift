import AppKit
import ParcCore

extension EaselCanvasView {
    var isCaptureBoard: Bool { fixedCanvasSize != nil }

    func captureBoardAllows(_ control: EaselToolbarControl) -> Bool {
        guard isCaptureBoard else { return true }
        switch control {
        case .createSection, .sectionTitle, .link, .connectorLabel, .altText, .codeLanguage, .mergeCells, .cellFill: return false
        default: return true
        }
    }

    func captureBoardPasteable(_ items: [EaselItem]) -> [EaselItem] {
        guard isCaptureBoard else { return items }
        return items.filter { Self.captureBoardAccepts($0.kind) }
    }

    static func captureBoardAccepts(_ kind: EaselItemKind) -> Bool {
        switch kind {
        case .text, .image, .rectangle, .circle, .arrow, .freehand, .sticky, .stamp: return true
        case .webCard, .browser, .link, .section, .table, .code, .video: return false
        }
    }
}
