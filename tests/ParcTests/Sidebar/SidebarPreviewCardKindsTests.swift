import AppKit
import Testing
@testable import Parc

@MainActor
struct SidebarPreviewCardKindsTests {
    final class FlippedHost: NSView { override var isFlipped: Bool { true } }

    private func all<T: NSView>(_ view: NSView, _ type: T.Type) -> [T] { SidebarPreviewFolderCardTests.all(view, type) }
    private func near(_ a: CGFloat, _ b: CGFloat) -> Bool { abs(a - b) < 0.001 }
    private let right = SidebarPreviewFolderCardTests.right
    private let provider = URL(string: "https://www.notion.so/team/doc")!
    private let pageURL = URL(string: "https://www.example.com/a")!
    private let now = Date()

    @MainActor final class Recents {
        let card: SidebarPreviewCard
        var requested: [URL] = [], created: [URL] = [], settings = 0
        init(provider: URL, now: Date) {
            card = SidebarPreviewCard(title: "Notion", domain: .notion, providerURL: provider)
            card.now = { now }
            card.requestFavicon = { [weak self] url, done in self?.requested.append(url); done(nil) }
            card.modifierFlags = { [.option] }
            card.onAction = { [weak self] row, action in if action == .create(.option) { self?.created.append(row.url) } }
            card.onSettings = { [weak self] in self?.settings += 1 }
            card.setRows([])
        }
    }

    @Test func theRecentsHeaderUsesTheProviderFaviconAndTitle() {
        let r = Recents(provider: provider, now: now)
        #expect(r.requested == [provider])
        #expect(all(r.card, NSTextField.self).contains { $0.stringValue == "Recents" })
    }

    @Test func emptyRecentsShowTheProviderEmptyStateWithoutSearch() {
        let r = Recents(provider: provider, now: now)
        #expect(all(r.card, NSTextField.self).contains { $0.stringValue == "Recent Notion docs appear here." && !$0.isHidden })
        #expect(!all(r.card, NSTextField.self).contains { $0.isEditable })
        #expect(all(r.card, SidebarPreviewDivider.self).isEmpty)
    }

    @Test func recentsOfferOnlyTheCreateButtonAndTheGear() {
        let r = Recents(provider: provider, now: now)
        let buttons = all(r.card, NSButton.self)
        #expect(buttons.map { $0.accessibilityLabel() ?? "" } == ["New Page", "Previews Settings"])
        buttons.forEach { $0.sendClick() }
        #expect(r.created == [URL(string: "https://notion.so/new")!] && r.settings == 1)
    }

    @Test func darkRecentsFillIsThePreviewBackgroundColor() {
        let r = Recents(provider: provider, now: now)
        var fill: NSColor?
        NSAppearance(named: .darkAqua)!.performAsCurrentDrawingAppearance { fill = r.card.fill?.usingColorSpace(.sRGB) }
        #expect(fill.map { near($0.redComponent, 0.129) && near($0.blueComponent, 0.133) } == true)
    }

