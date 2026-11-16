import Foundation
import CoreGraphics
import CoreImage
import Metal

struct Projected {
    var corners: [CGPoint]
    var depths: [Double]
    var centerDepth: Double
}

public final class FilmRenderer {
    public let film: Film
    public let context: CIContext
    let W: Double, H: Double, ss: Double
    let frameRect: CGRect
    let noise: CIImage

    public init(film: Film) {
        self.film = film
        let device = MTLCreateSystemDefaultDevice()!
        context = CIContext(mtlDevice: device, options: [
            .workingFormat: CIFormat.RGBAh,
            .workingColorSpace: CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!,
            .cacheIntermediates: false,
            .name: "film"
        ])
        W = Double(film.settings.width)
        H = Double(film.settings.height)
        ss = Double(film.settings.supersample)
        frameRect = CGRect(x: 0, y: 0, width: W * ss, height: H * ss)
        noise = CIFilter(name: "CIRandomGenerator")!.outputImage!
    }

    func rotate(_ p: Vec3, _ r: Vec3) -> Vec3 {
        let (rx, ry, rz) = (r.x * .pi / 180, r.y * .pi / 180, r.z * .pi / 180)
        var x = p.x * cos(rz) - p.y * sin(rz)
        var y = p.x * sin(rz) + p.y * cos(rz)
        var z = p.z
        let y2 = y * cos(rx) + z * sin(rx)
        let z2 = -y * sin(rx) + z * cos(rx)
        y = y2; z = z2
        let x3 = x * cos(ry) - z * sin(ry)
        let z3 = x * sin(ry) + z * cos(ry)
        x = x3; z = z3
        return Vec3(x, y, z)
    }

    func inverseRotate(_ p: Vec3, _ r: Vec3) -> Vec3 {
        let (rx, ry, rz) = (-r.x * .pi / 180, -r.y * .pi / 180, -r.z * .pi / 180)
        var x = p.x * cos(ry) - p.z * sin(ry)
        var z = p.x * sin(ry) + p.z * cos(ry)
        var y = p.y
        let y2 = y * cos(rx) + z * sin(rx)
        let z2 = -y * sin(rx) + z * cos(rx)
        y = y2; z = z2
        let x3 = x * cos(rz) - y * sin(rz)
        let y3 = x * sin(rz) + y * cos(rz)
        x = x3; y = y3
        return Vec3(x, y, z)
    }

    func project(_ layer: Layer, _ t: Double, _ cam: Camera, pad: CGSize = .zero) -> Projected? {
        let s = layer.scale.value(at: t)
        let pos = layer.position.value(at: t)
        let rot = layer.rotation.value(at: t)
        let w = (Double(layer.size.width) + Double(pad.width) * 2) * s
        let h = (Double(layer.size.height) + Double(pad.height) * 2) * s
        let ax = Double(layer.anchor.x), ay = Double(layer.anchor.y)
        let local: [(Double, Double)] = [(0, 0), (1, 0), (1, 1), (0, 1)]
        let F = cam.focalLength.value(at: t)
        let cp = cam.eyePosition(at: t)
        let cr = cam.rotation.value(at: t)
        let eye = Vec3(cp.x, cp.y, cp.z - F)
        var corners: [CGPoint] = []
        var depths: [Double] = []
        let padU = Double(pad.width) * s, padV = Double(pad.height) * s
        let ox = ax * Double(layer.size.width) * s + padU
        let oy = ay * Double(layer.size.height) * s + padV
        for (u, v) in local {
            let lp = Vec3(u * w - ox, v * h - oy, 0)
            let wp = rotate(lp, rot) + pos
            let q = inverseRotate(wp - eye, cr)
            if q.z < 10 { return nil }
            corners.append(CGPoint(x: W / 2 + F * q.x / q.z, y: H / 2 + F * q.y / q.z))
            depths.append(q.z)
        }
        let qc = inverseRotate(pos - eye, cr)
        return Projected(corners: corners, depths: depths, centerDepth: qc.z)
    }

    func ci(_ p: CGPoint) -> CIVector { CIVector(x: p.x * ss, y: (H - p.y) * ss) }

    func coc(_ depth: Double, _ cam: Camera, _ t: Double) -> Double {
        let F = cam.focalLength.value(at: t)
        let cp = cam.eyePosition(at: t)
        let focusDist = cam.focus.value(at: t) - cp.z + F
        let a = cam.aperture.value(at: t)
        return a * abs(1 - focusDist / depth)
    }

