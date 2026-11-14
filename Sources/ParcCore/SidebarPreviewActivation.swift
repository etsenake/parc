import Foundation

struct SidebarPreviewModifiers: OptionSet, Hashable {
    let rawValue: UInt8
    init(rawValue: UInt8) { self.rawValue = rawValue }
    static let shift = Self(rawValue: 1), control = Self(rawValue: 2)
    static let option = Self(rawValue: 4), command = Self(rawValue: 8)
    static let numericPad = Self(rawValue: 0x10), capsLock = Self(rawValue: 0x20)
    static let help = Self(rawValue: 0x40), function = Self(rawValue: 0x80)

    init(eventFlags flags: UInt) {
        let bits: [(UInt, Self)] = [(1 << 16, .capsLock), (1 << 17, .shift), (1 << 18, .control), (1 << 19, .option),
                                    (1 << 20, .command), (1 << 21, .numericPad), (1 << 22, .help), (1 << 23, .function)]
        self = bits.reduce(into: []) { result, bit in if flags & bit.0 != 0 { result.insert(bit.1) } }
    }

    var normalized: Self { subtracting(Self(rawValue: 0xF0)) }
}

enum SidebarPreviewActivation: Equatable {
    case navigateSource(split: Bool)
    case openNewTab(split: Bool)
    case selectOriginal(split: Bool)
    case duplicate
    case reveal
    case excludedMiniWindow

    static func recentPage(_ modifiers: SidebarPreviewModifiers) -> Self {
        let split = modifiers.contains(.option)
        return modifiers.contains(.command) ? .openNewTab(split: split) : .navigateSource(split: split)
    }

    static func folderItem(_ modifiers: SidebarPreviewModifiers) -> Self {
        let flags = modifiers.normalized
        if flags == [.option, .command] { return .excludedMiniWindow }
        if flags == [.command, .shift] { return .duplicate }
        if flags.contains(.command) { return .reveal }
        return .selectOriginal(split: flags == .option)
    }

    var dismissesPreview: Bool {
        switch self {
        case .navigateSource, .openNewTab, .selectOriginal: return true
        case .duplicate, .reveal, .excludedMiniWindow: return false
        }
    }
}

enum SidebarPreviewSourceRoute: Equatable {
    case inPlace, newTab

    static func route(to target: URL, isSavedItem: Bool, inSplit: Bool, currentHost: String?, savedHost: String?,
                      authenticationUnlocked: Bool) -> Self {
        guard isSavedItem, !inSplit, !authenticationUnlocked, let host = target.host else { return .inPlace }
        return host == currentHost || host == savedHost ? .inPlace : .newTab
    }
}
