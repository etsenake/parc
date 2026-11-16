import Foundation
import CoreGraphics
import CoreImage

struct Piece { let source: VideoSource; let from: Double; let to: Double; let local: Double; let fade: Double }

func ease(_ value: Any?) -> Ease {
    switch value as? String {
    case "linear": return .linear
    case "hold": return .hold
    case "settle": return .spring(response: 1.1, damping: 1)
    case "out": return .bezier(0.4, 0, 0.25, 1)
    default: return .bezier(0.45, 0, 0.3, 1)
    }
}

@main
struct Plates {
    static func main() throws {
        setvbuf(stdout, nil, _IOLBF, 0)
        let config = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "plates.json")
        let base = config.deletingLastPathComponent()
        let only = CommandLine.arguments.count > 2 ? Set(CommandLine.arguments[2].split(separator: ",").map(String.init)) : nil
        let obj = try JSONSerialization.jsonObject(with: Data(contentsOf: config)) as! [String: Any]
        Fonts.register(base.appendingPathComponent("fonts"))
        let outDir = base.appendingPathComponent((obj["out"] as? String) ?? "out/plates")
        let review = outDir.appendingPathComponent("review")
        try FileManager.default.createDirectory(at: review, withIntermediateDirectories: true)
        let width = (obj["width"] as? Int) ?? 1200, height = (obj["height"] as? Int) ?? 788
        let bitrate = (obj["bitrate"] as? Int) ?? 2_500_000, fps = (obj["fps"] as? Int) ?? 60
        let context = CIContext(options: [.workingFormat: CIFormat.RGBAh, .cacheIntermediates: false])
        let looper = WindowLoop(context: context)
        let geometry = looper.geometry
        let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
        let box = CGRect(x: 0, y: 0, width: width, height: height)
        var sources: [String: VideoSource] = [:]
        for plate in obj["plates"] as! [[String: Any]] {
            let name = plate["name"] as! String
            if let only, !only.contains(name) { continue }
            var pieces: [Piece] = []
            var local = 0.0
            for seg in plate["segments"] as! [[String: Any]] {
                let path = seg["source"] as! String
                let url = base.appendingPathComponent(path)
                let src = try sources[url.path] ?? VideoSource(url)
                sources[url.path] = src
                let a = seg["in"] as! Double, b = seg["out"] as! Double
                pieces.append(Piece(source: src, from: a, to: b, local: local, fade: min((seg["fade"] as? Double) ?? 0, 0.4)))
                local += b - a
            }
            let length = local
            let keys = plate["camera"] as! [[Any]]
            func vec(_ k: [Any]) -> Vec3 { Vec3(k[1] as! Double, k[2] as! Double, k[3] as! Double) }
            var track = Track(vec(keys[0]))
            for k in keys.dropFirst() { track = track.keyed(k[0] as! Double, vec(k), ease(k.count > 4 ? k[4] : nil)) }
            let dissolve = min((plate["dissolve"] as? Double) ?? 0, 0.4)
            let n = Int((length * Double(fps)).rounded())
            let k = Int((dissolve * Double(fps)).rounded())
            var held: [Int: CIImage] = [:]
            for (i, piece) in pieces.enumerated() where i > 0 && piece.fade > 0 {
                let prev = pieces[i - 1]
                let image = prev.source.image(at: prev.to)
                held[i] = CIImage(cgImage: context.createCGImage(image, from: image.extent)!)
            }
            func sourceImage(_ t: Double) -> CIImage {
                let index = pieces.lastIndex { t >= $0.local - 1e-9 } ?? 0
                let piece = pieces[index]
                let image = piece.source.image(at: min(piece.from + t - piece.local, piece.to))
                guard let still = held[index], t - piece.local < piece.fade else { return image }
                let w = (t - piece.local) / piece.fade
                return still.applyingFilter("CIDissolveTransition", parameters: ["inputTargetImage": image, "inputTime": w * w * (3 - 2 * w)])
            }
            func cropRect(_ t: Double) -> CGRect {
                let v = track.value(at: t)
                let w = min(max(v.z, 200), 1280), h = w * 840 / 1280
                let x = min(max(v.x - w / 2, 0), 1280 - w), y = min(max(v.y - h / 2, 0), 840 - h)
                return CGRect(x: x, y: y, width: w, height: h)
            }
            func compose(_ t: Double) -> CIImage {
                let crop = geometry.ciRect(windowPoints: cropRect(t))
                let s = Double(width) / Double(crop.width)
                var out = looper.opaqueWindow(sourceImage(t)).cropped(to: crop)
                out = out.transformed(by: CGAffineTransform(translationX: -crop.minX, y: -crop.minY))
                out = out.applyingFilter("CILanczosScaleTransform", parameters: ["inputScale": s, "inputAspectRatio": (Double(height) / Double(crop.height)) / s])
                return out.cropped(to: box).settingAlphaOne(in: box)
            }
            let firstCG = context.createCGImage(compose(0), from: box, format: .RGBA8, colorSpace: srgb)!
            let first = CIImage(cgImage: firstCG)
            Images.write(firstCG, to: outDir.appendingPathComponent("\(name).jpg"), jpeg: true)
            Images.write(firstCG, to: review.appendingPathComponent("\(name)-first.png"))
            let url = outDir.appendingPathComponent("\(name).mp4")
            let writer = try VideoWriter(url: url, width: width, height: height, fps: fps, bitrate: bitrate, network: true)
            var stripFrames: [CGImage] = []
            let stripIdx = (0..<8).map { $0 * n / 8 }
            var firstThumb: [Float] = [], prevThumb: [Float] = [], steps: [Double] = []
            let tw = 96, th = Int((96.0 * Double(height) / Double(width)).rounded())
            for i in 0..<n {
                autoreleasepool {
                    let t = Double(i) / Double(fps)
                    var img = i == 0 ? first : compose(t)
                    if k > 0 && i >= n - k {
                        let w = Double(i - (n - k) + 1) / Double(k)
                        let s = w * w * (3 - 2 * w)
                        img = img.applyingFilter("CIDissolveTransition", parameters: ["inputTargetImage": first, "inputTime": s])
                    }
                    writer.append(img, frame: i, context: context)
                    let tb = looper.thumb(img, tw, th)
                    if i == 0 { firstThumb = tb } else { steps.append(looper.diff(prevThumb, tb)) }
                    prevThumb = tb
                    if stripIdx.contains(i) || i == n - 1 {
                        let cg = context.createCGImage(img, from: box, format: .RGBA8, colorSpace: srgb)!
                        if stripIdx.contains(i) { stripFrames.append(cg) }
                        if i == n - 1 { Images.write(cg, to: review.appendingPathComponent("\(name)-last.png")) }
                    }
                }
            }
            writer.finish()
            FilmOutput.writeStrip(stripFrames, times: stripIdx.map { Double($0) / Double(fps) }, to: review.appendingPathComponent("\(name)-strip.png"))
            let sorted = steps.sorted()
            let size = ((try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0) ?? 0
            print(String(format: "%@: %d frames (%.2f s) %dx%d, dissolve %.2f s; seam %.2f vs median step %.2f; %.2f MB", name, n, length, width, height, dissolve,
                         looper.diff(prevThumb, firstThumb), sorted.isEmpty ? 0 : sorted[sorted.count / 2], Double(size) / 1_000_000))
        }
    }
}
