import AppKit

@MainActor final class FakeOwner: BrowserScriptOwner {
    let scriptingID = UUID()
    var scriptingAvailable = true
    var scriptingIsIncognito = false
    var scriptingWindow: NSWindow? { nil }
    let profile = UUID(), otherProfile = UUID(), space = UUID()
    var scriptingTabs: [ScriptTabRecord] = []
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
    var scriptingSpaces: [ScriptSpaceRecord] { [ScriptSpaceRecord(id: space, profileID: profile, title: "Space")] }
    var scriptingActiveTabID: UUID? { scriptingTabs.first?.id }
    var scriptingActiveSpaceID: UUID { space }
    func scriptingTabs(in space: UUID, profile: UUID) -> [ScriptTabRecord] {
        guard self.space == space, self.profile == profile else { return [] }
        return scriptingTabs.filter { $0.profileID == profile }
    }
    func scriptingPerform(_ action: ScriptTabAction, tab: UUID, profile: UUID) throws { actions.append((action, tab, profile)) }
    func scriptingNavigate(_ url: URL, tab: UUID, profile: UUID) throws { navigations.append((url, tab, profile)) }
    func scriptingMakeTab(_ url: URL, space: UUID?, profile: UUID?) throws -> ScriptTabRecord {
        let record = ScriptTabRecord(id: UUID(), profileID: self.profile, title: "New", url: url.absoluteString, loading: false, location: "unpinned")
        scriptingTabs.append(record); return record
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

@MainActor final class ObservedCreateCommand: ParcCreateCommand {
    var suspensions = 0, resumptions = 0
    var result: Any?
    var properties: [String: Any] = ["mode": "incognito"]
    override var createClassDescription: NSScriptClassDescription {
        NSScriptSuiteRegistry.shared().classDescription(withAppleEventCode: 0x57694e44)!
    }
    override var resolvedKeyDictionary: [String: Any] { properties }
    override var evaluatedReceivers: Any? { nil }
    override func suspendExecution() { suspensions += 1 }
    override func resumeExecution(withResult result: Any?) { resumptions += 1; self.result = result }
}

@MainActor final class ScriptDelegateProbe: NSObject, NSApplicationDelegate, BrowserPrivateScriptFactory {
    var privateCreations = 0
    var privateReply: ((Result<ParcScriptWindow, Error>) -> Void)?
    func scriptingMakePrivateWindow(completion: @escaping (Result<ParcScriptWindow, Error>) -> Void) {
        privateCreations += 1; privateReply = completion
    }
    var owners = [FakeOwner()]
    var factories = 0, insertions = 0
    var readyOnCreation = true
    func application(_ sender: NSApplication, delegateHandlesKey key: String) -> Bool { key == "appleScriptWindows" }
    @objc dynamic var appleScriptWindows: [ParcScriptWindow] {
        get { owners.filter(\.scriptingAvailable).map { ParcScriptWindow(owner: $0) } }
        set {
            if acceptScriptInsertion(newValue, existing: appleScriptWindows, id: { $0.identifier },
                pending: { $0.isPendingInsertion }, owned: { wrapper in owners.contains { wrapper.belongs(to: $0) } },
                consume: { wrapper in
                    guard let owner = owners.first(where: { wrapper.belongs(to: $0) }) else { return false }
                    return wrapper.acceptInsertion(owner: owner)
                }) { insertions += 1 }
        }
    }
    override func newScriptingObject(of objectClass: AnyClass, forValueForKey key: String,
                                     withContentsValue contentsValue: Any?, properties: [String: Any]) -> Any? {
        guard objectClass == ParcScriptWindow.self, key == "appleScriptWindows" else { return nil }
        factories += 1
        let owner = FakeOwner(); owner.scriptingAvailable = readyOnCreation; owners.append(owner)
        return ParcScriptWindow(owner: owner, pendingInsertion: true)
    }
}

@main struct ScriptingChecks {
    @MainActor static func main() throws {
        var checks = 0
        func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
            precondition(condition(), message); checks += 1
        }
        expect(scriptWindowHasNormalOwner(origin: .application, context: .unavailable), "an app window showing the empty content or a blank tab retains its real app owner")
        expect(scriptWindowHasNormalOwner(origin: .application, context: .regular), "app window with regular contexts is exposed")
        expect(scriptWindowHasNormalOwner(origin: .nativeBrowser, context: .regular), "original native-created normal browser is exposed")
        expect(!scriptWindowHasNormalOwner(origin: .nativeBrowser, context: .unavailable), "native shell is unavailable before adoption or after drain")
        expect(!scriptWindowHasNormalOwner(origin: .auxiliary, context: .regular), "popup and auxiliary native owners stay outside browser-window collection")
        expect(!scriptWindowHasNormalOwner(origin: .offTheRecord, context: .regular), "private reservation cannot be relabeled from a later regular context")
        for origin: ScriptWindowOrigin in [.application, .nativeBrowser, .auxiliary, .offTheRecord] {
            expect(!scriptWindowHasNormalOwner(origin: origin, context: .offTheRecord), "actual private context is excluded")
            expect(!scriptWindowHasNormalOwner(origin: origin, context: .mixed), "mixed original contexts cannot be exposed as normal")
        }
        let app = NSApplication.shared
        let delegate = ScriptDelegateProbe()
        app.delegate = delegate
        _ = NSScriptSuiteRegistry.shared()
        expect((app.value(forKey: "appleScriptWindows") as? [ParcScriptWindow])?.count == 1, "application delegates scripting collection getter")
        let applicationMade = app.newScriptingObject(of: ParcScriptWindow.self, forValueForKey: "appleScriptWindows", withContentsValue: nil, properties: [:])
        expect(delegate.factories == 1 && applicationMade is ParcScriptWindow, "application delegates scripting creation to collection owner")
        app.insertValue(applicationMade!, at: 0, inPropertyWithKey: "appleScriptWindows")
        expect(delegate.insertions == 1 && delegate.owners.count == 2, "post-factory getter plus Cocoa insertion leaves one actual new window")
        app.insertValue(applicationMade!, at: 0, inPropertyWithKey: "appleScriptWindows")
        expect(delegate.insertions == 1 && delegate.owners.count == 2, "issued window token can only be acknowledged once")
        app.setValue(Array(delegate.appleScriptWindows.reversed()), forKey: "appleScriptWindows")
        expect(delegate.insertions == 1, "arbitrary collection replacement cannot reorder windows")
        delegate.readyOnCreation = false
        let openingWindow = app.newScriptingObject(of: ParcScriptWindow.self, forValueForKey: "appleScriptWindows", withContentsValue: nil, properties: [:])!
        app.insertValue(openingWindow, at: 0, inPropertyWithKey: "appleScriptWindows")
        expect(delegate.insertions == 2 && delegate.owners.count == 3, "already-created opening window is acknowledged before native readiness")
        expect((try? scriptWindowCreationIsIncognito([:])) == false, "default creation remains normal")
        expect((try? scriptWindowCreationIsIncognito(["isIncognito": true])) == true, "native Boolean requests private mode")
        expect((try? scriptWindowCreationIsIncognito(["mode": "incognito"])) == true, "mode requests private context")
        expect((try? scriptWindowCreationIsIncognito(["mode": "normal", "isIncognito": true])) == nil, "conflicting modes have no creation side effect")
        expect((try? scriptWindowCreationIsIncognito(["isIncognito": 2])) == nil, "integer is not an incognito Boolean")
        expect((try? scriptWindowCreationIsIncognito(["title": "Spoof"])) == nil, "unimplemented creation attributes are refused")
        var creationResults = 0
        let pending = PendingBrowserCreation<Int> { _ in creationResults += 1 }
        expect(pending.isPending, "new asynchronous creation is initially owned")
        pending.finish(.failure(BrowserScriptError.cancelled))
        expect(!pending.isPending && creationResults == 1, "application termination cancels pending factory")
        pending.finish(.success(1))
        expect(creationResults == 1, "late profile readiness cannot complete cancelled creation again")
        let createDescription = NSScriptSuiteRegistry.shared().commandDescription(withAppleEventClass: 0x636f7265, andAppleEventCode: 0x6372656c)!
        let create = ObservedCreateCommand(commandDescription: createDescription)
        _ = create.performDefaultImplementation()
        expect(create.suspensions == 1 && create.resumptions == 0 && delegate.privateCreations == 1, "private make suspends before asynchronous original-profile preparation")
        let privateOwner = FakeOwner(); privateOwner.scriptingIsIncognito = true
        let privateWindow = ParcScriptWindow(owner: privateOwner)
        delegate.privateReply?(.success(privateWindow))
        delegate.privateReply?(.failure(BrowserScriptError.missing))
        expect(create.resumptions == 1 && create.result as? ParcScriptWindow === privateWindow, "private make returns the original created wrapper exactly once")
        expect(privateWindow.mode == "incognito" && privateWindow.isIncognito, "private properties derive actual owner")
        expect(privateWindow.identifier == privateOwner.scriptingID.uuidString, "private window preserves original stable identity")
        let rejected = ObservedCreateCommand(commandDescription: createDescription)
        _ = rejected.performDefaultImplementation(); delegate.privateReply?(.failure(BrowserScriptError.missing))
        expect(rejected.resumptions == 1 && rejected.scriptErrorNumber == -1728 && rejected.result == nil, "profile loss fails the suspended factory without a stand-in object")
        let malformed = ObservedCreateCommand(commandDescription: createDescription)
        malformed.properties = ["mode": "incognito", "isIncognito": false]
        _ = malformed.performDefaultImplementation()
        expect(malformed.suspensions == 0 && delegate.privateCreations == 2 && malformed.scriptErrorNumber != 0, "malformed request never starts profile creation")
        privateOwner.scriptingAvailable = false
        expect(privateWindow.mode.isEmpty && privateWindow.appleScriptTabs.isEmpty, "retired private owner cannot resolve through a normal window")
        let description = NSScriptSuiteRegistry.shared().commandDescription(withAppleEventClass: 0x636f7265, andAppleEventCode: 0x636c6f73)!
        let command = ObservedCommand(commandDescription: description)
        let owner = FakeOwner()
        let record = ScriptTabRecord(id: UUID(), profileID: owner.profile, title: "Original", url: "https://example.test/page", loading: true, location: "pinned")
        owner.scriptingTabs = [record]
        let window = ParcScriptWindow(owner: owner)
        let tab = window.appleScriptTabs[0]
        expect(tab.value(forKey: "id") as? String == record.id.uuidString, "KVC stable tab id")
        expect(tab.title == "Original" && tab.loading && tab.location == "pinned", "actual snapshot properties")
        expect(window.activeTab?.identifier == record.id.uuidString, "active tab identity")
        expect(window.activeSpace?.identifier == owner.space.uuidString, "active Space identity")
        expect(window.objectSpecifier is NSUniqueIDSpecifier, "window unique-id specifier")
        expect(tab.objectSpecifier?.container is NSUniqueIDSpecifier, "tab retains window container")
        expect(window.appleScriptSpaces[0].objectSpecifier is NSUniqueIDSpecifier, "Space unique-id specifier")
        tab.select(command); tab.goBack(command); tab.goForward(command); tab.reload(command); tab.stopLoading(command)
        expect(owner.actions.count == 5 && owner.actions.allSatisfy { $0.1 == record.id && $0.2 == owner.profile }, "commands target original identity")
        tab.URL = "https://example.test/next"
        expect(owner.navigations.count == 1 && owner.navigations[0].1 == record.id, "URL assignment stays on original tab")
        tab.URL = "javascript:document.title"
        expect(owner.navigations.count == 1, "URL cannot bypass JavaScript gate")
        tab.URL = "not a URL"
        expect(owner.navigations.count == 1, "relative address is not a search")
        tab.close(command)
        expect(command.suspensions == 1 && command.resumptions == 0, "close suspends until native outcome")
        owner.closeCallback?(false); owner.closeCallback = nil
        expect(command.resumptions == 1 && command.scriptErrorNumber == -128, "denied close replies as cancellation")
        let immediate = ObservedCommand(commandDescription: description)
        owner.immediateClose = true; window.close(immediate)
        expect(immediate.suspensions == 1 && immediate.resumptions == 1, "synchronous local close is balanced")
        owner.immediateClose = nil
        let count = owner.scriptingTabs.count
        let made = window.newScriptingObject(of: ParcScriptTab.self, forValueForKey: "appleScriptTabs", withContentsValue: nil, properties: ["URL": "https://example.test/new"]) as! ParcScriptTab
        expect(owner.scriptingTabs.count == count + 1, "factory creates one actual tab")
        window.insertValue(made, at: 0, inPropertyWithKey: "appleScriptTabs")
        expect(owner.scriptingTabs.count == count + 1, "Cocoa insertion does not create a duplicate")
        expect(!made.acceptInsertion(in: owner.scriptingID), "factory insertion token is single use")
        let invalid = window.newScriptingObject(of: ParcScriptTab.self, forValueForKey: "appleScriptTabs", withContentsValue: nil, properties: [:])
        expect(invalid == nil && owner.scriptingTabs.count == count + 1, "missing URL has no side effect")
        let space = window.appleScriptSpaces[0]
        space.focus(command)
        expect(owner.focused == owner.space, "Space focus uses original identity")
        let inSpace = space.newScriptingObject(of: ParcScriptTab.self, forValueForKey: "appleScriptTabs", withContentsValue: nil, properties: ["URL": "https://example.test/in-space"]) as! ParcScriptTab
        space.insertValue(inSpace, at: 0, inPropertyWithKey: "appleScriptTabs")
        expect(space.appleScriptTabs.count == count + 2, "Space creation uses actual container")
        let executeDescription = NSScriptSuiteRegistry.shared().commandDescription(withAppleEventClass: 0x43725375, andAppleEventCode: 0x45784a61)!
        func execution(_ parameters: [String: Any]? = ["javascript": "document.title"]) -> ObservedCommand {
            let value = ObservedCommand(commandDescription: executeDescription); value.parameters = parameters; return value
        }
        let js = execution(); tab.executeJavascript(js)
        expect(js.suspensions == 1 && js.resumptions == 0, "execute suspends for the actual completion")
        expect(owner.javascriptRequests.last?.0 == "document.title" && owner.javascriptRequests.last?.1 == record.id && owner.javascriptRequests.last?.2 == owner.profile, "code dispatch retains exact original tab/profile")
        let completion = owner.javascriptCallback!; owner.javascriptCallback = nil
        completion(.success("\"title\"")); completion(.success("ignored"))
        expect(js.resumptions == 1 && js.result as? String == "\"title\"", "JSON string text preserved and completion is single use")
        let denied = execution(); tab.executeJavascript(denied)
        owner.javascriptCallback?(.failure(BrowserScriptError.execution("Permission is disabled", -1743))); owner.javascriptCallback = nil
        expect(denied.resumptions == 1 && denied.scriptErrorNumber == -1743 && denied.result == nil, "permission denial balances suspension with exact error")
        let timeout = execution(); tab.executeJavascript(timeout)
        owner.javascriptCallback?(.failure(BrowserScriptError.execution("Timeout", -1712))); owner.javascriptCallback = nil
        expect(timeout.resumptions == 1 && timeout.scriptErrorNumber == -1712, "native timeout reaches scripting client")
        let cancelledJS = execution(); tab.executeJavascript(cancelledJS)
        owner.javascriptCallback?(.failure(BrowserScriptError.execution("Cancelled", -128))); owner.javascriptCallback = nil
        expect(cancelledJS.resumptions == 1 && cancelledJS.scriptErrorNumber == -128, "native cancellation reaches scripting client")
        owner.immediateJavaScript = .success("{\"items\":[1,true,null]}")
        let immediateJS = execution(); tab.executeJavascript(immediateJS)
        expect(immediateJS.suspensions == 1 && immediateJS.resumptions == 1 && immediateJS.result as? String == "{\"items\":[1,true,null]}", "synchronous owner result preserves JSON and balances suspension")
        expect(owner.cancellations == 1, "already completed request does not retain a subsequently issued lease")
        owner.immediateJavaScript = .success(nil)
        let absentJS = execution(); tab.executeJavascript(absentJS)
        expect(absentJS.resumptions == 1 && absentJS.result == nil && absentJS.scriptErrorNumber == 0, "optional absent result stays absent")
        owner.immediateJavaScript = nil; owner.javascriptThrows = BrowserScriptError.busy
        let throwsJS = execution(); tab.executeJavascript(throwsJS)
        expect(throwsJS.suspensions == 1 && throwsJS.resumptions == 1 && throwsJS.scriptErrorNumber == -10000, "dispatch refusal resumes suspended command")
        owner.javascriptThrows = nil
        let badJS = execution(["javascript": 4]); tab.executeJavascript(badJS)
        expect(badJS.suspensions == 0 && badJS.scriptErrorNumber == -1700, "nontext parameter rejected before suspension")
        let staleJS = execution(); tab.executeJavascript(staleJS)
        owner.scriptingAvailable = false
        owner.javascriptCallback?(.success("42")); owner.javascriptCallback = nil
        expect(staleJS.resumptions == 1 && staleJS.scriptErrorNumber == -1728 && staleJS.result == nil, "late result cannot escape stale original owner")
        owner.scriptingAvailable = true
        owner.scriptingTabs[0] = ScriptTabRecord(id: record.id, profileID: owner.otherProfile, title: "Different", url: "https://other.test", loading: false, location: "unpinned")
        tab.select(command); tab.URL = "https://example.test/reject"
        expect(owner.actions.count == 5 && owner.navigations.count == 1, "profile change invalidates old tab wrapper")
        owner.scriptingAvailable = false
        space.focus(command); window.close(command)
        expect(command.suspensions == 1, "stale window cannot start close")
        expect(window.appleScriptTabs.isEmpty, "unavailable original owner has no objects")
        expect(window.mode.isEmpty, "retired or no-longer-normal owner is not reported as normal")
        expect((try? BrowserScriptError.url("https:///")) == nil, "network URLs need host")
        expect((try? BrowserScriptError.url("parc://easel/test")) == nil, "no unimplemented local document conversion")
        print("\(checks) scripting component assertions passed; no browser or Apple Event dispatch.")
    }
}
