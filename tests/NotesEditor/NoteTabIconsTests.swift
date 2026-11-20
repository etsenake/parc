import Combine
import Foundation

@main @MainActor
struct NoteTabIconsTests {
    static let clock = ManualNoteClock()
    static var folder: URL!
    static var folderSignals: [String: PassthroughSubject<Void, Never>] = [:]

    static func main() {
        exitOnFailure {
            NoteFileSession.clock = clock
            NoteFileSession.worker = .inline
            NoteLibrary.clock = clock
            NoteLibrary.worker = .inline
            NoteTabIcons.clock = clock
            NoteTabIcons.worker = .inline
            folder = NoteFileTestSupport.makeFolder("tab-icons")
            defer { NoteFileTestSupport.remove(folder) }
            parsing()
            readingFrontMatter()
            try cachingAndInvalidation()
            try coalescedAnnouncements()
            try liveSessions()
            try backgroundReads()
            try followedFolders()
            try staleReads()
            print("NoteTabIconsTests passed")
        }
    }

    static func note(_ name: String, _ text: String) -> URL {
        NoteFileTestSupport.write(text, to: folder.appendingPathComponent(name))
    }

    static func iconNote(_ icon: String) -> String { "---\nicon: \"\(icon)\"\n---\nBody text\n" }

    static func freshIcons() -> NoteTabIcons {
        let icons = NoteTabIcons.shared
        icons.forget()
        folderSignals = [:]
        icons.folderChanges = { note in
            let key = (NoteTabIcons.key(note) as NSString).deletingLastPathComponent
            let signal = folderSignals[key] ?? PassthroughSubject<Void, Never>()
            folderSignals[key] = signal
            return signal.eraseToAnyPublisher()
        }
        icons.readIcon = { NoteTabIcons.frontMatterIcon($0) }
        return icons
    }

    static func signalFolder(of url: URL) {
        folderSignals[(NoteTabIcons.key(url) as NSString).deletingLastPathComponent]?.send()
    }

    static func parsing() {
        let base = URL(fileURLWithPath: "/Users/me/Notes/Plan.md")
        let resolve: (String) -> URL? = { value in
            value.hasPrefix("https://") ? URL(string: value) : base.deletingLastPathComponent().appendingPathComponent(value)
        }
        expectEqual(NoteTabIcon("🚀", resolve: resolve), .emoji("🚀"), "a plain emoji is an icon")
        expectEqual(NoteTabIcon("  🌱 \n", resolve: resolve), .emoji("🌱"), "whitespace around the emoji is fine")
        expectEqual(NoteTabIcon("❤️", resolve: resolve), .emoji("❤️"), "text-default emoji with the emoji selector count")
        expectEqual(NoteTabIcon("👩🏽‍🚀", resolve: resolve), .emoji("👩🏽‍🚀"), "skin tones and joins stay one icon")
        expectEqual(NoteTabIcon("🇨🇦", resolve: resolve), .emoji("🇨🇦"), "flags are icons")
        expectEqual(NoteTabIcon("1️⃣", resolve: resolve), .emoji("1️⃣"), "keycaps are icons")
        expectEqual(NoteTabIcon("1", resolve: resolve), nil, "a bare digit isn't an emoji")
        expectEqual(NoteTabIcon("©", resolve: resolve), nil, "a text-style symbol isn't an emoji")
        expectEqual(NoteTabIcon("🚀🚀", resolve: resolve), nil, "two emoji don't fit one tab")
        expectEqual(NoteTabIcon("rocket", resolve: resolve), nil, "words fall back to the symbol")
        expectEqual(NoteTabIcon("", resolve: resolve), nil, "empty icons fall back to the symbol")
        expectEqual(NoteTabIcon(nil, resolve: resolve), nil, "missing icons fall back to the symbol")
        expectEqual(NoteTabIcon("Attachments/cover.png", resolve: resolve),
                    .image(URL(fileURLWithPath: "/Users/me/Notes/Attachments/cover.png")), "relative images resolve beside the note")
        expectEqual(NoteTabIcon("https://example.org/icon.png", resolve: resolve), nil, "web images never load from the sidebar")
        expectEqual(NoteTabIcon("Attachments/notes.pdf", resolve: resolve), nil, "non-image files fall back to the symbol")
        expect(NoteTabIcons.touches(nil, note: base), "an unscoped change touches every note")
        expect(NoteTabIcons.touches([base.path], note: URL(string: "file:///Users/me/Notes/./Plan.md")!), "scoped changes match by path")
        expect(!NoteTabIcons.touches(["/Users/me/Notes/Other.md"], note: base), "other notes are left alone")
    }

