import Foundation
import Testing
@testable import ParcCore

struct NativeMessagingHostsTests {
    final class Layout {
        let files = FileManager.default
        let root: URL
        let arc: URL
        let chrome: URL
        let missing: URL
        let engine: URL
        let folder: URL
        var sources: [URL] { [arc, missing, chrome] }

        init() throws {
            root = files.temporaryDirectory.appendingPathComponent("parc-nmh-\(UUID().uuidString)", isDirectory: true)
            arc = root.appendingPathComponent("home/Library/Application Support/Arc/User Data/NativeMessagingHosts", isDirectory: true)
            chrome = root.appendingPathComponent("chrome", isDirectory: true)
            missing = root.appendingPathComponent("missing", isDirectory: true)
            engine = root.appendingPathComponent("engine", isDirectory: true)
            folder = engine.appendingPathComponent("NativeMessagingHosts", isDirectory: true)
            for directory in [arc, chrome] { try files.createDirectory(at: directory, withIntermediateDirectories: true) }
            try write("arc-a", arc.appendingPathComponent("a.json"))
            try write("arc-b", arc.appendingPathComponent("b.json"))
            try write("chrome-b", chrome.appendingPathComponent("b.json"))
            try write("chrome-c", chrome.appendingPathComponent("c.json"))
            try write("chrome-e", chrome.appendingPathComponent("e.json"))
            try write("notes", chrome.appendingPathComponent("notes.txt"))
        }

        deinit { try? files.removeItem(at: root) }

        func write(_ text: String, _ url: URL) throws { try Data(text.utf8).write(to: url) }

        func contents(_ name: String) -> String? {
            (try? Data(contentsOf: folder.appendingPathComponent(name))).map { String(decoding: $0, as: UTF8.self) }
        }

        func destination(_ name: String) -> String? {
            try? files.destinationOfSymbolicLink(atPath: folder.appendingPathComponent(name).path)
        }

        func link() { NativeMessagingHosts.link(engineRoot: engine, sources: sources, fileManager: files) }

        var elsewhere: String { root.appendingPathComponent("volume/d.json").path }

        func changeSources() throws {
            try files.removeItem(at: folder.appendingPathComponent("c.json"))
            try write("own-c", folder.appendingPathComponent("c.json"))
            try files.createSymbolicLink(atPath: folder.appendingPathComponent("d.json").path, withDestinationPath: elsewhere)
            try files.removeItem(at: arc.appendingPathComponent("b.json"))
            try files.removeItem(at: chrome.appendingPathComponent("e.json"))
            try write("arc-c", arc.appendingPathComponent("c.json"))
            try write("arc-x", arc.appendingPathComponent("x.json"))
        }

        func relinkAfterOwnFileIsGone() throws {
            try files.removeItem(at: folder.appendingPathComponent("c.json"))
            link()
            try write("arc-b2", arc.appendingPathComponent("b.json"))
            link()
        }

        var unplugged: String { root.appendingPathComponent("Volumes/External/NativeMessagingHosts/z.json").path }
        var chosen: String { chrome.appendingPathComponent("c.json").path }

        func leaveStaleLinks() throws {
            let renamed = root.appendingPathComponent("old-home/Library/Application Support/Arc/User Data/NativeMessagingHosts/y.json").path
            try files.createSymbolicLink(atPath: folder.appendingPathComponent("y.json").path, withDestinationPath: renamed)
            try write("arc-y", arc.appendingPathComponent("y.json"))
            try files.createSymbolicLink(atPath: folder.appendingPathComponent("z.json").path, withDestinationPath: unplugged)
            try write("arc-z", arc.appendingPathComponent("z.json"))
            try files.removeItem(at: folder.appendingPathComponent("x.json"))
            try files.createSymbolicLink(atPath: folder.appendingPathComponent("x.json").path, withDestinationPath: chosen)
        }
    }

    @Test func theEnginesManifestFolderIsCreatedAndArcsManifestIsLinked() throws {
        let layout = try Layout()
        layout.link()
        #expect(layout.files.fileExists(atPath: layout.folder.path))
        #expect(layout.destination("a.json") == layout.arc.appendingPathComponent("a.json").path)
    }

    @Test func arcsManifestWinsOverChromesOfTheSameHost() throws {
        let layout = try Layout()
        layout.link()
        #expect(layout.contents("b.json") == "arc-b")
    }

    @Test func aHostOnlyChromeHasIsLinked() throws {
        let layout = try Layout()
        layout.link()
        #expect(layout.contents("c.json") == "chrome-c")
    }

    @Test func onlyManifestsAreLinked() throws {
        let layout = try Layout()
        layout.link()
        #expect(layout.contents("notes.txt") == nil)
    }

