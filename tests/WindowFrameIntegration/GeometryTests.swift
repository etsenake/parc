import AppKit

@main struct WindowFrameGeometryTests {
    static var count = 0
    static func check(_ value: @autoclosure () -> Bool, _ message: String) {
        count += 1
        guard value() else { fatalError("WindowFrameGeometry: \(message)") }
    }

    static func frames(_ presentation: SidebarPresentation, thickness: CGFloat, popup: Bool = false, fullscreen: Bool = false,
                       library: Bool = false, sidePanel: Bool = false) -> SidebarChromeFrames {
        let placement = SidebarPresentationFrame(presentation, inMotion: false, floatingSurface: presentation == .floating,
                                                 revealsAnchored: false)
        return SidebarChromeFrames(bounds: NSRect(x: 0, y: 0, width: 1200, height: 760), sidebarWidth: 240,
                                   presentation: presentation, placement: placement, fullscreen: fullscreen, library: library,
                                   libraryContentWidth: 500, popup: popup, sidePanel: sidePanel, thickness: thickness)
    }

    static func main() { exitOnFailure(runChecks) }
    static func runChecks() {
        for thickness in [CGFloat(3), 10, 13] {
            let hidden = frames(.hidden, thickness: thickness).pageHost
            check(hidden == NSRect(x: thickness, y: thickness, width: 1200 - 2 * thickness, height: 760 - 2 * thickness),
                  "a hidden sidebar frames the page on all four sides at \(thickness)")
            let floating = frames(.floating, thickness: thickness).pageHost
            check(floating == hidden, "a floating sidebar frames the page like a hidden one at \(thickness)")
            let locked = frames(.locked, thickness: thickness).pageHost
            check(locked == NSRect(x: 240, y: thickness, width: 1200 - 240 - thickness, height: 760 - 2 * thickness),
                  "a docked sidebar forms the left edge at \(thickness)")
            let panel = frames(.hidden, thickness: thickness, sidePanel: true)
            check(panel.sidePanel.maxX == 1200 - thickness && panel.pageHost.maxX == panel.sidePanel.minX,
                  "the side panel shares the right margin at \(thickness)")
            let popup = frames(.hidden, thickness: thickness, popup: true).pageHost
            check(popup.minX == 8 && popup.minY == 10 + 47 && 1200 - popup.maxX == 10, "popups keep their compact chrome at \(thickness)")
            check(frames(.hidden, thickness: thickness, fullscreen: true).pageHost == NSRect(x: 0, y: 0, width: 1200, height: 760),
                  "full screen stays frameless at \(thickness)")
            let library = frames(.locked, thickness: thickness, library: true)
            check(library.pageHost.minX == library.library.maxX && library.pageHost.minY == thickness,
                  "Library keeps its column and follows the frame elsewhere at \(thickness)")
        }
        let standard = SidebarChromeFrames(bounds: NSRect(x: 0, y: 0, width: 1200, height: 760), sidebarWidth: 240,
                                           presentation: .hidden, placement: .hidden)
        check(standard.pageHost == frames(.hidden, thickness: 10).pageHost, "the default thickness is today's 10 points")
        print("WindowFrame geometry: \(count) checks passed")
    }
}
