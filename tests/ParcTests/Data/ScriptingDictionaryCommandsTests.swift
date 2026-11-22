import AppKit
import Testing
@testable import Parc

extension ScriptingDictionaryTestsSupport {
    @MainActor
    struct ScriptingDictionaryCommandsTests {
        private func executing(_ owner: Owner, _ arguments: [String: Any] = ["javascript": "document.title"]) throws
            -> BrowserScriptingTests.ObservedCommand {
            try #require(ScriptingDictionary.windowClass != nil)
            owner.tabs = [tab(owner, "Page")]
            let script = try command("CrSuExJa", arguments: arguments)
            try #require(ParcScriptWindow(owner: owner).activeTab).executeJavascript(script)
            return script
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
    }
}
