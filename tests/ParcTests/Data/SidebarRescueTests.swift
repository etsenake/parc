import Foundation
import Testing
@testable import Parc
@testable import ParcCore

@MainActor
struct SidebarRescueTests {
    nonisolated private static let base = Date(timeIntervalSince1970: 1_794_844_800)
    nonisolated private static let keptAddress = "https://kept-sidebar.test/"

    private final class Clock {
        var now: Date
        init(_ now: Date) { self.now = now }
    }

    private final class Questions {
        var offers: [SidebarRescue.Offer] = []
        var answer: Bool?
        init(answer: Bool? = true) { self.answer = answer }
        var ask: (SidebarRescue.Offer) -> Bool? { { [self] offer in offers.append(offer); return answer } }
    }

    @MainActor
    private final class Fixture {
        let directory: URL
        let clock = Clock(SidebarRescueTests.base)

        init() throws {
            directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("parc-session-backups-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
                                                    attributes: [.posixPermissions: 0o700])
        }

        deinit {
            try? FileManager.default.removeItem(at: directory)
        }

        var session: URL { directory.appendingPathComponent("session.json") }

        func backingStore() throws -> BrowserStore {
            try BrowserStore(directory: directory, now: { [clock] in clock.now }, keepsBackups: true)
        }

        func saveKeptSidebar() throws {
            let store = try backingStore()
            _ = store.openResolvedURL(URL(string: SidebarRescueTests.keptAddress)!)
            try store.save()
        }

        func open(keepsBackups: Bool = true, interactive: Bool = true, at location: URL? = nil,
                  ask: @escaping (SidebarRescue.Offer) -> Bool?) throws -> BrowserStore? {
            try SidebarRescue.openStore(at: location ?? directory, keepsBackups: keepsBackups, interactive: interactive,
                                        now: { [clock] in clock.now }, ask: ask)
        }

        func hasKeptSidebar(_ store: BrowserStore?) -> Bool {
            store?.state.tabs.contains { $0.url == SidebarRescueTests.keptAddress } == true
        }
    }

    @Test func aMissingFileWithAGoodBackupAsksOnceOfferingTheNewestCopy() throws {
        let fixture = try Fixture()
        try fixture.saveKeptSidebar()
        try FileManager.default.removeItem(at: fixture.session)
        fixture.clock.now = Self.base.addingTimeInterval(7_200)
        let questions = Questions()
        _ = try fixture.open(ask: questions.ask)
        #expect(questions.offers == [.init(trouble: .missing, date: Self.base, skippedNewer: false, now: fixture.clock.now)])
    }

    @Test func restoreBackupBringsTheSidebarBack() throws {
        let fixture = try Fixture()
        try fixture.saveKeptSidebar()
        try FileManager.default.removeItem(at: fixture.session)
        let restored = try fixture.open(ask: Questions().ask)
        #expect(fixture.hasKeptSidebar(restored))
    }

    @Test func withNoFileThereIsNothingToSetAside() throws {
        let fixture = try Fixture()
        try fixture.saveKeptSidebar()
        try FileManager.default.removeItem(at: fixture.session)
        _ = try fixture.open(ask: Questions().ask)
        let names = try FileManager.default.contentsOfDirectory(atPath: fixture.directory.path)
        #expect(!names.contains { $0.hasPrefix("session-unreadable-") })
    }

    @Test func restoringKeepsEveryBackup() throws {
        let fixture = try Fixture()
        try fixture.saveKeptSidebar()
        try FileManager.default.removeItem(at: fixture.session)
        let before = SessionBackups.list(in: fixture.directory)
        let restored = try fixture.open(ask: Questions().ask)
        try restored?.save()
        #expect(Set(before.map(\.url)).isSubset(of: SessionBackups.list(in: fixture.directory).map(\.url)))
    }

