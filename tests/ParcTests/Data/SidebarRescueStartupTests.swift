import Foundation
import Testing
@testable import Parc
@testable import ParcCore
@testable import ParcSidebar

extension SidebarRescueTestsSupport {
    @MainActor
    struct SidebarRescueStartupTests {
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
            let clock = Clock(SidebarRescueTestsSupport.base)

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
                _ = store.openResolvedURL(URL(string: SidebarRescueStartupTests.keptAddress)!)
                try store.save()
            }

            func open(keepsBackups: Bool = true, interactive: Bool = true, at location: URL? = nil,
                      ask: @escaping (SidebarRescue.Offer) -> Bool?) throws -> BrowserStore? {
                try SidebarRescue.openStore(at: location ?? directory, keepsBackups: keepsBackups, interactive: interactive,
                                            now: { [clock] in clock.now }, ask: ask)
            }

            func hasKeptSidebar(_ store: BrowserStore?) -> Bool {
                store?.state.tabs.contains { $0.url == SidebarRescueStartupTests.keptAddress } == true
            }
        }

        @Test func aMissingFileWithAGoodBackupAsksOnceOfferingTheNewestCopy() throws {
            let fixture = try Fixture()
            try fixture.saveKeptSidebar()
            try FileManager.default.removeItem(at: fixture.session)
            fixture.clock.now = SidebarRescueTestsSupport.base.addingTimeInterval(7_200)
            let questions = Questions()
            _ = try fixture.open(ask: questions.ask)
            #expect(questions.offers == [.init(trouble: .missing, date: SidebarRescueTestsSupport.base, skippedNewer: false, now: fixture.clock.now)])
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

        private func damagedSidebar() throws -> Fixture {
            let fixture = try Fixture()
            try fixture.saveKeptSidebar()
            try Data("{".utf8).write(to: fixture.session)
            return fixture
        }

        @Test func aDamagedFileOffersRescueAsAnUnreadableSidebar() throws {
            let fixture = try damagedSidebar()
            let questions = Questions(answer: false)
            _ = try fixture.open(ask: questions.ask)
            #expect(questions.offers.map(\.trouble) == [.unreadable])
        }

        @Test func quittingTheRescueLeavesTheSidebarUnopened() throws {
            let fixture = try damagedSidebar()
            let quit = try fixture.open(ask: Questions(answer: false).ask)
            #expect(quit == nil)
        }

        @Test func quittingOverADamagedFileChangesNothing() throws {
            let fixture = try Fixture()
            try fixture.saveKeptSidebar()
            let damaged = Data("{".utf8)
            try damaged.write(to: fixture.session)
            _ = try fixture.open(ask: Questions(answer: false).ask)
            #expect(try Data(contentsOf: fixture.session) == damaged)
        }
    }
}
