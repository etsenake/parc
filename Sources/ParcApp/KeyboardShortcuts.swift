import AppKit
import Carbon.HIToolbox
import Combine

enum CaptureGesturePreference {
    static let disabledKey = "parc.capture.dragDisabled"
    static func isEnabled(defaults: UserDefaults = .standard) -> Bool {
        !defaults.bool(forKey: disabledKey)
    }
    static func setEnabled(_ enabled: Bool, defaults: UserDefaults = .standard) {
        defaults.set(!enabled, forKey: disabledKey)
    }
    static func permits(_ flags: NSEvent.ModifierFlags) -> Bool {
        flags.contains([.command, .shift])
    }
}

struct KeyboardShortcut: Codable, Equatable, Hashable {
    let key: String
    let modifiers: UInt
    static let modifierMask: NSEvent.ModifierFlags = [.control, .option, .shift, .command]
    static let clearKey = "\u{f739}"
    static let keypadDecimalCode: UInt16 = 65
    private static let keypadMark: Unicode.Scalar = "\u{20e3}"
    private static let keypadCharacters: [UInt16: String] = [
        65: ".", 67: "*", 69: "+", 75: "/", 78: "-", 81: "=", 82: "0", 83: "1", 84: "2",
        85: "3", 86: "4", 87: "5", 88: "6", 89: "7", 91: "8", 92: "9", 95: ","
    ]
    var flags: NSEvent.ModifierFlags { .init(rawValue: modifiers) }
    var isKeypadKey: Bool {
        let scalars = Array(key.unicodeScalars)
        return scalars.count == 2 && scalars[1] == Self.keypadMark
    }
    var matchesPhysicalKey: Bool { isKeypadKey || key == Self.clearKey }

