import AppKit
@testable import Parc
import ParcCore

struct FingerSwipe {
    let name: String
    let start: Double
    let duration: Double
    let distance: CGFloat
    let rest: Double
    let easesOut: Bool

    func finger(_ u: Double) -> CGFloat {
        let u = CGFloat(min(1, max(0, u)))
        return easesOut ? distance * (1 - (1 - u) * (1 - u)) : distance * u * u * (2.2 - 1.2 * u)
    }
    var release: Double { start + duration + rest }
}

@MainActor enum SpacesFilm {
    static let fps = 60
    static let substeps = 2
    static let duration = 9.0
    static let swipes = [
        FingerSwipe(name: "Work to Home", start: 1.00, duration: 0.40, distance: -300, rest: 0, easesOut: false),
        FingerSwipe(name: "Home to Side quest", start: 3.00, duration: 0.40, distance: -300, rest: 0, easesOut: false),
        FingerSwipe(name: "Past Side quest (rubber band)", start: 4.85, duration: 0.55, distance: -320, rest: 0.12, easesOut: true),
        FingerSwipe(name: "Side quest to Home", start: 6.25, duration: 0.36, distance: 300, rest: 0, easesOut: false),
        FingerSwipe(name: "Home to Work", start: 7.25, duration: 0.36, distance: 300, rest: 0, easesOut: false),
    ]
    static let sheetTimes: [Double] = [0.50, 1.22, 1.40, 1.60, 2.50, 3.30, 4.40, 5.30, 5.62, 6.50, 7.45, 8.60]
    static let keyTimes: [(String, Double)] = [("mid-swipe", 1.30), ("release", 1.42), ("settle", 1.60), ("rubber-band", 5.40),
                                               ("rubber-release", 5.62), ("swipe-back", 6.50), ("work-end", 8.60)]

    struct TraceRow: Encodable {
        let frame: Int
        let t: Double
        let stripOffset: Double
        let space: String
        let themeFrom: String?
        let themeTo: String?
        let themeProgress: Double?
        let fingerDown: Bool
    }

    static func run(_ scene: BrowserScene, out: String, limit: Int? = nil) {
        let pager = scene.sidebar.spacePager
        let spaces = scene.state.spaces
        let name = { (theme: SpaceTheme) in spaces.first { $0.theme == theme }?.name }
        let frames = limit ?? Int(duration * Double(fps))
        let dt = 1.0 / Double(fps * substeps)
        let writer = try! AlphaVideoWriter(path: out + "/spaces.mov", width: 2880, height: 1800)
        var sheet: [(Double, CGImage)] = []
        var trace: [TraceRow] = []
        var swipeLog: [[String: Any]] = []
        var settled: [Int: Double] = [:]
        var started = Date()
        for step in 0..<(frames * substeps) {
            let t = Double(step) * dt
            scene.clock = t
            var down = false
            for (index, swipe) in swipes.enumerated() {
                let begin = Int((swipe.start / dt).rounded()), end = Int((swipe.release / dt).rounded())
                guard step >= begin, step <= end else { continue }
                let u0 = (Double(step - 1) * dt - swipe.start) / swipe.duration, u1 = (t - swipe.start) / swipe.duration
                let dx = swipe.finger(u1) - swipe.finger(u0)
                if step == begin {
                    let ok = pager.gesture(phase: .began, momentum: false, dx: swipe.finger(1.0 / 48) - swipe.finger(0), dy: 0, time: t)
                    swipeLog.append(["name": swipe.name, "fingerDown": t, "began": ok, "fromSpace": scene.spaceName,
                                     "fingerDistance": Double(swipe.distance), "stripTravelUnresisted": Double(-0.5 * swipe.distance)])
                    down = true
                } else if step == end {
                    swipeLog[index]["stripOffsetAtRelease"] = Double(pager.offset)
                    _ = pager.gesture(phase: .ended, momentum: false, dx: 0, dy: 0, time: t)
                    swipeLog[index]["release"] = t
                    swipeLog[index]["stripOffsetAfterCommit"] = Double(pager.offset)
                } else {
                    _ = pager.gesture(phase: .changed, momentum: false, dx: dx, dy: 0, time: t)
                    down = true
                }
            }
            pager.tick()
            for (index, entry) in swipeLog.enumerated() where settled[index] == nil {
                if let release = entry["release"] as? Double, t > release, !pager.isAnimating, pager.offset == 0, !pager.isTracking {
                    settled[index] = t
                }
            }
            guard step % substeps == 0 else { continue }
            let frame = step / substeps
            autoreleasepool {
            RunLoop.main.run(until: Date().addingTimeInterval(0.001))
            scene.updateTheme()
            let bitmap = scene.render(NSRect(origin: .zero, size: scene.stage.bounds.size), pixelsWide: 2880, pixelsHigh: 1800)
            guard var image = bitmap.cgImage else { fatalError("no frame image") }
            if let faded = dockCrossfade(scene, over: image, at: t) { image = faded }
            writer.append(image)
            trace.append(TraceRow(frame: frame, t: t, stripOffset: Double(pager.offset), space: scene.spaceName,
                                  themeFrom: scene.transition.flatMap { name($0.from) }, themeTo: scene.transition.flatMap { name($0.theme) },
                                  themeProgress: scene.transition.map { Double($0.progress) }, fingerDown: down))
            if sheetTimes.contains(where: { abs($0 - t) < dt / 2 }) { sheet.append((t, image)) }
            for (name, time) in keyTimes where abs(time - t) < dt / 2 {
                Render.writePNG(NSBitmapImageRep(cgImage: image), out + "/key-\(name).png")
            }
            if frame % 60 == 0 {
                print(String(format: "frame %d t=%.2f offset=%.1f space=%@ (%.1fs)", frame, t, pager.offset, scene.spaceName, Date().timeIntervalSince(started)))
                started = Date()
            }
            }
        }
        let result = writer.finish()
        print("wrote", out + "/spaces.mov", result.frames, "frames status", result.status.rawValue, result.error?.localizedDescription ?? "")
        writeSheet(sheet, path: out + "/spaces-strip.png")
        for (index, time) in settled { swipeLog[index]["settled"] = time }
        for index in swipeLog.indices {
            if let release = swipeLog[index]["release"] as? Double,
               let commit = scene.commits.first(where: { abs($0.time - release) < 0.001 }) {
                swipeLog[index]["commit"] = commit.time; swipeLog[index]["toSpace"] = commit.space
            } else {
                swipeLog[index]["toSpace"] = swipeLog[index]["fromSpace"]
            }
        }
        writeBeats(swipeLog, trace: trace, path: out + "/spaces-beats.json")
    }

