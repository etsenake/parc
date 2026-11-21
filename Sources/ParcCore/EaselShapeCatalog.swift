import Foundation

package struct EaselShapeFamily: Equatable {
    package let title: String
    package let shapes: [EaselShape]
}

package enum EaselShapeCatalog {
    package struct Slot: Equatable {
        package var family: Int
        package var index: Int

        package init(family: Int, index: Int) {
            self.family = family
            self.index = index
        }
    }

    package static let columns = 6

    package static let families = [
        EaselShapeFamily(title: "Basic", shapes: [.rectangle, .roundedRectangle, .ellipse, .diamond, .triangle, .triangleDown,
                                                  .pentagon, .hexagon, .octagon, .star, .plus, .speechBubble,
                                                  .arrowLeft, .arrowRight, .arrowUp, .arrowDown, .chevron]),
        EaselShapeFamily(title: "Flowchart", shapes: [.parallelogram, .parallelogramLeft, .trapezoid, .manualInput, .cylinder,
                                                      .cylinderHorizontal, .file, .folder, .document, .documents,
                                                      .predefinedProcess, .internalStorage, .shield, .or, .summingJunction])
    ]

    package static func shape(at slot: Slot) -> EaselShape? {
        guard families.indices.contains(slot.family), families[slot.family].shapes.indices.contains(slot.index) else { return nil }
        return families[slot.family].shapes[slot.index]
    }

    package static func slot(of shape: EaselShape) -> Slot? {
        for (family, value) in families.enumerated() {
            if let index = value.shapes.firstIndex(of: shape) { return Slot(family: family, index: index) }
        }
        return nil
    }

    package static func move(from slot: Slot?, dx: Int, dy: Int) -> Slot {
        guard let slot, shape(at: slot) != nil else { return Slot(family: 0, index: 0) }
        if dx != 0 {
            let flat = families.prefix(slot.family).reduce(0) { $0 + $1.shapes.count } + slot.index
            let total = families.reduce(0) { $0 + $1.shapes.count }
            var target = ((flat + dx) % total + total) % total
            for (family, value) in families.enumerated() {
                if target < value.shapes.count { return Slot(family: family, index: target) }
                target -= value.shapes.count
            }
            return slot
        }
        guard dy != 0 else { return slot }
        let column = slot.index % columns, row = slot.index / columns
        let rows = (families[slot.family].shapes.count + columns - 1) / columns
        let nextRow = row + dy
        if nextRow >= 0 && nextRow < rows {
            return Slot(family: slot.family, index: min(nextRow * columns + column, families[slot.family].shapes.count - 1))
        }
        let family = ((slot.family + (dy > 0 ? 1 : -1)) % families.count + families.count) % families.count
        let count = families[family].shapes.count
        let targetRow = dy > 0 ? 0 : (count - 1) / columns
        return Slot(family: family, index: min(targetRow * columns + column, count - 1))
    }
}
