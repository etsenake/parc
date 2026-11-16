import AppKit

@main @MainActor struct CompactLayoutTests {
    static func main() {
        _ = NSApplication.shared
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

        let sidebarAddress = CGRect(x: window.minX + 9, y: window.maxY - 90, width: 222, height: 36)
        func typingFrame(_ anchor: CGRect, window: CGRect, lift: CGFloat = Compact.sessionLift) -> CGRect {
            let width = Compact.width(popup: false, window: window, screen: screen)
            return CGRect(x: Compact.originX(anchor: anchor.minX, width: width, window: window, screen: screen),
                          y: Compact.originY(anchor: anchor, height: 309, lift: lift, screen: screen), width: width, height: 309)
        }
        func onScreen(_ frame: CGRect, in panel: CGRect) -> CGRect {
            CGRect(x: panel.minX + frame.minX, y: panel.maxY - frame.maxY, width: frame.width, height: frame.height)
        }
        let smallest = CGRect(x: 0, y: 100, width: 760, height: 540)
        for (anchor, sidebar, owner) in [(sidebarAddress, CGFloat(276), window),
                                         (CGRect(x: smallest.minX + 9, y: smallest.maxY - 90, width: 246, height: 36), 300, smallest)] {
            let rest = Compact.restingFrame(anchor: anchor, sidebar: sidebar, screen: screen), typing = typingFrame(anchor, window: owner)
            expect(rest.minX == anchor.minX && rest.maxY == anchor.maxY && rest.height == anchor.height && rest.width == sidebar - 18,
                   "the resting field covers the sidebar's whole address field from the address button's edge")
            let restingText = onScreen(Compact.inputFrame(width: rest.width, resting: true), in: rest)
            let typingText = onScreen(Compact.inputFrame(width: typing.width, resting: false), in: typing)
            expect(restingText.minX == typingText.minX && restingText.midY == typingText.midY,
                   "the first keystroke leaves the text and caret exactly where they were")
            expect(onScreen(Compact.iconFrame(resting: true), in: rest) == onScreen(Compact.iconFrame(resting: false), in: typing),
                   "the field's icon stays put as the results open")
            expect(restingText.midY == anchor.midY, "the resting text is centred on the sidebar address field")
            expect(typing.maxY == anchor.maxY + Compact.sessionLift, "only the typing panel rises, just enough to keep the row on its line")
        }
        expect(Compact.inputFrame(width: 450, resting: false).minX == Compact.textX
               && Compact.iconFrame(resting: false).minX == Compact.iconX, "the typing row keeps the result columns")
        let clicked = typingFrame(sidebarAddress, window: window, lift: 0)
        expect(clicked.maxY == sidebarAddress.maxY, "a click on the sidebar's address still opens the editor from the field's top edge")

        let rows = ResultRows()
        let surface = NSWindow(contentRect: NSRect(x: -30000, y: -30000, width: 900, height: 500), styleMask: [.borderless],
                               backing: .buffered, defer: false)
        let container = NSView(frame: NSRect(x: 0, y: 0, width: Compact.sidebarWidth, height: 309))
        surface.contentView!.addSubview(container)
        let scroll = CommandResultsScrollView(frame: NSRect(x: Compact.listInset, y: 9, width: Compact.sidebarWidth - 2 * Compact.listInset,
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
        func badgeTrailing(_ total: Int, style: NSScroller.Style) -> CGFloat {
            scroll.scrollerStyle = style
            rows.count = total; table.reloadData()
            table.fit(in: scroll, rowCount: total)
            table.layoutSubtreeIfNeeded()
            let tab = table.view(atColumn: 0, row: 0, makeIfNecessary: true) as! CommandResultCell
            tab.layoutSubtreeIfNeeded()
            let badge = field(tab, "→")!.superview!
            return container.bounds.width - badge.convert(badge.bounds, to: container).maxX
        }
        let legacyWidth = NSScroller.scrollerWidth(for: .regular, scrollerStyle: .legacy)
        for (total, style, reserve) in [(8, NSScroller.Style.legacy, legacyWidth), (3, .legacy, 0), (8, .overlay, 0)] {
            let trailing = badgeTrailing(total, style: style)
            let name = style == .legacy ? "permanent" : "overlay"
            expect(scroll.scrollerReserve == reserve, "\(total) rows with \(name) scroll bars reserve \(reserve) points")
            expect(abs(Compact.trailing + scroll.scrollerReserve - trailing) < 0.01,
                   "the address row ends on the badge column with \(total) rows and \(name) scroll bars")
        }
        _ = badgeTrailing(8, style: .overlay)
        tiledReserves.removeAll()
        scroll.scrollerStyle = .legacy; scroll.layoutSubtreeIfNeeded()
        expect(tiledReserves.last == legacyWidth, "switching to permanent scroll bars re-tiles the list and reports the reserved width")
        let switched = badgeTrailing(8, style: .legacy)
        expect(abs(Compact.trailing + scroll.scrollerReserve - switched) < 0.01, "the address row follows the list after the setting changes")
        scroll.isHidden = true
        expect(scroll.scrollerReserve == 0, "a hidden list reserves nothing for its scroller")
        surface.orderOut(nil)
        print("CommandBar compact layout tests passed (\(count) assertions)")
    }
}

@MainActor private final class ResultRows: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    var count = 0
    func numberOfRows(in tableView: NSTableView) -> Int { count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        CommandResultCell(title: "Gmail \(row)", subtitle: "— mail.example.com", detail: "", accessory: "Switch to Tab", isTab: true,
                          icon: NSImage(systemSymbolName: "clock", accessibilityDescription: nil), enabled: true)
    }
}
