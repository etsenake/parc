import Combine
import Foundation

enum NoteFileSaveState: Equatable {
    case saved
    case unsaved
    case saving
    case failed(String)
    case conflict
    case missing
}

enum NoteFileError: Error, LocalizedError, Equatable {
    case unreadable(String)
    case tooLarge
    case nameTaken(String)
    case invalidName
    case missing
    case notANote
    case unwritable(String)
    case conflict

    var errorDescription: String? {
        switch self {
        case .unreadable(let detail): return "Parc couldn’t read this note. \(detail)"
        case .tooLarge: return "This file is too big to open as a note."
        case .nameTaken(let name): return "There’s already a note called “\(name)” here."
        case .invalidName: return "Notes can’t be named that."
        case .missing: return "This note isn’t where it used to be."
        case .notANote: return "Parc can only open Markdown and text files as notes."
        case .unwritable(let detail): return "Parc couldn’t save this note. \(detail)"
        case .conflict: return "This note changed somewhere else too. Pick the version to keep first."
        }
    }
}

@MainActor
final class NoteFileSession {
    private struct SaveRequest {
        var page: NotePage
        var text: String
        var data: Data
        var format: NoteFileFormat
        var url: URL
        var expected: String?
        var force: Bool
    }

    private final class WriteTicket: @unchecked Sendable {
        private let lock = NSLock()
        private var stored: NoteFileWriteOutcome?
        var handled = false
        var outcome: NoteFileWriteOutcome? {
            get { lock.withLock { stored } }
            set { lock.withLock { stored = newValue } }
        }
    }

    private static var sessions: [String: NoteFileSession] = [:]
    static var clock: NoteFileClock = NoteFileSystemClock.shared
    static var worker: NoteFileWorker = .files
    static var autosaveDelay: TimeInterval = 0.6
    static var longestAutosaveWait: TimeInterval = 5
    static var diskCheckDelay: TimeInterval = 0.12
    nonisolated static let coordinatedSaveWait: TimeInterval = 1

    static func open(_ url: URL) throws -> NoteFileSession {
        guard url.isFileURL else { throw NoteFileError.notANote }
        let canonical = NoteFilePaths.canonical(url)
        if let existing = sessions[canonical.path] { return existing }
        guard let kind = NoteFileKind(url: canonical) ?? NoteFileKind(url: url) else { throw NoteFileError.notANote }
        guard NoteFilePaths.itemExists(canonical) else { throw NoteFileError.missing }
        let contents = try NoteFileIO.read(canonical, kind: kind)
        let session = NoteFileSession(url: canonical, kind: kind, contents: contents)
        sessions[canonical.path] = session
        session.startWatching()
        return session
    }

    static func session(for url: URL) -> NoteFileSession? { sessions[NoteFilePaths.key(for: url)] }

    static var openSessions: [NoteFileSession] { Array(sessions.values) }

    static func flushAll() throws {
        var firstError: Error?
        for session in sessions.values {
            do { try session.flush() } catch { if firstError == nil { firstError = error } }
        }
        if let firstError { throw firstError }
    }

    private(set) var url: URL
    let kind: NoteFileKind
    let page: NotePageSession
    let environment: NoteEnvironment
    @Published private(set) var state: NoteFileSaveState = .saved
    let urlChanges = PassthroughSubject<URL, Never>()
    private(set) var format: NoteFileFormat
    private(set) var hasUnsavedChanges = false
    private(set) var editorCount = 0
    private(set) var lastSaveError: String?
    private(set) var readProblem: String?

    private let fileEnvironment: NoteFileEnvironment
    private var diskText: String?
    private var baseline: NotePage
    private var conflict: NoteFileContents?
    private var forceNextSave = false
    private var firstUnsavedEdit: Date?
    private var autosaveTimer: NoteFileTimer?
    private var diskCheckTimer: NoteFileTimer?
    private var pendingMovePath: String?
    private var applyingDisk = false
    private var tickets: [(WriteTicket, SaveRequest)] = []
    private var watcher: NoteFileWatcher?
    private var changeSubscription: AnyCancellable?
    private var isClosed = false

