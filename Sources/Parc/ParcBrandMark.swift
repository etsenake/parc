import AppKit

@MainActor
enum ParcBrandMark {
    enum Style: String { case borderless = "Borderless", monochrome = "Monochrome" }

    static func image(_ style: Style, resources: URL? = Bundle.main.resourceURL) -> NSImage? {
        guard let url = resources?.appendingPathComponent("AppIcons/Marks/\(style.rawValue).png"),
              let image = NSImage(contentsOf: url), image.isValid else { return nil }
        image.isTemplate = style == .monochrome
        return image
    }

    static func drawMonochrome(_ image: NSImage, in rect: CGRect, color: NSColor, context: CGContext) {
        guard rect.width > 0, rect.height > 0,
              let mask = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        let scale = min(rect.width / CGFloat(mask.width), rect.height / CGFloat(mask.height))
        let fitted = CGRect(x: rect.midX - CGFloat(mask.width) * scale / 2,
                            y: rect.midY - CGFloat(mask.height) * scale / 2,
                            width: CGFloat(mask.width) * scale, height: CGFloat(mask.height) * scale)
        context.saveGState()
        context.clip(to: fitted, mask: mask)
        context.setFillColor(color.cgColor)
        context.fill(fitted)
        context.restoreGState()
    }
}
