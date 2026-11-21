import AppKit

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

@main
struct EaselSelectionToolbarCanvasTests {
    @MainActor static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() { failTest(message) }
    }

    @MainActor static func main() { exitOnFailure(runChecks) }

    @MainActor static func controls(_ canvas: EaselCanvasView) -> [EaselToolbarControl] {
        canvas.selectionToolbarModel?.groups.flatMap { $0.map(\.control) } ?? []
    }

    @MainActor static func style(_ session: EaselSession, _ id: UUID) -> EaselTextStyle? {
        session.document.items.first { $0.id == id }?.resolvedTextStyle
    }

    @MainActor static func runChecks() throws {
        let fake = FakeSelectionToolbar()
        EaselCanvasView.selectionToolbarFactory = { fake }
        let date = Date()
        let text = EaselItem(kind: .text, frame: .init(x: 40, y: 40, width: 280, height: 28), zIndex: 1, text: "Hello")
        let shape = EaselItem(kind: .rectangle, frame: .init(x: 400, y: 40, width: 120, height: 80), zIndex: 2)
        let document = EaselDocument(id: UUID(), title: "Toolbar", createdAt: date, modifiedAt: date, items: [text, shape])
        let session = try EaselSession(inMemory: document, assets: [:])
        let canvas = EaselCanvasView(session: session)
        expect(canvas.selectionToolbar === fake, "The canvas builds its toolbar through the app's factory")
        expect(canvas.selectionToolbarModel == nil, "Nothing selected means no toolbar")

        canvas.selection = [text.id]
        expect(fake.refreshes == 0, "A canvas outside a window never asks its toolbar to show")
        expect(canvas.selectionToolbarContent == nil, "Only a canvas in a window presents the toolbar")
        expect(controls(canvas) == [.typeface, .textSize, .smaller, .larger, .textFill, .more],
               "Text gets typeface, size, quick steps, fill and the ••• menu")
        guard let model = canvas.selectionToolbarModel else { failTest("Text selections build a toolbar") }
        expect(model.anchor == NSRect(x: 40, y: 40, width: 280, height: 28), "The toolbar anchors on the selected frames")
        let buttons = model.groups.joined()
        let size = buttons.first { $0.control == .textSize }
        expect(size?.face == .text("Body") && size?.opens == .menu, "The size button names the current size and opens a menu")
        let smaller = buttons.first { $0.control == .smaller }
        expect(smaller?.isEnabled == false && smaller?.commandID == TextFormatCommand.smaller.bindingID,
               "Body text can't shrink, and the step shows its live shortcut")
        expect(buttons.first { $0.control == .more }?.opens == .menu, "••• opens a menu")

        expect(canvas.performSelectionToolbar(.larger), "The bigger step runs")
        expect(style(session, text.id)?.size == .h2, "Bigger steps the text up one size")
        try session.undo()
        expect(style(session, text.id)?.size == .body, "One Undo takes the step back")
        expect(!canvas.performSelectionToolbar(.smaller), "The smaller step refuses at body size")
        expect(canvas.performSelectionToolbar(.textFill), "Text fill toggles")
        expect(style(session, text.id)?.resolvedFill == .contentHugging, "Fill turns on")
        canvas.performSelectionToolbar(.textFill)
        expect(style(session, text.id)?.resolvedFill == EaselTextStyle.Fill.none, "Fill turns back off")
        expect(canvas.performSelectionToolbarMenu(.typeface, entry: "mono"), "Picking a typeface applies it")
        expect(style(session, text.id)?.family == .mono, "The typeface menu sets the family")
        expect(!canvas.performSelectionToolbarMenu(.typeface, entry: "comic"), "Unknown menu entries are refused")
        let typefaces = canvas.selectionToolbarMenu(for: .typeface)
        expect(typefaces.map(\.title) == ["Mono", "Fancy", "Hip", "Clean"] && typefaces.first?.isChecked == true,
               "The typeface menu checks the current family")
        expect(canvas.performSelectionToolbarMenu(.textSize, entry: "h1"), "Picking a size applies it")
        expect(style(session, text.id)?.size == .h1, "The size menu sets the size")
        expect(!canvas.performSelectionToolbar(.bold), "Range emphasis waits for text editing")

        canvas.selection = [text.id, shape.id]
        expect(controls(canvas).last == .more && !controls(canvas).contains(.typeface), "Mixed selections drop text-only controls")
        let count = session.document.items.count
        expect(canvas.performSelectionToolbarMenu(.more, entry: "duplicate"), "••• Duplicate runs")
        expect(session.document.items.count == count + 2, "Duplicate copies the whole selection in one step")

        canvas.selection = [shape.id]
        canvas.selectionBeforeGesture = [shape.id]
        canvas.start = NSPoint(x: 410, y: 50)
        expect(!canvas.selectionToolbarSuppressed, "A plain press on the current selection keeps the toolbar")
        canvas.marqueeRect = NSRect(x: 0, y: 0, width: 10, height: 10)
        expect(canvas.selectionToolbarSuppressed, "A marquee hides the toolbar")
        canvas.marqueeRect = nil
        canvas.dragDistance = 4
        expect(canvas.selectionToolbarSuppressed, "Dragging hides the toolbar")
        canvas.dragDistance = 0
        canvas.selectionBeforeGesture = []
        expect(canvas.selectionToolbarSuppressed, "The press that makes a new selection waits for the mouse to come up")
        canvas.start = nil
        expect(!canvas.selectionToolbarSuppressed, "Letting go brings the toolbar back")

        expect(EaselChords.command(characters: "?", keyCode: 44, modifiers: [.command, .shift]) == .focusSelectionToolbar
               && EaselChords.command(characters: "/", keyCode: 44, modifiers: [.command, .shift]) == .focusSelectionToolbar,
               "⇧⌘/ is the toolbar's chord, like the Notes format bar")
        expect(EaselChords.command(characters: "/", keyCode: 44, modifiers: [.command]) == nil, "⌘/ alone is left for Parc")
        expect(canvas.performChord(.focusSelectionToolbar, editing: false) && fake.focusRequests == 1,
               "The chord hands keyboard focus to the toolbar")
        expect(canvas.performChord(.focusSelectionToolbar, editing: true) && fake.focusRequests == 2,
               "It works mid-sentence too, so text formatting is reachable from the keyboard")

        let element = NSView()
        fake.element = element
        expect(canvas.accessibilityChildren()?.contains { ($0 as AnyObject) === element } == true,
               "VoiceOver finds the toolbar among the canvas's children")
        fake.element = nil
        expect(canvas.accessibilityChildren()?.contains { ($0 as AnyObject) === element } != true,
               "A hidden toolbar leaves the canvas's children")
        print("EaselSelectionToolbarCanvasTests passed")
    }
}
