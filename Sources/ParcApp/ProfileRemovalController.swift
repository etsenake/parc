import AppKit
import Combine

@MainActor
final class ProfileRemovalController: ObservableObject {
    static let shared = ProfileRemovalController()
    struct Progress {
        var message: String
        var running: Bool
        var canCancel: Bool
        var error: Error?
        var reported = false
    }
    @Published private(set) var revision = 0
    private weak var store: BrowserStore?
    private var progress: [UUID: Progress] = [:]
    private var cancelling = Set<UUID>()
    private var leases: [UUID: PCNativeProfileRemoval] = [:]

    func configure(store: BrowserStore) {
        self.store = store
        for record in store.state.profileRemovals { recover(record) }
    }

    func status(for profileID: UUID) -> Progress? { progress[profileID] }

    func claimFailure(for profileID: UUID) -> Progress? {
        guard let status = progress[profileID], !status.running, status.error != nil, !status.reported else { return nil }
        progress[profileID]?.reported = true
        return status
    }

    func remove(profileID: UUID, expectedName: String) {
        guard let store, progress[profileID]?.running != true else { return }
        if let record = store.state.profileRemovals.first(where: { $0.profileID == profileID }) {
            recover(record)
            return
        }
        do {
            let record = try store.stageProfileRemoval(profileID, expectedName: expectedName)
            prepare(record)
        } catch { set(profileID, message: error.localizedDescription, running: false, canCancel: true, error: error) }
    }

    func removeUnusedProfiles(_ profiles: [BrowserProfile]) throws {
        guard let store else { throw ProfileRemovalError.unavailable }
        guard !profiles.isEmpty, Set(profiles.map(\.id)).count == profiles.count else {
            throw ProfileRemovalError.invalidSelection
        }
        var newProfiles: [BrowserProfile] = []
        var recovering: [ProfileRemovalRecord] = []
        for expected in profiles {
            guard let current = store.state.profiles.first(where: { $0.id == expected.id }) else { continue }
            guard current.name == expected.name else { throw ProfileRemovalError.nameChanged }
            guard progress[current.id]?.running != true else { throw ProfileRemovalError.alreadyRemoving }
            if let record = store.state.profileRemovals.first(where: { $0.profileID == current.id }) {
                guard record.profileName == expected.name else { throw ProfileRemovalError.nameChanged }
                recovering.append(record)
            } else {
                newProfiles.append(expected)
            }
        }
        let records = newProfiles.isEmpty ? [] : try store.stageUnusedProfileRemovals(newProfiles)
        for record in recovering { recover(record) }
        for record in records { prepare(record) }
    }

    private func prepare(_ record: ProfileRemovalRecord) {
        guard let store else { return }
        set(record.profileID, message: "Preparing this profile for removal…", running: true, canCancel: true)
        PCNativeBrowserApplication.prepareProfileRemoval(
            profilePath: store.independentEngineProfilePath(for: record.profileID),
            protectedProfilePath: store.independentEngineProfilePath(for: store.defaultProfileID),
            operationID: record.id.uuidString) { [weak self] lease, error in
                MainActor.assumeIsolated { self?.prepared(record, lease: lease, error: error) }
            }
    }

    func cancel(profileID: UUID) {
        guard progress[profileID]?.canCancel == true else { return }
        guard let record = store?.state.profileRemovals.first(where: { $0.profileID == profileID }) else {
            progress.removeValue(forKey: profileID); revision &+= 1; return
        }
        cancelling.insert(record.id)
        if let lease = leases.removeValue(forKey: record.id) {
            lease.cancel()
            cancelPrepared(record)
        }
    }

