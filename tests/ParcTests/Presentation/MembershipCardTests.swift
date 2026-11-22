import AppKit
import Testing
@testable import ParcCore
@testable import Parc
@testable import ParcSettings

struct MembershipCardTests {
    private let specimen = MembershipCardState(name: "Ada Lovelace", createdAt: Date(timeIntervalSince1970: 1_800_000_000),
                                              palette: 2, shape: 1, title: "ARCHITECT",
                                              backgroundBlobInfo: Array(1...14) + [1])

    @MainActor private func withCard(_ body: (MembershipCardSettingsView, MembershipCardStore) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("card.json")
        try JSONEncoder().encode(specimen).write(to: url)
        let store = MembershipCardStore(url: url, initialName: "Unused")
        try body(MembershipCardSettingsView(cards: store), store)
    }

    @MainActor private func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }

    @Test(arguments: ["Share card", "Download card", "Randomize card design", "Edit card display name"])
    @MainActor func eachActionIsAvailableUnderItsAccessibilityLabel(label: String) throws {
        try withCard { pane, _ in
            let action = descendants(pane).compactMap { $0 as? NSButton }
                .first { $0.accessibilityLabel() == label }
            #expect(action?.isEnabled == true)
        }
    }

    @Test @MainActor func theCardReadsAsOneAccessibleImage() throws {
        try withCard { pane, _ in
            let card = try #require(pane.subviews.compactMap { $0 as? MembershipCardView }.first)
            #expect(card.accessibilityRole() == .image)
            #expect(card.accessibilityLabel()?.contains(specimen.name) == true)
        }
    }

    @Test @MainActor func changingTheSavedDesignUpdatesTheDetachedCard() throws {
        try withCard { pane, store in
            try store.regenerate()
            let card = try #require(pane.subviews.compactMap { $0 as? MembershipCardView }.first)
            #expect(card.state == store.state)
        }
    }

    @Test @MainActor func theDefaultBrowserBannerShowsTheSystemsRefusal() throws {
        try withCard { pane, _ in
            pane.showDefaultBrowserPrompt(true, waiting: false, failure: "macOS refused the change.")
            #expect(descendants(pane).contains { ($0 as? NSTextField)?.stringValue == "macOS refused the change." })
        }
    }

    @Test(arguments: [1, 2, 3, 4])
    @MainActor func everyMaskPaintsArtworkSeparatelyFromTheCardChrome(shape: Int) throws {
        var state = specimen
        state.shape = shape
        let render = try #require(MembershipCardArtwork.render(state, scale: 1, resources: Bundle.module))
        let chrome = try #require(MembershipCardArtwork.render(state, scale: 1, includeArtwork: false, resources: Bundle.module))
        #expect(render.size == MembershipCardArtwork.size)
        #expect(render.colorAt(x: 120, y: 200) != chrome.colorAt(x: 120, y: 200))
        #expect(render.colorAt(x: 120, y: 230) == chrome.colorAt(x: 120, y: 230))
    }

    @Test @MainActor func theShareImageUsesAThreeTimesScaleMatte() throws {
        let image = try #require(MembershipCardArtwork.sharingBitmap(specimen))
        #expect(image.pixelsWide == 1236 && image.pixelsHigh == 1593)
    }

    @Test @MainActor func theSavedDesignSeedsTheSameRestingBlobArrangement() {
        let first = MembershipCardBlobField(specimen)
        let second = MembershipCardBlobField(specimen)
        #expect(first.rest.count == specimen.backgroundBlobInfo.count)
        #expect(first.rest.map(\.offset) == second.rest.map(\.offset))
        #expect(first.rest.map(\.rotation) == second.rest.map(\.rotation))
    }

    @Test @MainActor func aDifferentSavedDesignChangesTheBlobArrangement() {
        var changed = specimen
        changed.palette = 7
        let original = MembershipCardBlobField(specimen)
        let updated = MembershipCardBlobField(changed)
        #expect(original.colors != updated.colors)
        #expect(original.rest.map(\.offset) != updated.rest.map(\.offset))
    }
}
