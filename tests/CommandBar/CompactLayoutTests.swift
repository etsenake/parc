import AppKit

@main @MainActor struct CompactLayoutTests {
    static func main() { exitOnFailure(runChecks) }
    static func runChecks() {
        NSApplication.shared.setActivationPolicy(.prohibited)
        var count = 0
        func expect(_ value: @autoclosure () -> Bool, _ message: String) {
            count += 1; precondition(value(), message)
        }
        typealias Compact = CommandBarCompactLayout
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 944)
        let window = CGRect(x: 100, y: 80, width: 1200, height: 800)

        expect(Compact.width(popup: false, window: window, screen: screen) == 450, "the sidebar editor is 450 points wide")
        expect(Compact.width(popup: true, window: window, screen: screen) == 350, "a popup keeps its 350-point editor")
        let signIn = CGRect(x: 600, y: 300, width: 300, height: 360)
        let popupWidth = Compact.width(popup: true, window: signIn, screen: screen)
        expect(popupWidth == 284, "a narrow sign-in popup caps the editor to its own width")
        let popupX = Compact.originX(anchor: signIn.minX + 70, width: popupWidth, window: signIn, screen: screen)
        expect(popupX >= signIn.minX + 8 && popupX + popupWidth <= signIn.maxX - 8, "the popup editor stays inside its window")
        let tiny = CGRect(x: 0, y: 0, width: 12, height: 360)
        expect(Compact.width(popup: true, window: tiny, screen: screen) == 0, "a window too narrow for margins never gets a negative width")

        let small = CGRect(x: 40, y: 40, width: 420, height: 540)
        let smallWidth = Compact.width(popup: false, window: small, screen: screen)
        expect(smallWidth == 404, "a small window caps the sidebar editor inside its margins")
        let smallX = Compact.originX(anchor: small.minX + 12, width: smallWidth, window: small, screen: screen)
        expect(smallX == small.minX + 8 && smallX + smallWidth == small.maxX - 8, "the capped editor fits between the window margins")
        let narrowScreen = CGRect(x: 0, y: 0, width: 400, height: 700)
        expect(Compact.width(popup: false, window: window, screen: narrowScreen) == 384, "the screen still caps the editor")

        let anchor = window.minX + 14
        expect(Compact.originX(anchor: anchor, width: 450, window: window, screen: screen) == anchor,
               "the sidebar editor starts at the address field when it fits")
        let trailingAnchor = window.maxX - 200
        let trailingX = Compact.originX(anchor: trailingAnchor, width: 450, window: window, screen: screen)
        expect(trailingX == window.maxX - 8 - 450, "an anchor near the window's right edge slides the editor back inside")
        let overhanging = CGRect(x: 900, y: 80, width: 800, height: 800)
        let overhangingX = Compact.originX(anchor: overhanging.minX + 300, width: 450, window: overhanging, screen: screen)
        expect(overhangingX + 450 == screen.maxX - 8, "a window hanging off the screen keeps the editor on screen when it can")
        let mostlyOff = CGRect(x: 1300, y: 80, width: 600, height: 800)
        let mostlyOffX = Compact.originX(anchor: mostlyOff.minX + 14, width: 450, window: mostlyOff, screen: screen)
        expect(mostlyOffX == mostlyOff.minX + 8, "the editor never leaves its own window, which hosts it")

        let cellWidth = Compact.sidebarWidth - 2 * Compact.listInset
        func cell(_ title: String, accessory: String = "", isTab: Bool = false) -> CommandResultCell {
            let cell = CommandResultCell(title: title, subtitle: "— example.com", detail: "", accessory: accessory, isTab: isTab,
                                         icon: NSImage(systemSymbolName: "clock", accessibilityDescription: nil), enabled: true)
            cell.frame = NSRect(x: 0, y: 0, width: cellWidth, height: 50)
            cell.layoutSubtreeIfNeeded()
            return cell
        }
        func field(_ view: NSView, _ text: String) -> NSTextField? {
            for subview in view.subviews {
                if let field = subview as? NSTextField, field.stringValue == text { return field }
                if let found = field(subview, text) { return found }
            }
            return nil
        }
        let history = cell("Example page")
        let icon = history.subviews.compactMap { $0 as? NSImageView }.first!
        let title = field(history, "Example page")!
        expect(Compact.iconX == Compact.listInset + icon.frame.minX, "the address icon starts where result icons start")
        expect(Compact.iconSize == icon.frame.width, "the address icon is the result icon's size")
        expect(Compact.textX == Compact.listInset + title.frame.minX, "the address text starts at the result title column")
        let tab = cell("Gmail", accessory: "Switch to Tab", isTab: true)
        let badge = field(tab, "→")!.superview!
        expect(Compact.trailing == Compact.listInset + (cellWidth - badge.frame.maxX),
               "the address row ends at the result badge column")

