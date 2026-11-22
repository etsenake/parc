import AppKit
import Testing
@testable import Parc

extension ScriptingDictionaryTestsSupport {
    @MainActor
    struct ScriptingDictionaryTabPropertiesTests {
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

        private func listedOwner() -> (Owner, docs: ScriptTabRecord, news: ScriptTabRecord, work: ScriptSpaceRecord) {
            let owner = Owner()
            let work = ScriptSpaceRecord(id: UUID(), profileID: owner.profile, title: "Work")
            owner.extraSpaces = [work]
            let docs = tab(owner, "Docs", loading: true, location: "pinned")
            let news = tab(owner, "News", location: "topApp")
            owner.tabs = [docs, news]
            return (owner, docs, news, work)
        }

        enum Addressed: CaseIterable { case idInWindow, idInSpace, activeTab }

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

        struct SpaceTitle: CustomTestStringConvertible, Sendable {
            let testDescription: String
            let title: String
            let found: Bool

            static let cases: [Self] = [
                .init(testDescription: "Existing Space", title: "Work", found: true),
                .init(testDescription: "Missing Space", title: "Missing", found: false),
            ]
        }

        @Test(arguments: SpaceTitle.cases)
        func focusReachesOnlyASpaceNamedByItsTitle(_ sample: SpaceTitle) throws {
            let (owner, _, _, work) = listedOwner()
            let application = ScriptingApplication(owners: [owner])
            let window = AppleEvents.identified("WiND", owner.scriptingID)

            try application.run { _ in
                _ = AppleEvents.perform("SpaFocus", on: AppleEvents.reference("sPaC", "name", NSAppleEventDescriptor(string: sample.title), in: window))
            }

            #expect(owner.focused == (sample.found ? work.id : nil))
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

        struct TabProperty: CustomTestStringConvertible, Sendable {
            let testDescription: String
            let property: String
            let readsEachTab: Bool

            static let cases: [Self] = [
                .init(testDescription: "ID skips tab lookup", property: "ID  ", readsEachTab: false),
                .init(testDescription: "Name reads each tab", property: "pnam", readsEachTab: true),
            ]
        }

        @Test(arguments: TabProperty.cases)
        func onePropertyOfEveryTabListsOnceInWindowOrder(_ sample: TabProperty) throws {
            let owner = bulkOwner()
            let application = ScriptingApplication(owners: [owner])
            let window = AppleEvents.identified("WiND", owner.scriptingID)

            let result = try application.run { _ in
                counted(owner) { AppleEvents.get(AppleEvents.property(sample.property, of: AppleEvents.everyTab(in: window))) }
            }

            let expected = owner.tabs.map { sample.property == "pnam" ? $0.title : $0.id.uuidString }
            #expect(AppleEvents.items(result.reply).map(\.stringValue) == expected.map(Optional.some))
            #expect(result.passes == 1)
            #expect(result.lookups == (sample.readsEachTab ? owner.tabs.count : 0))
        }

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

        struct TabAddress: CustomTestStringConvertible, Sendable {
            let testDescription: String
            let inSpace: Bool
            let padded: Bool

            static let cases: [Self] = [
                .init(testDescription: "Numeric ID in window", inSpace: false, padded: false),
                .init(testDescription: "Padded ID in window", inSpace: false, padded: true),
                .init(testDescription: "Numeric ID in Space", inSpace: true, padded: false),
                .init(testDescription: "Padded ID in Space", inSpace: true, padded: true),
            ]
        }

        @Test(arguments: TabAddress.cases)
        func anIDThatIsNotATabIdentityKeepsCocoasComparisonOverTheList(_ sample: TabAddress) throws {
            let owner = bulkOwner()
            let window = ParcScriptWindow(owner: owner)
            let space = try #require(window.appleScriptSpaces.first)
            let id: Any = sample.padded ? " " + owner.tabs[3].id.uuidString : NSNumber(value: 5)

            let result = counted(owner) {
                sample.inSpace ? space.valueInAppleScriptTabs(withUniqueID: id) : window.valueInAppleScriptTabs(withUniqueID: id)
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
}
