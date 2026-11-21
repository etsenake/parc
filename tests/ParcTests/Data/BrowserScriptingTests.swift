import AppKit
import Testing
@testable import Parc

struct BrowserScriptingTests {
    @MainActor final class Owner: BrowserScriptOwner {
        let scriptingID = UUID()
        var scriptingAvailable = true
        var scriptingIsIncognito = false
        var scriptingWindow: NSWindow? { nil }
        let profile = UUID(), otherProfile = UUID(), space = UUID()
        var tabs: [ScriptTabRecord] = []
        var listPasses = 0, tabLookups = 0
        var scriptingTabs: [ScriptTabRecord] { listPasses += 1; return tabs }
        func scriptingTabRecord(_ id: UUID, profile: UUID?) -> ScriptTabRecord? {
            tabLookups += 1
            return tabs.first { $0.id == id && (profile == nil || $0.profileID == profile) }
        }
        var actions: [(ScriptTabAction, UUID, UUID)] = []
        var navigations: [(URL, UUID, UUID)] = []
        var javascriptCallback: ((Result<String?, Error>) -> Void)?
        var javascriptRequests: [(String, UUID, UUID)] = []
        var immediateJavaScript: Result<String?, Error>?
        var javascriptThrows: Error?
        var cancellations = 0
        func scriptingExecuteJavaScript(_ script: String, tab: UUID, profile: UUID,
            completion: @escaping (Result<String?, Error>) -> Void) throws -> () -> Void {
            if let javascriptThrows { throw javascriptThrows }
            javascriptRequests.append((script, tab, profile))
            if let immediateJavaScript { completion(immediateJavaScript) } else { javascriptCallback = completion }
            return { [weak self] in self?.cancellations += 1 }
        }
        var closeCallback: ((Bool) -> Void)?
        var immediateClose: Bool?
        var focused: UUID?
        var extraSpaces: [ScriptSpaceRecord] = []
        var scriptingSpaces: [ScriptSpaceRecord] { [ScriptSpaceRecord(id: space, profileID: profile, title: "Space")] + extraSpaces }
        var activeTabID: UUID?
        var scriptingActiveTabID: UUID? { activeTabID ?? tabs.first?.id }
        var scriptingActiveSpaceID: UUID { space }
        func scriptingTabs(in space: UUID, profile: UUID) -> [ScriptTabRecord] {
            listPasses += 1
            guard self.space == space, self.profile == profile else { return [] }
            return tabs.filter { $0.profileID == profile }
        }
        func scriptingTabRecord(_ id: UUID, inSpace space: UUID, profile: UUID) -> ScriptTabRecord? {
            tabLookups += 1
            guard self.space == space, self.profile == profile else { return nil }
            return tabs.first { $0.id == id && $0.profileID == profile }
        }
        func scriptingPerform(_ action: ScriptTabAction, tab: UUID, profile: UUID) throws { actions.append((action, tab, profile)) }
        func scriptingNavigate(_ url: URL, tab: UUID, profile: UUID) throws { navigations.append((url, tab, profile)) }
        func scriptingMakeTab(_ url: URL, space: UUID?, profile: UUID?) throws -> ScriptTabRecord {
            let record = ScriptTabRecord(id: UUID(), profileID: self.profile, title: "New", url: url.absoluteString, loading: false, location: "unpinned")
            tabs.append(record); return record
        }
        func scriptingFocus(space: UUID, profile: UUID) throws { focused = space }
        func scriptingClose(tab: UUID?, profile: UUID?, completion: @escaping (Bool) -> Void) throws {
            if let immediateClose { completion(immediateClose) } else { closeCallback = completion }
        }
    }
    final class ObservedCommand: NSScriptCommand {
        var suspensions = 0, resumptions = 0
        var result: Any?
        var parameters: [String: Any]?
        override var evaluatedArguments: [String: Any]? { parameters }
        override func suspendExecution() { suspensions += 1 }
        override func resumeExecution(withResult result: Any?) { resumptions += 1; self.result = result }
    }

    @Test(arguments: [(ScriptWindowOrigin.application, ScriptWindowContext.unavailable, true),
                      (.application, .regular, true), (.nativeBrowser, .regular, true),
                      (.nativeBrowser, .unavailable, false), (.auxiliary, .regular, false),
                      (.offTheRecord, .regular, false), (.application, .offTheRecord, false),
                      (.application, .mixed, false), (.nativeBrowser, .offTheRecord, false),
                      (.nativeBrowser, .mixed, false), (.auxiliary, .offTheRecord, false),
                      (.auxiliary, .mixed, false), (.offTheRecord, .offTheRecord, false),
                      (.offTheRecord, .mixed, false)])
    func onlyOriginalNormalBrowserOwnersAreListed(_ origin: ScriptWindowOrigin, _ context: ScriptWindowContext, _ listed: Bool) {
        #expect(scriptWindowHasNormalOwner(origin: origin, context: context) == listed)
    }