        let sidebarAddress = CGRect(x: window.minX + 9, y: window.maxY - 90, width: 222, height: SidebarChromeLayout.fieldHeight)
        func editorFrame(_ anchor: CGRect, window: CGRect, popup: Bool = false) -> CGRect {
            let width = Compact.width(popup: popup, window: window, screen: screen)
            return CGRect(x: Compact.originX(anchor: anchor.minX, width: width, window: window, screen: screen),
                          y: Compact.originY(anchor: anchor, height: 309, lift: Compact.lift(anchorHeight: anchor.height), screen: screen),
                          width: width, height: 309)
        }
        func onScreen(_ frame: CGRect, in panel: CGRect) -> CGRect {
            CGRect(x: panel.minX + frame.minX, y: panel.maxY - frame.maxY, width: frame.width, height: frame.height)
        }
        let smallest = CGRect(x: 0, y: 100, width: 760, height: 540)
        for (anchor, sidebar, owner) in [(sidebarAddress, CGFloat(276), window),
                                         (CGRect(x: smallest.minX + 9, y: smallest.maxY - 90, width: 246, height: 36), 300, smallest)] {
            let rest = Compact.restingFrame(anchor: anchor, sidebar: sidebar, screen: screen), typing = editorFrame(anchor, window: owner)
            expect(rest.minX == anchor.minX && rest.maxY == anchor.maxY && rest.height == anchor.height && rest.width == sidebar - 18,
                   "the resting field covers the sidebar's whole address field from the address button's edge")
            let restingText = onScreen(Compact.inputFrame(width: rest.width, centre: rest.height / 2), in: rest)
            let typingText = onScreen(Compact.inputFrame(width: typing.width, centre: Compact.headerCentre), in: typing)
            expect(restingText.minX == typingText.minX && restingText.maxY == typingText.maxY,
                   "the first keystroke leaves the text and caret exactly where they were")
            expect(onScreen(Compact.iconFrame(centre: rest.height / 2), in: rest) == onScreen(Compact.iconFrame(centre: Compact.headerCentre), in: typing),
                   "the field's icon stays put as the results open")
            expect(restingText.maxY - Compact.textLineHeight / 2 == anchor.midY, "the resting text's line is centred on the sidebar address field")
            expect(typing.maxY == anchor.maxY + Compact.lift(anchorHeight: anchor.height), "the typing panel rises just enough to keep the row on its line")
        }
        expect(Compact.lift(anchorHeight: SidebarChromeLayout.fieldHeight) == 6, "the sidebar editors rise six points")
        expect(Compact.inputFrame(width: 450, centre: Compact.headerCentre).minX == Compact.textX
               && Compact.iconFrame(centre: Compact.headerCentre).minX == Compact.iconX, "the typing row keeps the result columns")
        let header = Compact.inputFrame(width: 450, centre: Compact.headerCentre), headerIcon = Compact.iconFrame(centre: Compact.headerCentre)
        let popupWindow = CGRect(x: 600, y: 300, width: 420, height: 500)
        let popupAddress = CGRect(x: popupWindow.minX + 73, y: popupWindow.maxY - 39, width: 340, height: 31)
        let popupEditor = editorFrame(popupAddress, window: popupWindow, popup: true)
        expect(onScreen(header, in: popupEditor).maxY - Compact.textLineHeight / 2 == popupAddress.midY
               && onScreen(headerIcon, in: popupEditor).midY == popupAddress.midY,
               "a pop-up's editor centres its text line and icon on the pop-up's address")

