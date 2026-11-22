import AppKit
import Testing
@testable import Parc
@testable import ParcCore
@testable import ParcKit
@testable import ParcSidebar

@MainActor
struct SpaceManagerCardTestsRowTests {
    private typealias Cards = SpaceManagerCardTestsSupport.Cards

    @Test func theIdleTitleLabelExtendsTwoPastTheInsetAndTheTrailingEdge() {
        let cards = Cards()
        let row = sidebarDescendants(cards.sidebar).compactMap { $0 as? SidebarTabRow }.first { $0.tabID == cards.today.id }!
        let title = sidebarDescendants(row).compactMap { $0 as? SidebarChromeLabel }.first { $0.stringValue == "today" }!
        let frame = title.convert(title.bounds, to: row)
        #expect(frame.minX == SidebarRowAppearance.titleInset - SidebarRowAppearance.titleTextPadding)
        #expect(frame.maxX == SidebarRowAppearance.titleTrailingEdge(in: row.bounds, closeVisible: false) + SidebarRowAppearance.titleTextPadding)
    }

    @Test func aRowBuildsItsRenameFieldForItsFirstRename() {
        let cards = Cards()
        let row = sidebarDescendants(cards.sidebar).compactMap { $0 as? SidebarTabRow }.first { $0.tabID == cards.today.id }!
        #expect(sidebarDescendants(row).allSatisfy { !($0 is SidebarTitleField) })
    }

    @Test func aHoveredTitlesTextStopsTwoBeforeTheCloseWithItsFrameAtTheClose() {
        let cards = Cards()
        let row = sidebarDescendants(cards.sidebar).compactMap { $0 as? SidebarTabRow }.first { $0.tabID == cards.today.id }!
        let title = sidebarDescendants(row).compactMap { $0 as? SidebarChromeLabel }.first { $0.stringValue == "today" }!
        cards.window.pointer = row.convert(NSPoint(x: row.bounds.midX, y: row.bounds.midY), to: nil)
        row.updateTrackingAreas()
        row.layoutSubtreeIfNeeded()
        let close = sidebarDescendants(row).compactMap { $0 as? SidebarRowActionButton }.first { $0.accessibilityLabel() == "Archive Tab" }!
        let frame = title.convert(title.bounds, to: row)
        #expect(!close.isHidden)
        #expect(frame.maxX == close.frame.minX)
        #expect(frame.maxX - SidebarRowAppearance.titleTextPadding < close.frame.minX)
    }

    @Test func renamingEditsFromTheTitlesFrameToEightInsideTheRow() {
        let cards = Cards()
        let row = sidebarDescendants(cards.sidebar).compactMap { $0 as? SidebarTabRow }.first { $0.tabID == cards.today.id }!
        let title = sidebarDescendants(row).compactMap { $0 as? SidebarChromeLabel }.first { $0.stringValue == "today" }!
        let titleFrame = title.convert(title.bounds, to: row)
        #expect(row.beginTitleEditing("today") { _ in })
        row.layoutSubtreeIfNeeded()
        let field = sidebarDescendants(row).compactMap { $0 as? SidebarTitleField }.first!
        let editing = field.convert(field.bounds, to: row)
        #expect(editing.minX == titleFrame.minX)
        #expect(editing.maxX == row.bounds.width - 8)
    }

    @Test func afterARenameTheFieldKeepsTheIdleTitlesFrame() {
        let cards = Cards()
        let row = sidebarDescendants(cards.sidebar).compactMap { $0 as? SidebarTabRow }.first { $0.tabID == cards.today.id }!
        let title = sidebarDescendants(row).compactMap { $0 as? SidebarChromeLabel }.first { $0.stringValue == "today" }!
        let titleFrame = title.convert(title.bounds, to: row)
        _ = row.beginTitleEditing("today") { _ in }
        row.layoutSubtreeIfNeeded()
        let field = sidebarDescendants(row).compactMap { $0 as? SidebarTitleField }.first!
        row.cancelTitleEditing()
        cards.window.pointer = nil
        row.updateTrackingAreas()
        row.layoutSubtreeIfNeeded()
        #expect(field.convert(field.bounds, to: row) == title.convert(title.bounds, to: row))
        #expect(field.convert(field.bounds, to: row) == titleFrame)
    }

    @Test func appKitDrawsTheLabelsTextTwoPointsInSoInkStartsAtTheInset() {
        let cards = Cards()
        let row = sidebarDescendants(cards.sidebar).compactMap { $0 as? SidebarTabRow }.first { $0.tabID == cards.today.id }!
        let title = sidebarDescendants(row).compactMap { $0 as? SidebarChromeLabel }.first { $0.stringValue == "today" }!
        let glyphs = title.bitmapImageRepForCachingDisplay(in: title.bounds)!
        title.cacheDisplay(in: title.bounds, to: glyphs)
        let scale = CGFloat(glyphs.pixelsWide) / title.bounds.width
        let firstInk = (0..<glyphs.pixelsWide).first { x in (0..<glyphs.pixelsHigh).contains { glyphs.colorAt(x: x, y: $0)!.alphaComponent > 0.25 } }!
        #expect((2...3).contains(CGFloat(firstInk) / scale))
    }

    @Test func aCardsRowOffersNoDoubleClickRenameSoItsTooltipCarriesNoHint() {
        let cards = Cards()
        let row = sidebarDescendants(cards.sidebar).compactMap { $0 as? SidebarTabRow }.first { $0.tabID == cards.today.id }!
        #expect(row.beginRename == nil)
        #expect(row.parcTooltip == SidebarTabRow.rowTooltip(cards.today, renameable: false))
        #expect(row.parcTooltip?.style == .label(subtitle: nil))
    }
}
