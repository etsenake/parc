import AppKit
import Testing
@testable import Parc

@MainActor
struct ResultRowTests {
    typealias Marks = CommandResultCell.Marks

    static let lookalike = "— accounts.google.com.example-security-check.ru"
    static let lookalikeMarks = Marks(host: NSRange(location: 2, length: 45),
                                      matches: [NSRange(location: 2, length: 8), NSRange(location: 39, length: 5)])
    static let longTitle = String(repeating: "Long title ", count: 80)

    func cell(title: String, subtitle: String? = nil, accessory: String = "", isTab: Bool = false,
              icon: NSImage? = NSImage(systemSymbolName: "clock", accessibilityDescription: nil), isAction: Bool = false) -> CommandResultCell {
        CommandBarTestSupport.prepareAppKit()
        let cell = CommandResultCell(title: title, subtitle: subtitle, detail: "", accessory: accessory, isTab: isTab,
                                     icon: icon, enabled: true, isAction: isAction)
        cell.selectedColor = .systemGreen
        cell.frame = NSRect(x: 0, y: 0, width: 747, height: 50)
        cell.appearance = CommandBarTestSupport.dark
        cell.layoutSubtreeIfNeeded()
        return cell
    }

    func field(_ cell: CommandResultCell, _ text: String) throws -> NSTextField {
        try #require(CommandBarTestSupport.labels(in: cell).first { $0.stringValue == text })
    }

    func subtitleLabel(_ cell: CommandResultCell) throws -> NSTextField {
        try #require(cell.subviews.compactMap { $0 as? NSTextField }.first { $0.lineBreakMode == .byTruncatingMiddle })
    }

    func tile(_ cell: CommandResultCell) throws -> NSView {
        try #require(cell.subviews.first { $0.identifier == CommandResultCell.iconTileIdentifier })
    }

    func image(_ cell: CommandResultCell) throws -> NSImageView {
        try #require(cell.subviews.compactMap { $0 as? NSImageView }.first)
    }

    func foreground(_ label: NSTextField, _ index: Int) -> NSColor? {
        label.attributedStringValue.attribute(.foregroundColor, at: index, effectiveRange: nil) as? NSColor
    }

    func history() -> CommandResultCell { cell(title: "YouTube", subtitle: "— youtube.com") }

    func favicon() -> NSImage { NSImage(size: NSSize(width: 16, height: 16), flipped: false) { _ in true } }

    func marked() -> CommandResultCell {
        let marked = cell(title: "My Apps Dashboard | Fullscript", subtitle: "— fullscript.okta.com")
        marked.setMarks(title: Marks(matches: [NSRange(location: 0, length: 2)]),
                        subtitle: Marks(host: NSRange(location: 2, length: 19), matches: [NSRange(location: 13, length: 4)]))
        marked.layoutSubtreeIfNeeded()
        return marked
    }

    func commandRow() -> CommandResultCell {
        cell(title: "New Easel", icon: NSImage(systemSymbolName: "scribble.variable", accessibilityDescription: nil), isAction: true)
    }

    @Test func aHistoryRowShowsItsURLSubtitle() throws {
        #expect(try !field(history(), "— youtube.com").isHidden)
    }

    @Test func theSubtitleSitsFourPointsAfterTheTitle() throws {
        let row = history()
        #expect(try abs(field(row, "— youtube.com").frame.minX - (field(row, "YouTube").frame.maxX + 4)) < 0.5)
    }

    @Test func aShortTitleKeepsItsOwnWidth() throws {
        #expect(try field(history(), "YouTube").frame.width < 120)
    }

    @Test func theSubtitleTruncatesItsMiddleAndTheTitleItsTail() throws {
        let row = history()
        #expect(try field(row, "— youtube.com").lineBreakMode == .byTruncatingMiddle)
        #expect(try field(row, "YouTube").lineBreakMode == .byTruncatingTail)
    }

    @Test func theAttributedSubtitleKeepsItsMiddleTruncation() throws {
        let style = try field(history(), "— youtube.com").attributedStringValue.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
        #expect(style?.lineBreakMode == .byTruncatingMiddle)
    }

    @Test func aLongTitleIsCappedAt480Points() throws {
        let long = cell(title: Self.longTitle, subtitle: "— " + String(repeating: "youtube.com/results?search_query=rick+and+morty", count: 4))
        let title = try #require(long.subviews.compactMap { $0 as? NSTextField }.first { $0.stringValue.hasPrefix("Long title") })
        #expect(title.frame.width == 480)
    }

