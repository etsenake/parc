import AppKit
import Testing
@testable import Parc
@testable import ParcCore

@MainActor
struct SidebarPreviewRowTextTests {
    private let now = Date()
    private let pageURL = URL(string: "https://www.example.com/a")!

    private func page(_ title: String, _ url: String, _ age: TimeInterval = 5) -> SidebarPreviewRow {
        SidebarPreviewRow(id: url, tabID: nil, title: title, url: URL(string: url)!, visitedAt: now.addingTimeInterval(-age))
    }

    private func visited(_ id: String, _ age: TimeInterval?) -> SidebarPreviewRow {
        SidebarPreviewRow(id: id, tabID: UUID(), title: id, url: URL(string: "https://example.com/" + id)!,
                          visitedAt: age.map { now.addingTimeInterval(-$0) })
    }

    private var notionPages: [SidebarPreviewRow] {
        SidebarPreviewRow.recentPages([
            page("(2) Roadmap | Notion", "https://www.notion.so/Roadmap-0123456789abcdef0123456789abcdef"),
            page("Roadmap", "https://www.notion.so/Old-fedcba9876543210fedcba9876543210"),
            page("Roadmap moved", "https://www.notion.so/r-0123456789abcdef0123456789abcdef"),
            page("Elsewhere", "https://example.com/notion"),
            page("Spec", "https://acme.notion.site/Spec", 3600),
        ], domain: .notion)
    }

    @Test func recentPagesTidyTitlesCheckTheProviderAndKeepTheFirstOccurrence() {
        #expect(notionPages.map(\.title) == ["Roadmap", "Spec"])
    }

    @Test func recentPagesShowARelativeVisitSubtitle() {
        let pages = notionPages
        #expect(pages.first?.subtitle(now: now) == "Just now" && pages.last?.subtitle(now: now) != "Just now")
    }

    @Test func aLinearIDMovesToTheSubtitle() {
        let issue = SidebarPreviewRow.recentPages([page("ENG-7 Fix it", "https://linear.app/acme/issue/ENG-7/fix-it")], domain: .linear)
        #expect(issue.map(\.title) == ["Fix it"] && issue.first?.subtitle(now: now) == "ENG-7 • Just now")
    }

    @Test func theConfluenceSuffixIsDropped() {
        let pages = SidebarPreviewRow.recentPages([page("Plan - Eng - Confluence", "https://acme.atlassian.net/wiki/spaces/E/pages/1")],
                                                  domain: .confluence)
        #expect(pages.map(\.title) == ["Plan"])
    }

