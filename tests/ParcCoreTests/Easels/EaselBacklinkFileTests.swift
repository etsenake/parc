import Foundation
import Testing
@testable import ParcCore

struct EaselBacklinkFileTests {
    private static let roadmap = "file:///Users/me/Notes/Roadmap.md"

    private static func file(runs: [(location: Int, length: Int)], text: String) throws -> URL {
        let font = EaselRichText.Font(name: "Helvetica", size: 15)
        var item = EaselItem(kind: .text, frame: EaselRect(x: 0, y: 0, width: 200, height: 40))
        item.text = text
        item.richText = EaselRichText(runs: runs.map {
            EaselRichText.Run(location: $0.location, length: $0.length,
                              attributes: EaselRichText.Attributes(font: font, ink: "#000000FF", link: roadmap))
        })
        let document = EaselDocument(id: UUID(), title: "Plans", createdAt: Date(), modifiedAt: Date(), items: [item])
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("board.json")
        try JSONEncoder().encode(document).write(to: url)
        return url
    }

    @Test func aDamagedEaselFileIsSkippedInsteadOfIndexed() throws {
        let url = try Self.file(runs: [(0, -3)], text: "Roadmap")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        #expect(EaselBacklinkScanner.read(fileAt: url) == nil)
    }

    @Test func aRunPastTheEndOfTheTextIsSkipped() throws {
        let url = try Self.file(runs: [(0, 1), (1, Int.max)], text: "Roadmap")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        #expect(EaselBacklinkScanner.read(fileAt: url) == nil)
    }

    @Test func aHealthyEaselFileStillReportsItsNoteLinks() throws {
        let url = try Self.file(runs: [(0, 7)], text: "Roadmap")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let read = try #require(EaselBacklinkScanner.read(fileAt: url))
        #expect(read.title == "Plans")
        #expect(read.links.count == 1)
    }
}