    @Test func aManifestInstalledForParcItselfIsNeverReplaced() throws {
        let layout = try Layout()
        layout.link()
        try layout.changeSources()
        layout.link()
        #expect(layout.contents("c.json") == "own-c")
    }

    @Test func aLinkParcDidntMakeIsKeptEvenWhenDangling() throws {
        let layout = try Layout()
        layout.link()
        try layout.changeSources()
        layout.link()
        #expect(layout.destination("d.json") == layout.elsewhere)
    }

    @Test func aHostArcDroppedFallsBackToChromesManifest() throws {
        let layout = try Layout()
        layout.link()
        try layout.changeSources()
        layout.link()
        #expect(layout.contents("b.json") == "chrome-b")
    }

    @Test func aHostEveryBrowserDroppedIsUnlinked() throws {
        let layout = try Layout()
        layout.link()
        try layout.changeSources()
        layout.link()
        #expect(layout.destination("e.json") == nil)
    }

    @Test func existingLinksAreKept() throws {
        let layout = try Layout()
        layout.link()
        try layout.changeSources()
        layout.link()
        #expect(layout.contents("a.json") == "arc-a")
    }

    @Test func aLinkIsRepointedWhenArcGainsTheHostAgain() throws {
        let layout = try Layout()
        layout.link()
        try layout.changeSources()
        layout.link()
        try layout.relinkAfterOwnFileIsGone()
        #expect(layout.contents("b.json") == "arc-b2")
    }

    @Test func arcsManifestIsLinkedOnceTheOwnFileIsGone() throws {
        let layout = try Layout()
        layout.link()
        try layout.changeSources()
        layout.link()
        try layout.relinkAfterOwnFileIsGone()
        #expect(layout.contents("c.json") == "arc-c")
    }

    @Test func relinkingIsIdempotent() throws {
        let layout = try Layout()
        layout.link()
        try layout.changeSources()
        layout.link()
        try layout.relinkAfterOwnFileIsGone()
        layout.link()
        let names = try layout.files.contentsOfDirectory(atPath: layout.folder.path).sorted()
        #expect(names == ["a.json", "b.json", "c.json", "d.json", "x.json"])
    }

    @Test func aLinkLeftBehindByARenamedHomeFolderIsRepaired() throws {
        let layout = try Layout()
        layout.link()
        try layout.changeSources()
        layout.link()
        try layout.relinkAfterOwnFileIsGone()
        layout.link()
        try layout.leaveStaleLinks()
        layout.link()
        #expect(layout.contents("y.json") == "arc-y")
    }

    @Test func aLinkUnderAnotherManifestsNameIsTheUsersAndKept() throws {
        let layout = try Layout()
        layout.link()
        try layout.changeSources()
        layout.link()
        try layout.relinkAfterOwnFileIsGone()
        layout.link()
        try layout.leaveStaleLinks()
        layout.link()
        #expect(layout.destination("x.json") == layout.chosen)
    }

    @Test func aUsersLinkToAnUnpluggedDriveIsKept() throws {
        let layout = try Layout()
        layout.link()
        try layout.changeSources()
        layout.link()
        try layout.relinkAfterOwnFileIsGone()
        layout.link()
        try layout.leaveStaleLinks()
        layout.link()
        #expect(layout.destination("z.json") == layout.unplugged)
    }

    @Test func aManifestFolderTheUserPointedElsewhereIsLeftAlone() throws {
        let layout = try Layout()
        let pointed = layout.root.appendingPathComponent("pointed", isDirectory: true)
        try layout.files.createDirectory(at: pointed, withIntermediateDirectories: true)
        let other = layout.root.appendingPathComponent("other-engine", isDirectory: true)
        try layout.files.createDirectory(at: other, withIntermediateDirectories: true)
        try layout.files.createSymbolicLink(at: other.appendingPathComponent("NativeMessagingHosts"), withDestinationURL: pointed)
        NativeMessagingHosts.link(engineRoot: other, sources: layout.sources, fileManager: layout.files)
        #expect(try layout.files.contentsOfDirectory(atPath: pointed.path).isEmpty)
    }

    @Test func arcsFolderIsSearchedFirstAndChromesIsSearched() {
        let home = URL(fileURLWithPath: "/Users/someone", isDirectory: true)
        let paths = NativeMessagingHosts.sourceDirectories(home: home).map(\.path)
        #expect(paths.first == "/Users/someone/Library/Application Support/Arc/User Data/NativeMessagingHosts")
        #expect(paths.contains("/Users/someone/Library/Application Support/Google/Chrome/NativeMessagingHosts"))
    }
}
