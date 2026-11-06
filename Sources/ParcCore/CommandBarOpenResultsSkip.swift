import Foundation

/// Open-bar result rebuild skip. Everyday refresh/reconcile ticks that leave
/// the query and result identity unchanged must not rebuild Result rows or call
/// `reloadData`/`layoutContents`. Membership inputs are fingerprinted cheaply;
/// closed-bar snapshot gating stays in `CommandBarReconcileInputs`.
enum CommandBarOpenResultsSkip {
    /// Distinct presentation while the sidebar-anchored bar is in browse mode.
    static let sidebarBrowsingToken = "sidebar-browsing"

    /// True no-op: identical open-bar presentation fingerprint, including an
    /// identical empty or sidebar-browsing token. A changed query, selection,
    /// or tab/history membership bit must not skip.
    static func shouldSkip(previous: String?, next: String) -> Bool {
        previous == next
    }

    /// A tab row also shows its custom title and its Switch to Tab caption,
    /// which follows the active Space and split membership.
    static func tabToken(id: UUID, title: String, url: String, archived: Bool,
                         customTitle: String? = nil, caption: String = "") -> String {
        [id.uuidString, title, url, archived ? "1" : "0", customTitle ?? "", caption].joined(separator: "\u{1f}")
    }

    static func historyToken(url: String, title: String) -> String {
        [url, title].joined(separator: "\u{1f}")
    }

    static func commandToken(id: String, title: String, group: String) -> String {
        [id, title, group].joined(separator: "\u{1f}")
    }

    static func spaceToken(id: String, name: String, profileName: String, needsProfileLabel: Bool) -> String {
        [id, name, profileName, needsProfileLabel ? "1" : "0"].joined(separator: "\u{1f}")
    }

    static func folderToken(id: String, name: String, detail: String) -> String {
        [id, name, detail].joined(separator: "\u{1f}")
    }

    /// Fingerprint of the open-bar query plus every input that feeds result
    /// identity (tab/history membership, natives, commands, selection, scope).
    static func fingerprint(
        query: String,
        actionsScope: Bool,
        websiteScoped: Bool,
        scopeInvalidated: Bool,
        scopeName: String,
        selectionID: String?,
        nativeError: String?,
        nativeResultIDs: [String],
        extensionActionIDs: [String],
        extensionLaunchIDs: [String],
        tabTokens: [String],
        historyTokens: [String],
        commandTokens: [String],
        spaceTokens: [String],
        folderTokens: [String],
        folderMoveIDs: [String],
        favoriteActionID: String?,
        favoriteEligible: Bool,
        favoriteRenameID: String?,
        renameEligible: Bool,
        retainedBackgroundID: String?,
        retainedBackgroundRow: Int?,
        supportsMuteAllTabs: Bool
    ) -> String {
        var parts: [String] = [
            "q:\(query)",
            actionsScope ? "a1" : "a0",
            websiteScoped ? "w1" : "w0",
            scopeInvalidated ? "i1" : "i0",
            "scope:\(scopeName)",
            "sel:\(selectionID ?? "-")",
            "err:\(nativeError ?? "-")",
            "fav:\(favoriteActionID ?? "-")|\(favoriteEligible ? "1" : "0")",
            "ren:\(favoriteRenameID ?? "-")|\(renameEligible ? "1" : "0")",
            "bg:\(retainedBackgroundID ?? "-")|\(retainedBackgroundRow.map(String.init) ?? "-")",
            supportsMuteAllTabs ? "mute1" : "mute0",
        ]
        parts.append("native:\(nativeResultIDs.joined(separator: ","))")
        parts.append("ext:\(extensionActionIDs.joined(separator: ","))")
        parts.append("launch:\(extensionLaunchIDs.joined(separator: ","))")
        parts.append("tabs:\(tabTokens.joined(separator: ";"))")
        parts.append("hist:\(historyTokens.joined(separator: ";"))")
        parts.append("cmd:\(commandTokens.joined(separator: ";"))")
        parts.append("space:\(spaceTokens.joined(separator: ";"))")
        parts.append("folder:\(folderTokens.joined(separator: ";"))")
        parts.append("move:\(folderMoveIDs.joined(separator: ","))")
        return parts.joined(separator: "|")
    }
}
