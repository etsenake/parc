import Foundation
import Testing
@testable import ParcCore

enum EaselMermaidTestsSupport {
    static func diagram(_ text: String) throws -> EaselMermaidDiagram {
        switch EaselMermaid.parse(text) {
        case .success(let value): return value
        case .failure(let refusal): throw NoteTestFailure("Expected a diagram but got \(refusal.message) for:\n\(text)")
        }
    }

    static func refusal(_ text: String) -> EaselMermaidRefusal? {
        if case .failure(let value) = EaselMermaid.parse(text) { return value }
        return nil
    }

    static func edge(_ value: EaselMermaidDiagram, _ from: String, _ to: String) -> EaselMermaidEdge? {
        value.edges.first { $0.from == from && $0.to == to }
    }

    static func frames(_ text: String) throws -> (EaselMermaidDiagram, EaselMermaidLayout) {
        let value = try diagram(text)
        var sizes: [String: EaselMermaidSize] = [:]
        for node in value.nodes { sizes[node.id] = EaselMermaid.frameSize(node.shape, text: EaselMermaid.estimate(node.label, maximumWidth: 220)) }
        return (value, EaselMermaidLayoutEngine.layout(value, nodeSizes: sizes, labelSizes: [:]))
    }

    static func center(_ rect: EaselRect?) -> EaselPoint {
        guard let rect else { return EaselPoint(x: .nan, y: .nan) }
        return EaselPoint(x: rect.x + rect.width / 2, y: rect.y + rect.height / 2)
    }

    static func overlaps(_ a: EaselRect, _ b: EaselRect, margin: Double = 0) -> Bool {
        a.x < b.x + b.width + margin && b.x < a.x + a.width + margin && a.y < b.y + b.height + margin && b.y < a.y + a.height + margin
    }
}
