import Foundation

@MainActor
final class SoftwareUpdateBanner: ObservableObject {
    static let shared = SoftwareUpdateBanner()
    static var releaseNotesURL: URL? {
        Bundle.main.url(forResource: "WhatsNew", withExtension: "html") == nil ? nil : URL(string: WhatsNewPage.address)
    }

    @Published private(set) var completedUpdate: AppVersion?
    private(set) var updatedFrom: AppVersion?
    var completedUpdateFragment: String? {
        guard let completedUpdate, let updatedFrom else { return nil }
        return "from=\(updatedFrom.version)&to=\(completedUpdate.version)"
    }
    private var record: ReleaseNotesLaunch?
    private var directory: URL?

    var showsCompletedUpdate: Bool { completedUpdate != nil && Self.releaseNotesURL != nil }

    func launch(in directory: URL, existingData: Bool,
                current: AppVersion? = AppVersion(infoDictionary: Bundle.main.infoDictionary)) {
        guard let current else { return }
        let record = ReleaseNotesLaunch.launching(current, previous: .read(in: directory), existingData: existingData)
        record.write(in: directory)
        self.record = record
        self.directory = directory
        completedUpdate = record.pending
        updatedFrom = record.updatedFrom
    }

    func markCompletedUpdateShown() {
        guard var record, let directory, record.pending != nil else { return }
        record.markShown()
        record.write(in: directory)
        self.record = record
    }

    func retireCompletedUpdate() {
        markCompletedUpdateShown()
        completedUpdate = nil
        updatedFrom = nil
    }
}
