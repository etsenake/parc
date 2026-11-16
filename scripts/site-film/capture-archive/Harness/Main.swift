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
        setvbuf(stdout, nil, _IOLBF, 0)
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
        let pages = "../pages/png"
        if mode.hasPrefix("capture") {
            CaptureFilm(scene: scene, pagePath: pages + "/article.png").run(out: out, stills: mode.hasSuffix("stills"))
        }
        if mode.hasPrefix("archive") {
            let directory = URL(fileURLWithPath: out).appendingPathComponent("archive-store", isDirectory: true)
            ArchiveFilm(scene: scene, articlePath: pages + "/article.png", picnicPath: pages + "/picnic.png", storeDirectory: directory)
                .run(out: out, stills: mode.hasSuffix("stills"))
        }
        requireNoWindows("at exit")
        print("windows at exit: \(NSApp.windows.count)")
    }
}
