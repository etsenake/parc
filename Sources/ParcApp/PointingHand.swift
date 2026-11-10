import AppKit
import SwiftUI

extension NSView {
    /// Asks for `cursorUpdate(with:)` while the pointer is over this view.
    /// AppKit sends the update to the view under the pointer, so a control
    /// covered by something drawn over it, such as the command bar, keeps
    /// that view's cursor.
    func addCursorUpdateArea(owner: NSView? = nil) {
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.cursorUpdate, .activeInKeyWindow, .inVisibleRect], owner: owner ?? self))
    }

    /// AppKit only asks for the cursor as the pointer enters, so a control
    /// that turns clickable or not under a still pointer sets it itself.
    func refreshPointingHand(_ shows: Bool) {
        guard let window, window.isKeyWindow, !isHiddenOrHasHiddenAncestor else { return }
        let point = window.mouseLocationOutsideOfEventStream
        guard visibleRect.contains(convert(point, from: nil)), let content = window.contentView,
              let hit = content.hitTest(content.superview?.convert(point, from: nil) ?? point),
              hit.isDescendant(of: self) || isDescendant(of: hit) else { return }
        (shows ? NSCursor.pointingHand : NSCursor.arrow).set()
    }
}

/// Every Parc button shows the pointing hand while a click on it does
/// something. Pop-up buttons, switches, segmented controls and colour wells
/// can't share this class, so each has its own below.
class PointingHandButton: NSButton {
    /// Narrowed by a control that can be enabled and still ignore a click.
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
    /// The pointing hand over this control while it is enabled.
    func pointingHandCursor() -> some View { background(PointingHandCursorArea()) }
}

/// A cursor rect rather than a cursor update: the update goes to the view
/// under the pointer, which is the hosting view, never this one.
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