    static func readingFrontMatter() {
        expectEqual(NoteTabIcons.frontMatterIcon(note("Rocket.md", iconNote("🚀"))), "🚀", "front matter icons are read")
        expectEqual(NoteTabIcons.frontMatterIcon(note("Bare.md", "---\nicon: 🌵\nfont: serif\n---\n# Hi\n")), "🌵", "unquoted icons are read")
        expectEqual(NoteTabIcons.frontMatterIcon(note("None.md", "# Just a heading\n")), nil, "no front matter means no icon")
        expectEqual(NoteTabIcons.frontMatterIcon(note("Open.md", "---\nicon: 🚀\nstill going\n")), nil, "unclosed front matter is ignored")
        expectEqual(NoteTabIcons.frontMatterIcon(note("Plain.txt", iconNote("🚀"))), nil, "text files never have icons")
        expectEqual(NoteTabIcons.frontMatterIcon(folder.appendingPathComponent("Missing.md")), nil, "missing files have no icon")
    }

    static func cachingAndInvalidation() throws {
        let icons = freshIcons()
        var heard: [Set<String>?] = []
        let watch = icons.changes.sink { heard.append($0) }
        defer { watch.cancel() }
        let rocket = note("Launch.md", iconNote("🚀"))
        expectEqual(icons.lookup(rocket), .known(.emoji("🚀")), "the first lookup reads the file")
        clock.advance(0)
        expectEqual(heard.count, 1, "the first read is announced")
        expect(heard.last.map { NoteTabIcons.touches($0, note: rocket) } ?? false, "the announcement names the note")
        let reads = ReadCounter()
        icons.readIcon = { reads.bump(); return NoteTabIcons.frontMatterIcon($0) }
        expectEqual(icons.lookup(rocket), .known(.emoji("🚀")), "later lookups come from the cache")
        expectEqual(reads.count, 0, "cached lookups don't touch the disk")
        _ = note("Launch.md", iconNote("🌱"))
        expectEqual(icons.lookup(rocket), .known(.emoji("🚀")), "the cache holds until the folder changes")
        signalFolder(of: rocket)
        expectEqual(reads.count, 1, "a folder change rereads the notes it holds")
        expectEqual(icons.lookup(rocket), .known(.emoji("🌱")), "the new icon shows after a folder change")
        clock.advance(0)
        expectEqual(heard.count, 2, "a changed icon is announced")
        signalFolder(of: rocket)
        clock.advance(0)
        expectEqual(reads.count, 2, "every folder change rereads")
        expectEqual(heard.count, 2, "an unchanged icon stays quiet")
        _ = note("Launch.md", "# No icon now\n")
        signalFolder(of: rocket)
        expectEqual(icons.lookup(rocket), .known(nil), "a removed icon falls back to the symbol")
        try FileManager.default.removeItem(at: rocket)
        signalFolder(of: rocket)
        expectEqual(icons.lookup(rocket), .known(nil), "a deleted note shows the symbol")
        let plain = note("Words.txt", iconNote("🚀"))
        expectEqual(icons.lookup(plain), .known(nil), "text notes always use the symbol")
        let nested = note("Deeper/Inner.md", iconNote("🐙"))
        expectEqual(icons.lookup(nested), .known(.emoji("🐙")), "notes in other folders read too")
        _ = note("Deeper/Inner.md", iconNote("🦑"))
        signalFolder(of: rocket)
        expectEqual(icons.lookup(nested), .known(.emoji("🐙")), "a change in another folder leaves this one cached")
        signalFolder(of: nested)
        expectEqual(icons.lookup(nested), .known(.emoji("🦑")), "its own folder's change rereads it")
        let image = note("Pictured.md", iconNote("Attachments/face.png"))
        expectEqual(icons.lookup(image), .known(.image(NoteFilePaths.canonical(folder).appendingPathComponent("Attachments/face.png"))),
                    "image icons resolve beside their note")
    }

