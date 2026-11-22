import CoreGraphics
import Foundation
import Testing
@testable import ParcSidebar

struct LayoutChromeGeometrySkipTests {
    private static func fingerprint(
        width: CGFloat = 1200, height: CGFloat = 800, sidebarWidth: CGFloat = 228,
        presentation: SidebarPresentation = .locked, motionVisible: Bool = false, floatingSurface: Bool = false,
        revealsAnchored: Bool = false, previewingHidden: Bool = false, fullscreen: Bool = false, library: Bool = false,
        libraryContentWidth: CGFloat = 0, popup: Bool = false, sidePanel: Bool = false, findVisible: Bool = false,
        resizing: Bool = false, currentTabID: UUID? = nil, activePeekID: UUID? = nil, commandBarOpen: Bool = false,
        windowClosePending: Bool = false, transferringTabIDs: [UUID] = [], frameThickness: CGFloat = 10
    ) -> LayoutChromeGeometryFingerprint {
        LayoutChromeGeometryFingerprint(
            boundsWidth: width, boundsHeight: height, sidebarWidth: sidebarWidth, presentation: presentation,
            motionVisible: motionVisible, floatingSurface: floatingSurface, revealsAnchored: revealsAnchored,
            previewingHidden: previewingHidden, fullscreen: fullscreen, library: library,
            libraryContentWidth: libraryContentWidth, popup: popup, sidePanel: sidePanel, findVisible: findVisible,
            resizing: resizing, currentTabID: currentTabID, activePeekID: activePeekID, commandBarOpen: commandBarOpen,
            windowClosePending: windowClosePending, transferringTabIDs: transferringTabIDs, frameThickness: frameThickness)
    }

    private static func skips(_ previous: LayoutChromeGeometryFingerprint?, _ next: LayoutChromeGeometryFingerprint, dirty: Bool = false) -> Bool {
        LayoutChromeGeometrySkip.shouldReturnEarly(previous: previous, next: next, dirtyHostedLayout: dirty)
    }

    @Test func theFirstApplyRuns() {
        #expect(!Self.skips(nil, Self.fingerprint()))
    }

    @Test func identicalGeometryWithACleanHostedTreeIsATrueNoOp() {
        #expect(Self.skips(Self.fingerprint(), Self.fingerprint()))
    }

    @Test func aDirtyHostedTreeStillEnters() {
        #expect(!Self.skips(Self.fingerprint(), Self.fingerprint(), dirty: true))
    }

    @Test func aSidebarPresentationOrMotionChangeRuns() {
        #expect(!Self.skips(Self.fingerprint(), Self.fingerprint(presentation: .hidden, motionVisible: true)))
    }

    @Test func aBoundsChangeRuns() {
        #expect(!Self.skips(Self.fingerprint(), Self.fingerprint(width: 1100)))
    }

    @Test func aSidebarWidthChangeRuns() {
        #expect(!Self.skips(Self.fingerprint(), Self.fingerprint(sidebarWidth: 300)))
    }

    @Test func sidePanelVisibilityRuns() {
        #expect(!Self.skips(Self.fingerprint(), Self.fingerprint(sidePanel: true)))
    }

    @Test func findBarVisibilityRuns() {
        #expect(!Self.skips(Self.fingerprint(), Self.fingerprint(findVisible: true)))
    }

    @Test func aLibraryPageWidthChangeRuns() {
        #expect(!Self.skips(Self.fingerprint(library: true, libraryContentWidth: 417), Self.fingerprint(library: true, libraryContentWidth: 480)))
    }

    @Test func motionSettlingRunsTheFullPass() {
        #expect(!Self.skips(Self.fingerprint(presentation: .hidden, motionVisible: true), Self.fingerprint(presentation: .hidden, motionVisible: false)))
    }

    @Test func aFloatingSurfaceSettleRuns() {
        #expect(!Self.skips(Self.fingerprint(presentation: .floating, motionVisible: true, floatingSurface: true),
                            Self.fingerprint(presentation: .floating, motionVisible: false, floatingSurface: false)))
    }

    @Test func aTabSelectionChangeRuns() {
        #expect(!Self.skips(Self.fingerprint(currentTabID: UUID()), Self.fingerprint(currentTabID: UUID())))
    }

    @Test func aPeekPresentationRuns() {
        let tab = UUID()
        #expect(!Self.skips(Self.fingerprint(currentTabID: tab), Self.fingerprint(currentTabID: tab, activePeekID: UUID())))
    }

    @Test func openingTheCommandBarRuns() {
        let tab = UUID()
        #expect(!Self.skips(Self.fingerprint(currentTabID: tab), Self.fingerprint(currentTabID: tab, commandBarOpen: true)))
    }

    @Test func inFlightTabTransfersRun() {
        let tab = UUID()
        #expect(!Self.skips(Self.fingerprint(currentTabID: tab), Self.fingerprint(currentTabID: tab, transferringTabIDs: [tab])))
    }

    @Test func aWindowFrameThicknessChangeRelaysOutOpenWindows() {
        #expect(!Self.skips(Self.fingerprint(), Self.fingerprint(frameThickness: 7)))
    }

    @Test func aLiveCrankPreviewBetweenPointsRelaysOut() {
        #expect(!Self.skips(Self.fingerprint(frameThickness: 10), Self.fingerprint(frameThickness: 10.4)))
    }
}
