import AppKit
import ParcCore
import ParcEngine
import Testing
@testable import Parc
@testable import ParcOnboarding

@MainActor @Suite(.serialized)
struct BrowserImportSafariExportTests {
    private nonisolated static let passwordsCSV = "Title,URL,Username,Password,Notes,OTPAuth\nExample,https://kept.example.test/,me,secret,,\n"
    private nonisolated static let cards = #"{"metadata":{"data_type":"payment_cards"},"payment_cards":[]}"#

    private nonisolated static func history(_ address: String) -> String {
        #"{"metadata":{"browser_name":"Safari","data_type":"history","schema_version":1},"history":[{"url":"\#(address)","time_usec":1751296375691668,"visit_count":1}]}"#
    }

    private static func storedZip(_ entries: [(String, String)]) -> Data {
        var archive = [UInt8](), central = [UInt8]()
        func put<T: FixedWidthInteger>(_ value: T, _ bytes: inout [UInt8]) {
            for index in 0..<MemoryLayout<T>.size { bytes.append(UInt8(truncatingIfNeeded: value >> (8 * index))) }
        }
        func crc(_ data: [UInt8]) -> UInt32 {
            var value: UInt32 = 0xFFFF_FFFF
            for byte in data {
                value ^= UInt32(byte)
                for _ in 0..<8 { value = value & 1 == 1 ? 0xEDB8_8320 ^ (value >> 1) : value >> 1 }
            }
            return value ^ 0xFFFF_FFFF
        }
        for (name, text) in entries {
            let data = Array(text.utf8), path = Array(name.utf8), offset = UInt32(archive.count), sum = crc(data)
            put(UInt32(0x0403_4B50), &archive); put(UInt16(20), &archive); put(UInt16(0x0800), &archive)
            put(UInt16(0), &archive); put(UInt32(0), &archive); put(sum, &archive)
            put(UInt32(data.count), &archive); put(UInt32(data.count), &archive)
            put(UInt16(path.count), &archive); put(UInt16(0), &archive)
            archive += path + data
            put(UInt32(0x0201_4B50), &central); put(UInt16(0x031E), &central); put(UInt16(20), &central)
            put(UInt16(0x0800), &central); put(UInt16(0), &central); put(UInt32(0), &central); put(sum, &central)
            put(UInt32(data.count), &central); put(UInt32(data.count), &central); put(UInt16(path.count), &central)
            for _ in 0..<4 { put(UInt16(0), &central) }
            put(UInt32(0), &central); put(offset, &central)
            central += path
        }
        let start = UInt32(archive.count)
        archive += central
        put(UInt32(0x0605_4B50), &archive); put(UInt32(0), &archive)
        put(UInt16(entries.count), &archive); put(UInt16(entries.count), &archive)
        put(UInt32(central.count), &archive); put(start, &archive); put(UInt16(0), &archive)
        return Data(archive)
    }

    private nonisolated static let fullExport: [(String, String)] = [
        ("Safari Export/Bookmarks.html", """
            <!DOCTYPE NETSCAPE-Bookmark-file-1>
            <DT><H3 id="BookmarksBar">Favorites</H3>
            <DL><p>
            <DT><A HREF="https://kept.example.test/">Kept</A>
            </DL><p>
            """),
        ("Safari Export/Passwords.csv", passwordsCSV),
        ("Safari Export/History.json", history("https://default.example.test/")),
        ("Safari Export/History - Work.json", history("https://work.example.test/")),
        ("Safari Export/PaymentCards.json", cards),
    ]

    private func root(_ scene: BrowserImportScene) -> URL { scene.directory.appendingPathComponent("SafariExportRoot") }

