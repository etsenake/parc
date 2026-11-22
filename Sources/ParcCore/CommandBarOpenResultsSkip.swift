import Foundation

package enum CommandBarOpenResultsSkip {
    package static let sidebarBrowsingToken = "sidebar-browsing"

    package static func shouldSkip(previous: String?, next: String) -> Bool {
        previous == next
    }

    package static func tabToken(id: UUID, title: String, url: String, archived: Bool,
                         customTitle: String? = nil, caption: String = "") -> String {
        [id.uuidString, title, url, archived ? "1" : "0", customTitle ?? "", caption].joined(separator: "\u{1f}")
    }

    static func historyToken(url: String, title: String) -> String {
        [url, title].joined(separator: "\u{1f}")
    }

    package static func commandToken(id: String, title: String, group: String) -> String {
        [id, title, group].joined(separator: "\u{1f}")
    }

    package static func spaceToken(id: String, name: String, position: Int, needsPositionLabel: Bool) -> String {
        [id, name, String(position), needsPositionLabel ? "1" : "0"].joined(separator: "\u{1f}")
    }

    package static func folderToken(id: String, name: String, detail: String) -> String {
        [id, name, detail].joined(separator: "\u{1f}")
    }

    package static func fingerprint(
        query: String,
        actionsScope: Bool,
        websiteScoped: Bool,
        scopeInvalidated: Bool,
        scopeName: String,
        selectionID: String?,
        nativeError: String?,
        nativeRevision: UInt64 = 0,
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
            "publication:\(nativeRevision)",
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
