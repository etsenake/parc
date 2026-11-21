import Foundation
import Testing
@testable import ParcCore

@MainActor
struct LinkRoutingStoreTests {
    func route(_ pattern: String) -> LinkRoute {
        var route = LinkRoute()
        route.conditions[0].pattern = pattern
        return route
    }

    func withBrokenStore(_ body: (LinkRoutingStore, URL, Data) throws -> Void) throws {
        try DataFixtures.withTemporaryDirectory { directory in
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let file = directory.appendingPathComponent("link-routing.json")
            let original = Data("unreadable routes".utf8)
            try original.write(to: file)
            try body(LinkRoutingStore(directory: directory), file, original)
        }
    }

    func withLiveStore(_ body: (LinkRoutingStore, URL) throws -> Void) throws {
        try DataFixtures.withTemporaryDirectory { directory in
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try body(LinkRoutingStore(directory: directory), directory.appendingPathComponent("link-routing.json"))
        }
    }

    @Test func anUnreadableFileReportsAnErrorAndStartsEmpty() throws {
        try withBrokenStore { store, _, _ in
            #expect(store.errorMessage != nil)
            #expect(store.state.rules.isEmpty)
        }
    }

    @Test func savingOverAnUnreadableFileIsRefusedAndKeepsTheErrorAndTheBytes() throws {
        try withBrokenStore { store, file, original in
            let message = store.errorMessage
            #expect(!store.save(LinkRoute()))
            #expect(!store.save(route("example.com")))
            #expect(store.errorMessage == message)
            let actual1 = try Data(contentsOf: file)
            #expect(actual1 == original)
        }
    }

    @Test func recommittingIdenticalRoutesKeepsTheBytesAndSkipsTheAtomicRewrite() throws {
        try withLiveStore { live, file in
            let rule = route("parc.example")
            #expect(live.save(rule))
            let written = try Data(contentsOf: file)
            let firstModified = try #require(try FileManager.default.attributesOfItem(atPath: file.path)[.modificationDate] as? Date)
            #expect(live.save(rule))
            let actual2 = try Data(contentsOf: file)
            #expect(actual2 == written)
            let secondModified = try #require(try FileManager.default.attributesOfItem(atPath: file.path)[.modificationDate] as? Date)
            #expect(secondModified == firstModified)
        }
    }

    @Test func changedRoutesStillRewriteTheFile() throws {
        try withLiveStore { live, file in
            #expect(live.save(route("parc.example")))
            let written = try Data(contentsOf: file)
            #expect(live.save(route("other.example")))
            let actual3 = try Data(contentsOf: file)
            #expect(actual3 != written)
            #expect(live.state.rules.map(\.conditions[0].pattern) == ["parc.example", "other.example"])
        }
    }
}

@MainActor
struct LinkRoutingEditorTests {
    func route(_ pattern: String) -> LinkRoute {
        var route = LinkRoute()
        route.conditions[0].pattern = pattern
        return route
    }

    func withStore(_ body: (LinkRoutingStore, URL) throws -> Void) throws {
        try DataFixtures.withTemporaryDirectory { directory in
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try body(LinkRoutingStore(directory: directory), directory)
        }
    }

    @Test func committingTheEditorKeepsAnIncompleteRouteWithItsCompletedConditions() throws {
        try withStore { store, _ in
            let first = route("first.example")
            var incomplete = LinkRoute()
            incomplete.conditions.append(LinkRouteCondition(pattern: "other.example"))
            let last = route("last.example")
            #expect(store.commitEditor([first, incomplete, last], basedOn: []))
            var completed = incomplete
            completed.conditions.removeFirst()
            #expect(store.state.rules == [first, completed, last])
        }
    }