    private init(url: URL, kind: NoteFileKind, contents: NoteFileContents) {
        self.url = url
        self.kind = kind
        format = contents.format
        diskText = contents.text
        let parsed = Self.parse(contents, kind: kind)
        page = NotePageSession(page: parsed)
        baseline = page.page
        fileEnvironment = NoteFileEnvironment(documentURL: url, isPlainText: kind == .plainText)
        environment = fileEnvironment
        changeSubscription = page.changes.sink { [weak self] change in self?.pageChanged(change) }
    }

    var title: String { url.deletingPathExtension().lastPathComponent }

    var conflictingText: String? { conflict.map { NoteFileText.editableText($0, kind: kind) } }

    var isMissing: Bool { diskText == nil }

    var presenter: NSFilePresenter? { watcher }

    func retain() { editorCount += 1 }

    func release() {
        guard editorCount > 0 else { return }
        editorCount -= 1
        guard editorCount == 0 else { return }
        do { try flush() } catch { return }
        close()
    }

    func flush() throws {
        autosaveTimer?.cancel()
        autosaveTimer = nil
        drainWrites()
        if conflict != nil { throw NoteFileError.conflict }
        guard hasUnsavedChanges || forceNextSave, let request = makeSaveRequest() else { return }
        let ticket = WriteTicket()
        tickets.append((ticket, request))
        refreshState()
        let presenter = watcher
        let outcome = Self.worker.sync {
            NoteFileIO.write(request.data, text: request.text, to: request.url, kind: kind, expecting: request.expected,
                             force: request.force, presenter: presenter)
        }
        ticket.outcome = outcome
        complete(ticket)
        switch outcome {
        case .written, .unchanged: return
        case .conflict: throw NoteFileError.conflict
        case .failed(let message): throw NoteFileError.unwritable(message)
        }
    }

    func resolveConflict(keepMine: Bool) {
        guard let theirs = conflict else { return }
        conflict = nil
        if keepMine {
            diskText = theirs.text
            forceNextSave = true
            hasUnsavedChanges = true
            if firstUnsavedEdit == nil { firstUnsavedEdit = Self.clock.now }
            refreshState()
            save()
        } else {
            adopt(theirs, undoable: true)
        }
    }

    func rename(to proposed: String) throws -> URL {
        guard let target = try NoteFileNaming.renameTarget(for: url, to: proposed) else { return url }
        if NoteFilePaths.itemExists(url) {
            let source = url
            let presenter = watcher
            try Self.worker.sync { try NoteFileIO.move(source, to: target, presenter: presenter) }
        }
        relocate(to: NoteFilePaths.canonical(target.deletingLastPathComponent()).appendingPathComponent(target.lastPathComponent))
        return url
    }

    func saveMarkdownCopy() throws -> URL {
        let folder = url.deletingLastPathComponent()
        let base = NoteFileNaming.sanitizedTitle(title)
        let target = NoteFileNaming.uniqueURL(in: folder, base: base.isEmpty ? NoteFileNaming.untitled : base, pathExtension: "md")
        let text = NoteFileText.fileText(NoteMarkdown.serialize(page.page), format: .standard, kind: .markdown)
        try Self.worker.sync { try Data(text.utf8).write(to: target, options: .withoutOverwriting) }
        return NoteFilePaths.canonical(target)
    }

    func checkDisk() {
        diskCheckTimer?.cancel()
        diskCheckTimer = nil
        guard !isClosed else { return }
        let target = url, kind = kind, moved = pendingMovePath, presenter = watcher
        pendingMovePath = nil
        Self.worker.perform({ NoteFileIO.probe(target, kind: kind, movedPath: moved, presenter: presenter) }) { [weak self] probe in
            self?.apply(probe, checked: target)
        }
    }

    private static func parse(_ contents: NoteFileContents, kind: NoteFileKind) -> NotePage {
        let text = NoteFileText.editableText(contents, kind: kind)
        return kind == .markdown ? NoteMarkdown.parse(text) : NotePlainText.parse(text)
    }

    private func render(_ value: NotePage) -> String {
        let body = kind == .markdown ? NoteMarkdown.serialize(value) : NotePlainText.serialize(value)
        return NoteFileText.fileText(body, format: format, kind: kind)
    }

