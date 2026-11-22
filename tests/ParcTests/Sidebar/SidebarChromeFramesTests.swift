import AppKit
import Testing
@testable import Parc
@testable import ParcLibrary
@testable import ParcSidebar

struct SidebarChromeFramesTests {
    private let root = NSRect(x: 0, y: 0, width: 1470, height: 831)
    private let libraryWindow = NSRect(x: 0, y: 0, width: 1280, height: 832)

    private func chrome(_ presentation: SidebarPresentation, _ placement: SidebarPresentationFrame, previewingHidden: Bool = false,
                        fullscreen: Bool = false, library: Bool = false, popup: Bool = false, panel: Bool = false) -> SidebarChromeFrames {
        SidebarChromeFrames(bounds: root, sidebarWidth: 228, presentation: presentation, placement: placement, previewingHidden: previewingHidden,
                            fullscreen: fullscreen, library: library, popup: popup, sidePanel: panel)
    }

    @Test func lockedChromePutsThePageBesideTheSidebar() {
        let locked = chrome(.locked, .locked)
        #expect(locked.sidebar == SidebarPresentationFrame.locked.rect(width: 228, in: root))
        #expect(locked.pageHost == NSRect(x: 228, y: 10, width: 1232, height: 811))
    }

    @Test func hiddenChromeInsetsThePageFromTheWindowEdge() {
        let away = chrome(.hidden, .hidden)
        #expect(away.sidebar == SidebarPresentationFrame.hidden.rect(width: 228, in: root))
        #expect(away.pageHost == NSRect(x: 10, y: 10, width: 1450, height: 811))
    }

    @Test func aWidthDragsHiddenPreviewShowsHiddenGeometry() {
        let preview = chrome(.locked, .locked, previewingHidden: true)
        #expect(preview.sidebar.minX == -228 && preview.pageHost.minX == 10)
    }

    @Test func theSidePanelSitsBesideThePage() {
        let paneled = chrome(.locked, .locked, panel: true)
        #expect(paneled.showsSidePanel)
        #expect(paneled.pageHost == NSRect(x: 228, y: 10, width: 872, height: 811))
        #expect(paneled.sidePanel == NSRect(x: 1100, y: 10, width: 360, height: 811))
    }

    @Test func pageFullScreenFillsTheWindowWithoutThePanel() {
        let fullscreen = chrome(.locked, .locked, fullscreen: true, panel: true)
        #expect(fullscreen.pageHost == root && !fullscreen.showsSidePanel)
    }

    @Test func popupChromeSitsAboveThePage() {
        let popup = chrome(.hidden, .hidden, popup: true)
        #expect(popup.pageHost == NSRect(x: 8, y: 57, width: 1452, height: 764))
        #expect(popup.popupChrome == NSRect(x: 8, y: 0, width: 1454, height: 47))
    }

    @Test func theLibraryIs417WideBeforeAPageReportsItsWidth() {
        let library = chrome(.locked, .locked, library: true)
        #expect(library.library.width == 417 && library.pageHost.minX == 417)
    }

    @Test func aDefaultWidthLibraryInsetsItsPageVertically() {
        let frames = SidebarChromeFrames(bounds: libraryWindow, sidebarWidth: 228, presentation: .locked, placement: .locked,
                                         library: true, libraryContentWidth: LibraryView.minimumWidth)
        #expect(frames.library == NSRect(x: 0, y: 0, width: 417, height: 832))
        #expect(frames.pageHost == NSRect(x: 417, y: 10, width: 853, height: 812))
    }

    @Test(arguments: [
        (480.0, 1470.0, 480.0),
        (744.0, 1470.0, 744.0),
        (1536.0, 1470.0, 1414.0),
        (744.0, 760.0, 704.0),
        (417.0, 1470.0, 417.0),
        (300.0, 1470.0, 417.0),
        (0.0, 1470.0, 417.0),
        (480.0, 400.0, 417.0),
    ] as [(CGFloat, CGFloat, CGFloat)])
    func libraryWidthFollowsItsContentBetweenTheFloorAndTheWindow(content: CGFloat, width: CGFloat, expected: CGFloat) {
        let frames = SidebarChromeFrames(bounds: NSRect(x: 0, y: 0, width: width, height: 831), sidebarWidth: 228, presentation: .locked,
                                         placement: .locked, library: true, libraryContentWidth: content)
        #expect(frames.library == NSRect(x: 0, y: 0, width: expected, height: 831))
        #expect(frames.pageHost == NSRect(x: expected, y: 10, width: max(0, width - expected - 10), height: 811))
    }

    @Test func theExtensionPanelStartsAtAWideLibrarysEdge() {
        let frames = SidebarChromeFrames(bounds: libraryWindow, sidebarWidth: 228, presentation: .locked, placement: .locked,
                                         library: true, libraryContentWidth: 1008, sidePanel: true)
        #expect(frames.library.width == 1008 && frames.showsSidePanel)
        #expect(frames.sidePanel.minX == 1008 && frames.sidePanel.maxX == 1270 && frames.pageHost.width == 0)
    }

    @Test func the417LibraryWidthIsAFloorNotACap() {
        let frames = SidebarChromeFrames(bounds: NSRect(x: 0, y: 0, width: 400, height: 600), sidebarWidth: 228,
                                         presentation: .locked, placement: .locked, library: true)
        #expect(frames.library.width == 417 && frames.pageHost.minX == 417)
    }

    @Test func fullScreenHidesTheLibraryColumn() {
        let frames = SidebarChromeFrames(bounds: libraryWindow, sidebarWidth: 228, presentation: .locked, placement: .locked,
                                         fullscreen: true, library: true, libraryContentWidth: 744)
        #expect(frames.library.width == 0 && frames.pageHost == libraryWindow)
    }

    @Test(arguments: [
        (1470.0, 831.0, 228.0, false, false),
        (760.0, 540.0, 420.0, false, false),
        (760.0, 540.0, 228.0, false, true),
        (300.0, 160.0, 0.0, true, false),
        (400.0, 300.0, 300.0, false, false),
        (0.0, 0.0, 228.0, false, false),
    ] as [(CGFloat, CGFloat, CGFloat, Bool, Bool)])
    func theExtensionPanelFitsTheWindowAndFollowsThePage(width: CGFloat, height: CGFloat, sidebarWidth: CGFloat, popup: Bool, library: Bool) {
        let panel = SidebarChromeFrames(bounds: NSRect(x: 0, y: 0, width: width, height: height), sidebarWidth: sidebarWidth,
                                        presentation: popup ? .hidden : .locked, placement: popup ? .hidden : .locked,
                                        library: library, popup: popup, sidePanel: true)
        #expect(panel.sidePanel.width >= 0 && panel.sidePanel.minX >= 0 && panel.sidePanel.maxX <= width && panel.pageHost.width >= 0)
        #expect(panel.sidePanel.minY == panel.pageHost.minY && panel.sidePanel.maxY == panel.pageHost.maxY)
        if panel.sidePanel.width > 0 { #expect(panel.sidePanel.minX == panel.pageHost.maxX) }
    }
}
