import AppKit
import Testing
@testable import ParcCore
@testable import ParcSidebar

struct WindowFrameGeometryTests {
    private static func frames(_ presentation: SidebarPresentation, thickness: CGFloat, popup: Bool = false, fullscreen: Bool = false,
                               library: Bool = false, sidePanel: Bool = false) -> SidebarChromeFrames {
        let placement = SidebarPresentationFrame(presentation, inMotion: false, floatingSurface: presentation == .floating, revealsAnchored: false)
        return SidebarChromeFrames(bounds: NSRect(x: 0, y: 0, width: 1200, height: 760), sidebarWidth: 240, presentation: presentation,
                                   placement: placement, fullscreen: fullscreen, library: library, libraryContentWidth: 500, popup: popup,
                                   sidePanel: sidePanel, thickness: thickness)
    }

    @Test(arguments: [CGFloat(3), 10, 13])
    func aHiddenSidebarFramesThePageOnAllFourSides(_ t: CGFloat) {
        #expect(Self.frames(.hidden, thickness: t).pageHost == NSRect(x: t, y: t, width: 1200 - 2 * t, height: 760 - 2 * t))
    }

    @Test(arguments: [CGFloat(3), 10, 13])
    func aFloatingSidebarFramesThePageLikeAHiddenOne(_ t: CGFloat) {
        #expect(Self.frames(.floating, thickness: t).pageHost == Self.frames(.hidden, thickness: t).pageHost)
    }

    @Test(arguments: [CGFloat(3), 10, 13])
    func aDockedSidebarFormsTheLeftEdge(_ t: CGFloat) {
        #expect(Self.frames(.locked, thickness: t).pageHost == NSRect(x: 240, y: t, width: 1200 - 240 - t, height: 760 - 2 * t))
    }

    @Test(arguments: [CGFloat(3), 10, 13])
    func theSidePanelSharesTheRightMargin(_ t: CGFloat) {
        let panel = Self.frames(.hidden, thickness: t, sidePanel: true)
        #expect(panel.sidePanel.maxX == 1200 - t)
        #expect(panel.pageHost.maxX == panel.sidePanel.minX)
    }

    @Test(arguments: [CGFloat(3), 10, 13])
    func popupsKeepTheirCompactChrome(_ t: CGFloat) {
        let popup = Self.frames(.hidden, thickness: t, popup: true).pageHost
        #expect(popup.minX == CGFloat(8))
        #expect(popup.minY == CGFloat(57))
        #expect(CGFloat(1200) - popup.maxX == CGFloat(10))
    }

    @Test(arguments: [CGFloat(3), 10, 13])
    func fullScreenStaysFrameless(_ t: CGFloat) {
        #expect(Self.frames(.hidden, thickness: t, fullscreen: true).pageHost == NSRect(x: 0, y: 0, width: 1200, height: 760))
    }

    @Test(arguments: [CGFloat(3), 10, 13])
    func theLibraryKeepsItsColumnAndFollowsTheFrameElsewhere(_ t: CGFloat) {
        let library = Self.frames(.locked, thickness: t, library: true)
        #expect(library.pageHost.minX == library.library.maxX)
        #expect(library.pageHost.minY == t)
    }

    @Test func theDefaultThicknessIsTodaysTenPoints() {
        let standard = SidebarChromeFrames(bounds: NSRect(x: 0, y: 0, width: 1200, height: 760), sidebarWidth: 240, presentation: .hidden, placement: .hidden)
        #expect(standard.pageHost == Self.frames(.hidden, thickness: 10).pageHost)
    }
}
