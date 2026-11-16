import AppKit

@MainActor final class FakeOwner: BrowserScriptOwner {
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
    @MainActor static func main() { exitOnFailure(runChecks) }
    @MainActor static func runChecks() throws {
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
        let alpha = BrowserProfile(id: UUID(), name: "Alpha"), leaving = BrowserProfile(id: UUID(), name: "Leaving")
        let beta = BrowserProfile(id: UUID(), name: "Beta")
        let home = BrowserSpace(id: UUID(), name: "Home", symbol: "circle", color: "ABCDEF", profileID: alpha.id)
        let office = BrowserSpace(id: UUID(), name: "Work", symbol: "circle", color: "ABCDEF", profileID: alpha.id)
        let away = BrowserSpace(id: UUID(), name: "Away", symbol: "circle", color: "ABCDEF", profileID: leaving.id)
        let lab = BrowserSpace(id: UUID(), name: "Lab", symbol: "circle", color: "ABCDEF", profileID: beta.id)
        let gone = UUID()
        var distinct = BrowserState(profiles: [alpha, leaving, beta], spaces: [home, office, away, lab], activeSpaceID: home.id)
        distinct.profileRemovals = [ProfileRemovalRecord(id: UUID(), profileID: leaving.id, profileName: "Leaving", fallbackProfileID: alpha.id)]
        distinct.tabs = (0..<60).map { index in
            let space = [home.id, office.id, away.id, gone, lab.id][index % 5]
            let profile = index % 5 == 4 ? beta.id : index % 7 == 0 || index % 5 == 2 ? leaving.id : alpha.id
            var tab = BrowserTab(id: UUID(), spaceID: space, profileID: profile, url: "https://model.test/\(index)", title: "Model \(index)",
                kind: TabKind.allCases[index % 3], folderID: nil, createdAt: Date(timeIntervalSince1970: Double(index)),
                lastAccessed: Date(timeIntervalSince1970: Double(index)), savedURL: "https://model.test/\(index)", savedTitle: "Model \(index)")
            if index % 6 == 5 { tab.archivedAt = Date(timeIntervalSince1970: 1_000) }
            return tab
        }
        let shared = distinct.tabs[1], doubled = distinct.tabs[16], crossed = distinct.tabs[31]
        var archivedTwin = shared
        archivedTwin.spaceID = home.id; archivedTwin.kind = .today; archivedTwin.archivedAt = Date(timeIntervalSince1970: 2_000)
        var openTwin = doubled
        openTwin.spaceID = home.id; openTwin.kind = .today
        var profileTwin = crossed
        profileTwin.spaceID = lab.id; profileTwin.profileID = beta.id
        var model = distinct
        model.tabs.insert(archivedTwin, at: 0)
        model.tabs.insert(profileTwin, at: 1)
        model.tabs.append(openTwin)
        let blocked: Set<UUID> = [distinct.tabs[6].id, distinct.tabs[26].id]
        let usable: (BrowserTab) -> Bool = { !blocked.contains($0.id) }
        let probeIDs = model.tabs.map(\.id) + [UUID(), UUID()]
        expect(distinct.attachingTabLookup(after: nil).tabLookup.lookup?.match(crossed.id, in: distinct.tabs) == .found(31)
            && distinct.attachingTabLookup(after: nil).tabLookup.lookup?.match(UUID(), in: distinct.tabs) == .absent
            && model.attachingTabLookup(after: nil).tabLookup.lookup?.match(crossed.id, in: model.tabs) == .ambiguous,
            "the model states reach the index's found, absent and repeated-identity paths")
        for (state, twins) in [(distinct, false), (distinct.attachingTabLookup(after: nil), false), (model, true), (model.attachingTabLookup(after: nil), true)] {
            let listed = state.tabs.filter { tab in
                tab.archivedAt == nil && !state.profileRemovals.contains { $0.profileID == tab.profileID } && usable(tab)
                    && state.spaces.contains { $0.id == tab.spaceID && $0.profileID == tab.profileID }
            }
            expect(Set(listed.map(\.profileID)) == [alpha.id, beta.id] && listed.contains { $0.id == shared.id } && listed.contains { $0.id == doubled.id }
                && listed.contains { $0.id == crossed.id }, "the model lists tabs from two profiles, including every twinned tab")
            expect(state.scriptListedTabs(where: usable) == listed, "the window's tab list keeps the old filter and order")
            expect(probeIDs.allSatisfy { id in [nil, alpha.id, leaving.id, beta.id].allSatisfy { profile in
                state.scriptListedTab(id, profile: profile, where: usable) == listed.first { $0.id == id && (profile == nil || $0.profileID == profile) }
            } }, "a single tab lookup finds what the old list's first match found")
            expect([home.id, office.id, away.id, lab.id, gone].allSatisfy { space in [alpha.id, leaving.id, beta.id].allSatisfy { profile in
                let members = Set(state.tabs.filter { $0.profileID == profile && ($0.spaceID == space || $0.kind == .favorite) }.map(\.id))
                return state.scriptListedTabs(inSpace: space, profile: profile, where: usable) == listed.filter { members.contains($0.id) }
            } }, "a Space's tab list keeps the old membership rule and order")
            expect(probeIDs.allSatisfy { id in [home.id, office.id, away.id, lab.id, gone].allSatisfy { space in [alpha.id, leaving.id, beta.id].allSatisfy { profile in
                state.scriptListedTab(id, inSpace: space, profile: profile, where: usable)
                    == state.scriptListedTabs(inSpace: space, profile: profile, where: usable).first { $0.id == id }
            } } }, "a tab named inside a Space is the Space list's first match, found without listing it")
            guard twins else { continue }
            let homeTabs = state.scriptListedTabs(inSpace: home.id, profile: alpha.id, where: usable)
            expect(homeTabs.contains { $0.id == shared.id && $0.spaceID == office.id } && homeTabs.filter { $0.id == doubled.id }.count == 2,
                "a Space keeps listing tabs that share an identity with one of its own, as before")
            expect(state.scriptListedTab(crossed.id, profile: nil, where: usable)?.profileID == beta.id
                && state.scriptListedTab(crossed.id, profile: alpha.id, where: usable) == crossed,
                "a profile-bound lookup skips an earlier tab from another profile with the same identity")
            expect(state.scriptListedTab(shared.id, inSpace: home.id, profile: alpha.id, where: usable)?.spaceID == office.id
                && state.scriptListedTab(crossed.id, inSpace: office.id, profile: alpha.id, where: usable)?.profileID == beta.id
                && state.scriptListedTab(distinct.tabs[46].id, inSpace: office.id, profile: alpha.id, where: usable) == distinct.tabs[46]
                && state.scriptListedTab(distinct.tabs[46].id, inSpace: home.id, profile: alpha.id, where: usable) == nil,
                "a tab named inside a Space keeps the list's identity rule, its first match and its absences")
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
        owner.tabs = [record]
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
        let count = owner.tabs.count
        let made = window.newScriptingObject(of: ParcScriptTab.self, forValueForKey: "appleScriptTabs", withContentsValue: nil, properties: ["URL": "https://example.test/new"]) as! ParcScriptTab
        expect(owner.tabs.count == count + 1, "factory creates one actual tab")
        window.insertValue(made, at: 0, inPropertyWithKey: "appleScriptTabs")
        expect(owner.tabs.count == count + 1, "Cocoa insertion does not create a duplicate")
        expect(!made.acceptInsertion(in: owner.scriptingID), "factory insertion token is single use")
        let invalid = window.newScriptingObject(of: ParcScriptTab.self, forValueForKey: "appleScriptTabs", withContentsValue: nil, properties: [:])
        expect(invalid == nil && owner.tabs.count == count + 1, "missing URL has no side effect")
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
        owner.tabs[0] = ScriptTabRecord(id: record.id, profileID: owner.otherProfile, title: "Different", url: "https://other.test", loading: false, location: "unpinned")
        tab.select(command); tab.URL = "https://example.test/reject"
        expect(owner.actions.count == 5 && owner.navigations.count == 1, "profile change invalidates old tab wrapper")
        owner.scriptingAvailable = false
        space.focus(command); window.close(command)
        expect(command.suspensions == 1, "stale window cannot start close")
        expect(window.appleScriptTabs.isEmpty, "unavailable original owner has no objects")
        expect(window.mode.isEmpty, "retired or no-longer-normal owner is not reported as normal")
        expect((try? BrowserScriptError.url("https:///")) == nil, "network URLs need host")
        expect((try? BrowserScriptError.url("parc://easel/test")) == nil, "no unimplemented local document conversion")
        func fourCharacterCode(_ text: String) -> FourCharCode { text.utf8.reduce(0) { ($0 << 8) | FourCharCode($1) } }
        func reference(_ want: String, _ form: String, _ data: NSAppleEventDescriptor, in container: NSAppleEventDescriptor) -> NSAppleEventDescriptor {
            let record = NSAppleEventDescriptor.record()
            record.setDescriptor(NSAppleEventDescriptor(typeCode: fourCharacterCode(want)), forKeyword: fourCharacterCode("want"))
            record.setDescriptor(NSAppleEventDescriptor(enumCode: fourCharacterCode(form)), forKeyword: fourCharacterCode("form"))
            record.setDescriptor(data, forKeyword: fourCharacterCode("seld"))
            record.setDescriptor(container, forKeyword: fourCharacterCode("from"))
            return record.coerce(toDescriptorType: fourCharacterCode("obj "))!
        }
        func property(_ code: String, of container: NSAppleEventDescriptor) -> NSAppleEventDescriptor {
            reference("prop", "prop", NSAppleEventDescriptor(typeCode: fourCharacterCode(code)), in: container)
        }
        func perform(_ event: String, on receiver: NSAppleEventDescriptor) -> Any? {
            let command = NSScriptSuiteRegistry.shared().commandDescription(withAppleEventClass: fourCharacterCode(String(event.prefix(4))),
                andAppleEventCode: fourCharacterCode(String(event.suffix(4))))!.createCommandInstance()
            command.receiversSpecifier = NSScriptObjectSpecifier(descriptor: receiver)
            return command.execute()
        }
        func field(_ record: NSAppleEventDescriptor?, _ code: String) -> NSAppleEventDescriptor? { record?.forKeyword(fourCharacterCode(code)) }
        let listed = FakeOwner()
        let work = ScriptSpaceRecord(id: UUID(), profileID: listed.profile, title: "Work")
        listed.extraSpaces = [work]
        let docs = ScriptTabRecord(id: UUID(), profileID: listed.profile, title: "Docs", url: "https://example.test/docs", loading: true, location: "pinned")
        let news = ScriptTabRecord(id: UUID(), profileID: listed.profile, title: "News", url: "https://example.test/news", loading: false, location: "topApp")
        listed.tabs = [docs, news]
        delegate.owners.append(listed)
        let listedWindow = reference("WiND", "ID  ", NSAppleEventDescriptor(string: listed.scriptingID.uuidString), in: .null())
        var all = fourCharacterCode("all ")
        let everyTab = reference("tAbB", "indx", NSAppleEventDescriptor(descriptorType: fourCharacterCode("abso"), bytes: &all, length: 4)!, in: listedWindow)
        let everyRecord = perform("coregetd", on: property("pALL", of: everyTab)) as? NSAppleEventDescriptor
        let docsRecord = everyRecord?.atIndex(1), newsRecord = everyRecord?.atIndex(2)
        expect(everyRecord?.descriptorType == fourCharacterCode("list") && everyRecord?.numberOfItems == 2, "properties of every tab returns one record per tab")
        expect(field(docsRecord, "ID  ")?.stringValue == docs.id.uuidString && field(docsRecord, "pnam")?.stringValue == "Docs"
            && field(docsRecord, "URL ")?.stringValue == docs.url && field(docsRecord, "loca")?.stringValue == "pinned"
            && field(docsRecord, "pcls")?.typeCodeValue == fourCharacterCode("tAbB"), "tab record carries id, title, URL, location and class under the dictionary codes")
        expect(field(docsRecord, "ldng")?.descriptorType == fourCharacterCode("bool") && field(docsRecord, "ldng")?.booleanValue == true
            && field(newsRecord, "ldng")?.booleanValue == false, "tab record reports loading as a Boolean")
        expect(field(newsRecord, "pnam")?.stringValue == "News" && field(newsRecord, "loca")?.stringValue == "topApp", "tab records keep window tab order")
        listed.activeTabID = news.id
        let activeRecord = perform("coregetd", on: property("pALL", of: property("acTa", of: listedWindow))) as? NSAppleEventDescriptor
        expect(activeRecord?.descriptorType == fourCharacterCode("reco") && field(activeRecord, "ID  ")?.stringValue == news.id.uuidString
            && field(activeRecord, "pnam")?.stringValue == "News", "properties of active tab describes the focused tab")
        expect(["WiND", "tAbB", "sPaC"].allSatisfy {
            NSScriptSuiteRegistry.shared().classDescription(withAppleEventCode: fourCharacterCode($0))?.key(withAppleEventCode: fourCharacterCode("pALL")) == "scriptingProperties"
        }, "windows, tabs and Spaces all answer the standard properties")
        _ = perform("SpaFocus", on: reference("sPaC", "name", NSAppleEventDescriptor(string: "Work"), in: listedWindow))
        expect(listed.focused == work.id, "a Space addressed by its title receives focus")
        let bulk = FakeOwner()
        bulk.tabs = (0..<120).map { index in
            ScriptTabRecord(id: UUID(), profileID: bulk.profile, title: "Tab \(index)", url: "https://example.test/\(index)",
                loading: index % 2 == 0, location: ["topApp", "pinned", "unpinned"][index % 3])
        }
        delegate.owners.append(bulk)
        let bulkWindow = reference("WiND", "ID  ", NSAppleEventDescriptor(string: bulk.scriptingID.uuidString), in: .null())
        let bulkSpace = reference("sPaC", "ID  ", NSAppleEventDescriptor(string: bulk.space.uuidString), in: bulkWindow)
        func every(in container: NSAppleEventDescriptor) -> NSAppleEventDescriptor {
            reference("tAbB", "indx", NSAppleEventDescriptor(descriptorType: fourCharacterCode("abso"), bytes: &all, length: 4)!, in: container)
        }
        func items(_ reply: Any?) -> [NSAppleEventDescriptor] {
            guard let list = reply as? NSAppleEventDescriptor, list.descriptorType == fourCharacterCode("list") else { return [] }
            return list.numberOfItems == 0 ? [] : (1...list.numberOfItems).compactMap { list.atIndex($0) }
        }
        func describes(_ record: NSAppleEventDescriptor?, _ tab: ScriptTabRecord) -> Bool {
            record?.descriptorType == fourCharacterCode("reco") && field(record, "ID  ")?.stringValue == tab.id.uuidString
                && field(record, "pnam")?.stringValue == tab.title && field(record, "URL ")?.stringValue == tab.url
                && field(record, "ldng")?.booleanValue == tab.loading && field(record, "loca")?.stringValue == tab.location
                && field(record, "pcls")?.typeCodeValue == fourCharacterCode("tAbB")
        }
        func counted(_ request: () -> Any?) -> (reply: Any?, passes: Int, lookups: Int) {
            bulk.listPasses = 0; bulk.tabLookups = 0
            let reply = request()
            return (reply, bulk.listPasses, bulk.tabLookups)
        }
        let everyProperties = counted { perform("coregetd", on: property("pALL", of: every(in: bulkWindow))) }
        let everyRecords = items(everyProperties.reply)
        expect(everyRecords.count == bulk.tabs.count && zip(everyRecords, bulk.tabs).allSatisfy { describes($0, $1) },
            "properties of every tab keeps every value, identity and the window's tab order")
        expect(everyProperties.passes == 1 && everyProperties.lookups == bulk.tabs.count,
            "properties of every tab lists the window once and reads each tab's record with one lookup")
        let everyID = counted { perform("coregetd", on: property("ID  ", of: every(in: bulkWindow))) }
        expect(items(everyID.reply).map(\.stringValue) == bulk.tabs.map { Optional($0.id.uuidString) }
            && everyID.passes == 1 && everyID.lookups == 0, "id of every tab is one pass in window order")
        let everyTitle = counted { perform("coregetd", on: property("pnam", of: every(in: bulkWindow))) }
        expect(items(everyTitle.reply).map(\.stringValue) == bulk.tabs.map { Optional($0.title) }
            && everyTitle.passes == 1 && everyTitle.lookups == bulk.tabs.count, "title of every tab is one pass plus one lookup per tab")
        let spaceProperties = counted { perform("coregetd", on: property("pALL", of: every(in: bulkSpace))) }
        let spaceRecords = items(spaceProperties.reply)
        expect(spaceRecords.count == bulk.tabs.count && zip(spaceRecords, bulk.tabs).allSatisfy { describes($0, $1) }
            && spaceProperties.passes == 1 && spaceProperties.lookups == bulk.tabs.count, "every tab of a Space is one pass with the same records")
        let target = bulk.tabs[57]
        let targetReference = reference("tAbB", "ID  ", NSAppleEventDescriptor(string: target.id.uuidString), in: bulkWindow)
        let byID = counted { perform("coregetd", on: property("pALL", of: targetReference)) }
        expect(describes(byID.reply as? NSAppleEventDescriptor, target) && byID.passes == 0 && byID.lookups == 2,
            "a tab named by its id is found and read through lookups without listing the window")
        bulk.activeTabID = target.id
        let active = counted { perform("coregetd", on: property("pALL", of: property("acTa", of: bulkWindow))) }
        expect(describes(active.reply as? NSAppleEventDescriptor, target) && active.passes == 0 && active.lookups == 2,
            "properties of active tab looks up only the focused tab")
        let bulkWrapper = ParcScriptWindow(owner: bulk)
        let directByID = counted { bulkWrapper.valueInAppleScriptTabs(withUniqueID: target.id.uuidString) }
        expect(directByID.reply as? ParcScriptTab != nil && (directByID.reply as? ParcScriptTab)?.identifier == target.id.uuidString
            && directByID.passes == 0 && directByID.lookups == 1, "the window resolves a tab id through one lookup")
        let absentByID = counted { bulkWrapper.valueInAppleScriptTabs(withUniqueID: UUID().uuidString) }
        expect(absentByID.reply as? ParcScriptTab == nil && absentByID.passes == 0 && absentByID.lookups == 1, "an unknown tab id finds nothing after one lookup")
        let lowercaseByID = counted { bulkWrapper.valueInAppleScriptTabs(withUniqueID: target.id.uuidString.lowercased()) }
        expect((lowercaseByID.reply as? ParcScriptTab)?.identifier == target.id.uuidString && lowercaseByID.passes == 0 && lowercaseByID.lookups == 1,
            "a tab id in other letter case still matches the way Cocoa compares script text")
        let numberByID = counted { bulkWrapper.valueInAppleScriptTabs(withUniqueID: NSNumber(value: 5)) }
        let paddedByID = counted { bulkWrapper.valueInAppleScriptTabs(withUniqueID: " " + target.id.uuidString) }
        expect(numberByID.reply as? ParcScriptTab == nil && numberByID.passes == 1 && numberByID.lookups == 0
            && paddedByID.reply as? ParcScriptTab == nil && paddedByID.passes == 1 && paddedByID.lookups == 0,
            "an id that is not a tab identity keeps Cocoa's own comparison over the listed tabs")
        let tabInSpace = reference("tAbB", "ID  ", NSAppleEventDescriptor(string: target.id.uuidString), in: bulkSpace)
        let spaceByID = counted { perform("coregetd", on: property("pALL", of: tabInSpace)) }
        expect(describes(spaceByID.reply as? NSAppleEventDescriptor, target) && spaceByID.passes == 0 && spaceByID.lookups == 2,
            "a tab named by its id inside a Space is found and read through lookups without listing the Space")
        let bulkSpaceWrapper = bulkWrapper.appleScriptSpaces[0]
        let directInSpace = counted { bulkSpaceWrapper.valueInAppleScriptTabs(withUniqueID: target.id.uuidString) }
        expect((directInSpace.reply as? ParcScriptTab)?.identifier == target.id.uuidString && directInSpace.passes == 0 && directInSpace.lookups == 1,
            "the Space resolves a tab id through one lookup")
        let absentInSpace = counted { bulkSpaceWrapper.valueInAppleScriptTabs(withUniqueID: UUID().uuidString) }
        expect(absentInSpace.reply as? ParcScriptTab == nil && absentInSpace.passes == 0 && absentInSpace.lookups == 1,
            "an unknown tab id inside a Space finds nothing after one lookup")
        let lowercaseInSpace = counted { bulkSpaceWrapper.valueInAppleScriptTabs(withUniqueID: target.id.uuidString.lowercased()) }
        expect((lowercaseInSpace.reply as? ParcScriptTab)?.identifier == target.id.uuidString && lowercaseInSpace.passes == 0 && lowercaseInSpace.lookups == 1,
            "a tab id in other letter case still matches inside a Space")
        let numberInSpace = counted { bulkSpaceWrapper.valueInAppleScriptTabs(withUniqueID: NSNumber(value: 5)) }
        let paddedInSpace = counted { bulkSpaceWrapper.valueInAppleScriptTabs(withUniqueID: " " + target.id.uuidString) }
        expect(numberInSpace.reply as? ParcScriptTab == nil && numberInSpace.passes == 1 && numberInSpace.lookups == 0
            && paddedInSpace.reply as? ParcScriptTab == nil && paddedInSpace.passes == 1 && paddedInSpace.lookups == 0,
            "an id that is not a tab identity keeps Cocoa's own comparison over the Space's tabs")
        let stranger = ScriptTabRecord(id: UUID(), profileID: bulk.otherProfile, title: "Stranger", url: "https://example.test/stranger",
            loading: false, location: "unpinned")
        bulk.tabs.append(stranger)
        let strangerInSpace = counted { bulkSpaceWrapper.valueInAppleScriptTabs(withUniqueID: stranger.id.uuidString) }
        expect((bulkWrapper.valueInAppleScriptTabs(withUniqueID: stranger.id.uuidString))?.identifier == stranger.id.uuidString
            && strangerInSpace.reply as? ParcScriptTab == nil && strangerInSpace.passes == 0 && strangerInSpace.lookups == 1,
            "a tab the window has but the Space doesn't list is not found inside the Space")
        bulk.tabs.removeLast()
        let listedSpaces = ParcScriptWindow(owner: listed).appleScriptSpaces
        expect(listedSpaces[1].title == "Work" && listedSpaces[1].valueInAppleScriptTabs(withUniqueID: docs.id.uuidString) == nil
            && listedSpaces[0].valueInAppleScriptTabs(withUniqueID: docs.id.uuidString)?.identifier == docs.id.uuidString,
            "a tab is found only inside the Space that lists it")
        listed.scriptingAvailable = false
        expect(listedSpaces[0].valueInAppleScriptTabs(withUniqueID: docs.id.uuidString) == nil, "a Space whose window is gone finds no tab")
        listed.scriptingAvailable = true
        let held = bulkWrapper.appleScriptTabs[1]
        bulk.tabs[1] = ScriptTabRecord(id: bulk.tabs[1].id, profileID: bulk.profile, title: "Renamed", url: "https://example.test/renamed",
            loading: true, location: "unpinned")
        let renamed = counted { held.value(forKey: "scriptingProperties") }
        expect((renamed.reply as? [String: Any])?["title"] as? String == "Renamed" && (renamed.reply as? [String: Any])?["URL"] as? String == bulk.tabs[1].url
            && renamed.lookups == 1, "a later properties read looks the tab up again and sees its current values")
        let renamedTitle = counted { held.title }
        expect(renamedTitle.reply as? String == "Renamed" && renamedTitle.lookups == 1, "a single property read is one lookup with current values")
        bulk.tabs.remove(at: 1)
        expect(held.title.isEmpty && held.location == "unknown" && ((held.value(forKey: "scriptingProperties") as? [String: Any])?["title"] as? String)?.isEmpty == true,
            "a tab gone from the window still reads as missing")
        listed.focused = nil
        _ = perform("SpaFocus", on: reference("sPaC", "name", NSAppleEventDescriptor(string: "Missing"), in: listedWindow))
        expect(listed.focused == nil, "an unknown Space title focuses nothing")
        print("\(checks) scripting component assertions passed; no browser or Apple Event dispatch.")
    }
}
