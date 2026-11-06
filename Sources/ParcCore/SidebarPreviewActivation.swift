import Foundation

///
/// shift 1, control 2, option 4, command 8, numericPad 0x10, capsLock 0x20,
///
///
struct SidebarPreviewModifiers: OptionSet, Hashable {
    let rawValue: UInt8
    init(rawValue: UInt8) { self.rawValue = rawValue }
    static let shift = Self(rawValue: 1), control = Self(rawValue: 2)
    static let option = Self(rawValue: 4), command = Self(rawValue: 8)
    static let numericPad = Self(rawValue: 0x10), capsLock = Self(rawValue: 0x20)
    static let help = Self(rawValue: 0x40), function = Self(rawValue: 0x80)

    /// `flags` is NSEvent.ModifierFlags.rawValue (device-independent bits 16–23).
    init(eventFlags flags: UInt) {
        let bits: [(UInt, Self)] = [(1 << 16, .capsLock), (1 << 17, .shift), (1 << 18, .control), (1 << 19, .option),
                                    (1 << 20, .command), (1 << 21, .numericPad), (1 << 22, .help), (1 << 23, .function)]
        self = bits.reduce(into: []) { result, bit in if flags & bit.0 != 0 { result.insert(bit.1) } }
    }

    ///
    var normalized: Self { subtracting(Self(rawValue: 0xF0)) }
}

/// What an activated preview row does. Recent rows and the header's plus
///
///
enum SidebarPreviewActivation: Equatable {
    /// Plain or Option: the previewed tab's own navigation policy routes the
    ///
    /// split-after-focused disposition (0x43) for a policy-created tab.
    case navigateSource(split: Bool)
    ///
    /// Option also asks for split-after-focused presentation.
    case openNewTab(split: Bool)
    /// Reveal the original's ancestors, select it (exact Option: in split
    /// after the focused pane) and dismiss.
    case selectOriginal(split: Bool)
    /// Exact Command-Shift: duplicate with shouldOpen; the preview stays and
    /// nothing is selected or revealed.
    case duplicate
    /// Any other Command combination: reveal ancestors and keep the preview.
    ///
    /// so Parc selects nothing (the predicate's empty-data result).
    case reveal
    ///
    /// the activation is consumed and the preview stays.
    case excludedLittleArc

    /// Shift and Control have no effect; the tests use `contains`, not equality.
    static func recentPage(_ modifiers: SidebarPreviewModifiers) -> Self {
        let split = modifiers.contains(.option)
        return modifiers.contains(.command) ? .openNewTab(split: split) : .navigateSource(split: split)
    }

    static func folderItem(_ modifiers: SidebarPreviewModifiers) -> Self {
        let flags = modifiers.normalized
        if flags == [.option, .command] { return .excludedLittleArc }
        if flags == [.command, .shift] { return .duplicate }
        if flags.contains(.command) { return .reveal }
        return .selectOriginal(split: flags == .option)
    }

    ///
    ///
    var dismissesPreview: Bool {
        switch self {
        case .navigateSource, .openNewTab, .selectOriginal: return true
        case .duplicate, .reveal, .excludedLittleArc: return false
        }
    }
}

///
///
///
/// a single pinned or Favorite item keeps its current or saved host, or an
/// unlocked authentication flow, in place; another host opens a new tab with
/// the source as referrer. Today and split sources navigate in place.
enum SidebarPreviewSourceRoute: Equatable {
    case inPlace, newTab

    static func route(to target: URL, isSavedItem: Bool, inSplit: Bool, currentHost: String?, savedHost: String?,
                      authenticationUnlocked: Bool) -> Self {
        guard isSavedItem, !inSplit, !authenticationUnlocked, let host = target.host else { return .inPlace }
        return host == currentHost || host == savedHost ? .inPlace : .newTab
    }
}