    private func prepared(_ record: ProfileRemovalRecord, lease: PCNativeProfileRemoval?, error: Error?) {
        guard let store else { lease?.cancel(); return }
        let nativeError = error as NSError?
        if lease == nil, nativeError?.domain == "ParcProfileRemoval", nativeError?.code == 6 {
            cancelling.remove(record.id)
            set(record.profileID, message: "Recovering this profile’s removal…", running: false, canCancel: false)
            recover(record)
            return
        }
        if cancelling.contains(record.id) {
            lease?.cancel(); cancelPrepared(record); return
        }
        guard let lease else {
            failedBeforeCommit(record, error: error ?? ProfileRemovalError.unavailable)
            return
        }
        guard lease.operationID == record.id.uuidString,
              lease.profilePath == store.independentEngineProfilePath(for: record.profileID) else {
            lease.cancel(); failedBeforeCommit(record, error: ProfileRemovalError.unavailable); return
        }
        leases[record.id] = lease
        set(record.profileID, message: "Removing this profile’s browser data…", running: true, canCancel: false)
        lease.commit(revalidate: { [weak self] in
            MainActor.assumeIsolated {
                guard let store = self?.store,
                      store.state.profileRemovals.contains(record),
                      record.profileID != store.defaultProfileID,
                      store.state.profiles.contains(where: { $0.id == record.profileID && $0.name == record.profileName }),
                      !store.state.spaces.contains(where: { $0.profileID == record.profileID }) else { return false }
                return true
            }
        }, completion: { [weak self] result, error in
            MainActor.assumeIsolated { self?.completed(record, result: result, error: error) }
        })
    }

    private func recover(_ record: ProfileRemovalRecord) {
        guard let store, progress[record.profileID]?.running != true else { return }
        set(record.profileID, message: "Finishing this profile’s removal…", running: true, canCancel: false)
        PCNativeBrowserApplication.recoverProfileRemoval(
            profilePath: store.independentEngineProfilePath(for: record.profileID),
            protectedProfilePath: store.independentEngineProfilePath(for: store.defaultProfileID),
            operationID: record.id.uuidString) { [weak self] result, error in
                MainActor.assumeIsolated { self?.completed(record, result: result, error: error) }
            }
    }

    private func completed(_ record: ProfileRemovalRecord, result: PCNativeProfileRemovalState, error: Error?) {
        leases.removeValue(forKey: record.id)
        guard let store else { return }
        switch result {
        case .removed:
            do {
                try store.finishProfileRemoval(record)
                progress.removeValue(forKey: record.profileID); revision &+= 1
            } catch {
                set(record.profileID, message: "The browser data was removed, but Parc couldn’t save the final change. Retry to finish. " + error.localizedDescription,
                    running: false, canCancel: false, error: error)
            }
        case .failed:
            failedBeforeCommit(record, error: error ?? ProfileRemovalError.unavailable)
        case .pending:
            set(record.profileID, message: error?.localizedDescription ?? "Removal is incomplete. Retry to finish this profile’s cleanup.",
                running: false, canCancel: false, error: error ?? ProfileRemovalError.incompleteOperation)
        @unknown default:
            set(record.profileID, message: "Removal needs to be recovered before this profile can be used.",
                running: false, canCancel: false, error: ProfileRemovalError.incompleteOperation)
        }
    }

    private func cancelPrepared(_ record: ProfileRemovalRecord) {
        cancelling.remove(record.id)
        do {
            try store?.cancelProfileRemoval(record)
            progress.removeValue(forKey: record.profileID); revision &+= 1
        } catch {
            set(record.profileID, message: error.localizedDescription, running: false, canCancel: false, error: error)
        }
    }

    private func failedBeforeCommit(_ record: ProfileRemovalRecord, error: Error) {
        do {
            try store?.cancelProfileRemoval(record)
            set(record.profileID, message: error.localizedDescription, running: false, canCancel: true, error: error)
        } catch {
            set(record.profileID, message: "Parc couldn’t save the cancelled removal. Retry to recover the profile. " + error.localizedDescription,
                running: false, canCancel: false, error: error)
        }
    }

    private func set(_ id: UUID, message: String, running: Bool, canCancel: Bool, error: Error? = nil) {
        progress[id] = Progress(message: message, running: running, canCancel: canCancel, error: error)
        revision &+= 1
    }
}
