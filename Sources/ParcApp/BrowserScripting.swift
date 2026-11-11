import AppKit

struct ScriptTabRecord {
    let id: UUID
    let profileID: UUID
    let title: String
    let url: String
    let loading: Bool
    let location: String
}
struct ScriptSpaceRecord {
    let id: UUID
    let profileID: UUID
    let title: String
}
enum ScriptTabAction { case select, back, forward, reload, stop }

func scriptWindowCreationIsIncognito(_ properties: [String: Any]) throws -> Bool {
    guard Set(properties.keys).isSubset(of: ["mode", "isIncognito"]) else {
        throw BrowserScriptError.unsupported("Only mode and incognito may be set when creating a window.")
    }
    let mode = properties["mode"] as? String
    guard properties["mode"] == nil || mode == "normal" || mode == "incognito" else {
        throw BrowserScriptError.unsupported("Window mode must be normal or incognito.")
    }
    let flag = properties["isIncognito"] as? NSNumber
    guard properties["isIncognito"] == nil || (flag != nil && CFGetTypeID(flag!) == CFBooleanGetTypeID()) else {
        throw BrowserScriptError.unsupported("Incognito must be a Boolean.")
    }
    let result = flag?.boolValue ?? (mode == "incognito")
    guard mode == nil || result == (mode == "incognito") else {
        throw BrowserScriptError.unsupported("The requested mode and incognito properties disagree.")
    }
    return result
}

@MainActor
final class PendingBrowserCreation<Value> {
    let id = UUID()
    private var completion: ((Result<Value, Error>) -> Void)?
    var isPending: Bool { completion != nil }
    init(_ completion: @escaping (Result<Value, Error>) -> Void) { self.completion = completion }
    func finish(_ result: Result<Value, Error>) {
        guard let completion else { return }
        self.completion = nil
        completion(result)
    }
}

@MainActor
protocol BrowserPrivateScriptFactory: AnyObject {
    func scriptingMakePrivateWindow(completion: @escaping (Result<ParcScriptWindow, Error>) -> Void)
}

@MainActor
@objc(ParcCreateCommand)
class ParcCreateCommand: NSCreateCommand {
    override func performDefaultImplementation() -> Any? {
        guard createClassDescription.implementationClassName == NSStringFromClass(ParcScriptWindow.self) else {
            return super.performDefaultImplementation()
        }
        do {
            guard try scriptWindowCreationIsIncognito(resolvedKeyDictionary) else {
                return super.performDefaultImplementation()
            }
            let receiver = evaluatedReceivers
            let isApplication = receiver == nil || (receiver as? NSApplication) === NSApp ||
                ((receiver as? [NSApplication]).map { $0.count == 1 && $0[0] === NSApp } ?? false)
            guard isApplication,
                  let factory = NSApp.delegate as? any BrowserPrivateScriptFactory else {
                throw BrowserScriptError.unsupported("Create an incognito window in the application.")
            }
            let reply = ScriptPrivateWindowReply(self)
            factory.scriptingMakePrivateWindow { reply.finish($0) }
        } catch { BrowserScriptError.report(error, command: self) }
        return nil
    }
}

@MainActor
private final class ScriptPrivateWindowReply {
    private var command: NSScriptCommand?
    init(_ command: NSScriptCommand) { self.command = command; command.suspendExecution() }
    func finish(_ result: Result<ParcScriptWindow, Error>) {
        guard let command else { return }
        self.command = nil
        switch result {
        case .success(let window): command.resumeExecution(withResult: window)
        case .failure(let error):
            BrowserScriptError.report(error, command: command)
            command.resumeExecution(withResult: nil)
        }
    }
}

enum ScriptWindowOrigin { case application, nativeBrowser, auxiliary, offTheRecord }
enum ScriptWindowContext { case unavailable, regular, offTheRecord, mixed }
func scriptWindowHasNormalOwner(origin: ScriptWindowOrigin, context: ScriptWindowContext) -> Bool {
    switch (origin, context) {
    case (.application, .unavailable), (.application, .regular), (.nativeBrowser, .regular): return true
    default: return false
    }
}

