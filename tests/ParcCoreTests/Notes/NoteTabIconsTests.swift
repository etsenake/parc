import Combine
import Foundation
import Testing
@testable import ParcCore

extension NoteProcessWide {
@MainActor final class NoteTabIconsTests {
    init() {
        NoteFileSession.clock = clock
        NoteFileSession.worker = .inline
        NoteLibrary.clock = clock
        NoteLibrary.worker = .inline
        NoteTabIcons.clock = clock
        NoteTabIcons.worker = .inline
        folder = NoteFileTestSupport.makeFolder("tab-icons")
    }

    deinit {
        NoteFileTestSupport.remove(folder)
    }

    let clock = NoteManualClock()

    var folder: URL!

    var folderSignals: [String: PassthroughSubject<Void, Never>] = [:]

    func note(_ name: String, _ text: String) -> URL {
        NoteFileTestSupport.write(text, to: folder.appendingPathComponent(name))
    }

    func iconNote(_ icon: String) -> String { "---\nicon: \"\(icon)\"\n---\nBody text\n" }

    func freshIcons() -> NoteTabIcons {
        let icons = NoteTabIcons.shared
        icons.forget()
        folderSignals = [:]
        icons.folderChanges = { [self] note in
            let key = (NoteTabIcons.key(note) as NSString).deletingLastPathComponent
            let signal = self.folderSignals[key] ?? PassthroughSubject<Void, Never>()
            self.folderSignals[key] = signal
            return signal.eraseToAnyPublisher()
        }
        icons.readIcon = { NoteTabIcons.frontMatterIcon($0) }
        return icons
    }

    func signalFolder(of url: URL) {
        folderSignals[(NoteTabIcons.key(url) as NSString).deletingLastPathComponent]?.send()
    }

    @Test func aPlainEmojiIsAnIcon() {
        let base = URL(fileURLWithPath: "/Users/me/Notes/Plan.md")
        let resolve: (String) -> URL? = { value in
            value.hasPrefix("https://") ? URL(string: value) : base.deletingLastPathComponent().appendingPathComponent(value)
        }
        #expect(NoteTabIcon("🚀", resolve: resolve) == .emoji("🚀"), "a plain emoji is an icon")
        #expect(NoteTabIcon("  🌱 \n", resolve: resolve) == .emoji("🌱"), "whitespace around the emoji is fine")
        #expect(NoteTabIcon("❤️", resolve: resolve) == .emoji("❤️"), "text-default emoji with the emoji selector count")
        #expect(NoteTabIcon("👩🏽‍🚀", resolve: resolve) == .emoji("👩🏽‍🚀"), "skin tones and joins stay one icon")
        #expect(NoteTabIcon("🇨🇦", resolve: resolve) == .emoji("🇨🇦"), "flags are icons")
        #expect(NoteTabIcon("1️⃣", resolve: resolve) == .emoji("1️⃣"), "keycaps are icons")
        #expect(NoteTabIcon("1", resolve: resolve) == nil, "a bare digit isn't an emoji")
        #expect(NoteTabIcon("©", resolve: resolve) == nil, "a text-style symbol isn't an emoji")
        #expect(NoteTabIcon("🚀🚀", resolve: resolve) == nil, "two emoji don't fit one tab")
        #expect(NoteTabIcon("rocket", resolve: resolve) == nil, "words fall back to the symbol")
        #expect(NoteTabIcon("", resolve: resolve) == nil, "empty icons fall back to the symbol")
        #expect(NoteTabIcon(nil, resolve: resolve) == nil, "missing icons fall back to the symbol")
        #expect(NoteTabIcon("Attachments/cover.png", resolve: resolve) == .image(URL(fileURLWithPath: "/Users/me/Notes/Attachments/cover.png")), "relative images resolve beside the note")
        #expect(NoteTabIcon("https://example.org/icon.png", resolve: resolve) == nil, "web images never load from the sidebar")
        #expect(NoteTabIcon("Attachments/notes.pdf", resolve: resolve) == nil, "non-image files fall back to the symbol")
        #expect(NoteTabIcons.touches(nil, note: base), "an unscoped change touches every note")
        #expect(NoteTabIcons.touches([base.path], note: URL(string: "file:///Users/me/Notes/./Plan.md")!), "scoped changes match by path")
        #expect(!NoteTabIcons.touches(["/Users/me/Notes/Other.md"], note: base), "other notes are left alone")
    }

