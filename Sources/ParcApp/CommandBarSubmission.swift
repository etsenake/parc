import AppKit

enum CommandBarSubmission: Equatable {
    case ordinary, split, background

    static func resolve(_ flags: NSEvent.ModifierFlags) -> Self? {
        switch flags.intersection([.command, .option, .control, .shift]) {
        case []: return .ordinary
        case .option: return .split
        case [.command, .option]: return .background
        default: return nil
        }
    }

    static func resolveReturn(_ flags: NSEvent.ModifierFlags) -> Self? {
        if flags.intersection([.command, .option, .control, .shift]) == .command { return .background }
        return resolve(flags)
    }

    static func resolveTextCommand(_ selector: Selector, event: NSEvent?, hasMarkedText: Bool) -> Self? {
        guard !hasMarkedText else { return nil }
        switch NSStringFromSelector(selector) {
        case "insertNewline:":
            return resolveReturn(event?.modifierFlags ?? [])
        case "insertNewlineIgnoringFieldEditor:":
            let flags = event?.modifierFlags.intersection([.command, .option, .control, .shift])
            return flags == nil || flags == .option ? .split : nil
        case "noop:":
            guard let event, event.type == .keyDown, [36, 76].contains(event.keyCode),
                  event.modifierFlags.intersection([.command, .option, .control, .shift]) == .command else { return nil }
            return .background
        default: return nil
        }
    }

}
