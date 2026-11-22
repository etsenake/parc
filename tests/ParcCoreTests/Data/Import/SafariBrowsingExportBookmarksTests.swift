import Compression
import Foundation
import Testing
@testable import ParcCore

struct SafariBrowsingExportBookmarksTests {
    private typealias Support = SafariBrowsingExportTestsSupport

    @Test func theSampleKeepsFoldersTheEmptyReadingListAndTheTopLevelLeaf() throws {
        let sample = try SafariBookmarksHTML.parse(Data(Support.safariSampleBookmarks.utf8))
        #expect(sample == [
            BrowserImportBookmark(id: "safari-export/0", title: "Favorites", url: nil, children: [
                BrowserImportBookmark(id: "safari-export/0.0", title: "Example", url: "https://www.example.com/", children: []),
            ]),
            BrowserImportBookmark(id: "safari-export/1", title: "Reading List", url: nil, children: []),
            BrowserImportBookmark(id: "safari-export/2", title: "Guide", url: "https://support.example.com/guide/", children: []),
        ])
        #expect((try? BrowserImportSelection(roots: sample)) != nil)
    }

    func rich() throws -> [BrowserImportBookmark] { try SafariBookmarksHTML.parse(Data(Support.safariRichBookmarks.utf8)) }

    @Test func topLevelFoldersAndLeavesKeepTheirOrderAndDecodedTitles() throws {
        let rich = try rich()
        #expect(rich.map(\.title) == ["Favorites & Friends", "Reading List", "Guide", "Unclosed"])
        #expect(rich.map(\.id) == ["safari-export/0", "safari-export/1", "safari-export/2", "safari-export/3"])
    }

    @Test func entitiesAreDecodedUnknownOnesKeptAndLinksWithoutAUsableAddressSkipped() throws {
        let favorites = try rich()[0].children
        #expect(favorites.map(\.title) == [#"Tom & Jerry <3 "quoted" 'single' café café &unknown; a&b"#, "lower case", "Nested", "Empty Inner", "After Empty"])
        #expect(favorites.map(\.id) == ["safari-export/0.0", "safari-export/0.1", "safari-export/0.2", "safari-export/0.3", "safari-export/0.4"])
    }

    @Test func addressesAreDecodedAndQuotedGreaterThanSignsDontEndATag() throws {
        #expect(try rich()[0].children[0].url == "https://www.example.com/?a=1&b=2")
    }

    @Test func singleQuotedLowercaseTagsAreRead() throws {
        #expect(try rich()[0].children[1].url == "https://example.org/single")
    }

    @Test func mixedCaseFolderTagsNestTheirBookmarks() throws {
        #expect(try rich()[0].children[2].children
                == [BrowserImportBookmark(id: "safari-export/0.2.0", title: "Deep", url: "https://nested.example.net/", children: [])])
    }

    @Test func aFolderWithoutItsOwnListIsKeptEmpty() throws {
        let folder = try rich()[0].children[3]
        #expect(folder.url == nil && folder.children.isEmpty)
    }

    @Test func theEmptyReadingListStaysAnOrdinaryEmptyFolder() throws {
        let readingList = try rich()[1]
        #expect(readingList.url == nil && readingList.children.isEmpty)
    }

    @Test func aListMissingItsFinalCloseStillKeepsItsBookmarks() throws {
        #expect(try rich()[3].children.map(\.url) == ["https://unclosed.example.com/"])
    }

    @Test func bookmarksInsideCommentsAreIgnored() throws {
        #expect(!(try rich()).contains { $0.title == "hidden" })
    }

    @Test func parsingTheSameFileTwiceGivesTheSameIDs() throws {
        #expect((try? SafariBookmarksHTML.parse(Data(Support.safariRichBookmarks.utf8))) == (try rich()))
    }

    @Test func aWrappingTopLevelListAndStrayClosingTagsDontAddOrCloseFolders() throws {
        let netscape = try SafariBookmarksHTML.parse(Data("<H1>Bookmarks</H1>\n<DL><p>\n<DT><H3>Bar</H3>\n<DL><p>\n<DT><A HREF=\"https://bar.example.com/\">Bar Link</A>\n</DL><p>\n<DT><A HREF=\"https://top.example.com/\">Top</A>\n</DL><p>\n</DL></DL>".utf8))
        #expect(netscape.map(\.title) == ["Bar", "Top"] && netscape[0].children.map(\.title) == ["Bar Link"])
    }

    @Test func aBookmarksFileThatIsntUTF8IsReadAsLatin1() {
        var latin = Data("<DT><A HREF=\"https://latin.example.com/\">Caf".utf8)
        latin.append(0xE9)
        latin.append(contentsOf: Array("</A>".utf8))
        #expect((try? SafariBookmarksHTML.parse(latin))?.map(\.title) == ["Café"])
    }

    @Test func aBookmarkOnThe128thLevelIsAccepted() throws {
        let deepest = try SafariBookmarksHTML.parse(Support.safariNested(127, leaf: true))
        #expect((try? BrowserImportSelection(roots: deepest)) != nil)
    }

    @Test func aFolderOnThe128thLevelIsAccepted() throws {
        let deepest = try SafariBookmarksHTML.parse(Support.safariNested(128, leaf: false))
        #expect((try? BrowserImportSelection(roots: deepest)) != nil)
    }

    @Test func bookmarksNestedDeeperThan128LevelsAreRefused() {
        #expect((try? SafariBookmarksHTML.parse(Support.safariNested(128, leaf: true))) == nil)
    }

    @Test func foldersNestedDeeperThan128LevelsAreRefused() {
        #expect((try? SafariBookmarksHTML.parse(Support.safariNested(129, leaf: false))) == nil)
    }

    @Test func exactly50000BookmarksAreAccepted() throws {
        let links = String(repeating: "<DT><A HREF=\"https://many.example.com/\">Many</A>\n", count: 50_000)
        let many = try SafariBookmarksHTML.parse(Data(links.utf8))
        #expect(many.count == 50_000 && (try? BrowserImportSelection(roots: many)) != nil)
    }

    @Test func moreThan50000BookmarksAreRefused() {
        let links = String(repeating: "<DT><A HREF=\"https://many.example.com/\">Many</A>\n", count: 50_000)
        #expect((try? SafariBookmarksHTML.parse(Data((links + "<DT><H3>One More</H3>").utf8))) == nil)
    }

    @Test func arcInternalAddressesAreSkippedSinceParcsSidebarCantOpenThem() throws {
        let arcLink = try SafariBookmarksHTML.parse(Data("<DT><A HREF=\"arc://space/1\">Arc</A>\n<DT><A HREF=\"https://kept.example.com/\">Kept</A>".utf8))
        #expect(arcLink.count == 1 && arcLink[0].url == "https://kept.example.com/")
    }
}
