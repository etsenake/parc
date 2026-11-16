import AppKit

@main @MainActor struct Render {
    static func requireNoWindows(_ moment: String) {
        guard NSApp.windows.isEmpty else {
            FileHandle.standardError.write(Data("FAIL: \(NSApp.windows.count) window(s) exist \(moment): \(NSApp.windows)\n".utf8))
            exit(2)
        }
    }

    static func writePNG(_ bitmap: NSBitmapImageRep, _ path: String) {
        guard let data = bitmap.representation(using: .png, properties: [:]) else { fatalError("no PNG for \(path)") }
        try! data.write(to: URL(fileURLWithPath: path))
        print("wrote", path, bitmap.pixelsWide, "x", bitmap.pixelsHigh)
    }

    static func main() {
        NSApplication.shared.setActivationPolicy(.prohibited)
        NSApp.appearance = NSAppearance(named: .aqua)
        let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "out"
        let mode = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "all"
        try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
        requireNoWindows("at start")
        let size = NSSize(width: 1440, height: 900)
        let windowRect = NSRect(x: 80, y: 18, width: 1280, height: 840)
        let page = CommandLine.arguments.count > 3 ? CommandLine.arguments[3] : ""
        let scene = BrowserScene(size: size, windowRect: windowRect, scale: 2, pagePath: page)
        requireNoWindows("after building the scene")
        let lines = scene.report()
        print(lines.joined(separator: "\n"))
        try? lines.joined(separator: "\n").write(toFile: out + "/report.txt", atomically: true, encoding: .utf8)
        if mode == "all" || mode == "still" {
            writePNG(scene.render(NSRect(origin: .zero, size: size), pixelsWide: 2880, pixelsHigh: 1800), out + "/window-work.png")
            requireNoWindows("after the still")
        }
        if mode == "compare" {
            let cached = scene.render(NSRect(origin: .zero, size: size), pixelsWide: 2880, pixelsHigh: 1800)
            writePNG(cached, out + "/compare-cachedisplay.png")
            for flip in [false, true] {
                guard let layered = scene.renderLayers(scale: 2, flip: flip) else { print("no layer image"); continue }
                let rep = NSBitmapImageRep(cgImage: layered)
                writePNG(rep, out + "/compare-layers-\(flip ? "flipped" : "plain").png")
                Compare.report(cached, rep, regions: [("sidebar", NSRect(x: 80, y: 18, width: 228, height: 840)),
                                                       ("page", NSRect(x: 308, y: 28, width: 1042, height: 820)),
                                                       ("whole", NSRect(origin: .zero, size: size))], label: flip ? "flipped" : "plain")
            }
            requireNoWindows("after compare")
        }
        if mode == "collapse" || mode == "collapse-keys" {
            CollapseFilm.run(scene, out: out, keysOnly: mode == "collapse-keys")
            requireNoWindows("after the film")
        }
        if mode == "all" || mode == "video" {
            writeProof(scene, path: out + "/proof.mp4", sheet: out + "/proof-frames.png")
            requireNoWindows("after the video")
        }
        requireNoWindows("at exit")
        print("windows at exit: \(NSApp.windows.count)")
    }

    static func writeProof(_ scene: BrowserScene, path: String, sheet: String) {
        let crop = NSRect(x: scene.windowRect.minX, y: scene.windowRect.minY + 150, width: 800, height: 500)
        let rows = scene.scenario.todayTitles.compactMap { scene.row(titled: $0) }
            + ["Q4 planning", "Design review notes", "Team calendar"].compactMap { scene.row(titled: $0) }
        let ordered = rows.sorted { scene.surface.convert($0.bounds, from: $0).minY < scene.surface.convert($1.bounds, from: $1).minY }
        guard let first = ordered.first, let last = ordered.last else { print("no rows for the proof"); return }
        let top = scene.surface.convert(first.bounds, from: first), bottom = scene.surface.convert(last.bounds, from: last)
        let x = top.minX + 120
        let writer = try! VideoWriter(path: path, width: 1600, height: 1000)
        let frames = 120
        var keyframes: [NSBitmapImageRep] = []
        for frame in 0..<frames {
            let t = Double(frame) / Double(frames - 1)
            let eased = CGFloat(0.5 - 0.5 * cos(Double.pi * t))
            let point = NSPoint(x: x + 6 * sin(CGFloat(t) * .pi), y: top.midY + (bottom.midY - top.midY) * eased)
            let stagePoint = NSPoint(x: point.x + scene.windowRect.minX, y: point.y + scene.windowRect.minY)
            precondition(crop.contains(stagePoint), "pointer leaves the clip")
            scene.pointer.location = point
            let hovered = ordered.first { scene.surface.convert($0.bounds, from: $0).contains(point) }
            scene.setHover(hovered)
            let bitmap = scene.render(crop, pixelsWide: 1600, pixelsHigh: 1000)
            writer.append(bitmap.cgImage!, background: NSColor.white.cgColor)
            if frame % 30 == 0 || frame == frames - 1 { keyframes.append(bitmap) }
        }
        scene.pointer.location = nil
        scene.setHover(nil)
        let result = writer.finish()
        print("wrote", path, result.frames, "frames status", result.status.rawValue, result.error?.localizedDescription ?? "")
        let thumb = NSSize(width: 400, height: 250)
        let image = NSImage(size: NSSize(width: thumb.width * CGFloat(keyframes.count), height: thumb.height), flipped: false) { _ in
            for (index, rep) in keyframes.enumerated() {
                rep.draw(in: NSRect(x: CGFloat(index) * thumb.width, y: 0, width: thumb.width, height: thumb.height))
            }
            return true
        }
        if let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) { writePNG(rep, sheet) }
    }
}