    @Test(arguments: [false, nil] as [Bool?])
    func startEmptyOrAnUnshowableAlertOpensAnEmptySidebarInsteadOfQuitting(answer: Bool?) throws {
        let fixture = try Fixture()
        try fixture.saveKeptSidebar()
        try FileManager.default.removeItem(at: fixture.session)
        let questions = Questions(answer: answer)
        let empty = try fixture.open(ask: questions.ask)
        #expect(questions.offers.count == 1)
        #expect(empty != nil)
        #expect(!fixture.hasKeptSidebar(empty))
    }

    @Test(arguments: [false, nil] as [Bool?])
    func startingEmptyWritesNothingYetAndLeavesTheBackupsAlone(answer: Bool?) throws {
        let fixture = try Fixture()
        try fixture.saveKeptSidebar()
        try FileManager.default.removeItem(at: fixture.session)
        let kept = SessionBackups.list(in: fixture.directory)
        _ = try fixture.open(ask: Questions(answer: answer).ask)
        #expect(!FileManager.default.fileExists(atPath: fixture.session.path))
        #expect(SessionBackups.list(in: fixture.directory) == kept)
    }

    @Test func aFreshInstallStartsWithoutAnAlert() throws {
        let fixture = try Fixture()
        let questions = Questions()
        let fresh = try fixture.open(ask: questions.ask)
        #expect(fresh != nil)
        #expect(questions.offers.isEmpty)
    }

    @Test func aFreshInstallStartsWithTheUsualNewSidebar() throws {
        let fixture = try Fixture()
        let fresh = try fixture.open(ask: Questions().ask)
        #expect(fresh?.state.tabs == BrowserState.initial().tabs)
        #expect(fresh?.state.spaces.count == BrowserState.initial().spaces.count)
    }

    @Test func openingAFreshInstallCreatesNoBackupFolder() throws {
        let fixture = try Fixture()
        _ = try fixture.open(ask: Questions().ask)
        #expect(!FileManager.default.fileExists(atPath: SessionBackups.folder(in: fixture.directory).path))
    }

    @Test func aFolderThatDoesNotExistYetStartsWithoutAnAlert() throws {
        let fixture = try Fixture()
        let questions = Questions()
        _ = try fixture.open(at: fixture.directory.appendingPathComponent("Fresh Profile", isDirectory: true),
                             ask: questions.ask)
        #expect(questions.offers.isEmpty)
    }

    @Test func aSidebarThatLoadsNeverAsksEvenWithBackups() throws {
        let fixture = try Fixture()
        try fixture.saveKeptSidebar()
        let questions = Questions()
        _ = try fixture.open(ask: questions.ask)
        #expect(questions.offers.isEmpty)
    }

    @Test func aDisposableProfileThatKeepsNoBackupsStartsEmptyWithoutAsking() throws {
        let fixture = try Fixture()
        try fixture.saveKeptSidebar()
        try FileManager.default.removeItem(at: fixture.session)
        let questions = Questions()
        let opened = try fixture.open(keepsBackups: false, ask: questions.ask)
        #expect(opened != nil)
        #expect(questions.offers.isEmpty)
    }

    @Test func aSmokeRunReportsNothingAndStartsEmpty() throws {
        let fixture = try Fixture()
        try fixture.saveKeptSidebar()
        try FileManager.default.removeItem(at: fixture.session)
        let questions = Questions()
        let opened = try fixture.open(interactive: false, ask: questions.ask)
        #expect(opened != nil)
        #expect(questions.offers.isEmpty)
    }

    @Test func backupsThatCannotBeReadAreNotOfferedForAMissingFile() throws {
        let fixture = try Fixture()
        try fixture.saveKeptSidebar()
        try FileManager.default.removeItem(at: fixture.session)
        for backup in SessionBackups.list(in: fixture.directory) { try Data("{}".utf8).write(to: backup.url) }
        let questions = Questions()
        let opened = try fixture.open(ask: questions.ask)
        #expect(opened != nil)
        #expect(questions.offers.isEmpty)
    }