    func signedCoc(_ depth: Double, _ cam: Camera, _ t: Double) -> Double {
        let F = cam.focalLength.value(at: t)
        let cp = cam.eyePosition(at: t)
        let focusDist = cam.focus.value(at: t) - cp.z + F
        return cam.aperture.value(at: t) * (1 - focusDist / depth)
    }

    func withAlpha(_ img: CIImage, _ a: Double) -> CIImage {
        if a >= 0.999 { return img }
        return img.applyingFilter("CIColorMatrix", parameters: ["inputAVector": CIVector(x: 0, y: 0, z: 0, w: a)])
    }

    func silhouette(_ img: CIImage, _ a: Double) -> CIImage {
        img.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: a)
        ])
    }

    func gaussian(_ img: CIImage, _ r: Double, clampTo: CGRect? = nil) -> CIImage {
        if r < 0.3 { return img }
        if let rect = clampTo {
            return img.clampedToExtent().applyingGaussianBlur(sigma: r).cropped(to: rect)
        }
        return img.applyingGaussianBlur(sigma: r).cropped(to: img.extent.insetBy(dx: -r * 3, dy: -r * 3))
    }

    func padded(_ img: CIImage, _ p: Double) -> CIImage {
        let e = img.extent
        let clear = CIImage(color: .clear).cropped(to: e.insetBy(dx: -p, dy: -p))
        return img.composited(over: clear).transformed(by: CGAffineTransform(translationX: -e.minX + p, y: -e.minY + p))
    }

    func renderWorldLayer(_ layer: Layer, _ t: Double, _ cam: Camera, into base: CIImage) -> CIImage {
        let opacity = layer.opacity.value(at: t)
        if opacity <= 0.001 { return base }
        var src = layer.content(t)
        if layer.edgeClamp && cam.rotation.value(at: t).isZero && layer.rotation.value(at: t).isZero {
            return renderPlate(layer, src, t, cam, opacity, into: base)
        }
        let srcW = Double(src.extent.width)
        let texPerWorld = srcW / Double(layer.size.width)
        let padPx = 3.0
        src = padded(src, padPx)
        let padWorld = CGSize(width: padPx / texPerWorld, height: padPx / texPerWorld)
        guard let pr = project(layer, t, cam, pad: padWorld) else { return base }
        let c = pr.corners
        let projW = max(hypot(c[1].x - c[0].x, c[1].y - c[0].y), hypot(c[2].x - c[3].x, c[2].y - c[3].y)) * ss
        let ratio = projW / Double(src.extent.width)
        if ratio < 0.55 {
            let f = max(ratio * 1.6, 0.02)
            src = src.applyingFilter("CILanczosScaleTransform", parameters: ["inputScale": f, "inputAspectRatio": 1.0])
            src = src.transformed(by: CGAffineTransform(translationX: -src.extent.minX, y: -src.extent.minY))
        }
        let ev = layer.exposure.value(at: t)
        if abs(ev) > 0.001 {
            src = src.applyingFilter("CIExposureAdjust", parameters: ["inputEV": ev])
        }
        var img = src.applyingFilter("CIPerspectiveTransform", parameters: [
            "inputTopLeft": ci(c[0]), "inputTopRight": ci(c[1]),
            "inputBottomRight": ci(c[2]), "inputBottomLeft": ci(c[3])
        ])
        let bounds = img.extent.intersection(frameRect.insetBy(dx: -400 * ss, dy: -400 * ss))
        if bounds.isNull || bounds.isEmpty { return base }
        img = img.cropped(to: bounds)
        let manual = layer.blur.value(at: t)
        var out = base
        if let sh = layer.shadow {
            let el = layer.elevation.value(at: t)
            let k = projW / 1000
            let key = silhouette(img, sh.opacity * opacity)
                .applyingGaussianBlur(sigma: sh.radius * el * k)
                .transformed(by: CGAffineTransform(translationX: 0, y: -sh.offset * el * k))
                .cropped(to: frameRect)
            let contact = silhouette(img, sh.contactOpacity * opacity)
                .applyingGaussianBlur(sigma: sh.contactRadius * max(el, 0.3) * k)
                .transformed(by: CGAffineTransform(translationX: 0, y: -sh.contactOffset * el * k))
                .cropped(to: frameRect)
            out = key.composited(over: out)
            out = contact.composited(over: out)
        }
        if layer.depthOfField && film.settings.supersample > 0 {
            let s = pr.depths.map { signedCoc($0, cam, t) }
            let mags = s.map { abs($0) }
            let maxC = (mags.max() ?? 0) + manual
            let minC = (mags.min() ?? 0) + manual
            if maxC - minC < 0.6 {
                img = gaussian(img, (maxC + minC) / 2 * ss)
            } else {
                let iNear = s.indices.min { pr.depths[$0] < pr.depths[$1] }!
                let iFar = s.indices.max { pr.depths[$0] < pr.depths[$1] }!
                let p0 = ci(c[iNear]), p1 = ci(c[iFar])
                let s0 = s[iNear], s1 = s[iFar]
                let mx = maxC
                func grad(_ a: CIVector, _ b: CIVector, _ va: Double, _ vb: Double) -> CIImage {
                    let ga = (va + manual) / mx, gb = (vb + manual) / mx
                    return CIFilter(name: "CISmoothLinearGradient", parameters: [
                        "inputPoint0": a, "inputPoint1": b,
                        "inputColor0": CIColor(red: ga, green: ga, blue: ga),
                        "inputColor1": CIColor(red: gb, green: gb, blue: gb)
                    ])!.outputImage!
                }
                var mask: CIImage
                if s0 * s1 >= 0 {
                    mask = grad(p0, p1, abs(s0), abs(s1))
                } else {
                    let tz = s0 / (s0 - s1)
                    let pz = CIVector(x: p0.x + (p1.x - p0.x) * tz, y: p0.y + (p1.y - p0.y) * tz)
                    let a = grad(p0, pz, abs(s0), 0)
                    let b = grad(pz, p1, 0, abs(s1))
                    mask = a.applyingFilter("CIMaximumCompositing", parameters: ["inputBackgroundImage": b])
                }
                mask = mask.cropped(to: img.extent.insetBy(dx: -mx * ss * 3, dy: -mx * ss * 3))
                let r = mx * ss
                img = img.applyingFilter("CIMaskedVariableBlur", parameters: ["inputMask": mask, "inputRadius": r])
                    .cropped(to: img.extent.insetBy(dx: -r * 3, dy: -r * 3))
            }
        } else if manual > 0.3 {
            img = gaussian(img, manual * ss)
        }
        img = withAlpha(img, opacity)
        return img.composited(over: out)
    }

    func renderPlate(_ layer: Layer, _ input: CIImage, _ t: Double, _ cam: Camera, _ opacity: Double, into base: CIImage) -> CIImage {
        guard let pr = project(layer, t, cam) else { return base }
        let c = pr.corners
        let rect = CGRect(x: c[0].x * ss, y: (H - c[2].y) * ss, width: (c[1].x - c[0].x) * ss, height: (c[2].y - c[0].y) * ss)
        let e = input.extent
        let sx = rect.width / e.width, sy = rect.height / e.height
        var img = input.transformed(by: CGAffineTransform(translationX: -e.minX, y: -e.minY))
            .clampedToExtent().cropped(to: CGRect(x: -16, y: -16, width: e.width + 32, height: e.height + 32))
        img = img.applyingFilter("CILanczosScaleTransform", parameters: ["inputScale": sy, "inputAspectRatio": sx / sy])
        img = img.transformed(by: CGAffineTransform(translationX: rect.minX, y: rect.minY))
        img = img.cropped(to: rect.intersection(frameRect))
        let ev = layer.exposure.value(at: t)
        if abs(ev) > 0.001 { img = img.applyingFilter("CIExposureAdjust", parameters: ["inputEV": ev]) }
        let r = layer.blur.value(at: t)
        if r > 0.3 { img = gaussian(img, r * ss, clampTo: rect.intersection(frameRect)) }
        return withAlpha(img, opacity).composited(over: base)
    }

    func renderScreenLayer(_ layer: Layer, _ t: Double, _ cam: Camera, into base: CIImage) -> CIImage {
        let opacity = layer.opacity.value(at: t)
        if opacity <= 0.001 { return base }
        var src = layer.content(t)
        let s = layer.scale.value(at: t)
        let pos = layer.position.value(at: t)
        let rz = layer.rotation.value(at: t).z * .pi / 180
        let sx = Double(layer.size.width) * s * ss / Double(src.extent.width)
        let sy = Double(layer.size.height) * s * ss / Double(src.extent.height)
        src = src.transformed(by: CGAffineTransform(translationX: -src.extent.minX - src.extent.width * layer.anchor.x, y: -src.extent.minY - src.extent.height * (1 - layer.anchor.y)))
        let cx = (layer.space == .background ? W / 2 + pos.x : pos.x) * ss
        let cy = (H - (layer.space == .background ? H / 2 + pos.y : pos.y)) * ss
        var tf = CGAffineTransform(scaleX: sx, y: sy)
        tf = tf.concatenating(CGAffineTransform(rotationAngle: -rz))
        tf = tf.concatenating(CGAffineTransform(translationX: cx, y: cy))
        var img = src.transformed(by: tf, highQualityDownsample: true)
        let ev = layer.exposure.value(at: t)
        if abs(ev) > 0.001 {
            img = img.applyingFilter("CIExposureAdjust", parameters: ["inputEV": ev])
        }
        var r = layer.blur.value(at: t)
        if layer.space == .background && layer.depthOfField {
            let F = cam.focalLength.value(at: t)
            let d = layer.backgroundDepth - cam.eyePosition(at: t).z + F
            r += coc(d, cam, t)
        }
        if layer.space == .background {
            img = gaussian(img, r * ss, clampTo: frameRect)
        } else {
            img = gaussian(img, r * ss)
        }
        img = withAlpha(img, opacity)
        return img.composited(over: base)
    }

    public func shotImage(_ shot: Shot, at time: Double) -> CIImage {
        let t = time - shot.start
        let cam = shot.camera
        var img = CIImage(color: shot.backdrop).cropped(to: frameRect)
        for l in shot.layers where l.space == .background {
            img = renderScreenLayer(l, t, cam, into: img)
        }
        let world = shot.layers.enumerated().filter { $0.element.space == .world }
        let sorted = world.map { (idx, l) -> (Int, Layer, Double) in
            let d = project(l, t, cam)?.centerDepth ?? -1
            return (idx, l, d)
        }.sorted { a, b in
            if abs(a.2 - b.2) > 0.5 { return a.2 > b.2 }
            return a.0 < b.0
        }
        for (_, l, _) in sorted {
            img = renderWorldLayer(l, t, cam, into: img)
        }
        for l in shot.layers where l.space == .overlay {
            img = renderScreenLayer(l, t, cam, into: img)
        }
        let ev = shot.exposure.value(at: t)
        if abs(ev) > 0.001 {
            img = img.applyingFilter("CIExposureAdjust", parameters: ["inputEV": ev])
        }
        return img.cropped(to: frameRect)
    }

    func floodMask(_ origin: CGPoint, _ radius: Double, _ feather: Double) -> CIImage {
        let c = ci(origin)
        let r1 = max(radius * ss, 0.01)
        let r0 = max(r1 - feather * ss, 0)
        return CIFilter(name: "CIRadialGradient", parameters: [
            "inputCenter": c, "inputRadius0": r0, "inputRadius1": r1,
            "inputColor0": CIColor(red: 1, green: 1, blue: 1, alpha: 1),
            "inputColor1": CIColor(red: 0, green: 0, blue: 0, alpha: 0)
        ])!.outputImage!.cropped(to: frameRect)
    }

    public func composite(at t: Double) -> CIImage {
        let shots = film.shots
        guard let i = shots.lastIndex(where: { $0.start <= t + 1e-9 }) else {
            return CIImage(color: .black).cropped(to: frameRect)
        }
        let cur = shots[i]
        let tr = cur.transitionIn
        let d = tr.duration
        if i == 0 || d <= 0 || t >= cur.start + d {
            return shotImage(cur, at: t)
        }
        let prev = shots[i - 1]
        let p = (t - cur.start) / d
        switch tr {
        case .cut:
            return shotImage(cur, at: t)
        case .dissolve:
            let e = Ease.inOut.progress(elapsed: p, duration: 1)
            let a = shotImage(prev, at: t)
            let b = shotImage(cur, at: t)
            return b.applyingFilter("CIDissolveTransition", parameters: ["inputTargetImage": a, "inputTime": 1 - e])
        case let .flood(color, _, origin):
            let far = [CGPoint(x: 0, y: 0), CGPoint(x: W, y: 0), CGPoint(x: 0, y: H), CGPoint(x: W, y: H)]
                .map { hypot($0.x - origin.x, $0.y - origin.y) }.max()!
            let feather = 220.0
            let fill = CIImage(color: color).cropped(to: frameRect)
            if p < 0.5 {
                let e = Ease.bezier(0.55, 0.0, 0.75, 0.6).progress(elapsed: p * 2, duration: 1)
                let a = shotImage(prev, at: t)
                let m = floodMask(origin, e * (far + feather), feather)
                return fill.applyingFilter("CIBlendWithMask", parameters: ["inputBackgroundImage": a, "inputMaskImage": m])
            } else {
                let e = Ease.out.progress(elapsed: (p - 0.5) * 2, duration: 1)
                let b = shotImage(cur, at: t)
                let m = floodMask(origin, e * (far + feather), feather)
                return b.applyingFilter("CIBlendWithMask", parameters: ["inputBackgroundImage": fill, "inputMaskImage": m])
            }
        }
    }

    func motionAmount(at t: Double, half: Double) -> Double {
        var m = 0.0
        for shot in film.shots where t >= shot.start - 0.05 && t <= shot.end + 0.05 {
            let lt = t - shot.start
            for l in shot.layers {
                switch l.space {
                case .world:
                    guard let a = project(l, lt - half, shot.camera), let b = project(l, lt + half, shot.camera) else { continue }
                    for k in 0..<4 { m = max(m, hypot(a.corners[k].x - b.corners[k].x, a.corners[k].y - b.corners[k].y)) }
                case .overlay, .background:
                    let a = l.position.value(at: lt - half), b = l.position.value(at: lt + half)
                    let sa = l.scale.value(at: lt - half), sb = l.scale.value(at: lt + half)
                    m = max(m, hypot(a.x - b.x, a.y - b.y) + abs(sa - sb) * Double(max(l.size.width, l.size.height)) / 2)
                }
            }
        }
        return m
    }

    public private(set) var lastSampleCount = 1

    public func frame(_ index: Int) -> CIImage {
        let fps = Double(film.settings.fps)
        let t = Double(index) / fps
        let shutter = film.settings.shutter / fps
        var n = 1
        if film.settings.motionBlur {
            let m = motionAmount(at: t, half: shutter / 2)
            n = m < film.settings.motionMinimum ? 1 : Int(min(Double(film.settings.maxMotionSamples), max(1, ceil(m / film.settings.motionThreshold))))
        }
        lastSampleCount = n
        var img: CIImage
        if n == 1 {
            img = composite(at: t)
        } else {
            let w = 1.0 / Double(n)
            var acc: CIImage?
            for k in 0..<n {
                let ts = t + shutter * ((Double(k) + 0.5) / Double(n) - 0.5)
                let s = withAlpha(composite(at: ts), w)
                acc = acc.map { s.applyingFilter("CIAdditionCompositing", parameters: ["inputBackgroundImage": $0]) } ?? s
            }
            img = acc!.cropped(to: frameRect)
        }
        img = finish(img, index: index)
        return img
    }

    func finish(_ input: CIImage, index: Int) -> CIImage {
        var img = input
        let st = film.settings
        if st.vignette > 0.001 {
            let c = CIVector(x: frameRect.midX, y: frameRect.midY)
            let r0 = frameRect.height * 0.55, r1 = frameRect.width * 0.72
            let mask = CIFilter(name: "CIRadialGradient", parameters: [
                "inputCenter": c, "inputRadius0": r0, "inputRadius1": r1,
                "inputColor0": CIColor(red: 1, green: 1, blue: 1),
                "inputColor1": CIColor(red: 1 - st.vignette, green: 1 - st.vignette, blue: 1 - st.vignette)
            ])!.outputImage!.cropped(to: frameRect)
            img = img.applyingFilter("CIMultiplyCompositing", parameters: ["inputBackgroundImage": mask])
        }
        let target = CGRect(x: 0, y: 0, width: W, height: H)
        if st.supersample > 1 {
            img = img.transformed(by: CGAffineTransform(scaleX: 1 / ss, y: 1 / ss), highQualityDownsample: true).cropped(to: target)
        }
        if st.grain > 0.0001 {
            var rng = SplitMix(seed: UInt64(index) &* 2654435761 &+ 17)
            let ox = Double(rng.next() % 4096), oy = Double(rng.next() % 4096)
            let a = st.grain
            let g = noise.transformed(by: CGAffineTransform(translationX: -ox, y: -oy))
                .cropped(to: target).settingAlphaOne(in: target)
                .applyingFilter("CIColorMatrix", parameters: [
                    "inputRVector": CIVector(x: a, y: 0, z: 0, w: 0),
                    "inputGVector": CIVector(x: a, y: 0, z: 0, w: 0),
                    "inputBVector": CIVector(x: a, y: 0, z: 0, w: 0),
                    "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                    "inputBiasVector": CIVector(x: 1 - a / 2, y: 1 - a / 2, z: 1 - a / 2, w: 1)
                ]).cropped(to: target)
            img = g.applyingFilter("CIMultiplyCompositing", parameters: ["inputBackgroundImage": img])
        }
        return img.cropped(to: target)
    }
}

struct SplitMix {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

extension Vec3 {
    var isZero: Bool { abs(x) < 1e-9 && abs(y) < 1e-9 && abs(z) < 1e-9 }
}
