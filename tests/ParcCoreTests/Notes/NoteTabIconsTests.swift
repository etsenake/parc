import Combine
import Foundation
import Testing
@testable import ParcCore

struct NoteTabIconParsingTests {
    static let base = URL(fileURLWithPath: "/Users/me/Notes/Plan.md")

    func icon(_ raw: String?) -> NoteTabIcon? {
        NoteTabIcon(raw) { value in
            value.hasPrefix("https://") ? URL(string: value) : Self.base.deletingLastPathComponent().appendingPathComponent(value)
        }
    }

    @Test(arguments: [("🚀", "🚀"), ("  🌱 \n", "🌱"), ("❤️", "❤️"), ("👩🏽‍🚀", "👩🏽‍🚀"), ("🇨🇦", "🇨🇦"), ("1️⃣", "1️⃣")])
    func aSingleEmojiIsAnIcon(raw: String, expected: String) {
        #expect(icon(raw) == .emoji(expected))
    }

    @Test(arguments: ["1", "©", "🚀🚀", "rocket", "", "https://example.org/icon.png", "Attachments/notes.pdf"])
    func anythingElseFallsBackToTheSymbol(raw: String) {
        #expect(icon(raw) == nil)
    }

    @Test func aMissingIconFallsBackToTheSymbol() {
        #expect(icon(nil) == nil)
    }

    @Test func relativeImagesResolveBesideTheNote() {
        #expect(icon("Attachments/cover.png") == .image(URL(fileURLWithPath: "/Users/me/Notes/Attachments/cover.png")))
    }

    @Test func anUnscopedChangeTouchesEveryNote() {
        #expect(NoteTabIcons.touches(nil, note: Self.base))
    }

    @Test func scopedChangesMatchByPath() {
        #expect(NoteTabIcons.touches([Self.base.path], note: URL(string: "file:///Users/me/Notes/./Plan.md")!))
        #expect(!NoteTabIcons.touches(["/Users/me/Notes/Other.md"], note: Self.base))
    }
}

final class NoteFrontMatterIconTests {
    let folder = NoteFileTestSupport.makeFolder("front-matter")

    deinit {
        NoteFileTestSupport.remove(folder)
    }

    @Test(arguments: [
        ("Rocket.md", "---\nicon: \"🚀\"\n---\nBody text\n", "🚀"),
        ("Bare.md", "---\nicon: 🌵\nfont: serif\n---\n# Hi\n", "🌵"),
        ("None.md", "# Just a heading\n", nil),
        ("Open.md", "---\nicon: 🚀\nstill going\n", nil),
        ("Plain.txt", "---\nicon: \"🚀\"\n---\nBody text\n", nil),
    ] as [(String, String, String?)])
    func frontMatterIconsAreReadFromMarkdownOnly(name: String, text: String, expected: String?) {
        #expect(NoteTabIcons.frontMatterIcon(NoteFileTestSupport.write(text, to: folder.appendingPathComponent(name))) == expected)
    }

    @Test func missingFilesHaveNoIcon() {
        #expect(NoteTabIcons.frontMatterIcon(folder.appendingPathComponent("Missing.md")) == nil)
    }
}

@MainActor final class NoteTabIconsTests {
    let clock = NoteManualClock()
    let folder = NoteFileTestSupport.makeFolder("tab-icons")
    lazy var files = NoteFileTestSupport.files(clock: clock)
    let jobs = NoteFileDeferredJobs()
    var folderSignals: [String: PassthroughSubject<Void, Never>] = [:]
    var heard: [Set<String>?] = []
    var subscriptions: [AnyCancellable] = []

    deinit {
        NoteFileTestSupport.remove(folder)
    }

    final class ReadCounter: @unchecked Sendable {
        private let lock = NSLock()
        private var stored = 0

        var count: Int { lock.withLock { stored } }

        func bump() { lock.withLock { stored += 1 } }
    }

    func note(_ name: String, _ text: String) -> URL {
        NoteFileTestSupport.write(text, to: folder.appendingPathComponent(name))
    }

    func iconNote(_ icon: String) -> String { "---\nicon: \"\(icon)\"\n---\nBody text\n" }

