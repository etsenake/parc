import AppKit
import CoreText
import Testing
@testable import Parc
@testable import ParcCore

@MainActor
struct SplitAppearanceIconCatalogTests {
    @Test func theIconResourcesLoadFromTheBundlesCustomInfoPickerFolder() {
        #expect(SidebarIconCatalog.resourceDirectory == Bundle.main.resourceURL?.appendingPathComponent("CustomInfoPicker", isDirectory: true))
    }

    @Test func allSixtyOneCasesAreInOrder() {
        #expect(SidebarIconType.allCases.count == 61)
        #expect(SidebarIconType.allCases.first == .star)
        #expect(SidebarIconType.allCases.last == .search)
    }

    @Test func theTabAndSpaceCatalogStopsAtTrain() {
        #expect(SidebarIconType.tabAndSpacePicker.count == 56)
        #expect(SidebarIconType.tabAndSpacePicker.last == .train)
    }

    @Test func theFolderCatalogKeepsItsOrder() {
        #expect(SidebarIconType.folderPicker.count == 24)
        #expect(SidebarIconType.folderPicker[8] == .chatBubbleEllipses)
        #expect(SidebarIconType.folderPicker.last == .skull)
    }

    @Test func thePaletteIconDecodesTheOriginalSpelling() {
        #expect(SidebarIconType(rawValue: "colorPallete") == .colorPallete)
    }

    @Test func theFullFileTrayEncodesItsOriginalName() {
        #expect(SidebarIconType.fileTrayFull.rawValue == "fileTrayFull")
    }

    @Test(arguments: [SidebarIconCatalog.Font.ionicons, .feather])
    func theBundledIconFontsLoad(_ font: SidebarIconCatalog.Font) {
        #expect(SidebarIconCatalog.font(font, size: 14, in: SplitAppearanceSupport.iconFixtures).fontName == font.rawValue)
    }

    @Test func theIconFontComesFromTheBundledFileNotANameLookup() {
        let ionicons = SidebarIconCatalog.font(.ionicons, size: 14, in: SplitAppearanceSupport.iconFixtures)
        let url = CTFontCopyAttribute(ionicons as CTFont, kCTFontURLAttribute) as? URL
        #expect(url?.standardizedFileURL == SplitAppearanceSupport.iconFixtures?.appendingPathComponent("ionicons.ttf").standardizedFileURL)
    }

