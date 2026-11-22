import AppKit
import ParcCore
import QuartzCore
import CoreImage

@MainActor
package enum MembershipCardArtwork {
    package static let size = NSSize(width: 240, height: 360)
    static func image(_ name: String, resources: Bundle = .main) -> NSImage? {
        guard let url = resources.url(forResource: name, withExtension: "png", subdirectory: "MembershipCard") else { return nil }
        return NSImage(contentsOf: url)
    }
    static func color(_ hex: String) -> NSColor {
        let value = UInt32(hex, radix: 16) ?? 0
        return NSColor(srgbRed: Double((value >> 16) & 255) / 255,
                       green: Double((value >> 8) & 255) / 255,
                       blue: Double(value & 255) / 255, alpha: 1)
    }
    static func date(_ state: MembershipCardState) -> String {
        let formatter = DateFormatter(); formatter.dateStyle = .medium; formatter.timeStyle = .none
        return formatter.string(from: state.createdAt)
    }
    static func render(_ state: MembershipCardState, scale: CGFloat = 3, includeArtwork: Bool = true,
                       resources: Bundle = .main) -> NSBitmapImageRep? {
        let picture = NSImage(size: size, flipped: true) { rect in
            let ink = color(MembershipCardState.palettes[state.palette][0])
            NSColor(srgbRed: 1, green: 0.99, blue: 0.92, alpha: 1).setFill()
            NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6).fill()
            let artwork = NSRect(x: 16, y: 16, width: 208, height: 192)
            if includeArtwork, let art = staticArtwork(state, resources: resources) { art.draw(in: artwork) }
            let paragraph = NSMutableParagraphStyle(); paragraph.lineBreakMode = .byTruncatingTail
            (state.name as NSString).draw(in: NSRect(x: 16, y: 224, width: 208, height: 32), withAttributes: [
                .font: NSFont.systemFont(ofSize: 23, weight: .bold), .foregroundColor: ink, .paragraphStyle: paragraph])
            let titleParagraph = NSMutableParagraphStyle(); titleParagraph.lineBreakMode = .byWordWrapping
            (state.title as NSString).draw(in: NSRect(x: 16, y: 253, width: 208, height: 32), withAttributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .medium), .foregroundColor: ink, .paragraphStyle: titleParagraph])
            ("CARD CREATED" as NSString).draw(at: NSPoint(x: 16, y: 314), withAttributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 7, weight: .medium), .foregroundColor: ink])
            let ticket = NSRect(x: 16, y: 328, width: 145, height: 16)
            ink.setStroke(); let outline = NSBezierPath(roundedRect: ticket, xRadius: 2, yRadius: 2); outline.lineWidth = 1; outline.stroke()
            ("PARC" as NSString).draw(at: NSPoint(x: 21, y: 331), withAttributes: [.font: NSFont.systemFont(ofSize: 8, weight: .bold), .foregroundColor: ink])
            let lines = NSRect(x: 48, y: 329, width: 14, height: 14)
            if let image = image("Lines", resources: resources) {
                let tinted = image.copy() as! NSImage
                tinted.lockFocus(); ink.setFill(); NSRect(origin: .zero, size: tinted.size).fill(using: .sourceAtop); tinted.unlockFocus()
                tinted.draw(in: lines)
            }
            (date(state) as NSString).draw(in: NSRect(x: 66, y: 331, width: 91, height: 12), withAttributes: [
                .font: NSFont.systemFont(ofSize: 8, weight: .semibold), .foregroundColor: ink, .paragraphStyle: paragraph])
            ("PARC" as NSString).draw(in: NSRect(x: 181, y: 329, width: 45, height: 17), withAttributes: [
                .font: NSFont.systemFont(ofSize: 13, weight: .heavy), .foregroundColor: ink])
            return true
        }
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale),
            pixelsHigh: Int(size.height * scale), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
            isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return nil }
        bitmap.size = size
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = context
        context.cgContext.scaleBy(x: scale, y: scale)
        picture.draw(in: NSRect(origin: .zero, size: size))
        NSGraphicsContext.restoreGraphicsState()
        return bitmap
    }
    package static func sharingBitmap(_ state: MembershipCardState) -> NSBitmapImageRep? {
        guard let card = render(state) else { return nil }
        let matteSize = NSSize(width: 412, height: 531)
        let image = NSImage(size: matteSize, flipped: true) { rect in
            let ink = color(MembershipCardState.palettes[state.palette][0])
            ink.blended(withFraction: 0.4, of: .white)?.setFill(); rect.fill()
            let shadow = NSShadow(); shadow.shadowColor = ink.withAlphaComponent(0.8)
            shadow.shadowBlurRadius = 80; shadow.shadowOffset = NSSize(width: 0, height: -16)
            NSGraphicsContext.saveGraphicsState(); shadow.set()
            let picture = NSImage(size: size); picture.addRepresentation(card)
            picture.draw(in: NSRect(x: 86, y: 85.5, width: 240, height: 360))
            NSGraphicsContext.restoreGraphicsState()
            return true
        }
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1236, pixelsHigh: 1593,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return nil }
        bitmap.size = matteSize
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = context
        context.cgContext.scaleBy(x: 3, y: 3); image.draw(in: NSRect(origin: .zero, size: matteSize))
        NSGraphicsContext.restoreGraphicsState()
        return bitmap
    }
    static func staticArtwork(_ state: MembershipCardState, resources: Bundle = .main) -> NSImage? {
        guard let mask = image("Shape\(state.shape)", resources: resources) else { return nil }
        let field = MembershipCardBlobField(state)
        let textures = field.colors.map { blobTexture($0, resources: resources) }
        let result = NSImage(size: artworkSize, flipped: true) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            field.background.setFill(); rect.fill()
            for blob in field.rest {
                guard let texture = textures[blob.color] else { continue }
                context.saveGState()
                context.translateBy(x: artworkSize.width / 2, y: artworkSize.height / 2)
                context.rotate(by: blob.rotation)
                context.translateBy(x: blob.offset.x, y: blob.offset.y)
                context.scaleBy(x: blob.scale / blobTextureScale, y: -blob.scale / blobTextureScale)
                let size = texture.size
                context.draw(texture.image, in: CGRect(x: -size.width / 2, y: -size.height / 2, width: size.width, height: size.height))
                context.restoreGState()
            }
            mask.draw(in: rect, from: .zero, operation: .destinationIn, fraction: 1, respectFlipped: true, hints: nil)
            return true
        }
        return result
    }
    static let artworkSize = NSSize(width: 208, height: 192)
    static let blobSize = NSSize(width: 634, height: 669)
    static let blobBlur: CGFloat = 50
    static let blobTextureScale: CGFloat = 0.275
    private static var textureCache: [String: (image: CGImage, size: CGSize)] = [:]
    private static let blurContext = CIContext(options: [.cacheIntermediates: false])
    static func blobTexture(_ color: NSColor, resources: Bundle = .main) -> (image: CGImage, size: CGSize)? {
        let key = color.usingColorSpace(.sRGB).map { "\($0.redComponent),\($0.greenComponent),\($0.blueComponent)" } ?? color.description
        if resources == .main, let cached = textureCache[key] { return cached }
        guard let original = image("AnimatingCardBlob", resources: resources) else { return nil }
        let pixelsPerPoint: CGFloat = 0.5
        let blob = CGSize(width: blobSize.width * blobTextureScale, height: blobSize.height * blobTextureScale)
        let pad = blobBlur * 3
        let size = CGSize(width: blob.width + pad * 2, height: blob.height + pad * 2)
        let width = Int((size.width * pixelsPerPoint).rounded()), height = Int((size.height * pixelsPerPoint).rounded())
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                                            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let drawing = NSGraphicsContext(bitmapImageRep: bitmap) else { return nil }
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = drawing
        let inner = NSRect(x: 0, y: 0, width: width, height: height).insetBy(dx: pad * pixelsPerPoint, dy: pad * pixelsPerPoint)
        original.draw(in: inner)
        color.setFill(); inner.fill(using: .sourceAtop)
        NSGraphicsContext.restoreGraphicsState()
        guard let cg = bitmap.cgImage else { return nil }
        let input = CIImage(cgImage: cg)
        let blurred = input.clampedToExtent()
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: blobBlur * pixelsPerPoint])
            .cropped(to: input.extent)
        guard let output = blurContext.createCGImage(blurred, from: input.extent) else { return nil }
        let result = (image: output, size: size)
        if resources == .main { textureCache[key] = result }
        return result
    }
}

