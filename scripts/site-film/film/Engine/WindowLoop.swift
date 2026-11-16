import Foundation
import CoreGraphics
import CoreImage

public struct WindowGeometry {
    public var canvas = CGSize(width: 1440, height: 900)
    public var window = CGRect(x: 80, y: 18, width: 1280, height: 840)
    public var scale = 2.0
    public var cornerRadius = 16.0
    public init() {}

    var canvasPx: CGSize { CGSize(width: canvas.width * scale, height: canvas.height * scale) }

    func ciRect(windowPoints r: CGRect) -> CGRect {
        let x = (window.minX + r.minX) * scale
        let yTop = (window.minY + r.minY) * scale
        let h = r.height * scale
        return CGRect(x: x, y: canvasPx.height - yTop - h, width: r.width * scale, height: h)
    }
}

public enum LoopSource {
    case video(VideoSource)
    case still(CIImage)
    case provider((Double) -> CIImage)

    func image(at t: Double) -> CIImage {
        switch self {
        case let .video(v): return v.image(at: t)
        case let .still(i): return i
        case let .provider(p): return p(t)
        }
    }

    var duration: Double? {
        if case let .video(v) = self { return v.duration }
        return nil
    }
}

public struct LoopSpec {
    public var name: String
    public var source: LoopSource
    public var crop = CGRect(x: 0, y: 0, width: 1280, height: 840)
    public var width = 1600
    public var bitrate = 6_000_000
    public var start = 0.0
    public var end = 10.0
    public var crossfade = 0.0
    public var fps = 60
    public var repeatFirstFrame = false
    public init(name: String, source: LoopSource) { self.name = name; self.source = source }

    public var height: Int {
        let h = Double(width) * Double(crop.height) / Double(crop.width)
        return Int((h / 2).rounded()) * 2
    }
}

public struct LoopReport {
    public var frames: Int
    public var size: (Int, Int)
    public var seam: Double
    public var typicalStep: Double
    public var maxStep: Double
    public var seconds: Double
}

public final class WindowLoop {
    public let geometry: WindowGeometry
    let context: CIContext
    let mask: CIImage
    let windowRect: CGRect