    @Test func aLongSubtitleIsCappedAt280Points() throws {
        let long = cell(title: Self.longTitle, subtitle: "— " + String(repeating: "youtube.com/results?search_query=rick+and+morty", count: 4))
        let subtitle = try #require(long.subviews.compactMap { $0 as? NSTextField }.first { $0.stringValue.hasPrefix("— ") })
        #expect(subtitle.frame.width <= 280)
    }

    @Test func aSearchRowCarriesNoDescription() {
        let search = cell(title: "hello", icon: NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: nil))
        #expect(search.subviews.compactMap { $0 as? NSTextField }.allSatisfy { $0.stringValue != "Google Search" })
    }

    @Test func aRowWithoutASubtitleHidesItsSubtitleLabel() throws {
        #expect(try subtitleLabel(cell(title: "hello")).isHidden)
    }

    @Test func aSelectedSearchGlyphHasNoTile() throws {
        let search = cell(title: "hello", icon: NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: nil))
        search.setSelected(true)
        #expect(try tile(search).isHidden)
    }

    @Test func aLongCaptionTruncatesItsTail() throws {
        #expect(try field(cell(title: "Gmail", accessory: "Switch to Tab", isTab: true), "Switch to Tab").lineBreakMode == .byTruncatingTail)
    }

    @Test func anUnselectedTabRowStillShowsSwitchToTab() throws {
        let caption = try field(cell(title: "Gmail", accessory: "Switch to Tab", isTab: true), "Switch to Tab")
        #expect(!caption.isHidden)
        #expect(caption.textColor == CommandBarPalette.textSecondary)
    }

    @Test func theSelectedCaptionIsWhiteAndKeepsItsArrow() throws {
        let tab = cell(title: "Gmail", accessory: "Switch to Tab", isTab: true)
        tab.setSelected(true)
        let caption = try field(tab, "Switch to Tab")
        #expect(caption.textColor == .white)
        #expect(!caption.isHidden)
        #expect(CommandBarTestSupport.labels(in: tab).contains { $0.stringValue == "→" })
    }

    @Test func switchToTabFitsWithoutAnEllipsis() throws {
        let caption = try field(cell(title: "Gmail", accessory: "Switch to Tab", isTab: true), "Switch to Tab")
        let size = try #require(caption.cell).cellSize
        #expect(caption.frame.width >= ceil(size.width))
    }

    func lineMidY(_ label: NSTextField) -> CGFloat { label.frame.maxY - ceil(label.cell!.cellSize.height) / 2 }

    @Test func theTitleAndSubtitleLinesAreCentredOnTheIcon() throws {
        let row = history()
        #expect(try abs(lineMidY(field(row, "YouTube")) - image(row).frame.midY) < 0.5)
        #expect(try abs(lineMidY(field(row, "— youtube.com")) - 25) < 0.5)
    }

    @Test func switchToTabIsCentredOnTheRow() throws {
        let tab = cell(title: "Gmail", accessory: "Switch to Tab", isTab: true)
        #expect(try abs(lineMidY(field(tab, "Switch to Tab")) - 25) < 0.5)
    }

    @Test func anUnselectedFaviconHasNoTile() throws {
        #expect(try tile(cell(title: "YouTube", subtitle: "— youtube.com", icon: favicon())).isHidden)
    }

    @Test func aSelectedFaviconSitsOnTheWhiteTile() throws {
        let site = cell(title: "YouTube", subtitle: "— youtube.com", icon: favicon())
        site.setSelected(true)
        #expect(try !tile(site).isHidden)
    }

    @Test func aTemplateGlyphOnAnOrdinaryRowNeverGetsTheTile() throws {
        let clock = cell(title: "Old page", subtitle: "— old.example")
        clock.setSelected(true)
        #expect(try tile(clock).isHidden)
    }

    @Test func aCommandRowAlwaysShowsItsTile() throws {
        let command = commandRow()
        #expect(try !tile(command).isHidden)
        #expect(try image(command).image?.isTemplate == true)
    }

    @Test func theSelectedCommandKeepsItsTile() throws {
        let command = commandRow()
        command.setSelected(true)
        command.layoutSubtreeIfNeeded()
        #expect(try !tile(command).isHidden)
    }

    @Test func theTileIs24PointsSquareWithAFourPointRadius() throws {
        let command = commandRow()
        #expect(try tile(command).frame.size == NSSize(width: 24, height: 24))
        #expect(try tile(command).layer?.cornerRadius == 4)
    }

    @Test func theGlyphIs14PointsSquareAndCentredOnTheTile() throws {
        let command = commandRow()
        let tile = try tile(command), glyph = try image(command)
        #expect(glyph.frame.size == NSSize(width: 14, height: 14))
        #expect(abs(tile.frame.midX - glyph.frame.midX) < 0.5)
        #expect(abs(tile.frame.midY - glyph.frame.midY) < 0.5)
    }

    @Test func theSelectedGlyphIsATintedCopyTheRowCannotWhiten() throws {
        let command = commandRow()
        command.setSelected(true)
        #expect(try image(command).image?.isTemplate == false)
    }

    @Test func deselectingRestoresTheTemplateGlyph() throws {
        let command = commandRow()
        command.setSelected(true)
        command.setSelected(false)
        #expect(try image(command).image?.isTemplate == true)
        #expect(try !tile(command).isHidden)
    }

    @Test func voiceOverReadsThePlainURLAndNamesTheTabsSpace() {
        CommandBarTestSupport.prepareAppKit()
        let spoken = CommandResultCell(title: "Docs", subtitle: "— docs.com", detail: "", accessory: "Work", isTab: true, icon: nil,
                                       spokenAccessory: "Switch to Tab in Work", spokenSubtitle: "docs.com", enabled: true)
        #expect(spoken.accessibilityLabel() == "Docs, docs.com, Switch to Tab in Work")
    }

    @Test func voiceOverStillReadsThePlainSite() {
        CommandBarTestSupport.prepareAppKit()
        let spokenSite = CommandResultCell(title: "My Apps Dashboard | Fullscript", subtitle: "— fullscript.okta.com", detail: "", accessory: "",
                                           isTab: false, icon: nil, spokenSubtitle: "fullscript.okta.com", enabled: true)
        spokenSite.setMarks(title: Marks(matches: [NSRange(location: 0, length: 2)]), subtitle: Marks(host: NSRange(location: 2, length: 19)))
        #expect(spokenSite.accessibilityLabel() == "My Apps Dashboard | Fullscript, fullscript.okta.com")
    }

    @Test func theTypedPartOfTheTitleIsBrighter() throws {
        let title = try field(marked(), "My Apps Dashboard | Fullscript")
        #expect(foreground(title, 0) == CommandBarPalette.textPrimaryMatch)
        #expect(foreground(title, 3) == CommandBarPalette.textPrimary)
    }

    @Test func theTypedPartOfTheSiteIsBrighter() throws {
        let site = try field(marked(), "— fullscript.okta.com")
        #expect(foreground(site, 13) == CommandBarPalette.textSecondaryMatch)
        #expect(foreground(site, 2) == CommandBarPalette.textSecondary)
    }

    @Test func aSiteSubtitleNeverLosesItsMiddle() throws {
        #expect(try field(marked(), "— fullscript.okta.com").lineBreakMode == .byTruncatingTail)
    }

    @Test func aSelectedTitleStaysWhite() throws {
        let row = marked()
        row.setSelected(true)
        let title = try field(row, "My Apps Dashboard | Fullscript")
        #expect(foreground(title, 0) == CommandBarPalette.selectedText)
        #expect(foreground(title, 3) == CommandBarPalette.selectedText)
    }

    @Test func aSelectedSubtitleKeepsItsBrighterMatch() throws {
        let row = marked()
        row.setSelected(true)
        let site = try field(row, "— fullscript.okta.com")
        #expect(foreground(site, 13) == CommandBarPalette.selectedSecondaryMatchText)
        #expect(foreground(site, 2) == CommandBarPalette.selectedSecondaryText)
    }

    @Test func aSqueezedLookalikeHostShowsWhereItReallyLeads() throws {
        let squeezed = cell(title: Self.longTitle, subtitle: Self.lookalike)
        squeezed.setMarks(title: Marks(), subtitle: Self.lookalikeMarks)
        squeezed.layoutSubtreeIfNeeded()
        let subtitle = try #require(squeezed.subviews.compactMap { $0 as? NSTextField }.first { $0.stringValue.hasPrefix("— ") })
        #expect(subtitle.stringValue.hasPrefix("— …"))
        #expect(subtitle.stringValue.hasSuffix("security-check.ru"))
        #expect(subtitle.frame.width <= 280)
    }

    func regrownRow() -> CommandResultCell {
        let regrown = cell(title: Self.longTitle, subtitle: "— accounts.google.com.example.ru")
        regrown.setMarks(title: Marks(), subtitle: Marks(host: NSRange(location: 2, length: 30), matches: [NSRange(location: 22, length: 7)]))
        return regrown
    }

    @Test func aNarrowRowShowsTheEndOfTheHost() throws {
        let regrown = regrownRow()
        regrown.frame.size.width = 700
        regrown.layoutSubtreeIfNeeded()
        let subtitle = try #require(regrown.subviews.compactMap { $0 as? NSTextField }.first { $0.stringValue.hasPrefix("— ") })
        #expect(subtitle.stringValue.hasPrefix("— …"))
        #expect(subtitle.stringValue.hasSuffix("example.ru"))
    }

    @Test func wideningTheRowBringsBackTheWholeHostAndItsMarks() throws {
        let regrown = regrownRow()
        regrown.frame.size.width = 700
        regrown.layoutSubtreeIfNeeded()
        regrown.frame.size.width = 2000
        regrown.layoutSubtreeIfNeeded()
        let subtitle = try #require(regrown.subviews.compactMap { $0 as? NSTextField }.first { $0.stringValue.contains("accounts") || $0.stringValue.hasPrefix("— ") })
        #expect(subtitle.stringValue == "— accounts.google.com.example.ru")
        #expect(foreground(subtitle, 22) == CommandBarPalette.textSecondaryMatch)
    }

    @Test func anUnavailableRowDrawsNoBrighterMatch() throws {
        CommandBarTestSupport.prepareAppKit()
        let disabled = CommandResultCell(title: "My Apps Dashboard | Fullscript", subtitle: "— fullscript.okta.com", detail: "", accessory: "",
                                         isTab: false, icon: nil, enabled: false)
        disabled.setMarks(title: Marks(matches: [NSRange(location: 0, length: 2)]),
                          subtitle: Marks(host: NSRange(location: 2, length: 19), matches: [NSRange(location: 13, length: 4)]))
        let title = try field(disabled, "My Apps Dashboard | Fullscript")
        let site = try field(disabled, "— fullscript.okta.com")
        #expect(foreground(title, 0) == .disabledControlTextColor)
        #expect(foreground(site, 13) == CommandBarPalette.textSecondary)
    }
}

