import AppKit
import Testing
@testable import Parc

extension ScriptingDictionaryTestsSupport {
    @MainActor
    struct ScriptingDictionaryWindowTests {
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

        @Test func anImmediateCloseResumesTheCommandItSuspended() throws {
            try #require(ScriptingDictionary.windowClass != nil)
            let owner = Owner()
            owner.immediateClose = true
            let close = try command("coreclos")

            ParcScriptWindow(owner: owner).close(close)

            #expect(close.suspensions == 1)
            #expect(close.resumptions == 1)
        }

        @Test func aRetiredWindowCannotClose() throws {
            try #require(ScriptingDictionary.windowClass != nil)
            let owner = Owner()
            let window = ParcScriptWindow(owner: owner)
            let close = try command("coreclos")
            owner.scriptingAvailable = false
            window.close(close)
            #expect(close.suspensions == 0)
        }

        @Test func aSpaceInARetiredWindowCannotFocus() throws {
            try #require(ScriptingDictionary.windowClass != nil)
            let owner = Owner()
            let window = ParcScriptWindow(owner: owner)
            let space = try #require(window.appleScriptSpaces.first)
            let close = try command("coreclos")
            owner.scriptingAvailable = false
            space.focus(close)
            #expect(close.suspensions == 0)
            #expect(owner.focused == nil)
        }
    }
}
