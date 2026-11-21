import Foundation
@testable import ParcCore

@MainActor
struct PresentationOnboardingFixture {
    let root: URL
    let store: BrowserStore

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("parc-onboarding-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        store = try BrowserStore(directory: root, now: { Date(timeIntervalSince1970: 1_700_000_000) })
        try store.save()
    }

    func remove() { try? FileManager.default.removeItem(at: root) }

    var draftFile: URL { root.appendingPathComponent("onboarding.json") }

    func loadDraft() throws -> OnboardingDraft {
        try OnboardingDraft.load(directory: root, space: store.activeSpace)
    }

    func pendingDraft() throws -> OnboardingDraft {
        var draft = try loadDraft()
        draft.spaceName = "Personal"
        draft.stage = .bookmarks
        draft.iCloudPasswordsProfileID = store.activeSpace.profileID
        draft.favoriteURLs = [OnboardingDraft.favoriteChoices[0].url]
        draft.bookmarks = [.init(title: "Docs", url: "https://example.com/docs"),
                           .init(title: "Duplicate", url: "https://example.com/docs"),
                           .init(title: "Invalid", url: "javascript:alert(1)")]
        return draft
    }

    func rewriteDraft(_ file: URL? = nil, _ change: (inout [String: Any]) -> Void) throws {
        let target = file ?? draftFile
        var json = try JSONSerialization.jsonObject(with: Data(contentsOf: target)) as! [String: Any]
        change(&json)
        try JSONSerialization.data(withJSONObject: json).write(to: target)
    }

    func subdirectory(_ name: String) -> URL { root.appendingPathComponent(name) }

    static func draft(stage: OnboardingDraft.Stage = .bookmarks) -> OnboardingDraft {
        var draft = OnboardingDraft(spaceID: UUID(), spaceName: "Personal", theme: SpaceTheme())
        draft.stage = stage
        return draft
    }
}
