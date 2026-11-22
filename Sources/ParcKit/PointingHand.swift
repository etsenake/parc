import AppKit
import SwiftUI

extension NSView {
    package func addCursorUpdateArea(owner: NSView? = nil) {
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.cursorUpdate, .activeInKeyWindow, .inVisibleRect], owner: owner ?? self))
    }

    package func refreshPointingHand(_ shows: Bool) {
        guard let window, window.isKeyWindow, !isHiddenOrHasHiddenAncestor else { return }
        let point = window.mouseLocationOutsideOfEventStream
        guard visibleRect.contains(convert(point, from: nil)), let content = window.contentView,
              let hit = content.hitTest(content.superview?.convert(point, from: nil) ?? point),
              hit.isDescendant(of: self) || isDescendant(of: hit) else { return }
        (shows ? NSCursor.pointingHand : NSCursor.arrow).set()
    }
}

open class PointingHandButton: NSButton, Sendable {
    open var showsPointingHand: Bool { isEnabled }
    var setCursor: (NSCursor) -> Void = { $0.set() }

    public override init(frame: NSRect) {
        super.init(frame: frame)
        addCursorUpdateArea()
    }
    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        addCursorUpdateArea()
    }
    open override var isEnabled: Bool { didSet { if isEnabled != oldValue { refreshPointingHand(showsPointingHand) } } }
    open override func cursorUpdate(with event: NSEvent) {
        if showsPointingHand { setCursor(.pointingHand) } else { super.cursorUpdate(with: event) }
    }
}

open class PointingHandPopUpButton: NSPopUpButton, Sendable {
    public override convenience init(frame: NSRect) { self.init(frame: frame, pullsDown: false) }
    public override init(frame: NSRect, pullsDown: Bool) {
        super.init(frame: frame, pullsDown: pullsDown)
        addCursorUpdateArea()
    }
    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        addCursorUpdateArea()
    }
    open override var isEnabled: Bool { didSet { if isEnabled != oldValue { refreshPointingHand(isEnabled) } } }
    public override func cursorUpdate(with event: NSEvent) {
        if isEnabled { NSCursor.pointingHand.set() } else { super.cursorUpdate(with: event) }
    }
}

package final class PointingHandSwitch: NSSwitch {
    package override init(frame: NSRect) {
        super.init(frame: frame)
        addCursorUpdateArea()
    }
    package required init?(coder: NSCoder) {
        super.init(coder: coder)
        addCursorUpdateArea()
    }
    package override var isEnabled: Bool { didSet { if isEnabled != oldValue { refreshPointingHand(isEnabled) } } }
    package override func cursorUpdate(with event: NSEvent) {
        if isEnabled { NSCursor.pointingHand.set() } else { super.cursorUpdate(with: event) }
    }
}

package final class PointingHandSegmentedControl: NSSegmentedControl {
    package override init(frame: NSRect) {
        super.init(frame: frame)
        addCursorUpdateArea()
    }
    package required init?(coder: NSCoder) {
        super.init(coder: coder)
        addCursorUpdateArea()
    }
    package override var isEnabled: Bool { didSet { if isEnabled != oldValue { refreshPointingHand(isEnabled) } } }
    package override func cursorUpdate(with event: NSEvent) {
        if isEnabled { NSCursor.pointingHand.set() } else { super.cursorUpdate(with: event) }
    }
}

package final class PointingHandColorWell: NSColorWell {
    package override init(frame: NSRect) {
        super.init(frame: frame)
        addCursorUpdateArea()
    }
    package required init?(coder: NSCoder) {
        super.init(coder: coder)
        addCursorUpdateArea()
    }
    package override var isEnabled: Bool { didSet { if isEnabled != oldValue { refreshPointingHand(isEnabled) } } }
    package override func cursorUpdate(with event: NSEvent) {
        if isEnabled { NSCursor.pointingHand.set() } else { super.cursorUpdate(with: event) }
    }
}

extension View {
    package func pointingHandCursor() -> some View { modifier(PointingHandCursor()) }
}

struct PointingHandCursor: ViewModifier {
    @Environment(\.isEnabled) private var isEnabled
    func body(content: Content) -> some View {
        let marked = content.background(PointingHandCursorArea())
        if #available(macOS 15, *) { marked.pointerStyle(isEnabled ? .link : nil) } else { marked }
    }
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
