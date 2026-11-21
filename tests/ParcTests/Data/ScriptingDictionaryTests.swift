import AppKit
import Testing
@testable import Parc

@MainActor
private enum ScriptingDictionary {
    static let windowClass: NSScriptClassDescription? = install()

    private static func install() -> NSScriptClassDescription? {
        guard let url = Bundle.module.url(forResource: "Parc", withExtension: "sdef", subdirectory: "Scripting"),
              let data = try? Data(contentsOf: url) else { return nil }
        _ = NSApplication.shared
        let registry = NSScriptSuiteRegistry()
        registry.setValue(NSMutableArray(), forKey: "_suiteDescriptions")
        registry.setValue(NSMutableDictionary(), forKey: "_cachedClassDescriptionsByAppleEventCode")
        registry.setValue(NSMutableDictionary(), forKey: "_cachedCommandDescriptionsByAppleEventCodes")
        registry.setValue(nil, forKey: "_cachedSuiteDescriptionsByName")
        registry.setValue(true, forKey: "_isLoadingSDEFFiles")
        _ = registry.perform(NSSelectorFromString("_loadIntrinsicScriptingDefinitions"))
        _ = registry.perform(NSSelectorFromString("_loadSuitesFromSDEFData:bundle:"), with: data, with: Bundle(for: ParcScriptWindow.self))
        registry.setValue(false, forKey: "_isLoadingSDEFFiles")
        if let collected = registry.value(forKey: "_suiteDescriptionsBeingCollected") as? NSArray, collected.count > 0 {
            _ = registry.perform(NSSelectorFromString("_registerSuiteDescriptions:"), with: collected)
        }
        NSScriptSuiteRegistry.setShared(registry)
        return registry.classDescription(withAppleEventCode: AppleEvents.code("WiND"))
    }
}

@MainActor
private enum AppleEvents {
    static func code(_ text: String) -> FourCharCode { text.utf8.reduce(0) { ($0 << 8) | FourCharCode($1) } }

    static func reference(_ want: String, _ form: String, _ data: NSAppleEventDescriptor,
                          in container: NSAppleEventDescriptor = .null()) -> NSAppleEventDescriptor {
        let record = NSAppleEventDescriptor.record()
        record.setDescriptor(NSAppleEventDescriptor(typeCode: code(want)), forKeyword: code("want"))
        record.setDescriptor(NSAppleEventDescriptor(enumCode: code(form)), forKeyword: code("form"))
        record.setDescriptor(data, forKeyword: code("seld"))
        record.setDescriptor(container, forKeyword: code("from"))
        return record.coerce(toDescriptorType: code("obj "))!
    }

    static func identified(_ want: String, _ id: UUID, in container: NSAppleEventDescriptor = .null()) -> NSAppleEventDescriptor {
        reference(want, "ID  ", NSAppleEventDescriptor(string: id.uuidString), in: container)
    }

    static func property(_ property: String, of container: NSAppleEventDescriptor) -> NSAppleEventDescriptor {
        reference("prop", "prop", NSAppleEventDescriptor(typeCode: code(property)), in: container)
    }

    static func everyTab(in container: NSAppleEventDescriptor) -> NSAppleEventDescriptor {
        var all = code("all ")
        return reference("tAbB", "indx", NSAppleEventDescriptor(descriptorType: code("abso"), bytes: &all, length: 4)!, in: container)
    }

    static func perform(_ event: String, on receiver: NSAppleEventDescriptor) -> Any? {
        guard let description = NSScriptSuiteRegistry.shared().commandDescription(
            withAppleEventClass: code(String(event.prefix(4))), andAppleEventCode: code(String(event.suffix(4)))) else { return nil }
        let command = description.createCommandInstance()
        command.receiversSpecifier = NSScriptObjectSpecifier(descriptor: receiver)
        return command.execute()
    }

    static func get(_ reference: NSAppleEventDescriptor) -> Any? { perform("coregetd", on: reference) }

    static func field(_ record: NSAppleEventDescriptor?, _ key: String) -> NSAppleEventDescriptor? {
        record?.forKeyword(code(key))
    }