    static func coalescedAnnouncements() throws {
        let icons = freshIcons()
        var heard: [Set<String>?] = []
        let watch = icons.changes.sink { heard.append($0) }
        defer { watch.cancel() }
        let first = note("One.md", iconNote("🍎")), second = note("Two.md", iconNote("🍐"))
        _ = icons.lookup(first)
        _ = icons.lookup(second)
        expectEqual(heard.count, 0, "announcements wait for the next turn")
        clock.advance(0)
        expectEqual(heard.count, 1, "reads in one turn share one announcement")
        expectEqual(heard.last ?? nil, [NoteTabIcons.key(first), NoteTabIcons.key(second)], "and name every note")
    }

    static func liveSessions() throws {
        let icons = freshIcons()
        var heard: [Set<String>?] = []
        let watch = icons.changes.sink { heard.append($0) }
        defer { watch.cancel() }
        let url = note("Live.md", iconNote("🔥"))
        let session = try NoteFileSession.open(url)
        session.retain()
        defer { session.release() }
        expectEqual(icons.follow(session), .emoji("🔥"), "following a session reads its live settings")
        let reads = ReadCounter()
        icons.readIcon = { reads.bump(); return NoteTabIcons.frontMatterIcon($0) }
        expectEqual(icons.lookup(url), .known(.emoji("🔥")), "open notes answer from their session")
        expectEqual(reads.count, 0, "without touching the disk")
        clock.advance(0)
        heard.removeAll()
        session.page.edit("Change Icon", kind: .settings) { $0.settings.icon = "💧" }
        expectEqual(icons.lookup(url), .known(.emoji("💧")), "icon edits show right away")
        clock.advance(0)
        expectEqual(heard.count, 1, "icon edits are announced")
        expect(heard.last.map { NoteTabIcons.touches($0, note: url) } ?? false, "for the edited note")
        heard.removeAll()
        let id = session.page.page.blocks[0].id
        session.page.edit("Typing", kind: .text) { $0.update(id) { $0.text = NoteText("Still typing") } }
        clock.advance(0)
        expectEqual(heard.count, 0, "typing never announces an icon change")
        session.page.undo()
        session.page.undo()
        expectEqual(icons.lookup(url), .known(.emoji("🔥")), "undo brings the old icon back")
        clock.advance(0)
        expectEqual(heard.count, 1, "and announces it")
        let renamed = try session.rename(to: "Renamed")
        expectEqual(icons.lookup(renamed), .known(.emoji("🔥")), "a renamed note keeps its icon")
        session.page.edit("Remove Icon", kind: .settings) { $0.settings.icon = nil }
        expectEqual(icons.lookup(renamed), .known(nil), "removing the icon brings back the symbol")
        expectEqual(reads.count, 0, "live notes never reread the disk")
        try session.flush()
        let plain = try NoteFileSession.open(note("Live.txt", "plain words\n"))
        expectEqual(icons.follow(plain), nil, "text sessions never show an icon")
    }

