import AppKit

struct ExtensionPopupSource {
    let identifier: String
    weak var control: NSView?
    private weak var popup: AnyObject?
    private(set) var claimed = false

    init(identifier: String, control: NSView) {
        self.identifier = identifier
        self.control = control
    }

    mutating func control(for identifier: String, popup: AnyObject) -> NSView? {
        guard identifier == self.identifier else { return nil }
        if claimed { return self.popup === popup ? control : nil }
        claimed = true
        self.popup = popup
        return control
    }
}

struct ExtensionPopupArea {
    let owner: NSView
    let bar: NSView
    let controls: [NSView?]
}

enum ExtensionPopupPlacement {
    static let gap: CGFloat = 6
    static let margin: CGFloat = 8
    static let pageInset: CGFloat = 40

    static func origin(size: CGSize, control: CGRect, bar: CGRect, window: CGRect, screen: CGRect?) -> CGPoint {
        let anchor = control.union(bar)
        let areas = regions(window: window, screen: screen)
        let fitting = areas.filter { size.width <= $0.width && size.height <= $0.height }
        let x = { (region: CGRect) in horizontal(control.maxX - size.width, size.width, in: region) }
        let below = { (region: CGRect) in min(anchor.minY - gap, region.maxY) - size.height }
        let clear = { (region: CGRect) -> CGPoint? in
            if below(region) >= region.minY { return CGPoint(x: x(region), y: below(region)) }
            let above = max(anchor.maxY + gap, region.minY)
            if above + size.height <= region.maxY { return CGPoint(x: x(region), y: above) }
            return beside(anchor, size, in: region)
        }
        for place in [clear, { beside(control, size, in: $0) }] {
            for region in fitting { if let spot = place(region) { return spot } }
        }
        let region = fitting.first ?? areas[areas.count - 1]
        return CGPoint(x: x(region), y: vertical(below(region), size.height, in: region))
    }

    @MainActor static func anchor(clicked: NSView?, owners: [ExtensionPopupArea], defaults: [ExtensionPopupArea],
                                  shows: (NSView) -> Bool) -> (control: NSView, bar: NSView)? {
        if let clicked, shows(clicked),
           let area = owners.first(where: { clicked.isDescendant(of: $0.owner) && shows($0.bar) }) {
            return (clicked, area.bar)
        }
        guard let area = defaults.first(where: { shows($0.bar) }) else { return nil }
        return (area.controls.compactMap { $0 }.first(where: shows) ?? area.bar, area.bar)
    }

    static func pageAnchor(_ page: CGRect) -> CGRect {
        CGRect(x: page.maxX - pageInset, y: page.maxY, width: 0, height: 0)
    }

    static func regions(window: CGRect, screen: CGRect?) -> [CGRect] {
        let inset = { (rect: CGRect) -> CGRect in
            let inner = rect.insetBy(dx: margin, dy: margin)
            return inner.isNull ? rect : inner
        }
        guard let screen else { return [inset(window)] }
        let visible = window.intersection(screen)
        return visible.isNull || visible.isEmpty ? [inset(screen)] : [inset(visible), inset(screen)]
    }

    private static func beside(_ rect: CGRect, _ size: CGSize, in region: CGRect) -> CGPoint? {
        let y = vertical(rect.maxY - size.height, size.height, in: region)
        let leading = rect.minX - gap - size.width
        if leading >= region.minX { return CGPoint(x: leading, y: y) }
        let trailing = rect.maxX + gap
        return trailing + size.width <= region.maxX ? CGPoint(x: trailing, y: y) : nil
    }

    private static func horizontal(_ value: CGFloat, _ length: CGFloat, in region: CGRect) -> CGFloat {
        max(region.minX, min(value, region.maxX - length))
    }

    private static func vertical(_ value: CGFloat, _ length: CGFloat, in region: CGRect) -> CGFloat {
        min(region.maxY - length, max(value, region.minY))
    }
}
