import AppKit
import QuartzCore

///
///
/// ConfettiConfig defaults were not recovered from its metadata accessor.
final class OnboardingConfettiView: NSView {
    private let emitter = CAEmitterLayer()
    private var burstGeneration = 0
    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = true
        emitter.emitterShape = .line
        emitter.birthRate = 0
        layer?.addSublayer(emitter)
        setAccessibilityElement(false)
        setAccessibilityHidden(true)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        emitter.frame = bounds
        emitter.emitterPosition = CGPoint(x: bounds.midX, y: 8)
        emitter.emitterSize = CGSize(width: max(1, bounds.width * 0.55), height: 1)
    }

    func burst(using colors: [NSColor]) {
        stop()
        guard !bounds.isEmpty else { return }
        burstGeneration += 1
        let token = burstGeneration
        layout()
        let cells = (colors.isEmpty ? [OnboardingSetupPalette.action] : colors).prefix(6).map { color -> CAEmitterCell in
            let cell = CAEmitterCell()
            cell.contents = Self.particle(color)
            cell.birthRate = 28
            cell.lifetime = 1.6
            cell.velocity = 280
            cell.velocityRange = 90
            cell.emissionLongitude = .pi
            cell.emissionRange = .pi / 3
            cell.spin = 4
            cell.spinRange = 6
            cell.scale = 0.55
            cell.scaleRange = 0.25
            cell.alphaSpeed = -0.6
            cell.yAcceleration = 420
            return cell
        }
        emitter.emitterCells = Array(cells)
        emitter.beginTime = CACurrentMediaTime()
        emitter.birthRate = 1
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self, self.burstGeneration == token else { return }
            self.emitter.birthRate = 0
        }
    }

    var emitterBirthRate: Float { emitter.birthRate }

    func stop() {
        burstGeneration += 1
        emitter.birthRate = 0
        emitter.emitterCells = nil
    }

    private static func particle(_ color: NSColor) -> CGImage? {
        let size = NSSize(width: 10, height: 6)
        let image = NSImage(size: size, flipped: true) { rect in
            (color.usingColorSpace(.sRGB) ?? color).setFill()
            NSBezierPath(roundedRect: rect, xRadius: 1.5, yRadius: 1.5).fill()
            return true
        }
        return image.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }
}
