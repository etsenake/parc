import AppKit
import QuartzCore
import ParcSidebar

enum OnboardingThemeEditorLayout {
    static let editorSize = NSSize(width: 356, height: 508)
    static let scale: CGFloat = 0.83
    static let cornerRadius: CGFloat = 16
    static let shadowOpacity: Float = 0.25
    static let shadowRadius: CGFloat = 30
    static let shadowOffsetY: CGFloat = 7
    static let appearDuration: TimeInterval = 0.1
    static let spaceNameHeight: CGFloat = 36
    static let emptyStateText = "Click to pick a color"
    static let colorPadSize: CGFloat = 340
    static let wrapMaterial = NSVisualEffectView.Material.popover
    static let wrapMaterialState = NSVisualEffectView.State.followsWindowActiveState
    static let wrapBlendingMode = NSVisualEffectView.BlendingMode.withinWindow
    static let wrapMaterialEmphasized = false
    static var visualSize: NSSize {
        NSSize(width: editorSize.width * scale, height: editorSize.height * scale)
    }

    static func frame(in bounds: NSRect) -> NSRect {
        NSRect(x: (bounds.width - visualSize.width) / 2,
               y: (bounds.height - visualSize.height) / 2,
               width: visualSize.width, height: visualSize.height)
    }

    static func shouldAnimateAppearance(alreadyVisible: Bool) -> Bool { !alreadyVisible }
}

final class OnboardingSpaceNameField: NSView, NSTextFieldDelegate {
    let field = NSTextField()
    var themeTextColor: NSColor? { didSet { updateColors() } }
    override var isFlipped: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.cornerCurve = .continuous
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 17, weight: .medium)
        field.alignment = .left
        field.placeholderString = "Space name"
        field.setAccessibilityLabel("Space name")
        addSubview(field)
        updateColors()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func layout() {
        super.layout()
        field.frame = bounds.insetBy(dx: 10, dy: 6)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColors()
    }

    func updateColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(dark ? 0.12 : 0.08).cgColor
            let ink = themeTextColor ?? OnboardingSetupPalette.title
            field.textColor = ink
            if themeTextColor != nil {
                field.placeholderAttributedString = NSAttributedString(string: "Space name", attributes: [
                    .foregroundColor: ink.withAlphaComponent(0.65), .font: field.font!
                ])
            } else {
                field.placeholderAttributedString = nil
                field.placeholderString = "Space name"
            }
        }
    }
}

final class OnboardingThemeEditorPopoverBackground: NSView {
    let translucency = NSVisualEffectView()
    override var isFlipped: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.cornerRadius = OnboardingThemeEditorLayout.cornerRadius
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        translucency.material = OnboardingThemeEditorLayout.wrapMaterial
        translucency.state = OnboardingThemeEditorLayout.wrapMaterialState
        translucency.blendingMode = OnboardingThemeEditorLayout.wrapBlendingMode
        translucency.isEmphasized = OnboardingThemeEditorLayout.wrapMaterialEmphasized
        translucency.wantsLayer = true
        translucency.layer?.cornerRadius = OnboardingThemeEditorLayout.cornerRadius
        translucency.layer?.cornerCurve = .continuous
        translucency.layer?.masksToBounds = true
        translucency.setAccessibilityElement(false)
        addSubview(translucency)
        applyClearShadow()
        setAccessibilityElement(false)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func layout() {
        super.layout()
        translucency.frame = bounds
    }

    func applyClearShadow() {
        layer?.shadowColor = NSColor.clear.cgColor
        layer?.shadowOpacity = 0
        layer?.shadowRadius = 0
        layer?.shadowOffset = .zero
        layer?.shadowPath = nil
    }
}

final class OnboardingThemeEditorHitRegion: NSView {
    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }

    override init(frame: NSRect) {
        super.init(frame: frame)
        setAccessibilityElement(false)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func mouseDown(with _: NSEvent) {
    }
}

private final class OnboardingThemeEditorComposition: NSView {
    override var isFlipped: Bool { true }
}

final class OnboardingThemeEditorChrome: NSView {
    let editor: SpaceThemeEditorView
    let popoverBackground = OnboardingThemeEditorPopoverBackground(frame: .zero)
    let hitRegion = OnboardingThemeEditorHitRegion(frame: .zero)
    let composition: NSView = OnboardingThemeEditorComposition(frame: .zero)
    override var isFlipped: Bool { true }

    init(editor: SpaceThemeEditorView) {
        self.editor = editor
        super.init(frame: NSRect(origin: .zero, size: OnboardingThemeEditorLayout.editorSize))
        wantsLayer = true
        composition.wantsLayer = true
        applyParentShadow()
        composition.setAccessibilityElement(false)
        editor.presentation = .setup
        popoverBackground.applyClearShadow()
        addSubview(hitRegion)
        addSubview(composition)
        composition.addSubview(popoverBackground)
        popoverBackground.addSubview(editor)
        setAccessibilityElement(false)
        updateShadowPath()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func layout() {
        super.layout()
        hitRegion.frame = bounds
        let editorBounds = NSRect(origin: .zero, size: OnboardingThemeEditorLayout.editorSize)
        popoverBackground.frame = editorBounds
        editor.frame = editorBounds
        applyParentShadow()
    }

    func applyFrame(in bounds: NSRect) {
        frame = bounds
        hitRegion.frame = self.bounds
        composition.frame = OnboardingThemeEditorLayout.frame(in: self.bounds)
        composition.setBoundsSize(OnboardingThemeEditorLayout.editorSize)
        let editorBounds = NSRect(origin: .zero, size: OnboardingThemeEditorLayout.editorSize)
        popoverBackground.frame = editorBounds
        popoverBackground.applyClearShadow()
        editor.frame = editorBounds
        applyParentShadow()
        needsLayout = true
    }

    private func applyParentShadow() {
        composition.layer?.cornerRadius = OnboardingThemeEditorLayout.cornerRadius
        composition.layer?.cornerCurve = .continuous
        composition.layer?.masksToBounds = false
        composition.layer?.shadowColor = NSColor.black.cgColor
        composition.layer?.shadowOpacity = OnboardingThemeEditorLayout.shadowOpacity
        composition.layer?.shadowRadius = OnboardingThemeEditorLayout.shadowRadius
        composition.layer?.shadowOffset = CGSize(width: 0, height: OnboardingThemeEditorLayout.shadowOffsetY)
        updateShadowPath()
    }

    private func updateShadowPath() {
        let radius = OnboardingThemeEditorLayout.cornerRadius
        let rect = CGRect(origin: .zero, size: OnboardingThemeEditorLayout.editorSize)
        composition.layer?.shadowPath = CGPath(
            roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
    }

    func prepareAppearance(reduceMotion: Bool, in bounds: NSRect? = nil) {
        if let bounds { applyFrame(in: bounds) }
        composition.layer?.removeAnimation(forKey: "opacity")
        composition.alphaValue = reduceMotion ? 1 : 0
    }

    func playAppearance(reduceMotion: Bool, in bounds: NSRect? = nil) {
        if let bounds { applyFrame(in: bounds) }
        if reduceMotion {
            composition.alphaValue = 1
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = OnboardingThemeEditorLayout.appearDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            composition.animator().alphaValue = 1
        }
    }
}
