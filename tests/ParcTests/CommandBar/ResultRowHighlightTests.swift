import AppKit
import Testing
@testable import Parc

@MainActor
struct ResultRowHighlightTests {
    typealias Support = CommandBarTestSupport

    struct Fixture {
        let window: NSWindow
        let row = CommandResultRowView(frame: NSRect(x: 0, y: 0, width: 600, height: 50))
        let palette = CommandBarPalette(theme: CommandBarPaletteTests.pinkTheme())

        init() {
            window = Support.borderlessWindow(width: 900, height: 500)
            window.appearance = Support.dark
            row.selectedColor = palette.selected
            window.contentView?.addSubview(row)
            row.layoutSubtreeIfNeeded()
        }
    }

    @Test func theHighlightIsAttachedToTheRow() {
        let fixture = Fixture()
        #expect(fixture.row.highlight.superlayer === fixture.row.layer)
    }

    @Test func theHighlightGeometryIsInsetWithAContinuousSixPointCorner() {
        let row = Fixture().row
        #expect(row.highlight.frame == row.bounds.insetBy(dx: 2, dy: 2))
        #expect(row.highlight.cornerRadius == 6)
        #expect(row.highlight.cornerCurve == .continuous)
    }

    @Test func unselectedRowsAreClear() {
        #expect(Support.rgba(Fixture().row.highlight.backgroundColor).w == 0)
    }

    @Test func selectedRowsTakeTheThemeFocus() {
        let fixture = Fixture()
        fixture.row.isSelected = true
        #expect(Support.near(Support.rgba(fixture.row.highlight.backgroundColor), Support.rgba(fixture.palette.selected, in: Support.dark)))
    }

    @Test func theHighlightIsNotAViewsBackingLayer() {
        #expect(Fixture().row.highlight.delegate == nil)
    }

    @Test func deselectionClears() {
        let fixture = Fixture()
        fixture.row.isSelected = true
        fixture.row.isSelected = false
        #expect(Support.rgba(fixture.row.highlight.backgroundColor).w == 0)
    }

    @Test(arguments: [true, false])
    func aRowWithoutAThemeDefaultsToNeutralGreyNotTheSystemAccent(dark: Bool) {
        let appearance = dark ? Support.dark : Support.light
        let selected = Support.rgba(CommandResultRowView().selectedColor, in: appearance)
        let accents = [Support.rgba(.controlAccentColor, in: appearance), Support.rgba(.selectedContentBackgroundColor, in: appearance)]
        #expect(Support.near(selected, dark ? CommandBarPaletteTests.neutralDark : CommandBarPaletteTests.neutralLight))
        #expect(!accents.contains { Support.near($0, selected, 0.05) })
    }

    @Test func aCellWithoutAThemeDefaultsToNeutralGreyNotTheSystemAccent() {
        Support.prepareAppKit()
        let cell = CommandResultCell(title: "x", detail: "", accessory: "", isTab: false, icon: nil, enabled: true)
        let selected = Support.rgba(cell.selectedColor, in: Support.dark)
        let accents = [Support.rgba(.controlAccentColor, in: Support.dark), Support.rgba(.selectedContentBackgroundColor, in: Support.dark)]
        #expect(Support.near(selected, CommandBarPaletteTests.neutralDark))
        #expect(!accents.contains { Support.near($0, selected, 0.05) })
    }
}
