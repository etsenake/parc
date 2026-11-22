import AppKit
import Testing
@testable import Parc
@testable import ParcCore

@MainActor
private final class FakeSelectionToolbar: EaselSelectionToolbarPresenting {
    var refreshes = 0
    var focusRequests = 0
    var element: NSView?
    func refresh(for canvas: EaselCanvasView) { refreshes += 1 }
    func detach() {}
    func settle() {}
    func owns(_ responder: NSResponder?) -> Bool { responder != nil && responder === element }
    func focusFromKeyboard() -> Bool { focusRequests += 1; return true }
    var accessibilityToolbar: Any? { element }
}

struct EaselSelectionToolbarCanvasTests {
    @MainActor private func controls(_ canvas: EaselCanvasView) -> [EaselToolbarControl] {
        canvas.selectionToolbarModel?.groups.flatMap { $0.map(\.control) } ?? []
    }

    @MainActor private func style(_ session: EaselSession, _ id: UUID) -> EaselTextStyle? {
        session.document.items.first { $0.id == id }?.resolvedTextStyle
    }

    @MainActor
    private struct Board {
        let toolbar = FakeSelectionToolbar()
        let text = EaselItem(kind: .text, frame: .init(x: 40, y: 40, width: 280, height: 28), zIndex: 1, text: "Hello")
        let shape = EaselItem(kind: .rectangle, frame: .init(x: 400, y: 40, width: 120, height: 80), zIndex: 2)
        let session: EaselSession
        let canvas: EaselCanvasView

        init() throws {
            let date = Date(timeIntervalSince1970: 0)
            let document = EaselDocument(id: UUID(), title: "Toolbar", createdAt: date, modifiedAt: date, items: [text, shape])
            session = try EaselSession(inMemory: document, assets: [:])
            canvas = makeTestEaselCanvas(session: session)
            canvas.selectionToolbar = toolbar
        }
    }

    @MainActor @Test
    func anEmptySelectionHasNoToolbar() throws {
        let board = try Board()
        let canvas = board.canvas
        #expect(canvas.selectionToolbarModel == nil, "Nothing selected means no toolbar")
    }

    @MainActor @Test
    func aDetachedCanvasDoesNotPresentItsToolbar() throws {
        let board = try Board()
        let canvas = board.canvas
        let text = board.text
        canvas.selection = [text.id]
        let fake = board.toolbar
        #expect(fake.refreshes == 0, "A canvas outside a window never asks its toolbar to show")
        #expect(canvas.selectionToolbarContent == nil, "Only a canvas in a window presents the toolbar")
    }