    @Test func eachProviderHasItsCreateButtonAndEmptyState() {
        #expect(SidebarRecentDomain.allCases.map(\.createTitle) == ["New Page", "New File", "New Issue", "New Page"])
        #expect(SidebarRecentDomain.allCases.map(\.createURL.absoluteString)
                == ["https://notion.so/new", "https://figma.com/new", "https://linear.app/new", "https://confluence.new"])
        #expect(SidebarRecentDomain.allCases.map(\.emptyMessage) == ["Recent Notion docs appear here.", "Recent Figma files appear here.",
            "Recent Linear projects and issues appear here.", "Recent Confluence pages appear here."])
    }

    @Test func aFolderTitlePrefersTheCustomNameThenTheTidiedPageTitle() {
        let url = URL(string: "https://www.figma.com/design/a/Board")!
        #expect(SidebarPreviewRow.folderTitle(custom: "Mine", url: url, title: "Board – Figma") == "Mine")
        #expect(SidebarPreviewRow.folderTitle(custom: nil, url: url, title: "Board – Figma") == "Board")
        #expect(SidebarPreviewRow.folderTitle(custom: nil, url: URL(string: "https://example.com")!, title: "Raw") == "Raw")
    }

    @Test func folderRowsAreNewestFirstWithSidebarOrderForTies() {
        let rows = [visited("a", 60), visited("b", nil), visited("c", 5), visited("d", 60)]
        #expect(SidebarPreviewRow.newestFirst(rows).map(\.id) == ["c", "a", "d", "b"])
    }

    @Test func aFolderSubtitleIsTheVisitTimeWithoutALinearPrefix() {
        let older = visited("old", 7200)
        #expect(older.subtitle(now: now) == RecentPageText.relativeTime(older.visitedAt!, now: now))
        let linear = SidebarPreviewRow(id: "l", tabID: UUID(), title: "Fix it", url: URL(string: "https://linear.app/acme/issue/ENG-7/fix-it")!,
                                       visitedAt: now)
        #expect(linear.subtitle(now: now) == "Just now")
    }

    @Test func aBadgedRowSaysRecentlyAddedInBold() {
        var badged = visited("new", 5); badged.isBadged = true
        #expect(badged.subtitle(now: now) == "Recently Added")
        let cell = SidebarPreviewItemView(row: badged, title: .labelColor, secondary: .secondaryLabelColor, now: now)
        #expect(cell.subtitle.font == .boldSystemFont(ofSize: 11) && cell.subtitle.stringValue == "Recently Added")
    }

    @Test func folderRowsKeepTheirIcons() {
        let cell = SidebarPreviewItemView(row: visited("old", 7200), title: .labelColor, secondary: .secondaryLabelColor, now: now)
        #expect(cell.subtitle.font == .systemFont(ofSize: 11))
        #expect(!SidebarPreviewFolderCardTests.all(cell, NSImageView.self).isEmpty)
    }

    @Test func theRowKindSelectsTheRoute() {
        let older = visited("old", 7200), recent = notionPages[0]
        #expect(SidebarPreviewAction.activate(.option).activation(for: older) == .selectOriginal(split: true))
        #expect(SidebarPreviewAction.activate(.option).activation(for: recent) == .navigateSource(split: true))
        #expect(SidebarPreviewAction.create(.command).activation(for: recent) == .openNewTab(split: false))
        #expect(SidebarPreviewAction.split.activation(for: older) == nil)
    }

    private func pageSource(_ target: SidebarPreviewTarget, _ domain: SidebarRecentDomain?, profile: UUID = UUID(), space: UUID = UUID(),
                            title: String = "Example", url: URL? = nil) -> SidebarPreviewSource {
        SidebarPreviewSource(target: target, profileID: profile, spaceID: space, selectedTabIDs: [], focusedTabID: nil,
                             theme: SpaceTheme(), title: title, domain: domain, originalURL: url ?? pageURL, rows: [])
    }

    @Test func aPictureCardKeepsItsSessionAcrossTitleAndAddressChanges() {
        let target = SidebarPreviewTarget.tab(UUID()), profile = UUID(), space = UUID()
        let before = pageSource(target, nil, profile: profile, space: space)
        let renamed = pageSource(target, nil, profile: profile, space: space, title: "Inbox (3)", url: URL(string: "https://www.example.com/b")!)
        #expect(renamed.hasSameOwner(as: before))
    }

    @Test func movingOntoAProviderEndsThePictureCardsSession() {
        let target = SidebarPreviewTarget.tab(UUID()), profile = UUID(), space = UUID()
        let before = pageSource(target, nil, profile: profile, space: space)
        let notion = pageSource(target, .notion, profile: profile, space: space, title: "Notion", url: URL(string: "https://notion.so/doc")!)
        #expect(!notion.hasSameOwner(as: before))
    }

    @Test func onlyATabWithoutAProviderShowsItsPicture() {
        #expect(pageSource(.tab(UUID()), nil).showsPicture)
        #expect(!pageSource(.tab(UUID()), .notion).showsPicture)
        #expect(!pageSource(.folder(UUID()), nil).showsPicture)
    }

    @Test func onlyRowsMayRefreshWithinASession() {
        let target = SidebarPreviewTarget.folder(UUID()), profile = UUID(), space = UUID()
        func source(_ rows: [SidebarPreviewRow], selected: [UUID] = []) -> SidebarPreviewSource {
            SidebarPreviewSource(target: target, profileID: profile, spaceID: space, selectedTabIDs: selected, focusedTabID: nil,
                                 theme: SpaceTheme(), title: "Docs", domain: nil, originalURL: nil, rows: rows)
        }
        let older = visited("old", 7200)
        var badged = visited("new", 5); badged.isBadged = true
        #expect(source([older]).hasSameOwner(as: source([older, badged])))
        #expect(!source([older]).hasSameOwner(as: source([older], selected: [UUID()])))
    }
}