    func icons(deferred: Bool = false) -> NoteTabIcons {
        let icons = NoteTabIcons(files: files, worker: deferred ? NoteFileWorker(deferred: jobs) : .inline, clock: clock)
        icons.folderChanges = { [unowned self] note in
            let key = (NoteTabIcons.key(note) as NSString).deletingLastPathComponent
            let signal = self.folderSignals[key] ?? PassthroughSubject<Void, Never>()
            self.folderSignals[key] = signal
            return signal.eraseToAnyPublisher()
        }
        subscriptions.append(icons.changes.sink { [unowned self] in self.heard.append($0) })
        return icons
    }

    func counting(_ icons: NoteTabIcons) -> ReadCounter {
        let reads = ReadCounter()
        icons.readIcon = { reads.bump(); return NoteTabIcons.frontMatterIcon($0) }
        return reads
    }

    func signalFolder(of url: URL) {
        folderSignals[(NoteTabIcons.key(url) as NSString).deletingLastPathComponent]?.send()
    }

    @Test func theFirstLookupReadsTheFile() {
        #expect(icons().lookup(note("Launch.md", iconNote("🚀"))) == .known(.emoji("🚀")))
    }

    @Test func theFirstReadIsAnnouncedForThatNote() {
        let icons = icons()
        let rocket = note("Launch.md", iconNote("🚀"))
        _ = icons.lookup(rocket)
        clock.advance(0)
        #expect(heard.count == 1)
        #expect(heard.last.map { NoteTabIcons.touches($0, note: rocket) } ?? false)
    }

    @Test func laterLookupsComeFromTheCacheEvenAfterTheFileChanges() {
        let icons = icons()
        let rocket = note("Launch.md", iconNote("🚀"))
        _ = icons.lookup(rocket)
        let reads = counting(icons)
        _ = note("Launch.md", iconNote("🌱"))
        #expect(icons.lookup(rocket) == .known(.emoji("🚀")))
        #expect(reads.count == 0)
    }

    @Test func aFolderChangeRereadsAndShowsTheNewIcon() {
        let icons = icons()
        let rocket = note("Launch.md", iconNote("🚀"))
        _ = icons.lookup(rocket)
        clock.advance(0)
        let reads = counting(icons)
        _ = note("Launch.md", iconNote("🌱"))
        signalFolder(of: rocket)
        #expect(reads.count == 1)
        #expect(icons.lookup(rocket) == .known(.emoji("🌱")))
        clock.advance(0)
        #expect(heard.count == 2)
    }

    @Test func anUnchangedIconStaysQuietAfterAFolderChange() {
        let icons = icons()
        let rocket = note("Launch.md", iconNote("🚀"))
        _ = icons.lookup(rocket)
        clock.advance(0)
        signalFolder(of: rocket)
        clock.advance(0)
        #expect(heard.count == 1)
    }

    @Test func aRemovedIconFallsBackToTheSymbol() {
        let icons = icons()
        let rocket = note("Launch.md", iconNote("🚀"))
        _ = icons.lookup(rocket)
        _ = note("Launch.md", "# No icon now\n")
        signalFolder(of: rocket)
        #expect(icons.lookup(rocket) == .known(nil))
    }

    @Test func aDeletedNoteShowsTheSymbol() throws {
        let icons = icons()
        let rocket = note("Launch.md", iconNote("🚀"))
        _ = icons.lookup(rocket)
        try FileManager.default.removeItem(at: rocket)
        signalFolder(of: rocket)
        #expect(icons.lookup(rocket) == .known(nil))
    }

    @Test func textNotesAlwaysUseTheSymbol() {
        #expect(icons().lookup(note("Words.txt", iconNote("🚀"))) == .known(nil))
    }

    @Test func aChangeInAnotherFolderLeavesThisOneCached() {
        let icons = icons()
        let rocket = note("Launch.md", iconNote("🚀"))
        let nested = note("Deeper/Inner.md", iconNote("🐙"))
        _ = icons.lookup(rocket)
        _ = icons.lookup(nested)
        _ = note("Deeper/Inner.md", iconNote("🦑"))
        signalFolder(of: rocket)
        #expect(icons.lookup(nested) == .known(.emoji("🐙")))
        signalFolder(of: nested)
        #expect(icons.lookup(nested) == .known(.emoji("🦑")))
    }

