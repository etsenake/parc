import Foundation

enum EaselShapeStyle {
    static let defaultHue = NoteColor.blue

    static func newItem(_ shape: EaselShape, frame: EaselRect, ink: String, zIndex: Int) -> EaselItem {
        let stroke: String, fill: String?
        switch EaselPalette.color(for: ink, role: .ink) {
        case .note(let note)?:
            stroke = EaselPalette.hex(.note(note), role: .ink) ?? ink
            fill = EaselPalette.hex(.note(note), role: .fill)
        case .automatic?:
            stroke = EaselPalette.hex(.note(defaultHue), role: .ink) ?? ink
            fill = EaselPalette.hex(.note(defaultHue), role: .fill)
        default:
            stroke = ink
            fill = EaselPalette.hex(.neutral, role: .fill)
        }
        var item = EaselItem(kind: shape == .ellipse ? .circle : .rectangle, frame: frame, zIndex: zIndex, color: stroke)
        if shape != .ellipse { item.shape = shape }
        item.fill = fill
        item.fillOpacity = 1
        item.strokeWidth = EaselPaintRules.shapeWidth
        return item
    }
}
