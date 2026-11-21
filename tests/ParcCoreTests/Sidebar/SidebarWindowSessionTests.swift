import Combine
import Foundation
import Testing
@testable import ParcCore

@MainActor
struct SidebarWindowSessionTests {
    private struct LegacyDatedRecord: Encodable {
        let sidebarWidth: Double
        let itemLastActiveDates: [UUID: Date]
    }

    private struct OlderParcWindowRecord: Decodable {
        let sidebarWidth: Double?
        let id: UUID?
        let focusedSpaceID: UUID?
        let selectedTabIDs: [UUID]?
        let focusedTabID: UUID?
        let sidebarHidden: Bool?
        let stayOnTop: Bool?
    }

    static func frame(_ x: Double, _ y: Double, _ width: Double, _ height: Double) -> SavedWindowFrame {
        SavedWindowFrame(x: x, y: y, width: width, height: height)!
    }

    func frame(_ x: Double, _ y: Double, _ width: Double, _ height: Double) -> SavedWindowFrame { Self.frame(x, y, width, height) }

    func record(_ width: SidebarWindowWidth) -> BrowserWindowRecord { BrowserWindowRecord(sidebarWidth: width.width) }

    @MainActor final class Directory {
        let url: URL
        let file: URL
        init() throws {
            url = FileManager.default.temporaryDirectory.appendingPathComponent("parc-window-session-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
            file = url.appendingPathComponent("session.json")
        }
        deinit { try? FileManager.default.removeItem(at: url) }

        func json() throws -> [String: Any] {
            try #require(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        }
    }

    @Test func theRecordEncodesAndRoundTripsItsWidth() throws {
        let encoded = try JSONEncoder().encode(BrowserWindowRecord(sidebarWidth: 312))
        #expect((try JSONSerialization.jsonObject(with: encoded) as? [String: Any])?["sidebarWidth"] as? Double == 312)
        #expect(try JSONDecoder().decode(BrowserWindowRecord.self, from: encoded).sidebarWidth == 312)
    }

    @Test func olderRecordsDecodeWithDefaultsAndKeepASavedWidth() throws {
        #expect(try JSONDecoder().decode(BrowserWindowRecord.self, from: Data("{}".utf8)).sidebarWidth == 228)
        #expect(try !JSONDecoder().decode(BrowserWindowRecord.self, from: Data("{}".utf8)).stayOnTop)
        #expect(try JSONDecoder().decode(BrowserWindowRecord.self, from: Data(#"{"sidebarWidth":900}"#.utf8)).sidebarWidth == 900)
    }

    @Test func theAutosaveHolderComesFirstThenFrontToBackThenOpeningOrder() {
        let order = BrowserWindowRecord.sessionOrder
        #expect(order([false, true, false], [0, 2, 1]) == [1, 0, 2])
        #expect(order([false, false, false], [nil, 1, 0]) == [2, 1, 0])
        #expect(order([false, false], [nil, nil]) == [0, 1])
        #expect(order([], []).isEmpty)
        #expect(order([true], [nil]) == [0])
    }

    @Test func aFrameAddsOneKeyToTheRecordAndLeavesEveryOlderKeyAsItWas() throws {
        let framedRecord = BrowserWindowRecord(sidebarWidth: 300, id: UUID(), stayOnTop: true, frame: frame(120, 80, 1100, 760))
        let framedJSON = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(framedRecord)) as? [String: Any])
        var frameless = framedRecord
        frameless.frame = nil
        let framelessJSON = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(frameless)) as? [String: Any])
        var strippedJSON = framedJSON
        strippedJSON.removeValue(forKey: "frame")
        #expect(framedJSON["frame"] as? [String: Double] == ["x": 120, "y": 80, "width": 1100, "height": 760])
        #expect(NSDictionary(dictionary: strippedJSON).isEqual(to: framelessJSON))
    }

    @Test func theRecordRoundTripsItsFrameAndAnOlderRecordDecodesWithNone() throws {
        let framedRecord = BrowserWindowRecord(sidebarWidth: 300, id: UUID(), stayOnTop: true, frame: frame(120, 80, 1100, 760))
        #expect(try JSONDecoder().decode(BrowserWindowRecord.self, from: JSONEncoder().encode(framedRecord)) == framedRecord)
        #expect(try JSONDecoder().decode(BrowserWindowRecord.self, from: Data(#"{"sidebarWidth":300}"#.utf8)).frame == nil)
    }

    @Test func anOlderParcsRecordDecodingReadsTheNewerRecordAndIgnoresTheFrame() throws {
        let framedRecord = BrowserWindowRecord(sidebarWidth: 300, id: UUID(), stayOnTop: true, frame: frame(120, 80, 1100, 760))
        let older = try JSONDecoder().decode(OlderParcWindowRecord.self, from: JSONEncoder().encode(framedRecord))
        #expect(older.sidebarWidth == 300)
        #expect(older.id == framedRecord.id)
        #expect(older.stayOnTop == true)
    }

    @Test(arguments: [
        #""frame":"wide""#, #""frame":null"#, #""frame":[1,2,3,4]"#, #""frame":{"x":1,"y":2,"width":5}"#,
        #""frame":{"x":1,"y":2,"width":-5,"height":9}"#, #""frame":{"x":1,"y":2,"width":5,"height":0}"#,
        #""frame":{"x":1e400,"y":2,"width":5,"height":9}"#, #""frame":{"x":1e300,"y":2,"width":5,"height":9}"#,
        #""frame":{"x":"1","y":2,"width":5,"height":9}"#,
    ])
    func anUnusableFrameIsDroppedWithoutLosingTheRestOfTheRecord(damaged: String) throws {
        let decoded = try JSONDecoder().decode(BrowserWindowRecord.self,
                                               from: Data((#"{"sidebarWidth":300,"stayOnTop":true,"# + damaged + "}").utf8))
        #expect(decoded.frame == nil)
        #expect(decoded.sidebarWidth == 300)
        #expect(decoded.stayOnTop)
    }

    @Test func onceTheFirstWindowClosesTheFrontWindowsRecordLeadsWithItsOwnFrameAndWidth() {
        let frames = [frame(0, 90, 1200, 800), frame(1600, -100, 1400, 900), frame(300, 200, 900, 700)]
        let widths = [228.0, 310, 260]
        let liveAfterHolderClosed = [1, 2]
        let order = BrowserWindowRecord.sessionOrder
        let fallbackOrder = order(liveAfterHolderClosed.map { _ in false }, [1, 0])
        let fallbackRecords = fallbackOrder.map { liveAfterHolderClosed[$0] }
            .map { BrowserWindowRecord(sidebarWidth: widths[$0], id: UUID(), frame: frames[$0]) }
        #expect(fallbackRecords.first?.frame == frames[2])
        #expect(fallbackRecords.first?.sidebarWidth == 260)
    }

    @Test func aSessionSavesItsWindowRecordsAndAnOlderSessionWithoutThemReopensAtTheLastUsedWidth() throws {
        let d = try Directory()
        let store = try BrowserStore(directory: d.url)
        store.updateSettings { $0.sidebarWidth = 250 }
        try store.save()
        var json = try d.json()
        #expect((json["windows"] as? [Any])?.isEmpty == true)
        json.removeValue(forKey: "windows")
        try JSONSerialization.data(withJSONObject: json).write(to: d.file)
        let migrated = try BrowserStore(directory: d.url)
        #expect(migrated.windowRecords.isEmpty)
        #expect(SidebarWindowWidth(lastUsed: migrated.state.settings.sidebarWidth,
                                   restored: migrated.windowRecords.first?.sidebarWidth).width == 250)
    }

    func waitFor(_ condition: () throws -> Bool) async throws {
        let deadline = Date().addingTimeInterval(30)
        while Date() < deadline {
            if try condition() { return }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    struct TwoWindows {
        var first: SidebarWindowWidth
        var second: SidebarWindowWidth
        var lastUsed: Double

        init() {
            first = SidebarWindowWidth(lastUsed: 250, restored: 320)
            second = SidebarWindowWidth(lastUsed: 250)
            lastUsed = 250
            var gesture = SidebarResizeGesture(width: second.width, locked: true)
            _ = gesture.change(translationX: -40, velocityX: 0, now: 0)
            if let written = second.end(gesture.end(.ended, translationX: -40), .ended) { lastUsed = written }
        }
    }

    @Test func newRecordsUpdateTheStorePublishNothingAndScheduleTheSessionSave() async throws {
        let d = try Directory()
        let store = try BrowserStore(directory: d.url)
        let w = TwoWindows()
        store.updateSettings { $0.sidebarWidth = w.lastUsed }
        try store.save()
        var published = 0
        let subscription = store.statePublisher.dropFirst().sink { _ in published += 1 }
        let settingsUpdates = published
        store.updateWindowRecords([record(w.first), record(w.second)])
        #expect(store.windowRecords.map(\.sidebarWidth) == [320, 210])
        #expect(published == settingsUpdates)
        #expect(store.state.windows.isEmpty)
        try await waitFor { ((try d.json())["windows"] as? [[String: Any]])?.compactMap { $0["sidebarWidth"] as? Double } == [320, 210] }
        let written = try d.json()
        #expect((written["windows"] as? [[String: Any]])?.compactMap { $0["sidebarWidth"] as? Double } == [320, 210])
        let updates = published
        store.updateWindowRecords([record(w.first), record(w.second)])
        #expect(published == updates)
        subscription.cancel()
    }

    @Test func cancelAndCollapseWriteNoLastUsedWidthAndNoRecord() throws {
        let d = try Directory()
        let store = try BrowserStore(directory: d.url)
        var w = TwoWindows()
        store.updateWindowRecords([record(w.first), record(w.second)])
        var published = 0
        let subscription = store.statePublisher.dropFirst().sink { _ in published += 1 }
        let updates = published
        for completion in [SidebarResizeGesture.Completion.cancelled, .ended] {
            var drag = SidebarResizeGesture(width: w.first.width, locked: true)
            _ = drag.change(translationX: completion == .ended ? -300 : 60, velocityX: 0, now: 0)
            let written = w.first.end(drag.end(completion, translationX: completion == .ended ? -300 : 60), completion)
            #expect(written == nil)
            store.updateWindowRecords([record(w.first), record(w.second)])
        }
        #expect(published == updates)
        #expect(w.first.width == 320)
        subscription.cancel()
    }

    @Test func eachWindowsWidthSurvivesARelaunchInOrderBesideTheLastUsedWidth() throws {
        let d = try Directory()
        let store = try BrowserStore(directory: d.url)
        let w = TwoWindows()
        store.updateSettings { $0.sidebarWidth = w.lastUsed }
        store.updateWindowRecords([record(w.first), record(w.second)])
        try store.save()
        let relaunched = try BrowserStore(directory: d.url)
        #expect(relaunched.windowRecords == [BrowserWindowRecord(sidebarWidth: 320), BrowserWindowRecord(sidebarWidth: 210)])
        #expect(relaunched.state.windows.isEmpty)
        #expect(relaunched.state.settings.sidebarWidth == 210)
        #expect(SidebarWindowWidth(lastUsed: relaunched.state.settings.sidebarWidth,
                                   restored: relaunched.windowRecords.first?.sidebarWidth).width == 320)
        #expect(SidebarWindowWidth(lastUsed: relaunched.state.settings.sidebarWidth).width == 210)
    }

    struct Dated {
        let tabID = UUID(), otherTabID = UUID()
        let date = Date(timeIntervalSince1970: 1_700_000_000.125)
        let firstID = UUID(), secondID = UUID(), spaceID = UUID()
        var records: [BrowserWindowRecord] {
            [BrowserWindowRecord(sidebarWidth: 320, itemLastActiveDates: [tabID: date], id: firstID,
                                 focusedSpaceID: spaceID, selectedTabIDs: [tabID], focusedTabID: tabID,
                                 sidebarHidden: true, stayOnTop: true),
             BrowserWindowRecord(sidebarWidth: 210, itemLastActiveDates: [otherTabID: date.addingTimeInterval(10)],
                                 id: secondID, focusedSpaceID: spaceID, selectedTabIDs: [otherTabID],
                                 focusedTabID: otherTabID, sidebarHidden: false)]
        }
    }

    @Test func aLiveWindowReplacesOnlyItsExactSavedIdentityAndKeepsOtherAndOlderRecords() {
        let dated = Dated().records
        var updatedFirst = dated[0]
        updatedFirst.sidebarWidth = 325
        let legacyWithoutID = BrowserWindowRecord(sidebarWidth: 275)
        #expect(BrowserWindowRecord.preservingUnrestored(live: [updatedFirst], unrestored: dated + [legacyWithoutID])
                == [updatedFirst, dated[1], legacyWithoutID])
        #expect(BrowserWindowRecord.preservingUnrestored(live: [], unrestored: dated) == dated)
    }

    @Test func eachWindowsIdentityPresentationAndActivityDatesSurviveTheRealSessionStoreAndLaterWrites() throws {
        let d = try Directory()
        let store = try BrowserStore(directory: d.url)
        let dated = Dated().records
        store.updateWindowRecords(dated)
        try store.save()
        #expect(try BrowserStore(directory: d.url).windowRecords == dated)
        store.updateSettings { $0.sidebarWidth = 230 }
        try store.save()
        #expect(try BrowserStore(directory: d.url).windowRecords == dated)
    }

    @Test func theEarlierISO8601ActivityDatesRemainReadable() throws {
        let tabID = UUID()
        let legacyEncoder = JSONEncoder()
        legacyEncoder.dateEncodingStrategy = .iso8601
        let legacyDecoder = JSONDecoder()
        legacyDecoder.dateDecodingStrategy = .iso8601
        let legacyDate = Date(timeIntervalSince1970: 1_700_000_000)
        let legacy = LegacyDatedRecord(sidebarWidth: 220, itemLastActiveDates: [tabID: legacyDate])
        #expect(try legacyDecoder.decode(BrowserWindowRecord.self, from: legacyEncoder.encode(legacy))
                == BrowserWindowRecord(sidebarWidth: 220, itemLastActiveDates: [tabID: legacyDate]))
    }

    func framedRecords() -> [BrowserWindowRecord] {
        [BrowserWindowRecord(sidebarWidth: 310, id: UUID(), frame: frame(1600, -100, 1400, 900)),
         BrowserWindowRecord(sidebarWidth: 240, id: UUID(), sidebarHidden: true, frame: frame(40, 60, 1200, 800))]
    }

    @Test func eachWindowsFrameSurvivesARelaunchBesideItsOwnWidth() throws {
        let d = try Directory()
        let store = try BrowserStore(directory: d.url)
        let framed = framedRecords()
        store.updateWindowRecords(framed)
        try store.save()
        let reopened = try BrowserStore(directory: d.url)
        #expect(reopened.windowRecords == framed)
        #expect(reopened.windowRecords.first?.frame == framed[0].frame)
        #expect(reopened.windowRecords.first?.sidebarWidth == 310)
    }

    @Test func aFileAnOlderParcSavedBackLoadsWithoutFramesAndKeepsEverythingElse() throws {
        let d = try Directory()
        let store = try BrowserStore(directory: d.url)
        let framed = framedRecords()
        store.updateWindowRecords(framed)
        try store.save()
        let json = try d.json()
        var rewritten = json
        rewritten["windows"] = (json["windows"] as! [[String: Any]]).map { record -> [String: Any] in
            var older = record
            older.removeValue(forKey: "frame")
            return older
        }
        try JSONSerialization.data(withJSONObject: rewritten).write(to: d.file)
        let downgraded = try BrowserStore(directory: d.url)
        #expect(downgraded.windowRecords.allSatisfy { $0.frame == nil })
        #expect(downgraded.windowRecords.map(\.sidebarWidth) == [310, 240])
        #expect(downgraded.windowRecords.map(\.id) == framed.map(\.id))
        #expect(downgraded.windowRecords[1].sidebarHidden == true)
    }

    @Test func aDamagedFrameNeverMakesTheSavedSessionUnreadable() throws {
        let d = try Directory()
        let store = try BrowserStore(directory: d.url)
        try store.save()
        var damaged = try d.json()
        damaged["windows"] = [["sidebarWidth": 310, "frame": ["x": 1, "y": 2, "width": 0, "height": 5]],
                              ["sidebarWidth": 240, "frame": "tall"]] as [[String: Any]]
        try JSONSerialization.data(withJSONObject: damaged).write(to: d.file)
        #expect(try BrowserStore(directory: d.url).windowRecords == [BrowserWindowRecord(sidebarWidth: 310), BrowserWindowRecord(sidebarWidth: 240)])
    }

    @Test func olderRecordsKeepTheirWidthsAndDefaultMissingActivityDatesToEmptyAndSeedingClampsASavedWidth() throws {
        let d = try Directory()
        let store = try BrowserStore(directory: d.url)
        try store.save()
        var json = try d.json()
        json["windows"] = [["sidebarWidth": 40], [:]] as [[String: Any]]
        try JSONSerialization.data(withJSONObject: json).write(to: d.file)
        let edited = try BrowserStore(directory: d.url)
        #expect(edited.windowRecords.map(\.sidebarWidth) == [40, 228])
        #expect(edited.windowRecords.allSatisfy { $0.itemLastActiveDates.isEmpty })
        #expect(SidebarWindowWidth(lastUsed: 210, restored: edited.windowRecords[0].sidebarWidth).width == 164)
    }

    @Test func aPrivateStoreKeepsNoWindowRecords() throws {
        let d = try Directory()
        let store = try BrowserStore(directory: d.url)
        let incognito = BrowserStore(privateParentProfileID: store.activeSpace.profileID, engineProfilePath: "/tmp/parc-test",
                                     directory: d.url, settings: store.state.settings)
        incognito.updateWindowRecords([BrowserWindowRecord(sidebarWidth: 400)])
        #expect(incognito.windowRecords.isEmpty)
    }
}
