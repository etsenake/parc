import AppKit

@MainActor
private final class SilentSelectionToolbar: EaselSelectionToolbarPresenting {
    func refresh(for canvas: EaselCanvasView) {}
    func detach() {}
    func settle() {}
    func owns(_ responder: NSResponder?) -> Bool { false }
    func focusFromKeyboard() -> Bool { false }
    var accessibilityToolbar: Any? { nil }
}

@main
struct EaselCanvasHoverTests {
    @MainActor static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() { failTest(message) }
    }

    @MainActor static func main() { exitOnFailure(runChecks) }

    @MainActor static func quickDots(_ canvas: EaselCanvasView, for id: UUID) -> [EaselConnection.Side] {
        canvas.connectorChromeItems().compactMap {
            if case .quickCreate(let item, let side) = $0.chrome, item.id == id { return side }
            return nil
        }
    }

    @MainActor static func hover(_ canvas: EaselCanvasView, _ id: UUID?, at point: NSPoint) {
        canvas.hoveredObjectID = id
        canvas.updateConnectorHover(at: point)
        canvas.updateMindMapHover(at: point)
    }

    @MainActor static func press(_ type: NSEvent.EventType = .leftMouseDown) -> NSEvent {
        NSEvent.mouseEvent(with: type, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
                           context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
    }

    @MainActor static func dragDot(_ canvas: EaselCanvasView, from source: EaselItem, side: EaselConnection.Side, to point: NSPoint) {
        let center = NSPoint(x: source.frame.x + source.frame.width / 2, y: source.frame.y + source.frame.height / 2)
        hover(canvas, source.id, at: center)
        let dot = canvas.quickCreateDot(for: source, side: side)
        hover(canvas, nil, at: dot)
        canvas.start = dot
        expect(canvas.beginConnectorGesture(at: dot, event: press()), "Pressing a hovered dot starts a drag out of it")
        _ = canvas.continueConnectorGesture(to: point, event: press(.leftMouseDragged))
        _ = canvas.endConnectorGesture(at: point, event: press(.leftMouseUp))
        canvas.start = nil
    }

    @MainActor static func checkDraggingDots(_ date: Date) throws {
        let left = EaselItem(kind: .sticky, frame: .init(x: 100, y: 100, width: 160, height: 160), zIndex: 1, color: "#FFE58F")
        let right = EaselItem(kind: .sticky, frame: .init(x: 500, y: 100, width: 160, height: 160), zIndex: 2, color: "#FFE58F")
        let section = EaselItem(kind: .section, frame: .init(x: 400, y: 500, width: 600, height: 400), zIndex: 0, text: "Ideas")
        let cover = EaselItem(kind: .section, frame: .init(x: 60, y: 60, width: 240, height: 240), zIndex: 10, text: "On top")
        let document = EaselDocument(id: UUID(), title: "Links", createdAt: date, modifiedAt: date, items: [section, left, right, cover])
        let session = try EaselSession(inMemory: document, assets: [:])
        let canvas = EaselCanvasView(session: session)
        func count(_ kind: EaselItemKind) -> Int { session.document.items.filter { $0.kind == kind }.count }

        dragDot(canvas, from: left, side: .right, to: NSPoint(x: 580, y: 180))
        let links = session.document.items.filter { $0.kind == .arrow }
        expect(count(.sticky) == 2, "Dropping a dot on another sticky makes nothing new")
        expect(links.count == 1 && links.first.map {
            $0.startConnection?.itemID == left.id && $0.startConnection?.side == .right && $0.endConnection?.itemID == right.id
        } == true, "Dropping a dot on another sticky joins the two from that side")
        expect(links.first.map { canvas.selection == [$0.id] } == true, "The new connector ends up selected")
        try session.undo()
        expect(count(.arrow) == 0, "Joining is one Undo step")

        dragDot(canvas, from: left, side: .right, to: NSPoint(x: 150, y: 150))
        expect(count(.sticky) == 2 && count(.arrow) == 0, "Letting go back on the source changes nothing, even under a section on top")

        dragDot(canvas, from: left, side: .bottom, to: NSPoint(x: 700, y: 700))
        expect(count(.sticky) == 3 && count(.arrow) == 1, "Letting go inside a section places a new sticky there instead of joining the section")
        _ = canvas.finishEditing(removingEmpty: false)
    }

    @MainActor static func runChecks() throws {
        EaselCanvasView.selectionToolbarFactory = { SilentSelectionToolbar() }
        let date = Date()
        try checkDraggingDots(date)
        let sticky = EaselItem(kind: .sticky, frame: .init(x: 100, y: 100, width: 160, height: 160), zIndex: 1, color: "#FFE58F")
        var locked = EaselItem(kind: .rectangle, frame: .init(x: 600, y: 100, width: 120, height: 80), zIndex: 2)
        locked.locked = true
        let label = EaselItem(kind: .text, frame: .init(x: 100, y: 500, width: 200, height: 28), zIndex: 3, text: "Topic")
        let document = EaselDocument(id: UUID(), title: "Hover", createdAt: date, modifiedAt: date, items: [sticky, locked, label])
        let session = try EaselSession(inMemory: document, assets: [:])
        let canvas = EaselCanvasView(session: session)

        hover(canvas, sticky.id, at: NSPoint(x: 180, y: 180))
        expect(Set(quickDots(canvas, for: sticky.id)) == Set(EaselConnection.Side.allCases),
               "Hovering an unselected sticky shows a quick-create dot on every side")
        let right = canvas.quickCreateDot(for: sticky, side: .right)
        hover(canvas, nil, at: right)
        expect(quickDots(canvas, for: sticky.id).count == 4, "The dots stay while the pointer heads out to one")
        expect(canvas.connectors.quickHover.map { $0.id == sticky.id && $0.side == .right } == true, "The dot under the pointer turns into a plus")
        hover(canvas, nil, at: NSPoint(x: 900, y: 900))
        expect(quickDots(canvas, for: sticky.id).isEmpty, "The dots go once the pointer leaves")
        hover(canvas, label.id, at: NSPoint(x: 150, y: 510))
        expect(canvas.connectorChromeItems().isEmpty, "Text never shows quick-create dots")
        hover(canvas, locked.id, at: NSPoint(x: 650, y: 140))
        expect(quickDots(canvas, for: locked.id).isEmpty, "Locked shapes show no quick-create dots")

        hover(canvas, sticky.id, at: NSPoint(x: 180, y: 180))
        hover(canvas, nil, at: right)
        canvas.start = right
        expect(canvas.beginConnectorGesture(at: right, event: press()), "Pressing a hovered dot starts quick create without selecting first")
        _ = canvas.endConnectorGesture(at: right, event: press())
        canvas.start = nil
        let made = session.document.items.filter { $0.kind == .sticky && $0.id != sticky.id }
        expect(made.count == 1 && made.first.map { $0.frame.x > sticky.frame.x + sticky.frame.width } == true,
               "A click on the hovered sticky's right dot adds the next sticky to its right")
        expect(made.first.map { canvas.selection == [$0.id] } == true, "The new sticky ends up selected")
        _ = canvas.finishEditing()
        expect(quickDots(canvas, for: sticky.id).isEmpty, "The source's dots don't pop back once quick create is done")

        canvas.selection = []
        hover(canvas, sticky.id, at: NSPoint(x: 180, y: 180))
        canvas.tool = .hand
        canvas.tool = .select
        expect(canvas.connectorChromeItems().isEmpty, "Switching tools drops the hover dots until the pointer moves again")

        canvas.selection = []
        hover(canvas, sticky.id, at: NSPoint(x: 180, y: 180))
        canvas.start = NSPoint(x: 180, y: 180)
        expect(!canvas.beginConnectorGesture(at: NSPoint(x: 180, y: 180), event: press()), "Pressing the sticky itself isn't a dot press")
        canvas.start = nil
        expect(canvas.connectors.quickCreateHover == nil, "Pressing anywhere else drops the hover dots before a drag")

        canvas.selection = [label.id]
        expect(canvas.startMindMap(from: label.id), "Text starts a mind map")
        _ = canvas.finishEditing()
        canvas.selection = []
        guard let root = session.document.items.first(where: { $0.id == label.id }) else { failTest("The root survives") }
        func children() -> Int { session.document.items.filter { $0.kind == .text && $0.mindMap?.parent == root.id }.count }
        let before = children()
        let bounds = EaselShapeGeometry.visualBounds(of: root)
        let center = NSPoint(x: bounds.x + bounds.width / 2, y: bounds.y + bounds.height / 2)
        let plus = NSPoint(x: bounds.x + bounds.width + Double(EaselCanvasView.mindMapButtonOffset), y: center.y)
        hover(canvas, nil, at: plus)
        expect(canvas.mindMapControl(at: plus) == nil, "An unhovered, unselected node shows no + buttons")
        hover(canvas, root.id, at: center)
        hover(canvas, nil, at: plus)
        expect(canvas.mindMapControl(at: plus).map { $0.id == root.id && $0.control == .add(.right) } == true,
               "Hovering a node shows its + buttons, and they stay as the pointer heads out")
        canvas.start = plus
        expect(canvas.mindMapControlPress(at: plus), "A click on a + button lands even though the press has already begun")
        canvas.start = nil
        expect(children() == before + 1, "The click adds a child")
    }
}
