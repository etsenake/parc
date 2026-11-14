import Foundation

var count = 0
func check(_ value: @autoclosure () -> Bool, _ description: String) {
    count += 1
    guard value() else { fatalError("SidebarPreviewTitles: \(description)") }
}
func url(_ string: String) -> URL { URL(string: string)! }

let rules: [String: [TidyTitleRule]] = ["example.com": [
    TidyTitleRule(match: .pathEquals("/"), title: .always("Example")),
    TidyTitleRule(match: .fragmentEquals("inbox"), title: .always("Inbox")),
    TidyTitleRule(match: .fragmentContainsRegex("^label/.+"), title: .removing([" - .+$"])),
    TidyTitleRule(match: .pathContainsRegex("^/blank"), title: .removing([".*"])),
    TidyTitleRule(match: nil, title: .removing(["^\\([0-9]+\\)\\s", " \\| Example$"])),
]]
check(TidyTitles.title(for: url("https://www.example.com/"), title: "Home", rules: rules) == "Example", "www. stripped; pathEquals root")
check(TidyTitles.title(for: url("https://example.com"), title: "Home", rules: rules) == "Example", "empty path is root")
check(TidyTitles.title(for: url("https://example.com/x#inbox"), title: "x", rules: rules) == "Inbox", "fragmentEquals")
check(TidyTitles.title(for: url("https://example.com/x#label/work"), title: "Work - Mail", rules: rules) == "Work", "fragment regex removal")
check(TidyTitles.title(for: url("https://example.com/blank"), title: "Gone", rules: rules) == nil, "blank result falls back")
check(TidyTitles.title(for: url("https://example.com/p"), title: "(3) Page | Example", rules: rules) == "Page", "unconditional patterns in order")
check(TidyTitles.title(for: url("https://other.com/p"), title: "Page", rules: rules) == nil, "unknown host")
check(TidyTitles.title(for: url("https://example.com/p"), title: " Page ", rules: ["example.com": [TidyTitleRule(match: nil, title: .removing(["x"]))]]) == " Page ", "untrimmed result kept")

check(TidyTitles.title(for: url("https://www.notion.so/Roadmap-0123456789abcdef0123456789abcdef"), title: "(2) Roadmap | Notion") == "Roadmap", "Notion count and suffix")
check(TidyTitles.title(for: url("https://www.notion.so/"), title: "Anything") == "Notion", "Notion root")
check(TidyTitles.title(for: url("https://www.figma.com/design/abc/Board"), title: "Board – Figma") == "Board", "Figma suffix")
check(TidyTitles.title(for: url("https://www.figma.com/files/recent"), title: "x") == "Recently Viewed", "Figma recent files")

let linear = url("https://linear.app/acme/issue/ENG-123/fix-the-thing")
check(RecentPageText.linearTicketID(linear) == "ENG-123", "Linear ticket id from five components")
check(RecentPageText.linearTicketID(url("https://linear.app/acme/issue/ENG-123")) == nil, "Linear needs the slug component")
check(RecentPageText.tidyTitle(.linear, url: linear, title: "ENG-123 Fix the thing") == "Fix the thing", "Linear id prefix stripped")
check(RecentPageText.tidyTitle(.linear, url: linear, title: "Fix the thing") == "Fix the thing", "Linear without prefix unchanged")
check(RecentPageText.tidyTitle(.linear, url: linear, title: "  Fix the thing ") == "Fix the thing", "Linear titles always trimmed")
let confluence = url("https://acme.atlassian.net/wiki/spaces/ENG/pages/1/Plan")
check(RecentPageText.tidyTitle(.confluence, url: confluence, title: "Plan - Engineering - Confluence") == "Plan", "Confluence drops space and suffix")
check(RecentPageText.tidyTitle(.confluence, url: confluence, title: "Plan - Confluence") == "Plan", "Confluence two parts")
check(RecentPageText.tidyTitle(.confluence, url: confluence, title: "A - B - C - Confluence") == "A - B", "Confluence keeps leading parts")
check(RecentPageText.tidyTitle(.confluence, url: confluence, title: "Plan - Draft") == "Plan - Draft", "Confluence without suffix unchanged")
check(RecentPageText.tidyTitle(.figma, url: url("https://figma.com/file/x/y"), title: "y – Figma") == "y", "Figma via rules")

