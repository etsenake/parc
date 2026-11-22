import Foundation
import Testing
@testable import ParcCore

struct BrowserStoreNativeLinkCopyTests {
    @Test @MainActor static func copyingAFolderWithASelectedChildExpandsItsOriginalsOnce() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let store = try BrowserStore(directory: directory), space = store.activeSpaceID, profile = store.activeSpace.profileID
            let folder = store.createFolder(name: "Folder")
            let a = store.open("https://example.com/a(b)", kind: .today)
            let b = store.open("https://example.com/a(b)", kind: .pinned)
            let c = store.open("https://example.com/c", kind: .today)
            store.updateTab(a, title: "A [label]\nnext")
            store.moveTab(a, toSpace: space, folderID: folder)
            store.moveTab(b, toSpace: space, folderID: folder)
            store.toggleFolder(folder)
            let original = store.state
            let links = FolderLinks.links(in: original, items: [.folder(folder), .tab(a), .tab(c)], spaceID: space, profileID: profile)!
            #expect(links.map(\.tabID) == [a, b, c], "Plural copy includes collapsed folder originals once and preserves distinct same-URL tabs")
            #expect(store.state == original, "Preparing copy never mutates original page/model selection")
        }
    }

    @Test @MainActor static func plainCopyExportsOneOriginalURLPerLine() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let store = try BrowserStore(directory: directory), space = store.activeSpaceID, profile = store.activeSpace.profileID
            let folder = store.createFolder(name: "Folder")
            let a = store.open("https://example.com/a(b)", kind: .today)
            let b = store.open("https://example.com/a(b)", kind: .pinned)
            let c = store.open("https://example.com/c", kind: .today)
            store.updateTab(a, title: "A [label]\nnext")
            store.moveTab(a, toSpace: space, folderID: folder)
            store.moveTab(b, toSpace: space, folderID: folder)
            store.toggleFolder(folder)
            let original = store.state
            let links = FolderLinks.links(in: original, items: [.folder(folder), .tab(a), .tab(c)], spaceID: space, profileID: profile)!
            #expect(FolderLinks.text(for: links, format: .plain) == links.map(\.url).joined(separator: "\n"), "Plain plural copy exports one original URL per line")
        }
    }

    @Test @MainActor static func markdownCopyUsesTheSidebarTitleAndEscapesIt() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let store = try BrowserStore(directory: directory), space = store.activeSpaceID, profile = store.activeSpace.profileID
            let folder = store.createFolder(name: "Folder")
            let a = store.open("https://example.com/a(b)", kind: .today)
            let b = store.open("https://example.com/a(b)", kind: .pinned)
            let c = store.open("https://example.com/c", kind: .today)
            store.updateTab(a, title: "A [label]\nnext")
            store.moveTab(a, toSpace: space, folderID: folder)
            store.moveTab(b, toSpace: space, folderID: folder)
            store.toggleFolder(folder)
            let original = store.state
            let links = FolderLinks.links(in: original, items: [.folder(folder), .tab(a), .tab(c)], spaceID: space, profileID: profile)!
            #expect(FolderLinks.text(for: links, format: .markdown)?.hasPrefix("[A \\[label\\] next](<https://example.com/a(b)>)") == true, "Plural Markdown uses the sidebar title and safe folder serialization")
        }
    }

    @Test @MainActor static func aStaleSelectedRowRefusesTheWholeCopy() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let store = try BrowserStore(directory: directory), space = store.activeSpaceID, profile = store.activeSpace.profileID
            let c = store.open("https://example.com/c", kind: .today)
            let original = store.state
            #expect(FolderLinks.links(in: original, items: [.folder(UUID()), .tab(c)], spaceID: space, profileID: profile) == nil, "A stale selected item refuses the whole copy proposal")
        }
    }

    @Test @MainActor static func aForeignProfileCannotCopyTheOriginalSpace() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let store = try BrowserStore(directory: directory), space = store.activeSpaceID
            let c = store.open("https://example.com/c", kind: .today)
            let original = store.state
            #expect(FolderLinks.links(in: original, items: [.tab(c)], spaceID: space, profileID: UUID()) == nil, "Foreign profile cannot export the original Space")
        }
    }

    @Test @MainActor static func copyingASplitWithAnotherTabExpandsTheOriginalPanesInOrder() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let store = try BrowserStore(directory: directory), space = store.activeSpaceID, profile = store.activeSpace.profileID
            let folder = store.createFolder(name: "Folder")
            let a = store.open("https://example.com/a(b)", kind: .today)
            let b = store.open("https://example.com/a(b)", kind: .pinned)
            let c = store.open("https://example.com/c", kind: .today)
            store.updateTab(a, title: "A [label]\nnext")
            store.moveTab(a, toSpace: space, folderID: folder)
            store.moveTab(b, toSpace: space, folderID: folder)
            store.toggleFolder(folder)
            store.selectTab(a); store.selectTab(b, extendingSplit: true)
            let split = store.activeSplitLayout!
            let splitLinks = FolderLinks.links(in: store.state, items: [.split(split.id), .tab(c)], spaceID: space, profileID: profile)!
            #expect(splitLinks.map(\.tabID) == [a, b, c], "Plural copy expands the original split children in their existing order")
        }
    }

    @Test @MainActor static func copyingOneSelectedTabReturnsOnlyItsAddress() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let store = try BrowserStore(directory: directory), space = store.activeSpaceID, profile = store.activeSpace.profileID
            let c = store.open("https://example.com/c", kind: .today)
            #expect(FolderLinks.links(in: store.state, items: [.tab(c)], spaceID: space, profileID: profile)?.map(\.tabID) == [c], "One selected tab copies its own address")
        }
    }

    @Test @MainActor static func copyingOneSelectedSplitReturnsItsPanesInOrder() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let store = try BrowserStore(directory: directory), space = store.activeSpaceID, profile = store.activeSpace.profileID
            let folder = store.createFolder(name: "Folder")
            let a = store.open("https://example.com/a(b)", kind: .today)
            let b = store.open("https://example.com/a(b)", kind: .pinned)
            store.updateTab(a, title: "A [label]\nnext")
            store.moveTab(a, toSpace: space, folderID: folder)
            store.moveTab(b, toSpace: space, folderID: folder)
            store.toggleFolder(folder)
            store.selectTab(a); store.selectTab(b, extendingSplit: true)
            let split = store.activeSplitLayout!
            #expect(FolderLinks.links(in: store.state, items: [.split(split.id)], spaceID: space, profileID: profile)?.map(\.tabID) == [a, b], "One selected split copies all of its pages in pane order")
        }
    }

    @Test @MainActor static func copyingASplitIncludesItsFavoritePaneFromAnotherSpace() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let store = try BrowserStore(directory: directory), space = store.activeSpaceID, profile = store.activeSpace.profileID
            let folder = store.createFolder(name: "Folder")
            let a = store.open("https://example.com/a(b)", kind: .today)
            let b = store.open("https://example.com/a(b)", kind: .pinned)
            store.updateTab(a, title: "A [label]\nnext")
            store.moveTab(a, toSpace: space, folderID: folder)
            store.moveTab(b, toSpace: space, folderID: folder)
            store.toggleFolder(folder)
            store.selectTab(a); store.selectTab(b, extendingSplit: true)
            let split = store.activeSplitLayout!
            var mixed = store.state
            let favorite = mixed.tabs.firstIndex { $0.id == b }!
            mixed.tabs[favorite].kind = .favorite; mixed.tabs[favorite].folderID = nil; mixed.tabs[favorite].spaceID = UUID()
            #expect(FolderLinks.links(in: mixed, items: [.split(split.id)], spaceID: space, profileID: profile)?.map(\.tabID) == [a, b]
                       && FolderLinks.links(in: mixed, tabIDs: split.tabIDs, spaceID: space, profileID: profile).map(\.tabID) == [a, b], "A split row's Favorite from another Space is copied alike from the sidebar and the split menu")
        }
    }

    @Test @MainActor static func copyingOneSelectedFolderReturnsItsChildren() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let store = try BrowserStore(directory: directory), space = store.activeSpaceID, profile = store.activeSpace.profileID
            let folder = store.createFolder(name: "Folder")
            let a = store.open("https://example.com/a(b)", kind: .today)
            let b = store.open("https://example.com/a(b)", kind: .pinned)
            store.updateTab(a, title: "A [label]\nnext")
            store.moveTab(a, toSpace: space, folderID: folder)
            store.moveTab(b, toSpace: space, folderID: folder)
            store.toggleFolder(folder)
            let original = store.state
            #expect(FolderLinks.links(in: original, items: [.folder(folder)], spaceID: space, profileID: profile)?.map(\.tabID) == [a, b], "One selected folder copies its contents")
        }
    }

    @Test @MainActor static func onlyDocumentsWithCopyableAddressesJoinTheWebLinks() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let store = try BrowserStore(directory: directory), space = store.activeSpaceID, profile = store.activeSpace.profileID
            let c = store.open("https://example.com/c", kind: .today)
            let documents = [InternalPage.note(URL(fileURLWithPath: NSTemporaryDirectory() + "Parc Notes/" + UUID().uuidString + ".md")).urlString, InternalPage.easel(UUID()).urlString, "parc://settings/", "about:blank"]
                .map { store.openResolvedURL(URL(string: $0)!) }
            #expect(FolderLinks.links(in: store.state, items: documents.map { .tab($0) } + [.tab(c)], spaceID: space, profileID: profile)?.map(\.tabID) == [documents[0], c], "Notes copy their file's address, while Easels, Parc pages and blank tabs have no address to copy")
        }
    }

    @Test static func richCopyEscapesTitlesAndAddressesAndUsesAnAddressForABlankTitle() {
        let rich = [FolderLinks.Link(tabID: UUID(), title: "A [label]\nnext", url: "https://example.com/a?x=1&y=2"),
                    FolderLinks.Link(tabID: UUID(), title: " ", url: "https://example.com/\"c\"")]
        #expect(FolderLinks.html(for: rich) == "<meta charset=\"utf-8\"><a href=\"https://example.com/a?x=1&amp;y=2\">A [label] next</a><br>\n"
                   + "<a href=\"https://example.com/&quot;c&quot;\">https://example.com/&quot;c&quot;</a>", "Rich copy links each page title to its address, escaped, falling back to the address")
    }

    @Test static func markdownCopyUsesTheAddressForABlankTitle() {
        let rich = [FolderLinks.Link(tabID: UUID(), title: "A [label]\nnext", url: "https://example.com/a?x=1&y=2"),
                    FolderLinks.Link(tabID: UUID(), title: " ", url: "https://example.com/\"c\"")]
        #expect(FolderLinks.text(for: rich, format: .markdown)?.hasSuffix("\n[https://example.com/\"c\"](<https://example.com/\"c\">)") == true, "Markdown falls back to the address for a blank title too")
    }

    @Test static func emptyRichCopyHasNoHTML() {
        #expect(FolderLinks.html(for: []) == nil, "Nothing to copy has no rich flavor")
    }

    @Test @MainActor static func renamedTabsUseTheirSidebarNameInEachCopyFormat() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let store = try BrowserStore(directory: directory), space = store.activeSpaceID, profile = store.activeSpace.profileID
            let renamed = store.open("https://example.com/renamed", kind: .pinned)
            let named = store.createFolder(name: "Named")
            store.moveTab(renamed, toSpace: space, folderID: named)
            store.updateTab(renamed, title: "Page Title")
            try store.saveSidebarTitle(store.state.tab(renamed)!, title: "  My <Name> & Co  ")
            let renamedLinks = FolderLinks.links(in: store.state, items: [.tab(renamed)], spaceID: space, profileID: profile)!
            #expect(FolderLinks.text(for: renamedLinks, format: .markdown) == "[My \\<Name> & Co](<https://example.com/renamed>)", "Markdown copies a renamed tab under the name the sidebar shows")
            #expect(FolderLinks.html(for: renamedLinks) == "<meta charset=\"utf-8\"><a href=\"https://example.com/renamed\">My &lt;Name&gt; &amp; Co</a>", "Rich copy links a renamed tab's sidebar name to its address")
            #expect(FolderLinks.text(for: renamedLinks, format: .plain) == "https://example.com/renamed", "Plain copies of a renamed tab stay a bare address")
        }
    }

    @Test @MainActor static func folderAndSplitMenuCopyUseTheSameRenamedTabTitle() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let store = try BrowserStore(directory: directory), space = store.activeSpaceID, profile = store.activeSpace.profileID
            let renamed = store.open("https://example.com/renamed", kind: .pinned)
            let named = store.createFolder(name: "Named")
            store.moveTab(renamed, toSpace: space, folderID: named)
            store.updateTab(renamed, title: "Page Title")
            try store.saveSidebarTitle(store.state.tab(renamed)!, title: "  My <Name> & Co  ")
            let renamedLinks = FolderLinks.links(in: store.state, items: [.tab(renamed)], spaceID: space, profileID: profile)!
            #expect(FolderLinks.links(in: store.state, tabIDs: [renamed], spaceID: space, profileID: profile) == renamedLinks
                       && FolderLinks.links(in: store.state, target: FolderLinkTarget(folderID: named, spaceID: space, profileID: profile)) == renamedLinks, "The split menu and a folder's Copy All Links use the same sidebar name")
        }
    }

    @Test @MainActor static func clearingTheSidebarNameRestoresTheSavedTitleForCopy() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let store = try BrowserStore(directory: directory), space = store.activeSpaceID, profile = store.activeSpace.profileID
            let renamed = store.open("https://example.com/renamed", kind: .pinned)
            let named = store.createFolder(name: "Named")
            store.moveTab(renamed, toSpace: space, folderID: named)
            store.updateTab(renamed, title: "Page Title")
            try store.saveSidebarTitle(store.state.tab(renamed)!, title: "  My <Name> & Co  ")
            try store.saveSidebarTitle(store.state.tab(renamed)!, title: "")
            let unnamed = FolderLinks.links(in: store.state, items: [.tab(renamed)], spaceID: space, profileID: profile)!
            #expect(FolderLinks.text(for: unnamed, format: .markdown) == "[example.com](<https://example.com/renamed>)", "Clearing the sidebar name falls back to the title saved when the tab was pinned")
        }
    }

    @Test @MainActor static func copiedLinksUseSavedPinnedTitle() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let store = try BrowserStore(directory: directory), space = store.activeSpaceID, profile = store.activeSpace.profileID
            let id = store.open("https://example.com/pinned", kind: .today)
            store.updateTab(id, title: "Saved <Title>")
            store.setKind(id, .pinned)
            let folder = store.createFolder(name: "Saved")
            store.moveTab(id, toSpace: space, folderID: folder)
            store.updateTab(id, title: "Live Title")
            let tab = store.state.tab(id)!
            #expect(tab.kind == .pinned && tab.customTitle == nil && tab.title == "Live Title"
                       && SidebarTabTitle.display(tab) == "Saved <Title>", "A pinned tab's sidebar row keeps the title saved when it was pinned")
            let links = FolderLinks.links(in: store.state, items: [.tab(id)], spaceID: space, profileID: profile)!
            #expect(links.map(\.title) == [SidebarTabTitle.display(tab)], "Copied links take the title the sidebar row shows")
            #expect(FolderLinks.text(for: links, format: .markdown) == "[Saved \\<Title>](<https://example.com/pinned>)", "Markdown copies a pinned tab under its saved title, not the live one")
            #expect(FolderLinks.html(for: links) == "<meta charset=\"utf-8\"><a href=\"https://example.com/pinned\">Saved &lt;Title&gt;</a>", "Rich copy links a pinned tab's saved title to its address")
            #expect(FolderLinks.text(for: links, format: .plain) == "https://example.com/pinned", "Plain copies stay a bare address")
            #expect(FolderLinks.links(in: store.state, tabIDs: [id], spaceID: space, profileID: profile) == links
                       && FolderLinks.links(in: store.state, target: FolderLinkTarget(folderID: folder, spaceID: space, profileID: profile)) == links, "The split menu and a folder's Copy All Links use the same saved title")
        }
    }

    struct MarkdownLabel: Sendable, CustomTestStringConvertible {
        let testDescription: String
        let title: String
        let expected: String
    }

    @Test(arguments: [
        MarkdownLabel(testDescription: "Generic type", title: "Vec<T>", expected: #"Vec\<T>"#),
        MarkdownLabel(testDescription: "HTML and angle brackets", title: "<b>bold</b> & <https://example.com>", expected: #"\<b>bold\</b> & \<https://example.com>"#),
        MarkdownLabel(testDescription: "Internal underscores", title: "snake_case_name.py", expected: "snake_case_name.py"),
        MarkdownLabel(testDescription: "Leading underscores", title: "_private and __dunder__", expected: #"\_private and \_\_dunder\_\_"#),
        MarkdownLabel(testDescription: "Emphasis markers", title: "**Bold** and *it* or a*b*c", expected: #"\*\*Bold\*\* and \*it\* or a\*b\*c"#),
        MarkdownLabel(testDescription: "Standalone punctuation", title: "5 * 3 = 15 and x ~ y and a _ b", expected: "5 * 3 = 15 and x ~ y and a _ b"),
        MarkdownLabel(testDescription: "Tildes", title: "~/Downloads and ~~gone~~", expected: #"\~/Downloads and \~\~gone\~\~"#),
        MarkdownLabel(testDescription: "Backticks", title: "`code` here", expected: #"\`code\` here"#),
        MarkdownLabel(testDescription: "Heading marks", title: "# Heading #1", expected: "# Heading #1"),
        MarkdownLabel(testDescription: "Entities and ampersands", title: "AT&T &amp; Tom & Jerry &#169; &#x1F600; &; &copy", expected: #"AT&T \&amp; Tom & Jerry \&#169; \&#x1F600; &; &copy"#),
        MarkdownLabel(testDescription: "Backslashes", title: #"C:\Users\me and a\*b and trailing\"#, expected: #"C:\Users\me and a\\\*b and trailing\\"#),
        MarkdownLabel(testDescription: "Bracket syntax", title: "[link](url) ![img]", expected: #"\[link\](url) !\[img\]"#),
        MarkdownLabel(testDescription: "Line breaks", title: "Line\r\nbreak\nhere", expected: "Line  break here"),
        MarkdownLabel(testDescription: "Unicode text", title: "naïve_test 日本_語 😀_x", expected: #"naïve_test 日本_語 😀\_x"#),
        MarkdownLabel(testDescription: "Nonbreaking spaces", title: "a\u{00A0}*\u{00A0}b", expected: "a\u{00A0}*\u{00A0}b"),
        MarkdownLabel(testDescription: "Blank label", title: "", expected: ""),
    ])
    static func markdownLabelsEscapeOnlySpecialText(_ label: MarkdownLabel) {
        #expect(FolderLinks.markdownLabel(label.title) == label.expected)
    }

    @Test static func copiedMarkdownLabelsUseTheAddressForBlankTitles() {
        let links = [FolderLinks.Link(tabID: UUID(), title: "Vec<T> & `Option<_>`", url: "https://example.com/a_b"),
                     FolderLinks.Link(tabID: UUID(), title: "", url: "https://example.com/_next/a_b?x=1&y=2")]
        #expect(FolderLinks.text(for: links, format: .markdown) == #"[Vec\<T> & \`Option\<\_>\`](<https://example.com/a_b>)"# + "\n"
                   + #"[https://example.com/\_next/a_b?x=1&y=2](<https://example.com/_next/a_b?x=1&y=2>)"#, "Markdown copies escape every label, including the address standing in for a blank title, and keep destinations as they were")
    }
}