struct ResultRowFitTests {
    typealias Marks = CommandResultCell.Marks

    static let measure: @Sendable (String) -> CGFloat = { CGFloat(($0 as NSString).length) * 7 }
    static let address = "fullscript.okta.com/app/UserHome"
    static let hostMarks = Marks(host: NSRange(location: 0, length: 19), matches: [NSRange(location: 11, length: 4)])
    static let lookalike = "— accounts.google.com.example-security-check.ru"
    static let lookalikeMarks = Marks(host: NSRange(location: 2, length: 45),
                                      matches: [NSRange(location: 2, length: 8), NSRange(location: 39, length: 5)])

    @Test func anAddressThatFitsShowsWhole() {
        let fit = CommandResultCell.fit(Self.address, marks: Self.hostMarks, width: 400, measure: Self.measure)
        #expect(fit == .init(text: Self.address, matches: Self.hostMarks.matches, clipped: false))
    }

    @Test func aLongPathIsLeftToTheLabelWhileTheWholeHostAndAnEllipsisFit() {
        let fit = CommandResultCell.fit(Self.address, marks: Self.hostMarks, width: 160, measure: Self.measure)
        #expect(fit == .init(text: Self.address, matches: Self.hostMarks.matches, clipped: false))
    }

    @Test func aHostTooLongToFitKeepsItsEndTheRealSite() {
        let elided = CommandResultCell.fit(Self.lookalike, marks: Self.lookalikeMarks, width: 140, measure: Self.measure)
        #expect(elided.clipped)
        #expect(elided.text == "— …security-check.ru")
    }

    @Test func marksFollowTheKeptEndOfTheHost() {
        let elided = CommandResultCell.fit(Self.lookalike, marks: Self.lookalikeMarks, width: 140, measure: Self.measure)
        #expect(elided.matches.map { (elided.text as NSString).substring(with: $0) } == ["check"])
    }

    @Test func anAddressTitleTooNarrowForItsHostShowsTheHostsEnd() {
        let fit = CommandResultCell.fit("averyveryverylonghostname.example.com/path", marks: Marks(host: NSRange(location: 0, length: 37)),
                                        width: 105, measure: Self.measure)
        #expect(fit.clipped)
        #expect(fit.text == "…me.example.com")
    }

    @Test func aPageTitleIsCutByTheLabelAsBefore() {
        let plain = CommandResultCell.fit(String(repeating: "Long title ", count: 20), marks: Marks(), width: 50, measure: Self.measure)
        #expect(!plain.clipped)
    }
}
