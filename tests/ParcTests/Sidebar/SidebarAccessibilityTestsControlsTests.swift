import AppKit
import Testing
@testable import Parc

@MainActor
struct SidebarAccessibilityTestsControlsTests {
    private func mask(_ view: NSView) -> NSBitmapImageRep {
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 28, pixelsHigh: 28, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                      isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSColor.black.setFill()
        view.drawFocusRingMask()
        NSGraphicsContext.restoreGraphicsState()
        return bitmap
    }

    @Test func theToggleLabelsFollowTheLockedFloatingPair() {
        #expect(SidebarAccessibility.hideSidebar == "Hide sidebar")
        #expect(SidebarAccessibility.lockSidebar == "Lock sidebar")
    }

    @Test func theNavigationLabels() {
        #expect(SidebarAccessibility.goBack == "Go back")
        #expect(SidebarAccessibility.goForward == "Go forward")
        #expect(SidebarAccessibility.reload == "Reload this page")
    }

    private func configuredSpace(_ name: String = "Home") -> ActionButton {
        let space = ActionButton(name, symbol: "house")
        space.title = ""
        SidebarAccessibility.configureSpace(space, name: name)
        return space
    }

    @Test func anUnconfiguredButtonHasNoneOfTheSpaceValues() {
        let space = ActionButton("Home", symbol: "house")
        space.title = ""
        #expect(space.accessibilityRoleDescription() != "Space")
        #expect(space.accessibilityTitle() != "Home")
        #expect(space.accessibilityIdentifier() != "SidebarDockItem-Home")
    }

    @Test func aSpaceButtonHasItsRoleDescriptionTitleAndIdentifier() {
        let space = configuredSpace()
        #expect(space.accessibilityRoleDescription() == "Space")
        #expect(space.accessibilityTitle() == "Home")
        #expect(space.accessibilityIdentifier() == "SidebarDockItem-Home")
        #expect(space.accessibilityLabel() == "Home")
    }

    @Test func aSpaceButtonTakesNoKeyboardFocusAndDrawsNoRing() {
        let space = configuredSpace()
        #expect(space.refusesFirstResponder)
        #expect(!space.acceptsFirstResponder)
        #expect(space.focusRingType == .none)
    }

    @Test func appKitExposesTheButtonsCellCarryingTheSpaceValues() {
        let space = configuredSpace()
        let exposed = NSAccessibility.unignoredDescendant(of: space) as? NSCell
        #expect(exposed != nil)
        #expect(exposed === space.cell)
        #expect(exposed?.accessibilityRoleDescription() == "Space")
        #expect(exposed?.accessibilityTitle() == "Home")
        #expect(exposed?.accessibilityIdentifier() == "SidebarDockItem-Home")
    }

    @Test func theExposedToggleCellReadsTheCurrentLabel() {
        let labelled = ActionButton("Hide sidebar", symbol: "sidebar.left")
        SidebarAccessibility.label(labelled, SidebarAccessibility.lockSidebar)
        let cell = NSAccessibility.unignoredDescendant(of: labelled) as? NSCell
        #expect(cell?.accessibilityLabel() == "Lock sidebar")
        #expect(labelled.image?.accessibilityDescription == "Lock sidebar")
    }

    @Test func labellingATitledButtonLeavesOtherButtonsLabelsAlone() {
        func titled(_ title: String) -> NSButton {
            let button = NSButton(frame: .zero)
            button.setButtonType(.momentaryChange); button.isBordered = false
            button.image = NSImage(systemSymbolName: "ellipsis", accessibilityDescription: "")
            button.image = nil; button.title = title
            return button
        }
        let labelled = titled("Stop"), other = titled("Done")
        SidebarAccessibility.label(labelled, SidebarAccessibility.reload)
        #expect(other.cell?.accessibilityLabel() == "Done")
    }

    @Test func labellingAButtonLeavesItsSharedArtworkAlone() throws {
        let shared = try #require(NSImage(systemSymbolName: "sidebar.left", accessibilityDescription: "Hide sidebar"))
        let button = ActionButton("Hide sidebar", symbol: "sidebar.left")
        button.image = shared
        SidebarAccessibility.label(button, SidebarAccessibility.lockSidebar)
        #expect(shared.accessibilityDescription == "Hide sidebar")
        #expect(button.image?.accessibilityDescription == "Lock sidebar")
    }

    @Test func anEmptyNameFallsBackToUntitledSpace() {
        let untitled = ActionButton("", symbol: "house")
        SidebarAccessibility.configureSpace(untitled, name: "")
        #expect(untitled.accessibilityTitle() == "Untitled Space")
        #expect(untitled.accessibilityIdentifier() == "SidebarDockItem-Untitled Space")
    }

    @Test func existingActionButtonUsersKeepNoRing() {
        #expect(ActionButton("Downloads", symbol: "arrow.down.circle").focusRingType == .none)
    }

    private func ringed() -> ActionButton {
        let button = ActionButton("Hide sidebar", symbol: "sidebar.left")
        button.frame = NSRect(x: 0, y: 0, width: 28, height: 28)
        button.focusRingCornerRadius = 5
        return button
    }

    @Test func aRadiusEnablesTheKeyboardRingOverTheButtonBounds() {
        let button = ringed()
        #expect(button.focusRingType == .exterior)
        #expect(button.focusRingMaskBounds == button.bounds)
    }

    @Test func theMaskCornerIsRoundedAndTheMaskFillsTheButtonToItsEdge() {
        let bitmap = mask(ringed())
        #expect((bitmap.colorAt(x: 0, y: 0)?.alphaComponent ?? 1) < 0.1)
        #expect((bitmap.colorAt(x: 14, y: 14)?.alphaComponent ?? 0) > 0.9)
        #expect((bitmap.colorAt(x: 14, y: 0)?.alphaComponent ?? 0) > 0.9)
    }

    @Test func clearingTheRadiusRemovesTheRing() {
        let button = ringed()
        button.focusRingCornerRadius = nil
        #expect(button.focusRingType == .none)
    }

    @Test func navigationButtonsKeepTheExteriorRingByDefault() {
        let n = SidebarAccessibilityTestsSupport.navigation()
        #expect(n.focusRingType == .exterior)
        #expect(n.focusRingCornerRadius == nil)
    }

    @Test func theSidebarsNavigationRingCoversTheBoundsWithRoundedCorners() {
        let n = SidebarAccessibilityTestsSupport.navigation()
        n.focusRingCornerRadius = 5
        let bitmap = mask(n)
        #expect(n.focusRingType == .exterior)
        #expect(n.focusRingMaskBounds == n.bounds)
        #expect((bitmap.colorAt(x: 0, y: 0)?.alphaComponent ?? 1) < 0.1)
        #expect((bitmap.colorAt(x: 14, y: 14)?.alphaComponent ?? 0) > 0.9)
        #expect((bitmap.colorAt(x: 14, y: 0)?.alphaComponent ?? 0) > 0.9)
    }
}
