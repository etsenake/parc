import AppKit
import CoreImage
@testable import Parc
import ParcCore

struct SplitMix: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9e3779b97f4a7c15
        var z = state
        z = (z ^ (z >> 30)) &* 0xbf58476d1ce4e5b9
        z = (z ^ (z >> 27)) &* 0x94d049bb133111eb
        return z ^ (z >> 31)
    }
}

@MainActor final class CardShot {
    let state: MembershipCardState
    let view: MembershipCardView
    let surface: CALayer
    let art: CALayer
    let shine: CAGradientLayer
    let field: MembershipCardBlobField
    let capture: CGFloat = 4
    let display: CGFloat = 3.4
    let outSize = CGSize(width: 1200, height: 1800)
    let ci = CIContext(options: [.cacheIntermediates: false])

    static func makeState(seed: UInt64, name: String) -> MembershipCardState {
        var random = SplitMix(state: seed)
        var components = DateComponents(); components.year = 2026; components.month = 11; components.day = 16; components.hour = 12
        let date = Calendar(identifier: .gregorian).date(from: components)!
        return MembershipCardState.make(name: name, date: date, using: &random)
    }

    init(state: MembershipCardState) {
        self.state = state
        view = MembershipCardView(frame: NSRect(origin: .zero, size: MembershipCardArtwork.size))
        view.appearance = NSAppearance(named: .aqua)
        view.display(state, animated: false)
        let root = view.layer!
        let squish = root.sublayers!.first!
        surface = squish.sublayers!.first!
        art = surface.sublayers![0]
        shine = surface.sublayers![1] as! CAGradientLayer
        field = MembershipCardBlobField(state)
        CATransaction.begin(); CATransaction.setDisableActions(true)
        surface.contents = MembershipCardArtwork.render(state, scale: 8, includeArtwork: false)?.cgImage
        surface.shadowOpacity = 0
        CATransaction.commit()
    }

    func setDrift(_ t: Double) {
        let d = field.duration
        let phase = t.truncatingRemainder(dividingBy: 2 * d)
        let linear = phase < d ? phase / d : 2 - phase / d
        let p = CGFloat(cubicBezier(linear, 0.42, 0, 0.58, 1))
        let scale = MembershipCardArtwork.blobTextureScale
        let rotors = art.sublayers!.filter { $0.sublayers?.isEmpty == false }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        for (index, rotor) in rotors.enumerated() where index < field.rest.count {
            let rest = field.rest[index], moved = field.moved[index]
            rotor.setValue(rest.rotation + (moved.rotation - rest.rotation) * p, forKeyPath: "transform.rotation.z")
            guard let image = rotor.sublayers?.first else { continue }
            image.position = CGPoint(x: rest.offset.x + (moved.offset.x - rest.offset.x) * p, y: rest.offset.y + (moved.offset.y - rest.offset.y) * p)
            image.setValue((rest.scale + (moved.scale - rest.scale) * p) / scale, forKeyPath: "transform.scale")
        }
        CATransaction.commit()
    }

    func setShine(_ point: CGPoint?) {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        if let point {
            shine.startPoint = CGPoint(x: point.x / 240, y: point.y / 360)
            shine.endPoint = CGPoint(x: point.x / 240 + 0.8, y: point.y / 360 + 0.8)
        }
        shine.opacity = point == nil ? 0 : 1
        CATransaction.commit()
    }

    func flat() -> CGImage {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(240 * capture), pixelsHigh: Int(360 * capture), bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        rep.size = MembershipCardArtwork.size
        NSAppearance(named: .aqua)!.performAsCurrentDrawingAppearance { view.cacheDisplay(in: view.bounds, to: rep) }
        return rep.cgImage!
    }

