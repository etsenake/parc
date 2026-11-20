import AppKit

enum TextFormatCommand: Int, CaseIterable {
    case bold, italic, underline, strikethrough, bigger, smaller
    case heading1, heading2, heading3, body, bulletedList, numberedList
    case increaseIndent, decreaseIndent, link

    static let action = NSSelectorFromString("formatText:")
    static let addLinkTitle = "Add Link…"
    static let editLinkTitle = "Edit Link…"

    init?(_ sender: Any?) {
        guard let item = sender as? NSMenuItem, item.action == Self.action else { return nil }
        self.init(rawValue: item.tag)
    }
    var title: String {
        switch self {
        case .bold: "Bold"
        case .italic: "Italic"
        case .underline: "Underline"
        case .strikethrough: "Strikethrough"
        case .bigger: "Bigger"
        case .smaller: "Smaller"
        case .heading1: "Heading 1"
        case .heading2: "Heading 2"
        case .heading3: "Heading 3"
        case .body: "Body"
        case .bulletedList: "Bulleted List"
        case .numberedList: "Numbered List"
        case .increaseIndent: "Increase"
        case .decreaseIndent: "Decrease"
        case .link: Self.addLinkTitle
        }
    }
    var commandTitle: String {
        switch self {
        case .bigger: "Bigger Text"
        case .smaller: "Smaller Text"
        case .body: "Body Text"
        case .increaseIndent: "Increase List Indent"
        case .decreaseIndent: "Decrease List Indent"
        case .link: "Add or Edit Link…"
        default: title
        }
    }
    var bindingID: String {
        switch self {
        case .bold: "formatBold"
        case .italic: "formatItalic"
        case .underline: "formatUnderline"
        case .strikethrough: "formatStrikethrough"
        case .bigger: "formatBigger"
        case .smaller: "formatSmaller"
        case .heading1: "formatHeading1"
        case .heading2: "formatHeading2"
        case .heading3: "formatHeading3"
        case .body: "formatBody"
        case .bulletedList: "formatBulletedList"
        case .numberedList: "formatNumberedList"
        case .increaseIndent: "formatIncreaseIndent"
        case .decreaseIndent: "formatDecreaseIndent"
        case .link: "formatLink"
        }
    }
}

struct TextFormatKeyEquivalent: Equatable {
    static let modifierMask: NSEvent.ModifierFlags = [.control, .option, .shift, .command]
    let key: String
    let modifiers: NSEvent.ModifierFlags

    init(key: String, modifiers: NSEvent.ModifierFlags) {
        var flags = modifiers.intersection(Self.modifierMask)
        if key.count == 1, let letter = key.first, letter.isLetter, letter.isUppercase { flags.insert(.shift) }
        self.key = key.lowercased()
        self.modifiers = flags
    }

    @MainActor
    init?(of item: NSMenuItem) {
        guard !item.keyEquivalent.isEmpty else { return nil }
        self.init(key: item.keyEquivalent, modifiers: item.keyEquivalentModifierMask)
    }
}

@MainActor
protocol TextFormatShortcutOwner: AnyObject {
    func formatKeyEquivalent(for command: TextFormatCommand) -> TextFormatKeyEquivalent?
}

@MainActor
enum TextFormatMenu {
    @MainActor private final class StateReset: NSObject, NSMenuDelegate {
        private var shown = TextFormatShortcutSwap()
        func menuNeedsUpdate(_ menu: NSMenu) {
            for item in menu.items where item.action == TextFormatCommand.action {
                item.state = .off
                if TextFormatCommand(item) == .link { item.title = TextFormatCommand.addLinkTitle }
            }
        }
        func menuWillOpen(_ menu: NSMenu) {
            let owner = NSApp.target(forAction: TextFormatCommand.action, to: nil, from: nil) as? TextFormatShortcutOwner
            shown.show(owner, in: menu)
        }
        func menuDidClose(_ menu: NSMenu) { shown.restore(in: menu) }
    }
    private enum Section {
        case submenu(String, [[TextFormatCommand]])
        case items([TextFormatCommand])
    }
    private static let reset = StateReset()
    private static let layout: [Section] = [
        .submenu("Font", [[.bold, .italic, .underline, .strikethrough], [.bigger, .smaller]]),
        .items([.heading1, .heading2, .heading3, .body]),
        .items([.bulletedList, .numberedList]),
        .submenu("Indentation", [[.increaseIndent, .decreaseIndent]]),
        .items([.link])
    ]

    @discardableResult
    static func add(to edit: NSMenu, register: (NSMenuItem, TextFormatCommand) -> Void) -> NSMenuItem {
        func menu(_ title: String, in parent: NSMenu) -> (NSMenuItem, NSMenu) {
            let menu = NSMenu(title: title); menu.delegate = reset
            let root = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            root.submenu = menu; parent.addItem(root)
            return (root, menu)
        }
        func add(_ commands: [TextFormatCommand], to menu: NSMenu) {
            for command in commands {
                let item = NSMenuItem(title: command.title, action: TextFormatCommand.action, keyEquivalent: "")
                item.tag = command.rawValue
                menu.addItem(item)
                register(item, command)
            }
        }
        let (root, format) = menu("Format", in: edit)
        for (index, section) in layout.enumerated() {
            if index > 0 { format.addItem(.separator()) }
            switch section {
            case .items(let commands): add(commands, to: format)
            case .submenu(let title, let groups):
                let (_, submenu) = menu(title, in: format)
                for (group, commands) in groups.enumerated() {
                    if group > 0 { submenu.addItem(.separator()) }
                    add(commands, to: submenu)
                }
            }
        }
        return root
    }
}

@MainActor
struct TextFormatShortcutSwap {
    private struct Entry {
        let item: NSMenuItem
        let original: TextFormatKeyEquivalent?
        let shown: TextFormatKeyEquivalent?
    }
    private var entries: [ObjectIdentifier: Entry] = [:]

    private static func apply(_ equivalent: TextFormatKeyEquivalent?, to item: NSMenuItem) {
        item.keyEquivalent = equivalent?.key ?? ""
        item.keyEquivalentModifierMask = equivalent?.modifiers ?? []
    }

    mutating func show(_ owner: TextFormatShortcutOwner?, in menu: NSMenu) {
        guard let owner else { return }
        for item in menu.items {
            guard let command = TextFormatCommand(item) else { continue }
            let key = ObjectIdentifier(item)
            let current = TextFormatKeyEquivalent(of: item)
            var original = current
            if let previous = entries[key], previous.shown == current { original = previous.original }
            let next = owner.formatKeyEquivalent(for: command)
            entries[key] = Entry(item: item, original: original, shown: next)
            Self.apply(next, to: item)
        }
    }

    mutating func restore(in menu: NSMenu) {
        for item in menu.items {
            guard let entry = entries.removeValue(forKey: ObjectIdentifier(item)) else { continue }
            if TextFormatKeyEquivalent(of: item) == entry.shown { Self.apply(entry.original, to: item) }
        }
    }
}
