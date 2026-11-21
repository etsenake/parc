import AppKit

extension EaselCanvasView {
    func shapeMenuRows(_ context: EaselMenuContext) -> [EaselMenuRow] {
        guard context.target != .canvas, !context.items.isEmpty,
              context.items.allSatisfy({ $0.resolvedShape != nil }), context.items.contains(where: { !$0.isLocked }) else { return [] }
        let current = Set(context.items.compactMap(\.resolvedShape))
        let choices = EaselShape.allCases.map { shape in
            EaselMenuRow(id: "shape-" + shape.rawValue, title: EaselShapeGeometry.displayName(shape),
                         isChecked: current == [shape]) { [weak self] in
                _ = self?.changeSelectedShapes(to: shape)
            }
        }
        return [EaselMenuRow(id: "shape", title: "Shape", symbol: "square.on.circle", children: choices)]
    }
}