    static let dockFadeDuration = 0.25

    static func dockCrossfade(_ scene: BrowserScene, over image: CGImage, at t: Double) -> CGImage? {
        guard let fade = scene.dockFade, let dock = scene.dock, t - fade.time < dockFadeDuration, let from = fade.from,
              from != dock.selectedIndex else { return nil }
        let u = CGFloat((t - fade.time) / dockFadeDuration)
        let eased = u * u * (3 - 2 * u)
        let current = dock.selectedIndex
        dock.selectedIndex = from
        let old = scene.render(NSRect(origin: .zero, size: scene.stage.bounds.size), pixelsWide: image.width, pixelsHigh: image.height).cgImage
        dock.selectedIndex = current
        guard let old else { return nil }
        let scale = CGFloat(image.width) / scene.stage.bounds.width
        let rect = scene.stage.convert(dock.bounds, from: dock).insetBy(dx: -2, dy: -2)
        let clip = CGRect(x: rect.minX * scale, y: (scene.stage.bounds.height - rect.maxY) * scale, width: rect.width * scale, height: rect.height * scale)
        guard let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let full = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        context.draw(image, in: full)
        context.clip(to: clip)
        context.setAlpha(1 - eased)
        context.draw(old, in: full)
        return context.makeImage()
    }

    static func proof(_ scene: BrowserScene, out: String) {
        let pager = scene.sidebar.spacePager
        let rect = NSRect(origin: .zero, size: scene.stage.bounds.size)
        scene.updateTheme()
        Render.writePNG(scene.render(rect, pixelsWide: 2880, pixelsHigh: 1800), out + "/proof-rest.png")
        scene.clock = 0
        print("began", pager.gesture(phase: .began, momentum: false, dx: -2, dy: 0, time: 0))
        for i in 1...20 { scene.clock = Double(i) / 120; _ = pager.gesture(phase: .changed, momentum: false, dx: -12, dy: 0, time: scene.clock) }
        print("offset", pager.offset, "transition", scene.transition.map { "\($0.progress)" } ?? "nil")
        scene.updateTheme()
        Render.writePNG(scene.render(rect, pixelsWide: 2880, pixelsHigh: 1800), out + "/proof-strip.png")
        print("strips", BrowserScene.descendants(scene.sidebar).compactMap { $0 as? SidebarPageStripView }.map { "\($0.frame) \($0.layer?.sublayerTransform.m41 ?? 0) subviews \($0.subviews.map { "\(type(of: $0)) \($0.frame)" })" })
    }