@MainActor
struct MembershipCardBlobField {
    struct Blob { var color: Int; var scale: CGFloat; var offset: CGPoint; var rotation: CGFloat }
    let colors: [NSColor]
    let background: NSColor
    let rest: [Blob]
    let moved: [Blob]
    let duration: CFTimeInterval
    init(_ state: MembershipCardState) {
        colors = MembershipCardState.palettes[state.palette].map(MembershipCardArtwork.color)
        background = colors[state.backgroundBlobInfo.reduce(0, +) % colors.count]
        var random = Seeded(state)
        func roll(_ value: Int) -> Blob {
            Blob(color: value % 3,
                 scale: 0.2 + CGFloat(random.unit()) * 0.15,
                 offset: CGPoint(x: CGFloat(random.next() % 301), y: CGFloat(random.next() % 301)),
                 rotation: (CGFloat(random.unit()) * 720 - 360) * .pi / 180)
        }
        rest = state.backgroundBlobInfo.map(roll)
        moved = state.backgroundBlobInfo.map(roll)
        duration = 8 + random.unit() * 7
    }
    private struct Seeded {
        var value: UInt64
        init(_ state: MembershipCardState) {
            var hash: UInt64 = 0xcbf29ce484222325
            for byte in Array("\(state.palette)|\(state.shape)|\(state.title)|\(state.backgroundBlobInfo)".utf8) {
                hash = (hash ^ UInt64(byte)) &* 0x100000001b3
            }
            value = hash
        }
        mutating func next() -> UInt64 {
            value &+= 0x9e3779b97f4a7c15
            var z = value
            z = (z ^ (z >> 30)) &* 0xbf58476d1ce4e5b9
            z = (z ^ (z >> 27)) &* 0x94d049bb133111eb
            return z ^ (z >> 31)
        }
        mutating func unit() -> Double { Double(next() >> 11) / Double(1 << 53) }
    }
}