    static func transform(hover: CGFloat, point: CGPoint?) -> CATransform3D {
        guard let point, hover > 0 else { return CATransform3DIdentity }
        var target = CATransform3DIdentity
        let x = min(1, max(0, point.x / 240)) * 2 - 1
        let y = min(1, max(0, point.y / 360)) * 2 - 1
        let distance = hypot(x, y)
        target.m34 = -1 / 800
        if distance > 0 { target = CATransform3DRotate(target, distance * 2 * .pi / 180 * hover, y, -x, 0) }
        let s = 1 + 0.05 * hover
        return CATransform3DScale(target, s, s, 1)
    }

    func project(_ m: CATransform3D, _ x: CGFloat, _ y: CGFloat) -> CGPoint {
        let px = x * m.m11 + y * m.m21 + m.m41
        let py = x * m.m12 + y * m.m22 + m.m42
        let pw = x * m.m14 + y * m.m24 + m.m44
        return CGPoint(x: outSize.width / 2 + px / pw * display, y: outSize.height / 2 + py / pw * display)
    }

    func frame(transform m: CATransform3D, shadowOpacity: CGFloat) -> CGImage {
        let card = flat()
        let tl = project(m, -120, -180), tr = project(m, 120, -180), br = project(m, 120, 180), bl = project(m, -120, 180)
        let width = Int(outSize.width), height = Int(outSize.height)
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.clear(CGRect(origin: .zero, size: outSize))
        func flip(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x, y: outSize.height - p.y) }
        let shift: CGFloat = 6000
        let quad = CGMutablePath()
        quad.addLines(between: [tl, tr, br, bl].map { CGPoint(x: flip($0).x + shift, y: flip($0).y) })
        quad.closeSubpath()
        context.saveGState()
        context.setShadow(offset: CGSize(width: -shift, height: -24 * display), blur: 2 * 54 * display,
                          color: NSColor(white: 0.22, alpha: shadowOpacity).cgColor)
        context.addPath(quad); context.setFillColor(NSColor.black.cgColor); context.fillPath()
        context.restoreGState()
        let fade: CGFloat = 140
        let ramp = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                              colors: [CGColor(gray: 0, alpha: 0), CGColor(gray: 0, alpha: 1)] as CFArray, locations: [0, 1])!
        context.saveGState()
        context.setBlendMode(.destinationIn)
        let edges: [(CGRect, CGPoint, CGPoint)] = [
            (CGRect(x: 0, y: 0, width: fade, height: outSize.height), CGPoint(x: 0, y: 0), CGPoint(x: fade, y: 0)),
            (CGRect(x: outSize.width - fade, y: 0, width: fade, height: outSize.height), CGPoint(x: outSize.width, y: 0), CGPoint(x: outSize.width - fade, y: 0)),
            (CGRect(x: 0, y: 0, width: outSize.width, height: fade), CGPoint(x: 0, y: 0), CGPoint(x: 0, y: fade)),
            (CGRect(x: 0, y: outSize.height - fade, width: outSize.width, height: fade), CGPoint(x: 0, y: outSize.height), CGPoint(x: 0, y: outSize.height - fade))]
        for (rect, start, end) in edges {
            context.saveGState(); context.clip(to: rect)
            context.drawLinearGradient(ramp, start: start, end: end, options: [])
            context.restoreGState()
        }
        context.restoreGState()
        let input = CIImage(cgImage: card)
        let warped = input.applyingFilter("CIPerspectiveTransform", parameters: [
            "inputTopLeft": CIVector(cgPoint: flip(tl)), "inputTopRight": CIVector(cgPoint: flip(tr)),
            "inputBottomRight": CIVector(cgPoint: flip(br)), "inputBottomLeft": CIVector(cgPoint: flip(bl))])
        if let image = ci.createCGImage(warped, from: warped.extent) {
            context.interpolationQuality = .high
            context.draw(image, in: warped.extent)
        }
        return context.makeImage()!
    }

    static func sheet(out: String) {
        var frames: [(Double, NSBitmapImageRep)] = []
        for seed in UInt64(1)...UInt64(10) {
            let shot = CardShot(state: makeState(seed: seed, name: "Sam Rivera"))
            shot.setDrift(0)
            let image = shot.frame(transform: CATransform3DIdentity, shadowOpacity: 0.1)
            print("seed", seed, "palette", shot.state.palette, "shape", shot.state.shape, "title", shot.state.title)
            frames.append((Double(seed), NSBitmapImageRep(cgImage: image)))
        }
        Strip.write(frames, thumb: NSSize(width: 240, height: 360), columns: 5, path: out + "/card-seeds.png")
    }

    func run(out: String) {
        let fps = 60.0, duration = 4.0
        let frames = Int(duration * fps)
        let enter = 0.7, exit = 3.25
        func pointer(_ t: Double) -> CGPoint {
            let u = (t - enter) / (exit - enter)
            let angle = Double.pi * (0.28 + 1.15 * u)
            return CGPoint(x: 120 + 78 * cos(angle), y: 180 + 132 * sin(angle))
        }
        var beats: [[String: Any]] = []
        func beat(_ t: Double, _ text: String) {
            beats.append(["t": (t * 1000).rounded() / 1000, "frame": Int((t * 60).rounded()), "beat": text])
        }
        beat(0, "card at rest; blob drift starts from the saved rest arrangement (8-15 s ease-in-out, autoreverse)")
        beat(enter, "virtual pointer enters: shine on and shadow 0.15 instantly, 1.05 scale + tilt on the 0.3/0.95 spring")
        beat(enter + 0.05, "tilt tracks the pointer directly (no spring) while it moves")
        beat(exit, "virtual pointer leaves: shine off and shadow 0.1 instantly, transform springs back to identity")
        let writer = try! VideoWriter(path: out + "/card.mov", width: Int(outSize.width), height: Int(outSize.height), fps: 60, alpha: true,
                                      bitRate: 40_000_000)
        var keyframes: [(Double, NSBitmapImageRep)] = []
        let keyTimes: Set<Int> = [0, 50, 90, 130, 170, 200, 215, 239]
        for index in 0..<frames {
            let t = Double(index) / fps
            setDrift(t)
            var hover: CGFloat = 0
            var point: CGPoint?
            var shadow: CGFloat = 0.1
            if t >= enter && t < exit {
                point = pointer(t)
                hover = CGFloat(springProgress(t - enter, response: 0.3, damping: 0.95))
                shadow = 0.15
                setShine(point)
            } else if t >= exit {
                point = pointer(exit)
                hover = CGFloat(1 - springProgress(t - exit, response: 0.3, damping: 0.95))
                setShine(nil)
            } else {
                setShine(nil)
            }
            let image = frame(transform: Self.transform(hover: hover, point: point), shadowOpacity: shadow)
            writer.append(image, background: NSColor.clear.cgColor)
            if keyTimes.contains(index) {
                let rep = NSBitmapImageRep(cgImage: image)
                keyframes.append((t, rep))
                Render.writePNG(rep, out + String(format: "/card-frame-%03d.png", index))
            }
            Render.requireNoWindows("during card frame \(index)")
        }
        let result = writer.finish()
        print("wrote card.mov", result.frames, "frames status", result.status.rawValue, result.error?.localizedDescription ?? "")
        Strip.write(keyframes, thumb: NSSize(width: 300, height: 450), columns: 8, path: out + "/card-strip.png")
        let info: [String: Any] = ["file": "card.mov", "fps": 60, "frames": frames, "duration": duration, "size": [1200, 1800],
                                   "codec": "hevcWithAlpha", "name": state.name, "title": state.title, "palette": state.palette,
                                   "shape": state.shape, "created": MembershipCardArtwork.date(state), "driftDuration": field.duration, "beats": beats]
        let data = try! JSONSerialization.data(withJSONObject: info, options: [.prettyPrinted, .sortedKeys])
        try! data.write(to: URL(fileURLWithPath: out + "/card-beats.json"))
    }
}
