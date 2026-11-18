import AppKit

@MainActor enum StackRun {
    static let stripTimes = [0.0, 0.9, 1.45, 1.8, 2.8, 3.6, 4.7, 5.2, 5.6, 6.1, 6.6, 8.9]

    static func run(out: String, stills: [Double]?) {
        let started = Date()
        let film = StackFilm()
        Render.requireNoWindows("after building the stacked scene")
        let fps = StackFilm.fps
        let total = Int((StackFilm.duration * fps).rounded())
        let writer = stills == nil ? try! AlphaVideoWriter(path: out + "/stacks.mov", width: 2880, height: 1800) : nil
        var strip: [(Double, CGImage)] = []
        let stage = NSRect(x: 0, y: 0, width: 1440, height: 900)
        let last = stills?.max() ?? StackFilm.duration
        for frame in 0..<total {
            let t = Double(frame) / fps
            if t > last + 0.5 / fps { break }
            film.step(t)
            let wantsStill = stills?.contains { abs($0 - t) < 0.5 / fps } ?? false
            let inStrip = stills == nil && stripTimes.contains { abs($0 - t) < 0.5 / fps }
            guard writer != nil || wantsStill || inStrip else { continue }
            let bitmap = film.scene.render(stage, pixelsWide: 2880, pixelsHigh: 1800)
            guard let image = bitmap.cgImage else { continue }
            writer?.append(image)
            if wantsStill { Render.writePNG(bitmap, out + String(format: "/still-%.2f.png", t)); strip.append((t, image)) }
            if inStrip { strip.append((t, image)) }
            if frame % 60 == 0 { print(String(format: "frame %d t %.2f elapsed %.0fs", frame, t, Date().timeIntervalSince(started))) }
        }
        if let writer {
            let result = writer.finish()
            print("wrote", out + "/stacks.mov", result.frames, "frames status", result.status.rawValue, result.error?.localizedDescription ?? "")
        }
        SplitRun.writeStrip(strip, path: out + (stills == nil ? "/stacks-strip.png" : "/stacks-proof-strip.png"))
        let beats: [[String: Any]] = film.beats.sorted { $0.0 < $1.0 }.map { beat in
            ["t": (beat.0 * 1000).rounded() / 1000, "frame": Int((beat.0 * fps).rounded()), "beat": beat.1]
        }
        let json: [String: Any] = ["scene": "split view stacks", "fps": Int(fps), "duration": StackFilm.duration, "frames": total,
                                   "size": [2880, 1800], "points": [1440, 900], "window": [80, 18, 1280, 840],
                                   "beats": beats, "log": film.log, "drop": film.drop?.log ?? film.dropLog]
        let data = try! JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
        try! data.write(to: URL(fileURLWithPath: out + (stills == nil ? "/stacks-beats.json" : "/stacks-proof-beats.json")))
        print(film.log.joined(separator: "\n"))
        print((film.drop?.log ?? film.dropLog).joined(separator: "\n"))
        print(String(format: "done in %.0fs", Date().timeIntervalSince(started)))
    }
}
