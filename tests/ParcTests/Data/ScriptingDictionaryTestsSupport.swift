import AppKit
import Testing
@testable import Parc

@Suite(.serialized)
@MainActor
enum ScriptingDictionaryTestsSupport {
    @MainActor
    enum ScriptingDictionary {
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
    enum AppleEvents {
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
    final class ScriptingApplication: NSObject, NSApplicationDelegate, BrowserPrivateScriptFactory {
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

    typealias Owner = BrowserScriptingTests.Owner

    static func tab(_ owner: Owner, _ title: String, loading: Bool = false, location: String = "unpinned",
                     profile: UUID? = nil) -> ScriptTabRecord {
        ScriptTabRecord(id: UUID(), profileID: profile ?? owner.profile, title: title,
                        url: "https://example.test/\(title.lowercased())", loading: loading, location: location)
    }

    static func command(_ event: String, arguments: [String: Any]? = nil) throws -> BrowserScriptingTests.ObservedCommand {
        let description = try #require(NSScriptSuiteRegistry.shared().commandDescription(
            withAppleEventClass: AppleEvents.code(String(event.prefix(4))), andAppleEventCode: AppleEvents.code(String(event.suffix(4)))))
        let command = BrowserScriptingTests.ObservedCommand(commandDescription: description)
        command.parameters = arguments
        return command
    }
}
