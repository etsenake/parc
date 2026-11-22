import AppKit
import Testing
@testable import Parc
@testable import ParcCore
@testable import ParcSidebar

@MainActor
struct SidebarSpaceHeaderTestsEditingTests {
    private typealias Support = SidebarSpaceHeaderTestsSupport
    private typealias H = Support.H
    private typealias Header = Support.Header

    @Test func editingShowsDoneAtTheTrailingEdgeWithRoomForItsTitleWithoutHover() {
        let header = Support.editing()
        let doneWidth = header.button.attributedTitle.size().width
        let frames = H.frames(width: 228, icon: false, titleHeight: header.titleHeight,
                              editButtonWidth: H.editButtonWidth(shown: true, editing: true, titleWidth: doneWidth))
        #expect(header.button.frame == frames.editButton && header.button.frame.maxX == 214 && header.button.frame.width >= ceil(doneWidth) + 4)
        #expect(header.field.frame == frames.title && header.field.frame.maxX == header.button.frame.minX - 4)
    }

    @Test func theEditingChangeFadesInInTheSameGroup() {
        let header = Support.editing()
        #expect(header.button.alphaValue == 1 && Support.isEditFade(header.opacityFade))
    }

    @Test func doneReplacesTheEllipsis() {
        let header = Support.editing()
        #expect(header.button.image?.tiffRepresentation != Support.ellipsis?.tiffRepresentation && (header.button.image?.size.width ?? 0) <= 1)
        #expect(header.button.title == "Done")
        #expect(header.button.cell?.accessibilityLabel() == "Done")
    }

    @Test func thereIsNoHoverFillWhileEditing() {
        let header = Support.editing()
        header.button.mouseEntered(with: header.crossing(.mouseEntered))
        #expect(header.fill() == [0, 0, 0, 0])
    }

    @Test func clickingDoneEndsTheRename() {
        let header = Support.editing()
        header.field.isEditable = true
        let began = header.window.makeFirstResponder(header.field)
        header.button.sendClick()
        #expect(began && header.window.firstResponder === header.window)
    }

    @Test func leavingEditingRestoresTheEllipsisAndHidesTheButton() {
        let header = Support.editing()
        header.header.isEditing = false
        #expect(header.button.frame.width == 0 && header.button.title == "")
        #expect(header.button.image?.tiffRepresentation == Support.ellipsis?.tiffRepresentation)
    }

    @Test func theEditButtonsMenuMatchesTheRightClickMenu() {
        let header = Header(icon: false)
        let clickMenu = header.header.makeMenu()
        #expect(clickMenu.items.map(\.title) == header.click.flatMap { header.header.menu(for: $0) }?.items.map(\.title))
        #expect(clickMenu.items.map(\.title) == Support.base)
    }

    @Test func choosingRenameFromTheEditButtonRunsTheAction() {
        let header = Header(icon: false)
        let clickMenu = header.header.makeMenu()
        clickMenu.performActionForItem(at: 0)
        #expect(header.calls == ["rename"])
    }

    @Test func resigningKeyClearsTheHoverAndHidesTheButton() {
        let header = Header(icon: false)
        header.showButton()
        NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: header.window)
        header.runScheduled()
        #expect(!header.header.isHovered && header.button.frame.width == 0)
    }

    @Test func hidingTheHeaderClearsTheHoverAndShownAgainItWaitsForThePointer() {
        let header = Header(icon: false)
        header.showButton()
        header.header.isHidden = true
        header.runScheduled()
        #expect(!header.header.isHovered && header.button.frame.width == 0)
        header.header.isHidden = false
        header.runScheduled()
        #expect(header.button.frame.width == 0 && header.button.alphaValue == 0)
    }

    @Test func pointsOverTheNameIconOrRestingButtonSlotHitTheHeader() {
        let header = Header(icon: false)
        #expect(header.header.hitTest(NSPoint(x: 100, y: 108)) === header.header && header.header.hitTest(NSPoint(x: 20, y: 108)) === header.header)
        #expect(header.header.hitTest(NSPoint(x: 212, y: 108)) === header.header)
    }

    @Test func theShownEditButtonTakesItsOwnClicks() {
        let header = Header(icon: false)
        header.showButton()
        #expect(header.header.hitTest(NSPoint(x: 202, y: 108)) === header.button && header.header.hitTest(NSPoint(x: 100, y: 108)) === header.header)
    }

    @Test func pointsBelowTheHeaderMissIt() {
        #expect(Header(icon: false).header.hitTest(NSPoint(x: 100, y: 130)) == nil)
    }

    @Test func theHeaderIsNoKeyboardStopTheEditButtonIncluded() {
        let header = Header(icon: false)
        #expect(!header.header.acceptsFirstResponder && !header.header.canBecomeKeyView && !header.field.acceptsFirstResponder)
        #expect(!header.button.acceptsFirstResponder && !header.button.canBecomeKeyView && !header.window.isKeyWindow)
    }
}
