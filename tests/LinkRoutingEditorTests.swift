import Foundation

@main
struct LinkRoutingEditorTests {
    @MainActor static func main() { exitOnFailure(runChecks) }
    @MainActor static func runChecks() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = LinkRoutingStore(directory: directory)
        var first = LinkRoute(); first.conditions[0].pattern = "first.example"
        var incomplete = LinkRoute(); incomplete.conditions.append(LinkRouteCondition(pattern: "other.example"))
        var last = LinkRoute(); last.conditions[0].pattern = "last.example"
        precondition(store.commitEditor([first, incomplete, last], basedOn: []))
        var completed = incomplete; completed.conditions.removeFirst()
        precondition(store.state.rules == [first, completed, last])
        var savedRoute = LinkRoute(); savedRoute.conditions[0].pattern = "youtube.com"
        var typing = savedRoute; typing.conditions[0].pattern = "you"; typing.destination = .space(UUID())
        let added = LinkRouteCondition(pattern: "watch"), blank = LinkRouteCondition(pattern: "  ")
        typing.conditions += [added, blank]
        var held = typing; held.conditions = [savedRoute.conditions[0]]
        precondition(LinkRoutingDraft.savable([typing, LinkRoute()], editing: [typing.conditions[0].id, added.id],
                                              saved: [savedRoute]) == [held])
        var finished = typing; finished.conditions.removeLast()
        precondition(LinkRoutingDraft.savable([typing], saved: [savedRoute]) == [finished])
        let baseline = store.state.rules
        var peer = LinkRoute(); peer.conditions[0].pattern = "peer.example"
        precondition(store.save(peer))
        let recent = UUID(); store.noteVisitedSpace(recent)
        let current = store.state.rules
        precondition(store.commitEditor(baseline + [LinkRoute()], basedOn: baseline))
        precondition(store.state.rules == current)
        precondition(!store.commitEditor([last], basedOn: baseline))
        precondition(!store.reset(basedOn: baseline))
        precondition(store.state.rules == current)
        precondition(store.state.recentSpaceIDs == [recent])
        let restored = LinkRoutingStore(directory: directory)
        precondition(restored.state.rules == current)
        precondition(restored.state.recentSpaceIDs == [recent])
        precondition(store.reset(basedOn: current))
        precondition(store.state.rules.isEmpty && store.state.recentSpaceIDs == [recent])
        let brokenDirectory = directory.appendingPathComponent("broken")
        try FileManager.default.createDirectory(at: brokenDirectory, withIntermediateDirectories: true)
        let brokenFile = brokenDirectory.appendingPathComponent("link-routing.json")
        let brokenData = Data("unreadable".utf8); try brokenData.write(to: brokenFile)
        let broken = LinkRoutingStore(directory: brokenDirectory)
        precondition(broken.commitEditor([LinkRoute()], basedOn: []))
        let preserved = try Data(contentsOf: brokenFile)
        precondition(preserved == brokenData)
        precondition(broken.reset(basedOn: []))
        let recovered = LinkRoutingStore(directory: brokenDirectory)
        precondition(recovered.errorMessage == nil && recovered.state.rules.isEmpty)
        print("LinkRouting editor saving and conflict preservation passed")
    }
}
