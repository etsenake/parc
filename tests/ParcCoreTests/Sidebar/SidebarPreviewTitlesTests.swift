import Foundation
import Testing
@testable import ParcCore

struct SidebarPreviewTitlesTests {
    func url(_ string: String) -> URL { URL(string: string)! }
    var linear: URL { url("https://linear.app/acme/issue/ENG-123/fix-the-thing") }
    var confluence: URL { url("https://acme.atlassian.net/wiki/spaces/ENG/pages/1/Plan") }
    let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    @Test func tidyTitleRulesApplyInOrderWithHostNormalization() {
        let rules: [String: [TidyTitleRule]] = ["example.com": [
            TidyTitleRule(match: .pathEquals("/"), title: .always("Example")),
            TidyTitleRule(match: .fragmentEquals("inbox"), title: .always("Inbox")),
            TidyTitleRule(match: .fragmentContainsRegex("^label/.+"), title: .removing([" - .+$"])),
            TidyTitleRule(match: .pathContainsRegex("^/blank"), title: .removing([".*"])),
            TidyTitleRule(match: nil, title: .removing(["^\\([0-9]+\\)\\s", " \\| Example$"])),
        ]]
        #expect(TidyTitles.title(for: url("https://www.example.com/"), title: "Home", rules: rules) == "Example", "www. stripped; pathEquals root")
        #expect(TidyTitles.title(for: url("https://example.com"), title: "Home", rules: rules) == "Example", "empty path is root")
        #expect(TidyTitles.title(for: url("https://example.com/x#inbox"), title: "x", rules: rules) == "Inbox", "fragmentEquals")
        #expect(TidyTitles.title(for: url("https://example.com/x#label/work"), title: "Work - Mail", rules: rules) == "Work", "fragment regex removal")
        #expect(TidyTitles.title(for: url("https://example.com/blank"), title: "Gone", rules: rules) == nil, "blank result falls back")
        #expect(TidyTitles.title(for: url("https://example.com/p"), title: "(3) Page | Example", rules: rules) == "Page", "unconditional patterns in order")
        #expect(TidyTitles.title(for: url("https://other.com/p"), title: "Page", rules: rules) == nil, "unknown host")
        #expect(TidyTitles.title(for: url("https://example.com/p"), title: " Page ", rules: ["example.com": [TidyTitleRule(match: nil, title: .removing(["x"]))]]) == " Page ", "untrimmed result kept")
    }

    @Test func knownSitesTidyTheirTitles() {
        #expect(TidyTitles.title(for: url("https://www.notion.so/Roadmap-0123456789abcdef0123456789abcdef"), title: "(2) Roadmap | Notion") == "Roadmap", "Notion count and suffix")
        #expect(TidyTitles.title(for: url("https://www.notion.so/"), title: "Anything") == "Notion", "Notion root")
        #expect(TidyTitles.title(for: url("https://www.figma.com/design/abc/Board"), title: "Board – Figma") == "Board", "Figma suffix")
        #expect(TidyTitles.title(for: url("https://www.figma.com/files/recent"), title: "x") == "Recently Viewed", "Figma recent files")
    }

    @Test func linearAndConfluenceTitlesAreTidied() {
        #expect(RecentPageText.linearTicketID(linear) == "ENG-123", "Linear ticket id from five components")
        #expect(RecentPageText.linearTicketID(url("https://linear.app/acme/issue/ENG-123")) == nil, "Linear needs the slug component")
        #expect(RecentPageText.tidyTitle(.linear, url: linear, title: "ENG-123 Fix the thing") == "Fix the thing", "Linear id prefix stripped")
        #expect(RecentPageText.tidyTitle(.linear, url: linear, title: "Fix the thing") == "Fix the thing", "Linear without prefix unchanged")
        #expect(RecentPageText.tidyTitle(.linear, url: linear, title: "  Fix the thing ") == "Fix the thing", "Linear titles always trimmed")
        #expect(RecentPageText.tidyTitle(.confluence, url: confluence, title: "Plan - Engineering - Confluence") == "Plan", "Confluence drops space and suffix")
        #expect(RecentPageText.tidyTitle(.confluence, url: confluence, title: "Plan - Confluence") == "Plan", "Confluence two parts")
        #expect(RecentPageText.tidyTitle(.confluence, url: confluence, title: "A - B - C - Confluence") == "A - B", "Confluence keeps leading parts")
        #expect(RecentPageText.tidyTitle(.confluence, url: confluence, title: "Plan - Draft") == "Plan - Draft", "Confluence without suffix unchanged")
        #expect(RecentPageText.tidyTitle(.figma, url: url("https://figma.com/file/x/y"), title: "y – Figma") == "y", "Figma via rules")
    }