let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
check(RecentPageText.relativeTime(now.addingTimeInterval(-59), now: now) == "Just now", "under a minute is Just now")
check(RecentPageText.relativeTime(now.addingTimeInterval(59), now: now) == "Just now", "absolute interval")
check(RecentPageText.relativeTime(now.addingTimeInterval(-120), now: now) != "Just now", "older uses the formatter")
check(RecentPageText.subtitle(url: linear, visitedAt: now.addingTimeInterval(-5), now: now) == "ENG-123 • Just now", "Linear subtitle prefix")
check(RecentPageText.subtitle(url: confluence, visitedAt: now, now: now) == "Just now", "plain subtitle")

struct Row { let title: String; let url: URL }
let rows = [
    Row(title: "Plan", url: url("https://www.notion.so/Plan-0123456789abcdef0123456789abcdef")),
    Row(title: "Plan", url: url("https://www.notion.so/Other-fedcba9876543210fedcba9876543210")),
    Row(title: "Renamed plan", url: url("https://www.notion.so/x-0123456789abcdef0123456789abcdef")),
    Row(title: "File A", url: url("https://figma.com/file/a/A")),
    Row(title: "File B", url: url("https://figma.com/file/b/B")),
]
let kept = RecentPageText.deduplicated(rows, title: \.title, url: \.url).map(\.title)
check(kept == ["Plan", "File A", "File B"], "title then identity dedupe keeps unrecognized pages apart")
check(RecentPageText.pageIdentity(url("https://acme.notion.site/Doc-0123456789ABCDEF0123456789ABCDEF")) == "notion:0123456789abcdef0123456789abcdef", "Notion identity normalized")
check(RecentPageText.pageIdentity(url("https://figma.com/file/a")) == nil, "Figma has no identity")

check(RecentPageText.rowMenu(linear) == .linearIssue(id: "ENG-123"), "a Linear ticket copies its ID and URL")
check(RecentPageText.rowMenu(url("https://www.linear.app/acme/issue/ENG-9/x")) == .linearIssue(id: "ENG-9"), "www. is stripped")
check(RecentPageText.rowMenu(url("https://linear.app/acme/issue/ENG-123")) == .copyURL
      && RecentPageText.rowMenu(url("https://linear.app/acme/projects")) == .copyURL, "other Linear pages are unrecognized")
check(RecentPageText.rowMenu(url("https://acme.linear.app/acme/issue/ENG-1/x")) == .copyURL, "the Linear host must match exactly")
check(RecentPageText.rowMenu(url("https://www.notion.so/Plan-0123456789abcdef0123456789abcdef")) == .none
      && RecentPageText.rowMenu(url("https://notion.so/team/0123456789ABCDEF0123456789ABCDEF")) == .none, "a Notion page has no menu")
check(RecentPageText.rowMenu(url("https://www.notion.so/")) == .copyURL
      && RecentPageText.rowMenu(url("https://www.notion.so/Plan-0123")) == .copyURL, "a Notion URL without a page ID copies its URL")
check(RecentPageText.rowMenu(url("https://acme.notion.site/Doc-0123456789abcdef0123456789abcdef")) == .copyURL,
      "notion.site is not the Notion host")
check(RecentPageText.rowMenu(url("https://www.figma.com/design/a/Board")) == .copyURL && RecentPageText.rowMenu(confluence) == .copyURL,
      "Figma and Confluence copy their URL")

