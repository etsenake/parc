import AppKit
import Testing
@testable import Parc
@testable import ParcCore

@MainActor
struct SidebarPreviewHeaderTests {
    private let url = URL(string: "https://www.coastalfieldnotes.org/tide-pools")!
    private let title = "Tide pools of the Pacific coast: a field guide to every rock and creature"
    private var row: SidebarPreviewRow { SidebarPreviewRow(id: "tab", tabID: UUID(), title: "Tide pools", url: url, visitedAt: nil) }

    private func all<T: NSView>(_ view: NSView, _ type: T.Type) -> [T] {
        view.subviews.flatMap { ($0 as? T).map { [$0] } ?? [] + all($0, type) }
    }

    @MainActor private final class Offer {
        var asked: [SidebarPreviewRow] = []
        var offered = true
    }

    private func card(_ row: SidebarPreviewRow, width: CGFloat = 288, offers: ((SidebarPreviewRow) -> Bool)?) -> SidebarPreviewCard {
        let card = SidebarPreviewCard(title: title, domain: nil, providerURL: url, picture: NSImage(size: NSSize(width: 320, height: 200)),
                                      site: "coastalfieldnotes.org", resources: .module)
        card.offersPeek = offers
        card.setRows([row])
        card.frame = NSRect(x: 0, y: 0, width: width, height: card.preferredHeight(width: width))
        card.layoutSubtreeIfNeeded()
        return card
    }

    private func button(_ card: SidebarPreviewCard, _ label: String) -> ActionButton? { all(card, ActionButton.self).first { $0.accessibilityLabel() == label } }
    private func text(_ card: SidebarPreviewCard, _ value: String) -> NSTextField? { all(card, NSTextField.self).first { $0.stringValue == value } }
    private let todaySplit = NSRect(x: 256, y: 16, width: 24, height: 24)

    @Test func withoutAPeekOfferTheHeaderHasOnlySplitView() {
        let plain = card(row, offers: nil)
        #expect(button(plain, "Open in Peek") == nil)
        #expect(all(plain, ActionButton.self).map { $0.accessibilityLabel() } == ["Open in Split View"])
    }

    @Test func aDeclinedOfferShowsNoOpenInPeekButton() {
        #expect(button(card(row, offers: { _ in false }), "Open in Peek") == nil)
    }

    @Test(arguments: [true, false])
    func splitViewStaysAtTheHeadersRightEdgeAndTitleAndSiteKeepTodaysWidth(noOffer: Bool) {
        let c = card(row, offers: noOffer ? nil : { _ in false })
        #expect(button(c, "Open in Split View")?.frame == todaySplit)
        #expect(text(c, title)?.frame == NSRect(x: 37, y: 12, width: 211, height: 17))
        #expect(text(c, "coastalfieldnotes.org")?.frame == NSRect(x: 37, y: 29, width: 211, height: 14))
    }

    @Test func thePeekOfferIsAskedAboutTheCardsOwnTab() {
        let offer = Offer()
        let row = row
        let c = card(row, offers: { offer.asked.append($0); return offer.offered })
        #expect(button(c, "Open in Peek") != nil)
        #expect(offer.asked.last == row)
    }

    @Test func openInPeekSitsDirectlyLeftOfSplitViewOnTheRecentsHeadersPitch() {
        let c = card(row, offers: { _ in true })
        #expect(button(c, "Open in Peek")?.frame == NSRect(x: 230, y: 16, width: 24, height: 24))
        #expect(button(c, "Open in Split View")?.frame == todaySplit)
    }

    @Test func theOpenInPeekArtworkIsASixteenPointTemplate() throws {
        let artwork = try #require(SidebarPreviewArtwork.openInPeek(in: .module))
        #expect(artwork.isTemplate)
        #expect(artwork.size == NSSize(width: 16, height: 16))
    }

    @Test func theArtworkCombinesTheOneAndTwoTimesBitmapsWithTheVector() throws {
        let representations = try #require(SidebarPreviewArtwork.openInPeek(in: .module)).representations
        #expect(representations.contains { $0.pixelsWide == 16 })
        #expect(representations.contains { $0.pixelsWide == 32 })
        #expect(representations.contains { $0 is NSPDFImageRep })
    }

