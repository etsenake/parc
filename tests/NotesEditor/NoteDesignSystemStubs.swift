import AppKit

struct KeyboardShortcut: Equatable {
    let key: String
    let flags: NSEvent.ModifierFlags
    init(key: String, flags: NSEvent.ModifierFlags) {
        self.key = key
        self.flags = flags
    }
    static func == (lhs: KeyboardShortcut, rhs: KeyboardShortcut) -> Bool { lhs.key == rhs.key && lhs.flags == rhs.flags }
}

struct TooltipConfiguration {
    enum Anchor { case top, bottom, leading, trailing, topLeading, topTrailing, bottomLeading, bottomTrailing, cursor }
    enum Shortcut { case fixed(KeyboardShortcut), command(String) }
    var label: String
    var shortcut: Shortcut?
    init(_ label: String, shortcut: Shortcut? = nil, anchor: Anchor = .bottomTrailing) {
        self.label = label
        self.shortcut = shortcut
    }
}

@MainActor enum LiveShortcutToolTip {
    static func set(_ view: NSView, _ title: String, commandID: String? = nil, anchor: TooltipConfiguration.Anchor = .bottomTrailing) {
        view.parcTooltip = TooltipConfiguration(title, shortcut: commandID.map { .command($0) })
    }
}

@MainActor private var attachedTooltips: [ObjectIdentifier: TooltipConfiguration] = [:]

extension NSView {
    @MainActor var parcTooltip: TooltipConfiguration? {
        get { attachedTooltips[ObjectIdentifier(self)] }
        set { attachedTooltips[ObjectIdentifier(self)] = newValue }
    }
}
