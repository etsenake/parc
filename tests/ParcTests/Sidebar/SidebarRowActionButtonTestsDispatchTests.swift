import AppKit
import Testing
@testable import Parc

@MainActor
struct SidebarRowActionButtonTestsDispatchTests {
    private typealias Owner = SidebarRowActionButtonTestsSupport.Owner

    private final class FlippedRow: NSView {
        override var isFlipped: Bool { true }
    }

    private final class Separations {
        var count = 0
    }

    private func separating(_ owner: Owner) -> Separations {
        let separations = Separations()
        owner.attachReset()
        owner.reset.prepareSeparate = { [unowned owner] in
            guard owner.available else { return nil }
            var used = false
            return { guard !used else { return false }; used = true; separations.count += 1; return true }
        }
        return separations
    }

    @Test func aCommandClickSeparates() {
        let owner = Owner()
        let separations = separating(owner)
        #expect(owner.reset.lease(.command)?() == true)
        #expect(separations.count == 1)
        #expect(owner.dispatches == 0)
    }

    @Test func aCommandShiftClickStillSeparates() {
        let owner = Owner()
        let separations = separating(owner)
        #expect(owner.reset.lease([.command, .shift])?() == true)
        #expect(separations.count == 1)
    }

    @Test func aPlainClickResets() {
        let owner = Owner()
        let separations = separating(owner)
        #expect(owner.reset.lease([])?() == true)
        #expect(owner.dispatches == 1)
        #expect(separations.count == 0)
    }

    @Test func shiftAloneResetsBecauseOnlyCommandIsRead() {
        let owner = Owner()
        _ = separating(owner)
        #expect(owner.reset.lease(.shift)?() == true)
        #expect(owner.dispatches == 1)
    }

    @Test func aSeparationCommandIsOneUse() throws {
        let owner = Owner()
        let separations = separating(owner)
        let separate = try #require(owner.reset.lease(.command))
        #expect(separate())
        #expect(!separate())
        #expect(separations.count == 1)
    }

    @Test func noCommandExistsWhileTheOwnerIsUnavailable() {
        let owner = Owner()
        _ = separating(owner)
        owner.available = false
        #expect(owner.reset.lease(.command) == nil)
        #expect(owner.reset.lease([]) == nil)
    }

    @Test func theResetTooltipCarriesTheRegistryShortcut() {
        let owner = Owner()
        owner.reset.toolTip = "Reset Tab ⌥⌘R"
        #expect(owner.reset.toolTip == "Reset Tab ⌥⌘R")
    }

    @Test func theRegionContextKeepsTheRowsMenuProvider() {
        let owner = Owner()
        owner.attachReset()
        owner.reset.makeMenu = { NSMenu(title: "Original row") }
        #expect(owner.reset.menu(for: owner.rightMouseDown())?.title == "Original row")
    }

    @Test func theBodyRegionTakesNoInput() {
        let owner = Owner()
        let body = SidebarRowBodyRegionView(frame: NSRect(x: 70, y: 10, width: 100, height: 35))
        owner.window.contentView!.addSubview(body)
        #expect(body.hitTest(NSPoint(x: 80, y: 20)) == nil)
        #expect(!body.isAccessibilityElement())
    }

    @Test func darkBodyHoverUsesTheSidebarItemBackground() {
        let owner = Owner()
        let body = SidebarRowBodyRegionView(frame: NSRect(x: 70, y: 10, width: 100, height: 35))
        owner.window.contentView!.addSubview(body)
        body.dark = true
        body.hovered = true
        #expect(SidebarRowActionButtonTestsSupport.components(body.layer!.backgroundColor) == [0.98, 0.984, 1, 0.1])
    }

    @Test func theSlashIsDecorative() {
        let slash = SidebarRowSlashView(frame: NSRect(x: 0, y: 0, width: 4, height: 15))
        #expect(slash.hitTest(NSPoint(x: 2, y: 7)) == nil)
        #expect(!slash.isAccessibilityElement())
    }

    @Test func theProductionSlashRenders() throws {
        let slash = SidebarRowSlashView(frame: NSRect(x: 0, y: 0, width: 4, height: 15))
        let bitmap = try #require(slash.bitmapImageRepForCachingDisplay(in: slash.bounds))
        slash.cacheDisplay(in: slash.bounds, to: bitmap)
        #expect(bitmap.pixelsWide > 0)
    }

    @Test func theTitleStackLeavesInputToTheRow() {
        let stack = SidebarRowTitleStack(frame: NSRect(x: 38, y: 8, width: 100, height: 32))
        #expect(stack.hitTest(NSPoint(x: 50, y: 10)) == nil)
    }

    @Test func liftRaisesTheTitleSevenPoints() {
        let owner = Owner()
        owner.window.contentView!.wantsLayer = true
        let row = FlippedRow(frame: NSRect(x: 0, y: 0, width: 200, height: 35))
        row.wantsLayer = true
        owner.window.contentView!.addSubview(row)
        let stack = SidebarRowTitleStack(frame: NSRect(x: 38, y: 8, width: 100, height: 32))
        stack.wantsLayer = true
        let title = NSTextField(labelWithString: "Title")
        title.frame = NSRect(x: 0, y: 0, width: 100, height: 18)
        title.wantsLayer = true
        stack.addSubview(title)
        row.addSubview(stack)
        owner.window.contentView!.layoutSubtreeIfNeeded()
        owner.window.displayIfNeeded()
        let root = owner.window.contentView!.layer!
        let resting = title.layer!.convert(CGPoint.zero, to: root)
        stack.layer!.sublayerTransform = CATransform3DMakeTranslation(0, -7, 0)
        let lifted = title.layer!.convert(CGPoint.zero, to: root)
        #expect(root.contentsAreFlipped() == false)
        #expect(lifted.y - resting.y == 7)
    }

    @MainActor private final class Costly {
        let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 200, height: 100),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        let button = SidebarRowActionButton("Archive this item")
        var prepares = 0
        var cheap = true
        var dispatches = 0

        init() {
            window.isReleasedWhenClosed = false
            button.frame = NSRect(x: 40, y: 10, width: 24, height: 24)
            button.prepareAction = { [unowned self] in prepares += 1; return { [unowned self] in dispatches += 1; return true } }
            button.isAvailable = { [unowned self] in cheap }
            button.isHidden = true
            window.contentView!.addSubview(button)
            button.refreshAvailability()
        }

        deinit { MainActor.assumeIsolated { window.close() } }
    }

    @Test func aHiddenButtonDoesNotRefresh() {
        #expect(Costly().prepares == 0)
    }

    @Test func showingRefreshesThroughTheCheapCheckWithoutPreparing() {
        let costly = Costly()
        costly.button.isHidden = false
        #expect(costly.button.isEnabled)
        #expect(costly.prepares == 0)
    }

    @Test func theCheapCheckDisablesWithoutPreparing() {
        let costly = Costly()
        costly.button.isHidden = false
        costly.cheap = false
        costly.button.refreshAvailability()
        #expect(!costly.button.isEnabled)
        #expect(!costly.button.isAccessibilityEnabled())
        #expect(costly.prepares == 0)
    }

    @Test func aPressPreparesAndRunsTheActionOnce() {
        let costly = Costly()
        costly.button.isHidden = false
        #expect(costly.button.accessibilityPerformPress())
        #expect(costly.prepares == 1)
        #expect(costly.dispatches == 1)
    }
}