@MainActor
protocol BrowserScriptOwner: AnyObject {
    var scriptingID: UUID { get }
    var scriptingIsIncognito: Bool { get }
    var scriptingAvailable: Bool { get }
    var scriptingWindow: NSWindow? { get }
    var scriptingTabs: [ScriptTabRecord] { get }
    var scriptingSpaces: [ScriptSpaceRecord] { get }
    var scriptingActiveTabID: UUID? { get }
    var scriptingActiveSpaceID: UUID { get }
    func scriptingTabs(in space: UUID, profile: UUID) -> [ScriptTabRecord]
    func scriptingPerform(_ action: ScriptTabAction, tab: UUID, profile: UUID) throws
    func scriptingNavigate(_ url: URL, tab: UUID, profile: UUID) throws
    func scriptingMakeTab(_ url: URL, space: UUID?, profile: UUID?) throws -> ScriptTabRecord
    func scriptingFocus(space: UUID, profile: UUID) throws
    func scriptingExecuteJavaScript(_ script: String, tab: UUID, profile: UUID,
        completion: @escaping (Result<String?, Error>) -> Void) throws -> () -> Void
    func scriptingClose(tab: UUID?, profile: UUID?, completion: @escaping (Bool) -> Void) throws
}

extension BrowserScriptOwner { var scriptingIsIncognito: Bool { false } }

enum BrowserScriptError: Error, LocalizedError {
    case missing, busy, invalidURL, unsupported(String), cancelled, execution(String, Int)
    var number: Int {
        switch self {
        case .execution(_, let number): return number
        case .missing: return -1728
        case .invalidURL: return -1700
        case .cancelled: return -128
        case .busy, .unsupported: return -10000
        }
    }
    var errorDescription: String? {
        switch self {
        case .execution(let message, _): return message
        case .missing: return "The original browser window, Space or tab is no longer available."
        case .busy: return "The original browser window or page is busy. Try again after its current operation finishes."
        case .invalidURL: return "Provide a valid absolute URL property for the new tab or URL assignment."
        case .unsupported(let message): return message
        case .cancelled: return "Closing was cancelled; the browser has kept the page or window."
        }
    }
    @MainActor static func report(_ error: Error, command: NSScriptCommand? = NSScriptCommand.current()) {
        let failure = error as? BrowserScriptError
        command?.scriptErrorNumber = failure?.number ?? -10000
        command?.scriptErrorString = error.localizedDescription
    }
    static func url(_ value: Any?) throws -> URL {
        guard let value = value as? String, !value.isEmpty,
              !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
              let url = URL(string: value), let scheme = url.scheme, !scheme.isEmpty else { throw Self.invalidURL }
        guard scheme.lowercased() != "javascript" else {
            throw Self.unsupported("JavaScript from Apple Events is not enabled by URL assignment.")
        }
        guard !InternalPage.isInternal(value) else {
            throw Self.unsupported("Scripting navigation to a local Parc document is not supported.")
        }
        if ["http", "https", "ftp"].contains(scheme.lowercased()), url.host?.isEmpty != false { throw Self.invalidURL }
        guard scheme.lowercased() != "arc" else { throw Self.invalidURL }
        return URL(string: BrowserInternalURL.publicString(url.absoluteString)) ?? url
    }
}

@MainActor
private func scriptResult<T>(_ body: () throws -> T) -> T? {
    do { return try body() } catch { BrowserScriptError.report(error); return nil }
}

@MainActor
private func scriptClose(_ owner: any BrowserScriptOwner, tab: UUID? = nil,
                         profile: UUID? = nil, command: NSScriptCommand) {
    command.suspendExecution()
    do {
        try owner.scriptingClose(tab: tab, profile: profile) { approved in
            if !approved { BrowserScriptError.report(BrowserScriptError.cancelled, command: command) }
            command.resumeExecution(withResult: nil)
        }
    } catch {
        BrowserScriptError.report(error, command: command)
        command.resumeExecution(withResult: nil)
    }
}

@MainActor
private final class ScriptJavaScriptReply {
    private var command: NSScriptCommand?
    private var cancellation: (() -> Void)?
    init(_ command: NSScriptCommand) { self.command = command; command.suspendExecution() }
    func attach(_ cancellation: @escaping () -> Void) {
        guard command != nil else { cancellation(); return }
        self.cancellation = cancellation
    }
    func finish(_ result: Result<String?, Error>) {
        guard let command else { return }
        self.command = nil
        switch result {
        case .success(let text): command.resumeExecution(withResult: text)
        case .failure(let error):
            BrowserScriptError.report(error, command: command)
            command.resumeExecution(withResult: nil)
        }
        cancellation = nil
    }
}

