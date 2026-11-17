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
        typealias Marks = CommandResultCell.Marks
        let measure: (String) -> CGFloat = { CGFloat(($0 as NSString).length) * 7 }
        let address = "fullscript.okta.com/app/UserHome"
        let hostMarks = Marks(host: NSRange(location: 0, length: 19), matches: [NSRange(location: 11, length: 4)])
        expect(CommandResultCell.fit(address, marks: hostMarks, width: 400, measure: measure)
               == .init(text: address, matches: hostMarks.matches, clipped: false), "an address that fits shows whole")
        let tight = CommandResultCell.fit(address, marks: hostMarks, width: 160, measure: measure)
        expect(tight == .init(text: address, matches: hostMarks.matches, clipped: false),
               "a long path is left to the label to cut from its end while the whole host and an ellipsis fit")
        let lookalike = "— accounts.google.com.example-security-check.ru"
        let lookalikeMarks = Marks(host: NSRange(location: 2, length: 45),
                                   matches: [NSRange(location: 2, length: 8), NSRange(location: 39, length: 5)])
        let elided = CommandResultCell.fit(lookalike, marks: lookalikeMarks, width: 140, measure: measure)
        expect(elided.clipped && elided.text == "— …security-check.ru", "a host too long to fit keeps its end, the real site")
        expect(elided.matches.map { (elided.text as NSString).substring(with: $0) } == ["check"], "marks follow the kept end of the host")
        let narrowTitle = CommandResultCell.fit("averyveryverylonghostname.example.com/path", marks: Marks(host: NSRange(location: 0, length: 37)),
                                                width: 105, measure: measure)
        expect(narrowTitle.clipped && narrowTitle.text == "…me.example.com", "an address title too narrow for its host shows the host's end")
        let plain = CommandResultCell.fit(String(repeating: "Long title ", count: 20), marks: Marks(), width: 50, measure: measure)
        expect(!plain.clipped, "a page title is cut by the label as before")

        let marked = cell(title: "My Apps Dashboard | Fullscript", subtitle: "— fullscript.okta.com")
        marked.setMarks(title: Marks(matches: [NSRange(location: 0, length: 2)]),
                        subtitle: Marks(host: NSRange(location: 2, length: 19), matches: [NSRange(location: 13, length: 4)]))
        marked.layoutSubtreeIfNeeded()
        let markedTitle = field(marked, "My Apps Dashboard | Fullscript")!, markedSubtitle = field(marked, "— fullscript.okta.com")!
        func colour(_ label: NSTextField, _ at: Int) -> NSColor? {
            label.attributedStringValue.attribute(.foregroundColor, at: at, effectiveRange: nil) as? NSColor
        }
        expect(colour(markedTitle, 0) == CommandBarPalette.textPrimaryMatch && colour(markedTitle, 3) == CommandBarPalette.textPrimary,
               "the typed part of the title is brighter")
        expect(colour(markedSubtitle, 13) == CommandBarPalette.textSecondaryMatch && colour(markedSubtitle, 2) == CommandBarPalette.textSecondary,
               "the typed part of the site is brighter")
        expect(markedSubtitle.lineBreakMode == .byTruncatingTail, "a site subtitle never loses its middle")
        marked.setSelected(true)
        expect(colour(markedTitle, 0) == CommandBarPalette.selectedText && colour(markedTitle, 3) == CommandBarPalette.selectedText,
               "a selected title stays white")
        expect(colour(markedSubtitle, 13) == CommandBarPalette.selectedSecondaryMatchText
               && colour(markedSubtitle, 2) == CommandBarPalette.selectedSecondaryText, "a selected subtitle keeps its brighter match")
        let spokenSite = CommandResultCell(title: "My Apps Dashboard | Fullscript", subtitle: "— fullscript.okta.com", detail: "", accessory: "",
                                           isTab: false, icon: nil, spokenSubtitle: "fullscript.okta.com", enabled: true)
        spokenSite.setMarks(title: Marks(matches: [NSRange(location: 0, length: 2)]), subtitle: Marks(host: NSRange(location: 2, length: 19)))
        expect(spokenSite.accessibilityLabel() == "My Apps Dashboard | Fullscript, fullscript.okta.com", "VoiceOver still reads the plain site")

        let squeezed = cell(title: String(repeating: "Long title ", count: 80), subtitle: lookalike)
        squeezed.setMarks(title: Marks(), subtitle: lookalikeMarks)
        squeezed.layoutSubtreeIfNeeded()
        let squeezedSubtitle = squeezed.subviews.compactMap { $0 as? NSTextField }.first { $0.stringValue.hasPrefix("— ") }!
        expect(squeezedSubtitle.stringValue.hasPrefix("— …") && squeezedSubtitle.stringValue.hasSuffix("security-check.ru"),
               "a squeezed lookalike host shows where it really leads")
        expect(squeezedSubtitle.frame.width <= 280, "the subtitle keeps its width cap")
        let siteText = "— accounts.google.com.example.ru"
        let regrown = cell(title: String(repeating: "Long title ", count: 80), subtitle: siteText)
        regrown.setMarks(title: Marks(), subtitle: Marks(host: NSRange(location: 2, length: 30), matches: [NSRange(location: 22, length: 7)]))
        regrown.frame.size.width = 700; regrown.layoutSubtreeIfNeeded()
        let regrownSubtitle = regrown.subviews.compactMap { $0 as? NSTextField }.first { $0.stringValue.hasPrefix("— ") }!
        expect(regrownSubtitle.stringValue.hasPrefix("— …") && regrownSubtitle.stringValue.hasSuffix("example.ru"),
               "a narrow row shows the end of the host")
        regrown.frame.size.width = 2000; regrown.layoutSubtreeIfNeeded()
        expect(regrownSubtitle.stringValue == siteText && colour(regrownSubtitle, 22) == CommandBarPalette.textSecondaryMatch,
               "widening the row brings back the whole host and its marks")
        let disabled = CommandResultCell(title: "My Apps Dashboard | Fullscript", subtitle: "— fullscript.okta.com", detail: "", accessory: "",
                                         isTab: false, icon: nil, enabled: false)
        disabled.setMarks(title: Marks(matches: [NSRange(location: 0, length: 2)]),
                          subtitle: Marks(host: NSRange(location: 2, length: 19), matches: [NSRange(location: 13, length: 4)]))
        let disabledSubtitle = field(disabled, "— fullscript.okta.com")!
        expect(colour(field(disabled, "My Apps Dashboard | Fullscript")!, 0) == .disabledControlTextColor
               && colour(disabledSubtitle, 13) == CommandBarPalette.textSecondary, "an unavailable row draws no brighter match")
        print("CommandBar result row tests passed (\(count) assertions)")
    }
}
