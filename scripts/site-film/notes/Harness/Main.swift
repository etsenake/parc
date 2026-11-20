import AppKit

@main @MainActor struct Render {
    static func requireNoWindows(_ moment: String) {
        guard NSApp.windows.isEmpty else {
            FileHandle.standardError.write(Data("FAIL: \(NSApp.windows.count) window(s) exist \(moment): \(NSApp.windows)\n".utf8))
            exit(2)
        }
    }

    static func main() {
        setvbuf(stdout, nil, _IOLBF, 0)
        NSApplication.shared.setActivationPolicy(.prohibited)
        NSApp.appearance = NSAppearance(named: .aqua)
        WindowGuard.install()
        InputGuard.install()
        FilmMotion.shared.install()
        let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "out"
        let mode = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "notes"
        try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
        requireNoWindows("at start")
        guard mode.hasPrefix("notes") else {
            FileHandle.standardError.write(Data("usage: render <out> notes|notes-still\n".utf8))
            exit(1)
        }
        let scene = NotesScene()
        requireNoWindows("after building the notes scene")
        scene.run(out: out, still: mode.hasSuffix("-still"))
        requireNoWindows("at exit")
        print("windows at exit: \(NSApp.windows.count)")
    }
}
