import AppKit
import SwiftUI

extension NSView {
    func addCursorUpdateArea(owner: NSView? = nil) {
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.cursorUpdate, .activeInKeyWindow, .inVisibleRect], owner: owner ?? self))
    }

    func refreshPointingHand(_ shows: Bool) {
        guard let window, window.isKeyWindow, !isHiddenOrHasHiddenAncestor else { return }
        let point = window.mouseLocationOutsideOfEventStream
        guard visibleRect.contains(convert(point, from: nil)), let content = window.contentView,
              let hit = content.hitTest(content.superview?.convert(point, from: nil) ?? point),
              hit.isDescendant(of: self) || isDescendant(of: hit) else { return }
        (shows ? NSCursor.pointingHand : NSCursor.arrow).set()
    }
}

class PointingHandButton: NSButton {
    var showsPointingHand: Bool { isEnabled }

    override init(frame: NSRect) {
        super.init(frame: frame)
        addCursorUpdateArea()
    }
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        addCursorUpdateArea()
    }
    override var isEnabled: Bool { didSet { if isEnabled != oldValue { refreshPointingHand(showsPointingHand) } } }
    override func cursorUpdate(with event: NSEvent) {
        if showsPointingHand { NSCursor.pointingHand.set() } else { super.cursorUpdate(with: event) }
    }
}

class PointingHandPopUpButton: NSPopUpButton {
    override convenience init(frame: NSRect) { self.init(frame: frame, pullsDown: false) }
    override init(frame: NSRect, pullsDown: Bool) {
        super.init(frame: frame, pullsDown: pullsDown)
        addCursorUpdateArea()
    }
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        addCursorUpdateArea()
    }
    override var isEnabled: Bool { didSet { if isEnabled != oldValue { refreshPointingHand(isEnabled) } } }
    override func cursorUpdate(with event: NSEvent) {
        if isEnabled { NSCursor.pointingHand.set() } else { super.cursorUpdate(with: event) }
    }
}

final class PointingHandSwitch: NSSwitch {
    override init(frame: NSRect) {
        super.init(frame: frame)
        addCursorUpdateArea()
    }
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        addCursorUpdateArea()
    }
    override var isEnabled: Bool { didSet { if isEnabled != oldValue { refreshPointingHand(isEnabled) } } }
    override func cursorUpdate(with event: NSEvent) {
        if isEnabled { NSCursor.pointingHand.set() } else { super.cursorUpdate(with: event) }
    }
}

final class PointingHandSegmentedControl: NSSegmentedControl {
    override init(frame: NSRect) {
        super.init(frame: frame)
        addCursorUpdateArea()
    }
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        addCursorUpdateArea()
    }
    override var isEnabled: Bool { didSet { if isEnabled != oldValue { refreshPointingHand(isEnabled) } } }
    override func cursorUpdate(with event: NSEvent) {
        if isEnabled { NSCursor.pointingHand.set() } else { super.cursorUpdate(with: event) }
    }
}

final class PointingHandColorWell: NSColorWell {
    override init(frame: NSRect) {
        super.init(frame: frame)
        addCursorUpdateArea()
    }
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        addCursorUpdateArea()
    }
    override var isEnabled: Bool { didSet { if isEnabled != oldValue { refreshPointingHand(isEnabled) } } }
    override func cursorUpdate(with event: NSEvent) {
        if isEnabled { NSCursor.pointingHand.set() } else { super.cursorUpdate(with: event) }
    }
}

extension View {
    func pointingHandCursor() -> some View { background(PointingHandCursorArea()) }
}

private struct PointingHandCursorArea: NSViewRepresentable {
    func makeNSView(context: Context) -> AreaView { AreaView() }
    func updateNSView(_ view: AreaView, context: Context) { view.enabled = context.environment.isEnabled }

    final class AreaView: NSView {
        var enabled = true { didSet { if enabled != oldValue { window?.invalidateCursorRects(for: self) } } }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func resetCursorRects() {
            if enabled { addCursorRect(visibleRect, cursor: .pointingHand) }
        }
    }
}