    init(key: String, flags: NSEvent.ModifierFlags) {
        var flags = flags.intersection(Self.modifierMask)
        if key.count == 1, let letter = key.first, letter.isLetter, letter.isUppercase { flags.insert(.shift) }
        self.key = key.lowercased(); modifiers = flags.rawValue
    }
    var isValid: Bool {
        key.count == 1 && modifiers == flags.intersection(Self.modifierMask).rawValue &&
        (!flags.intersection([.control, .option, .command]).isEmpty || isSpecialKey || key == "\u{1b}")
    }
    var isReserved: Bool {
        (flags == .command && ["z", "x", "v", "i", "b", "u", "a"].contains(key))
            || (flags == [.command, .shift] && key == "z")
            || (flags == .option && key == "\t")
    }
    var isFunctionKey: Bool {
        key.unicodeScalars.contains { (0xF704...0xF726).contains($0.value) }
    }
    private var isSpecialKey: Bool {
        key.unicodeScalars.contains { (0xF700...0xF747).contains($0.value) }
    }
    private var namedKey: String? {
        switch key {
        case "\t": return "⇥"
        case "\r", "\n": return "↩"
        case "\u{3}": return "⌤"
        case Self.clearKey: return "⌧"
        case " ": return "⎵"
        case "\u{1b}": return "⎋"
        case "\u{7f}", "\u{8}": return "⌫"
        case "\u{f728}": return "⌦"
        case "\u{f700}": return "↑"
        case "\u{f701}": return "↓"
        case "\u{f702}": return "←"
        case "\u{f703}": return "→"
        case "\u{f729}": return "↖"
        case "\u{f72b}": return "↘"
        case "\u{f72c}": return "⇞"
        case "\u{f72d}": return "⇟"
        case "\u{5}": return "?⃝"
        default:
            if isKeypadKey, let character = key.unicodeScalars.first {
                return Self.keypadName(character, typing: Self.layoutCharacter(forPhysicalCode:))
            }
            guard let value = key.unicodeScalars.first?.value, (0xF704...0xF717).contains(value) else { return nil }
            return "F\(value - 0xF703)"
        }
    }
    private var spokenKey: String? {
        switch key {
        case " ": return "Space"
        case "\u{3}": return "Enter"
        case Self.clearKey: return "Clear"
        default: return nil
        }
    }
    var keyLabel: String { namedKey ?? key.uppercased() }
    private var modifierSymbols: [String] {
        [(NSEvent.ModifierFlags.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘")]
            .filter { flags.contains($0.0) }.map(\.1)
    }
    var symbols: [String] { modifierSymbols + [namedKey ?? key.localizedUppercase] }
    var keycapSymbols: [String] { modifierSymbols + [key == "\t" ? "TAB" : namedKey ?? key.localizedUppercase] }
    var display: String { (modifierSymbols + [keyLabel]).joined() }
    var spokenDisplay: String { spokenKey.map { (modifierSymbols + [$0]).joined() } ?? display }
    var searchText: String {
        var names = [display, keyLabel]
        if let spokenKey { names.append(spokenKey) }
        for (flag, label) in [(NSEvent.ModifierFlags.control, "control ctrl"), (.option, "option alt"), (.shift, "shift"), (.command, "command cmd")] {
            if flags.contains(flag) { names.append(label) }
        }
        return names.joined(separator: " ").lowercased()
    }

    static func physicalKeys(producingShifted symbol: String) -> Set<String> {
        guard let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
              let property = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return [] }
        let data = Unmanaged<CFData>.fromOpaque(property).takeUnretainedValue()
        guard let bytes = CFDataGetBytePtr(data) else { return [] }
        let layout = UnsafeRawPointer(bytes).assumingMemoryBound(to: UCKeyboardLayout.self)
        func translated(_ code: UInt16, shifted: Bool) -> String? {
            var dead: UInt32 = 0, length = 0
            var characters = [UniChar](repeating: 0, count: 4)
            let result = UCKeyTranslate(layout, code, UInt16(kUCKeyActionDisplay),
                shifted ? UInt32(shiftKey >> 8) : 0, UInt32(LMGetKbdType()), 0, &dead,
                characters.count, &length, &characters)
            return result == noErr && length > 0 ? String(utf16CodeUnits: characters, count: length).lowercased() : nil
        }
        return Set((UInt16(0)..<128).compactMap { code in
            translated(code, shifted: true) == symbol ? translated(code, shifted: false) : nil
        })
    }

    typealias LayoutTyping = (UInt16, Int) -> String?
    static func capture(_ event: NSEvent, layout: LayoutTyping? = nil) -> KeyboardShortcut? {
        guard let key = keypadKey(forPhysicalCode: event.keyCode) else { return characterCapture(event, layout: layout) }
        let value = KeyboardShortcut(key: key, flags: event.modifierFlags)
        return value.isValid ? value : nil
    }
    static func characterCapture(_ event: NSEvent, layout: LayoutTyping? = nil) -> KeyboardShortcut? {
        guard let key = keyForPhysicalCode(event.keyCode, layout: layout) else { return nil }
        let value = KeyboardShortcut(key: key, flags: event.modifierFlags)
        return value.isValid ? value : nil
    }
    static func keypadKey(forPhysicalCode keyCode: UInt16) -> String? {
        if keyCode == 71 { return clearKey }
        return keypadCharacters[keyCode].map { $0 + String(keypadMark) }
    }
    private static let unprintable = CharacterSet.whitespacesAndNewlines.union(.controlCharacters).union(.nonBaseCharacters)
    static func keypadName(_ character: Unicode.Scalar, typing: (UInt16) -> String?) -> String {
        guard character == ".", let typed = typing(keypadDecimalCode), typed.count == 1,
              !typed.unicodeScalars.contains(where: unprintable.contains) else { return "Keypad \(character)" }
        return "Keypad \(typed)"
    }

    private static let functionKeyNumbers: [UInt16: UInt32] = [
        122: 1, 120: 2, 99: 3, 118: 4, 96: 5, 97: 6, 98: 7, 100: 8,
        101: 9, 109: 10, 103: 11, 111: 12, 105: 13, 107: 14, 113: 15, 106: 16,
        64: 17, 79: 18, 80: 19, 90: 20
    ]

    static func canBeNativeShortcut(_ event: NSEvent) -> Bool {
        if !event.modifierFlags.intersection([.command, .control, .option]).isEmpty { return true }
        return event.keyCode == 53 || functionKeyNumbers[event.keyCode] != nil
    }

    static func keyForPhysicalCode(_ keyCode: UInt16, layout: LayoutTyping? = nil) -> String? {
        let specials: [UInt16: String] = [36: "\r", 48: "\t", 49: " ", 51: "\u{7f}", 53: "\u{1b}",
            117: "\u{f728}", 123: "\u{f702}", 124: "\u{f703}", 125: "\u{f701}", 126: "\u{f700}",
            115: "\u{f729}", 119: "\u{f72b}", 116: "\u{f72c}", 121: "\u{f72d}"]
        let key: String?
        if let special = specials[keyCode] { key = special }
        else if let number = functionKeyNumbers[keyCode], let scalar = UnicodeScalar(0xF703 + number) { key = String(scalar) }
        else { key = typedKey(forPhysicalCode: keyCode, layout: layout ?? currentLayout()) }
        return key
    }
    private static let numberRowCodes: Set<UInt16> = [18, 19, 20, 21, 22, 23, 25, 26, 28, 29]
    static func isNumberRow(_ keyCode: UInt16) -> Bool { numberRowCodes.contains(keyCode) }
    static func typedKey(forPhysicalCode keyCode: UInt16, layout: LayoutTyping) -> String? {
        let base = layout(keyCode, 0)
        guard isNumberRow(keyCode), !isDigit(base) else { return base }
        for modifiers in [cmdKey, shiftKey] {
            if let typed = layout(keyCode, modifiers), isDigit(typed) { return typed }
        }
        return base
    }
    private static func isDigit(_ text: String?) -> Bool {
        guard let text, text.count == 1, let scalar = text.unicodeScalars.first else { return false }
        return ("0"..."9").contains(scalar)
    }
    static func currentLayout() -> LayoutTyping {
        let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue()
        return { code, modifiers in source.flatMap { layoutCharacter(forPhysicalCode: code, modifiers: modifiers, in: $0) } }
    }
    static func layoutCharacter(forPhysicalCode keyCode: UInt16) -> String? { currentLayout()(keyCode, 0) }
    static func layoutCharacter(forPhysicalCode keyCode: UInt16, modifiers: Int = 0, in source: TISInputSource) -> String? {
        guard let property = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(property).takeUnretainedValue()
        guard let bytes = CFDataGetBytePtr(data) else { return nil }
        let layout = UnsafeRawPointer(bytes).assumingMemoryBound(to: UCKeyboardLayout.self)
        var dead: UInt32 = 0, length = 0
        var characters = [UniChar](repeating: 0, count: 4)
        let result = UCKeyTranslate(layout, keyCode, UInt16(kUCKeyActionDisplay), UInt32((modifiers >> 8) & 0xFF),
            UInt32(LMGetKbdType()), 0, &dead,
            characters.count, &length, &characters)
        return result == noErr && length > 0 ? String(utf16CodeUnits: characters, count: length) : nil
    }
    @MainActor static func systemShortcuts() -> Set<KeyboardShortcut> {
        var result: Unmanaged<CFArray>?
        guard CopySymbolicHotKeys(&result) == noErr, let result else { return [] }
        let records = result.takeRetainedValue() as NSArray
        return systemShortcuts(records: records.compactMap { $0 as? [String: Any] })
    }
    static func systemShortcuts(records: [[String: Any]], layout: LayoutTyping? = nil) -> Set<KeyboardShortcut> {
        let layout = layout ?? currentLayout()
        return Set(records.flatMap { record -> [KeyboardShortcut] in
            guard (record[kHISymbolicHotKeyEnabled as String] as? NSNumber)?.boolValue == true,
                  let code = (record[kHISymbolicHotKeyCode as String] as? NSNumber)?.intValue,
                  (0...Int(UInt16.max)).contains(code),
                  let modifiers = (record[kHISymbolicHotKeyModifiers as String] as? NSNumber)?.uintValue,
                  let key = keypadKey(forPhysicalCode: UInt16(code)) ?? keyForPhysicalCode(UInt16(code), layout: layout),
                  !key.isEmpty else { return [] }
            var flags: NSEvent.ModifierFlags = []
            for (carbon, native) in [(controlKey, NSEvent.ModifierFlags.control),
                                     (optionKey, .option), (shiftKey, .shift), (cmdKey, .command)] {
                if modifiers & UInt(carbon) != 0 { flags.insert(native) }
            }
            guard !flags.isEmpty else { return [] }
            let own = isNumberRow(UInt16(code)) ? layout(UInt16(code), 0).flatMap { $0.isEmpty ? nil : $0 } : nil
            return [KeyboardShortcut(key: key, flags: flags)] + (own.map { [KeyboardShortcut(key: $0, flags: flags)] } ?? [])
        })
    }

}

@MainActor
final class KeyboardShortcuts: ObservableObject {
    static let shared = KeyboardShortcuts()
    struct Command: Identifiable {
        let id: String
        let title: String
        let group: String
        let defaultShortcut: KeyboardShortcut?
    }
    private struct Override: Codable { let shortcut: KeyboardShortcut? }
    enum Priority: String, Codable, CaseIterable {
        case preferWebsites, useBoth, preferParc
        var title: String {
            switch self { case .preferWebsites: return "Prefer Websites"; case .useBoth: return "Use Both"; case .preferParc: return "Prefer Parc" }
        }
        var explanation: String {
            switch self {
            case .preferWebsites: return "Use the website’s shortcut when it handles this key. Otherwise, use Parc’s shortcut."
            case .useBoth: return "Press once to use the website’s shortcut. If the website uses it, press again while the hint is visible to use Parc’s shortcut."
            case .preferParc: return "Use Parc’s shortcut before the website receives this key. Native text editing and macOS shortcuts keep their normal behavior."
            }
        }
        var native: PCNativeShortcutPriority {
            switch self { case .preferWebsites: return .preferWebsites; case .useBoth: return .useBoth; case .preferParc: return .preferParc }
        }
    }
    private struct Document: Codable {
        var version = 3
        var overrides: [String: Override]
        var priorities: [String: Priority]?
        var developerDefaults: Int? = 1
        var selectionCommandDefaults: Int? = 1
        var menuPriorityDefaults: Int? = 1
        var creationShortcutDefaults: Int? = 1
        var alternateShortcutDefaults: Int? = 1
        var closeWindowShortcutDefaults: Int? = 1
        var fullscreenShortcutDefaults: Int? = 1
        var exitShortcutDefaults: Int? = 1
        var findShortcutDefaults: Int? = 1
        var clearTodayShortcutDefaults: Int? = 1
        var pasteStyleShortcutDefaults: Int? = 1
        var inventoryShortcutDefaults: Int? = 1
        var numberedTargetShortcutDefaults: Int? = 1
        var peekOpenShortcutDefaults: Int? = 1
        var formatShortcutDefaults: Int? = 1
    }
    private final class MenuReference {
        weak var item: NSMenuItem?
        let id: String
        let equivalent: KeyboardShortcut?
        let discoverable: Bool
        init(_ item: NSMenuItem, id: String, equivalent: KeyboardShortcut? = nil, discoverable: Bool = true) {
            self.item = item; self.id = id; self.equivalent = equivalent; self.discoverable = discoverable
        }
    }
    enum Failure: LocalizedError {
        case unavailable, invalid, reserved, unreadable, staleConflict
        var errorDescription: String? {
            switch self {
            case .unavailable: return "This command is no longer available."
            case .staleConflict: return "Shortcuts changed while this conflict was open. Record the shortcut again."
            case .reserved: return "This shortcut is reserved for text editing or macOS. Choose another shortcut."
            case .invalid: return "Use Command, Control or Option with a key, or use a function or navigation key."
            case .unreadable: return "Saved shortcuts could not be read. Reset All Shortcuts to start again."
            }
        }
    }
    @Published private(set) var revision = 0
    private(set) var loadError: String?
    private var fileURL: URL?
    private var lastWrittenBytes: Data?
    private var commandsByID: [String: Command] = [:] { didSet { bindingUses = nil } }
    private var overrides: [String: Override] = [:] { didSet { bindingUses = nil } }
    private var bindingUses: [KeyboardShortcut: Int]?
    private var priorities: [String: Priority] = [:]
    private var references: [MenuReference] = []
    private var nativeChords: [KeyboardShortcut: [MenuReference]] = [:]
    private var assignedPhysicalChords: Set<KeyboardShortcut> = []
    private var symbolicDefaults: [KeyboardShortcut: [MenuReference]] = [:]
    private let textEditingActions: Set<String> = ["undo:", "redo:", "cut:", "copy:", "paste:", "selectAll:",
                                                   "formatBold", "formatItalic", "formatUnderline"]
    var commands: [Command] { commandsByID.values.filter { !textEditingActions.contains($0.id) }.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending } }
    var hasOverrides: Bool { !overrides.isEmpty || !priorities.isEmpty || loadError != nil }

