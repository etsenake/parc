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
        expect(Compact.browsingIconX == 15 && Compact.browsingTextX == 38 && Compact.browsingTrailing == 11,
               "the resting Control-Space field keeps the sidebar address field's own geometry")
        print("CommandBar compact layout tests passed (\(count) assertions)")
    }
}
