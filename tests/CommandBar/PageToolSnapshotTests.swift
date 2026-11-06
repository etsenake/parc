import Foundation

@main
struct PageToolSnapshotTests {
    static var count = 0
    static func check(_ value: @autoclosure () -> Bool, _ message: String) {
        count += 1; precondition(value(), message)
    }
    /// The window's decision: the snapshot while its bar is open, else the engine.
    static func decide(_ snapshot: CommandBarPageToolSnapshot?, tool: Int, openPanel: ObjectIdentifier?,
                       page: ObjectIdentifier, engine: () -> Bool) -> Bool {
        snapshot?.allows(tool, openPanel: openPanel, page: page) ?? engine()
    }
    static func main() {
        let panel = NSObject(), otherPanel = NSObject(), page = NSObject(), otherPage = NSObject()
        let developerTools = 6, cast = 10, taskManager = 11
        let snapshot = CommandBarPageToolSnapshot(panel: ObjectIdentifier(panel), page: ObjectIdentifier(page),
                                                  tools: [developerTools, taskManager])
        let open = ObjectIdentifier(panel)

        // Bar open: the engine refuses (its window isn't key), the snapshot answers.
        check(decide(snapshot, tool: developerTools, openPanel: open, page: ObjectIdentifier(page), engine: { false }),
              "A tool allowed before opening stays available while the bar holds key")
        check(!decide(snapshot, tool: cast, openPanel: open, page: ObjectIdentifier(page), engine: { true }),
              "A tool refused before opening stays refused while the bar is open")
        check(!decide(snapshot, tool: taskManager, openPanel: open, page: ObjectIdentifier(otherPage), engine: { true }),
              "Another page never inherits the snapshot")

        // Bar closed or replaced: only the engine decides, so a refusal there stops the command.
        check(snapshot.allows(developerTools, openPanel: nil, page: ObjectIdentifier(page)) == nil,
              "No open bar: the snapshot doesn't apply")
        check(!decide(snapshot, tool: developerTools, openPanel: nil, page: ObjectIdentifier(page), engine: { false }),
              "After closing, the engine's refusal wins")
        check(decide(snapshot, tool: cast, openPanel: nil, page: ObjectIdentifier(page), engine: { true }),
              "After closing, the engine's current answer is used")
        check(snapshot.allows(developerTools, openPanel: ObjectIdentifier(otherPanel), page: ObjectIdentifier(page)) == nil,
              "A different bar doesn't reuse an earlier bar's snapshot")
        check(!decide(nil, tool: developerTools, openPanel: open, page: ObjectIdentifier(page), engine: { false }),
              "Without a snapshot the engine decides")
        print("PageToolSnapshotTests: \(count) checks passed")
    }
}
