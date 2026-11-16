import Foundation
import CoreGraphics
import CoreImage
import CoreText
import AVFoundation

public struct OutputPlan {
    public var master: URL
    public var web: URL?
    public var poster: (Double, URL)?
    public var strip: ([Double], URL)?
    public var stills: [(Double, URL)] = []
    public var masterBitrate = 22_000_000
    public var webBitrate = 6_000_000
    public var webSize = (1600, 900)
    public var webHEVC: URL?
    public var webHEVCBitrate = 2_000_000
    public var webPoster: URL?
    public var scratch: URL
    public var frameRange: Range<Int>?
    public init(master: URL, scratch: URL) { self.master = master; self.scratch = scratch }
}

public enum FilmOutput {
    public static func render(_ film: Film, plan: OutputPlan, log: (String) -> Void = { print($0) }) throws {
        let r = FilmRenderer(film: film)
        let st = film.settings
        let master = try VideoWriter(url: plan.master, width: st.width, height: st.height, fps: st.fps, bitrate: plan.masterBitrate, network: true)
        let web = try plan.web.map { try VideoWriter(url: $0, width: plan.webSize.0, height: plan.webSize.1, fps: st.fps, bitrate: plan.webBitrate, network: true) }
        let webHEVC = try plan.webHEVC.map { try VideoWriter(url: $0, width: plan.webSize.0, height: plan.webSize.1, fps: st.fps, bitrate: plan.webHEVCBitrate, network: true, codec: .hevc) }
        var captures: [Int: [URL]] = [:]
        var stripFrames: [Int: CGImage] = [:]
        let fps = Double(st.fps)
        func idx(_ t: Double) -> Int { min(film.frameCount - 1, max(0, Int((t * fps).rounded()))) }
        if let p = plan.poster { captures[idx(p.0), default: []].append(p.1) }
        for s in plan.stills { captures[idx(s.0), default: []].append(s.1) }
        let stripIdx = Set((plan.strip?.0 ?? []).map(idx))
        let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
        let range = plan.frameRange ?? 0..<film.frameCount
        let t0 = Date()
        var samples = 0
        var firstThumb: [Float] = [], lastThumb: [Float] = [], prevThumb: [Float] = []
        var steps: [Double] = []
        let probe = WindowLoop(context: r.context)
        for i in range { autoreleasepool {
            let img = r.frame(i)
            samples += r.lastSampleCount
            master.append(img, frame: i - range.lowerBound, context: r.context)
            let tb = probe.thumb(img, 96, Int(96 * Double(st.height) / Double(st.width)))
            if i == range.lowerBound { firstThumb = tb } else { steps.append(probe.diff(prevThumb, tb)) }
            prevThumb = tb
            lastThumb = tb
            if web != nil || webHEVC != nil || (plan.webPoster != nil && i == range.lowerBound) {
                let s = Double(plan.webSize.0) / Double(st.width)
                let box = CGRect(x: 0, y: 0, width: plan.webSize.0, height: plan.webSize.1)
                let wimg = img.applyingFilter("CILanczosScaleTransform", parameters: ["inputScale": s, "inputAspectRatio": 1.0]).cropped(to: box)
                web?.append(wimg, frame: i - range.lowerBound, context: r.context)
                webHEVC?.append(wimg, frame: i - range.lowerBound, context: r.context)
                if let poster = plan.webPoster, i == range.lowerBound {
                    Images.write(r.context.createCGImage(wimg, from: box, format: .RGBA8, colorSpace: srgb)!, to: poster, jpeg: true)
                }
            }
            if captures[i] != nil || stripIdx.contains(i) {
                let cg = r.context.createCGImage(img, from: CGRect(x: 0, y: 0, width: st.width, height: st.height), format: .RGBA8, colorSpace: srgb)!
                for u in captures[i] ?? [] { Images.write(cg, to: u, jpeg: u.pathExtension.lowercased() == "jpg") }
                if stripIdx.contains(i) { stripFrames[i] = cg }
            }
            if i % 60 == 0 { log(String(format: "frame %d/%d  %.1fs elapsed  samples %d", i, film.frameCount, Date().timeIntervalSince(t0), r.lastSampleCount)) }
        } }
        master.finish()
        web?.finish()
        webHEVC?.finish()
        let el = Date().timeIntervalSince(t0)
        log(String(format: "rendered %d frames in %.1fs (%.1f ms/frame, %.2f samples/frame avg)", range.count, el, el * 1000 / Double(range.count), Double(samples) / Double(range.count)))
        let sortedSteps = steps.sorted()
        log(String(format: "loop seam (last frame → first frame) %.2f vs median frame step %.2f, max step %.2f (mean abs, 0-255)", probe.diff(lastThumb, firstThumb), sortedSteps.isEmpty ? 0 : sortedSteps[sortedSteps.count / 2], sortedSteps.last ?? 0))
        if let (times, url) = plan.strip {
            let frames = times.map(idx).compactMap { stripFrames[$0] }
            writeStrip(frames, times: times, to: url)
        }
    }

    static func writeStrip(_ frames: [CGImage], times: [Double], to url: URL) {
        let cols = 4, tw = 480, g = 12, label = 28
        let th = frames.first.map { Int((Double(tw) * Double($0.height) / Double($0.width)).rounded()) } ?? 270
        let rows = (frames.count + cols - 1) / cols
        let w = cols * tw + (cols + 1) * g
        let h = rows * (th + label) + (rows + 1) * g
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(srgbRed: 0.07, green: 0.07, blue: 0.08, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.interpolationQuality = .high
        let font = Fonts.font("InstrumentSans-Regular", 15)
        for (k, f) in frames.enumerated() {
            let c = k % cols, rr = k / cols
            let x = g + c * (tw + g)
            let y = h - (g + rr * (th + label + g)) - th
            ctx.draw(f, in: CGRect(x: x, y: y, width: tw, height: th))
            let s = String(format: "%.2f s", times[k])
            let attrs: [CFString: Any] = [kCTFontAttributeName: font, kCTForegroundColorAttributeName: CGColor(gray: 0.75, alpha: 1)]
            let line = CTLineCreateWithAttributedString(CFAttributedStringCreate(nil, s as CFString, attrs as CFDictionary)!)
            ctx.textPosition = CGPoint(x: x + 2, y: y - 20)
            CTLineDraw(line, ctx)
        }
        Images.write(ctx.makeImage()!, to: url)
    }
}