@MainActor
func acceptScriptInsertion<T: AnyObject>(_ proposed: [T], existing: [T],
    id: (T) -> String, pending: (T) -> Bool, owned: (T) -> Bool,
    consume: (T) -> Bool) -> Bool {
    let tokens = proposed.filter(pending)
    guard tokens.count == 1, let token = tokens.first, proposed.allSatisfy(owned) else { return false }
    let remainder = proposed.filter { $0 !== token }.map(id)
    let current = existing.map(id)
    guard remainder == current || remainder == current.filter({ $0 != id(token) }) else { return false }
    return consume(token)
}

@MainActor
@objc(ParcScriptWindow)
final class ParcScriptWindow: NSObject {
    private weak var owner: (any BrowserScriptOwner)?
    private let identity: UUID
    private var pendingInsertion: Bool
    init(owner: any BrowserScriptOwner, pendingInsertion: Bool = false) {
        self.owner = owner; identity = owner.scriptingID; self.pendingInsertion = pendingInsertion
        super.init()
    }
    func resolve() throws -> any BrowserScriptOwner {
        guard let owner, owner.scriptingID == identity, owner.scriptingAvailable else { throw BrowserScriptError.missing }
        return owner
    }
    var isPendingInsertion: Bool { pendingInsertion }
    func belongs(to candidate: any BrowserScriptOwner) -> Bool {
        owner === candidate && identity == candidate.scriptingID
    }
    func acceptInsertion(owner candidate: any BrowserScriptOwner) -> Bool {
        guard pendingInsertion, belongs(to: candidate) else { return false }
        pendingInsertion = false; return true
    }
    @objc(id) dynamic var identifier: String { identity.uuidString }
    @objc dynamic var title: String { scriptResult { try resolve().scriptingWindow?.title ?? "" } ?? "" }
    @objc dynamic var orderedIndex: Int { (try? resolve().scriptingWindow?.orderedIndex) ?? 0 }
    @objc dynamic var hasCloseBox: Bool { (try? resolve().scriptingWindow?.styleMask.contains(.closable)) ?? false }
    @objc dynamic var isMiniaturizable: Bool { (try? resolve().scriptingWindow?.styleMask.contains(.miniaturizable)) ?? false }
    @objc dynamic var isMiniaturized: Bool { (try? resolve().scriptingWindow?.isMiniaturized) ?? false }
    @objc dynamic var isResizable: Bool { (try? resolve().scriptingWindow?.styleMask.contains(.resizable)) ?? false }
    @objc dynamic var isVisible: Bool { (try? resolve().scriptingWindow?.isVisible) ?? false }
    @objc dynamic var isZoomable: Bool { (try? resolve().scriptingWindow?.isZoomable) ?? false }
    @objc dynamic var isZoomed: Bool { (try? resolve().scriptingWindow?.isZoomed) ?? false }
    @objc dynamic var mode: String {
        get { scriptResult { try resolve().scriptingIsIncognito ? "incognito" : "normal" } ?? "" }
        set { BrowserScriptError.report(BrowserScriptError.unsupported("Window mode can be specified only when creating a window.")) }
    }
    @objc dynamic var isIncognito: Bool {
        get { scriptResult { try resolve().scriptingIsIncognito } ?? false }
        set { BrowserScriptError.report(BrowserScriptError.unsupported("An existing window cannot change its browsing context.")) }
    }
    @objc dynamic var appleScriptTabs: [ParcScriptTab] {
        get { scriptResult { let owner = try resolve(); return owner.scriptingTabs.map { ParcScriptTab(owner: owner, record: $0) } } ?? [] }
        set {
            guard let owner = scriptResult({ try resolve() }),
                  acceptScriptInsertion(newValue, existing: appleScriptTabs, id: { $0.identifier },
                    pending: { $0.isPendingInsertion }, owned: { $0.belongs(to: owner) },
                    consume: { $0.acceptInsertion(in: identity) }) else {
                BrowserScriptError.report(BrowserScriptError.unsupported("Moving or replacing scripted tabs is not supported.")); return
            }
        }
    }
    @objc dynamic var appleScriptSpaces: [ParcScriptSpace] {
        scriptResult { let owner = try resolve(); return owner.scriptingSpaces.map { ParcScriptSpace(owner: owner, record: $0) } } ?? []
    }
    @objc dynamic var activeTab: ParcScriptTab? {
        scriptResult {
            let owner = try resolve()
            return owner.scriptingTabs.first { $0.id == owner.scriptingActiveTabID }.map { ParcScriptTab(owner: owner, record: $0) }
        } ?? nil
    }
    @objc dynamic var activeSpace: ParcScriptSpace? {
        scriptResult {
            let owner = try resolve()
            return owner.scriptingSpaces.first { $0.id == owner.scriptingActiveSpaceID }.map { ParcScriptSpace(owner: owner, record: $0) }
        } ?? nil
    }
    override var objectSpecifier: NSScriptObjectSpecifier? {
        guard let description = NSClassDescription(for: NSApplication.self) as? NSScriptClassDescription else { return nil }
        return NSUniqueIDSpecifier(containerClassDescription: description, containerSpecifier: nil,
                                   key: "appleScriptWindows", uniqueID: identifier)
    }
    override func newScriptingObject(of objectClass: AnyClass, forValueForKey key: String,
                                     withContentsValue contentsValue: Any?, properties: [String: Any]) -> Any? {
        scriptResult {
            guard objectClass == ParcScriptTab.self, key == "appleScriptTabs", contentsValue == nil else {
                throw BrowserScriptError.unsupported("Only tabs can be created in a browser window.")
            }
            let owner = try resolve(), url = try BrowserScriptError.url(properties["URL"])
            guard Set(properties.keys).isSubset(of: ["URL"]) else {
                throw BrowserScriptError.unsupported("New tabs accept the URL property only.")
            }
            return ParcScriptTab(owner: owner, record: try owner.scriptingMakeTab(url, space: nil, profile: nil), pendingInsertion: true)
        }
    }
    @objc(close:) func close(_ command: NSScriptCommand) {
        guard let owner = scriptResult({ try resolve() }) else { return }
        scriptClose(owner, command: command)
    }
}

