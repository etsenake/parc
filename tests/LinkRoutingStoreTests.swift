import Foundation

@main
struct LinkRoutingStoreTests {
    @MainActor
    static func main() { exitOnFailure(runChecks) }
    @MainActor
    static func runChecks() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("link-routing.json")
        let original = Data("unreadable routes".utf8)
        try original.write(to: file)

        let store = LinkRoutingStore(directory: directory)
        let unreadableMessage = store.errorMessage
        precondition(unreadableMessage != nil)
        precondition(!store.save(LinkRoute()))
        var valid = LinkRoute()
        valid.conditions[0].pattern = "example.com"
        precondition(!store.save(valid))
        precondition(store.errorMessage == unreadableMessage)
        let preserved = try Data(contentsOf: file)
        precondition(preserved == original)
        precondition(store.state.rules.isEmpty)
        print("LinkRoutingStore unreadable-file preservation passed")

        let liveDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: liveDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: liveDirectory) }
        let liveFile = liveDirectory.appendingPathComponent("link-routing.json")
        let live = LinkRoutingStore(directory: liveDirectory)
        var rule = LinkRoute()
        rule.conditions[0].pattern = "parc.example"
        precondition(live.save(rule))
        let written = try Data(contentsOf: liveFile)
        let firstAttrs = try FileManager.default.attributesOfItem(atPath: liveFile.path)
        let firstModified = firstAttrs[.modificationDate] as! Date
        precondition(live.save(rule))
        let again = try Data(contentsOf: liveFile)
        precondition(again == written, "Identical link-routing recommit must keep pretty JSON bytes")
        let secondAttrs = try FileManager.default.attributesOfItem(atPath: liveFile.path)
        let secondModified = secondAttrs[.modificationDate] as! Date
        precondition(secondModified == firstModified, "Identical link-routing recommit must skip atomic rewrite")
        var other = LinkRoute()
        other.conditions[0].pattern = "other.example"
        precondition(live.save(other))
        let changed = try Data(contentsOf: liveFile)
        precondition(changed != written, "Changed link-routing must still rewrite pretty JSON")
        precondition(live.state.rules.map(\.conditions[0].pattern) == ["parc.example", "other.example"])
        print("LinkRoutingStore identical-byte persist skip passed")
    }
}