    private func leftovers(_ scene: BrowserImportScene) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: root(scene).path)) ?? []).filter { $0.hasPrefix("ParcSafariExport-") }
    }

    private func save(_ scene: BrowserImportScene, _ name: String, _ entries: [(String, String)]) throws -> URL {
        try save(scene, name, Self.storedZip(entries))
    }

    private func save(_ scene: BrowserImportScene, _ name: String, _ data: Data) throws -> URL {
        let url = scene.directory.appendingPathComponent(name)
        try data.write(to: url)
        return url
    }

    private func start(_ scene: BrowserImportScene) throws -> BrowserImportCoordinator {
        try FileManager.default.createDirectory(at: root(scene), withIntermediateDirectories: true)
        return scene.chosen(try scene.safari(), profiles: ImportFixture.profiles([ImportFixture.profile("Safari", [], .restricted)],
                            .restricted), onboarding: true, exportRoot: root(scene))
    }

    private func opened(_ scene: BrowserImportScene, _ entries: [(String, String)] = fullExport) throws
        -> (BrowserImportCoordinator, BrowserImportEngineFake.ExportRequest) {
        let coordinator = try start(scene)
        coordinator.importSafariExport(try save(scene, "Safari Export.zip", entries))
        scene.engine.settle()
        return (coordinator, try #require(scene.engine.exports.first))
    }

    private func importing(_ scene: BrowserImportScene) throws -> (BrowserImportCoordinator, BrowserImportEngineFake.ExportRequest) {
        let (coordinator, request) = try opened(scene)
        request.complete(ImportFixture.profiles([
            ImportFixture.profile("export-default", [.history, .autofill], name: "Safari", directory: "profile-0"),
            ImportFixture.profile("export-work", [.history], name: "Work", directory: "profile-1")]))
        return (coordinator, request)
    }

    private func historyRunning(_ scene: BrowserImportScene) throws -> (BrowserImportCoordinator, BrowserImportEngineFake.ExportRequest) {
        let (coordinator, request) = try importing(scene)
        coordinator.commitBookmarks()
        scene.engine.passwordRequests.removeFirst().complete(ImportFixture.password(.completed, imported: 1))
        return (coordinator, request)
    }

    private func passwordsOnly(_ scene: BrowserImportScene) throws
        -> (BrowserImportCoordinator, BrowserImportEngineFake.PasswordRequest) {
        let coordinator = try start(scene)
        coordinator.importSafariExport(try save(scene, "Passwords only.zip", [("Passwords.csv", Self.passwordsCSV)]))
        scene.engine.settle()
        return (coordinator, try #require(scene.engine.passwordRequests.first))
    }

    @Test func safariWithoutFullDiskAccessCanTakeItsExportFileInstead() throws {
        try BrowserImportScene.run { scene in
            let coordinator = try start(scene)
            #expect(coordinator.stage == .profiles && coordinator.canChooseSafariExport)
        }
    }

    @Test func onlyAZipFileIsAcceptedAsSafarisExport() throws {
        try BrowserImportScene.run { scene in
            let coordinator = try start(scene)
            coordinator.importSafariExport(scene.directory.appendingPathComponent("Passwords.csv"))
            scene.engine.settle()
            #expect(coordinator.stage == .profiles && coordinator.error != nil && scene.engine.exports.isEmpty)
        }
    }

    @Test func openingTheExportLoadsItsProfilesDefaultFirst() throws {
        try BrowserImportScene.run { scene in
            let coordinator = try start(scene)
            coordinator.importSafariExport(try save(scene, "Safari Export.zip", Self.fullExport))
            #expect(coordinator.stage == .loading)
            scene.engine.settle()
            let request = try #require(scene.engine.exports.first)
            #expect(request.names == ["Safari", "Work"] && request.directories.count == 2)
        }
    }

    @Test func openingClearsAnInterruptedImportsFolderButNotOneStillOpening() throws {
        try BrowserImportScene.run { scene in
            let files = FileManager.default
            try files.createDirectory(at: root(scene), withIntermediateDirectories: true)
            let abandoned = root(scene).appendingPathComponent("ParcSafariExport-abandoned")
            try files.createDirectory(at: abandoned, withIntermediateDirectories: true)
            try files.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -3600)], ofItemAtPath: abandoned.path)
            let opening = root(scene).appendingPathComponent("ParcSafariExport-opening")
            try files.createDirectory(at: opening, withIntermediateDirectories: true)
            _ = try opened(scene)
            #expect(!files.fileExists(atPath: abandoned.path) && files.fileExists(atPath: opening.path))
            #expect(leftovers(scene).count == 2)
        }
    }

    @Test func theExportsBookmarksBecomeTheUsualPageWithNoPasswordPage() throws {
        try BrowserImportScene.run { scene in
            let (coordinator, _) = try importing(scene)
            #expect(coordinator.stage == .bookmarks && coordinator.bookmarkPages.count == 1)
            #expect(coordinator.bookmarkPages.first?.destination == scene.destination)
            #expect(coordinator.passwordDestination == nil)
            #expect(coordinator.setupPage == .bookmarks && coordinator.setupPagesAhead.isEmpty)
            #expect(scene.store.state.profiles.contains { $0.name == "Work" })
        }
    }

    @Test func theExportsPasswordsGoToTheOriginalProfileBeforeAnyHistory() throws {
        try BrowserImportScene.run { scene in
            let (coordinator, _) = try importing(scene)
            let passwords = try #require(scene.engine.passwordRequests.first)
            #expect(scene.engine.passwordRequests.count == 1 && passwords.path == scene.originalPath)
            #expect(FileManager.default.fileExists(atPath: passwords.url.path))
            #expect(scene.engine.browserCompletions.isEmpty && coordinator.hasBackgroundWork)
        }
    }

    @Test func acceptingBookmarksSavesThemAndWaitsForThePasswords() throws {
        try BrowserImportScene.run { scene in
            let (coordinator, _) = try importing(scene)
            coordinator.commitBookmarks()
            #expect(coordinator.stage == .importing && coordinator.message == "Importing your Safari passwords…")
            #expect(scene.store.state.tabs.contains { $0.url == "https://kept.example.test/" })
            #expect(coordinator.setupPage == .progress && coordinator.setupPagesAhead.isEmpty)
        }
    }

    @Test func oncePasswordsAreInTheirCopyIsDeletedAndEachProfilesHistoryImports() throws {
        try BrowserImportScene.run { scene in
            let (coordinator, _) = try importing(scene)
            coordinator.commitBookmarks()
            let passwords = scene.engine.passwordRequests.removeFirst()
            passwords.complete(ImportFixture.password(.completed, imported: 1))
            #expect(coordinator.stage == .finished && !FileManager.default.fileExists(atPath: passwords.url.path))
            let work = try #require(scene.store.state.profiles.first { $0.name == "Work" })
            let requests = scene.engine.browserRequests.suffix(2)
            #expect(scene.engine.browserCompletions.count == 2)
            #expect(requests.map(\.path) == [scene.originalPath, scene.path(work.id)])
            #expect(requests.map(\.categories) == [[.history, .autofill], [.history]])
        }
    }

    @Test func paymentCardsWaitUntilTheReaderHasThemThenAreDeleted() throws {
        try BrowserImportScene.run { scene in
            let (_, request) = try historyRunning(scene)
            let files = FileManager.default
            let cards = request.directories[0].appendingPathComponent("PaymentCards.json")
            let reader = try #require(scene.engine.browserRequests.suffix(2).first)
            #expect(files.fileExists(atPath: cards.path))
            scene.engine.browserCompletions.remove(at: 1)(ImportFixture.result(.completed))
            #expect(files.fileExists(atPath: cards.path))
            reader.progress(ImportFixture.event(.history, .writing))
            reader.progress(ImportFixture.event(.autofill, .reading))
            #expect(files.fileExists(atPath: cards.path))
            reader.progress(ImportFixture.event(.autofill, .writing))
            #expect(!files.fileExists(atPath: cards.path))
            #expect(files.fileExists(atPath: request.directories[0].appendingPathComponent("History.json").path))
        }
    }

    @Test func theExportFolderStaysWhileHistoryIsReadAndGoesWhenItEnds() throws {
        try BrowserImportScene.run { scene in
            let (coordinator, _) = try historyRunning(scene)
            #expect(leftovers(scene).count == 1)
            scene.engine.finishAllBrowser()
            scene.engine.settle()
            #expect(leftovers(scene).isEmpty && !coordinator.hasBackgroundWork)
            #expect(ImportedBrowserDataFailures.take() == nil)
        }
    }

    @Test func aCardsOnlyExportImportsCardsAndAFailureStillDeletesThem() throws {
        try BrowserImportScene.run { scene in
            let (_, request) = try opened(scene, [("Safari Export/PaymentCards.json", Self.cards)])
            let cards = request.directories[0].appendingPathComponent("PaymentCards.json")
            #expect(request.names == ["Safari"] && FileManager.default.fileExists(atPath: cards.path))
            request.complete(ImportFixture.profiles([
                ImportFixture.profile("export-cards", [.autofill], name: "Safari", directory: "profile-0")]))
            #expect(scene.engine.browserRequests.last?.categories == [.autofill])
            #expect(scene.engine.browserRequests.last?.path == scene.originalPath)
            scene.engine.finishBrowser(.failed)
            #expect(!FileManager.default.fileExists(atPath: cards.path))
            scene.engine.settle()
            #expect(leftovers(scene).isEmpty && ImportedBrowserDataFailures.take() == .failed)
        }
    }

    @Test func aPasswordsOnlyExportStaysOnProgressAndReportsAPartialFile() throws {
        try BrowserImportScene.run { scene in
            let (coordinator, request) = try passwordsOnly(scene)
            #expect(scene.engine.exports.isEmpty && coordinator.stage == .importing && coordinator.hasBackgroundWork)
            request.complete(ImportFixture.password(.partial, imported: 1, invalid: 1))
            #expect(coordinator.stage == .finished)
            scene.engine.settle()
            #expect(ImportedBrowserDataFailures.take() == .partial)
        }
    }

    @Test func stopCancelsTheExportsPasswordsWithoutReportingAFailure() throws {
        try BrowserImportScene.run { scene in
            let (coordinator, request) = try passwordsOnly(scene)
            coordinator.stopImport()
            #expect(ImportFixture.cancelled(request.lease) && coordinator.stage == .finished)
            request.complete(ImportFixture.password(.cancelled))
            scene.engine.settle()
            #expect(leftovers(scene).isEmpty && ImportedBrowserDataFailures.take() == nil)
        }
    }

    @Test func passwordsLostWithoutStopReportAFailure() throws {
        try BrowserImportScene.run { scene in
            let (coordinator, request) = try passwordsOnly(scene)
            request.complete(ImportFixture.password(.cancelled))
            scene.engine.settle()
            #expect(coordinator.stage == .finished && ImportedBrowserDataFailures.take() == .failed)
        }
    }

    @Test func aFileThatIsNotSafarisExportReturnsWithAnExplanation() throws {
        try BrowserImportScene.run { scene in
            let coordinator = try start(scene)
            coordinator.importSafariExport(try save(scene, "Broken.zip", Data("not a zip".utf8)))
            scene.engine.settle()
            #expect(coordinator.stage == .profiles && coordinator.error?.contains("Export Browsing Data") == true)
            #expect(leftovers(scene).isEmpty)
        }
    }

    @Test func anExportWaitingOnTheLastImportCountsAndThenShowsItsBookmarksPage() throws {
        try BrowserImportScene.run { scene in
            let (finishing, passwords) = try passwordsOnly(scene)
            finishing.detach(onAdBlockers: nil)
            let queued = try start(scene)
            queued.importSafariExport(try save(scene, "Queued.zip", Self.fullExport))
            scene.engine.settle()
            scene.engine.exports.removeFirst().complete(ImportFixture.profiles([
                ImportFixture.profile("queued-default", [.history], name: "Safari", directory: "profile-0"),
                ImportFixture.profile("queued-work", [.history], name: "Work", directory: "profile-1")]))
            #expect(queued.stage == .importing && queued.message == "Finishing your last import…")
            #expect(queued.setupPage == .progress && queued.setupPagesAhead == [.bookmarks])
            passwords.complete(ImportFixture.password(.completed, imported: 1))
            #expect(!finishing.hasBackgroundWork && queued.stage == .bookmarks && queued.setupPagesAhead.isEmpty)
        }
    }

    @Test func aPasswordsOnlyExportNeverCountsTheSafariAppsBookmarks() throws {
        try BrowserImportScene.run { scene in
            try FileManager.default.createDirectory(at: root(scene), withIntermediateDirectories: true)
            let readable = scene.chosen(try scene.safari(), profiles: ImportFixture.profiles([
                ImportFixture.profile("Safari", [.history, .bookmarks])]), onboarding: true, exportRoot: root(scene))
            var counted: [[OnboardingDraft.ImportPage]] = []
            readable.onChange = { [unowned readable] in
                if readable.stage == .importing { counted.append(readable.setupPagesAhead) }
            }
            readable.importSafariExport(try save(scene, "Readable.zip", [("Passwords.csv", Self.passwordsCSV)]))
            scene.engine.settle()
            #expect(!scene.engine.passwordRequests.isEmpty)
            #expect(!counted.isEmpty && counted.allSatisfy(\.isEmpty))
        }
    }

    @Test func closingWhileTheExportOpensLeavesNoFolder() throws {
        try BrowserImportScene.run { scene in
            let coordinator = try start(scene)
            coordinator.importSafariExport(try save(scene, "Abandoned.zip", Self.fullExport))
            coordinator.cancel()
            scene.engine.settle()
            #expect(leftovers(scene).isEmpty && scene.engine.exports.isEmpty)
        }
    }
}
