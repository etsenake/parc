import Combine
import Foundation

@main @MainActor struct SidebarWindowSessionTests {
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
        guard let frame = SavedWindowFrame(x: x, y: y, width: width, height: height) else { fatalError("bad fixture") }
        return frame
    }
    static var count = 0
    static func check(_ value: @autoclosure () throws -> Bool, _ message: String) rethrows {
        count += 1
        guard try value() else { fatalError("SidebarWindowSession: \(message)") }
    }
    static func record(_ width: SidebarWindowWidth) -> BrowserWindowRecord { BrowserWindowRecord(sidebarWidth: width.width) }
    static func withDirectory(_ body: (URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("parc-window-session-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(directory)
    }
    static func main() { exitOnFailure(runChecks) }
    static func runChecks() throws {
        let encoded = try JSONEncoder().encode(BrowserWindowRecord(sidebarWidth: 312))
        try check((try JSONSerialization.jsonObject(with: encoded) as? [String: Any])?["sidebarWidth"] as? Double == 312, "the record encodes its width")
        try check(try JSONDecoder().decode(BrowserWindowRecord.self, from: encoded).sidebarWidth == 312, "the record round-trips")
        try check(try JSONDecoder().decode(BrowserWindowRecord.self, from: Data("{}".utf8)).sidebarWidth == 228,
                  "a record without a width decodes as 228")
        try check(try !JSONDecoder().decode(BrowserWindowRecord.self, from: Data("{}".utf8)).stayOnTop,
                  "older records default stay on top to false")
        try check(try JSONDecoder().decode(BrowserWindowRecord.self, from: Data(#"{"sidebarWidth":900}"#.utf8)).sidebarWidth == 900,
                  "decoding keeps the saved value; seeding clamps it")

        let order = BrowserWindowRecord.sessionOrder
        check(order([false, true, false], [0, 2, 1]) == [1, 0, 2], "the autosave holder first, though behind the others")
        check(order([false, false, false], [nil, 1, 0]) == [2, 1, 0] && order([false, false], [nil, nil]) == [0, 1],
              "then front to back, then opening order")
        check(order([], []).isEmpty && order([true], [nil]) == [0], "no windows, or only the holder off screen")

        let ownFrame = frame(120, 80, 1100, 760)
        let framedRecord = BrowserWindowRecord(sidebarWidth: 300, id: UUID(), stayOnTop: true, frame: ownFrame)
        let framedJSON = try JSONSerialization.jsonObject(with: JSONEncoder().encode(framedRecord)) as! [String: Any]
        var frameless = framedRecord; frameless.frame = nil
        let framelessJSON = try JSONSerialization.jsonObject(with: JSONEncoder().encode(frameless)) as! [String: Any]
        var strippedJSON = framedJSON; strippedJSON.removeValue(forKey: "frame")
        check(framedJSON["frame"] as? [String: Double] == ["x": 120, "y": 80, "width": 1100, "height": 760]
              && NSDictionary(dictionary: strippedJSON).isEqual(to: framelessJSON),
              "a frame adds one key to the record and leaves every older key as it was")
        try check(try JSONDecoder().decode(BrowserWindowRecord.self, from: JSONEncoder().encode(framedRecord)) == framedRecord,
                  "the record round-trips its frame")
        try check(try JSONDecoder().decode(BrowserWindowRecord.self, from: Data(#"{"sidebarWidth":300}"#.utf8)).frame == nil,
                  "an older record without a frame decodes with none")
        let older = try JSONDecoder().decode(OlderParcWindowRecord.self, from: JSONEncoder().encode(framedRecord))
        check(older.sidebarWidth == 300 && older.id == framedRecord.id && older.stayOnTop == true,
              "an older Parc's record decoding reads the newer record and ignores the frame")
        for damaged in [#""frame":"wide""#, #""frame":null"#, #""frame":[1,2,3,4]"#, #""frame":{"x":1,"y":2,"width":5}"#,
                        #""frame":{"x":1,"y":2,"width":-5,"height":9}"#, #""frame":{"x":1,"y":2,"width":5,"height":0}"#,
                        #""frame":{"x":1e400,"y":2,"width":5,"height":9}"#, #""frame":{"x":1e300,"y":2,"width":5,"height":9}"#,
                        #""frame":{"x":"1","y":2,"width":5,"height":9}"#] {
            let decoded = try JSONDecoder().decode(BrowserWindowRecord.self,
                                                   from: Data((#"{"sidebarWidth":300,"stayOnTop":true,"# + damaged + "}").utf8))
            check(decoded.frame == nil && decoded.sidebarWidth == 300 && decoded.stayOnTop,
                  "an unusable frame is dropped without losing the rest of the record: \(damaged)")
        }

        let frames = [frame(0, 90, 1200, 800), frame(1600, -100, 1400, 900), frame(300, 200, 900, 700)]
        let widths = [228.0, 310, 260]
        let liveAfterHolderClosed = [1, 2]
        let fallbackOrder = order(liveAfterHolderClosed.map { _ in false }, [1, 0])
        let fallbackRecords = fallbackOrder.map { liveAfterHolderClosed[$0] }
            .map { BrowserWindowRecord(sidebarWidth: widths[$0], id: UUID(), frame: frames[$0]) }
        check(fallbackRecords.first?.frame == frames[2] && fallbackRecords.first?.sidebarWidth == 260,
              "once the first window closes, the front window's record leads with its own frame and width")

        try withDirectory { directory in
            let file = directory.appendingPathComponent("session.json")
            let store = try BrowserStore(directory: directory)
            store.updateSettings { $0.sidebarWidth = 250 }
            try store.save()
            var json = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as! [String: Any]
            check((json["windows"] as? [Any])?.isEmpty == true, "a session saves its window records")
            json.removeValue(forKey: "windows")
            try JSONSerialization.data(withJSONObject: json).write(to: file)
            let migrated = try BrowserStore(directory: directory)
            check(migrated.windowRecords.isEmpty, "an older session has no window records")
            check(SidebarWindowWidth(lastUsed: migrated.state.settings.sidebarWidth,
                                     restored: migrated.windowRecords.first?.sidebarWidth).width == 250,
                  "without a record the reopened window takes the last-used width")

            var first = SidebarWindowWidth(lastUsed: 250, restored: 320), second = SidebarWindowWidth(lastUsed: 250)
            var lastUsed = 250.0
            var gesture = SidebarResizeGesture(width: second.width, locked: true)
            _ = gesture.change(translationX: -40, velocityX: 0, now: 0)
            if let written = second.end(gesture.end(.ended, translationX: -40), .ended) { lastUsed = written }
            migrated.updateSettings { $0.sidebarWidth = lastUsed }
            var published = 0
            let subscription = migrated.statePublisher.dropFirst().sink { _ in published += 1 }
            let settingsUpdates = published
            try migrated.save()
            migrated.updateWindowRecords([record(first), record(second)])
            check(migrated.windowRecords.map(\.sidebarWidth) == [320, 210], "new records update the store")
            check(published == settingsUpdates && migrated.state.windows.isEmpty,
                  "records publish nothing, so no window renders for them")
            RunLoop.main.run(until: Date().addingTimeInterval(0.6))
            let written = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as! [String: Any]
            check((written["windows"] as? [[String: Any]])?.compactMap { $0["sidebarWidth"] as? Double } == [320, 210],
                  "a records change schedules the session save")
            let updates = published
            migrated.updateWindowRecords([record(first), record(second)])
            check(published == updates, "unchanged records change nothing")
            for completion in [SidebarResizeGesture.Completion.cancelled, .ended] {
                var drag = SidebarResizeGesture(width: first.width, locked: true)
                _ = drag.change(translationX: completion == .ended ? -300 : 60, velocityX: 0, now: 0)
                check(first.end(drag.end(completion, translationX: completion == .ended ? -300 : 60), completion) == nil,
                      "cancel and collapse write no last-used width")
                migrated.updateWindowRecords([record(first), record(second)])
            }
            check(published == updates && first.width == 320, "cancel and collapse write no record")
            subscription.cancel()
            try migrated.save()

            let relaunched = try BrowserStore(directory: directory)
            check(relaunched.windowRecords == [BrowserWindowRecord(sidebarWidth: 320), BrowserWindowRecord(sidebarWidth: 210)]
                  && relaunched.state.windows.isEmpty, "each window's width survives a relaunch in order")
            check(relaunched.state.settings.sidebarWidth == 210, "the last-used width is saved beside them")
            check(SidebarWindowWidth(lastUsed: relaunched.state.settings.sidebarWidth,
                                     restored: relaunched.windowRecords.first?.sidebarWidth).width == 320,
                  "the reopened window takes its own width, not the last-used one")
            check(SidebarWindowWidth(lastUsed: relaunched.state.settings.sidebarWidth).width == 210,
                  "a new window takes the last-used width")
            let tabID = UUID(), otherTabID = UUID(), date = Date(timeIntervalSince1970: 1_700_000_000.125)
            let firstID = UUID(), secondID = UUID(), spaceID = UUID()
            let dated = [BrowserWindowRecord(sidebarWidth: 320, itemLastActiveDates: [tabID: date], id: firstID,
                                             focusedSpaceID: spaceID, selectedTabIDs: [tabID], focusedTabID: tabID,
                                             sidebarHidden: true, stayOnTop: true),
                         BrowserWindowRecord(sidebarWidth: 210, itemLastActiveDates: [otherTabID: date.addingTimeInterval(10)],
                                             id: secondID, focusedSpaceID: spaceID, selectedTabIDs: [otherTabID],
                                             focusedTabID: otherTabID, sidebarHidden: false)]
            var updatedFirst = dated[0]; updatedFirst.sidebarWidth = 325
            let legacyWithoutID = BrowserWindowRecord(sidebarWidth: 275)
            check(BrowserWindowRecord.preservingUnrestored(live: [updatedFirst], unrestored: dated + [legacyWithoutID])
                  == [updatedFirst, dated[1], legacyWithoutID],
                  "a live window replaces only its exact saved identity and keeps other and older records")
            check(BrowserWindowRecord.preservingUnrestored(live: [], unrestored: dated) == dated,
                  "failure to create a window retains the unopened records")
            relaunched.updateWindowRecords(dated)
            try relaunched.save()
            try check(try BrowserStore(directory: directory).windowRecords == dated,
                      "each window's identity, presentation and activity dates survive the real session store")
            let legacyEncoder = JSONEncoder(); legacyEncoder.dateEncodingStrategy = .iso8601
            let legacyDecoder = JSONDecoder(); legacyDecoder.dateDecodingStrategy = .iso8601
            let legacyDate = Date(timeIntervalSince1970: 1_700_000_000)
            let legacy = LegacyDatedRecord(sidebarWidth: 220, itemLastActiveDates: [tabID: legacyDate])
            try check(try legacyDecoder.decode(BrowserWindowRecord.self, from: legacyEncoder.encode(legacy))
                == BrowserWindowRecord(sidebarWidth: 220, itemLastActiveDates: [tabID: legacyDate]),
                "the earlier ISO-8601 activity dates remain readable")
            relaunched.updateSettings { $0.sidebarWidth = 230 }
            try relaunched.save()
            try check(try BrowserStore(directory: directory).windowRecords == dated,
                      "a later session write keeps the records")

            let framed = [BrowserWindowRecord(sidebarWidth: 310, id: UUID(), frame: frame(1600, -100, 1400, 900)),
                          BrowserWindowRecord(sidebarWidth: 240, id: UUID(), sidebarHidden: true, frame: frame(40, 60, 1200, 800))]
            relaunched.updateWindowRecords(framed)
            try relaunched.save()
            let reopened = try BrowserStore(directory: directory)
            check(reopened.windowRecords == framed, "each window's frame survives a relaunch beside its own width")
            check(reopened.windowRecords.first?.frame == framed[0].frame && reopened.windowRecords.first?.sidebarWidth == 310,
                  "the fallback window's frame and width come from the same saved window")
            json = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as! [String: Any]
            var rewritten = json
            rewritten["windows"] = (json["windows"] as! [[String: Any]]).map { record -> [String: Any] in
                var older = record; older.removeValue(forKey: "frame"); return older
            }
            try JSONSerialization.data(withJSONObject: rewritten).write(to: file)
            let downgraded = try BrowserStore(directory: directory)
            check(downgraded.windowRecords.allSatisfy { $0.frame == nil }
                  && downgraded.windowRecords.map(\.sidebarWidth) == [310, 240]
                  && downgraded.windowRecords.map(\.id) == framed.map(\.id) && downgraded.windowRecords[1].sidebarHidden == true,
                  "a file an older Parc saved back loads without frames and keeps everything else")
            var damaged = json
            damaged["windows"] = [["sidebarWidth": 310, "frame": ["x": 1, "y": 2, "width": 0, "height": 5]],
                                  ["sidebarWidth": 240, "frame": "tall"]] as [[String: Any]]
            try JSONSerialization.data(withJSONObject: damaged).write(to: file)
            try check(try BrowserStore(directory: directory).windowRecords
                      == [BrowserWindowRecord(sidebarWidth: 310), BrowserWindowRecord(sidebarWidth: 240)],
                      "a damaged frame never makes the saved session unreadable")
            try JSONSerialization.data(withJSONObject: json).write(to: file)

            json = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as! [String: Any]
            json["windows"] = [["sidebarWidth": 40], [:]] as [[String: Any]]
            try JSONSerialization.data(withJSONObject: json).write(to: file)
            let edited = try BrowserStore(directory: directory)
            check(edited.windowRecords.map(\.sidebarWidth) == [40, 228] && edited.windowRecords.allSatisfy { $0.itemLastActiveDates.isEmpty }, "older records keep their widths and default missing activity dates to empty")
            check(SidebarWindowWidth(lastUsed: 210, restored: edited.windowRecords[0].sidebarWidth).width == 164, "seeding clamps a saved width")

            let incognito = BrowserStore(privateParentProfileID: relaunched.activeSpace.profileID, engineProfilePath: "/tmp/parc-test",
                                         directory: directory, settings: relaunched.state.settings)
            incognito.updateWindowRecords([BrowserWindowRecord(sidebarWidth: 400)])
            check(incognito.windowRecords.isEmpty, "a private store keeps no window records")
        }
        print("SidebarWindowSession: \(count) assertions passed")
    }
}
