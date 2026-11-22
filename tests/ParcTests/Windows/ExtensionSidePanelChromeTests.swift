import AppKit
import Testing
@testable import Parc

@MainActor private final class InertKeyWindow: NSWindow {
    var key = true
    override var isKeyWindow: Bool { key }
}

@MainActor private final class Fixture {
    let panel = ExtensionSidePanelView(frame: NSRect(x: 0, y: 0, width: 300, height: 500))
    let window: InertKeyWindow
    let nativePage = NSView()
    var closes = 0

    init() {
        window = InertKeyWindow(contentRect: panel.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = panel
        panel.layoutSubtreeIfNeeded()
        nativePage.frame = panel.content.bounds
        nativePage.autoresizingMask = [.width, .height]
        panel.content.addSubview(nativePage)
        panel.onClose = { [weak self] in self?.closes += 1; return true }
    }

    func resize(to size: NSSize) {
        panel.frame.size = size
        panel.needsLayout = true
        panel.layoutSubtreeIfNeeded()
    }
}

@MainActor struct ExtensionSidePanelChromeTests {
    @Test func theNativePageGetsOnlyTheAreaBelowTheShellHeader() {
        let fixture = Fixture()
        #expect(fixture.panel.content.frame == NSRect(x: 0, y: 32, width: 300, height: 468))
    }

    @Test func theCloseControlKeepsItsSurfaceWithoutOverlappingExtensionContent() {
        let fixture = Fixture()
        let close = fixture.panel.closeButton
        #expect(close.frame.size == NSSize(width: 32, height: 24))
        #expect(close.frame.maxY <= fixture.panel.content.frame.minY)
    }

    @Test func theCloseControlSpeaksForThePanelNotASplitPane() {
        #expect(Fixture().panel.closeButton.accessibilityLabel() == "Close Extension Side Panel")
    }

    @Test func theCloseControlStaysANativeFocusTarget() {
        #expect(Fixture().panel.closeButton.acceptsFirstResponder)
    }

    @Test func clickingTheCloseControlReachesTheShellCloseCallbackOnce() {
        let fixture = Fixture()
        fixture.panel.closeButton.sendClick()
        #expect(fixture.closes == 1)
    }

    @Test func escapeReachesTheSameCloseOwner() {
        let fixture = Fixture()
        fixture.panel.cancelOperation(nil)
        #expect(fixture.closes == 1)
    }

    @Test func aHiddenPanelCannotCloseThroughItsOldControlOrEscape() {
        let fixture = Fixture()
        fixture.panel.isHidden = true
        fixture.panel.closeButton.sendClick()
        fixture.panel.cancelOperation(nil)
        #expect(fixture.closes == 0)
    }

    @Test func aPanelInAnInactiveWindowCannotClose() {
        let fixture = Fixture()
        fixture.window.key = false
        fixture.panel.closeButton.sendClick()
        fixture.panel.cancelOperation(nil)
        #expect(fixture.closes == 0)
    }

    @Test func resizingPreservesThePageContainerAndPageIdentity() {
        let fixture = Fixture()
        let content = fixture.panel.content
        fixture.resize(to: NSSize(width: 240, height: 320))
        #expect(fixture.panel.content === content)
        #expect(fixture.nativePage.superview === content)
    }

    @Test func theNativeHostFollowsResizingWithoutCoveringShellControls() {
        let fixture = Fixture()
        fixture.resize(to: NSSize(width: 240, height: 320))
        #expect(fixture.panel.content.frame == NSRect(x: 0, y: 32, width: 240, height: 288))
        #expect(fixture.nativePage.frame == fixture.panel.content.bounds)
    }

    @Test func anUndersizedHostKeepsNonnegativeContentAndHidesControlsThatCannotFit() {
        let fixture = Fixture()
        fixture.resize(to: NSSize(width: 20, height: 10))
        #expect(fixture.panel.closeButton.isHidden)
        #expect(fixture.panel.content.frame.height == 0)
        #expect(fixture.panel.content.frame.width == 20)
    }
}
