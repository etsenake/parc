import AppKit
import Testing
@testable import Parc

@MainActor
struct TooltipViewConfigurationTests {
    private static let configuration = TooltipConfiguration("Hide sidebar", shortcut: .command("toggleSidebar:"))

    private func configured() -> NSView {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 32, height: 32))
        view.toolTip = "Hide sidebar ⌘S"
        view.parcTooltip = Self.configuration
        return view
    }

    @Test func aConfigurationReplacesTheAppKitHelpTag() {
        let view = configured()
        #expect(view.parcTooltip == Self.configuration && view.toolTip == nil)
    }

    @Test func aConfigurationTracksThePointerWithOneArea() {
        #expect(configured().trackingAreas.count == 1)
    }

    @Test func theAreaTracksEnteredExitedAndMovedInEveryWindowStateOverTheVisibleRect() throws {
        let area = try #require(configured().trackingAreas.first)
        #expect(area.options.isSuperset(of: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect]))
        #expect(area.userInfo == nil)
    }

    @Test func theAreaIsOwnedByTheViewsTooltipTracker() throws {
        let view = configured()
        let area = try #require(view.trackingAreas.first)
        #expect(area.owner is NSResponder && area.owner !== view)
    }

    @Test func updatesReuseTheOneTrackingArea() throws {
        let view = configured()
        let area = try #require(view.trackingAreas.first)
        view.parcTooltip = Self.configuration
        view.parcTooltip = TooltipConfiguration("Lock sidebar", shortcut: .command("toggleSidebar:"))
        #expect(view.trackingAreas.count == 1 && view.trackingAreas.first === area)
        #expect(view.parcTooltip?.label == "Lock sidebar")
    }

    @Test func nilRemovesTheTooltipAndItsTrackingArea() {
        let view = configured()
        view.parcTooltip = nil
        #expect(view.parcTooltip == nil && view.trackingAreas.isEmpty)
    }

    @Test func eachWindowHasOneControllerNeutralUntilTold() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 100), styleMask: .borderless, backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        let controller = TooltipController.controller(for: window)
        #expect(TooltipController.controller(for: window) === controller && controller.palette == nil)
        #expect(!window.isVisible && !window.isKeyWindow)
    }

    private func button() -> NSButton {
        let button = NSButton(title: "", target: nil, action: nil)
        button.toolTip = "Go back ⌘["
        return button
    }

    @Test func aControlGetsTheTooltipPillWithItsCommandsLiveKeycapsAndNoHelpTag() {
        let button = button()
        LiveShortcutToolTip.set(button, "Go back", commandID: "goBack:", binder: nil)
        #expect(button.parcTooltip == TooltipConfiguration("Go back", shortcut: .command("goBack:")))
        #expect(button.toolTip == nil)
    }

    @Test func withoutTheAppsBinderTheHelpIsTheTitleOnTheButtonAndItsCell() {
        let button = button()
        LiveShortcutToolTip.set(button, "Go back", commandID: "goBack:", binder: nil)
        #expect(button.accessibilityHelp() == "Go back" && button.cell?.accessibilityHelp() == "Go back")
    }

    @Test func aSitesOwnAnchorAndDelayWithNoCommandHaveNoKeycaps() {
        let button = button()
        LiveShortcutToolTip.set(button, "Remove Personal Filter", anchor: .top, behavior: .onMouseIdle(delay: 0.6), binder: nil)
        #expect(button.parcTooltip == TooltipConfiguration("Remove Personal Filter", anchor: .top, behavior: .onMouseIdle(delay: 0.6)))
    }

    @Test func aBindingOnlyTooltipWithoutABinderHasNoHelp() {
        let button = button()
        LiveShortcutToolTip.set(button, "Reset Tab", commandID: "resetTab:", requiresBinding: true, binder: nil)
        #expect(button.parcTooltip?.requiresShortcut == true && button.accessibilityHelp() == nil)
    }

    @Test func theAppsBinderKeepsTheHelpOnTheLiveBinding() {
        let button = button()
        var bound: [(String, String?, Bool)] = []
        LiveShortcutToolTip.set(button, "Go back", commandID: "goBack:") { view, title, id, requires in
            bound.append((title, id, requires)); view.setAccessibilityHelp(title + " ⌘[")
        }
        #expect(bound.count == 1 && bound.first.map { $0 == ("Go back", "goBack:", false) } == true)
        #expect(button.accessibilityHelp() == "Go back ⌘[")
    }

    @Test func helpAloneSuitsAControlWithoutATooltip() {
        let pill = NSButton(title: "", target: nil, action: nil)
        var bound: [(String, String?, Bool)] = []
        LiveShortcutToolTip.help(pill, "New tab", commandID: "newTab:") { _, title, id, requires in bound.append((title, id, requires)) }
        #expect(pill.parcTooltip == nil && pill.toolTip == nil)
        #expect(bound.last.map { $0 == ("New tab", "newTab:", false) } == true)
    }
}
