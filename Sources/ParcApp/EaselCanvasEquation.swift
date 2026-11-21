import AppKit

@MainActor
protocol EaselEquationEditing: AnyObject {
    var textView: NSTextView { get }
    var onChange: ((String) -> Void)? { get set }
    var onCommit: (() -> Void)? { get set }
    var onCancel: (() -> Void)? { get set }
    var onDismiss: (() -> Void)? { get set }
    var onClickAway: (() -> Void)? { get set }
    func present(anchor: NSRect, error: String?, range: NSRange?)
    func reposition(anchor: NSRect)
    func setError(_ text: String?, range: NSRange?)
    func close(animated: Bool)
    func contains(_ view: NSView) -> Bool
}

@MainActor
final class EaselEquationState {
    var session: EaselEquationEditing?
    var editingID: UUID?
    var undoGroup: UUID?
    var fitNatural = EaselEquation.emptySize
    var finishing = false
    var observers: [NSObjectProtocol] = []
}

@MainActor
enum EaselEquationArtwork {
    static var fontSize: CGFloat { CGFloat(EaselEquation.fontSize) }

    static func layout(_ tex: String) -> NoteMathLayoutEntry? {
        guard !EaselEquation.isBlank(tex) else { return nil }
        return NoteMathRenderer.layout(tex, fontSize: fontSize, display: true)
    }

    static func error(of tex: String) -> NoteMathParseError? { layout(tex)?.error }

    static func typesetSize(_ tex: String) -> EaselEquationSize? {
        guard let entry = layout(tex), entry.error == nil, !entry.isEmpty else { return nil }
        return EaselEquationSize(width: Double(entry.frame.width), height: Double(entry.frame.height))
    }

    static func natural(_ tex: String) -> EaselEquationSize {
        EaselEquation.natural(typeset: typesetSize(tex))
    }

    static func rendering(_ tex: String, ink: NSColor) -> NoteMathRendering? {
        guard typesetSize(tex) != nil else { return nil }
        return NoteMathRenderer.render(tex, fontSize: fontSize, color: ink, display: true)
    }

    static func draw(_ item: EaselItem, in rect: NSRect, ink: NSColor, showsPlaceholder: Bool) {
        guard !EaselEquation.isBlank(item.text) else {
            guard showsPlaceholder else { return }
            NoteEquationArtwork.drawPlaceholder(in: rect, font: NoteTheme.bodyFont(.standard, small: true), fill: NoteTheme.mediaPlaceholderFill)
            return
        }
        guard let rendering = rendering(item.text, ink: ink), let context = NSGraphicsContext.current?.cgContext else {
            drawFailure(item, in: rect)
            return
        }
        let natural = natural(item.text)
        let factor = CGFloat(EaselEquation.scale(of: item.frame, natural: natural))
        let width = rendering.size.width * factor, height = rendering.size.height * factor
        let origin = CGPoint(x: rect.midX - width / 2, y: rect.midY - height / 2)
        context.saveGState()
        context.translateBy(x: origin.x, y: origin.y)
        context.scaleBy(x: factor, y: factor)
        rendering.drawFlipped(in: context, at: .zero)
        context.restoreGState()
    }

    private static func drawFailure(_ item: EaselItem, in rect: NSRect) {
        let radius = NoteTheme.blockRadius
        NoteTheme.mediaPlaceholderFill.setFill()
        NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
        NoteEquationArtwork.drawError(source: item.text, in: rect)
    }

    static func vector(_ tex: String) -> EaselVectorEquation? {
        guard !EaselEquation.isBlank(tex) else { return nil }
        if let failure = error(of: tex) {
            return EaselVectorEquation(width: 0, height: 0, parts: [], error: failure.message)
        }
        guard let rendering = rendering(tex, ink: .black) else { return nil }
        var flip = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: rendering.size.height)
        let parts = rendering.outlines().compactMap { outline -> EaselVectorEquationPart? in
            guard let flipped = outline.path.copy(using: &flip) else { return nil }
            let data = EaselDocumentExport.svgPath(flipped)
            guard !data.isEmpty else { return nil }
            switch outline.color {
            case .inherited: return EaselVectorEquationPart(path: data)
            case .link: return EaselVectorEquationPart(path: data, opacity: 0.42)
            case .muted:
                let muted = NSColor(cgColor: NoteMathRendering.mutedInk(for: .black))
                return EaselVectorEquationPart(path: data, color: muted.flatMap(EaselDocumentExport.hex), opacity: 0.85)
            case .custom(let color):
                return EaselVectorEquationPart(path: data, color: NSColor(cgColor: color).flatMap(EaselDocumentExport.hex))
            }
        }
        return EaselVectorEquation(width: Double(rendering.size.width), height: Double(rendering.size.height), parts: parts)
    }

    static func plainText(_ item: EaselItem) -> String? {
        let text = item.text.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }
}
