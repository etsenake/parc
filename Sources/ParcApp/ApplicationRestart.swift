import AppKit

@MainActor
final class ApplicationRestart {
    private let process = Process()
    private let commands = Pipe()
    private let readiness = Pipe()
    private var onReady: ((String?) -> Void)?
    private var didPrepare = false
    private var didArm = false
    private var cancelled = false
    private var timeout: DispatchWorkItem?

    func prepare(profileDirectory: URL?, completion: @escaping (String?) -> Void) {
        guard !cancelled, onReady == nil, !didPrepare,
              let helper = Bundle.main.url(forAuxiliaryExecutable: "ParcRestart") else {
            completion("The restart helper is unavailable in this build."); return
        }
        onReady = completion
        process.executableURL = helper
        process.arguments = [String(ProcessInfo.processInfo.processIdentifier), Bundle.main.bundleURL.path]
            + (profileDirectory.map { ["--parc-profile", $0.path] } ?? [])
        process.standardInput = commands; process.standardOutput = readiness
        process.standardError = FileHandle.nullDevice
        let reader = readiness.fileHandleForReading
        process.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async { [weak self] in
                guard let self, !self.cancelled, !self.didArm else { return }
                self.finishPreparation("Parc’s restart helper stopped before it was ready.")
            }
        }
        do { try process.run() }
        catch { finishPreparation(error.localizedDescription); return }
        try? readiness.fileHandleForWriting.close()
        try? commands.fileHandleForReading.close()
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = try? reader.readToEnd()
            DispatchQueue.main.async { [weak self] in
                guard let self, !self.cancelled else { return }
                self.finishPreparation(result == Data("READY\n".utf8) ? nil :
                    "Parc could not prepare to restart. Your browser is still open.")
            }
        }
        let deadline = DispatchWorkItem { [weak self] in
            self?.finishPreparation("Parc could not prepare to restart in time.")
        }
        timeout = deadline
        DispatchQueue.main.asyncAfter(deadline: .now() + 10, execute: deadline)
    }

    private func finishPreparation(_ failure: String?) {
        guard let callback = onReady else { return }
        onReady = nil; timeout?.cancel(); timeout = nil
        if failure == nil, process.isRunning { didPrepare = true; callback(nil) }
        else { cancel(); callback(failure ?? "Parc’s restart helper is no longer available.") }
    }

    func arm() throws {
        guard didPrepare, !didArm, !cancelled, process.isRunning else {
            throw CocoaError(.executableNotLoadable)
        }
        try commands.fileHandleForWriting.write(contentsOf: Data("RESTART\n".utf8))
        didArm = true
    }

    func cancel() {
        guard !cancelled else { return }
        cancelled = true; timeout?.cancel(); timeout = nil; onReady = nil
        if process.isRunning {
            try? commands.fileHandleForWriting.write(contentsOf: Data("CANCEL\n".utf8))
        }
        try? commands.fileHandleForWriting.close()
    }
}
