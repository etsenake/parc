import AppKit

@MainActor final class FilmInput {
    static let shared = FilmInput()

    var currentEvent: NSEvent?
    var pressed = false
    var cursorStack: [NSCursor] = []
    var cursorRects: [(NSView, NSRect, NSCursor)] = []
    var cursor: NSCursor = .arrow
    weak var root: NSView?
    var point = NSPoint(x: -100, y: -100)
    var time: Double = 0
    var stageOffset = NSPoint.zero
    private var inside: [ObjectIdentifier: NSTrackingArea] = [:]
    private var trackedFrames: [ObjectIdentifier: NSRect] = [:]
    private var lastPoint = NSPoint(x: -1000, y: -1000)
    private(set) var target: NSView?

    var screenLocation: NSPoint { NSPoint(x: point.x + stageOffset.x, y: 2000 - (point.y + stageOffset.y)) }

    func cursorSet(_ next: NSCursor) { cursor = next }

    func base(_ local: NSPoint) -> NSPoint { root!.convert(local, to: nil) }

    func mouse(_ type: NSEvent.EventType, clicks: Int = 1) -> NSEvent {
        NSEvent.mouseEvent(with: type, location: base(point), modifierFlags: [], timestamp: 1000 + time, windowNumber: 0, context: nil,
                           eventNumber: 0, clickCount: clicks, pressure: type == .leftMouseUp || type == .mouseMoved ? 0 : 1)!
    }

    func key(_ characters: String, code: UInt16 = 0) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 1000 + time, windowNumber: 0, context: nil,
                         characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code)!
    }

    func hit() -> NSView? { root?.hitTest(base(point)) }

    func down(clicks: Int = 1) -> NSView? {
        let event = mouse(.leftMouseDown, clicks: clicks)
        currentEvent = event
        pressed = true
        target = hit()
        target?.mouseDown(with: event)
        return target
    }

    func drag() {
        guard pressed else { return }
        let event = mouse(.leftMouseDragged)
        currentEvent = event
        target?.mouseDragged(with: event)
    }

    func up(clicks: Int = 1) {
        let event = mouse(.leftMouseUp, clicks: clicks)
        currentEvent = event
        pressed = false
        target?.mouseUp(with: event)
        target = nil
    }

    var downEvent: NSEvent?

    func press() -> NSEvent {
        let event = mouse(.leftMouseDown)
        currentEvent = event
        downEvent = event
        pressed = true
        return event
    }

    func release() -> NSEvent {
        let event = mouse(.leftMouseUp)
        currentEvent = event
        downEvent = nil
        pressed = false
        return event
    }

    static func visible(_ view: NSView) -> [NSView] { view.isHidden ? [] : [view] + view.subviews.flatMap(visible) }

    static func visibleRect(of view: NSView) -> NSRect {
        var rect = view.bounds
        var current = view
        while let parent = current.superview {
            rect = parent.convert(rect, from: current).intersection(parent.bounds)
            if rect.isEmpty { return .zero }
            current = parent
        }
        return view.convert(rect, from: current)
    }

    func hover() {
        guard let root else { return }
        let moved = point != lastPoint
        lastPoint = point
        let views = Self.visible(root)
        for view in views {
            let id = ObjectIdentifier(view)
            let frame = view.convert(view.bounds, to: nil)
            if trackedFrames[id] != frame {
                trackedFrames[id] = frame
                view.updateTrackingAreas()
            }
        }
        let location = base(point)
        var now: [ObjectIdentifier: NSTrackingArea] = [:]
        var owners: [ObjectIdentifier: NSView] = [:]
        for view in views {
            let local = view.convert(location, from: nil)
            for area in view.trackingAreas {
                let rect = area.options.contains(.inVisibleRect) ? Self.visibleRect(of: view) : area.rect
                if NSMouseInRect(local, rect, view.isFlipped) {
                    now[ObjectIdentifier(area)] = area
                    owners[ObjectIdentifier(area)] = view
                }
            }
        }
        func event(_ type: NSEvent.EventType, _ area: NSTrackingArea) -> NSEvent {
            NSEvent.enterExitEvent(with: type, location: location, modifierFlags: [], timestamp: 1000 + time, windowNumber: 0, context: nil,
                                   eventNumber: 0, trackingNumber: Int(bitPattern: Unmanaged.passUnretained(area).toOpaque()), userData: nil)!
        }
        let live = { (area: NSTrackingArea) in !self.pressed || area.options.contains(.enabledDuringMouseDrag) }
        for (id, area) in inside where now[id] == nil && live(area) {
            (area.owner as? NSResponder)?.mouseExited(with: event(.mouseExited, area))
        }
        var entered: [NSTrackingArea] = []
        for (id, area) in now where inside[id] == nil && live(area) {
            entered.append(area)
            if area.options.contains(.mouseEnteredAndExited) { (area.owner as? NSResponder)?.mouseEntered(with: event(.mouseEntered, area)) }
            if area.options.contains(.cursorUpdate) { (area.owner as? NSResponder)?.cursorUpdate(with: event(.cursorUpdate, area)) }
        }
        if moved && !pressed {
            let move = mouse(.mouseMoved)
            for (id, area) in now where area.options.contains(.mouseMoved) && !entered.contains(where: { ObjectIdentifier($0) == id }) {
                (area.owner as? NSResponder)?.mouseMoved(with: move)
            }
        }
        var kept = now
        if pressed { for (id, area) in inside where !live(area) { kept[id] = area } }
        inside = kept
        if !pressed { refreshCursor(views, location) }
        _ = owners
    }

    func refreshCursor(_ views: [NSView], _ location: NSPoint) {
        if let pushed = cursorStack.last { cursor = pushed; return }
        var chosen: NSCursor?
        for view in views {
            let local = view.convert(location, from: nil)
            let visible = Self.visibleRect(of: view)
            guard NSMouseInRect(local, visible, view.isFlipped) else { continue }
            cursorRects.removeAll()
            view.resetCursorRects()
            for (_, rect, cursor) in cursorRects where NSMouseInRect(local, rect.intersection(visible), view.isFlipped) { chosen = cursor }
        }
        cursorRects.removeAll()
        cursor = chosen ?? .arrow
    }

    var shownCursor: NSCursor { cursorStack.last ?? cursor }
}