    @Test func savableHoldsBackConditionsStillBeingEdited() {
        let savedRoute = route("youtube.com")
        var typing = savedRoute
        typing.conditions[0].pattern = "you"
        typing.destination = .space(UUID())
        let added = LinkRouteCondition(pattern: "watch")
        let blank = LinkRouteCondition(pattern: "  ")
        typing.conditions += [added, blank]
        var held = typing
        held.conditions = [savedRoute.conditions[0]]
        #expect(LinkRoutingDraft.savable([typing, LinkRoute()], editing: [typing.conditions[0].id, added.id],
                                         saved: [savedRoute]) == [held])
    }

    @Test func savableDropsABlankConditionOnceEditingFinishes() {
        let savedRoute = route("youtube.com")
        var typing = savedRoute
        typing.conditions[0].pattern = "you"
        typing.destination = .space(UUID())
        typing.conditions += [LinkRouteCondition(pattern: "watch"), LinkRouteCondition(pattern: "  ")]
        var finished = typing
        finished.conditions.removeLast()
        #expect(LinkRoutingDraft.savable([typing], saved: [savedRoute]) == [finished])
    }

    @Test func aStaleEditorCommitPreservesAPeersChangesAndTheRecentSpaces() throws {
        try withStore { store, directory in
            let baseline = store.state.rules
            #expect(store.save(route("peer.example")))
            let recent = UUID()
            store.noteVisitedSpace(recent)
            let current = store.state.rules
            #expect(store.commitEditor(baseline + [LinkRoute()], basedOn: baseline))
            #expect(store.state.rules == current)
            #expect(!store.commitEditor([route("last.example")], basedOn: baseline))
            #expect(!store.reset(basedOn: baseline))
            #expect(store.state.rules == current)
            #expect(store.state.recentSpaceIDs == [recent])
            let restored = LinkRoutingStore(directory: directory)
            #expect(restored.state.rules == current)
            #expect(restored.state.recentSpaceIDs == [recent])
        }
    }

    @Test func resettingFromTheCurrentRulesClearsThemAndKeepsTheRecentSpaces() throws {
        try withStore { store, _ in
            #expect(store.save(route("peer.example")))
            let recent = UUID()
            store.noteVisitedSpace(recent)
            #expect(store.reset(basedOn: store.state.rules))
            #expect(store.state.rules.isEmpty && store.state.recentSpaceIDs == [recent])
        }
    }

    @Test func aBrokenFileIsPreservedUntilAnEditorCommitAndResetRecoversIt() throws {
        try withStore { _, directory in
            let brokenDirectory = directory.appendingPathComponent("broken")
            try FileManager.default.createDirectory(at: brokenDirectory, withIntermediateDirectories: true)
            let brokenFile = brokenDirectory.appendingPathComponent("link-routing.json")
            let brokenData = Data("unreadable".utf8)
            try brokenData.write(to: brokenFile)
            let broken = LinkRoutingStore(directory: brokenDirectory)
            #expect(broken.commitEditor([LinkRoute()], basedOn: []))
            let actual4 = try Data(contentsOf: brokenFile)
            #expect(actual4 == brokenData)
            #expect(broken.reset(basedOn: []))
            let recovered = LinkRoutingStore(directory: brokenDirectory)
            #expect(recovered.errorMessage == nil && recovered.state.rules.isEmpty)
        }
    }
}

struct LinkRoutingUnavailableSpaceTests {
    let excluded = "excluded"
    let front = "front"
    let back = "back"
    let first = UUID()
    let lastFocused = UUID()
    let removed = UUID()

    @Test func skipsExcludedWindowsAndChoosesTheFrontmostEligibleWindow() {
        #expect(LinkRoutingUnavailableSpace.firstEligibleWindow(ordered: [excluded, front, back], eligible: [front, back]) == front)
    }

    @Test func systemOrderNotEligibilityOrderControlsSelection() {
        #expect(LinkRoutingUnavailableSpace.firstEligibleWindow(ordered: [back, excluded, front], eligible: [front, back]) == back)
    }

    @Test func anEligibleButUnorderedWindowIsNotSelected() {
        #expect(LinkRoutingUnavailableSpace.firstEligibleWindow(ordered: [excluded], eligible: [front]) == nil)
    }

    @Test func noEligibleWindowRequiresTheNewWindowFallback() {
        #expect(LinkRoutingUnavailableSpace.firstEligibleWindow(ordered: [front], eligible: Set<String>()) == nil)
    }

    @Test func aStillAvailableLastFocusedSpaceIsRetained() {
        #expect(LinkRoutingUnavailableSpace.newWindowSpace(lastFocused: lastFocused, available: [first, lastFocused]) == lastFocused)
    }

    @Test func aDeletedLastFocusedSpaceFallsBackToTheFirstAvailable() {
        #expect(LinkRoutingUnavailableSpace.newWindowSpace(lastFocused: removed, available: [first, lastFocused]) == first)
    }

    @Test func missingRecencyFallsBackToTheFirstAvailableSpace() {
        #expect(LinkRoutingUnavailableSpace.newWindowSpace(lastFocused: nil, available: [first]) == first)
    }

    @Test func anEmptyCollectionCannotFabricateASpace() {
        #expect(LinkRoutingUnavailableSpace.newWindowSpace(lastFocused: lastFocused, available: []) == nil)
    }
}
