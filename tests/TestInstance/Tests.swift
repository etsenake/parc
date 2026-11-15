import CoreGraphics
import Foundation

@main
struct TestInstanceTests {
    static var assertions = 0
    static func check(_ value: @autoclosure () -> Bool, _ label: String) {
        assertions += 1
        precondition(value(), label)
    }

    static func main() throws {
        let plain = TestInstance(arguments: ["Parc", "--parc-profile", "/tmp/profile", "--window-size=1280,800"])
        check(!plain.isActive && plain.perfMarksPath == nil && !plain.placesFirstWindow, "Without the switch nothing changes")
        check(TestInstance(arguments: []) == TestInstance(arguments: ["Parc"]), "Missing argv")
        let harness = TestInstance(arguments: [
            "Parc", "--parc-profile", "/tmp/run/profile", "--parc-test-instance", "--parc-perf-marks", "/tmp/run/marks.jsonl",
            "--remote-debugging-port=9333", "--remote-allow-origins=*", "--mute-audio", "--use-mock-keychain",
            "--window-size=1280,800", "--window-position=40,80"])
        check(harness.isActive && harness.placesFirstWindow, "Harness launch is a test instance that places its window")
        check(harness.perfMarksPath == "/tmp/run/marks.jsonl", "Separate marks operand")
        check(harness.windowSize == CGSize(width: 1280, height: 800), "Chromium window size")
        check(harness.windowPosition == CGPoint(x: 40, y: 80), "Chromium window position")
        check(TestInstance(arguments: ["Parc", "--parc-perf-marks=/tmp/m.jsonl"]).perfMarksPath == "/tmp/m.jsonl", "Joined marks operand")
        check(TestInstance(arguments: ["Parc", "--parc-perf-marks", "--parc-test-instance"]).perfMarksPath == nil, "Missing marks operand")
        check(TestInstance(arguments: ["Parc", "--parc-perf-marks="]).perfMarksPath == nil, "Empty marks operand")
        check(!TestInstance(arguments: ["Parc", "--", "--parc-test-instance"]).isActive, "Switch terminator")
        let malformed = TestInstance(arguments: ["Parc", "--parc-test-instance", "--window-size=0,800",
                                                 "--window-position=40", "--window-size=wide,tall"])
        check(malformed.windowSize == nil && malformed.windowPosition == nil && !malformed.placesFirstWindow, "Malformed geometry ignored")
        let screen = CGRect(x: 0, y: 0, width: 1728, height: 1117)
        let current = CGRect(x: 224, y: 138, width: 1280, height: 840)
        check(harness.firstWindowFrame(from: current, primaryScreen: screen) == CGRect(x: 40, y: 237, width: 1280, height: 800),
              "Top-left origin of the primary screen, like Chrome")
        let sized = TestInstance(arguments: ["Parc", "--parc-test-instance", "--window-size=1000,700"])
        check(sized.firstWindowFrame(from: current, primaryScreen: screen) == CGRect(x: 224, y: 278, width: 1000, height: 700),
              "Size alone keeps the top-left corner")
        let negative = TestInstance(arguments: ["Parc", "--parc-test-instance", "--window-position=-20,10"])
        check(negative.firstWindowFrame(from: current, primaryScreen: screen) == CGRect(x: -20, y: 267, width: 1280, height: 840),
              "Position alone keeps the size")

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("parc-perf-marks-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("marks.jsonl")
        check(PerfMarks(path: directory.appendingPathComponent("missing/marks.jsonl").path) == nil, "Unwritable path disables marks")
        let marks = try PerfMarks(path: file.path).unwrap()
        let before = Date().timeIntervalSince1970 * 1000
        marks.mark("main")
        marks.mark("tab-select", ["tab": "7C1A", "source": "click"])
        var displayed = false
        marks.markAfterDisplay("command-bar-typeable") { displayed = true; return true }
        marks.markAfterDisplay("never") { false }
        check(!displayed, "Display marks wait for the run loop")
        for _ in 0..<5 { CFRunLoopRunInMode(.defaultMode, 0.01, false) }
        check(displayed, "Display mark ran after the run loop turn")
        let again = try PerfMarks(path: file.path).unwrap()
        again.mark("keydown", ["keyCode": 17, "modifierFlags": 1_048_576])
        let records = try String(contentsOf: file, encoding: .utf8).split(separator: "\n").map {
            try JSONSerialization.jsonObject(with: Data($0.utf8)) as! [String: Any]
        }
        check(records.map { $0["mark"] as? String } == ["main", "tab-select", "command-bar-typeable", "keydown"],
              "One JSON line per mark, appended across opens")
        check(records.allSatisfy { (($0["t"] as? Double) ?? 0) >= before - 1 }, "Epoch milliseconds")
        check(records[1]["tab"] as? String == "7C1A" && records[1]["source"] as? String == "click", "String fields")
        check(records[3]["keyCode"] as? Int == 17 && records[3]["modifierFlags"] as? Int == 1_048_576, "Number fields")
        print("TestInstance: \(assertions) assertions passed")
    }
}

private extension Optional {
    func unwrap() throws -> Wrapped {
        guard let self else { throw CocoaError(.fileNoSuchFile) }
        return self
    }
}