    static func writeSheet(_ frames: [(Double, CGImage)], path: String) {
        let columns = 4, cell = CGSize(width: 720, height: 450), label: CGFloat = 28
        let rows = (frames.count + columns - 1) / columns
        let width = Int(cell.width) * columns, height = Int(cell.height + label) * rows
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
        context.setFillColor(hex(0xE6E6EA).cgColor); context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.interpolationQuality = .high
        let graphics = NSGraphicsContext(cgContext: context, flipped: false)
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = graphics
        for (index, (time, image)) in frames.enumerated() {
            let column = index % columns, row = index / columns
            let x = CGFloat(column) * cell.width, top = CGFloat(height) - CGFloat(row) * (cell.height + label)
            context.draw(image, in: CGRect(x: x, y: top - label - cell.height, width: cell.width, height: cell.height))
            NSAttributedString(string: String(format: "t = %.2f s  ·  frame %d", time, Int((time * Double(fps)).rounded())),
                               attributes: [.font: NSFont.monospacedSystemFont(ofSize: 15, weight: .medium), .foregroundColor: NSColor.black])
                .draw(at: NSPoint(x: x + 14, y: top - label + 6))
        }
        NSGraphicsContext.restoreGraphicsState()
        guard let image = context.makeImage() else { return }
        Render.writePNG(NSBitmapImageRep(cgImage: image), path)
    }

    static func writeBeats(_ swipes: [[String: Any]], trace: [TraceRow], path: String) {
        func frame(_ t: Double?) -> Int? { t.map { Int(($0 * Double(fps)).rounded()) } }
        let swipeRows: [[String: Any]] = swipes.map { entry in
            var row = entry
            for key in ["fingerDown", "release", "commit", "settled"] { if let f = frame(entry[key] as? Double) { row[key + "Frame"] = f } }
            return row
        }
        var beats: [[String: Any]] = []
        var cursor = 0.0
        for (index, entry) in swipeRows.enumerated() {
            let down = entry["fingerDown"] as? Double ?? cursor
            beats.append(["beat": "hold \(entry["fromSpace"] ?? "")", "start": cursor, "end": down, "startFrame": frame(cursor)!, "endFrame": frame(down)!])
            let end = entry["settled"] as? Double ?? down
            beats.append(["beat": "swipe: \(swipes[index]["name"] ?? "")", "start": down, "end": end, "startFrame": frame(down)!, "endFrame": frame(end)!])
            cursor = end
        }
        beats.append(["beat": "hold \(swipeRows.last?["toSpace"] ?? "")", "start": cursor, "end": duration, "startFrame": frame(cursor)!, "endFrame": frame(duration)!])
        let encoder = JSONEncoder()
        let traceJSON = (try? JSONSerialization.jsonObject(with: encoder.encode(trace))) ?? []
        let root: [String: Any] = [
            "file": "spaces.mov", "codec": "hevcWithAlpha", "width": 2880, "height": 1800, "pointSize": [1440, 900], "scale": 2, "fps": fps,
            "duration": duration, "frames": trace.count,
            "window": ["x": 80, "y": 18, "width": 1280, "height": 840, "origin": "top-left, points"],
            "sidebarWidth": 228,
            "motion": ["trackingFactor": -0.5, "spring": "critically damped, response 0.4 s", "rubberBand": "0.55*L*x/(0.55*x+L), L = 22.8",
                       "source": "SidebarSpacePager driven per 1/120 s with synthetic trackpad phases"],
            "beats": beats, "swipes": swipeRows, "trace": traceJSON]
        let data = try! JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
        try! data.write(to: URL(fileURLWithPath: path))
        print("wrote", path)
    }

    static func flood(out: String) {
        let scenario = ScenarioBuilder.make()
        let size = NSSize(width: 1920, height: 1080)
        let material = CGFloat(ThemeRenderMath.lightMaterial.x)
        for (space, name) in zip(scenario.spaces, ["work", "home", "sidequest"]) {
            let surface = ThemeRendererView(frame: NSRect(origin: .zero, size: size))
            surface.appearance = NSAppearance(named: .aqua)
            surface.theme = space.theme
            guard let theme = ThemeReadback.image(of: surface, scale: 1) else { print("no flood for", name); continue }
            let width = Int(size.width), height = Int(size.height)
            guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                          space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { continue }
            context.setFillColor(NSColor(white: material, alpha: 1).cgColor); context.fill(CGRect(origin: .zero, size: size))
            context.draw(theme, in: CGRect(origin: .zero, size: size))
            Render.writePNG(NSBitmapImageRep(cgImage: context.makeImage()!), out + "/flood-\(name).png")
        }
    }
}
