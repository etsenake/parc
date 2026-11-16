import Combine
import Foundation

@main @MainActor
struct SplitSubmissionTests {
    static var assertions = 0
    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        assertions += 1
        precondition(condition(), message)
    }
    static func main() { exitOnFailure(runChecks) }
    static func runChecks() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("parc-command-split-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try BrowserStore(directory: directory)
        let source = store.openResolvedURL(URL(string: "https://example.test/source")!)
        let right = store.openResolvedURL(URL(string: "https://example.test/right")!)
        store.setSplit([source, right])
        _ = store.setSplitLayout(orientation: .vertical, widthFactors: [3, 1])
        let target = UUID(), url = URL(string: "https://example.test/search?q=a%26b#fragment")!
        var publications = 0
        let observation = store.statePublisher.dropFirst().sink { state in
            publications += 1
            if state.tabs.contains(where: { $0.id == target }) {
                expect(state.selectedTabIDs == [source, target, right], "New token metadata must publish with its final destination")
            }
        }
        expect(store.insertCommandBarSplit(after: source, expectedSelection: [source, right], tabID: target, newURL: url), "Insert classified request metadata")
        observation.cancel()
        expect(publications == 1, "The split transaction publishes once")
        expect(store.state.selectedTabIDs == [source, target, right], "Insert immediately after focus, not at the end")
        expect(store.state.tabs.first(where: { $0.id == target })?.url == url.absoluteString, "URL is unchanged metadata")
        expect(store.state.tabs.first(where: { $0.id == target })?.profileID == store.activeSpace.profileID, "Exact active profile retained")
        expect(store.activeSplitLayout?.orientation == .vertical, "Existing orientation retained")
        let weights = store.activeSplitLayout!.widthFactors
        expect(abs(weights[0] / weights[2] - 3) < 0.0001, "Existing pane proportion retained")
        let stateBeforeRejection = store.state
        expect(!store.insertCommandBarSplit(after: source, expectedSelection: [source, right], tabID: UUID(), newURL: url), "Stale selection cannot commit")
        expect(store.state == stateBeforeRejection, "Stale selection rejection does not mutate")
        expect(!store.insertCommandBarSplit(after: UUID(), expectedSelection: store.state.selectedTabIDs, tabID: UUID(), newURL: url), "Missing original focus cannot commit")
        expect(!store.insertCommandBarSplit(after: source, expectedSelection: store.state.selectedTabIDs, tabID: target, newURL: url), "New request cannot replace an existing identity")
        let existing = store.openResolvedURL(URL(string: "https://example.test/existing")!)
        let expected = [source, target, right]
        store.setSplit(expected)
        let tabCount = store.state.tabs.count
        expect(store.insertCommandBarSplit(after: target, expectedSelection: expected, tabID: existing), "Existing tab enters a split without cloning")
        expect(store.state.selectedTabIDs == [source, target, existing, right], "Existing tab inserted after focused middle pane")
        expect(store.state.tabs.count == tabCount, "Original existing tab identity is reused")
        let full = store.state
        expect(!store.insertCommandBarSplit(after: target, expectedSelection: full.selectedTabIDs, tabID: UUID(), newURL: url), "Full split rejects before tab creation")
        expect(store.state == full, "Full split preserves all state")
        expect(store.insertCommandBarSplit(after: target, expectedSelection: full.selectedTabIDs, tabID: right), "Already-visible original tab remains eligible for focus")
        expect(store.state == full, "Already-visible tab does not reorder or duplicate panes")
        let laterHost = store.openResolvedURL(URL(string: "https://example.test/later-host")!)
        store.selectTab(laterHost)
        let noteID = store.openNote(id: UUID(), title: "Later Note")!
        store.selectTab(laterHost)
        expect(store.insertCommandBarSplit(after: laterHost, expectedSelection: [laterHost], tabID: noteID),
               "A Today Note joins as a later pane")
        expect(store.state.selectedTabIDs == [laterHost, noteID], "The Note is not promoted to the first tab")
        expect(store.state.tabs.filter { InternalPage(urlString: $0.url)?.noteID != nil }.count == 1,
               "Joining a Today Note does not leave a home")
        let easelHost = store.openResolvedURL(URL(string: "https://example.test/easel-host")!)
        store.selectTab(easelHost)
        let easelTab = store.openEasel(id: UUID(), title: "Later Easel")!
        store.selectTab(easelHost)
        expect(store.insertCommandBarSplit(after: easelHost, expectedSelection: [easelHost], tabID: easelTab),
               "A Today Easel joins as a later pane")
        expect(store.state.selectedTabIDs == [easelHost, easelTab], "The Easel is not promoted to the first tab")
        store.setSplit([source])
        let otherSpace = store.createSpace(name: "Other")
        let other = store.openResolvedURL(URL(string: "https://example.test/other")!)
        let foreign = store.openResolvedURL(URL(string: "https://example.test/foreign")!)
        let sourceSpace = store.state.tabs.first(where: { $0.id == source })!.spaceID
        store.selectSpace(sourceSpace); store.setSplit([source])
        expect(store.insertCommandBarSplit(after: source, expectedSelection: [source], tabID: foreign), "Foreign Space tab joins the split")
        expect(store.state.selectedTabIDs == [source, foreign] && store.activeSpaceID == sourceSpace
               && store.state.tabs.first(where: { $0.id == foreign })?.spaceID == sourceSpace, "It moves into this Space without a Space switch")
        store.setSplit([source])
        store.setKind(other, .favorite)
        expect(store.insertCommandBarSplit(after: source, expectedSelection: [source], tabID: other), "Same-profile Favorite is available across Spaces")
        let favoriteHome = store.state.tabs.first { $0.id != other && $0.kind == .favorite && $0.savedURL == "https://example.test/other" }
        expect(store.state.tabs.first(where: { $0.id == other })?.kind == .today
               && store.state.tabs.first(where: { $0.id == other })?.spaceID == sourceSpace, "The Favorite result joins the new Today split")
        expect(favoriteHome?.spaceID == otherSpace, "Its fresh tray home keeps the Favorite's saved Space")
        try store.save()
        let restored = try BrowserStore(directory: directory)
        expect(restored.state.selectedTabIDs == [source, other], "Split selection persists")
        expect(restored.activeSplitLayout?.tabIDs == [source, other], "Split layout persists")
        print("\(assertions) command-bar split model assertions passed")
    }
}
