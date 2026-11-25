import Foundation
import Testing
@testable import ParcCore

struct ChromiumSessionFilesTests {
    private typealias Fixture = ChromiumSessionFixture

    private static let closedAt = Date(timeIntervalSince1970: 1_792_900_000)

    private static func write(_ data: Data, _ name: String, in directory: URL, folder: String = "Sessions") throws {
        let sessions = directory.appendingPathComponent(folder, isDirectory: true)
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        try data.write(to: sessions.appendingPathComponent(name))
    }

    private static func tabsFile() -> Data {
        let stamp = Fixture.windowsMicroseconds(closedAt)
        var commands = Fixture.restoreTab(id: 40, url: "https://first.example/", title: "First", closedAt: stamp)
        commands += Fixture.restoreTab(id: 41, url: "https://reopened.example/", title: "Reopened", closedAt: stamp)
        commands += [Fixture.restoreWindow(id: 5, tabs: 2, closedAt: stamp + 1_000_000)]
        commands += Fixture.restoreTab(id: 50, url: "https://window-a.example/", title: "Window A", closedAt: 0)
        commands += Fixture.restoreTab(id: 51, url: "https://window-b.example/", title: "Window B", closedAt: 0)
        commands += [Fixture.restoreGroup(session: 6, tabs: 1, closedAt: stamp + 2_000_000)]
        commands += Fixture.restoreTab(id: 60, url: "https://grouped.example/", title: "Grouped", closedAt: 0)
        commands += [Fixture.restoreWindow(id: 7, tabs: 1, closedAt: stamp, type: 1)]
        commands += Fixture.restoreTab(id: 70, url: "https://popup.example/", title: "Popup", closedAt: 0)
        commands += [Fixture.command(2, Fixture.i32(41)), Fixture.marker]
        return Fixture.file(commands)
    }