    @Test func aDamagedFileStillOffersTheRescueAndQuitQuits() throws {
        let fixture = try Fixture()
        try fixture.saveKeptSidebar()
        try Data("{".utf8).write(to: fixture.session)
        let questions = Questions(answer: false)
        let quit = try fixture.open(ask: questions.ask)
        #expect(quit == nil)
        #expect(questions.offers.map(\.trouble) == [.unreadable])
    }

    @Test func quittingOverADamagedFileChangesNothing() throws {
        let fixture = try Fixture()
        try fixture.saveKeptSidebar()
        let damaged = Data("{".utf8)
        try damaged.write(to: fixture.session)
        _ = try fixture.open(ask: Questions(answer: false).ask)
        #expect(try Data(contentsOf: fixture.session) == damaged)
    }

    nonisolated private static let hoursAgo = base.addingTimeInterval(-7_200)

    private static func wording(_ trouble: SidebarRescue.Trouble, date: Date = hoursAgo,
                                skippedNewer: Bool = false) -> SidebarRescue.Wording {
        SidebarRescue.wording(for: .init(trouble: trouble, date: date, skippedNewer: skippedNewer, now: base))
    }

    @Test func aMissingFileHasItsOwnTitleAndOffersAnEmptySidebarInsteadOfQuitting() {
        let wording = Self.wording(.missing)
        #expect(wording.title == "Parc couldn’t find your saved sidebar")
        #expect(wording.alternative == "Start Empty")
    }

    @Test(arguments: ["damaged", "couldn’t be read", "unreadable"])
    func aMissingFileIsNotCalledDamagedOrUnreadable(word: String) {
        #expect(Self.wording(.missing).message.contains("is missing"))
        #expect(!Self.wording(.missing).message.contains(word))
    }

    @Test func theMessageSaysHowOldTheBackupIs() throws {
        let age = try #require(SidebarRescue.backupAge(Self.hoursAgo, now: Self.base))
        #expect(Self.wording(.missing).message.contains("is from \(age)."))
    }

    @Test func skippedCopiesAreMentionedWithoutBlamingTheMissingFile() {
        let message = Self.wording(.missing, skippedNewer: true).message
        #expect(message.contains("Newer backups couldn’t be read, so the most recent one that works is from"))
    }

    @Test func aSkippedCopiesMessageWithAFutureStampStillReadsAsOneSentence() {
        let message = Self.wording(.missing, date: Self.base.addingTimeInterval(86_400), skippedNewer: true).message
        #expect(message.contains("the most recent one that works is dated after your Mac’s current time; its age isn’t known."))
    }

    @Test func aDamagedFileKeepsItsWordingAndItsQuitButton() {
        let wording = Self.wording(.unreadable, skippedNewer: true)
        #expect(wording.title == "Parc couldn’t read your saved sidebar")
        #expect(wording.alternative == "Quit")
        #expect(wording.message.contains("damaged"))
        #expect(wording.message.contains("couldn’t be read either"))
    }

    @Test func aCopyStampedInTheFutureSaysItsAgeIsUnknown() {
        let ahead = Self.base.addingTimeInterval(365 * 86_400)
        #expect(SidebarRescue.backupAge(ahead, now: Self.base) == nil)
        #expect(Self.wording(.unreadable, date: ahead).message
            .contains("The most recent backup is dated after your Mac’s current time; its age isn’t known."))
    }

    @Test func aFutureDateIsNeverPresentedAsHowOldTheCopyIs() {
        let message = Self.wording(.unreadable, date: Self.base.addingTimeInterval(365 * 86_400)).message
        #expect(!message.contains("2027"))
        #expect(!message.contains("from"))
    }

    @Test(arguments: [30.0, -30.0])
    func secondsOfClockDriftEitherWayReadAsAMomentAgo(drift: Double) {
        #expect(SidebarRescue.backupAge(Self.base.addingTimeInterval(drift), now: Self.base) == "a moment ago")
    }
}