    private var keyboardLayoutObserver: NSObjectProtocol?
    init() {
        keyboardLayoutObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String), object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.keyboardLayoutDidChange() } }
    }
    deinit {
        if let keyboardLayoutObserver { DistributedNotificationCenter.default().removeObserver(keyboardLayoutObserver) }
    }
    func keyboardLayoutDidChange() {
        apply(); didChange()
    }

    func configure(directory: URL) {
        fileURL = directory.appendingPathComponent("keyboard-shortcuts.json")
        overrides = [:]; priorities = [:]; loadError = nil; lastWrittenBytes = nil
        if let fileURL, FileManager.default.fileExists(atPath: fileURL.path) {
            do {
                var document = try JSONDecoder().decode(Document.self, from: Data(contentsOf: fileURL))
                guard (1...3).contains(document.version), document.overrides.values.allSatisfy({ $0.shortcut == nil || ($0.shortcut!.isValid && !$0.shortcut!.isReserved) }) else { throw Failure.unreadable }
                let needsMigration = document.version < 3
                if document.version == 1 {
                    for (old, new) in [("nextTab:", "cycleToNextRecentTab:"), ("previousTab:", "cycleToPreviousRecentTab:")] {
                        if let value = document.overrides.removeValue(forKey: old), document.overrides[new] == nil {
                            document.overrides[new] = value
                        }
                        if let value = document.priorities?.removeValue(forKey: old), document.priorities?[new] == nil {
                            document.priorities?[new] = value
                        }
                    }
                    let newDefaults: [(String, KeyboardShortcut)] = [
                        ("nextTab:", .init(key: "\u{f701}", flags: [.command, .option])),
                        ("previousTab:", .init(key: "\u{f700}", flags: [.command, .option])),
                        ("cycleTabForward:", .init(key: "\u{f703}", flags: [.command, .control])),
                        ("cycleTabBackward:", .init(key: "\u{f702}", flags: [.command, .control])),
                        ("copyCurrentURL:", .init(key: "c", flags: [.command, .shift]))]
                    for (id, shortcut) in newDefaults where document.overrides[id] == nil {
                        if document.overrides.contains(where: { $0.key != id && $0.value.shortcut == shortcut }) {
                            document.overrides[id] = Override(shortcut: nil)
                        }
                    }
                    document.version = 2
                }
                if document.version < 3 {
                    var savedPriorities = document.priorities ?? [:]
                    if savedPriorities["copyCurrentURL:"] == nil { savedPriorities["copyCurrentURL:"] = .preferWebsites }
                    document.priorities = savedPriorities
                    for (id, flags) in [("copyCurrentURLAsMarkdown:", NSEvent.ModifierFlags([.command, .option, .shift])),
                                        ("copyCurrentURLAsQuote:", NSEvent.ModifierFlags([.command, .control, .shift]))] {
                        let chord = KeyboardShortcut(key: "c", flags: flags)
                        if document.overrides[id] == nil,
                           document.overrides.contains(where: { $0.key != id && $0.value.shortcut == chord }) {
                            document.overrides[id] = Override(shortcut: nil)
                        }
                    }
                    document.version = 3
                }
                var renamedCommand = false
                for (old, new) in [("toggleArcToolbar:", "toggleShowToolbar:")] {
                    if let value = document.overrides.removeValue(forKey: old) {
                        if document.overrides[new] == nil { document.overrides[new] = value }
                        renamedCommand = true
                    }
                    if let value = document.priorities?.removeValue(forKey: old) {
                        if document.priorities?[new] == nil { document.priorities?[new] = value }
                        renamedCommand = true
                    }
                }
                if needsMigration || renamedCommand {
                    do {
                        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                        try encoder.encode(document).write(to: fileURL, options: .atomic)
                    } catch {
                        loadError = "Your shortcuts remain available, but their command migration could not be saved: " + error.localizedDescription
                    }
                }
                let reveal = KeyboardShortcut(key: " ", flags: [.control])
                if document.overrides["focusSidebar:"] == nil,
                   document.overrides.contains(where: { $0.key != "focusSidebar:" && $0.value.shortcut == reveal }) {
                    document.overrides["focusSidebar:"] = Override(shortcut: nil)
                    do {
                        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                        try encoder.encode(document).write(to: fileURL, options: .atomic)
                    } catch {
                        loadError = "Your existing shortcut remains available, but the new Reveal Current Tab binding could not be saved: " + error.localizedDescription
                    }
                }
                var developerMigration = false
                for (id, binding) in [
                    ("toggleDeveloperMode:", KeyboardShortcut(key: "d", flags: [.control])),
                    ("inspectElements:", KeyboardShortcut(key: "c", flags: [.command, .option])),
                    ("javaScriptConsole:", KeyboardShortcut(key: "j", flags: [.command, .option]))
                ] where document.overrides[id] == nil {
                    if document.overrides.contains(where: { $0.key != id && $0.value.shortcut == binding }) {
                        document.overrides[id] = Override(shortcut: nil); developerMigration = true
                    }
                }
                if document.developerDefaults == nil {
                    var saved = document.priorities ?? [:]
                    for id in ["developerTools:", "viewSource:"] where saved[id] == nil { saved[id] = .preferWebsites }
                    document.priorities = saved; document.developerDefaults = 1; developerMigration = true
                }
                if developerMigration {
                    do {
                        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                        try encoder.encode(document).write(to: fileURL, options: .atomic)
                    } catch { loadError = "Your shortcuts remain available, but the Developer command migration could not be saved: " + error.localizedDescription }
                }
                if document.selectionCommandDefaults == nil {
                    var saved = document.priorities ?? [:]
                    if saved["closeTab:"] == nil { saved["closeTab:"] = .preferWebsites }
                    document.priorities = saved; document.selectionCommandDefaults = 1
                    do {
                        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                        try encoder.encode(document).write(to: fileURL, options: .atomic)
                    } catch { loadError = "Your shortcuts remain available, but the Close Tab priority migration could not be saved: " + error.localizedDescription }
                }
                if document.menuPriorityDefaults == nil {
                    var saved = document.priorities ?? [:]
                    for id in Self.recoveredMenuPriorities.keys where saved[id] == nil {
                        saved[id] = .preferWebsites
                    }
                    document.priorities = saved; document.menuPriorityDefaults = 1
                    do {
                        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                        try encoder.encode(document).write(to: fileURL, options: .atomic)
                    } catch { loadError = "Your shortcuts remain available, but their menu priority migration could not be saved: " + error.localizedDescription }
                }
                if document.creationShortcutDefaults == nil {
                    for id in Self.recoveredCreationShortcuts.keys where document.overrides[id] == nil {
                        document.overrides[id] = Override(shortcut: nil)
                    }
                    document.creationShortcutDefaults = 1
                    do {
                        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                        try encoder.encode(document).write(to: fileURL, options: .atomic)
                    } catch { loadError = "Your shortcuts remain available, but their creation-command migration could not be saved: " + error.localizedDescription }
                }
                if document.alternateShortcutDefaults == nil {
                    for (id, parent, chord) in Self.recoveredAlternates where document.overrides[id] == nil {
                        if document.overrides[parent] != nil || document.overrides.contains(where: {
                            $0.key != id && $0.value.shortcut == chord
                        }) { document.overrides[id] = Override(shortcut: nil) }
                    }
                    document.alternateShortcutDefaults = 1
                    do {
                        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                        try encoder.encode(document).write(to: fileURL, options: .atomic)
                    } catch { loadError = "Your shortcuts remain available, but their alternate-command migration could not be saved: " + error.localizedDescription }
                }
                if document.clearTodayShortcutDefaults == nil {
                    if document.overrides["clearToday:"] == nil,
                       document.overrides.contains(where: {
                           $0.key != "clearToday:" && $0.value.shortcut == Self.clearTodayShortcut
                       }) { document.overrides["clearToday:"] = Override(shortcut: nil) }
                    document.clearTodayShortcutDefaults = 1
                    do {
                        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                        try encoder.encode(document).write(to: fileURL, options: .atomic)
                    } catch { loadError = "Your shortcuts remain available, but their Clear Today migration could not be saved: " + error.localizedDescription }
                }
                if document.findShortcutDefaults == nil {
                    for (id, chord) in Self.recoveredFindShortcuts where document.overrides[id] == nil {
                        if document.overrides.contains(where: { $0.key != id && $0.value.shortcut == chord }) {
                            document.overrides[id] = Override(shortcut: nil)
                        }
                    }
                    document.findShortcutDefaults = 1
                    do {
                        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                        try encoder.encode(document).write(to: fileURL, options: .atomic)
                    } catch { loadError = "Your shortcuts remain available, but their Find-command migration could not be saved: " + error.localizedDescription }
                }
                if document.closeWindowShortcutDefaults == nil {
                    if document.overrides["closeWindow:"] == nil,
                       document.overrides.contains(where: {
                           $0.key != "closeWindow:" && $0.value.shortcut == Self.closeWindowShortcut
                       }) { document.overrides["closeWindow:"] = Override(shortcut: nil) }
                    document.closeWindowShortcutDefaults = 1
                    do {
                        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                        try encoder.encode(document).write(to: fileURL, options: .atomic)
                    } catch { loadError = "Your shortcuts remain available, but their Close Window migration could not be saved: " + error.localizedDescription }
                }
                if document.fullscreenShortcutDefaults == nil {
                    if document.overrides["toggleFullScreen:"] == nil,
                       document.overrides.contains(where: {
                           $0.key != "toggleFullScreen:" && $0.value.shortcut == Self.fullscreenShortcut
                       }) { document.overrides["toggleFullScreen:"] = Override(shortcut: nil) }
                    document.fullscreenShortcutDefaults = 1
                    do {
                        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                        try encoder.encode(document).write(to: fileURL, options: .atomic)
                    } catch { loadError = "Your shortcuts remain available, but their Full Screen migration could not be saved: " + error.localizedDescription }
                }
                if document.exitShortcutDefaults == nil {
                    if document.overrides["exit:"] == nil,
                       document.overrides.contains(where: { $0.key != "exit:" && $0.value.shortcut == Self.exitShortcut }) {
                        document.overrides["exit:"] = Override(shortcut: nil)
                    }
                    document.exitShortcutDefaults = 1
                    do {
                        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                        try encoder.encode(document).write(to: fileURL, options: .atomic)
                    } catch { loadError = "Your shortcuts remain available, but their Exit migration could not be saved: " + error.localizedDescription }
                }
                if document.numberedTargetShortcutDefaults == nil {
                    for (id, chord) in Self.numberedTargetShortcuts where document.overrides[id] == nil {
                        if document.overrides.contains(where: { $0.key != id && $0.value.shortcut == chord }) {
                            document.overrides[id] = Override(shortcut: nil)
                        }
                    }
                    document.numberedTargetShortcutDefaults = 1
                    do {
                        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                        try encoder.encode(document).write(to: fileURL, options: .atomic)
                    } catch { loadError = "Your shortcuts remain available, but their numbered-target migration could not be saved: " + error.localizedDescription }
                }
                if document.pasteStyleShortcutDefaults == nil {
                    if document.overrides["pasteAsPlainText:"] == nil,
                       document.overrides.contains(where: {
                           $0.key != "pasteAsPlainText:" && $0.value.shortcut == Self.pasteStyleShortcut
                       }) { document.overrides["pasteAsPlainText:"] = Override(shortcut: nil) }
                    document.pasteStyleShortcutDefaults = 1
                    do {
                        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                        try encoder.encode(document).write(to: fileURL, options: .atomic)
                    } catch { loadError = "Your shortcuts remain available, but their Paste and Match Style migration could not be saved: " + error.localizedDescription }
                }
                if document.inventoryShortcutDefaults == nil {
                    for (id, chord) in Self.recoveredInventoryShortcuts where document.overrides[id] == nil {
                        if document.overrides.contains(where: { $0.key != id && $0.value.shortcut == chord }) {
                            document.overrides[id] = Override(shortcut: nil)
                        }
                    }
                    document.inventoryShortcutDefaults = 1
                    do {
                        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                        try encoder.encode(document).write(to: fileURL, options: .atomic)
                    } catch { loadError = "Your shortcuts remain available, but their new command migration could not be saved: " + error.localizedDescription }
                }
                if document.peekOpenShortcutDefaults == nil {
                    if document.overrides["openInCurrentSpace:"] == nil,
                       document.overrides.contains(where: {
                           $0.key != "openInCurrentSpace:" && $0.value.shortcut == Self.peekOpenShortcut
                       }) { document.overrides["openInCurrentSpace:"] = Override(shortcut: nil) }
                    document.peekOpenShortcutDefaults = 1
                    do {
                        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                        try encoder.encode(document).write(to: fileURL, options: .atomic)
                    } catch { loadError = "Your shortcuts remain available, but their Peek command migration could not be saved: " + error.localizedDescription }
                }
                if document.formatShortcutDefaults == nil {
                    for (id, chord) in Self.formatShortcuts where document.overrides[id] == nil {
                        if document.overrides.contains(where: { $0.key != id && $0.value.shortcut == chord }) {
                            document.overrides[id] = Override(shortcut: nil)
                        }
                    }
                    document.formatShortcutDefaults = 1
                    do {
                        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                        try encoder.encode(document).write(to: fileURL, options: .atomic)
                    } catch { loadError = "Your shortcuts remain available, but their Format command migration could not be saved: " + error.localizedDescription }
                }
                overrides = document.overrides
                priorities = document.priorities ?? [:]
                let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                lastWrittenBytes = try? encoder.encode(Document(overrides: overrides, priorities: priorities))
            } catch { loadError = Failure.unreadable.localizedDescription }
        }
        apply(); didChange()
    }
    private static let recoveredCreationShortcuts: [String: KeyboardShortcut] = [
        "createNote:": .init(key: "n", flags: [.control, .shift]),
        "createNoteInSplit:": .init(key: "n", flags: [.control, .option]),
        "createEasel:": .init(key: "e", flags: [.control, .shift]),
        "capturePage:": .init(key: "2", flags: [.command, .shift])
    ]
    private static let clearTodayShortcut = KeyboardShortcut(key: "k", flags: [.command, .shift])
    private static let exitShortcut = KeyboardShortcut(key: "\u{1b}", flags: [])
    private static let fullscreenShortcut = KeyboardShortcut(key: "f", flags: [.command, .control])
    private static let peekOpenShortcut = KeyboardShortcut(key: "o", flags: [.command])
    private static let closeWindowShortcut = KeyboardShortcut(key: "w", flags: [.command, .shift])
    private static let pasteStyleShortcut = KeyboardShortcut(key: "v", flags: [.command, .shift])
    private static let recoveredAlternates: [(String, String, KeyboardShortcut)] = [
        ("goBack_Alternate", "goBack:", .init(key: "\u{f702}", flags: .command)),
        ("goForward_Alternate", "goForward:", .init(key: "\u{f703}", flags: .command)),
        ("developerTools_Alternate", "developerTools:", .init(key: "\u{f70f}", flags: []))
    ]
    static let recoveredInventoryShortcuts: [String: KeyboardShortcut] = [
        "newBlankWindow:": .init(key: "n", flags: [.command, .control]),
        "viewLibrary:": .init(key: "l", flags: [.command, .shift]),
        "nextTab": .init(key: "}", flags: .command),
        "previousTab": .init(key: "{", flags: .command)
    ]
    static let formatShortcuts: [String: KeyboardShortcut] = [
        "formatBold": .init(key: "b", flags: .command),
        "formatItalic": .init(key: "i", flags: .command),
        "formatUnderline": .init(key: "u", flags: .command),
        "formatHeading1": .init(key: "h", flags: [.command, .shift]),
        "formatBody": .init(key: "b", flags: [.command, .shift]),
        "formatBulletedList": .init(key: "7", flags: [.command, .shift]),
        "formatNumberedList": .init(key: "9", flags: [.command, .shift]),
        "formatLink": .init(key: "k", flags: .command)
    ]
    static let symbolicShiftedKeys: Set<String> = ["+", "}", "{"]
    static let numberedTargetShortcuts: [String: KeyboardShortcut] = {
        var value: [String: KeyboardShortcut] = [
            "findAndReplace:": .init(key: "f", flags: [.command, .option]),
            "jumpToSelection:": .init(key: "j", flags: [.command])
        ]
        for number in 1...9 {
            value["item\(number)"] = .init(key: String(number), flags: [.command])
            value["space\(number)"] = .init(key: String(number), flags: [.control])
        }
        return value
    }()
    static let recoveredFindShortcuts: [String: KeyboardShortcut] = [
        "findNext:": .init(key: "g", flags: [.command]),
        "findPrevious:": .init(key: "g", flags: [.command, .shift])
    ]

    func register(_ item: NSMenuItem, group: String, bindingID: String? = nil,
                  title: String? = nil, discoverable: Bool = true) {
        guard let action = item.action else { return }
        let id = bindingID ?? NSStringFromSelector(action)
        if commandsByID[id] == nil {
            let windowShortcut: KeyboardShortcut?
            switch id {
            case "clearToday:": windowShortcut = Self.clearTodayShortcut
            case "exit:": windowShortcut = Self.exitShortcut
            case "toggleFullScreen:": windowShortcut = Self.fullscreenShortcut
            case "openInCurrentSpace:": windowShortcut = Self.peekOpenShortcut
            case "closeWindow:": windowShortcut = Self.closeWindowShortcut
            case "pasteAsPlainText:": windowShortcut = Self.pasteStyleShortcut
            default: windowShortcut = nil
            }
            let otherDefault = Self.numberedTargetShortcuts[id] ?? Self.recoveredFindShortcuts[id]
                ?? Self.recoveredCreationShortcuts[id] ?? Self.recoveredInventoryShortcuts[id] ?? Self.formatShortcuts[id]
                ?? Self.recoveredAlternates.first(where: { $0.0 == id })?.2
            let shortcut = windowShortcut ?? otherDefault
                ?? (item.keyEquivalent.isEmpty ? nil : KeyboardShortcut(key: item.keyEquivalent, flags: item.keyEquivalentModifierMask))
            commandsByID[id] = Command(id: id, title: title ?? item.title, group: group, defaultShortcut: shortcut)
        } else if let title, let existing = commandsByID[id], existing.title != title {
            commandsByID[id] = Command(id: id, title: title, group: existing.group, defaultShortcut: existing.defaultShortcut)
        }
        references.removeAll { $0.item == nil || $0.item === item }
        references.append(MenuReference(item, id: id, discoverable: discoverable))
        apply(); didChange()
    }
    func retireCommands(_ ids: [String]) {
        let retired = ids.filter { commandsByID[$0] != nil }
        guard !retired.isEmpty else { return }
        for id in retired { commandsByID[id] = nil }
        references.removeAll { $0.item == nil || retired.contains($0.id) }
        apply(); didChange()
    }
    func registerEquivalent(_ item: NSMenuItem, for id: String, shortcut chord: KeyboardShortcut) {
        guard commandsByID[id] != nil, let action = item.action,
              references.contains(where: { $0.id == id && $0.item?.action == action }) else { return }
        guard chord.isValid, !chord.isReserved else { return }
        references.removeAll { $0.item == nil || $0.item === item }
        references.append(MenuReference(item, id: id, equivalent: chord, discoverable: false))
        apply(); didChange()
    }
    private func shortcut(for reference: MenuReference) -> KeyboardShortcut? {
        guard let primary = activeShortcut(for: reference.id) else { return nil }
        guard let equivalent = reference.equivalent else { return primary }
        guard primary == commandsByID[reference.id]?.defaultShortcut,
              !commandsByID.keys.contains(where: { $0 != reference.id && shortcut(for: $0) == equivalent }) else { return nil }
        return equivalent
    }
    static func permitsArrowNavigation(in window: NSWindow?) -> Bool {
        guard let window else { return false }
        var view = window.firstResponder as? NSView
        while let current = view {
            if current is NSTextView || current is NSTextField { return false }
            view = current.superview
        }
        return true
    }
    func shortcut(for id: String) -> KeyboardShortcut? {
        if textEditingActions.contains(id) { return commandsByID[id]?.defaultShortcut }
        if let value = overrides[id] { return value.shortcut }
        return commandsByID[id]?.defaultShortcut
    }
    func conflictingCommands(for id: String) -> [Command] {
        guard !textEditingActions.contains(id), let binding = shortcut(for: id) else { return [] }
        return commandsByID.values.filter { $0.id != id && shortcut(for: $0.id) == binding }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }
    func isConflicting(_ id: String) -> Bool {
        guard !textEditingActions.contains(id), let binding = shortcut(for: id) else { return false }
        if bindingUses == nil {
            var uses: [KeyboardShortcut: Int] = [:]
            for other in commandsByID.keys { if let shortcut = shortcut(for: other) { uses[shortcut, default: 0] += 1 } }
            bindingUses = uses
        }
        return (bindingUses?[binding] ?? 0) > (commandsByID[id] == nil ? 0 : 1)
    }
    func activeShortcut(for id: String) -> KeyboardShortcut? {
        guard commandsByID[id] != nil, !isConflicting(id) else { return nil }
        return shortcut(for: id)
    }
    func isCustomized(_ id: String) -> Bool { overrides[id] != nil || priorities[id] != nil }
    private static let recoveredMenuPriorities: [String: Priority] = [
        "goBack:": .preferParc, "goForward:": .preferParc,
        "cycleTabForward:": .preferParc, "cycleTabBackward:": .preferParc,
        "focusAddress:": .preferParc, "newTab:": .preferParc,
        "newWindow:": .preferParc, "newIncognitoWindow:": .preferParc,
        "restoreTab:": .preferParc,
        "nextTab:": .preferParc, "previousTab:": .preferParc,
        "cycleToNextRecentTab:": .preferParc, "cycleToPreviousRecentTab:": .preferParc,
        "hide:": .preferParc, "quitMenu:": .preferParc, "performMiniaturize:": .preferParc,
        "split:": .useBoth, "closeSplitPane:": .useBoth,
        "createNote:": .useBoth, "createNoteInSplit:": .useBoth,
        "printPage:": .useBoth, "toggleSidebar:": .useBoth,
        "togglePin:": .useBoth, "focusSidebar:": .useBoth
    ]
    private func defaultPriority(for id: String) -> Priority {
        if let priority = Self.recoveredMenuPriorities[id] { return priority }
        if ["copyCurrentURL:", "copyCurrentURLAsMarkdown:", "copyCurrentURLAsQuote:", "closeTab:", "closeWindow:"].contains(id) { return .preferParc }
        if ["developerTools_Alternate", "developerTools:", "viewSource:", "toggleDeveloperMode:", "inspectElements:", "toggleShowToolbar:", "toggleFullScreen:", "exit:", "openInCurrentSpace:"].contains(id) { return .useBoth }
        return .preferWebsites
    }
    func priority(for id: String) -> Priority { priorities[id] ?? defaultPriority(for: id) }
    func supportsPriority(_ id: String) -> Bool {
        guard !textEditingActions.contains(id), let shortcut = shortcut(for: id), !shortcut.isReserved else { return false }
        return (id == "exit:" && shortcut == Self.exitShortcut)
            || shortcut.isFunctionKey || !shortcut.flags.intersection([.command, .control, .option]).isEmpty
    }
    func setPriority(_ priority: Priority, for id: String) throws {
        guard loadError == nil else { throw Failure.unreadable }
        guard commandsByID[id] != nil, supportsPriority(id) else { throw Failure.unavailable }
        var next = priorities
        next[id] = priority == defaultPriority(for: id) ? nil : priority
        try commit(overrides, priorities: next)
    }
    private func didChange() {
        revision += 1
        rebuildNativeChords()
        PCNativeShortcutCommand.bindingsDidChange()
        refreshLiveHelp()
        liveMenuBindings = liveMenuBindings.filter { $0.value.item != nil }
        liveMenuBindings.values.forEach(applyDiscoveryBinding)
        onDiscoveryChange?()
    }
    private func rebuildNativeChords() {
        var chords: [KeyboardShortcut: [MenuReference]] = [:]
        var assigned: Set<KeyboardShortcut> = []
        var symbolic: [KeyboardShortcut: [MenuReference]] = [:]
        chords.reserveCapacity(references.count)
        for reference in references {
            guard !textEditingActions.contains(reference.id) else { continue }
            if let chord = shortcut(for: reference) {
                chords[chord, default: []].append(reference)
            }
            if reference.equivalent == nil,
               let value = activeShortcut(for: reference.id),
               value == commandsByID[reference.id]?.defaultShortcut,
               Self.symbolicShiftedKeys.contains(value.key) {
                symbolic[value, default: []].append(reference)
            }
        }
        for id in commandsByID.keys {
            if let chord = shortcut(for: id) { assigned.insert(chord) }
        }
        nativeChords = chords
        assignedPhysicalChords = assigned
        symbolicDefaults = symbolic
    }

    static func toolTip(_ title: String, shortcut: KeyboardShortcut?) -> String {
        shortcut.map { "\(title) \($0.display)" } ?? title
    }
    func toolTip(_ title: String, for id: String?) -> String {
        Self.toolTip(title, shortcut: id.flatMap { activeShortcut(for: $0) })
    }
    private final class LiveHelp {
        weak var view: NSView?
        let title: String
        let id: String?
        let requiresBinding: Bool
        init(view: NSView, title: String, id: String?, requiresBinding: Bool) {
            self.view = view; self.title = title; self.id = id; self.requiresBinding = requiresBinding
        }
    }
    private var liveHelp: [ObjectIdentifier: LiveHelp] = [:]
    private var liveHelpPruneThreshold = 64
    var onDiscoveryChange: (() -> Void)?
    private var liveMenuBindings: [ObjectIdentifier: MenuReference] = [:]
    private var liveMenuPruneThreshold = 64
    func bindHelp(_ view: NSView, title: String, commandID: String?, requiresBinding: Bool = false) {
        if liveHelp.count >= liveHelpPruneThreshold {
            liveHelp = liveHelp.filter { $0.value.view != nil }
            liveHelpPruneThreshold = max(64, liveHelp.count * 2)
        }
        let entry = LiveHelp(view: view, title: title, id: commandID, requiresBinding: requiresBinding)
        liveHelp[ObjectIdentifier(view)] = entry
        apply(entry)
    }
    private func apply(_ entry: LiveHelp) {
        guard let view = entry.view else { return }
        let shortcut = entry.id.flatMap { activeShortcut(for: $0) }
        let help = entry.requiresBinding && shortcut == nil ? nil : shortcut.map { "\(entry.title) \($0.spokenDisplay)" } ?? entry.title
        view.setAccessibilityHelp(help); (view as? NSControl)?.cell?.setAccessibilityHelp(help)
    }
    private func refreshLiveHelp() {
        liveHelp = liveHelp.filter { $0.value.view != nil }
        liveHelp.values.forEach(apply)
    }
    func showBinding(on item: NSMenuItem, for id: String) {
        if liveMenuBindings.count >= liveMenuPruneThreshold {
            liveMenuBindings = liveMenuBindings.filter { $0.value.item != nil }
            liveMenuPruneThreshold = max(64, liveMenuBindings.count * 2)
        }
        let reference = MenuReference(item, id: id, discoverable: false)
        liveMenuBindings[ObjectIdentifier(item)] = reference
        applyDiscoveryBinding(reference)
    }
    private func applyDiscoveryBinding(_ reference: MenuReference) {
        guard let item = reference.item else { return }
        let shortcut = activeShortcut(for: reference.id).flatMap { $0.isKeypadKey ? nil : $0 }
        item.keyEquivalent = shortcut?.key ?? ""
        item.keyEquivalentModifierMask = shortcut?.flags ?? []
    }

    static func typesReservedCharacters(_ event: NSEvent) -> Bool {
        guard let characters = event.characters, characters.count == 1 else { return false }
        return KeyboardShortcut(key: characters, flags: event.modifierFlags).isReserved
    }
    func chord(for event: NSEvent, layout: KeyboardShortcut.LayoutTyping? = nil) -> KeyboardShortcut? {
        if let key = KeyboardShortcut.keypadKey(forPhysicalCode: event.keyCode) {
            let physical = KeyboardShortcut(key: key, flags: event.modifierFlags)
            if assignedPhysicalChords.contains(physical) { return physical }
        }
        guard KeyboardShortcut.isNumberRow(event.keyCode) else { return KeyboardShortcut.characterCapture(event, layout: layout) }
        let layout = layout ?? KeyboardShortcut.currentLayout()
        guard let chord = KeyboardShortcut.characterCapture(event, layout: layout) else { return nil }
        guard let typed = layout(event.keyCode, 0) else { return chord }
        let own = KeyboardShortcut(key: typed, flags: event.modifierFlags)
        let bound = assignedPhysicalChords.contains(own) || (nativeChords[own] != nil && !assignedPhysicalChords.contains(chord))
        return own != chord && own.isValid && bound ? own : chord
    }
    func isAssigned(_ event: NSEvent, layout: KeyboardShortcut.LayoutTyping? = nil) -> Bool {
        chord(for: event, layout: layout).map(assignedPhysicalChords.contains) ?? false
    }
    func recordedChord(for event: NSEvent, layout: KeyboardShortcut.LayoutTyping? = nil) -> KeyboardShortcut? {
        KeyboardShortcut.keypadKey(forPhysicalCode: event.keyCode) == nil
            ? chord(for: event, layout: layout) : KeyboardShortcut.capture(event, layout: layout)
    }
    func performKeypadEquivalent(_ event: NSEvent) -> Bool? {
        guard event.type == .keyDown, let key = KeyboardShortcut.keypadKey(forPhysicalCode: event.keyCode) else { return nil }
        let physical = KeyboardShortcut(key: key, flags: event.modifierFlags)
        guard assignedPhysicalChords.contains(physical) else { return nil }
        guard NSApp.modalWindow == nil else { return false }
        for reference in nativeChords[physical] ?? [] {
            guard let item = reference.item, let target = validatedTarget(item), let action = item.action else { continue }
            guard NSApp.sendAction(action, to: target, from: item) else { return false }
            if let menu = item.menu {
                NotificationCenter.default.post(name: NSMenu.didSendActionNotification, object: menu, userInfo: ["MenuItem": item])
            }
            return true
        }
        return false
    }
    func boundShortcut(for command: PCNativeShortcutCommand) -> KeyboardShortcut? {
        guard let item = command.item, let reference = references.first(where: { $0.item === item }) else { return nil }
        return shortcut(for: reference)
    }
    private func eligibleShortcut(_ event: NSEvent) -> KeyboardShortcut? {
        guard event.type == .keyDown, !event.isARepeat, KeyboardShortcut.canBeNativeShortcut(event),
              let shortcut = chord(for: event),
              !shortcut.isReserved, !Self.typesReservedCharacters(event) else { return nil }
        let preferredExit = shortcut == Self.exitShortcut && self.shortcut(for: "exit:") == shortcut
            && priority(for: "exit:") == .preferParc
        guard preferredExit || shortcut.isFunctionKey || !shortcut.flags.intersection([.command, .control, .option]).isEmpty else { return nil }
        return shortcut
    }
    private func isAttached(_ item: NSMenuItem) -> Bool {
        var menu = item.menu
        while let parent = menu?.supermenu { menu = parent }
        return menu != nil && menu === NSApp.mainMenu
            && (!item.isHidden || item.allowsKeyEquivalentWhenHidden)
    }
    private func validatedTarget(_ item: NSMenuItem) -> AnyObject? {
        guard isAttached(item), let action = item.action,
              let target = NSApp.target(forAction: action, to: item.target, from: item) as AnyObject? else { return nil }
        if item.menu?.autoenablesItems == false {
            guard item.isEnabled else { return nil }
        } else if let validator = target as? NSMenuItemValidation {
            guard validator.validateMenuItem(item) else { return nil }
        } else if let validator = target as? NSUserInterfaceValidations {
            guard validator.validateUserInterfaceItem(item) else { return nil }
        } else if !item.isEnabled { return nil }
        return target
    }
    @MainActor final class MenuCommand {
        let id: String
        let title: String
        let toolTip: String?
        let group: String
        let shortcut: KeyboardShortcut?
        fileprivate weak var item: NSMenuItem?
        fileprivate weak var window: NSWindow?
        fileprivate let revision: Int
        fileprivate init(id: String, item: NSMenuItem, group: String, shortcut: KeyboardShortcut?, window: NSWindow, revision: Int) {
            self.id = id; self.item = item; title = item.title; toolTip = item.toolTip; self.group = group
            self.shortcut = shortcut; self.window = window; self.revision = revision
        }
    }
    func menuCommands(in window: NSWindow) -> [MenuCommand] {
        var seen = Set<String>()
        return references.compactMap { reference in
            guard reference.discoverable, !textEditingActions.contains(reference.id), !["copyCurrentURL:", "copyCurrentURLAsMarkdown:", "copyCurrentURLAsQuote:"].contains(reference.id), let item = reference.item,
                  isAttached(item), !item.isSeparatorItem, !item.hasSubmenu,
                  let metadata = commandsByID[reference.id], seen.insert(reference.id).inserted else { return nil }
            _ = validatedTarget(item)
            return MenuCommand(id: reference.id, item: item, group: metadata.group,
                               shortcut: activeShortcut(for: reference.id), window: window, revision: revision)
        }.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }
    func canPerformMenuCommand(_ command: MenuCommand) -> Bool {
        guard command.revision == revision, let window = command.window,
              window.isVisible, !window.isMiniaturized, NSApp.isActive,
              NSApp.mainWindow === window, window.attachedSheet == nil,
              let item = command.item,
              references.contains(where: { $0.id == command.id && $0.item === item }) else { return false }
        return validatedTarget(item) != nil
    }
    @discardableResult func performMenuCommand(_ command: MenuCommand) -> Bool {
        guard canPerformMenuCommand(command), let item = command.item,
              let target = validatedTarget(item), let action = item.action else { return false }
        return NSApp.sendAction(action, to: target, from: item)
    }

    func nativeCommand(for event: NSEvent, editable: Bool) -> PCNativeShortcutCommand? {
        guard let shortcut = eligibleShortcut(event) else { return nil }
        if let command = firstValidNativeCommand(from: nativeChords[shortcut] ?? []) { return command }
        guard let symbolic = symbolicChord(for: event, physical: shortcut) else { return nil }
        return firstValidNativeCommand(from: symbolicDefaults[symbolic] ?? [])
    }
    func symbolicChord(for event: NSEvent) -> KeyboardShortcut? {
        guard let physical = chord(for: event), firstValidNativeCommand(from: nativeChords[physical] ?? []) == nil else { return nil }
        return symbolicChord(for: event, physical: physical)
    }
    private func symbolicChord(for event: NSEvent, physical shortcut: KeyboardShortcut) -> KeyboardShortcut? {
        guard shortcut.flags.contains(.shift), let symbol = event.charactersIgnoringModifiers,
              Self.symbolicShiftedKeys.contains(symbol), !assignedPhysicalChords.contains(shortcut) else { return nil }
        return KeyboardShortcut(key: symbol, flags: shortcut.flags.subtracting(.shift))
    }
    private func firstValidNativeCommand(from candidates: [MenuReference]) -> PCNativeShortcutCommand? {
        for reference in candidates {
            guard let item = reference.item, validatedTarget(item) != nil else { continue }
            return PCNativeShortcutCommand(item: item, revision: UInt64(revision), priority: priority(for: reference.id).native)
        }
        return nil
    }
    func settingsCommandID(for command: PCNativeShortcutCommand) -> String? {
        guard command.revision == UInt64(revision), let item = command.item, isAttached(item),
              let reference = references.first(where: { $0.item === item }),
              commands.contains(where: { $0.id == reference.id }),
              priority(for: reference.id).native == command.priority else { return nil }
        return reference.id
    }
    func isExitCommand(_ command: PCNativeShortcutCommand) -> Bool {
        guard let item = command.item else { return false }
        return references.contains { $0.id == "exit:" && $0.item === item }
    }
    func perform(_ command: PCNativeShortcutCommand, event: NSEvent, editable: Bool) -> Bool {
        guard command.revision == UInt64(revision), let item = command.item,
              let current = nativeCommand(for: event, editable: editable), current.item === item,
              current.revision == command.revision, current.priority == command.priority,
              let target = validatedTarget(item), let action = item.action else { return false }
        return NSApp.sendAction(action, to: target, from: item)
    }

    struct ConflictProposal {
        let commandID: String
        let shortcut: KeyboardShortcut
        let conflicts: [Command]
        let revision: Int
        fileprivate let resetsPriority: Bool
    }
    func conflictProposal(for shortcut: KeyboardShortcut, commandID: String,
                          resetsPriority: Bool = false) throws -> ConflictProposal? {
        guard loadError == nil else { throw Failure.unreadable }
        guard commandsByID[commandID] != nil, !textEditingActions.contains(commandID) else { throw Failure.unavailable }
        guard shortcut.isValid else { throw Failure.invalid }
        guard !shortcut.isReserved else { throw Failure.reserved }
        let conflicts = commandsByID.values.filter { $0.id != commandID && self.shortcut(for: $0.id) == shortcut }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        guard !conflicts.contains(where: { textEditingActions.contains($0.id) }) else { throw Failure.reserved }
        guard !conflicts.isEmpty else { return nil }
        return ConflictProposal(commandID: commandID, shortcut: shortcut, conflicts: conflicts,
                                revision: revision, resetsPriority: resetsPriority)
    }
    func resolveConflict(_ proposal: ConflictProposal) throws {
        guard proposal.revision == revision,
              let current = try conflictProposal(for: proposal.shortcut, commandID: proposal.commandID,
                                                 resetsPriority: proposal.resetsPriority),
              current.conflicts.map(\.id) == proposal.conflicts.map(\.id),
              let target = commandsByID[proposal.commandID] else { throw Failure.staleConflict }
        var next = overrides
        for command in proposal.conflicts { next[command.id] = Override(shortcut: nil) }
        next[proposal.commandID] = proposal.shortcut == target.defaultShortcut ? nil : Override(shortcut: proposal.shortcut)
        var nextPriorities = priorities
        if proposal.resetsPriority { nextPriorities[proposal.commandID] = nil }
        try commit(next, priorities: nextPriorities)
    }

    func set(_ shortcut: KeyboardShortcut?, for id: String) throws {
        guard loadError == nil else { throw Failure.unreadable }
        guard let command = commandsByID[id], !textEditingActions.contains(id) else { throw Failure.unavailable }
        if let shortcut {
            guard shortcut.isValid else { throw Failure.invalid }
            guard !shortcut.isReserved else { throw Failure.reserved }
            if commandsByID.keys.contains(where: { $0 != id && textEditingActions.contains($0) && self.shortcut(for: $0) == shortcut }) { throw Failure.reserved }
        }
        var next = overrides
        next[id] = shortcut == command.defaultShortcut ? nil : Override(shortcut: shortcut)
        try commit(next)
    }
    func reset(_ id: String) throws {
        guard loadError == nil else { throw Failure.unreadable }
        guard commandsByID[id] != nil, !textEditingActions.contains(id) else { throw Failure.unavailable }
        var next = overrides; next[id] = nil
        var nextPriorities = priorities; nextPriorities[id] = nil
        try commit(next, priorities: nextPriorities)
    }
    func resetAll() throws { try commit([:], priorities: [:]); loadError = nil; didChange() }
    private func commit(_ next: [String: Override], priorities nextPriorities: [String: Priority]? = nil) throws {
        guard let fileURL else { throw Failure.unavailable }
        let resolvedPriorities = nextPriorities ?? priorities
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(Document(overrides: next, priorities: resolvedPriorities))
        if SettingsPrettyJSONPersistSkip.shouldSkip(previous: lastWrittenBytes, next: data) {
            overrides = next; priorities = resolvedPriorities
            return
        }
        try data.write(to: fileURL, options: .atomic)
        lastWrittenBytes = data
        overrides = next; priorities = resolvedPriorities; apply(); didChange()
    }
    private func apply() {
        references.removeAll { $0.item == nil }
        var suppressedSymbolic = Set<String>()
        for (id, command) in commandsByID {
            guard let primary = shortcut(for: id), Self.symbolicShiftedKeys.contains(primary.key),
                  primary == command.defaultShortcut else { continue }
            let physicalOwners = commandsByID.keys.filter { $0 != id }.compactMap { shortcut(for: $0) }
                .filter { $0.flags == primary.flags.union(.shift) }
            guard !physicalOwners.isEmpty else { continue }
            let keys = KeyboardShortcut.physicalKeys(producingShifted: primary.key)
            if physicalOwners.contains(where: { keys.contains($0.key) }) { suppressedSymbolic.insert(id) }
        }
        for reference in references {
            guard let item = reference.item else { continue }
            let value = shortcut(for: reference)
            let suppressed = (suppressedSymbolic.contains(reference.id) && reference.equivalent == nil)
                || (reference.id == "exit:" && value == Self.exitShortcut) || value?.isKeypadKey == true
            item.keyEquivalent = suppressed ? "" : value?.key ?? ""
            item.keyEquivalentModifierMask = suppressed ? [] : value?.flags ?? []
        }
    }

}

final class ShortcutMainMenu: NSMenu {
    weak var shortcuts: KeyboardShortcuts?
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let handled = MainActor.assumeIsolated { (shortcuts ?? .shared).performKeypadEquivalent(event) }
        return handled ?? super.performKeyEquivalent(with: event)
    }
}
