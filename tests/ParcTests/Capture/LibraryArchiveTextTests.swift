import Foundation
import Testing
@testable import ParcLibrary

struct LibraryArchiveTextTests {
    @MainActor @Test(arguments: [
        (["https://www.iana.org/domains/reserved"], nil, "iana.org/domains/reserved"),
        (["https://example.com/"], nil, "example.com"),
        (["parc://note/A"], nil, "parc://note/A"),
        (["https://user:secret@www.example.com/path"], nil, "example.com/path"),
        (["ftp://user@files.example.com/a"], nil, "ftp://files.example.com/a"),
        (["https://a.example", "https://b.example"], "Work", "2 tabs · Work")] as [([String], String?, String)])
    func anArchiveSubtitleReadsAsTheAddressOrTheTabCountAndSpace(_ urls: [String], _ space: String?, _ expected: String) {
        #expect(LibraryView.subtitle(urls: urls, spaceName: space) == expected)
    }

    @MainActor @Test(arguments: [(0.0, "Today"), (-86_400.0, "Yesterday")])
    func archiveSectionsUseRelativeDayNames(_ offset: Double, _ expected: String) {
        let now = Date(timeIntervalSince1970: 1_900_000_000)
        #expect(LibraryView.heading(for: now.addingTimeInterval(offset), relativeTo: now) == expected)
    }

    @MainActor @Test func olderArchiveSectionsNameTheirDistance() {
        let now = Date(timeIntervalSince1970: 1_900_000_000)
        #expect(LibraryView.heading(for: now.addingTimeInterval(-3 * 86_400), relativeTo: now).contains("3"))
    }
}
