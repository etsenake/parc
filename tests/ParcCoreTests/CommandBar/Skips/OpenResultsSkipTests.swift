import Foundation
import Testing
@testable import ParcCore

struct OpenResultsSkipTests {
    typealias Skip = CommandBarOpenResultsSkip

    let tabID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

    func tabToken(title: String = "Example", customTitle: String? = nil, caption: String? = nil) -> String {
        guard customTitle != nil || caption != nil else {
            return Skip.tabToken(id: tabID, title: title, url: "https://example.test", archived: false)
        }
        if let customTitle {
            return Skip.tabToken(id: tabID, title: title, url: "https://example.test", archived: false, customTitle: customTitle)
        }
        return Skip.tabToken(id: tabID, title: title, url: "https://example.test", archived: false, caption: caption!)
    }

    func fingerprint(query: String, selection: String? = nil, tabs: [String]? = nil, history: [String]? = nil) -> String {
        Skip.fingerprint(
            query: query, actionsScope: false, websiteScoped: false, scopeInvalidated: false, scopeName: "",
            selectionID: selection, nativeError: nil, nativeResultIDs: [], extensionActionIDs: [], extensionLaunchIDs: [],
            tabTokens: tabs ?? [tabToken()],
            historyTokens: history ?? [Skip.historyToken(url: "https://example.test", title: "Example")],
            commandTokens: [], spaceTokens: [], folderTokens: [], folderMoveIDs: [], favoriteActionID: nil,
            favoriteEligible: false, favoriteRenameID: nil, renameEligible: false, retainedBackgroundID: nil,
            retainedBackgroundRow: nil, supportsMuteAllTabs: false)
    }

    func extensionFingerprint(actionID: String) -> String {
        Skip.fingerprint(
            query: "q", actionsScope: false, websiteScoped: false, scopeInvalidated: false, scopeName: "",
            selectionID: nil, nativeError: nil, nativeResultIDs: ["native:false:https://a.test:A"],
            extensionActionIDs: [actionID], extensionLaunchIDs: [], tabTokens: [], historyTokens: [], commandTokens: [],
            spaceTokens: [], folderTokens: [], folderMoveIDs: [], favoriteActionID: nil, favoriteEligible: false,
            favoriteRenameID: nil, renameEligible: false, retainedBackgroundID: nil, retainedBackgroundRow: nil,
            supportsMuteAllTabs: false)
    }

    @Test func theFirstFingerprintNeverSkips() {
        #expect(!Skip.shouldSkip(previous: nil, next: "a"))
    }

    @Test func anIdenticalFingerprintSkips() {
        #expect(Skip.shouldSkip(previous: "a", next: "a"))
    }

    @Test func aChangedFingerprintDoesNotSkip() {
        #expect(!Skip.shouldSkip(previous: "a", next: "b"))
    }

    @Test func anIdenticalSidebarBrowsingTokenSkips() {
        #expect(Skip.shouldSkip(previous: Skip.sidebarBrowsingToken, next: Skip.sidebarBrowsingToken))
    }

    @Test func stableTabMembershipTokensMatch() {
        #expect(tabToken() == tabToken())
    }

    @Test func aTabTitleChangeAltersTheToken() {
        #expect(tabToken() != tabToken(title: "Changed"))
    }

    @Test func aCustomTitleAltersTheToken() {
        #expect(tabToken() != tabToken(customTitle: "Mine"))
    }

    @Test func aChangedSwitchToTabCaptionAltersTheToken() {
        #expect(tabToken(caption: "Switch to Tab") != tabToken(caption: "Work"))
    }

    @Test func stableHistoryMembershipTokensMatch() {
        #expect(Skip.historyToken(url: "https://example.test", title: "Example")
                == Skip.historyToken(url: "https://example.test", title: "Example"))
    }

    @Test func aHistoryTitleChangeAltersTheToken() {
        #expect(Skip.historyToken(url: "https://example.test", title: "Example")
                != Skip.historyToken(url: "https://example.test", title: "Changed"))
    }

    @Test func anIdenticalEmptyQueryFingerprintSkips() {
        let idle = fingerprint(query: "")
        #expect(Skip.shouldSkip(previous: idle, next: idle))
    }

    @Test func typingANewCharacterDoesNotSkip() {
        #expect(!Skip.shouldSkip(previous: fingerprint(query: ""), next: fingerprint(query: "a")))
    }

    @Test func aSelectionChangeDoesNotSkip() {
        #expect(!Skip.shouldSkip(previous: fingerprint(query: ""), next: fingerprint(query: "", selection: "tab:1")))
    }

    @Test func aTabMembershipChangeDoesNotSkip() {
        #expect(!Skip.shouldSkip(previous: fingerprint(query: ""), next: fingerprint(query: "", tabs: [tabToken(title: "Changed")])))
    }

    @Test func aHistoryMembershipChangeDoesNotSkip() {
        let changed = fingerprint(query: "", history: [Skip.historyToken(url: "https://example.test", title: "Changed")])
        #expect(!Skip.shouldSkip(previous: fingerprint(query: ""), next: changed))
    }

    @Test func unchangedTabMembershipRemainsATrueNoOp() {
        #expect(Skip.shouldSkip(previous: fingerprint(query: ""), next: fingerprint(query: "", tabs: [tabToken()])))
    }

    @Test func aStableExtensionActionIndexSkips() {
        let stable = extensionFingerprint(actionID: "extension:ext:edit:Title:0")
        #expect(Skip.shouldSkip(previous: stable, next: stable))
    }

    @Test func anExtensionActionResultIndexOnlyChangeDoesNotSkip() {
        #expect(!Skip.shouldSkip(previous: extensionFingerprint(actionID: "extension:ext:edit:Title:0"),
                                 next: extensionFingerprint(actionID: "extension:ext:edit:Title:2")))
    }
}