    @Test func readingFrontMatter() {
        #expect(NoteTabIcons.frontMatterIcon(note("Rocket.md", iconNote("🚀"))) == "🚀", "front matter icons are read")
        #expect(NoteTabIcons.frontMatterIcon(note("Bare.md", "---\nicon: 🌵\nfont: serif\n---\n# Hi\n")) == "🌵", "unquoted icons are read")
        #expect(NoteTabIcons.frontMatterIcon(note("None.md", "# Just a heading\n")) == nil, "no front matter means no icon")
        #expect(NoteTabIcons.frontMatterIcon(note("Open.md", "---\nicon: 🚀\nstill going\n")) == nil, "unclosed front matter is ignored")
        #expect(NoteTabIcons.frontMatterIcon(note("Plain.txt", iconNote("🚀"))) == nil, "text files never have icons")
        #expect(NoteTabIcons.frontMatterIcon(folder.appendingPathComponent("Missing.md")) == nil, "missing files have no icon")
    }

    @Test func cachingAndInvalidation() throws {
        let icons = freshIcons()
        var heard: [Set<String>?] = []
        let watch = icons.changes.sink { heard.append($0) }
        defer { watch.cancel() }
        let rocket = note("Launch.md", iconNote("🚀"))
        #expect(icons.lookup(rocket) == .known(.emoji("🚀")), "the first lookup reads the file")
        clock.advance(0)
        #expect(heard.count == 1, "the first read is announced")
        #expect(heard.last.map { NoteTabIcons.touches($0, note: rocket) } ?? false, "the announcement names the note")
        let reads = ReadCounter()
        icons.readIcon = { reads.bump(); return NoteTabIcons.frontMatterIcon($0) }
        #expect(icons.lookup(rocket) == .known(.emoji("🚀")), "later lookups come from the cache")
        #expect(reads.count == 0, "cached lookups don't touch the disk")
        _ = note("Launch.md", iconNote("🌱"))
        #expect(icons.lookup(rocket) == .known(.emoji("🚀")), "the cache holds until the folder changes")
        signalFolder(of: rocket)
        #expect(reads.count == 1, "a folder change rereads the notes it holds")
        #expect(icons.lookup(rocket) == .known(.emoji("🌱")), "the new icon shows after a folder change")
        clock.advance(0)
        #expect(heard.count == 2, "a changed icon is announced")
        signalFolder(of: rocket)
        clock.advance(0)
        #expect(reads.count == 2, "every folder change rereads")
        #expect(heard.count == 2, "an unchanged icon stays quiet")
        _ = note("Launch.md", "# No icon now\n")
        signalFolder(of: rocket)
        #expect(icons.lookup(rocket) == .known(nil), "a removed icon falls back to the symbol")
        try FileManager.default.removeItem(at: rocket)
        signalFolder(of: rocket)
        #expect(icons.lookup(rocket) == .known(nil), "a deleted note shows the symbol")
        let plain = note("Words.txt", iconNote("🚀"))
        #expect(icons.lookup(plain) == .known(nil), "text notes always use the symbol")
        let nested = note("Deeper/Inner.md", iconNote("🐙"))
        #expect(icons.lookup(nested) == .known(.emoji("🐙")), "notes in other folders read too")
        _ = note("Deeper/Inner.md", iconNote("🦑"))
        signalFolder(of: rocket)
        #expect(icons.lookup(nested) == .known(.emoji("🐙")), "a change in another folder leaves this one cached")
        signalFolder(of: nested)
        #expect(icons.lookup(nested) == .known(.emoji("🦑")), "its own folder's change rereads it")
        let image = note("Pictured.md", iconNote("Attachments/face.png"))
        #expect(icons.lookup(image) == .known(.image(NoteFilePaths.canonical(folder).appendingPathComponent("Attachments/face.png"))), "image icons resolve beside their note")
    }

    @Test func coalescedAnnouncements() throws {
        let icons = freshIcons()
        var heard: [Set<String>?] = []
        let watch = icons.changes.sink { heard.append($0) }
        defer { watch.cancel() }
        let first = note("One.md", iconNote("🍎")), second = note("Two.md", iconNote("🍐"))
        _ = icons.lookup(first)
        _ = icons.lookup(second)
        #expect(heard.count == 0, "announcements wait for the next turn")
        clock.advance(0)
        #expect(heard.count == 1, "reads in one turn share one announcement")
        #expect(heard.last ?? nil == [NoteTabIcons.key(first), NoteTabIcons.key(second)], "and name every note")
    }

