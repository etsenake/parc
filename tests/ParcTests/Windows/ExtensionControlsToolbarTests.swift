import AppKit
import QuartzCore
import Testing
@testable import ParcSidebar

@MainActor
struct ExtensionControlsToolbarTests {
    private func toolbar(width: CGFloat = 56, style: ExtensionControlStyle = .sidebar) -> ExtensionToolbarView {
        ExtensionToolbarView(frame: NSRect(x: 0, y: 0, width: width, height: style.surfaceSize.height), style: style)
    }

    private func button(_ view: ExtensionToolbarView, _ id: String) -> NSView? {
        view.subviews.first { $0.accessibilityIdentifier() == "extension-action-" + id }
    }

    @Test func onlyPinnedActionsReserveToolbarWidth() {
        let view = toolbar()
        view.update([ExtensionControlsSupport.controlItem("a", pin: 1), ExtensionControlsSupport.controlItem("b", pin: 0), ExtensionControlsSupport.controlItem("c")])
        view.layoutSubtreeIfNeeded()
        #expect(view.desiredWidth == 56)
    }

    @Test func unpinnedActionsStayOutOfTheToolbar() {
        let view = toolbar()
        view.update([ExtensionControlsSupport.controlItem("a", pin: 1), ExtensionControlsSupport.controlItem("b", pin: 0), ExtensionControlsSupport.controlItem("c")])
        #expect(view.subviews.count == 2)
    }

    @Test func pinPositionsOverrideModelOrder() throws {
        let view = toolbar()
        view.update([ExtensionControlsSupport.controlItem("a", pin: 1), ExtensionControlsSupport.controlItem("b", pin: 0)])
        view.layoutSubtreeIfNeeded()
        let a = try #require(button(view, "a")), b = try #require(button(view, "b"))
        #expect(b.frame.minX < a.frame.minX)
    }

    @Test func ordinaryUpdatesPreserveButtonIdentityAndDoNotRelayout() throws {
        let view = toolbar()
        var widths = 0
        view.onWidthChange = { widths += 1 }
        view.update([ExtensionControlsSupport.controlItem("a", pin: 1), ExtensionControlsSupport.controlItem("b", pin: 0)])
        view.layoutSubtreeIfNeeded()
        let a = try #require(button(view, "a"))
        view.update([ExtensionControlsSupport.controlItem("a", pin: 1), ExtensionControlsSupport.controlItem("b", pin: 0)])
        #expect(view.subviews.contains { $0 === a })
        #expect(widths == 1)
    }

    @Test func compressionHidesTheLaterPin() throws {
        let view = toolbar()
        view.update([ExtensionControlsSupport.controlItem("a", pin: 1), ExtensionControlsSupport.controlItem("b", pin: 0)])
        view.layoutSubtreeIfNeeded()
        view.frame.size.width = 28
        view.needsLayout = true
        view.layoutSubtreeIfNeeded()
        let a = try #require(button(view, "a")), b = try #require(button(view, "b"))
        #expect(a.isHidden)
        #expect(!b.isHidden)
    }

    @Test func aRemovedPinIsDetachedAndDisabled() throws {
        let view = toolbar()
        view.update([ExtensionControlsSupport.controlItem("a", pin: 1), ExtensionControlsSupport.controlItem("b", pin: 0)])
        view.layoutSubtreeIfNeeded()
        let a = try #require(button(view, "a") as? NSButton)
        view.update([ExtensionControlsSupport.controlItem("b", pin: 0)])
        #expect(a.superview == nil)
        #expect(!a.isEnabled)
    }

    @Test func clearingReleasesEveryPin() {
        let view = toolbar()
        view.update([ExtensionControlsSupport.controlItem("a", pin: 1), ExtensionControlsSupport.controlItem("b", pin: 0)])
        view.update([])
        #expect(view.desiredWidth == 0)
        #expect(view.subviews.isEmpty)
    }

    @Test func aSixtyThreePointToolbarHoldsOneCompleteAction() {
        let view = toolbar(width: 63, style: .toolbar)
        view.update([ExtensionControlsSupport.controlItem("first", pin: 0), ExtensionControlsSupport.controlItem("second", pin: 1)])
        view.layoutSubtreeIfNeeded()
        let buttons = view.orderedButtons
        #expect(view.desiredWidth == 64)
        #expect(!buttons[0].isHidden)
        #expect(buttons[1].isHidden)
    }

    @Test func bothToolbarPinsFitAtSixtyFourPointsWithAdjoiningSurfaces() {
        let view = toolbar(width: 63, style: .toolbar)
        view.update([ExtensionControlsSupport.controlItem("first", pin: 0), ExtensionControlsSupport.controlItem("second", pin: 1)])
        view.frame.size.width = 64
        view.needsLayout = true
        view.layoutSubtreeIfNeeded()
        let buttons = view.orderedButtons
        #expect(!buttons[1].isHidden)
        #expect(buttons[0].frame.maxX == buttons[1].frame.minX)
    }

    @Test func theTopBarKeepsItsShortRadiusSixSurface() {
        let view = toolbar(width: 64, style: .toolbar)
        view.update([ExtensionControlsSupport.controlItem("first", pin: 0), ExtensionControlsSupport.controlItem("second", pin: 1)])
        view.layoutSubtreeIfNeeded()
        #expect(view.orderedButtons.allSatisfy { $0.frame.height == 24 && $0.layer?.cornerRadius == 6 })
    }

    @Test func sidebarPinsKeepTheirSquareRadiusNineSurface() throws {
        let view = toolbar()
        view.update([ExtensionControlsSupport.controlItem("b", pin: 0)])
        view.layoutSubtreeIfNeeded()
        let b = try #require(button(view, "b"))
        #expect(b.frame.size == NSSize(width: 28, height: 28))
        #expect(b.layer?.cornerRadius == 9)
    }
}
