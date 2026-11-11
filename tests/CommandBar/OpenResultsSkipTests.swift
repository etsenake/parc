import Foundation

@main
struct OpenResultsSkipTests {
    static var assertions = 0
    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        assertions += 1
        precondition(condition(), message)
    }

    static func main() {
        typealias Skip = CommandBarOpenResultsSkip

        expect(Skip.shouldSkip(previous: nil, next: "a") == false, "First fingerprint never skips")
        expect(Skip.shouldSkip(previous: "a", next: "a"), "Identical fingerprint skips")
        expect(Skip.shouldSkip(previous: "a", next: "b") == false, "Changed fingerprint does not skip")
        expect(Skip.shouldSkip(previous: Skip.sidebarBrowsingToken, next: Skip.sidebarBrowsingToken),
               "Identical sidebar-browsing token skips")

        let tabA = Skip.tabToken(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
                                 title: "Example", url: "https://example.test", archived: false)
        let tabB = Skip.tabToken(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
                                 title: "Example", url: "https://example.test", archived: false)
        let tabTitle = Skip.tabToken(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
                                     title: "Changed", url: "https://example.test", archived: false)
        expect(tabA == tabB, "Stable tab membership tokens match")
        expect(tabA != tabTitle, "Tab title membership change alters token")
        let tabID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        expect(tabA != Skip.tabToken(id: tabID, title: "Example", url: "https://example.test", archived: false, customTitle: "Mine"),
               "A custom title alters the token")
        expect(Skip.tabToken(id: tabID, title: "Example", url: "https://example.test", archived: false, caption: "Switch to Tab")
               != Skip.tabToken(id: tabID, title: "Example", url: "https://example.test", archived: false, caption: "Work"),
               "A changed Switch to Tab caption alters the token")

        let histA = Skip.historyToken(url: "https://example.test", title: "Example")
        let histB = Skip.historyToken(url: "https://example.test", title: "Example")
        let histTitle = Skip.historyToken(url: "https://example.test", title: "Changed")
        expect(histA == histB, "Stable history membership tokens match")
        expect(histA != histTitle, "History title membership change alters token")

        func fingerprint(query: String, selection: String? = nil, tabs: [String] = [tabA],
                         history: [String] = [histA]) -> String {
            Skip.fingerprint(
                query: query,
                actionsScope: false,
                websiteScoped: false,
                scopeInvalidated: false,
                scopeName: "",
                selectionID: selection,
                nativeError: nil,
                nativeResultIDs: [],
                extensionActionIDs: [],
                extensionLaunchIDs: [],
                tabTokens: tabs,
                historyTokens: history,
                commandTokens: [],
                spaceTokens: [],
                folderTokens: [],
                folderMoveIDs: [],
                favoriteActionID: nil,
                favoriteEligible: false,
                favoriteRenameID: nil,
                renameEligible: false,
                retainedBackgroundID: nil,
                retainedBackgroundRow: nil,
                supportsMuteAllTabs: false
            )
        }

        let idle = fingerprint(query: "")
        expect(Skip.shouldSkip(previous: idle, next: idle), "Identical empty-query fingerprint skips")
        expect(Skip.shouldSkip(previous: idle, next: fingerprint(query: "a")) == false,
               "Typing a new character must not skip")
        expect(Skip.shouldSkip(previous: idle, next: fingerprint(query: "", selection: "tab:1")) == false,
               "Selection change must not skip")
        expect(Skip.shouldSkip(previous: idle, next: fingerprint(query: "", tabs: [tabTitle])) == false,
               "Tab membership change must not skip")
        expect(Skip.shouldSkip(previous: idle, next: fingerprint(query: "", history: [histTitle])) == false,
               "History membership change must not skip")
        expect(Skip.shouldSkip(previous: idle, next: fingerprint(query: "", tabs: [tabB])),
               "Unchanged tab membership remains a true no-op")

        let extA = Skip.fingerprint(
            query: "q",
            actionsScope: false,
            websiteScoped: false,
            scopeInvalidated: false,
            scopeName: "",
            selectionID: nil,
            nativeError: nil,
            nativeResultIDs: ["native:false:https://a.test:A"],
            extensionActionIDs: ["extension:ext:edit:Title:0"],
            extensionLaunchIDs: [],
            tabTokens: [],
            historyTokens: [],
            commandTokens: [],
            spaceTokens: [],
            folderTokens: [],
            folderMoveIDs: [],
            favoriteActionID: nil,
            favoriteEligible: false,
            favoriteRenameID: nil,
            renameEligible: false,
            retainedBackgroundID: nil,
            retainedBackgroundRow: nil,
            supportsMuteAllTabs: false
        )
        let extReordered = Skip.fingerprint(
            query: "q",
            actionsScope: false,
            websiteScoped: false,
            scopeInvalidated: false,
            scopeName: "",
            selectionID: nil,
            nativeError: nil,
            nativeResultIDs: ["native:false:https://a.test:A"],
            extensionActionIDs: ["extension:ext:edit:Title:2"],
            extensionLaunchIDs: [],
            tabTokens: [],
            historyTokens: [],
            commandTokens: [],
            spaceTokens: [],
            folderTokens: [],
            folderMoveIDs: [],
            favoriteActionID: nil,
            favoriteEligible: false,
            favoriteRenameID: nil,
            renameEligible: false,
            retainedBackgroundID: nil,
            retainedBackgroundRow: nil,
            supportsMuteAllTabs: false
        )
        expect(Skip.shouldSkip(previous: extA, next: extA), "Stable extension-action index skips")
        expect(Skip.shouldSkip(previous: extA, next: extReordered) == false,
               "Extension-action resultIndex-only change must not skip")

        print("\(assertions) command-bar open results skip assertions passed")
    }
}