@MainActor
package final class MembershipCardView: NSView {
    private let squishLayer = CALayer()
    private let surface = CALayer()
    private let art = CALayer()
    private let shine = CAGradientLayer()
    private let grain = CALayer()
    private var blobs: [CALayer] = []
    private var field: MembershipCardBlobField?
    private var tracking: NSTrackingArea?
    package private(set) var state: MembershipCardState?
    private var hovering = false
    private var live = false
    package override var isFlipped: Bool { true }
    package override var isHidden: Bool { didSet { updateActivity() } }

    package override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        surface.bounds = NSRect(origin: .zero, size: MembershipCardArtwork.size)
        surface.position = NSPoint(x: 120, y: 180)
        surface.shadowColor = NSColor(white: 0.22, alpha: 1).cgColor
        surface.shadowOpacity = 0.1; surface.shadowRadius = 54
        surface.shadowOffset = NSSize(width: 0, height: 24)
        surface.shadowPath = CGPath(roundedRect: surface.bounds, cornerWidth: 6, cornerHeight: 6, transform: nil)
        squishLayer.frame = NSRect(origin: .zero, size: MembershipCardArtwork.size)
        squishLayer.addSublayer(surface)
        layer?.addSublayer(squishLayer)
        art.frame = NSRect(x: 16, y: 16, width: 208, height: 192)
        art.masksToBounds = true; surface.addSublayer(art)
        grain.frame = art.bounds; grain.opacity = 0.12
        if let url = Bundle.main.url(forResource: "grain-1", withExtension: "png", subdirectory: "Onboarding") {
            grain.contents = NSImage(contentsOf: url)?.cgImage(forProposedRect: nil, context: nil, hints: nil)
        }
        shine.frame = surface.bounds; shine.cornerRadius = 6
        shine.type = .radial; shine.colors = [NSColor.white.withAlphaComponent(0.34).cgColor, NSColor.white.withAlphaComponent(0).cgColor]
        shine.startPoint = CGPoint(x: 0.5, y: 0.5); shine.endPoint = CGPoint(x: 1.3, y: 1.3)
        shine.opacity = 0; surface.addSublayer(shine)
        setAccessibilityElement(true); setAccessibilityRole(.image)
        let center = NotificationCenter.default
        for name in [NSApplication.didResignActiveNotification, NSApplication.didBecomeActiveNotification,
                     NSWindow.didResignKeyNotification, NSWindow.didBecomeKeyNotification,
                     NSWindow.didMiniaturizeNotification, NSWindow.didDeminiaturizeNotification,
                     NSWindow.didEndSheetNotification] {
            center.addObserver(self, selector: #selector(activityChanged), name: name, object: nil)
        }
        for name in [NSWindow.willBeginSheetNotification, NSWindow.willCloseNotification] {
            center.addObserver(self, selector: #selector(ownerInterrupted), name: name, object: nil)
        }
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(activityChanged),
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
    }
    package required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    deinit {
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }
    package override func viewWillMove(toWindow newWindow: NSWindow?) {
        stopMotion(); super.viewWillMove(toWindow: newWindow)
    }
    package override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); updateActivity() }
    package override func viewDidHide() { super.viewDidHide(); stopMotion() }
    package override func viewDidUnhide() { super.viewDidUnhide(); updateActivity() }
    package override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds, options: [.activeInKeyWindow, .inVisibleRect, .mouseEnteredAndExited, .mouseMoved], owner: self)
        addTrackingArea(area); tracking = area
    }
    package func display(_ state: MembershipCardState?, animated: Bool) {
        guard self.state != state else { return }
        self.state = state; stopMotion()
        CATransaction.begin(); CATransaction.setDisableActions(true)
        surface.contents = state.flatMap { MembershipCardArtwork.render($0, scale: 2, includeArtwork: false)?.cgImage }
        blobs.forEach { $0.removeFromSuperlayer() }; blobs = []
        if let state {
            setAccessibilityLabel("\(state.name), \(state.title). Local Parc card created \(MembershipCardArtwork.date(state)).")
            let mask = CALayer(); mask.frame = art.bounds
            mask.contents = MembershipCardArtwork.image("Shape\(state.shape)")?.cgImage(forProposedRect: nil, context: nil, hints: nil)
            art.mask = mask
            let field = MembershipCardBlobField(state)
            self.field = field
            art.contents = nil
            art.backgroundColor = field.background.cgColor
            let textures = field.colors.map { MembershipCardArtwork.blobTexture($0) }
            let center = CGPoint(x: art.bounds.midX, y: art.bounds.midY)
            for blob in field.rest {
                let rotor = CALayer()
                rotor.bounds = .zero; rotor.position = center
                rotor.setValue(blob.rotation, forKeyPath: "transform.rotation.z")
                let image = CALayer()
                if let texture = textures[blob.color] {
                    image.bounds = CGRect(origin: .zero, size: texture.size)
                    image.contents = texture.image
                }
                image.position = blob.offset
                image.setValue(blob.scale / MembershipCardArtwork.blobTextureScale, forKeyPath: "transform.scale")
                rotor.addSublayer(image)
                art.addSublayer(rotor); blobs.append(rotor)
            }
            art.addSublayer(grain)
            art.isHidden = false
        } else {
            setAccessibilityLabel("Local Parc card unavailable")
            field = nil
            art.isHidden = true
        }
        CATransaction.commit()
        if animated && canAnimate {
            let chrome = CATransition(); chrome.type = .fade; chrome.duration = 0.4
            surface.add(chrome, forKey: "design")
            let artwork = CATransition(); artwork.type = .fade; artwork.duration = 0.4
            art.add(artwork, forKey: "design")
        }
        updateActivity()
        NSAccessibility.post(element: self, notification: .valueChanged)
    }
    package func squish() {
        guard canAnimate, squishLayer.animation(forKey: "squish") == nil else { return }
        let step = 1.0 / 120
        let squish = CAKeyframeAnimation(keyPath: "transform.scale")
        let values = Self.squishCurve(step: step)
        squish.values = values
        squish.duration = step * Double(values.count - 1)
        squish.calculationMode = .linear
        squishLayer.add(squish, forKey: "squish")
    }

    static func squishCurve(step: Double) -> [Double] {
        let omega = 2 * Double.pi / 0.4
        let stiffness = omega * omega, damping = 2 * 0.8 * omega
        var value = 1.0, velocity = 0.0, time = 0.0
        var samples = [value]
        while time < 1.5 {
            let target = time < 0.05 ? 0.93 : 1
            let substeps = 8, h = step / Double(substeps)
            for _ in 0..<substeps {
                velocity += (stiffness * (target - value) - damping * velocity) * h
                value += velocity * h
            }
            time += step
            samples.append(value)
            if time > 0.05, abs(value - 1) < 0.0005, abs(velocity) < 0.01 { break }
        }
        samples[samples.count - 1] = 1
        return samples
    }

    private var canAnimate: Bool {
        guard let window else { return false }
        return state != nil && window.isVisible && window.isKeyWindow && !window.isMiniaturized &&
            window.attachedSheet == nil && NSApp.isActive && !isHiddenOrHasHiddenAncestor &&
            !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }
    @objc private func activityChanged(_ note: Notification) { updateActivity() }
    @objc private func ownerInterrupted(_ note: Notification) {
        if let affected = note.object as? NSWindow, affected === window { stopMotion() }
    }
    private func updateActivity() {
        guard canAnimate else { stopMotion(); return }
        guard !live else { return }; live = true
        art.isHidden = false
        guard let field else { return }
        for (index, rotor) in blobs.enumerated() {
            guard let image = rotor.sublayers?.first else { continue }
            let rest = field.rest[index], moved = field.moved[index]
            let scale = MembershipCardArtwork.blobTextureScale
            let tracks: [(CALayer, String, Any, Any)] = [
                (rotor, "transform.rotation.z", rest.rotation, moved.rotation),
                (image, "position", NSValue(point: rest.offset), NSValue(point: moved.offset)),
                (image, "transform.scale", rest.scale / scale, moved.scale / scale)]
            for (layer, key, from, to) in tracks {
                let drift = CABasicAnimation(keyPath: key)
                drift.fromValue = from; drift.toValue = to
                drift.duration = field.duration; drift.autoreverses = true; drift.repeatCount = .infinity
                drift.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                layer.add(drift, forKey: "drift")
            }
        }
    }
    func stopMotion() {
        live = false; hovering = false
        CATransaction.begin(); CATransaction.setDisableActions(true)
        surface.removeAllAnimations(); surface.transform = CATransform3DIdentity; surface.shadowOpacity = 0.1
        shine.removeAllAnimations(); shine.opacity = 0
        for rotor in blobs {
            rotor.removeAllAnimations(); rotor.sublayers?.forEach { $0.removeAllAnimations() }
        }
        art.isHidden = state == nil
        CATransaction.commit()
    }
    package override func mouseEntered(with event: NSEvent) { movePointer(event) }
    package override func mouseMoved(with event: NSEvent) { movePointer(event) }
    package override func mouseExited(with event: NSEvent) { setPointer(nil) }
    private func movePointer(_ event: NSEvent) {
        guard event.windowNumber == window?.windowNumber, canAnimate else { stopMotion(); return }
        let point = convert(event.locationInWindow, from: nil)
        setPointer(bounds.contains(point) && visibleRect.contains(point) ? point : nil)
    }
    private func setPointer(_ point: NSPoint?) {
        let previous = surface.presentation()?.transform ?? surface.transform
        let entered = point != nil && !hovering
        hovering = point != nil
        var target = CATransform3DIdentity
        if let point {
            let x = min(1, max(0, point.x / 240)) * 2 - 1
            let y = min(1, max(0, point.y / 360)) * 2 - 1
            let distance = hypot(x, y)
            target.m34 = -1 / 800
            if distance > 0 { target = CATransform3DRotate(target, distance * 2 * .pi / 180, y, -x, 0) }
            target = CATransform3DScale(target, 1.05, 1.05, 1)
            shine.startPoint = CGPoint(x: point.x / 240, y: point.y / 360)
            shine.endPoint = CGPoint(x: point.x / 240 + 0.8, y: point.y / 360 + 0.8)
        }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        surface.transform = target; surface.shadowOpacity = point == nil ? 0.1 : 0.15; shine.opacity = point == nil ? 0 : 1
        CATransaction.commit()
        if canAnimate && (entered || point == nil) {
            let spring = CASpringAnimation(keyPath: "transform")
            let frequency = 2 * Double.pi / 0.3
            spring.mass = 1; spring.stiffness = frequency * frequency; spring.damping = 2 * 0.95 * frequency
            spring.fromValue = NSValue(caTransform3D: previous); spring.toValue = NSValue(caTransform3D: target)
            spring.duration = spring.settlingDuration
            surface.add(spring, forKey: "hover")
        }
    }
}