    @Test func aBundleWithoutTheArtworkGivesNone() throws {
        let empty = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: empty) }
        let bundle = try #require(Bundle(url: empty))
        #expect(SidebarPreviewArtwork.openInPeek(in: bundle) == nil)
    }

    @Test func openInPeekShowsTheArtworkAlone() {
        let peek = button(card(row, offers: { _ in true }), "Open in Peek")
        #expect(peek?.image === SidebarPreviewArtwork.openInPeek(in: .module))
        #expect(peek?.imagePosition == .imageOnly)
        #expect(peek?.title == "")
        #expect(peek?.accessibilityLabel() == "Open in Peek")
    }

    @Test func openInPeekMatchesSplitViewsFocusRingAndTint() {
        let c = card(row, offers: { _ in true })
        let peek = button(c, "Open in Peek")
        let split = button(c, "Open in Split View")
        #expect(peek?.focusRingType == .exterior)
        #expect(peek?.focusRingCornerRadius == split?.focusRingCornerRadius)
        #expect(peek?.contentTintColor == split?.contentTintColor)
    }

    @Test func bothHeaderButtonsShowTheHoverPlate() {
        let c = card(row, offers: { _ in true })
        #expect(button(c, "Open in Peek")?.showsHoverFill == true)
        #expect(button(c, "Open in Split View")?.showsHoverFill == true)
    }

    @Test func titleAndSiteEndEightPointsBeforeOpenInPeek() {
        let c = card(row, offers: { _ in true })
        #expect(text(c, title)?.frame == NSRect(x: 37, y: 12, width: 185, height: 17))
        #expect(text(c, "coastalfieldnotes.org")?.frame == NSRect(x: 37, y: 29, width: 185, height: 14))
    }

    @Test func titleAndSiteTruncateAtTheTail() {
        let c = card(row, offers: { _ in true })
        #expect(text(c, title)?.lineBreakMode == .byTruncatingTail)
        #expect(text(c, "coastalfieldnotes.org")?.lineBreakMode == .byTruncatingTail)
    }

    @Test func theFixtureTitleIsLongEnoughToNeedTruncating() {
        let heading = text(card(row, offers: { _ in true }), title)
        #expect((heading?.attributedStringValue.size().width ?? 0) > heading?.frame.width ?? .infinity)
    }

    @Test func openInPeekOpensTheTabInAPeek() {
        let row = row
        let c = card(row, offers: { _ in true })
        var actions: [SidebarPreviewAction] = []
        c.onAction = { value, action in if value == row { actions.append(action) } }
        button(c, "Open in Peek")?.performClick(nil)
        #expect(actions == [.peek])
    }

    @Test func splitViewStillOpensTheTabInSplitView() {
        let row = row
        let c = card(row, offers: { _ in true })
        var actions: [SidebarPreviewAction] = []
        c.onAction = { value, action in if value == row { actions.append(action) } }
        button(c, "Open in Split View")?.performClick(nil)
        #expect(actions == [.split])
    }

    @Test func aClickAfterTheOfferLapsesDoesNothingAndHidesTheButton() {
        let offer = Offer()
        let row = row
        let c = card(row, offers: { _ in offer.offered })
        var actions: [SidebarPreviewAction] = []
        c.onAction = { _, action in actions.append(action) }
        let peek = button(c, "Open in Peek")
        offer.offered = false
        peek?.performClick(nil)
        c.layoutSubtreeIfNeeded()
        #expect(actions.isEmpty)
        #expect(button(c, "Open in Peek") == nil)
        #expect(text(c, title)?.frame.width == 211)
    }

    @Test func aRefreshedSourceBringsTheButtonBackWhenPeekIsOfferedAgain() {
        let offer = Offer()
        let row = row
        let c = card(row, offers: { _ in offer.offered })
        offer.offered = false
        c.setRows([row])
        c.layoutSubtreeIfNeeded()
        offer.offered = true
        c.setRows([row])
        c.layoutSubtreeIfNeeded()
        #expect(button(c, "Open in Peek")?.frame == NSRect(x: 230, y: 16, width: 24, height: 24))
        #expect(text(c, title)?.frame.width == 185)
    }

    @Test func aRefreshedSourceDropsTheButtonWhenPeekIsNoLongerOffered() {
        let offer = Offer()
        let row = row
        let c = card(row, offers: { _ in offer.offered })
        offer.offered = false
        c.setRows([row])
        c.layoutSubtreeIfNeeded()
        #expect(button(c, "Open in Peek") == nil)
        #expect(text(c, title)?.frame.width == 211)
    }

    @Test func aRenderTimeRefreshShowsTheButtonOnceTheOfferReturns() {
        let offer = Offer()
        let c = card(row, offers: { _ in offer.offered })
        offer.offered = false
        c.refreshPeek()
        offer.offered = true
        c.refreshPeek()
        c.layoutSubtreeIfNeeded()
        #expect(button(c, "Open in Peek") != nil)
        #expect(text(c, title)?.frame.width == 185)
    }

    @Test func aRenderTimeRefreshHidesTheButtonOnceTheOfferLapses() {
        let offer = Offer()
        let c = card(row, offers: { _ in offer.offered })
        offer.offered = false
        c.refreshPeek()
        c.layoutSubtreeIfNeeded()
        #expect(button(c, "Open in Peek") == nil)
        #expect(text(c, title)?.frame.width == 211)
    }

    @Test func aNarrowedCardKeepsBothButtonsAndNarrowsTheTitle() {
        let narrow = card(row, width: 240, offers: { _ in true })
        #expect(button(narrow, "Open in Split View")?.frame.minX == 208)
        #expect(button(narrow, "Open in Peek")?.frame.minX == 182)
        #expect(text(narrow, title)?.frame.width == 137)
    }

    @Test func aRetiringCardKeepsItsHeaderStillWhileItFades() {
        let c = card(row, offers: { _ in true })
        let peek = button(c, "Open in Peek")
        c.retire()
        c.layoutSubtreeIfNeeded()
        #expect(peek?.superview != nil)
        #expect(text(c, title)?.frame.width == 185)
    }

    @Test func aRetiredCardsOpenInPeekDoesNothingAndItsHeaderStaysPut() {
        let c = card(row, offers: { _ in true })
        var actions: [SidebarPreviewAction] = []
        c.onAction = { _, action in actions.append(action) }
        let peek = button(c, "Open in Peek")
        c.retire()
        peek?.performClick(nil)
        c.refreshPeek()
        c.layoutSubtreeIfNeeded()
        #expect(actions.isEmpty)
        #expect(peek?.superview != nil)
        #expect(text(c, title)?.frame.width == 185)
    }

    @Test func theRecentsHeaderIsUnchanged() {
        let recents = SidebarPreviewCard(title: "Notion", domain: .notion, providerURL: URL(string: "https://www.notion.so")!)
        recents.offersPeek = { _ in true }
        recents.setRows([SidebarPreviewRow(id: "page", tabID: nil, title: "Plan", url: URL(string: "https://www.notion.so/Plan-1")!, visitedAt: nil)])
        #expect(Set(all(recents, ActionButton.self).compactMap { $0.accessibilityLabel() }) == ["New Page", "Previews Settings"])
        #expect(all(recents, ActionButton.self).allSatisfy { !$0.showsHoverFill })
    }

    @Test func thePeekAndSplitViewButtonsUseParcsOwnTooltip() {
        let c = card(row, offers: { _ in true })
        let peek = button(c, "Open in Peek"), split = button(c, "Open in Split View")
        #expect(peek?.parcTooltip?.label == "Open in Peek" && peek?.parcTooltip?.anchor == .bottom && peek?.toolTip == nil)
        #expect(split?.parcTooltip?.label == "Open in Split View" && split?.parcTooltip?.anchor == .bottom && split?.toolTip == nil)
    }

    @Test func theRecentsHeaderButtonsUseParcsOwnTooltip() {
        let recents = SidebarPreviewCard(title: "Notion", domain: .notion, providerURL: URL(string: "https://www.notion.so")!)
        recents.offersPeek = { _ in true }
        recents.setRows([SidebarPreviewRow(id: "page", tabID: nil, title: "Plan", url: URL(string: "https://www.notion.so/Plan-1")!, visitedAt: nil)])
        #expect(Set(all(recents, ActionButton.self).compactMap { $0.parcTooltip?.label }) == ["New Page", "Previews Settings"])
        #expect(all(recents, ActionButton.self).allSatisfy { $0.toolTip == nil && $0.parcTooltip?.anchor == .bottom })
    }

    private func documentCard(offers: ((SidebarPreviewRow) -> Bool)?, available: Bool = true) -> SidebarPreviewCard {
        let kind = SidebarDocumentKind(url: URL(fileURLWithPath: "/tmp/Plan.md"))!
        let card = SidebarPreviewCard(title: "Plan", domain: nil, providerURL: nil, site: "Note", document: kind)
        card.offersPeek = offers
        card.setRows([row])
        card.setDocument(.init(availability: available ? .available : .missing, snippet: "Hello"), picture: nil)
        card.frame = NSRect(x: 0, y: 0, width: 288, height: card.preferredHeight(width: 288))
        card.layoutSubtreeIfNeeded()
        return card
    }

    @Test func aNoteCardShowsOpenInPeekAndSplitViewButNoCopyLink() {
        let note = documentCard(offers: { _ in true })
        #expect(all(note, ActionButton.self).compactMap { $0.accessibilityLabel() }.sorted() == ["Open in Peek", "Open in Split View"])
    }

    @Test func aNoteCardsButtonsSitWhereAWebCardsDo() {
        let note = documentCard(offers: { _ in true })
        #expect(button(note, "Open in Peek")?.frame == NSRect(x: 230, y: 16, width: 24, height: 24))
        #expect(button(note, "Open in Split View")?.frame == todaySplit)
    }

    @Test func aNoteCardsTitleEndsEightPointsBeforeOpenInPeek() {
        #expect(text(documentCard(offers: { _ in true }), "Plan")?.frame.maxX == 222)
    }

    @Test func aNoteCardsButtonsUseParcsOwnTooltip() {
        let note = documentCard(offers: { _ in true })
        #expect(all(note, ActionButton.self).allSatisfy { $0.toolTip == nil && $0.parcTooltip?.label == $0.accessibilityLabel() })
    }

    @Test func aNoteCardsButtonsOpenAPeekAndSplitView() {
        let note = documentCard(offers: { _ in true })
        var actions: [SidebarPreviewAction] = []
        note.onAction = { _, action in actions.append(action) }
        button(note, "Open in Peek")?.performClick(nil)
        button(note, "Open in Split View")?.performClick(nil)
        #expect(actions == [.peek, .split])
    }

    @Test func aNoteCardDropsOpenInPeekWhenTheTabCannotOpenInAPeek() {
        let offer = Offer()
        let note = documentCard(offers: { _ in offer.offered })
        offer.offered = false
        note.refreshPeek(); note.layoutSubtreeIfNeeded()
        #expect(button(note, "Open in Peek") == nil)
        #expect(text(note, "Plan")?.frame.maxX == 248)
    }

    @Test func aNoteCardBringsOpenInPeekBackWhenItIsOfferedAgain() {
        let offer = Offer()
        let note = documentCard(offers: { _ in offer.offered })
        offer.offered = false
        note.refreshPeek(); note.layoutSubtreeIfNeeded()
        offer.offered = true
        note.refreshPeek(); note.layoutSubtreeIfNeeded()
        #expect(button(note, "Open in Peek") != nil)
    }

    @Test func aNoteCardWithoutAPeekOfferHasOnlySplitView() {
        #expect(all(documentCard(offers: nil), ActionButton.self).map { $0.accessibilityLabel() } == ["Open in Split View"])
    }

    @Test(arguments: [true, false])
    func aMissingNoteShowsNoButtons(peekOffered: Bool) {
        #expect(all(documentCard(offers: { _ in peekOffered }, available: false), ActionButton.self).isEmpty)
    }

    @Test func aFolderCardGetsNoHeaderButton() {
        let folder = SidebarPreviewCard(title: "Docs", domain: nil, providerURL: nil)
        folder.offersPeek = { _ in true }
        folder.setRows([row])
        #expect(all(folder, ActionButton.self).isEmpty)
    }
}