    static func backgroundReads() throws {
        let icons = freshIcons()
        NoteTabIcons.clock = NoteFileSystemClock.shared
        NoteTabIcons.worker = NoteFileWorker(label: "org.parc.tests.tab-icons")
        defer {
            NoteTabIcons.clock = clock
            NoteTabIcons.worker = .inline
        }
        var heard: [Set<String>?] = []
        let watch = icons.changes.sink { heard.append($0) }
        defer { watch.cancel() }
        let url = note("Slow.md", iconNote("🐢"))
        expectEqual(icons.lookup(url), .pending, "a cold lookup waits for the background read")
        expectEqual(icons.lookup(url), .pending, "and doesn't start a second read")
        expect(NoteFileTestSupport.spin(timeout: 5) { !heard.isEmpty }, "the background read announces itself")
        expectEqual(icons.lookup(url), .known(.emoji("🐢")), "then the icon is known")
        _ = note("Slow.md", iconNote("🐇"))
        signalFolder(of: url)
        signalFolder(of: url)
        expect(NoteFileTestSupport.spin(timeout: 5) { heard.count >= 2 }, "rereads land in the background")
        expectEqual(icons.lookup(url), .known(.emoji("🐇")), "with the new icon")
        _ = NoteFileTestSupport.spin(timeout: 0.3) { false }
        expectEqual(heard.count, 2, "two quick folder changes still announce once")
    }
}

extension NoteTabIconsTests {
    static func followedFolders() throws {
        let icons = freshIcons()
        let url = note("Followed/Open.md", iconNote("🦉"))
        let folderKey = (NoteTabIcons.key(url) as NSString).deletingLastPathComponent
        let session = try NoteFileSession.open(url)
        session.retain()
        expectEqual(icons.follow(session), .emoji("🦉"), "following reads the live icon")
        expect(folderSignals[folderKey] != nil, "following a session watches its folder")
        session.release()
        expect(NoteFileSession.session(for: url) == nil, "the session closes")
        _ = note("Followed/Open.md", iconNote("🦅"))
        signalFolder(of: url)
        expectEqual(icons.lookup(url), .known(.emoji("🦅")), "an outside change after closing is noticed")
        let moving = try NoteFileSession.open(note("Followed/Mover.md", iconNote("🐝")))
        moving.retain()
        icons.follow(moving)
        let renamed = try moving.rename(to: "Moved")
        expectEqual(icons.lookup(renamed), .known(.emoji("🐝")), "a renamed session keeps its icon")
        moving.release()
        _ = note("Followed/Moved.md", iconNote("🦋"))
        signalFolder(of: renamed)
        expectEqual(icons.lookup(renamed), .known(.emoji("🦋")), "the renamed note's folder stays watched")
        clock.advance(0)
    }

    static func staleReads() throws {
        let icons = freshIcons()
        let gate = DispatchSemaphore(value: 0)
        NoteTabIcons.clock = NoteFileSystemClock.shared
        NoteTabIcons.worker = NoteFileWorker(label: "org.parc.tests.tab-icons.stale")
        defer {
            NoteTabIcons.clock = clock
            NoteTabIcons.worker = .inline
        }
        var heard: [Set<String>?] = []
        let watch = icons.changes.sink { heard.append($0) }
        defer { watch.cancel() }
        let url = note("Stale.md", iconNote("🔥"))
        icons.readIcon = { note in
            gate.wait()
            return NoteTabIcons.frontMatterIcon(note)
        }
        expectEqual(icons.lookup(url), .pending, "the cold read is stuck in the background")
        let session = try NoteFileSession.open(url)
        session.retain()
        session.page.edit("Change Icon", kind: .settings) { $0.settings.icon = "💧" }
        expectEqual(icons.follow(session), .emoji("💧"), "the open session has a newer icon")
        gate.signal()
        expect(NoteFileTestSupport.spin(timeout: 5) { !heard.isEmpty }, "the stale read still settles waiters")
        expectEqual(icons.lookup(url), .known(.emoji("💧")), "the stale read doesn't beat the session")
        icons.readIcon = { NoteTabIcons.frontMatterIcon($0) }
        try session.flush()
        session.release()
        expect(NoteFileSession.session(for: url) == nil, "the session closes")
        expectEqual(icons.lookup(url), .known(.emoji("💧")), "after closing, the session's icon is remembered, not the stale read")
    }
}

final class ReadCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var stored = 0

    var count: Int { lock.withLock { stored } }

    func bump() { lock.withLock { stored += 1 } }
}