    static func items(_ reply: Any?) -> [NSAppleEventDescriptor] {
        guard let list = reply as? NSAppleEventDescriptor, list.descriptorType == code("list") else { return [] }
        return list.numberOfItems == 0 ? [] : (1...list.numberOfItems).compactMap { list.atIndex($0) }
    }

    static func describes(_ record: NSAppleEventDescriptor?, _ tab: ScriptTabRecord) -> Bool {
        record?.descriptorType == code("reco") && field(record, "ID  ")?.stringValue == tab.id.uuidString
            && field(record, "pnam")?.stringValue == tab.title && field(record, "URL ")?.stringValue == tab.url
            && field(record, "ldng")?.descriptorType == code("bool") && field(record, "ldng")?.booleanValue == tab.loading
            && field(record, "loca")?.stringValue == tab.location && field(record, "pcls")?.typeCodeValue == code("tAbB")
    }
}

@MainActor
private final class ScriptingApplication: NSObject, NSApplicationDelegate, BrowserPrivateScriptFactory {
    var owners: [BrowserScriptingTests.Owner]
    var factories = 0, insertions = 0
    var readyOnCreation = true
    var privateCreations = 0
    var privateReply: ((Result<ParcScriptWindow, Error>) -> Void)?

    init(owners: [BrowserScriptingTests.Owner]? = nil) { self.owners = owners ?? [BrowserScriptingTests.Owner()] }

    func scriptingMakePrivateWindow(completion: @escaping (Result<ParcScriptWindow, Error>) -> Void) {
        privateCreations += 1
        privateReply = completion
    }

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
        let owner = BrowserScriptingTests.Owner()
        owner.scriptingAvailable = readyOnCreation
        owners.append(owner)
        return ParcScriptWindow(owner: owner, pendingInsertion: true)
    }

    func run<T>(_ body: (NSApplication) throws -> T) throws -> T {
        try #require(ScriptingDictionary.windowClass != nil)
        let app = NSApplication.shared
        let previous = app.delegate
        Thread.current.threadDictionary.removeObject(forKey: "NSScriptExecutionContext")
        app.delegate = self
        defer {
            app.delegate = previous
            Thread.current.threadDictionary.removeObject(forKey: "NSScriptExecutionContext")
        }
        return try body(app)
    }
}

@MainActor
private final class ObservedCreateCommand: ParcCreateCommand {
    var suspensions = 0, resumptions = 0
    var result: Any?
    var properties: [String: Any] = ["mode": "incognito"]
    override var createClassDescription: NSScriptClassDescription { ScriptingDictionary.windowClass! }
    override var resolvedKeyDictionary: [String: Any] { properties }
    override var evaluatedReceivers: Any? { nil }
    override func suspendExecution() { suspensions += 1 }
    override func resumeExecution(withResult result: Any?) { resumptions += 1; self.result = result }

    static func make(_ properties: [String: Any] = ["mode": "incognito"]) throws -> ObservedCreateCommand {
        let description = try #require(NSScriptSuiteRegistry.shared().commandDescription(
            withAppleEventClass: AppleEvents.code("core"), andAppleEventCode: AppleEvents.code("crel")))
        let command = ObservedCreateCommand(commandDescription: description)
        command.properties = properties
        return command
    }
}

@Suite(.serialized)
@MainActor
struct ScriptingDictionaryTests {
    typealias Owner = BrowserScriptingTests.Owner

    private func tab(_ owner: Owner, _ title: String, loading: Bool = false, location: String = "unpinned",
                     profile: UUID? = nil) -> ScriptTabRecord {
        ScriptTabRecord(id: UUID(), profileID: profile ?? owner.profile, title: title,
                        url: "https://example.test/\(title.lowercased())", loading: loading, location: location)
    }

    private func bulkOwner() -> Owner {
        let owner = Owner()
        owner.tabs = (0..<12).map { index in
            ScriptTabRecord(id: UUID(), profileID: owner.profile, title: "Tab \(index)", url: "https://example.test/\(index)",
                            loading: index % 2 == 0, location: ["topApp", "pinned", "unpinned"][index % 3])
        }
        return owner
    }

