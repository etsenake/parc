import AppKit
import Testing
@testable import ParcSidebar

@MainActor
struct SpaceHeaderMenuTests {
    @MainActor private final class Header {
        let view = SidebarSpaceHeaderView(frame: NSRect(x: 0, y: 0, width: 228, height: 36))
        let window: NSWindow
        var results: [String?] = []

        init() {
            window = NSWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: true)
            window.isReleasedWhenClosed = false
            window.contentView = view
            view.canShowHeaderButtonsIfPossible = true
        }

        deinit { MainActor.assumeIsolated { window.contentView = nil } }

        func beginEditing(_ title: String = "Work") -> Bool {
            view.beginNameEditing(title: title) { [weak self] in self?.results.append($0) }
        }
    }

    @Test func theNativeNameEditorBegins() {
        let header = Header()
        #expect(header.beginEditing())
    }

    @Test func editingUpdatesTheRealHeader() {
        let header = Header()
        _ = header.beginEditing()
        #expect(header.view.isEditing)
        #expect(header.view.nameField.isEditable)
        #expect(header.view.editButton.title == "Done")
    }

    @Test func doneKeepsMarkedTextInTheEditor() throws {
        let header = Header()
        _ = header.beginEditing()
        let editor = try #require(header.view.nameField.currentEditor() as? NSTextView)
        editor.setMarkedText("仮", selectedRange: NSRange(location: 1, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        header.view.editButton.sendClick()
        #expect(header.view.isEditing)
        #expect(header.results.isEmpty)
        #expect(editor.hasMarkedText())
    }

    @Test func returnCommitsTheNameOnce() {
        let header = Header()
        _ = header.beginEditing()
        header.view.nameField.stringValue = "Updated"
        _ = header.view.control(header.view.nameField, textView: NSTextView(), doCommandBy: #selector(NSResponder.insertNewline(_:)))
        #expect(header.results == ["Updated"])
        #expect(!header.view.isEditing)
    }

    @Test func escapeCancelsTheNativeDraft() {
        let header = Header()
        _ = header.beginEditing("Updated")
        header.view.nameField.stringValue = "Cancelled"
        _ = header.view.control(header.view.nameField, textView: NSTextView(), doCommandBy: #selector(NSResponder.cancelOperation(_:)))
        #expect(header.results.count == 1)
        #expect(header.results[0] == nil)
        #expect(!header.view.nameField.isEditable)
    }

    @MainActor private final class TitleRow {
        let host = NSView(frame: NSRect(x: 0, y: 0, width: 228, height: 36))
        let window: NSWindow
        let row: SidebarSpaceHeaderView
        let cover: NSView

        init() {
            window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: true)
            window.isReleasedWhenClosed = false
            window.contentView = host
            row = SidebarSpaceHeaderView(frame: host.bounds)
            host.addSubview(row)
            cover = NSView(frame: host.bounds)
            host.addSubview(cover)
        }

        deinit { MainActor.assumeIsolated { window.contentView = nil } }

        let centre = NSPoint(x: 114, y: 18)

        var entered: NSEvent {
            NSEvent.enterExitEvent(with: .mouseEntered, location: centre, modifierFlags: [], timestamp: 0, windowNumber: 0,
                                   context: nil, eventNumber: 0, trackingNumber: 0, userData: nil)!
        }

        var moved: NSEvent {
            NSEvent.mouseEvent(with: .mouseMoved, location: centre, modifierFlags: [], timestamp: 0, windowNumber: 0,
                               context: nil, eventNumber: 0, clickCount: 0, pressure: 0)!
        }
    }

    @Test func aCommandSurfaceOverTheTitleRowKeepsItsHoverOff() {
        let titleRow = TitleRow()
        titleRow.row.mouseEntered(with: titleRow.entered)
        #expect(!titleRow.row.isHovered)
    }

    @Test func movingOutFromUnderTheCoverLightsTheTitleRowAgain() {
        let titleRow = TitleRow()
        titleRow.row.mouseEntered(with: titleRow.entered)
        titleRow.cover.removeFromSuperview()
        titleRow.row.mouseMoved(with: titleRow.moved)
        #expect(titleRow.row.isHovered)
    }

    @Test func theHeaderAddsNoKeyboardStopOfItsOwn() {
        let header = Header()
        let list = NSView()
        let chain = SidebarAccessibility.keyViewChain(leading: [], favorites: NSView(), list: list, regions: [], trailing: [],
                                                      space: header.view, beforeList: [header.view])
        #expect(!chain.contains { $0 === header.view.editButton })
        #expect(chain.first === list)
    }

    @MainActor private final class Choices {
        var selected = 0
        lazy var menu = SidebarSpaceMenu(includesManagement: true, changeIcon: {},
            shareData: [("Work", true, {}), ("Play", false, { [weak self] in self?.selected += 1 }), ("Retiring", false, nil)],
            keepSeparate: (selected: false, action: { [weak self] in self?.selected += 100 }),
            rename: {}, editTheme: {}, newFolder: {}, toggleTitle: nil, toggleHeader: nil)
        var native: NSMenu { menu.makeMenu() }
        var sharing: NSMenu { native.item(withTitle: "Share data with")!.submenu! }
    }

    @Test func theMenuKeepsItsOrderAndTitles() {
        let choices = Choices()
        #expect(choices.native.items.map(\.title)
                == ["Change Space Icon…", "Rename Space…", "Edit Theme Color…", "Share data with", "New Folder", "Delete Space", "Manage Spaces…"])
    }

    @Test func sharingListsEachOtherSpaceASeparatorAndKeepSeparate() {
        let choices = Choices()
        #expect(choices.sharing.items.map(\.title) == ["Work", "Play", "Retiring", "", "Keep separate"])
    }

    @Test func checkmarksShowWhoSharesAndRetirementAvailability() {
        let choices = Choices()
        let items = choices.sharing.items
        #expect(items[0].state == .on)
        #expect(items[1].state == .off)
        #expect(items[4].state == .off)
        #expect(!items[2].isEnabled)
    }

    @Test func theNativeSubmenuReachesTheActualAction() {
        let choices = Choices()
        choices.sharing.performActionForItem(at: 1)
        #expect(choices.selected == 1)
    }

    @Test func keepSeparateReachesItsAction() {
        let choices = Choices()
        choices.sharing.performActionForItem(at: 4)
        #expect(choices.selected == 100)
    }

    @Test func aSpaceChoiceIsAKeyboardIndependentAccessibilityAction() {
        let choices = Choices()
        #expect(choices.menu.accessibilityActions.contains { $0.name == "Share data with Play" })
    }

    @Test func keepSeparateIsAnAccessibilityAction() {
        let choices = Choices()
        #expect(choices.menu.accessibilityActions.contains { $0.name == "Keep separate" })
    }

    @Test func anUnavailableSpaceIsOmittedFromAccessibilityActions() {
        let choices = Choices()
        #expect(!choices.menu.accessibilityActions.contains { $0.name == "Share data with Retiring" })
    }

    @Test func theMenuNeverSaysProfile() {
        let choices = Choices()
        #expect(!choices.native.items.contains { $0.title.contains("Profile") })
        #expect(!choices.sharing.items.contains { $0.title.contains("Profile") })
    }

    @Test func aLoneSpaceOnlyOffersACheckedKeepSeparate() {
        let alone = SidebarSpaceMenu(includesManagement: true, changeIcon: {}, keepSeparate: (selected: true, action: {}),
                                     rename: {}, editTheme: {}, newFolder: {}, toggleTitle: nil, toggleHeader: nil).makeMenu()
        let choices = alone.item(withTitle: "Share data with")!.submenu!
        #expect(choices.items.map(\.title) == ["Keep separate"])
        #expect(choices.items[0].state == .on)
    }

    @Test func anUnavailableManagementOwnerCannotFallBackToStaleActions() {
        let header = Header()
        header.view.onRenameSpace = {}
        header.view.managementMenu = { nil }
        #expect(header.view.makeMenu().items.isEmpty)
        #expect(header.view.nameField.accessibilityCustomActions()?.isEmpty == true)
    }
}
