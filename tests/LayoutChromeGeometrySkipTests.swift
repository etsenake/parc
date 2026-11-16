import CoreGraphics
import Foundation

@main
struct LayoutChromeGeometrySkipTests {
    static var assertions = 0
    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        assertions += 1
        precondition(condition(), message)
    }

    static func fingerprint(
        width: CGFloat = 1200,
        height: CGFloat = 800,
        sidebarWidth: CGFloat = 228,
        presentation: SidebarPresentation = .locked,
        motionVisible: Bool = false,
        floatingSurface: Bool = false,
        revealsAnchored: Bool = false,
        previewingHidden: Bool = false,
        fullscreen: Bool = false,
        library: Bool = false,
        libraryContentWidth: CGFloat = 0,
        popup: Bool = false,
        sidePanel: Bool = false,
        findVisible: Bool = false,
        resizing: Bool = false,
        currentTabID: UUID? = nil,
        activePeekID: UUID? = nil,
        commandBarOpen: Bool = false,
        windowClosePending: Bool = false,
        transferringTabIDs: [UUID] = [],
        frameThickness: CGFloat = 10
    ) -> LayoutChromeGeometryFingerprint {
        LayoutChromeGeometryFingerprint(
            boundsWidth: width,
            boundsHeight: height,
            sidebarWidth: sidebarWidth,
            presentation: presentation,
            motionVisible: motionVisible,
            floatingSurface: floatingSurface,
            revealsAnchored: revealsAnchored,
            previewingHidden: previewingHidden,
            fullscreen: fullscreen,
            library: library,
            libraryContentWidth: libraryContentWidth,
            popup: popup,
            sidePanel: sidePanel,
            findVisible: findVisible,
            resizing: resizing,
            currentTabID: currentTabID,
            activePeekID: activePeekID,
            commandBarOpen: commandBarOpen,
            windowClosePending: windowClosePending,
            transferringTabIDs: transferringTabIDs,
            frameThickness: frameThickness
        )
    }

    @MainActor static func main() { exitOnFailure(runChecks) }
    @MainActor static func runChecks() {
        let settled = fingerprint()
        expect(!LayoutChromeGeometrySkip.shouldReturnEarly(
            previous: nil, next: settled, dirtyHostedLayout: false),
               "First layoutChrome apply must run")
        expect(LayoutChromeGeometrySkip.shouldReturnEarly(
            previous: settled, next: settled, dirtyHostedLayout: false),
               "Identical chrome geometry with a clean hosted tree is a true no-op")
        expect(!LayoutChromeGeometrySkip.shouldReturnEarly(
            previous: settled, next: settled, dirtyHostedLayout: true),
               "Dirty pageHost / side-panel still enters for P1-W/P1-S flushes")

        expect(!LayoutChromeGeometrySkip.shouldReturnEarly(
            previous: settled,
            next: fingerprint(presentation: .hidden, motionVisible: true),
            dirtyHostedLayout: false),
               "Cmd-S presentation / motion inputs must still run layoutChrome")
        expect(!LayoutChromeGeometrySkip.shouldReturnEarly(
            previous: settled,
            next: fingerprint(width: 1100),
            dirtyHostedLayout: false),
               "Bounds changes must still run layoutChrome")
        expect(!LayoutChromeGeometrySkip.shouldReturnEarly(
            previous: settled,
            next: fingerprint(sidebarWidth: 300),
            dirtyHostedLayout: false),
               "Sidebar width changes must still run layoutChrome")
        expect(!LayoutChromeGeometrySkip.shouldReturnEarly(
            previous: settled,
            next: fingerprint(sidePanel: true),
            dirtyHostedLayout: false),
               "Side-panel visibility must still run layoutChrome")
        expect(!LayoutChromeGeometrySkip.shouldReturnEarly(
            previous: settled,
            next: fingerprint(findVisible: true),
            dirtyHostedLayout: false),
               "Find-bar visibility must still run layoutChrome")
        expect(!LayoutChromeGeometrySkip.shouldReturnEarly(
            previous: fingerprint(library: true, libraryContentWidth: 417),
            next: fingerprint(library: true, libraryContentWidth: 480),
            dirtyHostedLayout: false),
               "A Library page width change must still run layoutChrome")
        expect(!LayoutChromeGeometrySkip.shouldReturnEarly(
            previous: fingerprint(presentation: .hidden, motionVisible: true),
            next: fingerprint(presentation: .hidden, motionVisible: false),
            dirtyHostedLayout: false),
               "Cmd-S completion settling motionVisible must still run the full pass")
        expect(!LayoutChromeGeometrySkip.shouldReturnEarly(
            previous: fingerprint(presentation: .floating, motionVisible: true, floatingSurface: true),
            next: fingerprint(presentation: .floating, motionVisible: false, floatingSurface: false),
            dirtyHostedLayout: false),
               "Floating surface settle must still run layoutChrome")

        let tabA = UUID(), tabB = UUID()
        expect(!LayoutChromeGeometrySkip.shouldReturnEarly(
            previous: fingerprint(currentTabID: tabA),
            next: fingerprint(currentTabID: tabB),
            dirtyHostedLayout: false),
               "Tab selection changes must still run easel eligibility refresh")
        expect(!LayoutChromeGeometrySkip.shouldReturnEarly(
            previous: fingerprint(currentTabID: tabA),
            next: fingerprint(currentTabID: tabA, activePeekID: UUID()),
            dirtyHostedLayout: false),
               "Peek presentation must still run layoutChrome eligibility work")
        expect(!LayoutChromeGeometrySkip.shouldReturnEarly(
            previous: fingerprint(currentTabID: tabA),
            next: fingerprint(currentTabID: tabA, commandBarOpen: true),
            dirtyHostedLayout: false),
               "Command-bar open must still run layoutChrome eligibility work")
        expect(!LayoutChromeGeometrySkip.shouldReturnEarly(
            previous: fingerprint(currentTabID: tabA),
            next: fingerprint(currentTabID: tabA, transferringTabIDs: [tabA]),
            dirtyHostedLayout: false),
               "In-flight tab transfers must still run layoutChrome eligibility work")

        expect(!LayoutChromeGeometrySkip.shouldReturnEarly(
            previous: settled,
            next: fingerprint(frameThickness: 7),
            dirtyHostedLayout: false),
               "A window frame thickness change must relayout open windows")
        expect(!LayoutChromeGeometrySkip.shouldReturnEarly(
            previous: fingerprint(frameThickness: 10),
            next: fingerprint(frameThickness: 10.4),
            dirtyHostedLayout: false),
               "A live crank preview between points must relayout")

        print("\(assertions) layoutChrome geometry skip assertions passed")
    }
}
