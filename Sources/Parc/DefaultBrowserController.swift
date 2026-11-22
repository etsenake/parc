import AppKit
import Combine

@MainActor
final class DefaultBrowserController: ObservableObject {
    typealias Completion = @MainActor (Error?) -> Void
    typealias Setter = (URL, String, @escaping Completion) -> Void

    static let shared = DefaultBrowserController(
        applicationURL: Bundle.main.bundleURL,
        bundleIdentifier: Bundle.main.bundleIdentifier,
        lookup: { NSWorkspace.shared.urlForApplication(toOpen: $0) },
        setter: { application, scheme, completion in
            NSWorkspace.shared.setDefaultApplication(at: application, toOpenURLsWithScheme: scheme) { error in
                DispatchQueue.main.async { completion(error) }
            }
        })

    struct State: Equatable {
        var handlesHTTP = false
        var handlesHTTPS = false
        var isRequesting = false
        var failure: String?
        var isDefault: Bool { handlesHTTP && handlesHTTPS }
    }
    @Published private(set) var state = State()
    let isApplication: Bool
    private let applicationURL: URL
    private let lookup: (URL) -> URL?
    private let setter: Setter
    private var request: UUID?
    private var pendingScheme: String?
    private var activation: AnyCancellable?

    init(applicationURL: URL, bundleIdentifier: String?,
         lookup: @escaping (URL) -> URL?, setter: @escaping Setter,
         observeActivation: Bool = true) {
        self.applicationURL = applicationURL.standardizedFileURL.resolvingSymlinksInPath()
        isApplication = applicationURL.isFileURL && applicationURL.pathExtension.lowercased() == "app"
            && bundleIdentifier?.isEmpty == false
        self.lookup = lookup; self.setter = setter
        refresh()
        if observeActivation {
            activation = NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
                .receive(on: RunLoop.main).sink { [weak self] _ in self?.refresh() }
        }
    }

    var canRequest: Bool { isApplication && !state.isDefault && !state.isRequesting }

    func refresh() {
        var next = state
        func owns(_ scheme: String) -> Bool {
            guard isApplication, let url = URL(string: scheme + "://"),
                  let handler = lookup(url) else { return false }
            return handler.standardizedFileURL.resolvingSymlinksInPath() == applicationURL
        }
        next.handlesHTTP = owns("http"); next.handlesHTTPS = owns("https")
        if next.isDefault { next.failure = nil }
        if state != next { state = next }
    }

    @discardableResult
    func makeDefault(completion: @escaping (String?) -> Void = { _ in }) -> Bool {
        refresh()
        guard canRequest else { return false }
        let id = UUID(); request = id
        state.failure = nil; state.isRequesting = true
        set("http", request: id, completion: completion)
        return true
    }

    private func set(_ scheme: String, request id: UUID, completion: @escaping (String?) -> Void) {
        pendingScheme = scheme
        setter(applicationURL, scheme) { [weak self] error in
            guard let self, self.request == id, self.pendingScheme == scheme else { return }
            self.pendingScheme = nil
            if error == nil && scheme == "http" {
                self.set("https", request: id, completion: completion)
                return
            }
            self.request = nil
            self.state.isRequesting = false
            self.refresh()
            let cancelled = error.map { error in
                let value = error as NSError
                return (value.domain == NSCocoaErrorDomain && value.code == NSUserCancelledError)
                    || (value.domain == NSOSStatusErrorDomain && value.code == -128)
            } ?? false
            if !self.state.isDefault && !cancelled {
                self.state.failure = error?.localizedDescription
                    ?? "macOS has not selected Parc as the default browser. You can try again."
            }
            completion(self.state.failure)
        }
    }
}