@MainActor
@objc(ParcScriptTab)
final class ParcScriptTab: NSObject {
    private weak var owner: (any BrowserScriptOwner)?
    private let windowID: UUID
    private let tabID: UUID
    private let profileID: UUID
    private var pendingInsertion: Bool
    init(owner: any BrowserScriptOwner, record: ScriptTabRecord, pendingInsertion: Bool = false) {
        self.owner = owner; windowID = owner.scriptingID; tabID = record.id
        profileID = record.profileID; self.pendingInsertion = pendingInsertion; super.init()
    }
    private func resolve() throws -> (any BrowserScriptOwner, ScriptTabRecord) {
        guard let owner, owner.scriptingID == windowID, owner.scriptingAvailable,
              let tab = owner.scriptingTabs.first(where: { $0.id == tabID && $0.profileID == profileID }) else { throw BrowserScriptError.missing }
        return (owner, tab)
    }
    var isPendingInsertion: Bool { pendingInsertion }
    func belongs(to candidate: any BrowserScriptOwner) -> Bool {
        owner === candidate && windowID == candidate.scriptingID
            && candidate.scriptingTabs.contains { $0.id == tabID && $0.profileID == profileID }
    }
    func acceptInsertion(in window: UUID) -> Bool {
        guard windowID == window, pendingInsertion, (try? resolve()) != nil else { return false }
        pendingInsertion = false; return true
    }
    @objc(id) dynamic var identifier: String { tabID.uuidString }
    @objc dynamic var title: String { scriptResult { try resolve().1.title } ?? "" }
    @objc dynamic var URL: String {
        get { scriptResult { try resolve().1.url } ?? "" }
        set { _ = scriptResult { try resolve().0.scriptingNavigate(BrowserScriptError.url(newValue), tab: tabID, profile: profileID) } }
    }
    @objc dynamic var loading: Bool { scriptResult { try resolve().1.loading } ?? false }
    @objc dynamic var location: String { scriptResult { try resolve().1.location } ?? "unknown" }
    override var objectSpecifier: NSScriptObjectSpecifier? {
        guard let owner, let description = NSClassDescription(for: ParcScriptWindow.self) as? NSScriptClassDescription else { return nil }
        return NSUniqueIDSpecifier(containerClassDescription: description,
            containerSpecifier: ParcScriptWindow(owner: owner).objectSpecifier,
            key: "appleScriptTabs", uniqueID: identifier)
    }
    private func perform(_ action: ScriptTabAction) {
        _ = scriptResult { try resolve().0.scriptingPerform(action, tab: tabID, profile: profileID) }
    }
    @objc(executeJavascript:) func executeJavascript(_ command: NSScriptCommand) {
        do {
            let owner = try resolve().0
            guard let code = command.evaluatedArguments?["javascript"] as? String else {
                throw BrowserScriptError.execution("The javascript parameter must be text.", -1700)
            }
            let reply = ScriptJavaScriptReply(command)
            do {
                let cancel = try owner.scriptingExecuteJavaScript(code, tab: tabID, profile: profileID) { [self] result in
                    guard (try? resolve()) != nil else { reply.finish(.failure(BrowserScriptError.missing)); return }
                    reply.finish(result)
                }
                reply.attach(cancel)
            } catch { reply.finish(.failure(error)) }
        } catch { BrowserScriptError.report(error, command: command) }
    }
    @objc(select:) func select(_ command: NSScriptCommand) { perform(.select) }
    @objc(goBack:) func goBack(_ command: NSScriptCommand) { perform(.back) }
    @objc(goForward:) func goForward(_ command: NSScriptCommand) { perform(.forward) }
    @objc(reload:) func reload(_ command: NSScriptCommand) { perform(.reload) }
    @objc(stopLoading:) func stopLoading(_ command: NSScriptCommand) { perform(.stop) }
    @objc(close:) func close(_ command: NSScriptCommand) {
        guard let owner = scriptResult({ try resolve().0 }) else { return }
        scriptClose(owner, tab: tabID, profile: profileID, command: command)
    }
}