    public init(geometry: WindowGeometry = WindowGeometry(), context: CIContext) {
        self.geometry = geometry
        self.context = context
        windowRect = geometry.ciRect(windowPoints: CGRect(origin: .zero, size: geometry.window.size))
        let w = Int(windowRect.width), h = Int(windowRect.height)
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
        ctx.setFillColor(gray: 0, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        let r = geometry.cornerRadius * geometry.scale
        ctx.addPath(CGPath(roundedRect: CGRect(x: 0, y: 0, width: w, height: h).insetBy(dx: 1, dy: 1), cornerWidth: r, cornerHeight: r, transform: nil))
        ctx.setFillColor(gray: 1, alpha: 1)
        ctx.fillPath()
        mask = CIImage(cgImage: ctx.makeImage()!).transformed(by: CGAffineTransform(translationX: windowRect.minX, y: windowRect.minY))
    }

    public func opaqueWindow(_ canvas: CIImage) -> CIImage {
        let r = geometry.cornerRadius * geometry.scale + 2
        let fill = canvas.cropped(to: windowRect.insetBy(dx: r, dy: r)).clampedToExtent().cropped(to: windowRect)
        let body = canvas.cropped(to: windowRect).settingAlphaOne(in: windowRect)
        return body.applyingFilter("CIBlendWithMask", parameters: ["inputBackgroundImage": fill, "inputMaskImage": mask])
            .cropped(to: windowRect).settingAlphaOne(in: windowRect)
    }

    public func plate(_ canvas: CIImage) -> CIImage {
        opaqueWindow(canvas).transformed(by: CGAffineTransform(translationX: -windowRect.minX, y: -windowRect.minY))
    }

    public func cleanWindow(_ canvas: CIImage) -> CIImage {
        canvas.cropped(to: windowRect).settingAlphaOne(in: windowRect)
            .applyingFilter("CIBlendWithMask", parameters: ["inputBackgroundImage": CIImage.empty(), "inputMaskImage": mask])
            .cropped(to: windowRect)
            .transformed(by: CGAffineTransform(translationX: -windowRect.minX, y: -windowRect.minY))
    }

    public func frame(_ spec: LoopSpec, index i: Int, count n: Int) -> CIImage {
        let step = 1.0 / Double(spec.fps)
        let t = spec.start + Double(i) * step
        var img = spec.source.image(at: t)
        let k = Int((spec.crossfade * Double(spec.fps)).rounded())
        if k > 0 && i >= n - k {
            let w = Double(i - (n - k) + 1) / Double(k + 1)
            let pre = max(spec.start - Double(n - i) * step, 0)
            let other = spec.source.image(at: spec.start - Double(n - i) * step >= 0 ? pre : spec.start)
            img = other.applyingFilter("CIDissolveTransition", parameters: ["inputTargetImage": img, "inputTime": 1 - w])
        }
        let crop = geometry.ciRect(windowPoints: spec.crop)
        let s = Double(spec.width) / Double(crop.width)
        var out = opaqueWindow(img).cropped(to: crop)
        out = out.transformed(by: CGAffineTransform(translationX: -crop.minX, y: -crop.minY))
        out = out.applyingFilter("CILanczosScaleTransform", parameters: ["inputScale": s, "inputAspectRatio": (Double(spec.height) / Double(crop.height)) / s])
        return out.cropped(to: CGRect(x: 0, y: 0, width: spec.width, height: spec.height)).settingAlphaOne(in: CGRect(x: 0, y: 0, width: spec.width, height: spec.height))
    }

    func thumb(_ img: CIImage, _ w: Int, _ h: Int) -> [Float] {
        let small = img.applyingFilter("CILanczosScaleTransform", parameters: ["inputScale": Double(w) / Double(img.extent.width), "inputAspectRatio": 1.0])
        var buf = [Float](repeating: 0, count: w * h * 4)
        context.render(small, toBitmap: &buf, rowBytes: w * 16, bounds: CGRect(x: 0, y: 0, width: w, height: h), format: .RGBAf, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)
        return buf
    }

    func diff(_ a: [Float], _ b: [Float]) -> Double {
        var s = 0.0
        for i in stride(from: 0, to: a.count, by: 4) {
            s += Double(abs(a[i] - b[i]) + abs(a[i + 1] - b[i + 1]) + abs(a[i + 2] - b[i + 2])) / 3
        }
        return s / Double(a.count / 4) * 255
    }

    @discardableResult
    public func render(_ spec: LoopSpec, to url: URL, strip: URL? = nil, log: (String) -> Void = { print($0) }) throws -> LoopReport {
        let n = Int(((spec.end - spec.start) * Double(spec.fps)).rounded())
        let total = n + (spec.repeatFirstFrame ? 1 : 0)
        let writer = try VideoWriter(url: url, width: spec.width, height: spec.height, fps: spec.fps, bitrate: spec.bitrate, network: true)
        let t0 = Date()
        let tw = 96, th = Int((96.0 * Double(spec.height) / Double(spec.width)).rounded())
        var first: [Float] = [], prev: [Float] = []
        var steps: [Double] = []
        var stripFrames: [CGImage] = []
        let stripIdx = Set((0..<8).map { $0 * n / 8 })
        for i in 0..<total {
            autoreleasepool {
                let img = frame(spec, index: i % n, count: n)
                writer.append(img, frame: i, context: context)
                let tb = thumb(img, tw, th)
                if i == 0 { first = tb } else if i < n { steps.append(diff(prev, tb)) }
                prev = tb
                if strip != nil && stripIdx.contains(i) {
                    stripFrames.append(context.createCGImage(img, from: img.extent, format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)!)
                }
            }
        }
        writer.finish()
        let seam = diff(prev, first)
        let sorted = steps.sorted()
        let report = LoopReport(frames: total, size: (spec.width, spec.height), seam: seam, typicalStep: sorted.isEmpty ? 0 : sorted[sorted.count / 2], maxStep: sorted.last ?? 0, seconds: Date().timeIntervalSince(t0))
        if let strip {
            FilmOutput.writeStrip(stripFrames, times: (0..<8).map { spec.start + Double($0 * n / 8) / Double(spec.fps) }, to: strip)
        }
        log(String(format: "%@: %d frames %dx%d in %.1fs; seam step %.2f vs median step %.2f, max step %.2f (0-255 mean abs)", spec.name, report.frames, spec.width, spec.height, report.seconds, report.seam, report.typicalStep, report.maxStep))
        return report
    }
}