    @Test func relativeTimeAndSubtitlesDescribeRecentPages() {
        #expect(RecentPageText.relativeTime(now.addingTimeInterval(-59), now: now) == "Just now", "under a minute is Just now")
        #expect(RecentPageText.relativeTime(now.addingTimeInterval(59), now: now) == "Just now", "absolute interval")
        #expect(RecentPageText.relativeTime(now.addingTimeInterval(-120), now: now) != "Just now", "older uses the formatter")
        #expect(RecentPageText.subtitle(url: linear, visitedAt: now.addingTimeInterval(-5), now: now) == "ENG-123 • Just now", "Linear subtitle prefix")
        #expect(RecentPageText.subtitle(url: confluence, visitedAt: now, now: now) == "Just now", "plain subtitle")
    }

    @Test func recentPagesAreDeduplicatedByTitleThenIdentity() {
        struct Row { let title: String; let url: URL }
        let rows = [
            Row(title: "Plan", url: url("https://www.notion.so/Plan-0123456789abcdef0123456789abcdef")),
            Row(title: "Plan", url: url("https://www.notion.so/Other-fedcba9876543210fedcba9876543210")),
            Row(title: "Renamed plan", url: url("https://www.notion.so/x-0123456789abcdef0123456789abcdef")),
            Row(title: "File A", url: url("https://figma.com/file/a/A")),
            Row(title: "File B", url: url("https://figma.com/file/b/B")),
        ]
        let kept = RecentPageText.deduplicated(rows, title: \.title, url: \.url).map(\.title)
        #expect(kept == ["Plan", "File A", "File B"], "title then identity dedupe keeps unrecognized pages apart")
        #expect(RecentPageText.pageIdentity(url("https://acme.notion.site/Doc-0123456789ABCDEF0123456789ABCDEF")) == "notion:0123456789abcdef0123456789abcdef", "Notion identity normalized")
        #expect(RecentPageText.pageIdentity(url("https://figma.com/file/a")) == nil, "Figma has no identity")
    }