    @Test(arguments: SidebarIconType.allCases.filter { SidebarIconCatalog.glyph($0) != nil })
    func eachGlyphExistsInIoniconsAndRendersAsATemplate(_ type: SidebarIconType) throws {
        let ionicons = SidebarIconCatalog.font(.ionicons, size: 14, in: SplitAppearanceSupport.iconFixtures)
        let code = try #require(SidebarIconCatalog.glyph(type))
        var units = Array(String(Character(try #require(Unicode.Scalar(code)))).utf16)
        var glyphs = [CGGlyph](repeating: 0, count: units.count)
        #expect(CTFontGetGlyphsForCharacters(ionicons as CTFont, &units, &glyphs, units.count))
        #expect(SidebarIconCatalog.image(for: type, size: 14).isTemplate)
    }

    @Test(arguments: SidebarIconType.allCases.filter { SidebarIconCatalog.glyph($0) == nil })
    func theRemainingTypesAreCopiedImageAssets(_ type: SidebarIconType) {
        #expect([.linear, .figma].contains(type))
        #expect(SidebarIconCatalog.image(for: type, size: 16).size == NSSize(width: 16, height: 16))
    }

    struct GlyphCase: Sendable, CustomTestStringConvertible {
        let icon: SidebarIconType
        let codePoint: UInt32
        var testDescription: String { icon.rawValue }

        static let all = [
            Self(icon: .star, codePoint: 0xF53B),
            Self(icon: .bag, codePoint: 0xF166),
            Self(icon: .ellipse, codePoint: 0xF29E),
        ]
    }

    @Test(arguments: GlyphCase.all)
    func eachCatalogIconKeepsItsGlyphCodePoint(_ sample: GlyphCase) {
        #expect(SidebarIconCatalog.glyph(sample.icon) == sample.codePoint)
    }

    @Test func catalogIconsRoundTrip() throws {
        let encoded = try JSONEncoder().encode(SidebarGroupIcon.icon(.chatBubbleEllipses))
        #expect(try JSONDecoder().decode(SidebarGroupIcon.self, from: encoded) == .icon(.chatBubbleEllipses))
    }

    @Test func theFolderPickerHostIs272By144() {
        #expect(SidebarIconPickerMetrics.size(.folderPicker) == NSSize(width: 272, height: 144))
    }

    @Test func aStoredIconOpensTheIconPageOnAnEightBySevenGrid() throws {
        _ = NSApplication.shared
        let picker = SidebarGroupIconPicker(selected: .icon(.star))
        _ = picker.view
        let view = try #require(picker.pickerView)
        #expect(view.page == .icon)
        #expect(view.iconGrid.items.count == 56)
        #expect(view.iconGrid.fittingSize == NSSize(width: 247, height: 216))
    }

    @Test func cellsAreThirtyPointsOneApart() throws {
        _ = NSApplication.shared
        let picker = SidebarGroupIconPicker(selected: .icon(.star))
        _ = picker.view
        #expect(try #require(picker.pickerView).iconGrid.itemFrame(at: 9) == NSRect(x: 31, y: 31, width: 30, height: 30))
    }

    @Test func theGridCentersInTheTwoHundredSixtyFourPointPage() throws {
        _ = NSApplication.shared
        let picker = SidebarGroupIconPicker(selected: .icon(.star))
        _ = picker.view
        #expect(try #require(picker.pickerView).gridFrame.minX == 12.5)
    }

    private func gridItems() throws -> (star: SidebarIconItemView, heart: SidebarIconItemView) {
        _ = NSApplication.shared
        let picker = SidebarGroupIconPicker(selected: .icon(.star))
        _ = picker.view
        let grid = try #require(picker.pickerView).iconGrid
        let star = grid.items[0], heart = grid.items[2]
        star.appearance = NSAppearance(named: .aqua)
        heart.appearance = NSAppearance(named: .aqua)
        return (star, heart)
    }

    @Test func theSelectedItemCarriesTheRawNameLabel() throws {
        let (star, _) = try gridItems()
        #expect(star.isSelectedIcon)
        #expect(star.accessibilityLabel() == "star")
        #expect(star.isAccessibilitySelected())
    }

    @Test func theSelectedLightBackgroundIsBrandGrayAtAQuarter() throws {
        let (star, heart) = try gridItems()
        #expect(star.backgroundColor == SidebarIconCatalog.brandGray.withAlphaComponent(0.25))
        #expect(heart.backgroundColor == .clear)
    }

    @Test func theHoverBackgroundIsATenth() throws {
        let (_, heart) = try gridItems()
        let event = try #require(NSEvent.enterExitEvent(with: .mouseEntered, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
                                                        context: nil, eventNumber: 0, trackingNumber: 0, userData: nil))
        heart.mouseEntered(with: event)
        #expect(heart.backgroundColor == SidebarIconCatalog.brandGray.withAlphaComponent(0.1))
    }

    @Test func darkGlyphsAreWhite() throws {
        let (_, heart) = try gridItems()
        heart.appearance = NSAppearance(named: .darkAqua)
        #expect(heart.glyphColor == .white)
    }

    @Test func pressingDimsTheGlyph() throws {
        let (_, heart) = try gridItems()
        heart.setPressed(true)
        #expect(heart.glyphView.layer?.opacity == 0.75)
    }

    @Test func releasingRestoresTheGlyph() throws {
        let (_, heart) = try gridItems()
        heart.setPressed(true)
        heart.setPressed(false)
        #expect(heart.glyphView.layer?.opacity == 1)
    }

    @Test func aStoredSymbolOpensTheIconPageUnselected() throws {
        _ = NSApplication.shared
        let picker = SidebarGroupIconPicker(selected: .symbol("star"))
        _ = picker.view
        let view = try #require(picker.pickerView)
        #expect(view.page == .icon)
        #expect(view.iconGrid.selectedIcon == nil)
    }

    @Test func theFolderPickerIsIconsOnly() throws {
        _ = NSApplication.shared
        let picker = SidebarGroupIconPicker(selected: nil, iconSet: .folderPicker)
        _ = picker.view
        let view = try #require(picker.pickerView)
        #expect(view.page == .icon)
        #expect(view.heading?.stringValue == "Icon")
        #expect(view.emojiPage == nil)
        #expect(view.iconGrid.items.count == 24)
    }
}
