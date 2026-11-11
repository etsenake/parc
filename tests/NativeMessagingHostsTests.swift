import Foundation

@main
struct NativeMessagingHostsTests {
    static var assertions = 0
    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        assertions += 1
        precondition(condition(), message)
    }

    static func main() throws {
        let files = FileManager.default
        let root = files.temporaryDirectory.appendingPathComponent("parc-nmh-\(UUID().uuidString)", isDirectory: true)
        defer { try? files.removeItem(at: root) }
        let arc = root.appendingPathComponent("home/Library/Application Support/Arc/User Data/NativeMessagingHosts", isDirectory: true)
        let chrome = root.appendingPathComponent("chrome", isDirectory: true)
        let missing = root.appendingPathComponent("missing", isDirectory: true)
        let engine = root.appendingPathComponent("engine", isDirectory: true)
        let folder = engine.appendingPathComponent("NativeMessagingHosts", isDirectory: true)
        for directory in [arc, chrome] { try files.createDirectory(at: directory, withIntermediateDirectories: true) }
        func write(_ text: String, _ url: URL) throws { try Data(text.utf8).write(to: url) }
        try write("arc-a", arc.appendingPathComponent("a.json"))
        try write("arc-b", arc.appendingPathComponent("b.json"))
        try write("chrome-b", chrome.appendingPathComponent("b.json"))
        try write("chrome-c", chrome.appendingPathComponent("c.json"))
        try write("chrome-e", chrome.appendingPathComponent("e.json"))
        try write("notes", chrome.appendingPathComponent("notes.txt"))
        let sources = [arc, missing, chrome]
        func contents(_ name: String) -> String? {
            (try? Data(contentsOf: folder.appendingPathComponent(name))).map { String(decoding: $0, as: UTF8.self) }
        }
        func destination(_ name: String) -> String? {
            try? files.destinationOfSymbolicLink(atPath: folder.appendingPathComponent(name).path)
        }
        func link() { NativeMessagingHosts.link(engineRoot: engine, sources: sources, fileManager: files) }

        link()
        expect(files.fileExists(atPath: folder.path), "The engine's manifest folder is created")
        expect(destination("a.json") == arc.appendingPathComponent("a.json").path, "Arc's manifest is linked")
        expect(contents("b.json") == "arc-b", "Arc's manifest wins over Chrome's of the same host")
        expect(contents("c.json") == "chrome-c", "A host only Chrome has is linked")
        expect(contents("notes.txt") == nil, "Only manifests are linked")

        try files.removeItem(at: folder.appendingPathComponent("c.json"))
        try write("own-c", folder.appendingPathComponent("c.json"))
        let elsewhere = root.appendingPathComponent("volume/d.json").path
        try files.createSymbolicLink(atPath: folder.appendingPathComponent("d.json").path, withDestinationPath: elsewhere)
        try files.removeItem(at: arc.appendingPathComponent("b.json"))
        try files.removeItem(at: chrome.appendingPathComponent("e.json"))
        try write("arc-c", arc.appendingPathComponent("c.json"))
        try write("arc-x", arc.appendingPathComponent("x.json"))
        link()
        expect(contents("c.json") == "own-c", "A manifest installed for Parc itself is never replaced")
        expect(destination("d.json") == elsewhere, "A link Parc didn't make is kept, even when dangling")
        expect(contents("b.json") == "chrome-b", "A host Arc dropped falls back to Chrome's manifest")
        expect(destination("e.json") == nil, "A host every browser dropped is unlinked")
        expect(contents("a.json") == "arc-a", "Existing links are kept")

        try files.removeItem(at: folder.appendingPathComponent("c.json"))
        link()
        try write("arc-b2", arc.appendingPathComponent("b.json"))
        link()
        expect(contents("b.json") == "arc-b2", "A link is re-pointed when Arc gains the host again")
        expect(contents("c.json") == "arc-c", "Arc's manifest is linked once the own file is gone")
        link()
        let names = try files.contentsOfDirectory(atPath: folder.path).sorted()
        expect(names == ["a.json", "b.json", "c.json", "d.json", "x.json"], "Relinking is idempotent")

        let renamed = root.appendingPathComponent("old-home/Library/Application Support/Arc/User Data/NativeMessagingHosts/y.json").path
        try files.createSymbolicLink(atPath: folder.appendingPathComponent("y.json").path, withDestinationPath: renamed)
        try write("arc-y", arc.appendingPathComponent("y.json"))
        let unplugged = root.appendingPathComponent("Volumes/External/NativeMessagingHosts/z.json").path
        try files.createSymbolicLink(atPath: folder.appendingPathComponent("z.json").path, withDestinationPath: unplugged)
        try write("arc-z", arc.appendingPathComponent("z.json"))
        let chosen = chrome.appendingPathComponent("c.json").path
        try files.removeItem(at: folder.appendingPathComponent("x.json"))
        try files.createSymbolicLink(atPath: folder.appendingPathComponent("x.json").path, withDestinationPath: chosen)
        link()
        expect(contents("y.json") == "arc-y", "A link left behind by a renamed home folder is repaired")
        expect(destination("x.json") == chosen, "A link under another manifest's name is the user's and kept")
        expect(destination("z.json") == unplugged, "A user's link to an unplugged drive is kept")

        let pointed = root.appendingPathComponent("pointed", isDirectory: true)
        try files.createDirectory(at: pointed, withIntermediateDirectories: true)
        let other = root.appendingPathComponent("other-engine", isDirectory: true)
        try files.createDirectory(at: other, withIntermediateDirectories: true)
        try files.createSymbolicLink(at: other.appendingPathComponent("NativeMessagingHosts"), withDestinationURL: pointed)
        NativeMessagingHosts.link(engineRoot: other, sources: sources, fileManager: files)
        let pointedNames = try files.contentsOfDirectory(atPath: pointed.path)
        expect(pointedNames.isEmpty,
               "A manifest folder the user pointed elsewhere is left alone")

        let home = URL(fileURLWithPath: "/Users/someone", isDirectory: true)
        let paths = NativeMessagingHosts.sourceDirectories(home: home).map(\.path)
        expect(paths.first == "/Users/someone/Library/Application Support/Arc/User Data/NativeMessagingHosts",
               "Arc's folder is searched first")
        expect(paths.contains("/Users/someone/Library/Application Support/Google/Chrome/NativeMessagingHosts"),
               "Chrome's folder is searched")

        print("\(assertions) native messaging host assertions passed")
    }
}