        let canvasSize = NSSize(width: 320, height: 140)
        func ink(_ view: NSView, prepare: () -> Void = {}) -> CGRect {
            let canvas = FlippedCanvas(frame: NSRect(origin: .zero, size: canvasSize))
            canvas.appearance = NSAppearance(named: .aqua)
            canvas.addSubview(view)
            prepare()
            let scale = 4
            let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(canvasSize.width) * scale, pixelsHigh: Int(canvasSize.height) * scale,
                                       bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                       bytesPerRow: 0, bitsPerPixel: 0)!
            rep.size = canvasSize
            canvas.cacheDisplay(in: canvas.bounds, to: rep)
            var minX = Int.max, maxX = -1, minY = Int.max, maxY = -1
            let data = rep.bitmapData!, stride = rep.bytesPerRow
            for y in 0..<rep.pixelsHigh {
                for x in 0..<rep.pixelsWide where data[y * stride + x * 4 + 3] > 64 {
                    minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
                }
            }
            view.removeFromSuperview()
            precondition(maxX >= 0, "nothing was drawn")
            let s = CGFloat(scale)
            return CGRect(x: CGFloat(minX) / s, y: CGFloat(minY) / s, width: CGFloat(maxX + 1 - minX) / s, height: CGFloat(maxY + 1 - minY) / s)
        }
        let pill = CGRect(x: 9, y: 60, width: 222, height: SidebarChromeLayout.fieldHeight)
        func pillText() -> CGRect {
            let button = NSButton(frame: pill)
            button.isBordered = false; button.bezelStyle = .regularSquare; button.alignment = .left
            button.font = .systemFont(ofSize: SidebarChromeLayout.addressFontSize)
            let paragraph = NSMutableParagraphStyle()
            paragraph.firstLineHeadIndent = SidebarAddressSearchIcon.textIndent; paragraph.lineBreakMode = .byTruncatingTail
            button.attributedTitle = NSAttributedString(string: SidebarAddressSearchIcon.placeholder, attributes: [
                .font: NSFont.systemFont(ofSize: SidebarChromeLayout.addressFontSize), .foregroundColor: NSColor.black, .paragraphStyle: paragraph])
            return ink(button)
        }
        let side = SidebarAddressSearchIcon.side
        let pillIconFrame = CGRect(x: SidebarAddressSearchIcon.centerX - 1 - side / 2, y: (pill.height - side) / 2, width: side, height: side)
        func pillIcon() -> CGRect {
            let icon = SidebarAddressSearchIcon(frame: pillIconFrame.offsetBy(dx: pill.minX, dy: pill.minY))
            icon.contentTintColor = .black
            return ink(icon)
        }
        func fieldText(_ frame: CGRect, placeholder: String, editing: Bool = false, typed: String = "") -> CGRect {
            let input = NSTextField(frame: frame)
            input.isBordered = false; input.drawsBackground = false; input.font = CommandBarTypography.label
            input.usesSingleLineMode = true; input.cell?.wraps = false; input.cell?.isScrollable = true; input.lineBreakMode = .byClipping
            input.textColor = .black; input.stringValue = typed
            input.placeholderAttributedString = NSAttributedString(string: placeholder, attributes: [
                .font: CommandBarTypography.label, .foregroundColor: NSColor.black])
            return ink(input) {
                guard editing else { return }
                let editor = NSTextView(); editor.isFieldEditor = true
                input.cell?.select(withFrame: input.bounds, in: input, editor: editor, delegate: nil,
                                   start: (typed as NSString).length, length: 0)
                editor.insertionPointColor = .clear
            }
        }
        func fieldIcon(_ frame: CGRect) -> CGRect {
            let icon = NSImageView(frame: frame)
            icon.imageScaling = .scaleProportionallyDown; icon.image = SidebarAddressSearchIcon.glyph; icon.contentTintColor = .black
            return ink(icon)
        }
        expect(SidebarAddressSearchIcon(frame: .zero).image === SidebarAddressSearchIcon.glyph, "the pill and the editor draw the very same magnifying glass")
        let restingPill = pillText(), restingPillIcon = pillIcon()
        let lift = Compact.lift(anchorHeight: pill.height)
        let surfaces: [(String, CGRect, CGFloat, String)] = [
            ("Control-Space", CGRect(x: pill.minX, y: pill.minY, width: 260, height: pill.height), pill.height / 2, "Search…"),
            ("typing", CGRect(x: pill.minX, y: pill.minY - lift, width: 450, height: 309), Compact.headerCentre, "Search…"),
            ("a click", CGRect(x: pill.minX, y: pill.minY - lift, width: 450, height: 309), Compact.headerCentre, SidebarAddressSearchIcon.placeholder)]
        var settledText: CGRect?, settledIcon: CGRect?
        for (name, surface, centre, placeholder) in surfaces {
            let input = Compact.inputFrame(width: surface.width, centre: centre).offsetBy(dx: surface.minX, dy: surface.minY)
            let icon = Compact.iconFrame(centre: centre).offsetBy(dx: surface.minX, dy: surface.minY)
            let glide = Compact.glideOffsets(pillIconX: pill.minX + pillIconFrame.minX - surface.minX,
                                             pillTextX: pill.minX + SidebarAddressSearchIcon.textIndent - surface.minX,
                                             iconX: icon.minX - surface.minX, inputX: input.minX - surface.minX)
            let startText = fieldText(input.offsetBy(dx: glide.text, dy: 0), placeholder: placeholder)
            let startIcon = fieldIcon(icon.offsetBy(dx: glide.icon, dy: 0))
            expect(startText.minX == restingPill.minX, "\(name) starts its text exactly at the pill's text")
            expect(startText.minY == restingPill.minY && startText.maxY == restingPill.maxY, "\(name) keeps the text on the pill's line and baseline")
            expect(startIcon == restingPillIcon, "\(name) starts its icon exactly over the pill's icon")
            let focused = input.offsetBy(dx: glide.text, dy: 0)
            expect(fieldText(focused, placeholder: placeholder, editing: true) == startText,
                   "\(name) draws its placeholder in the same spot once the field editor takes over")
            let typedText = fieldText(focused, placeholder: "", editing: true, typed: "Search…")
            expect(typedText.minX == startText.minX && typedText.minY == startText.minY && typedText.maxY == startText.maxY,
                   "\(name) puts typed text and the caret where the placeholder began")
            let endText = fieldText(input, placeholder: placeholder), endIcon = fieldIcon(icon)
            expect(endText.minY == startText.minY && endText.maxY == startText.maxY && endIcon.minY == startIcon.minY && endIcon.maxY == startIcon.maxY,
                   "\(name) glides only sideways")
            expect(endText.minX == startText.minX - glide.text && endIcon.minX == startIcon.minX - glide.icon, "\(name) settles on the result columns")
            if let settledText, let settledIcon {
                expect(endText.minX == settledText.minX && endText.minY == settledText.minY && endIcon == settledIcon,
                       "\(name) settles exactly where Control-Space did")
            }
            settledText = settledText ?? endText; settledIcon = settledIcon ?? endIcon
        }

        let rows = ResultRows()
        let container = FlippedCanvas(frame: NSRect(x: 0, y: 0, width: Compact.sidebarWidth, height: 309))
        let scroll = CommandResultsScrollView(frame: NSRect(x: Compact.listInset, y: 50, width: Compact.sidebarWidth - 2 * Compact.listInset,
                                                            height: 250))
        let table = CommandResultsTable()
        table.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("suggestion")))
        table.style = .plain; table.headerView = nil; table.rowHeight = 50; table.intercellSpacing = .zero
        table.dataSource = rows; table.delegate = rows
        scroll.drawsBackground = false; scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true
        scroll.hasHorizontalScroller = false; scroll.horizontalScrollElasticity = .none
        scroll.documentView = table; container.addSubview(scroll)
        var tiledReserves: [CGFloat] = []
        scroll.onTile = { tiledReserves.append(scroll.scrollerReserve) }
        func badgeTrailing(_ total: Int, style: NSScroller.Style) -> (badge: CGFloat, row: CGFloat) {
            scroll.scrollerStyle = style
            rows.count = total; table.reloadData()
            table.fit(in: scroll, rowCount: total)
            table.layoutSubtreeIfNeeded()
            let tab = table.view(atColumn: 0, row: 0, makeIfNecessary: true) as! CommandResultCell
            tab.layoutSubtreeIfNeeded()
            let badge = field(tab, "→")!.superview!
            let row = table.rowView(atRow: 0, makeIfNecessary: true)!
            return (container.bounds.width - badge.convert(badge.bounds, to: container).maxX,
                    container.bounds.width - row.convert(row.bounds, to: container).maxX)
        }
        let legacyWidth = NSScroller.scrollerWidth(for: .regular, scrollerStyle: .legacy)
        for (style, reserve) in [(NSScroller.Style.legacy, legacyWidth), (.overlay, 0)] {
            let name = style == .legacy ? "permanent" : "overlay"
            let few = badgeTrailing(3, style: style)
            expect(scroll.scrollerReserve == reserve, "3 rows with \(name) scroll bars reserve \(reserve) points")
            let many = badgeTrailing(8, style: style)
            expect(scroll.scrollerReserve == reserve, "8 rows with \(name) scroll bars reserve \(reserve) points")
            expect(abs(few.badge - many.badge) < 0.01 && abs(few.row - many.row) < 0.01,
                   "badges and highlights stay put as \(name) scroll bars appear")
            expect(abs(Compact.trailing + reserve - many.badge) < 0.01, "the address row ends on the badge column with \(name) scroll bars")
            expect(abs(table.frame.width - scroll.contentView.frame.width) < 0.01, "the rows fit the reserved list width")
        }
        tiledReserves.removeAll()
        scroll.scrollerStyle = .legacy; scroll.layoutSubtreeIfNeeded()
        expect(tiledReserves.last == legacyWidth, "switching to permanent scroll bars re-tiles the list and reports the reserved width")
        let switched = badgeTrailing(8, style: .legacy)
        expect(abs(Compact.trailing + scroll.scrollerReserve - switched.badge) < 0.01, "the address row follows the list after the setting changes")
        scroll.isHidden = true
        expect(scroll.scrollerReserve == 0, "a hidden list reserves nothing for its scroller")
        print("CommandBar compact layout tests passed (\(count) assertions)")
    }
}

private final class FlippedCanvas: NSView {
    override var isFlipped: Bool { true }
}

@MainActor private final class ResultRows: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    var count = 0
    func numberOfRows(in tableView: NSTableView) -> Int { count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        CommandResultCell(title: "Gmail \(row)", subtitle: "— mail.example.com", detail: "", accessory: "Switch to Tab", isTab: true,
                          icon: NSImage(systemSymbolName: "clock", accessibilityDescription: nil), enabled: true)
    }
}