    enum Creation: CaseIterable {
        case normal, incognitoMode, incognitoFlag, conflicting, numericFlag, unknownProperty

        var properties: [String: Any] {
            switch self {
            case .normal: [:]
            case .incognitoMode: ["mode": "incognito"]
            case .incognitoFlag: ["isIncognito": true]
            case .conflicting: ["mode": "normal", "isIncognito": true]
            case .numericFlag: ["isIncognito": 2]
            case .unknownProperty: ["title": "Spoof"]
            }
        }

        var incognito: Bool? {
            switch self {
            case .normal: false
            case .incognitoMode, .incognitoFlag: true
            default: nil
            }
        }
    }

    @Test(arguments: Creation.allCases)
    func theWindowModeRequiresAConsistentBooleanOrModeName(_ input: Creation) {
        #expect((try? scriptWindowCreationIsIncognito(input.properties)) == input.incognito)
    }

    @MainActor @Test func aPendingWindowFactoryCompletesOnlyOnceAfterCancellation() {
        var results: [Result<Int, Error>] = []
        let pending = PendingBrowserCreation<Int> { results.append($0) }

        pending.finish(.failure(BrowserScriptError.cancelled))
        pending.finish(.success(1))

        #expect(!pending.isPending)
        #expect(results.count == 1)
        #expect((try? results.first?.get()) == nil)
    }

    @MainActor
    private func ownerWithTab() -> Owner {
        let owner = Owner()
        owner.tabs = [.init(id: UUID(), profileID: owner.profile, title: "Original",
                            url: "https://example.test/page", loading: true, location: "pinned")]
        return owner
    }

    @MainActor @Test func theActiveTabReportsItsCurrentProperties() throws {
        let owner = ownerWithTab()
        let window = ParcScriptWindow(owner: owner)
        let tab = try #require(window.activeTab)
        #expect(tab.value(forKey: "id") as? String == owner.tabs[0].id.uuidString)
        #expect(tab.title == "Original")
        #expect(tab.URL == "https://example.test/page")
        #expect(tab.loading)
        #expect(tab.location == "pinned")
    }

    @MainActor @Test(arguments: [false, true])
    func aUniqueIDLookupThroughTheWindowOrSpaceDoesNotListTabs(_ inSpace: Bool) throws {
        let owner = ownerWithTab()
        let window = ParcScriptWindow(owner: owner)
        let id = owner.tabs[0].id.uuidString.lowercased()
        let resolved: ParcScriptTab?
        if inSpace {
            let space = try #require(window.activeSpace)
            resolved = space.valueInAppleScriptTabs(withUniqueID: id)
        } else {
            resolved = window.valueInAppleScriptTabs(withUniqueID: id)
        }

        #expect(resolved?.identifier == owner.tabs[0].id.uuidString)
        #expect(owner.tabLookups == 1)
        #expect(owner.listPasses == 0)
    }

    @MainActor @Test func aTabWrapperNoLongerNavigatesAfterTheTabChangesProfiles() throws {
        let owner = ownerWithTab()
        let window = ParcScriptWindow(owner: owner)
        let tab = try #require(window.activeTab)
        owner.tabs[0] = .init(id: owner.tabs[0].id, profileID: owner.otherProfile,
                              title: "Different", url: "https://other.test", loading: false, location: "unpinned")

        tab.URL = "https://example.test/next"

        #expect(owner.navigations.isEmpty)
        #expect(tab.title.isEmpty)
    }

    @MainActor @Test(arguments: [("https://example.test/next", true), ("javascript:document.title", false),
                                 ("not a URL", false), ("https:///", false), ("parc://easel/test", false)])
    func anAssignedURLMustBeAnExplicitNavigableAddress(_ url: String, _ valid: Bool) throws {
        let owner = ownerWithTab()
        let window = ParcScriptWindow(owner: owner)
        let tab = try #require(window.activeTab)

        tab.URL = url

        #expect(owner.navigations.map { $0.0.absoluteString } == (valid ? [url] : []))
        #expect(owner.navigations.allSatisfy { $0.1 == owner.tabs[0].id && $0.2 == owner.profile })
    }

