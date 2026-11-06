import Foundation

// Deliberate native-boundary doubles. This executable exercises the production
// controller and real file-backed BrowserStore without loading Chromium,
// deleting native profile directories or sending browser input.
enum PCNativeProfileRemovalState { case removed, pending, failed }
@MainActor final class PCNativeProfileRemoval {
    let operationID: String
    let profilePath: String
    var cancelled = false
    var completion: ((PCNativeProfileRemovalState, Error?) -> Void)?
    init(path: String, operation: String) { profilePath = path; operationID = operation }
    func cancel() { cancelled = true }
    func commit(revalidate: () -> Bool, completion: @escaping (PCNativeProfileRemovalState, Error?) -> Void) {
        if revalidate() { self.completion = completion }
        else { completion(.failed, ProfileRemovalError.unavailable) }
    }
}
@MainActor enum PCNativeBrowserApplication {
    struct Preparation {
        let path: String
        let operation: String
        let completion: (PCNativeProfileRemoval?, Error?) -> Void
    }
    struct Recovery {
        let path: String
        let operation: String
        let completion: (PCNativeProfileRemovalState, Error?) -> Void
    }
    static var preparations: [Preparation] = []
    static var recoveries: [Recovery] = []
    static var willPrepare: (() -> Void)?
    static func prepareProfileRemoval(profilePath: String, protectedProfilePath: String, operationID: String,
                                      completion: @escaping (PCNativeProfileRemoval?, Error?) -> Void) {
        precondition(profilePath != protectedProfilePath)
        willPrepare?()
        preparations.append(Preparation(path: profilePath, operation: operationID, completion: completion))
    }
    static func recoverProfileRemoval(profilePath: String, protectedProfilePath: String, operationID: String,
                                      completion: @escaping (PCNativeProfileRemovalState, Error?) -> Void) {
        precondition(profilePath != protectedProfilePath)
        recoveries.append(Recovery(path: profilePath, operation: operationID, completion: completion))
    }
    static func prepare(_ index: Int) -> PCNativeProfileRemoval {
        let request = preparations[index]
        let lease = PCNativeProfileRemoval(path: request.path, operation: request.operation)
        request.completion(lease, nil)
        return lease
    }
}