    @Test func imageIconsResolveBesideTheirNote() {
        let image = note("Pictured.md", iconNote("Attachments/face.png"))
        #expect(icons().lookup(image) == .known(.image(folder.appendingPathComponent("Attachments/face.png"))))
    }

    @Test func readsInOneTurnShareOneAnnouncementNamingEveryNote() {
        let icons = icons()
        let first = note("One.md", iconNote("🍎")), second = note("Two.md", iconNote("🍐"))
        _ = icons.lookup(first)
        _ = icons.lookup(second)
        #expect(heard.isEmpty)
        clock.advance(0)
        #expect(heard.count == 1)
        #expect(heard.last ?? nil == [NoteTabIcons.key(first), NoteTabIcons.key(second)])
    }

    func live(_ icons: NoteTabIcons) throws -> (URL, NoteFileSession) {
        let url = note("Live.md", iconNote("🔥"))
        let session = try files.open(url)
        session.retain()
        return (url, session)
    }

    @Test func followingASessionReadsItsLiveSettings() throws {
        let icons = icons()
        let (_, session) = try live(icons)
        defer { session.release() }
        #expect(icons.follow(session) == .emoji("🔥"))
    }

    @Test func openNotesAnswerFromTheirSessionWithoutTouchingTheDisk() throws {
        let icons = icons()
        let (url, session) = try live(icons)
        defer { session.release() }
        icons.follow(session)
        let reads = counting(icons)
        #expect(icons.lookup(url) == .known(.emoji("🔥")))
        #expect(reads.count == 0)
    }

    @Test func iconEditsShowAndAreAnnouncedRightAway() throws {
        let icons = icons()
        let (url, session) = try live(icons)
        defer { session.release() }
        icons.follow(session)
        clock.advance(0)
        heard.removeAll()
        session.page.edit("Change Icon", kind: .settings) { $0.settings.icon = "💧" }
        #expect(icons.lookup(url) == .known(.emoji("💧")))
        clock.advance(0)
        #expect(heard.count == 1)
        #expect(heard.last.map { NoteTabIcons.touches($0, note: url) } ?? false)
    }

    @Test func typingNeverAnnouncesAnIconChange() throws {
        let icons = icons()
        let (_, session) = try live(icons)
        defer { session.release() }
        icons.follow(session)
        clock.advance(0)
        heard.removeAll()
        let id = session.page.page.blocks[0].id
        session.page.edit("Typing", kind: .text) { $0.update(id) { $0.text = NoteText("Still typing") } }
        clock.advance(0)
        #expect(heard.isEmpty)
    }

    @Test func undoBringsTheOldIconBackAndAnnouncesIt() throws {
        let icons = icons()
        let (url, session) = try live(icons)
        defer { session.release() }
        icons.follow(session)
        session.page.edit("Change Icon", kind: .settings) { $0.settings.icon = "💧" }
        clock.advance(0)
        heard.removeAll()
        session.page.undo()
        #expect(icons.lookup(url) == .known(.emoji("🔥")))
        clock.advance(0)
        #expect(heard.count == 1)
    }

    @Test func aRenamedLiveNoteKeepsItsIcon() throws {
        let icons = icons()
        let (_, session) = try live(icons)
        defer { session.release() }
        icons.follow(session)
        #expect(icons.lookup(try session.rename(to: "Renamed")) == .known(.emoji("🔥")))
    }

    @Test func removingALiveIconBringsBackTheSymbol() throws {
        let icons = icons()
        let (url, session) = try live(icons)
        defer { session.release() }
        icons.follow(session)
        session.page.edit("Remove Icon", kind: .settings) { $0.settings.icon = nil }
        #expect(icons.lookup(url) == .known(nil))
    }

    @Test func textSessionsNeverShowAnIcon() throws {
        #expect(icons().follow(try files.open(note("Live.txt", "plain words\n"))) == nil)
    }

    @Test func aColdLookupWaitsForTheBackgroundRead() {
        #expect(icons(deferred: true).lookup(note("Slow.md", iconNote("🐢"))) == .pending)
    }

    @Test func aColdLookupDoesNotStartASecondRead() {
        let icons = icons(deferred: true)
        let url = note("Slow.md", iconNote("🐢"))
        let reads = counting(icons)
        _ = icons.lookup(url)
        _ = icons.lookup(url)
        jobs.runAll()
        #expect(reads.count == 1)
    }