    @MainActor @Test
    func selectedTextGetsFormattingControls() throws {
        let board = try Board()
        let canvas = board.canvas
        let text = board.text
        canvas.selection = [text.id]
        #expect(controls(canvas) == [.typeface, .textSize, .smaller, .larger, .color, .textFill, .alignment, .link, .more],
               "Text gets typeface, size, quick steps, colour, fill, alignment, a link and the ••• menu")
        let model = try #require(canvas.selectionToolbarModel)
        #expect(model.anchor == NSRect(x: 40, y: 40, width: 280, height: 28), "The toolbar anchors on the selected frames")
        let buttons = model.groups.joined()
        let size = buttons.first { $0.control == .textSize }
        #expect(size?.face == .text("Body") && size?.opens == .menu, "The size button names the current size and opens a menu")
        let smaller = buttons.first { $0.control == .smaller }
        #expect(smaller?.isEnabled == false && smaller?.commandID == TextFormatCommand.smaller.bindingID,
               "Body text can't shrink, and the step shows its live shortcut")
        #expect(buttons.first { $0.control == .more }?.opens == .menu, "••• opens a menu")
    }

    @MainActor @Test
    func theLargerControlIsUndoableAndBodyCannotShrink() throws {
        let board = try Board()
        let canvas = board.canvas
        let text = board.text
        canvas.selection = [text.id]
        let session = board.session
        #expect(canvas.performSelectionToolbar(.larger), "The bigger step runs")
        #expect(style(session, text.id)?.size == .h2, "Bigger steps the text up one size")
        try session.undo()
        #expect(style(session, text.id)?.size == .body, "One Undo takes the step back")
        #expect(!canvas.performSelectionToolbar(.smaller), "The smaller step refuses at body size")
    }

    @MainActor @Test
    func theTextFillControlTogglesTheSavedFill() throws {
        let board = try Board()
        let canvas = board.canvas
        let text = board.text
        canvas.selection = [text.id]
        let session = board.session
        #expect(canvas.performSelectionToolbar(.textFill), "Text fill toggles")
        #expect(style(session, text.id)?.resolvedFill == .contentHugging, "Fill turns on")
        canvas.performSelectionToolbar(.textFill)
        #expect(style(session, text.id)?.resolvedFill == EaselTextStyle.Fill.none, "Fill turns back off")
    }

    @MainActor @Test
    func theTypefaceMenuAppliesAndChecksAKnownFamily() throws {
        let board = try Board()
        let canvas = board.canvas
        let text = board.text
        canvas.selection = [text.id]
        let session = board.session
        #expect(canvas.performSelectionToolbarMenu(.typeface, entry: "mono"), "Picking a typeface applies it")
        #expect(style(session, text.id)?.family == .mono, "The typeface menu sets the family")
        #expect(!canvas.performSelectionToolbarMenu(.typeface, entry: "comic"), "Unknown menu entries are refused")
        let typefaces = canvas.selectionToolbarMenu(for: .typeface)
        #expect(typefaces.map(\.title) == ["Mono", "Fancy", "Hip", "Clean"] && typefaces.first?.isChecked == true,
               "The typeface menu checks the current family")
    }

    @MainActor @Test
    func theSizeMenuSetsTheChosenSize() throws {
        let board = try Board()
        let canvas = board.canvas
        let text = board.text
        canvas.selection = [text.id]
        let session = board.session
        #expect(canvas.performSelectionToolbarMenu(.textSize, entry: "h1"), "Picking a size applies it")
        #expect(style(session, text.id)?.size == .h1, "The size menu sets the size")
    }

    @MainActor @Test
    func rangeEmphasisWaitsForAnEditor() throws {
        let board = try Board()
        let canvas = board.canvas
        let text = board.text
        canvas.selection = [text.id]
        #expect(!canvas.performSelectionToolbar(.bold), "Range emphasis waits for text editing")
    }

    @MainActor @Test
    func theAlignmentMenuReflectsTheSavedAlignment() throws {
        let board = try Board()
        let canvas = board.canvas
        let text = board.text
        canvas.selection = [text.id]
        let session = board.session
        #expect(canvas.performSelectionToolbarMenu(.alignment, entry: "center"), "Alignment applies from its menu")
        #expect(style(session, text.id)?.alignment == .center, "Centre alignment sticks to the text")
        #expect(canvas.selectionToolbarMenu(for: .alignment).first { $0.id == "center" }?.isChecked == true, "The menu checks the current alignment")
    }

    @MainActor @Test
    func theColorPickerUsesTheSavedInk() throws {
        let board = try Board()
        let canvas = board.canvas
        let text = board.text
        canvas.selection = [text.id]
        let session = board.session
        let colorButton = canvas.selectionToolbarModel?.groups.joined().first { $0.control == .color }
        #expect(colorButton?.opens == .stylePicker && colorButton?.isEnabled == true, "Text colour opens the colour and style picker")
        let red = try #require(EaselPalette.hex(.note(.red), role: .ink))
        #expect(canvas.applyColor(.palette(.note(.red))), "Picking a text colour applies it")
        #expect(session.document.items.first { $0.id == text.id }.flatMap { EaselPalette.normalized($0.color) } == EaselPalette.normalized(red),
               "The text takes the chosen ink")
        #expect(canvas.styleSummary.color.map { EaselPalette.normalized($0.hex(role: .ink)) } == EaselPalette.normalized(red),
               "The picker shows the current ink")
    }

    @MainActor @Test
    func mixedSelectionOffersBoardControls() throws {
        let board = try Board()
        let canvas = board.canvas
        let text = board.text
        canvas.selection = [text.id]
        let shape = board.shape
        canvas.selection = [text.id, shape.id]
        let pair = controls(canvas)
        #expect(pair.last == .more && !pair.contains(.textFill) && !pair.contains(.smaller), "Mixed selections drop text-only controls")
        #expect(!pair.contains(.link), "Links belong to one object at a time")
        #expect([.arrange, .tidyUp, .group, .createSection, .lock].allSatisfy(pair.contains), "Two objects get arrange, group, section and lock tools")
    }

    @MainActor @Test
    func twoObjectsCanAlignButCannotDistribute() throws {
        let board = try Board()
        let canvas = board.canvas
        let text = board.text
        canvas.selection = [text.id]
        let shape = board.shape
        canvas.selection = [text.id, shape.id]
        let arrangeMenu = canvas.selectionToolbarMenu(for: .arrange)
        #expect(arrangeMenu.count == 8 && arrangeMenu.prefix(6).allSatisfy(\.isEnabled) && arrangeMenu.suffix(2).allSatisfy { !$0.isEnabled },
               "Two objects can align but need a third to distribute")
    }

    @MainActor @Test
    func alignmentFromTheToolbarLinesUpTheObjects() throws {
        let board = try Board()
        let canvas = board.canvas
        let text = board.text
        canvas.selection = [text.id]
        let shape = board.shape
        canvas.selection = [text.id, shape.id]
        let session = board.session
        try session.perform("Stagger") { document in
            guard let index = document.items.firstIndex(where: { $0.id == shape.id }) else { return }
            document.items[index].frame.y = 90
        }
        #expect(canvas.performSelectionToolbarMenu(.arrange, entry: "align.top"), "Align top runs from the menu")
        #expect(Set(session.document.items.filter { [text.id, shape.id].contains($0.id) }.map(\.frame.y)).count == 1, "Align top lines the tops up")
        #expect(!canvas.performSelectionToolbarMenu(.arrange, entry: "align.sideways"), "Unknown alignments are refused")
    }

    @MainActor @Test
    func groupingSwitchesTheToolbarToUngroup() throws {
        let board = try Board()
        let canvas = board.canvas
        let text = board.text
        canvas.selection = [text.id]
        let shape = board.shape
        canvas.selection = [text.id, shape.id]
        let session = board.session
        #expect(canvas.performSelectionToolbar(.group), "Group runs")
        let grouped = session.document.items.filter { [text.id, shape.id].contains($0.id) }
        #expect(grouped.allSatisfy { $0.groupID != nil } && Set(grouped.compactMap(\.groupID)).count == 1, "Group joins the pair")
        #expect(canvas.selectionToolbarModel?.groups.joined().first { $0.control == .group }?.name == "Ungroup", "A group offers Ungroup next")
        #expect(canvas.performSelectionToolbar(.group), "Ungroup runs")
        #expect(session.document.items.filter { [text.id, shape.id].contains($0.id) }.allSatisfy { $0.groupID == nil }, "Ungroup splits the pair")
    }

    @MainActor @Test
    func lockingOnlyLeavesUnlockAndMore() throws {
        let board = try Board()
        let canvas = board.canvas
        let text = board.text
        canvas.selection = [text.id]
        let shape = board.shape
        canvas.selection = [text.id, shape.id]
        let session = board.session
        #expect(canvas.performSelectionToolbar(.lock), "Lock runs")
        #expect(canvas.selectionToolbarModel?.groups.map { $0.map(\.control) } == [[.unlock], [.more]], "A locked selection shows only Unlock and •••")
        #expect(canvas.selectionToolbarMenu(for: .more).first { $0.id == "delete" }?.isEnabled == false, "Locked objects can't be deleted from •••")
        #expect(canvas.performSelectionToolbarMenu(.unlock, entry: "unlock"), "Unlock confirms from its menu")
        #expect(session.document.items.filter { [text.id, shape.id].contains($0.id) }.allSatisfy { !$0.isLocked }, "Unlock frees the pair")
    }

    @MainActor @Test
    func duplicateFromMoreCopiesTheWholeSelection() throws {
        let board = try Board()
        let canvas = board.canvas
        let text = board.text
        canvas.selection = [text.id]
        let shape = board.shape
        canvas.selection = [text.id, shape.id]
        let session = board.session
        let count = session.document.items.count
        canvas.selection = [text.id, shape.id]
        #expect(canvas.performSelectionToolbarMenu(.more, entry: "duplicate"), "••• Duplicate runs")
        #expect(session.document.items.count == count + 2, "Duplicate copies the whole selection in one step")
    }

    @MainActor @Test
    func singleObjectMoreMenuOffersLayeringAndLocking() throws {
        let board = try Board()
        let canvas = board.canvas
        let shape = board.shape
        canvas.selection = [shape.id]
        let layers = canvas.selectionToolbarMenu(for: .more).filter { $0.id.hasPrefix("layer.") }
        #expect(layers.map(\.title) == ["Bring to Front", "Bring Forward", "Send Backward", "Send to Back"], "••• carries all four layer moves")
        #expect(canvas.selectionToolbarMenu(for: .more).contains { $0.id == "lock" }, "A single object locks from •••")
    }

    @MainActor @Test
    func stickiesCanToggleTheirShape() throws {
        let board = try Board()
        let canvas = board.canvas
        let session = board.session
        let sticky = EaselItem(kind: .sticky, frame: .init(x: 40, y: 400, width: 220, height: 220), zIndex: 10)
        try session.perform("Add sticky") { $0.items.append(sticky) }
        canvas.selection = [sticky.id]
        #expect(controls(canvas).contains(.stickyShape), "Stickies offer square or wide")
        #expect(canvas.performSelectionToolbar(.stickyShape) && canvas.isStickyWide, "The toggle makes the sticky wide")
        #expect(canvas.selectionToolbarModel?.groups.joined().first { $0.control == .stickyShape }?.isChecked == true, "The toggle shows it's wide")
    }

    @MainActor @Test
    func sectionsCanToggleTheirContentsFromMore() throws {
        let board = try Board()
        let canvas = board.canvas
        let session = board.session
        let section = EaselItem(kind: .section, frame: .init(x: 600, y: 400, width: 400, height: 400), zIndex: 0, text: "Ideas")
        try session.perform("Add section") { $0.items.append(section) }
        canvas.selection = [section.id]
        #expect(controls(canvas).first == .sectionTitle, "Sections lead with Rename")
        let sectionMenu = canvas.selectionToolbarMenu(for: .more).map(\.id)
        #expect(["section.lockAll", "section.lockBackground", "section.hide", "section.deleteKeepingContents"].allSatisfy(sectionMenu.contains),
               "A section's ••• menu holds Lock All, Lock Background Only, Hide Contents and Delete Section Only")
        #expect(canvas.performSelectionToolbarMenu(.more, entry: "section.hide"), "Hide contents runs")
        #expect(session.document.items.first { $0.id == section.id }?.contentsHidden == true, "Hide contents hides them")
        #expect(canvas.selectionToolbarMenu(for: .more).first { $0.id == "section.hide" }?.title == "Show Contents", "The row flips to Show Contents")
    }

    @MainActor @Test
    func theToolbarHidesDuringSelectionGestures() throws {
        let board = try Board()
        let canvas = board.canvas
        let shape = board.shape
        canvas.selection = [shape.id]
        canvas.selectionBeforeGesture = [shape.id]
        canvas.start = NSPoint(x: 410, y: 50)
        #expect(!canvas.selectionToolbarSuppressed, "A plain press on the current selection keeps the toolbar")
        canvas.marqueeRect = NSRect(x: 0, y: 0, width: 10, height: 10)
        #expect(canvas.selectionToolbarSuppressed, "A marquee hides the toolbar")
        canvas.marqueeRect = nil
        canvas.dragDistance = 4
        #expect(canvas.selectionToolbarSuppressed, "Dragging hides the toolbar")
        canvas.dragDistance = 0
        canvas.selectionBeforeGesture = []
        #expect(canvas.selectionToolbarSuppressed, "The press that makes a new selection waits for the mouse to come up")
        canvas.start = nil
        #expect(!canvas.selectionToolbarSuppressed, "Letting go brings the toolbar back")
    }

    @Test
    func theToolbarChordRequiresShift() {
        #expect(EaselChords.command(characters: "?", keyCode: 44, modifiers: [.command, .shift]) == .focusSelectionToolbar
               && EaselChords.command(characters: "/", keyCode: 44, modifiers: [.command, .shift]) == .focusSelectionToolbar,
               "⇧⌘/ is the toolbar's chord, like the Notes format bar")
        #expect(EaselChords.command(characters: "/", keyCode: 44, modifiers: [.command]) == nil, "⌘/ alone is left for Parc")
    }

    @MainActor @Test
    func theToolbarChordHandsOffKeyboardFocus() throws {
        let board = try Board()
        let canvas = board.canvas
        let text = board.text
        canvas.selection = [text.id]
        let shape = board.shape
        canvas.selection = [text.id, shape.id]
        let fake = board.toolbar
        #expect(canvas.performChord(.focusSelectionToolbar) && fake.focusRequests == 1,
               "The chord hands keyboard focus to the toolbar")
    }

    @MainActor @Test
    func voiceOverFindsOnlyTheVisibleToolbar() throws {
        let board = try Board()
        let canvas = board.canvas
        let fake = board.toolbar
        let element = NSView()
        fake.element = element
        #expect(canvas.accessibilityChildren()?.contains { ($0 as AnyObject) === element } == true,
               "VoiceOver finds the toolbar among the canvas's children")
        fake.element = nil
        #expect(canvas.accessibilityChildren()?.contains { ($0 as AnyObject) === element } != true,
               "A hidden toolbar leaves the canvas's children")
    }

}
