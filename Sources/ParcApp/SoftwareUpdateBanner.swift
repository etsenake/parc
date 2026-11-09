import Foundation

///
/// `updateSummary`): one state that every browser window's sidebar shows.
@MainActor
final class SoftwareUpdateBanner: ObservableObject {
    static let shared = SoftwareUpdateBanner()
    /// The What's New page in the bundle's Resources (UPD06 renders it at build
    /// time); a build without it has no release notes to open.
    static var releaseNotesURL: URL? { Bundle.main.url(forResource: "WhatsNew", withExtension: "html") }

    /// Update Complete!: the update this run is the first since, until the
    /// banner is retired.
    @Published private(set) var completedUpdate: AppVersion?
    private var record: ReleaseNotesLaunch?
    private var directory: URL?

    /// The banner offers See What's New, so a build without the page shows none.
    var showsCompletedUpdate: Bool { completedUpdate != nil && Self.releaseNotesURL != nil }

    /// Records a run that actually started on `directory`.
    func launch(in directory: URL, existingData: Bool,
                current: AppVersion? = AppVersion(infoDictionary: Bundle.main.infoDictionary)) {
        guard let current else { return }
        let record = ReleaseNotesLaunch.launching(current, previous: .read(in: directory), existingData: existingData)
        record.write(in: directory)
        self.record = record
        self.directory = directory
        completedUpdate = record.pending
    }

    ///
    /// one launch only; a launch that never reaches a browser window keeps it.
    func markCompletedUpdateShown() {
        guard var record, let directory, record.pending != nil else { return }
        record.markShown()
        record.write(in: directory)
        self.record = record
    }

    /// See What's New or the close button.
    func retireCompletedUpdate() {
        markCompletedUpdateShown()
        completedUpdate = nil
    }
}