typealias M = SidebarPreviewModifiers
check(M(eventFlags: 1 << 17 | 1 << 18 | 1 << 19 | 1 << 20) == [.shift, .control, .option, .command]
      && M(eventFlags: 1 << 17 | 1 << 18 | 1 << 19 | 1 << 20).rawValue == 0xF, "shift 1, control 2, option 4, command 8")
check(M(eventFlags: 1 << 16 | 1 << 21 | 1 << 22 | 1 << 23).rawValue == 0xF0, "capsLock, numericPad, help and function high bits")
check(M(eventFlags: 1 << 20 | 1 << 16 | 1 << 23 | 0xFFFF).normalized == .command, "normalization masks 0xF0 and ignores device bits")

let recent = SidebarPreviewActivation.recentPage
check(recent([]) == .navigateSource(split: false) && recent([.shift, .control]) == .navigateSource(split: false), "plain routes the source tab")
check(recent(.option) == .navigateSource(split: true) && recent([.option, .shift]) == .navigateSource(split: true), "Option asks for split")
check(recent(.command) == .openNewTab(split: false) && recent([.command, .shift, .capsLock]) == .openNewTab(split: false), "Command opens a new tab")
check(recent([.command, .option]) == .openNewTab(split: true), "Command-Option opens a new tab in split")
check([recent([]), recent(.option), recent(.command), recent([.command, .option])].allSatisfy(\.dismissesPreview), "recent routes dismiss")

let folder = SidebarPreviewActivation.folderItem
check(folder([]) == .selectOriginal(split: false) && folder(.shift) == .selectOriginal(split: false)
      && folder(.control) == .selectOriginal(split: false), "other modifiers select the original")
check(folder(.option) == .selectOriginal(split: true) && folder([.option, .capsLock, .function]) == .selectOriginal(split: true), "exact Option splits")
check(folder([.option, .shift]) == .selectOriginal(split: false) && folder([.option, .control]) == .selectOriginal(split: false), "inexact Option does not split")
check(folder([.option, .command]) == .excludedMiniWindow && folder([.option, .command, .numericPad]) == .excludedMiniWindow, "Option-Command is the excluded mini browser window")
check(folder([.command, .shift]) == .duplicate && folder([.command, .shift, .capsLock]) == .duplicate, "exact Command-Shift duplicates")
check(folder(.command) == .reveal && folder([.command, .control]) == .reveal && folder([.command, .option, .shift]) == .reveal,
      "other Command combinations reveal")
check(folder([]).dismissesPreview && folder(.option).dismissesPreview, "selection dismisses")
check(!folder([.command, .shift]).dismissesPreview && !folder(.command).dismissesPreview && !folder([.option, .command]).dismissesPreview,
      "Command routes keep the preview")

func route(_ target: String, saved: Bool = true, split: Bool = false, current: String? = "www.notion.so",
           savedHost: String? = "www.notion.so", unlocked: Bool = false) -> SidebarPreviewSourceRoute {
    .route(to: url(target), isSavedItem: saved, inSplit: split, currentHost: current, savedHost: savedHost, authenticationUnlocked: unlocked)
}
check(route("https://acme.notion.site/x", saved: false) == .inPlace, "Today navigates in place")
check(route("https://www.notion.so/x") == .inPlace, "saved item keeps its current host in place")
check(route("https://acme.notion.site/x", current: "acme.notion.site", savedHost: "www.notion.so") == .inPlace, "current host")
check(route("https://acme.notion.site/x", current: "www.notion.so", savedHost: "acme.notion.site") == .inPlace, "saved host")
check(route("https://acme.notion.site/x") == .newTab, "saved item on another host creates a tab")
check(route("https://acme.notion.site/x", split: true) == .inPlace && route("https://acme.notion.site/x", unlocked: true) == .inPlace,
      "split sources and unlocked authentication stay in place")
print("SidebarPreviewTitles: \(count) assertions passed")