    @Test func rowMenusFollowTheRecognizedSite() {
        #expect(RecentPageText.rowMenu(linear) == .linearIssue(id: "ENG-123"), "a Linear ticket copies its ID and URL")
        #expect(RecentPageText.rowMenu(url("https://www.linear.app/acme/issue/ENG-9/x")) == .linearIssue(id: "ENG-9"), "www. is stripped")
        #expect(RecentPageText.rowMenu(url("https://linear.app/acme/issue/ENG-123")) == .copyURL
              && RecentPageText.rowMenu(url("https://linear.app/acme/projects")) == .copyURL, "other Linear pages are unrecognized")
        #expect(RecentPageText.rowMenu(url("https://acme.linear.app/acme/issue/ENG-1/x")) == .copyURL, "the Linear host must match exactly")
        #expect(RecentPageText.rowMenu(url("https://www.notion.so/Plan-0123456789abcdef0123456789abcdef")) == .none
              && RecentPageText.rowMenu(url("https://notion.so/team/0123456789ABCDEF0123456789ABCDEF")) == .none, "a Notion page has no menu")
        #expect(RecentPageText.rowMenu(url("https://www.notion.so/")) == .copyURL
              && RecentPageText.rowMenu(url("https://www.notion.so/Plan-0123")) == .copyURL, "a Notion URL without a page ID copies its URL")
        #expect(RecentPageText.rowMenu(url("https://acme.notion.site/Doc-0123456789abcdef0123456789abcdef")) == .copyURL,
              "notion.site is not the Notion host")
        #expect(RecentPageText.rowMenu(url("https://www.figma.com/design/a/Board")) == .copyURL && RecentPageText.rowMenu(confluence) == .copyURL,
              "Figma and Confluence copy their URL")
    }

    @Test func modifierFlagsNormalizeToThePreviewModifiers() {
        typealias M = SidebarPreviewModifiers
        #expect(M(eventFlags: 1 << 17 | 1 << 18 | 1 << 19 | 1 << 20) == [.shift, .control, .option, .command]
              && M(eventFlags: 1 << 17 | 1 << 18 | 1 << 19 | 1 << 20).rawValue == 0xF, "shift 1, control 2, option 4, command 8")
        #expect(M(eventFlags: 1 << 16 | 1 << 21 | 1 << 22 | 1 << 23).rawValue == 0xF0, "capsLock, numericPad, help and function high bits")
        #expect(M(eventFlags: 1 << 20 | 1 << 16 | 1 << 23 | 0xFFFF).normalized == .command, "normalization masks 0xF0 and ignores device bits")
    }

    @Test func recentPageActivationFollowsTheModifiers() {
        let recent = SidebarPreviewActivation.recentPage
        #expect(recent([]) == .navigateSource(split: false) && recent([.shift, .control]) == .navigateSource(split: false), "plain routes the source tab")
        #expect(recent(.option) == .navigateSource(split: true) && recent([.option, .shift]) == .navigateSource(split: true), "Option asks for split")
        #expect(recent(.command) == .openNewTab(split: false) && recent([.command, .shift, .capsLock]) == .openNewTab(split: false), "Command opens a new tab")
        #expect(recent([.command, .option]) == .openNewTab(split: true), "Command-Option opens a new tab in split")
        #expect([recent([]), recent(.option), recent(.command), recent([.command, .option])].allSatisfy { $0.dismissesPreview }, "recent routes dismiss")
    }

    @Test func folderItemActivationFollowsTheModifiers() {
        let folder = SidebarPreviewActivation.folderItem
        #expect(folder([]) == .selectOriginal(split: false) && folder(.shift) == .selectOriginal(split: false)
              && folder(.control) == .selectOriginal(split: false), "other modifiers select the original")
        #expect(folder(.option) == .selectOriginal(split: true) && folder([.option, .capsLock, .function]) == .selectOriginal(split: true), "exact Option splits")
        #expect(folder([.option, .shift]) == .selectOriginal(split: false) && folder([.option, .control]) == .selectOriginal(split: false), "inexact Option does not split")
        #expect(folder([.option, .command]) == .excludedMiniWindow && folder([.option, .command, .numericPad]) == .excludedMiniWindow, "Option-Command is the excluded mini browser window")
        #expect(folder([.command, .shift]) == .duplicate && folder([.command, .shift, .capsLock]) == .duplicate, "exact Command-Shift duplicates")
        #expect(folder(.command) == .reveal && folder([.command, .control]) == .reveal && folder([.command, .option, .shift]) == .reveal,
              "other Command combinations reveal")
        #expect(folder([]).dismissesPreview && folder(.option).dismissesPreview, "selection dismisses")
        #expect(!folder([.command, .shift]).dismissesPreview && !folder(.command).dismissesPreview && !folder([.option, .command]).dismissesPreview,
              "Command routes keep the preview")
    }

    @Test func savedItemsNavigateInPlaceOnlyWithinTheirHostsOrSplitOrUnlocked() {
        func route(_ target: String, saved: Bool = true, split: Bool = false, current: String? = "www.notion.so",
                   savedHost: String? = "www.notion.so", unlocked: Bool = false) -> SidebarPreviewSourceRoute {
            .route(to: url(target), isSavedItem: saved, inSplit: split, currentHost: current, savedHost: savedHost, authenticationUnlocked: unlocked)
        }
        #expect(route("https://acme.notion.site/x", saved: false) == .inPlace, "Today navigates in place")
        #expect(route("https://www.notion.so/x") == .inPlace, "saved item keeps its current host in place")
        #expect(route("https://acme.notion.site/x", current: "acme.notion.site", savedHost: "www.notion.so") == .inPlace, "current host")
        #expect(route("https://acme.notion.site/x", current: "www.notion.so", savedHost: "acme.notion.site") == .inPlace, "saved host")
        #expect(route("https://acme.notion.site/x") == .newTab, "saved item on another host creates a tab")
        #expect(route("https://acme.notion.site/x", split: true) == .inPlace && route("https://acme.notion.site/x", unlocked: true) == .inPlace,
              "split sources and unlocked authentication stay in place")
    }
}