    private func startWatching() {
        let events: @Sendable (NoteFileWatchEvent) -> Void = { [weak self] event in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.handle(event) } }
        }
        let saveRequest: NoteFileWatcher.SaveRequest = { [weak self] completion in
            let outcome = NoteFileCoordinatedSave()
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    do { try self?.flush() } catch { outcome.error = error }
                    outcome.finished.signal()
                }
            }
            completion(outcome.finished.wait(timeout: .now() + Self.coordinatedSaveWait) == .success ? outcome.error : nil)
        }
        let watcher = NoteFileWatcher(url: url, events: events, saveRequest: saveRequest)
        self.watcher = watcher
        watcher.start()
    }

    func handle(_ event: NoteFileWatchEvent) {
        guard !isClosed else { return }
        switch event {
        case .moved(let destination):
            handleMove(to: destination)
        case .relocated(let path):
            if let path { pendingMovePath = path }
            scheduleDiskCheck()
        case .changed, .deleted:
            scheduleDiskCheck()
        }
    }

    private func scheduleDiskCheck() {
        diskCheckTimer?.cancel()
        diskCheckTimer = Self.clock.schedule(after: Self.diskCheckDelay) { [weak self] in self?.checkDisk() }
    }

    private func apply(_ probe: NoteFileProbe, checked target: URL) {
        guard !isClosed, target == url else { return }
        if case .unreadable = probe {} else { readProblem = nil }
        switch probe {
        case .contents(let contents):
            guard tickets.isEmpty else {
                scheduleDiskCheck()
                return
            }
            watcher?.rearm()
            if conflict != nil {
                if contents.text == render(page.page) { settleConflict(on: contents) } else { conflict = contents }
            } else if contents.text != diskText {
                if hasUnsavedChanges && page.page != baseline {
                    if contents.text == render(page.page) { settle(on: contents) } else { conflict = contents }
                } else {
                    adopt(contents, undoable: false)
                }
            }
        case .moved(let destination):
            handleMove(to: destination)
        case .missing:
            watcher?.rearm()
            handleDeletion()
        case .unreadable(let error):
            watcher?.rearm()
            readProblem = error.localizedDescription
        }
        refreshState()
    }

    private func settle(on contents: NoteFileContents) {
        diskText = contents.text
        format = contents.format
        baseline = page.page
        hasUnsavedChanges = false
        firstUnsavedEdit = nil
        autosaveTimer?.cancel()
        autosaveTimer = nil
    }

    private func settleConflict(on contents: NoteFileContents) {
        conflict = nil
        settle(on: contents)
    }

    private func adopt(_ contents: NoteFileContents, undoable: Bool) {
        let parsed = NoteFileReconciler.preservingIdentity(of: page.page, in: Self.parse(contents, kind: kind))
        let selection = NoteFileReconciler.mapSelection(page.selection, from: page.page, to: parsed)
        applyingDisk = true
        if undoable && !page.isReadOnly {
            page.edit("Use Their Version", kind: .replaced, selection: selection) { $0 = parsed }
        } else {
            page.replacePage(parsed, selection: selection, keepHistory: false)
        }
        applyingDisk = false
        forceNextSave = false
        lastSaveError = nil
        settle(on: contents)
        refreshState()
    }

    private func handleMove(to destination: URL) {
        let canonical = NoteFilePaths.canonical(destination)
        if NoteFilePaths.isInTrash(canonical) {
            watcher?.update(url: url)
            handleDeletion()
            refreshState()
            return
        }
        guard canonical.path != url.path else { return }
        relocate(to: canonical)
    }

    private func handleDeletion() {
        guard diskText != nil else { return }
        diskText = nil
        conflict = nil
        baseline = page.page
        hasUnsavedChanges = false
        forceNextSave = false
        firstUnsavedEdit = nil
        autosaveTimer?.cancel()
        autosaveTimer = nil
    }

    func noteWasTrashed() {
        handleDeletion()
        refreshState()
    }

    private func relocate(to destination: URL) {
        if Self.sessions[url.path] === self { Self.sessions[url.path] = nil }
        url = destination
        if !isClosed { Self.sessions[destination.path] = self }
        fileEnvironment.move(to: destination)
        watcher?.update(url: destination)
        urlChanges.send(destination)
    }

    private func pageChanged(_ change: NotePageChange) {
        guard change.kind != .selection, !applyingDisk else { return }
        if isClosed { reopen() }
        hasUnsavedChanges = true
        if firstUnsavedEdit == nil { firstUnsavedEdit = Self.clock.now }
        refreshState()
        scheduleAutosave()
    }

    private func scheduleAutosave() {
        guard conflict == nil, !isClosed else { return }
        autosaveTimer?.cancel()
        let waited = Self.clock.now.timeIntervalSince(firstUnsavedEdit ?? Self.clock.now)
        let delay = max(0, min(Self.autosaveDelay, Self.longestAutosaveWait - waited))
        autosaveTimer = Self.clock.schedule(after: delay) { [weak self] in self?.save() }
    }

    private func save() {
        autosaveTimer?.cancel()
        autosaveTimer = nil
        guard conflict == nil, hasUnsavedChanges || forceNextSave else { return }
        guard tickets.isEmpty else { return }
        guard let request = makeSaveRequest() else { return }
        let ticket = WriteTicket()
        tickets.append((ticket, request))
        refreshState()
        let presenter = watcher, kind = kind
        Self.worker.perform({ () -> NoteFileWriteOutcome in
            let outcome = NoteFileIO.write(request.data, text: request.text, to: request.url, kind: kind,
                                           expecting: request.expected, force: request.force, presenter: presenter)
            ticket.outcome = outcome
            return outcome
        }) { [weak self] _ in
            self?.complete(ticket)
        }
    }

    private func makeSaveRequest() -> SaveRequest? {
        let current = page.page
        let force = forceNextSave
        if !force && current == baseline {
            markClean(at: current)
            return nil
        }
        let text = render(current)
        if !force && text == diskText {
            markClean(at: current)
            return nil
        }
        let encoded = NoteFileText.encode(text, format: format)
        return SaveRequest(page: current, text: text, data: encoded.data, format: encoded.format, url: url,
                           expected: diskText, force: force)
    }

    private func markClean(at current: NotePage) {
        baseline = current
        hasUnsavedChanges = false
        firstUnsavedEdit = nil
        refreshState()
    }

    private func drainWrites() {
        guard !tickets.isEmpty else { return }
        Self.worker.sync {}
        for (ticket, _) in tickets { complete(ticket) }
    }

    private func complete(_ ticket: WriteTicket) {
        guard !ticket.handled, let outcome = ticket.outcome,
              let index = tickets.firstIndex(where: { $0.0 === ticket }) else { return }
        ticket.handled = true
        let request = tickets.remove(at: index).1
        switch outcome {
        case .written, .unchanged:
            diskText = request.text
            format = request.format
            baseline = request.page
            forceNextSave = false
            lastSaveError = nil
            if page.page == request.page {
                hasUnsavedChanges = false
                firstUnsavedEdit = nil
            }
            if case .written = outcome { watcher?.rearm() }
        case .conflict(let theirs):
            if theirs.text == render(page.page) {
                settle(on: theirs)
            } else {
                conflict = theirs
                autosaveTimer?.cancel()
                autosaveTimer = nil
            }
        case .failed(let message):
            lastSaveError = message
        }
        refreshState()
        if hasUnsavedChanges, conflict == nil, lastSaveError == nil, autosaveTimer == nil, tickets.isEmpty { scheduleAutosave() }
    }

    private func refreshState() {
        let next: NoteFileSaveState
        if conflict != nil { next = .conflict }
        else if let problem = lastSaveError ?? readProblem { next = .failed(problem) }
        else if !tickets.isEmpty { next = .saving }
        else if hasUnsavedChanges { next = .unsaved }
        else if diskText == nil { next = .missing }
        else { next = .saved }
        if state != next { state = next }
    }

    private func close() {
        isClosed = true
        autosaveTimer?.cancel()
        autosaveTimer = nil
        diskCheckTimer?.cancel()
        diskCheckTimer = nil
        watcher?.stop()
        watcher = nil
        if Self.sessions[url.path] === self { Self.sessions[url.path] = nil }
    }

    private func reopen() {
        isClosed = false
        if Self.sessions[url.path] == nil { Self.sessions[url.path] = self }
        startWatching()
    }
}

private final class NoteFileCoordinatedSave: @unchecked Sendable {
    let finished = DispatchSemaphore(value: 0)
    var error: Error?
}
