import AppKit
import Testing
@testable import Parc

struct ExtensionSidePanelNeedsDisplayTests {
    @MainActor private func panel() -> ExtensionSidePanelView {
        let panel = ExtensionSidePanelView(frame: CGRect(x: 0, y: 0, width: 320, height: 600))
        panel.layout()
        return panel
    }

    @MainActor private func title(in panel: ExtensionSidePanelView) throws -> NSTextField {
        try #require(panel.subviews.compactMap { $0 as? NSTextField }.first)
    }

    @MainActor @Test func theFirstLayoutInvalidatesTheHeader() {
        #expect(panel().headerDisplayInvalidations == 1)
    }

    @MainActor @Test func theHeaderLeavesTheContentBelowIt() {
        #expect(panel().content.frame == CGRect(x: 0, y: ExtensionSidePanelView.headerHeight,
            width: 320, height: 600 - ExtensionSidePanelView.headerHeight))
    }

    @MainActor @Test func theFullWidthHeaderShowsTheCloseButtonAndTitle() throws {
        let view = panel()
        #expect(!view.closeButton.isHidden)
        #expect(try !title(in: view).isHidden)
    }

    @MainActor @Test(arguments: [CGFloat(320), 280])
    func unchangedGeometryNeverInvalidatesTheHeaderAgain(_ width: CGFloat) {
        let view = panel()
        view.setFrameSize(CGSize(width: width, height: 600))
        view.layout()
        let count = view.headerDisplayInvalidations
        view.layout()
        #expect(view.headerDisplayInvalidations == count)
    }

    @MainActor @Test func aNarrowerHeaderRelaysOutTheTitle() throws {
        let view = panel()
        let title = try title(in: view)
        let prior = title.frame
        view.setFrameSize(CGSize(width: 280, height: 600))
        view.layout()
        #expect(title.frame.width < prior.width)
    }

    @MainActor @Test func theTitleHidesWhenThePanelIsTooNarrow() throws {
        let view = panel()
        view.setFrameSize(CGSize(width: 100, height: 600))
        view.layout()
        #expect(try title(in: view).isHidden)
    }

    @MainActor @Test(arguments: [CGSize(width: 280, height: 600), CGSize(width: 100, height: 600), CGSize(width: 320, height: 480)])
    func changedChromeGeometryInvalidatesTheHeader(_ size: CGSize) {
        let view = panel()
        let count = view.headerDisplayInvalidations
        view.setFrameSize(size)
        view.layout()
        #expect(view.headerDisplayInvalidations == count + 1)
    }

    @MainActor @Test func anAppearanceChangeInvalidatesTheHeaderFill() {
        let view = panel()
        let count = view.headerDisplayInvalidations
        view.viewDidChangeEffectiveAppearance()
        #expect(view.headerDisplayInvalidations == count + 1)
    }
}