    @Test func followingASessionReadsItsLiveSettings() throws {
        let icons = freshIcons()
        var heard: [Set<String>?] = []
        let watch = icons.changes.sink { heard.append($0) }
        defer { watch.cancel() }
        let url = note("Live.md", iconNote("🔥"))
        let session = try NoteFileSession.open(url)
        session.retain()
        defer { session.release() }
        #expect(icons.follow(session) == .emoji("🔥"), "following a session reads its live settings")
        let reads = ReadCounter()
        icons.readIcon = { reads.bump(); return NoteTabIcons.frontMatterIcon($0) }
        #expect(icons.lookup(url) == .known(.emoji("🔥")), "open notes answer from their session")
        #expect(reads.count == 0, "without touching the disk")
        clock.advance(0)
        heard.removeAll()
        session.page.edit("Change Icon", kind: .settings) { $0.settings.icon = "💧" }
        #expect(icons.lookup(url) == .known(.emoji("💧")), "icon edits show right away")
        clock.advance(0)
        #expect(heard.count == 1, "icon edits are announced")
        #expect(heard.last.map { NoteTabIcons.touches($0, note: url) } ?? false, "for the edited note")
        heard.removeAll()
        let id = session.page.page.blocks[0].id
        session.page.edit("Typing", kind: .text) { $0.update(id) { $0.text = NoteText("Still typing") } }
        clock.advance(0)
        #expect(heard.count == 0, "typing never announces an icon change")
        session.page.undo()
        session.page.undo()
        #expect(icons.lookup(url) == .known(.emoji("🔥")), "undo brings the old icon back")
        clock.advance(0)
        #expect(heard.count == 1, "and announces it")
        let renamed = try session.rename(to: "Renamed")
        #expect(icons.lookup(renamed) == .known(.emoji("🔥")), "a renamed note keeps its icon")
        session.page.edit("Remove Icon", kind: .settings) { $0.settings.icon = nil }
        #expect(icons.lookup(renamed) == .known(nil), "removing the icon brings back the symbol")
        #expect(reads.count == 0, "live notes never reread the disk")
        try session.flush()
        let plain = try NoteFileSession.open(note("Live.txt", "plain words\n"))
        #expect(icons.follow(plain) == nil, "text sessions never show an icon")
    }

    final class Heard {
        var announcements: [Set<String>?] = []
    }

    func deferredIcons() -> (NoteTabIcons, NoteFileDeferredJobs, Heard, AnyCancellable) {
        let icons = freshIcons()
        let jobs = NoteFileDeferredJobs()
        NoteTabIcons.worker = NoteFileWorker(deferred: jobs)
        let heard = Heard()
        let watch = icons.changes.sink { heard.announcements.append($0) }
        return (icons, jobs, heard, watch)
    }

    @Test func aColdLookupWaitsForTheBackgroundRead() {
        let (icons, _, _, watch) = deferredIcons()
        defer { watch.cancel() }
        let url = note("Slow.md", iconNote("🐢"))
        #expect(icons.lookup(url) == .pending)
    }

    @Test func aColdLookupDoesNotStartASecondRead() {
        let (icons, jobs, _, watch) = deferredIcons()
        defer { watch.cancel() }
        let url = note("Slow.md", iconNote("🐢"))
        let reads = ReadCounter()
        icons.readIcon = { reads.bump(); return NoteTabIcons.frontMatterIcon($0) }
        _ = icons.lookup(url)
        _ = icons.lookup(url)
        jobs.runAll()
        #expect(reads.count == 1)
    }

    @Test func theBackgroundReadAnnouncesItselfAndThenTheIconIsKnown() {
        let (icons, jobs, heard, watch) = deferredIcons()
        defer { watch.cancel() }
        let url = note("Slow.md", iconNote("🐢"))
        _ = icons.lookup(url)
        jobs.runAll()
        clock.advance(0.01)
        #expect(!heard.announcements.isEmpty)
        #expect(icons.lookup(url) == .known(.emoji("🐢")))
    }