    private func counted(_ owner: Owner, _ request: () -> Any?) -> (reply: Any?, passes: Int, lookups: Int) {
        owner.listPasses = 0
        owner.tabLookups = 0
        let reply = request()
        return (reply, owner.listPasses, owner.tabLookups)
    }

    @Test(arguments: ["WiND", "tAbB", "sPaC"])
    func everyScriptableClassAnswersTheStandardProperties(_ code: String) throws {
        try #require(ScriptingDictionary.windowClass != nil)
        let description = NSScriptSuiteRegistry.shared().classDescription(withAppleEventCode: AppleEvents.code(code))
        #expect(description?.key(withAppleEventCode: AppleEvents.code("pALL")) == "scriptingProperties")
    }

    @Test func theApplicationListsItsWindowsThroughTheDelegate() throws {
        let application = ScriptingApplication()
        let windows = try application.run { $0.value(forKey: "appleScriptWindows") as? [ParcScriptWindow] }
        #expect(windows?.count == 1)
    }

    @Test func creatingAndInsertingAWindowLeavesOneNewWindow() throws {
        let application = ScriptingApplication()
        try application.run { app in
            let made = try #require(app.newScriptingObject(of: ParcScriptWindow.self, forValueForKey: "appleScriptWindows",
                                                           withContentsValue: nil, properties: [:]) as? ParcScriptWindow)
            app.insertValue(made, at: 0, inPropertyWithKey: "appleScriptWindows")
        }
        #expect(application.factories == 1)
        #expect(application.insertions == 1)
        #expect(application.owners.count == 2)
    }

    @Test func aCreatedWindowIsAcknowledgedOnlyOnce() throws {
        let application = ScriptingApplication()
        try application.run { app in
            let made = try #require(app.newScriptingObject(of: ParcScriptWindow.self, forValueForKey: "appleScriptWindows",
                                                           withContentsValue: nil, properties: [:]))
            app.insertValue(made, at: 0, inPropertyWithKey: "appleScriptWindows")
            app.insertValue(made, at: 0, inPropertyWithKey: "appleScriptWindows")
        }
        #expect(application.insertions == 1)
        #expect(application.owners.count == 2)
    }

    @Test func replacingTheWindowListCannotReorderWindows() throws {
        let application = ScriptingApplication(owners: [Owner(), Owner()])
        try application.run { app in
            app.setValue(Array(application.appleScriptWindows.reversed()), forKey: "appleScriptWindows")
        }
        #expect(application.insertions == 0)
    }

    @Test func aWindowStillOpeningIsAcknowledgedBeforeItIsReady() throws {
        let application = ScriptingApplication()
        application.readyOnCreation = false
        try application.run { app in
            let made = try #require(app.newScriptingObject(of: ParcScriptWindow.self, forValueForKey: "appleScriptWindows",
                                                           withContentsValue: nil, properties: [:]))
            app.insertValue(made, at: 0, inPropertyWithKey: "appleScriptWindows")
        }
        #expect(application.insertions == 1)
        #expect(application.owners.count == 2)
    }

    @Test func aPrivateMakeWaitsForTheOriginalWindowAndRepliesOnce() throws {
        let application = ScriptingApplication()
        let owner = Owner()
        owner.scriptingIsIncognito = true
        let window = ParcScriptWindow(owner: owner)
        let command = try ObservedCreateCommand.make()
        try application.run { _ in
            _ = command.performDefaultImplementation()
            #expect(command.suspensions == 1)
            #expect(command.resumptions == 0)
            #expect(application.privateCreations == 1)
            let reply = try #require(application.privateReply)
            reply(.success(window))
            reply(.failure(BrowserScriptError.missing))
        }
        #expect(command.resumptions == 1)
        #expect(command.result as? ParcScriptWindow === window)
    }

    @Test func losingTheProfileFailsAPrivateMakeWithoutAStandIn() throws {
        let application = ScriptingApplication()
        let command = try ObservedCreateCommand.make()
        try application.run { _ in
            _ = command.performDefaultImplementation()
            let reply = try #require(application.privateReply)
            reply(.failure(BrowserScriptError.missing))
        }
        #expect(command.resumptions == 1)
        #expect(command.scriptErrorNumber == -1728)
        #expect(command.result == nil)
    }

    @Test func aMalformedPrivateMakeNeverStartsProfileCreation() throws {
        let application = ScriptingApplication()
        let command = try ObservedCreateCommand.make(["mode": "incognito", "isIncognito": false])
        try application.run { _ in _ = command.performDefaultImplementation() }
        #expect(command.suspensions == 0)
        #expect(application.privateCreations == 0)
        #expect(command.scriptErrorNumber != 0)
    }

    @Test func scriptObjectsAreNamedByUniqueIDInsideTheirWindow() throws {
        let owner = Owner()
        owner.tabs = [tab(owner, "Original")]
        let application = ScriptingApplication(owners: [owner])
        try application.run { _ in
            let window = ParcScriptWindow(owner: owner)
            #expect(window.objectSpecifier is NSUniqueIDSpecifier)
            #expect(window.appleScriptTabs.first?.objectSpecifier?.container is NSUniqueIDSpecifier)
            #expect(window.appleScriptSpaces.first?.objectSpecifier is NSUniqueIDSpecifier)
            #expect(window.activeSpace?.identifier == owner.space.uuidString)
        }
    }

    private func command(_ event: String, arguments: [String: Any]? = nil) throws -> BrowserScriptingTests.ObservedCommand {
        let description = try #require(NSScriptSuiteRegistry.shared().commandDescription(
            withAppleEventClass: AppleEvents.code(String(event.prefix(4))), andAppleEventCode: AppleEvents.code(String(event.suffix(4)))))
        let command = BrowserScriptingTests.ObservedCommand(commandDescription: description)
        command.parameters = arguments
        return command
    }

    @Test func anImmediateCloseResumesTheCommandItSuspended() throws {
        try #require(ScriptingDictionary.windowClass != nil)
        let owner = Owner()
        owner.immediateClose = true
        let close = try command("coreclos")

        ParcScriptWindow(owner: owner).close(close)

        #expect(close.suspensions == 1)
        #expect(close.resumptions == 1)
    }

    @Test func aRetiredWindowCannotCloseOrFocus() throws {
        try #require(ScriptingDictionary.windowClass != nil)
        let owner = Owner()
        let window = ParcScriptWindow(owner: owner)
        let space = try #require(window.appleScriptSpaces.first)
        let close = try command("coreclos")
        owner.scriptingAvailable = false

        space.focus(close)
        window.close(close)

        #expect(close.suspensions == 0)
        #expect(owner.focused == nil)
    }

    @Test func focusingASpaceUsesItsOriginalIdentity() throws {
        try #require(ScriptingDictionary.windowClass != nil)
        let owner = Owner()
        let space = try #require(ParcScriptWindow(owner: owner).appleScriptSpaces.first)

        space.focus(try command("SpaFocus"))

        #expect(owner.focused == owner.space)
    }

    @Test func aTabMadeInsideASpaceAppearsInThatSpace() throws {
        let owner = Owner()
        let space = try #require(ParcScriptWindow(owner: owner).appleScriptSpaces.first)
        let made = try #require(space.newScriptingObject(of: ParcScriptTab.self, forValueForKey: "appleScriptTabs",
            withContentsValue: nil, properties: ["URL": "https://example.test/in-space"]) as? ParcScriptTab)

        space.insertValue(made, at: 0, inPropertyWithKey: "appleScriptTabs")

        #expect(space.appleScriptTabs.map(\.URL) == ["https://example.test/in-space"])
    }

    @Test func aTabWithoutAURLIsNeverCreated() {
        let owner = Owner()
        let window = ParcScriptWindow(owner: owner)

        let made = window.newScriptingObject(of: ParcScriptTab.self, forValueForKey: "appleScriptTabs",
                                             withContentsValue: nil, properties: [:])

        #expect(made == nil)
        #expect(owner.tabs.isEmpty)
    }

    private func executing(_ owner: Owner, _ arguments: [String: Any] = ["javascript": "document.title"]) throws
        -> BrowserScriptingTests.ObservedCommand {
        try #require(ScriptingDictionary.windowClass != nil)
        owner.tabs = [tab(owner, "Page")]
        let script = try command("CrSuExJa", arguments: arguments)
        try #require(ParcScriptWindow(owner: owner).activeTab).executeJavascript(script)
        return script
    }

    @Test func anImmediateJavaScriptResultKeepsItsJSONAndHoldsNoLease() throws {
        let owner = Owner()
        owner.immediateJavaScript = .success("{\"items\":[1,true,null]}")

        let script = try executing(owner)

        #expect(script.suspensions == 1)
        #expect(script.resumptions == 1)
        #expect(script.result as? String == "{\"items\":[1,true,null]}")
        #expect(owner.cancellations == 1)
    }

    @Test func anAbsentJavaScriptResultStaysAbsent() throws {
        let owner = Owner()
        owner.immediateJavaScript = .success(nil)

        let script = try executing(owner)

        #expect(script.resumptions == 1)
        #expect(script.result == nil)
        #expect(script.scriptErrorNumber == 0)
    }

    @Test func aRefusedJavaScriptDispatchResumesTheCommand() throws {
        let owner = Owner()
        owner.javascriptThrows = BrowserScriptError.busy

        let script = try executing(owner)

        #expect(script.suspensions == 1)
        #expect(script.resumptions == 1)
        #expect(script.scriptErrorNumber == -10000)
    }

    @Test func nonTextJavaScriptIsRejectedBeforeSuspending() throws {
        let owner = Owner()

        let script = try executing(owner, ["javascript": 4])

        #expect(script.suspensions == 0)
        #expect(script.scriptErrorNumber == -1700)
        #expect(owner.javascriptRequests.isEmpty)
    }

    @Test func aLateJavaScriptResultCannotEscapeARetiredWindow() throws {
        let owner = Owner()
        let script = try executing(owner)
        let complete = try #require(owner.javascriptCallback)
        owner.scriptingAvailable = false

        complete(.success("42"))

        #expect(script.resumptions == 1)
        #expect(script.scriptErrorNumber == -1728)
        #expect(script.result == nil)
    }

    private func listedOwner() -> (Owner, docs: ScriptTabRecord, news: ScriptTabRecord, work: ScriptSpaceRecord) {
        let owner = Owner()
        let work = ScriptSpaceRecord(id: UUID(), profileID: owner.profile, title: "Work")
        owner.extraSpaces = [work]
        let docs = tab(owner, "Docs", loading: true, location: "pinned")
        let news = tab(owner, "News", location: "topApp")
        owner.tabs = [docs, news]
        return (owner, docs, news, work)
    }

    @Test func propertiesOfEveryTabAreOneRecordPerTabInWindowOrder() throws {
        let (owner, docs, news, _) = listedOwner()
        let application = ScriptingApplication(owners: [owner])
        let window = AppleEvents.identified("WiND", owner.scriptingID)

        let reply = try application.run { _ in AppleEvents.get(AppleEvents.property("pALL", of: AppleEvents.everyTab(in: window))) }

        let records = AppleEvents.items(reply)
        #expect(records.count == 2)
        #expect(AppleEvents.describes(records.first, docs))
        #expect(AppleEvents.describes(records.last, news))
    }

    @Test func propertiesOfTheActiveTabDescribeTheFocusedTab() throws {
        let (owner, _, news, _) = listedOwner()
        owner.activeTabID = news.id
        let application = ScriptingApplication(owners: [owner])
        let window = AppleEvents.identified("WiND", owner.scriptingID)

        let reply = try application.run { _ in AppleEvents.get(AppleEvents.property("pALL", of: AppleEvents.property("acTa", of: window))) }

        #expect(AppleEvents.describes(reply as? NSAppleEventDescriptor, news))
    }

    @Test(arguments: [("Work", true), ("Missing", false)])
    func focusReachesOnlyASpaceNamedByItsTitle(_ title: String, _ found: Bool) throws {
        let (owner, _, _, work) = listedOwner()
        let application = ScriptingApplication(owners: [owner])
        let window = AppleEvents.identified("WiND", owner.scriptingID)

        try application.run { _ in
            _ = AppleEvents.perform("SpaFocus", on: AppleEvents.reference("sPaC", "name", NSAppleEventDescriptor(string: title), in: window))
        }

        #expect(owner.focused == (found ? work.id : nil))
    }

    @Test(arguments: [false, true])
    func propertiesOfEveryTabListOnceAndLookUpEachTab(_ inSpace: Bool) throws {
        let owner = bulkOwner()
        let application = ScriptingApplication(owners: [owner])
        let window = AppleEvents.identified("WiND", owner.scriptingID)
        let container = inSpace ? AppleEvents.identified("sPaC", owner.space, in: window) : window

        let result = try application.run { _ in
            counted(owner) { AppleEvents.get(AppleEvents.property("pALL", of: AppleEvents.everyTab(in: container))) }
        }

        let records = AppleEvents.items(result.reply)
        #expect(records.count == owner.tabs.count)
        #expect(zip(records, owner.tabs).allSatisfy { AppleEvents.describes($0, $1) })
        #expect(result.passes == 1)
        #expect(result.lookups == owner.tabs.count)
    }

    @Test(arguments: [("ID  ", false), ("pnam", true)])
    func onePropertyOfEveryTabListsOnceInWindowOrder(_ property: String, _ readsEachTab: Bool) throws {
        let owner = bulkOwner()
        let application = ScriptingApplication(owners: [owner])
        let window = AppleEvents.identified("WiND", owner.scriptingID)

        let result = try application.run { _ in
            counted(owner) { AppleEvents.get(AppleEvents.property(property, of: AppleEvents.everyTab(in: window))) }
        }

        let expected = owner.tabs.map { property == "pnam" ? $0.title : $0.id.uuidString }
        #expect(AppleEvents.items(result.reply).map(\.stringValue) == expected.map(Optional.some))
        #expect(result.passes == 1)
        #expect(result.lookups == (readsEachTab ? owner.tabs.count : 0))
    }

    enum Addressed: CaseIterable { case idInWindow, idInSpace, activeTab }

    @Test(arguments: Addressed.allCases)
    func aSingleAddressedTabIsReadWithoutListing(_ addressed: Addressed) throws {
        let owner = bulkOwner()
        let target = owner.tabs[7]
        owner.activeTabID = target.id
        let application = ScriptingApplication(owners: [owner])
        let window = AppleEvents.identified("WiND", owner.scriptingID)
        let reference: NSAppleEventDescriptor
        switch addressed {
        case .idInWindow: reference = AppleEvents.identified("tAbB", target.id, in: window)
        case .idInSpace: reference = AppleEvents.identified("tAbB", target.id, in: AppleEvents.identified("sPaC", owner.space, in: window))
        case .activeTab: reference = AppleEvents.property("acTa", of: window)
        }

        let result = try application.run { _ in counted(owner) { AppleEvents.get(AppleEvents.property("pALL", of: reference)) } }

        #expect(AppleEvents.describes(result.reply as? NSAppleEventDescriptor, target))
        #expect(result.passes == 0)
        #expect(result.lookups == 2)
    }

    @Test(arguments: [false, true])
    func anUnknownTabIDFindsNothingAfterOneLookup(_ inSpace: Bool) throws {
        let owner = bulkOwner()
        let window = ParcScriptWindow(owner: owner)
        let space = try #require(window.appleScriptSpaces.first)

        let result = counted(owner) {
            inSpace ? space.valueInAppleScriptTabs(withUniqueID: UUID().uuidString)
                : window.valueInAppleScriptTabs(withUniqueID: UUID().uuidString)
        }

        #expect(result.reply as? ParcScriptTab == nil)
        #expect(result.passes == 0)
        #expect(result.lookups == 1)
    }

    @Test(arguments: [(false, false), (false, true), (true, false), (true, true)])
    func anIDThatIsNotATabIdentityKeepsCocoasComparisonOverTheList(_ inSpace: Bool, _ padded: Bool) throws {
        let owner = bulkOwner()
        let window = ParcScriptWindow(owner: owner)
        let space = try #require(window.appleScriptSpaces.first)
        let id: Any = padded ? " " + owner.tabs[3].id.uuidString : NSNumber(value: 5)

        let result = counted(owner) {
            inSpace ? space.valueInAppleScriptTabs(withUniqueID: id) : window.valueInAppleScriptTabs(withUniqueID: id)
        }

        #expect(result.reply as? ParcScriptTab == nil)
        #expect(result.passes == 1)
        #expect(result.lookups == 0)
    }

    @Test func aTabFromAnotherProfileIsNotFoundInsideTheSpace() throws {
        let owner = bulkOwner()
        let stranger = tab(owner, "Stranger", profile: owner.otherProfile)
        owner.tabs.append(stranger)
        let window = ParcScriptWindow(owner: owner)
        let space = try #require(window.appleScriptSpaces.first)

        let inSpace = counted(owner) { space.valueInAppleScriptTabs(withUniqueID: stranger.id.uuidString) }

        #expect(window.valueInAppleScriptTabs(withUniqueID: stranger.id.uuidString)?.identifier == stranger.id.uuidString)
        #expect(inSpace.reply as? ParcScriptTab == nil)
        #expect(inSpace.passes == 0)
        #expect(inSpace.lookups == 1)
    }

    @Test func aTabIsFoundOnlyInsideTheSpaceThatListsIt() {
        let (owner, docs, _, _) = listedOwner()
        let spaces = ParcScriptWindow(owner: owner).appleScriptSpaces

        #expect(spaces.map(\.title) == ["Space", "Work"])
        #expect(spaces[0].valueInAppleScriptTabs(withUniqueID: docs.id.uuidString)?.identifier == docs.id.uuidString)
        #expect(spaces[1].valueInAppleScriptTabs(withUniqueID: docs.id.uuidString) == nil)
    }

    @Test func aSpaceWhoseWindowIsGoneFindsNoTab() throws {
        let (owner, docs, _, _) = listedOwner()
        let space = try #require(ParcScriptWindow(owner: owner).appleScriptSpaces.first)
        owner.scriptingAvailable = false

        #expect(space.valueInAppleScriptTabs(withUniqueID: docs.id.uuidString) == nil)
    }

    @Test func aHeldTabReadsItsCurrentValuesWithOneLookup() throws {
        let owner = bulkOwner()
        let held = ParcScriptWindow(owner: owner).appleScriptTabs[1]
        owner.tabs[1] = ScriptTabRecord(id: owner.tabs[1].id, profileID: owner.profile, title: "Renamed",
                                        url: "https://example.test/renamed", loading: true, location: "unpinned")

        let properties = counted(owner) { held.value(forKey: "scriptingProperties") }
        let title = counted(owner) { held.title }

        #expect((properties.reply as? [String: Any])?["title"] as? String == "Renamed")
        #expect((properties.reply as? [String: Any])?["URL"] as? String == "https://example.test/renamed")
        #expect(properties.lookups == 1)
        #expect(title.reply as? String == "Renamed")
        #expect(title.lookups == 1)
    }

    @Test func aTabGoneFromTheWindowReadsAsMissing() {
        let owner = bulkOwner()
        let held = ParcScriptWindow(owner: owner).appleScriptTabs[1]
        owner.tabs.remove(at: 1)

        #expect(held.title.isEmpty)
        #expect(held.location == "unknown")
        #expect(((held.value(forKey: "scriptingProperties") as? [String: Any])?["title"] as? String)?.isEmpty == true)
    }
}