    @MainActor @Test func tabCreationAcknowledgementNeverCreatesAnExtraTab() throws {
        let owner = ownerWithTab()
        let window = ParcScriptWindow(owner: owner)
        let created = try #require(window.newScriptingObject(of: ParcScriptTab.self, forValueForKey: "appleScriptTabs",
            withContentsValue: nil, properties: ["URL": "https://example.test/new"]) as? ParcScriptTab)

        window.insertValue(created, at: 0, inPropertyWithKey: "appleScriptTabs")

        #expect(owner.tabs.count == 2)
        #expect(!created.acceptInsertion(in: owner.scriptingID))
    }

    @MainActor @Test func anIncognitoWindowUsesOnlyItsOriginalOwnerIdentity() {
        let owner = Owner()
        owner.scriptingIsIncognito = true
        let window = ParcScriptWindow(owner: owner)

        #expect(window.mode == "incognito")
        #expect(window.isIncognito)
        #expect(window.identifier == owner.scriptingID.uuidString)
    }

    @MainActor @Test func aRetiredWindowHasNoResolvableTabsOrMode() {
        let owner = ownerWithTab()
        let window = ParcScriptWindow(owner: owner)
        owner.scriptingAvailable = false

        #expect(window.mode.isEmpty)
        #expect(window.appleScriptTabs.isEmpty)
    }

    @MainActor
    private func command(arguments: [String: Any]? = nil) throws -> ObservedCommand {
        let description = try #require(NSScriptCommandDescription(suiteName: "ParcComponentTests",
            commandName: "componentCommand", dictionary: [
                "AppleEventCode": "comp",
                "CommandClass": NSStringFromClass(NSScriptCommand.self),
            ]))
        let probe = ObservedCommand(commandDescription: description)
        probe.parameters = arguments
        return probe
    }

    @MainActor @Test(arguments: [ScriptTabAction.select, .back, .forward, .reload, .stop])
    func scriptCommandsActOnTheOriginalTabAndProfile(_ action: ScriptTabAction) throws {
        let owner = ownerWithTab()
        let window = ParcScriptWindow(owner: owner)
        let tab = try #require(window.activeTab)
        let command = try command()

        switch action {
        case .select: tab.select(command)
        case .back: tab.goBack(command)
        case .forward: tab.goForward(command)
        case .reload: tab.reload(command)
        case .stop: tab.stopLoading(command)
        }

        #expect(owner.actions.count == 1)
        let performed = try #require(owner.actions.first)
        #expect(performed.0 == action)
        #expect(performed.1 == owner.tabs[0].id)
        #expect(performed.2 == owner.profile)
    }

    @MainActor @Test func refusingAnAsynchronousCloseResumesTheCommandAsCancelled() throws {
        let owner = ownerWithTab()
        let window = ParcScriptWindow(owner: owner)
        let tab = try #require(window.activeTab)
        let command = try command()
        tab.close(command)
        #expect(command.suspensions == 1)
        #expect(command.resumptions == 0)

        let complete = try #require(owner.closeCallback)
        complete(false)

        #expect(command.resumptions == 1)
        #expect(command.scriptErrorNumber == -128)
    }

    @MainActor @Test func javascriptReturnsTheOriginalJSONOnlyOnce() throws {
        let owner = ownerWithTab()
        let window = ParcScriptWindow(owner: owner)
        let tab = try #require(window.activeTab)
        let command = try command(arguments: ["javascript": "document.title"])
        tab.executeJavascript(command)
        let request = try #require(owner.javascriptRequests.first)
        #expect(request.0 == "document.title")
        #expect(request.1 == owner.tabs[0].id)
        #expect(request.2 == owner.profile)
        let complete = try #require(owner.javascriptCallback)

        complete(.success("\"title\""))
        complete(.success("late"))

        #expect(command.suspensions == 1)
        #expect(command.resumptions == 1)
        #expect(command.result as? String == "\"title\"")
    }

    @MainActor @Test(arguments: [-1743, -1712, -128])
    func javascriptForwardsTheOriginalFailureCode(_ code: Int) throws {
        let owner = ownerWithTab()
        let window = ParcScriptWindow(owner: owner)
        let tab = try #require(window.activeTab)
        let command = try command(arguments: ["javascript": "document.title"])
        tab.executeJavascript(command)
        let complete = try #require(owner.javascriptCallback)

        complete(.failure(BrowserScriptError.execution("Fixture refusal", code)))

        #expect(command.resumptions == 1)
        #expect(command.scriptErrorNumber == code)
        #expect(command.result == nil)
    }
}