    @Test func theBackgroundReadAnnouncesItselfAndThenTheIconIsKnown() {
        let icons = icons(deferred: true)
        let url = note("Slow.md", iconNote("🐢"))
        _ = icons.lookup(url)
        jobs.runAll()
        clock.advance(0)
        #expect(!heard.isEmpty)
        #expect(icons.lookup(url) == .known(.emoji("🐢")))
    }

    func rereadAfterTwoFolderChanges() -> (NoteTabIcons, URL) {
        let icons = icons(deferred: true)
        let url = note("Slow.md", iconNote("🐢"))
        _ = icons.lookup(url)
        jobs.runAll()
        clock.advance(0)
        _ = note("Slow.md", iconNote("🐇"))
        signalFolder(of: url)
        signalFolder(of: url)
        jobs.runAll()
        clock.advance(0)
        return (icons, url)
    }

    @Test func rereadsLandInTheBackgroundWithTheNewIcon() {
        let (icons, url) = rereadAfterTwoFolderChanges()
        #expect(icons.lookup(url) == .known(.emoji("🐇")))
    }

    @Test func twoQuickFolderChangesStillAnnounceOnce() {
        _ = rereadAfterTwoFolderChanges()
        #expect(heard.count == 2)
    }

    @Test func followingASessionWatchesItsFolder() throws {
        let icons = icons()
        let url = note("Followed/Open.md", iconNote("🦉"))
        let session = try files.open(url)
        icons.follow(session)
        #expect(folderSignals[(NoteTabIcons.key(url) as NSString).deletingLastPathComponent] != nil)
    }

    @Test func anOutsideChangeAfterTheSessionClosesIsNoticed() throws {
        let icons = icons()
        let url = note("Followed/Open.md", iconNote("🦉"))
        let session = try files.open(url)
        session.retain()
        icons.follow(session)
        session.release()
        _ = note("Followed/Open.md", iconNote("🦅"))
        signalFolder(of: url)
        #expect(icons.lookup(url) == .known(.emoji("🦅")))
    }

    @Test func aRenamedNotesFolderStaysWatchedAfterItCloses() throws {
        let icons = icons()
        let moving = try files.open(note("Followed/Mover.md", iconNote("🐝")))
        moving.retain()
        icons.follow(moving)
        let renamed = try moving.rename(to: "Moved")
        moving.release()
        _ = note("Followed/Moved.md", iconNote("🦋"))
        signalFolder(of: renamed)
        #expect(icons.lookup(renamed) == .known(.emoji("🦋")))
    }

    func staleRead() throws -> (NoteTabIcons, NoteFileSession, URL) {
        let icons = icons(deferred: true)
        let url = note("Stale.md", iconNote("🔥"))
        _ = icons.lookup(url)
        let session = try files.open(url)
        session.retain()
        session.page.edit("Change Icon", kind: .settings) { $0.settings.icon = "💧" }
        return (icons, session, url)
    }

    @Test func theOpenSessionHasANewerIconThanTheStuckColdRead() throws {
        let (icons, session, _) = try staleRead()
        defer { session.release() }
        #expect(icons.follow(session) == .emoji("💧"))
    }

    @Test func theStaleReadStillSettlesWaiters() throws {
        let (icons, session, _) = try staleRead()
        defer { session.release() }
        icons.follow(session)
        jobs.runAll()
        clock.advance(0)
        #expect(!heard.isEmpty)
    }

    @Test func theStaleReadDoesNotBeatTheSession() throws {
        let (icons, session, url) = try staleRead()
        defer { session.release() }
        icons.follow(session)
        jobs.runAll()
        clock.advance(0)
        #expect(icons.lookup(url) == .known(.emoji("💧")))
    }

    @Test func afterClosingTheSessionsIconIsRememberedNotTheStaleRead() throws {
        let (icons, session, url) = try staleRead()
        icons.follow(session)
        jobs.runAll()
        clock.advance(0)
        try session.flush()
        session.release()
        #expect(files.session(for: url) == nil)
        #expect(icons.lookup(url) == .known(.emoji("💧")))
    }
}