@MainActor
@objc(ParcScriptSpace)
final class ParcScriptSpace: NSObject {
    private weak var owner: (any BrowserScriptOwner)?
    private let windowID: UUID
    private let spaceID: UUID
    private let profileID: UUID
    init(owner: any BrowserScriptOwner, record: ScriptSpaceRecord) {
        self.owner = owner; windowID = owner.scriptingID; spaceID = record.id; profileID = record.profileID; super.init()
    }
    private func resolve() throws -> (any BrowserScriptOwner, ScriptSpaceRecord) {
        guard let owner, owner.scriptingID == windowID, owner.scriptingAvailable,
              let space = owner.scriptingSpaces.first(where: { $0.id == spaceID && $0.profileID == profileID }) else { throw BrowserScriptError.missing }
        return (owner, space)
    }
    @objc(id) dynamic var identifier: String { spaceID.uuidString }
    @objc dynamic var title: String { scriptResult { try resolve().1.title } ?? "" }
    @objc dynamic var appleScriptTabs: [ParcScriptTab] {
        get {
            scriptResult {
                let owner = try resolve().0
                return owner.scriptingTabs(in: spaceID, profile: profileID).map { ParcScriptTab(owner: owner, record: $0) }
            } ?? []
        }
        set {
            guard let owner = scriptResult({ try resolve().0 }),
                  acceptScriptInsertion(newValue, existing: appleScriptTabs, id: { $0.identifier },
                    pending: { $0.isPendingInsertion }, owned: { $0.belongs(to: owner) },
                    consume: { $0.acceptInsertion(in: windowID) }) else {
                BrowserScriptError.report(BrowserScriptError.unsupported("Moving or replacing scripted tabs is not supported.")); return
            }
        }
    }
    override var objectSpecifier: NSScriptObjectSpecifier? {
        guard let owner, let description = NSClassDescription(for: ParcScriptWindow.self) as? NSScriptClassDescription else { return nil }
        return NSUniqueIDSpecifier(containerClassDescription: description,
            containerSpecifier: ParcScriptWindow(owner: owner).objectSpecifier,
            key: "appleScriptSpaces", uniqueID: identifier)
    }
    override func newScriptingObject(of objectClass: AnyClass, forValueForKey key: String,
                                     withContentsValue contentsValue: Any?, properties: [String: Any]) -> Any? {
        scriptResult {
            guard objectClass == ParcScriptTab.self, key == "appleScriptTabs", contentsValue == nil,
                  Set(properties.keys).isSubset(of: ["URL"]) else {
                throw BrowserScriptError.unsupported("Only tabs with a URL can be created in a Space.")
            }
            let owner = try resolve().0, url = try BrowserScriptError.url(properties["URL"])
            let tab = try owner.scriptingMakeTab(url, space: spaceID, profile: profileID)
            return ParcScriptTab(owner: owner, record: tab, pendingInsertion: true)
        }
    }
    @objc(focus:) func focus(_ command: NSScriptCommand) {
        _ = scriptResult { try resolve().0.scriptingFocus(space: spaceID, profile: profileID) }
    }
}