    func rereadAfterTwoFolderChanges() -> (NoteTabIcons, Heard, URL, AnyCancellable) {
        let (icons, jobs, heard, watch) = deferredIcons()
        let url = note("Slow.md", iconNote("🐢"))
        _ = icons.lookup(url)
        jobs.runAll()
        clock.advance(0.01)
        _ = note("Slow.md", iconNote("🐇"))
        signalFolder(of: url)
        signalFolder(of: url)
        jobs.runAll()
        clock.advance(0.01)
        return (icons, heard, url, watch)
    }

    @Test func rereadsLandInTheBackgroundWithTheNewIcon() {
        let (icons, heard, url, watch) = rereadAfterTwoFolderChanges()
        defer { watch.cancel() }
        #expect(heard.announcements.count >= 2)
        #expect(icons.lookup(url) == .known(.emoji("🐇")))
    }

    @Test func twoQuickFolderChangesStillAnnounceOnce() {
        let (_, heard, _, watch) = rereadAfterTwoFolderChanges()
        defer { watch.cancel() }
        #expect(heard.announcements.count == 2)
    }

    @Test func followingReadsTheLiveIcon() throws {
        let icons = freshIcons()
        let url = note("Followed/Open.md", iconNote("🦉"))
        let folderKey = (NoteTabIcons.key(url) as NSString).deletingLastPathComponent
        let session = try NoteFileSession.open(url)
        session.retain()
        #expect(icons.follow(session) == .emoji("🦉"), "following reads the live icon")
        #expect(folderSignals[folderKey] != nil, "following a session watches its folder")
        session.release()
        #expect(NoteFileSession.session(for: url) == nil, "the session closes")
        _ = note("Followed/Open.md", iconNote("🦅"))
        signalFolder(of: url)
        #expect(icons.lookup(url) == .known(.emoji("🦅")), "an outside change after closing is noticed")
        let moving = try NoteFileSession.open(note("Followed/Mover.md", iconNote("🐝")))
        moving.retain()
        icons.follow(moving)
        let renamed = try moving.rename(to: "Moved")
        #expect(icons.lookup(renamed) == .known(.emoji("🐝")), "a renamed session keeps its icon")
        moving.release()
        _ = note("Followed/Moved.md", iconNote("🦋"))
        signalFolder(of: renamed)
        #expect(icons.lookup(renamed) == .known(.emoji("🦋")), "the renamed note's folder stays watched")
        clock.advance(0)
    }

    func staleRead() throws -> (NoteTabIcons, NoteFileSession, URL, Heard, NoteFileDeferredJobs, AnyCancellable) {
        let (icons, jobs, heard, watch) = deferredIcons()
        let url = note("Stale.md", iconNote("🔥"))
        #expect(icons.lookup(url) == .pending)
        let session = try NoteFileSession.open(url)
        session.retain()
        session.page.edit("Change Icon", kind: .settings) { $0.settings.icon = "💧" }
        return (icons, session, url, heard, jobs, watch)
    }

    @Test func theOpenSessionHasANewerIconThanTheStuckColdRead() throws {
        let (icons, session, _, _, _, watch) = try staleRead()
        defer { watch.cancel(); session.release() }
        #expect(icons.follow(session) == .emoji("💧"))
    }

    @Test func theStaleReadStillSettlesWaiters() throws {
        let (icons, session, _, heard, jobs, watch) = try staleRead()
        defer { watch.cancel(); session.release() }
        _ = icons.follow(session)
        jobs.runAll()
        clock.advance(0.01)
        #expect(!heard.announcements.isEmpty)
    }

    @Test func theStaleReadDoesNotBeatTheSession() throws {
        let (icons, session, url, _, jobs, watch) = try staleRead()
        defer { watch.cancel(); session.release() }
        _ = icons.follow(session)
        jobs.runAll()
        clock.advance(0.01)
        #expect(icons.lookup(url) == .known(.emoji("💧")))
    }

    @Test func afterClosingTheSessionsIconIsRememberedNotTheStaleRead() throws {
        let (icons, session, url, _, jobs, watch) = try staleRead()
        defer { watch.cancel() }
        _ = icons.follow(session)
        jobs.runAll()
        clock.advance(0.01)
        try session.flush()
        session.release()
        #expect(NoteFileSession.session(for: url) == nil)
        #expect(icons.lookup(url) == .known(.emoji("💧")))
    }

    final class ReadCounter: @unchecked Sendable {
        private let lock = NSLock()
        private var stored = 0

        var count: Int { lock.withLock { stored } }

        func bump() { lock.withLock { stored += 1 } }
    }
}
}