    @Test func closedTabsComeNewestFirstWithRestoredAndPopupEntriesLeftOut() throws {
        let closed = try #require(ChromiumSessionParser.closedTabs(Self.tabsFile(), flavor: .chrome))
        #expect(closed.map(\.url) == ["https://grouped.example/", "https://window-a.example/", "https://window-b.example/",
                                      "https://first.example/"])
        #expect(closed.map(\.title) == ["Grouped", "Window A", "Window B", "First"])
        #expect(closed[3].closedAt.map { abs($0.timeIntervalSince(Self.closedAt)) < 0.001 } == true)
        #expect(closed[1].closedAt.map { abs($0.timeIntervalSince(Self.closedAt.addingTimeInterval(1))) < 0.001 } == true)
    }

    @Test func closedTabsUseTheSelectedNavigation() throws {
        let stamp = Fixture.windowsMicroseconds(Self.closedAt)
        let commands = [Fixture.command(4, Fixture.i32(40, 1) + Fixture.le(UInt64(bitPattern: stamp))),
                        Fixture.restoreNavigation(index: 4, url: "https://back.example/", title: "Back"),
                        Fixture.restoreNavigation(index: 9, url: "https://front.example/", title: "Front"), Fixture.marker]
        #expect(ChromiumSessionParser.closedTabs(Fixture.file(commands), flavor: .chrome)?.map(\.url) == ["https://front.example/"])
    }

    @Test func anUnknownClosedTabCommandKeepsTheEntriesBeforeIt() throws {
        let stamp = Fixture.windowsMicroseconds(Self.closedAt)
        let commands = Fixture.restoreTab(id: 40, url: "https://kept.example/", title: "Kept", closedAt: stamp)
            + [Fixture.command(77, [])] + Fixture.restoreTab(id: 41, url: "https://lost.example/", title: "Lost", closedAt: stamp)
            + [Fixture.marker]
        #expect(ChromiumSessionParser.closedTabs(Fixture.file(commands), flavor: .chrome)?.map(\.url) == ["https://kept.example/"])
    }

    @Test func theNewestSessionWithAMarkerWinsAndClosedTabsJoinIt() throws {
        try DataFixtures.withTemporaryDirectory { directory in
            let older = Fixture.file(Fixture.standard() + [Fixture.windowTitle(1, "Older")])
            let newer = Fixture.file(Fixture.standard() + [Fixture.windowTitle(1, "Newer")])
            let unfinished = Fixture.file(Fixture.standard().filter { $0 != Fixture.marker } + [Fixture.windowTitle(1, "Crashed")])
            try Self.write(older, "Session_13350000000000001", in: directory)
            try Self.write(newer, "Session_13350000000000020", in: directory)
            try Self.write(unfinished, "Session_13350000000000300", in: directory)
            try Self.write(older, "Session_backup", in: directory)
            try Self.write(Self.tabsFile(), "Tabs_13350000000000005", in: directory)
            let outcome = ChromiumSessionParser.read(profileDirectory: directory, flavor: .chrome, decrypt: nil)
            let session = try #require(outcome.session)
            #expect(session.windows.map(\.userTitle) == ["Newer"])
            #expect(session.closedTabs.count == 4)
            #expect(!outcome.encryptedUnreadable)
        }
    }

    @Test func aMissingSessionsFolderGivesNothingAndNoWarning() throws {
        try DataFixtures.withTemporaryDirectory { directory in
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            #expect(ChromiumSessionParser.read(profileDirectory: directory, flavor: .chrome, decrypt: nil)
                    == ChromiumSessionParser.Outcome(session: nil))
        }
    }

    @Test func anEncryptedSessionIsDecryptedThroughTheClosure() throws {
        try DataFixtures.withTemporaryDirectory { directory in
            try Self.write(Data([0x53, 0x4E, 0x53, 0x53, 5, 0, 0, 0, 9, 9]), "Session_13350000000000009", in: directory,
                           folder: "Sessions_Encrypted")
            try Self.write(Data([0x53, 0x4E, 0x53, 0x53, 5, 0, 0, 0]), "Tabs_13350000000000009", in: directory,
                           folder: "Sessions_Encrypted")
            let plain = Fixture.file(Fixture.standard() + [Fixture.windowTitle(1, "Decrypted")])
            let tabs = Self.tabsFile()
            let calls = ChromiumDecryptCalls()
            let outcome = ChromiumSessionParser.read(profileDirectory: directory, flavor: .chrome) { url, format in
                calls.append(url.lastPathComponent, format)
                return url.lastPathComponent.hasPrefix("Tabs_") ? tabs : plain
            }
            #expect(outcome.session?.windows.map(\.userTitle) == ["Decrypted"])
            #expect(outcome.session?.closedTabs.count == 4)
            #expect(!outcome.encryptedUnreadable)
            #expect(calls.entries == [ChromiumDecryptCalls.Entry(name: "Session_13350000000000009", format: .chromiumSession),
                                      ChromiumDecryptCalls.Entry(name: "Tabs_13350000000000009", format: .chromiumSession)])
        }
    }

    @Test func aReadableCleartextSessionNeverTouchesTheDecryptor() throws {
        try DataFixtures.withTemporaryDirectory { directory in
            try Self.write(Fixture.file(Fixture.standard()), "Session_13350000000000001", in: directory)
            try Self.write(Data([0x53, 0x4E, 0x53, 0x53, 5, 0, 0, 0]), "Session_13350000000000009", in: directory,
                           folder: "Sessions_Encrypted")
            let calls = ChromiumDecryptCalls()
            let outcome = ChromiumSessionParser.read(profileDirectory: directory, flavor: .chrome) { url, format in
                calls.append(url.lastPathComponent, format)
                throw CocoaError(.userCancelled)
            }
            #expect(outcome.session?.windows.count == 1)
            #expect(calls.entries.isEmpty)
        }
    }

    @Test func anEncryptedSessionWithoutADecryptorOrWithAFailingOneIsFlagged() throws {
        try DataFixtures.withTemporaryDirectory { directory in
            try Self.write(Data([0x53, 0x4E, 0x53, 0x53, 5, 0, 0, 0]), "Session_13350000000000009", in: directory,
                           folder: "Sessions_Encrypted")
            try Self.write(Data([0x53, 0x4E, 0x53, 0x53, 5, 0, 0, 0]), "Session_13350000000000008", in: directory,
                           folder: "Sessions_Encrypted")
            #expect(ChromiumSessionParser.read(profileDirectory: directory, flavor: .chrome, decrypt: nil)
                    == ChromiumSessionParser.Outcome(session: nil, encryptedUnreadable: true))
            let calls = ChromiumDecryptCalls()
            let failed = ChromiumSessionParser.read(profileDirectory: directory, flavor: .chrome) { url, format in
                calls.append(url.lastPathComponent, format)
                throw CocoaError(.userCancelled)
            }
            #expect(failed == ChromiumSessionParser.Outcome(session: nil, encryptedUnreadable: true))
            #expect(calls.entries.count == 1)
        }
    }
}

final class ChromiumDecryptCalls: @unchecked Sendable {
    struct Entry: Equatable {
        let name: String
        let format: SidebarEncryptedFormat
    }

    private let lock = NSLock()
    private var stored: [Entry] = []

    var entries: [Entry] { lock.withLock { stored } }

    func append(_ name: String, _ format: SidebarEncryptedFormat) {
        lock.withLock { stored.append(Entry(name: name, format: format)) }
    }
}