    private func page(_ title: String, _ url: String, _ age: TimeInterval = 5) -> SidebarPreviewRow {
        SidebarPreviewRow(id: url, tabID: nil, title: title, url: URL(string: url)!, visitedAt: now.addingTimeInterval(-age))
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

    @Test func recentRowsHaveNoIconAndRequestNoFavicon() throws {
        let r = Recents(provider: provider, now: now)
        r.card.setRows(notionPages)
        let table = try #require(all(r.card, NSTableView.self).first)
        let cell = try #require(table.view(atColumn: 0, row: 0, makeIfNecessary: true) as? SidebarPreviewItemView)
        cell.frame = NSRect(x: 0, y: 0, width: 278, height: SidebarPreviewItemView.height); cell.layoutSubtreeIfNeeded()
        #expect(all(cell, NSImageView.self).isEmpty && cell.titleLabel.frame.minX == 10 && cell.subtitle.stringValue == "Just now")
        #expect(r.requested == [provider])
    }

    @Test func recentReturnCarriesTheHeldModifiers() throws {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 400), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let r = Recents(provider: provider, now: now)
        let pages = notionPages
        r.card.setRows(pages)
        window.contentView = r.card
        let table = try #require(all(r.card, NSTableView.self).first)
        table.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)
        var actions: [SidebarPreviewAction] = []
        r.card.onAction = { _, action in actions.append(action) }
        r.card.modifierFlags = { [.command, .option] }
        table.keyDown(with: NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.command, .option], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36)!)
        #expect(actions == [.activate([.command, .option])])
        #expect(actions.first?.activation(for: pages[1]) == .openNewTab(split: true))
    }

    @MainActor final class Pictured {
        let card: SidebarPreviewCard
        var icons: [URL] = [], actions: [SidebarPreviewAction] = [], resized = 0
        init(url: URL) {
            card = SidebarPreviewCard(title: "Example", domain: nil, providerURL: url, picture: NSImage(size: NSSize(width: 320, height: 200)),
                                      site: "example.com")
            card.requestFavicon = { [weak self] url, done in self?.icons.append(url); done(nil) }
            card.onAction = { [weak self] row, action in if row.tabID != nil { self?.actions.append(action) } }
            card.onHeightChange = { [weak self] in self?.resized += 1 }
            card.setRows([SidebarPreviewRow(id: "tab", tabID: UUID(), title: "Example", url: url, visitedAt: nil)])
        }
    }

    @Test func aPictureHeaderShowsTheTabsFaviconTitleAndSite() {
        let p = Pictured(url: pageURL)
        #expect(p.icons == [pageURL])
        let labels = all(p.card, NSTextField.self).map(\.stringValue)
        #expect(labels.contains("Example") && labels.contains("example.com"))
    }

    @Test func aPictureCardHasNoListAndOnlySplitView() {
        let p = Pictured(url: pageURL)
        #expect(all(p.card, NSScrollView.self).isEmpty && p.resized == 0)
        let buttons = all(p.card, NSButton.self)
        #expect(buttons.map { $0.accessibilityLabel() ?? "" } == ["Open in Split View"])
        buttons.forEach { $0.sendClick() }
        #expect(p.actions == [.split])
    }

    @Test func aPictureCardKeepsThePicturesAspect() {
        let p = Pictured(url: pageURL)
        #expect(p.card.fill != nil && p.card.preferredHeight(width: 288) == 56 + 168 + 10)
        #expect(near(p.card.preferredHeight(width: 240), 56 + 138 + 10))
    }

    @Test func titleAndSiteAreCentredInTheHeader() {
        let p = Pictured(url: pageURL)
        p.card.frame = NSRect(x: 0, y: 0, width: 288, height: 234); p.card.layout()
        let text = all(p.card, NSTextField.self)
        #expect(text.first { $0.stringValue == "Example" }?.frame.minY == 12)
        #expect(text.first { $0.stringValue == "example.com" }?.frame.minY == 29)
    }

    @Test func aTallerPictureIsCappedAndResizesTheCard() {
        let p = Pictured(url: pageURL)
        p.card.setPicture(NSImage(size: NSSize(width: 100, height: 400)))
        #expect(p.card.preferredHeight(width: 288) == 384 && p.resized == 1)
        p.card.frame = NSRect(x: 0, y: 0, width: 288, height: 384); p.card.layout()
        #expect(p.card.content.subviews.contains { $0.frame == NSRect(x: 10, y: 56, width: 268, height: 318) && $0.layer?.cornerRadius == 5 })
    }

    @Test func theHeaderFollowsTheTabsTitle() {
        let p = Pictured(url: pageURL)
        p.card.setHeading("Inbox (3)", site: "mail.example.com")
        #expect(all(p.card, NSTextField.self).map(\.stringValue).contains("Inbox (3)"))
    }

    @Test func aNarrowWindowNarrowsTheListCardAndWideningRestoresIt() {
        let host = FlippedHost(frame: NSRect(x: 0, y: 0, width: 500, height: 700))
        let folder = SidebarPreviewCard(title: "Docs", domain: nil, providerURL: nil)
        folder.setRows(SidebarPreviewFolderCardTests.rows); folder.placement = right
        host.addSubview(folder); folder.place()
        #expect(folder.frame == NSRect(x: 224, y: 124, width: 258, height: 384))
        host.frame.size.width = 1000; folder.place()
        #expect(folder.frame.width == 288)
    }

    @Test func aNarrowedPictureCardKeepsThePicturesAspect() {
        let host = FlippedHost(frame: NSRect(x: 0, y: 0, width: 500, height: 700))
        let picture = SidebarPreviewCard(title: "Example", domain: nil, providerURL: pageURL,
                                         picture: NSImage(size: NSSize(width: 320, height: 200)), site: "example.com")
        picture.placement = right
        host.addSubview(picture); picture.place(); picture.layoutSubtreeIfNeeded()
        #expect(picture.frame.size == NSSize(width: 258, height: 56 + 149 + 10))
        #expect(picture.content.subviews.contains { $0.frame == NSRect(x: 10, y: 56, width: 238, height: 149) })
    }

    @MainActor final class MenuStage {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 700), styleMask: [.borderless], backing: .buffered, defer: false)
        let host = FlippedHost(frame: NSRect(x: 0, y: 0, width: 1000, height: 700))
        let card: SidebarPreviewCard
        let menu: NSMenu?
        init(_ domain: SidebarRecentDomain?, _ row: SidebarPreviewRow, placement: SidebarPreviewPlacement) {
            window.isReleasedWhenClosed = false
            host.wantsLayer = true; window.contentView = host
            card = SidebarPreviewCard(title: "Menu", domain: domain, providerURL: nil)
            card.placement = placement; host.addSubview(card); card.place(); card.setRows([row])
            host.layoutSubtreeIfNeeded(); card.layoutSubtreeIfNeeded()
            let table = SidebarPreviewFolderCardTests.all(card, NSTableView.self).first!
            let point = table.convert(NSPoint(x: table.rect(ofRow: 0).midX, y: table.rect(ofRow: 0).midY), to: nil)
            let event = NSEvent.mouseEvent(with: .rightMouseDown, location: point, modifierFlags: [], timestamp: 0,
                                           windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
            menu = table.menu(for: event)
        }
        var titles: [String]? { menu?.items.map { $0.isSeparatorItem ? "—" : $0.title } }
        func choose() -> [SidebarPreviewAction] {
            var chosen: [SidebarPreviewAction] = []
            card.onAction = { _, action in chosen.append(action) }
            for item in menu?.items ?? [] where !item.isSeparatorItem { _ = (item.target as? NSObject)?.perform(item.action, with: item) }
            return chosen
        }
    }

    @Test func aFolderRowHasTheFolderPreviewMenu() {
        let s = MenuStage(nil, SidebarPreviewFolderCardTests.rows[0], placement: right)
        #expect(s.titles == ["Copy URL", "Open in Split View", "Duplicate", "—", "Archive"])
        #expect(s.choose() == [.copyURL, .split, .duplicate, .archive])
    }

    @Test func aLinearTicketRowCopiesItsIDOrURL() {
        let s = MenuStage(.linear, page("Fix it", "https://linear.app/acme/issue/ENG-7/fix-it"), placement: right)
        #expect(s.titles == ["Copy Issue ID", "Copy Issue URL"])
        #expect(s.choose() == [.copyIssueID("ENG-7"), .copyURL])
    }

    @Test func aRecognizedNotionPageRowHasNoMenu() {
        #expect(MenuStage(.notion, notionPages[0], placement: right).menu == nil)
    }

    @Test func anUnrecognizedPageRowCopiesItsURL() {
        let s = MenuStage(.figma, page("Board", "https://www.figma.com/design/a/Board"), placement: right)
        #expect(s.titles == ["Copy URL"])
        #expect(s.choose() == [.copyURL])
    }
}
