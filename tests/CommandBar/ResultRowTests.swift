import AppKit

@main @MainActor struct ResultRowTests {
    static func main() { exitOnFailure(runChecks) }
    static func runChecks() {
        _ = NSApplication.shared
        var count = 0
        func expect(_ value: @autoclosure () -> Bool, _ message: String) {
            count += 1; precondition(value(), message)
        }
        func cell(title: String, subtitle: String? = nil, accessory: String = "", isTab: Bool = false,
                  icon: NSImage? = NSImage(systemSymbolName: "clock", accessibilityDescription: nil), isAction: Bool = false) -> CommandResultCell {
            let cell = CommandResultCell(title: title, subtitle: subtitle, detail: "", accessory: accessory, isTab: isTab,
                                         icon: icon, enabled: true, isAction: isAction)
            cell.selectedColor = .systemGreen
            cell.frame = NSRect(x: 0, y: 0, width: 747, height: 50)
            cell.appearance = NSAppearance(named: .darkAqua)
            cell.layoutSubtreeIfNeeded()
            return cell
        }
        func fields(_ view: NSView) -> [NSTextField] {
            view.subviews.flatMap { ($0 as? NSTextField).map { [$0] } ?? fields($0) }
        }
        func field(_ cell: CommandResultCell, _ text: String) -> NSTextField? {
            fields(cell).first { $0.stringValue == text }
        }
        func subtitleLabel(_ cell: CommandResultCell) -> NSTextField {
            cell.subviews.compactMap { $0 as? NSTextField }.first { $0.lineBreakMode == .byTruncatingMiddle }!
        }
        func tile(_ cell: CommandResultCell) -> NSView {
            cell.subviews.first { $0.identifier == CommandResultCell.iconTileIdentifier }!
        }
        func image(_ cell: CommandResultCell) -> NSImageView { cell.subviews.compactMap { $0 as? NSImageView }.first! }

        let history = cell(title: "YouTube", subtitle: "— youtube.com")
        let title = field(history, "YouTube")!, subtitle = field(history, "— youtube.com")!
        expect(!subtitle.isHidden, "a history row shows its URL subtitle")
        expect(abs(subtitle.frame.minX - (title.frame.maxX + 4)) < 0.5, "the subtitle sits 4 points after the title")
        expect(title.frame.width < 120, "a short title keeps its own width instead of filling the row")
        expect(subtitle.lineBreakMode == .byTruncatingMiddle && title.lineBreakMode == .byTruncatingTail,
               "the subtitle truncates its middle and the title its tail")
        let style = subtitle.attributedStringValue.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
        expect(style?.lineBreakMode == .byTruncatingMiddle, "the attributed subtitle keeps its middle truncation")

        let long = cell(title: String(repeating: "Long title ", count: 80),
                        subtitle: "— " + String(repeating: "youtube.com/results?search_query=rick+and+morty", count: 4))
        let longTitle = long.subviews.compactMap { $0 as? NSTextField }.first { $0.stringValue.hasPrefix("Long title") }!
        let longSubtitle = long.subviews.compactMap { $0 as? NSTextField }.first { $0.stringValue.hasPrefix("— ") }!
        expect(longTitle.frame.width == 480, "the title is capped at 480 points")
        expect(longSubtitle.frame.width <= 280, "the subtitle is capped at 280 points")

        let search = cell(title: "hello", icon: NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: nil))
        expect(search.subviews.compactMap { $0 as? NSTextField }.allSatisfy { $0.stringValue != "Google Search" },
               "a search row carries no description")
        expect(subtitleLabel(search).isHidden, "a row without a subtitle hides its subtitle label")
        search.setSelected(true)
        expect(tile(search).isHidden, "a selected search glyph has no tile")

        let tab = cell(title: "Gmail", accessory: "Switch to Tab", isTab: true)
        let caption = field(tab, "Switch to Tab")!
        expect(caption.lineBreakMode == .byTruncatingTail, "a long caption truncates its tail")
        expect(!caption.isHidden, "an unselected tab row still shows Switch to Tab")
        expect(caption.textColor == CommandBarPalette.textSecondary, "the unselected caption is the secondary text colour")
        tab.setSelected(true)
        expect(caption.textColor == .white && !caption.isHidden, "the selected caption is white")
        expect(field(tab, "→") != nil, "the caption keeps its arrow")
        expect(caption.frame.width >= ceil(caption.cell!.cellSize.width), "Switch to Tab fits without an ellipsis")
        func lineMidY(_ label: NSTextField) -> CGFloat { label.frame.maxY - ceil(label.cell!.cellSize.height) / 2 }
        expect(abs(lineMidY(title) - image(history).frame.midY) < 0.5 && abs(lineMidY(subtitle) - 25) < 0.5,
               "the title and subtitle lines are centred on the icon")
        expect(abs(lineMidY(caption) - 25) < 0.5, "Switch to Tab is centred on the row")

        let favicon = NSImage(size: NSSize(width: 16, height: 16), flipped: false) { _ in true }
        let site = cell(title: "YouTube", subtitle: "— youtube.com", icon: favicon)
        expect(tile(site).isHidden, "an unselected favicon has no tile")
        site.setSelected(true)
        expect(!tile(site).isHidden, "a selected favicon sits on the white tile")
        let clock = cell(title: "Old page", subtitle: "— old.example")
        clock.setSelected(true)
        expect(tile(clock).isHidden, "a template glyph on an ordinary row never gets the tile")

        let command = cell(title: "New Easel", icon: NSImage(systemSymbolName: "scribble.variable", accessibilityDescription: nil), isAction: true)
        let commandTile = tile(command), glyph = image(command)
        expect(!commandTile.isHidden && glyph.image?.isTemplate == true, "a command row always shows its tile")
        command.setSelected(true); command.layoutSubtreeIfNeeded()
        expect(!commandTile.isHidden, "the selected command keeps its tile")
        expect(commandTile.frame.size == NSSize(width: 24, height: 24) && commandTile.layer?.cornerRadius == 4,
               "the tile is 24 points square with a 4-point radius")
        expect(glyph.frame.size == NSSize(width: 14, height: 14), "the glyph on it is 14 points square")
        expect(abs(commandTile.frame.midX - glyph.frame.midX) < 0.5 && abs(commandTile.frame.midY - glyph.frame.midY) < 0.5,
               "the tile is centred on the icon")
        expect(glyph.image?.isTemplate == false, "the selected glyph is a tinted copy the row cannot whiten")
        command.setSelected(false)
        expect(glyph.image?.isTemplate == true && !commandTile.isHidden, "deselecting restores the template glyph")
        let spoken = CommandResultCell(title: "Docs", subtitle: "— docs.com", detail: "", accessory: "Work", isTab: true, icon: nil,
                                       spokenAccessory: "Switch to Tab in Work", spokenSubtitle: "docs.com", enabled: true)
        expect(spoken.accessibilityLabel() == "Docs, docs.com, Switch to Tab in Work",
               "VoiceOver reads the plain URL and names the tab's Space")
        print("CommandBar result row tests passed (\(count) assertions)")
    }
}
