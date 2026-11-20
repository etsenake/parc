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
    case unsaved([String])
    case occupied(String)

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
        case .unsaved(let titles):
            let names = ListFormatter.localizedString(byJoining: titles.map { "“\($0)”" })
            return titles.count == 1 ? "Parc couldn’t save \(names) yet. Open it to sort things out."
                : "Parc couldn’t save \(names) yet. Open them to sort things out."
        case .occupied(let name): return "Something else is already called “\(name)” there. Move or rename it, then try again."
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

    private final class StagedDelivery: @unchecked Sendable {
        let write: NoteFileDisk.StagedWrite
        init(_ write: NoteFileDisk.StagedWrite) { self.write = write }
    }

    private static var sessions: [String: NoteFileSession] = [:]
    private static var live: [ObjectIdentifier: NoteFileSession] = [:]
    static var clock: NoteFileClock = NoteFileSystemClock.shared
    static var worker: NoteFileWorker = .files
    static var autosaveDelay: TimeInterval = 0.6
    static var longestAutosaveWait: TimeInterval = 5
    static var diskCheckDelay: TimeInterval = 0.12
    static var retryDelays: [TimeInterval] = [1, 2, 4, 8, 15, 30, 60]

    static func open(_ url: URL) throws -> NoteFileSession {
        guard url.isFileURL else { throw NoteFileError.notANote }
        let canonical = NoteFilePaths.canonical(url)
        let key = NoteFilePaths.identityKey(ofCanonicalPath: canonical.path)
        if let existing = sessions[key] { return existing }
        guard let kind = NoteFileKind(url: canonical) ?? NoteFileKind(url: url) else { throw NoteFileError.notANote }
        guard NoteFilePaths.isOpenableFile(canonical) else {
            throw NoteFilePaths.itemExists(canonical) ? NoteFileError.notANote : NoteFileError.missing
        }
        let read = try NoteFileIO.readStamped(canonical, kind: kind)
        let session = NoteFileSession(url: canonical, kind: kind, contents: read.contents)
        session.registryKey = key
        sessions[key] = session
        live[ObjectIdentifier(session)] = session
        session.startWatching(seen: read.stamp.map(NoteFileSighting.file))
        session.joinSyncedBlocks()
        return session
    }

    static func session(for url: URL) -> NoteFileSession? { sessions[NoteFilePaths.key(for: url)] }

    static var openSessions: [NoteFileSession] { Array(live.values) }

    static func flushAll() throws {
        var unsaved: [String] = []
        for session in live.values.sorted(by: { $0.url.path < $1.url.path }) {
            do { try session.flush() } catch {
                if session.preserveUnattendedConflict() { continue }
                unsaved.append(session.title)
            }
        }
        if !unsaved.isEmpty { throw NoteFileError.unsaved(unsaved) }
    }

    nonisolated static func render(_ value: NotePage, kind: NoteFileKind, format: NoteFileFormat, customEmoji: Set<String> = []) -> String {
        let body = kind == .markdown ? NoteMarkdown.serialize(value, customEmoji: customEmoji) : NotePlainText.serialize(value)
        return NoteFileText.fileText(body, format: format, kind: kind)
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
    private(set) var customEmoji: Set<String> = []
    private var emojiLibrary: NoteEmojiLibrary?
    private var emojiSubscription: AnyCancellable?

    private let fileEnvironment: NoteFileEnvironment
    private let disk: NoteFileDisk
    private var baseline: NotePage
    private var conflict: NoteFileContents?
    private var vanishedText: String?
    private var waitsForMissingFile = false
    private var forceNextSave = false
    private var firstUnsavedEdit: Date?
    private var autosaveTimer: NoteFileTimer?
    private var diskCheckTimer: NoteFileTimer?
    private var retryTimer: NoteFileTimer?
    private var retryAttempt = 0
    private var pendingMovePath: String?
    private var applyingDisk = false
    private var tickets: [(WriteTicket, SaveRequest)] = []
    private var watcher: NoteFileWatcher?
    private var changeSubscription: AnyCancellable?
    private var isClosed = false
    private var wasAttended = false
    private var registryKey = ""
    private var reportedMissing = false

    private init(url: URL, kind: NoteFileKind, contents: NoteFileContents) {
        self.url = url
        self.kind = kind
        format = contents.format
        disk = NoteFileDisk(text: contents.text)
        let library = kind == .markdown ? NoteEmojiLibrary.library(for: url) : nil
        let names = library?.names ?? []
        let parsed = Self.parse(contents, kind: kind, customEmoji: names)
        let session = NotePageSession(page: parsed)
        session.isFlat = kind == .plainText
        page = session
        baseline = session.page
        fileEnvironment = NoteFileEnvironment(documentURL: url, isPlainText: kind == .plainText)
        environment = fileEnvironment
        changeSubscription = page.changes.sink { [weak self] change in self?.pageChanged(change) }
        customEmoji = names
        follow(library)
    }

    private func follow(_ library: NoteEmojiLibrary?) {
        emojiLibrary = library
        emojiSubscription = library?.changes.sink { [weak self] in self?.emojiLibraryChanged() }
        emojiLibraryChanged()
    }

    private func emojiLibraryChanged() {
        let names = emojiLibrary?.names ?? []
        let added = names.subtracting(customEmoji)
        customEmoji = names
        guard !added.isEmpty else { return }
        let wasApplying = applyingDisk
        applyingDisk = true
        page.updateAllPagesMetadata { NoteCustomEmojiName.upgrading($0, names: added) }
        applyingDisk = wasApplying
        baseline = NoteCustomEmojiName.upgrading(baseline, names: added)
        refreshState()
    }

    var title: String { url.deletingPathExtension().lastPathComponent }

    var conflictingText: String? { conflict.map { NoteFileText.editableText($0, kind: kind) } }

    var isMissing: Bool { diskText == nil }

    var presenter: NSFilePresenter? { watcher }

    private var diskText: String? { disk.text }

    func retain() {
        if isClosed { reopen() }
        editorCount += 1
        wasAttended = true
    }

    func release() {
        guard editorCount > 0 else { return }
        editorCount -= 1
        guard editorCount == 0 else { return }
        do { try flush() } catch { scheduleRetry() }
        closeIfIdle()
    }

    func flush() throws {
        autosaveTimer?.cancel()
        autosaveTimer = nil
        drainWrites()
        if conflict != nil { throw NoteFileError.conflict }
        guard hasUnsavedChanges || forceNextSave else { return }
        var outcome = writeSynchronously()
        if case .missing? = outcome {
            locateSynchronously()
            if conflict != nil { throw NoteFileError.conflict }
            guard hasUnsavedChanges || forceNextSave else { return }
            outcome = writeSynchronously()
        }
        if let error = outcome?.error { throw error }
    }

    func restore() throws {
        autosaveTimer?.cancel()
        autosaveTimer = nil
        drainWrites()
        if conflict != nil { throw NoteFileError.conflict }
        guard diskText == nil else { return try flush() }
        let current = page.page
        let text = current == baseline ? vanishedText ?? render(current) : render(current)
        let encoded = NoteFileText.encode(text, format: format)
        let target = url, kind = kind, presenter = watcher, disk = disk
        let outcome = Self.worker.sync {
            NoteFileIO.write(encoded.data, text: text, to: target, kind: kind, disk: disk, force: false, presenter: presenter)
        }
        switch outcome {
        case .written, .unchanged:
            forceNextSave = false
            record(outcome, page: current, text: text, format: encoded.format, force: false)
            if case .unchanged = outcome { watcher?.rearm(seen: NoteFileStamp(path: target.path).map(NoteFileSighting.file)) }
        case .conflict:
            throw NoteFileError.occupied(target.lastPathComponent)
        case .missing:
            throw NoteFileError.missing
        case .failed(let message):
            if NoteFilePaths.itemExists(target) { throw NoteFileError.occupied(target.lastPathComponent) }
            throw NoteFileError.unwritable(message)
        }
    }

    func resolveConflict(keepMine: Bool) {
        guard let theirs = conflict else { return }
        conflict = nil
        if keepMine {
            disk.adopt(theirs.text)
            forceNextSave = true
            hasUnsavedChanges = true
            if firstUnsavedEdit == nil { firstUnsavedEdit = Self.clock.now }
            refreshState()
            save()
        } else {
            adopt(theirs, undoable: true)
        }
        closeIfIdle()
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
        let target = url, kind = kind, presenter = watcher, generation = disk.generation
        let moved = pendingMovePath ?? watcher?.movedPath()
        pendingMovePath = nil
        Self.worker.perform({ NoteFileIO.probe(target, kind: kind, movedPath: moved, presenter: presenter) }) { [weak self] probe in
            self?.apply(probe, checked: target, generation: generation)
        }
    }

    func noteWasTrashed() {
        handleDeletion()
        refreshState()
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

    private static func parse(_ contents: NoteFileContents, kind: NoteFileKind, customEmoji: Set<String>) -> NotePage {
        let text = NoteFileText.editableText(contents, kind: kind)
        return kind == .markdown ? NoteMarkdown.parse(text, customEmoji: customEmoji) : NotePlainText.parse(text)
    }

    private func render(_ value: NotePage) -> String { Self.render(value, kind: kind, format: format, customEmoji: customEmoji) }

    private func startWatching(seen: NoteFileSighting?) {
        let events: @Sendable (NoteFileWatchEvent) -> Void = { [weak self] event in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.handle(event) } }
        }
        let disk = disk
        let saveRequest: NoteFileWatcher.SaveRequest = { [weak self] completion in
            guard let written = disk.writeStaged() else {
                completion(nil)
                return
            }
            let delivery = StagedDelivery(written)
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.finishStagedWrite(delivery.write) } }
            completion(written.outcome.error)
        }
        let watcher = NoteFileWatcher(url: url, events: events, saveRequest: saveRequest)
        self.watcher = watcher
        watcher.start(seen: seen)
    }

    private func scheduleDiskCheck() {
        diskCheckTimer?.cancel()
        diskCheckTimer = Self.clock.schedule(after: Self.diskCheckDelay) { [weak self] in self?.checkDisk() }
    }

    private func locateSynchronously() {
        let target = url, kind = kind, presenter = watcher, generation = disk.generation
        let moved = pendingMovePath ?? watcher?.movedPath()
        pendingMovePath = nil
        let probe = Self.worker.sync { NoteFileIO.probe(target, kind: kind, movedPath: moved, presenter: presenter) }
        apply(probe, checked: target, generation: generation)
    }

    private func apply(_ probe: NoteFileProbe, checked target: URL, generation: Int) {
        guard !isClosed, target == url else { return }
        guard disk.generation == generation else {
            scheduleDiskCheck()
            return
        }
        if case .unreadable = probe {} else { readProblem = nil }
        switch probe {
        case .contents(let contents, let stamp):
            guard tickets.isEmpty else {
                scheduleDiskCheck()
                return
            }
            watcher?.rearm(seen: stamp.map(NoteFileSighting.file))
            absorb(contents)
        case .moved(let destination):
            handleMove(to: destination)
        case .missing:
            watcher?.rearm(seen: .absent)
            handleDeletion()
        case .unreadable(let error):
            watcher?.rearm()
            readProblem = error.localizedDescription
        }
        refreshState()
        resumeAutosaveIfNeeded()
        closeIfIdle()
    }

    private func absorb(_ contents: NoteFileContents) {
        let returning = vanishedText
        vanishedText = nil
        waitsForMissingFile = false
        if conflict != nil {
            if contents.text == render(page.page) { settleConflict(on: contents) } else { conflict = contents }
            return
        }
        guard contents.text != diskText else { return }
        guard hasUnsavedChanges && page.page != baseline else {
            adopt(contents, undoable: false)
            return
        }
        if contents.text == render(page.page) {
            settle(on: contents)
        } else if diskText == nil, contents.text == returning {
            resume(on: contents)
        } else {
            conflict = contents
            autosaveTimer?.cancel()
            autosaveTimer = nil
        }
    }

    private func settle(on contents: NoteFileContents) {
        disk.adopt(contents.text)
        format = contents.format
        baseline = page.page
        hasUnsavedChanges = false
        forceNextSave = false
        waitsForMissingFile = false
        vanishedText = nil
        firstUnsavedEdit = nil
        autosaveTimer?.cancel()
        autosaveTimer = nil
    }

    private func settleConflict(on contents: NoteFileContents) {
        conflict = nil
        settle(on: contents)
    }

    private func resume(on contents: NoteFileContents) {
        disk.adopt(contents.text)
        format = contents.format
        vanishedText = nil
        waitsForMissingFile = false
    }

    private func adopt(_ contents: NoteFileContents, undoable: Bool) {
        let parsed = NoteFileReconciler.preservingIdentity(of: page.page, in: Self.parse(contents, kind: kind, customEmoji: customEmoji))
        let selection = NoteFileReconciler.mapSelection(page.selection, from: page.page, to: parsed)
        applyingDisk = true
        if undoable && !page.isReadOnly {
            page.edit("Use the File’s Version", kind: .replaced, selection: selection) { $0 = parsed }
        } else {
            page.replacePage(parsed, selection: selection, keepHistory: false)
        }
        applyingDisk = false
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
        resumeAutosaveIfNeeded()
    }

    private func handleDeletion() {
        guard diskText != nil else { return }
        vanishedText = diskText
        disk.adopt(nil)
        conflict = nil
        autosaveTimer?.cancel()
        autosaveTimer = nil
        if hasUnsavedChanges || forceNextSave { waitsForMissingFile = true }
    }

    private func relocate(to destination: URL) {
        let previous = url
        if Self.sessions[registryKey] === self { Self.sessions[registryKey] = nil }
        url = destination
        registryKey = NoteFilePaths.identityKey(ofCanonicalPath: destination.path)
        if !isClosed, Self.sessions[registryKey] == nil { Self.sessions[registryKey] = self }
        fileEnvironment.move(to: destination)
        watcher?.update(url: destination)
        if kind == .markdown {
            let library = NoteEmojiLibrary.library(for: destination)
            if library !== emojiLibrary { follow(library) }
        }
        urlChanges.send(destination)
        NoteLibrary.noteDidMove(from: previous, to: destination)
    }

    private func pageChanged(_ change: NotePageChange) {
        guard change.kind != .selection, !applyingDisk else { return }
        if isClosed { reopen() }
        waitsForMissingFile = false
        hasUnsavedChanges = true
        if firstUnsavedEdit == nil { firstUnsavedEdit = Self.clock.now }
        refreshState()
        scheduleAutosave()
    }

    private func scheduleAutosave() {
        guard conflict == nil, !waitsForMissingFile, !isClosed else { return }
        autosaveTimer?.cancel()
        let waited = Self.clock.now.timeIntervalSince(firstUnsavedEdit ?? Self.clock.now)
        let delay = max(0, min(Self.autosaveDelay, Self.longestAutosaveWait - waited))
        autosaveTimer = Self.clock.schedule(after: delay) { [weak self] in self?.save() }
    }

    private func resumeAutosaveIfNeeded() {
        guard hasUnsavedChanges || forceNextSave, conflict == nil, !waitsForMissingFile, lastSaveError == nil,
              autosaveTimer == nil, tickets.isEmpty, !isClosed else { return }
        scheduleAutosave()
    }

    private func save() {
        autosaveTimer?.cancel()
        autosaveTimer = nil
        guard conflict == nil, !waitsForMissingFile, hasUnsavedChanges || forceNextSave, tickets.isEmpty else { return }
        guard let request = makeSaveRequest() else { return }
        let ticket = WriteTicket()
        tickets.append((ticket, request))
        refreshState()
        let presenter = watcher, kind = kind, disk = disk
        Self.worker.perform({ () -> NoteFileWriteOutcome in
            let outcome = NoteFileIO.write(request.data, text: request.text, to: request.url, kind: kind, disk: disk,
                                           force: request.force, presenter: presenter)
            ticket.outcome = outcome
            return outcome
        }) { [weak self] _ in
            self?.complete(ticket)
        }
    }

    private func writeSynchronously() -> NoteFileWriteOutcome? {
        guard let request = makeSaveRequest() else { return nil }
        let ticket = WriteTicket()
        tickets.append((ticket, request))
        refreshState()
        let presenter = watcher, kind = kind, disk = disk
        let outcome = Self.worker.sync {
            NoteFileIO.write(request.data, text: request.text, to: request.url, kind: kind, disk: disk,
                             force: request.force, presenter: presenter)
        }
        ticket.outcome = outcome
        complete(ticket)
        return outcome
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
        return SaveRequest(page: current, text: text, data: encoded.data, format: encoded.format, url: url, force: force)
    }

    private func markClean(at current: NotePage) {
        baseline = current
        hasUnsavedChanges = false
        waitsForMissingFile = false
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
        record(outcome, page: request.page, text: request.text, format: request.format, force: request.force)
    }

    private func finishStagedWrite(_ write: NoteFileDisk.StagedWrite) {
        record(write.outcome, page: write.staged.page, text: write.text, format: write.format, force: write.staged.force)
    }

    private func record(_ outcome: NoteFileWriteOutcome, page written: NotePage, text: String, format writtenFormat: NoteFileFormat,
                        force: Bool) {
        switch outcome {
        case .written, .unchanged:
            if diskText == text {
                format = writtenFormat
                baseline = written
                if page.page == written {
                    hasUnsavedChanges = false
                    waitsForMissingFile = false
                    firstUnsavedEdit = nil
                }
            }
            if force { forceNextSave = false }
            lastSaveError = nil
            vanishedText = nil
            retryAttempt = 0
            retryTimer?.cancel()
            retryTimer = nil
            if case .written(let stamp) = outcome { watcher?.rearm(seen: stamp.map(NoteFileSighting.file)) }
        case .conflict(let theirs):
            if theirs.text == render(page.page) {
                settle(on: theirs)
            } else {
                conflict = theirs
                autosaveTimer?.cancel()
                autosaveTimer = nil
            }
        case .missing:
            scheduleDiskCheck()
            refreshState()
            return
        case .failed(let message):
            lastSaveError = message
            scheduleRetry()
        }
        refreshState()
        resumeAutosaveIfNeeded()
        closeIfIdle()
    }

    private func scheduleRetry() {
        guard editorCount == 0, !isClosed, lastSaveError != nil, conflict == nil, retryTimer == nil else { return }
        let delays = Self.retryDelays.isEmpty ? [60] : Self.retryDelays
        let delay = delays[min(retryAttempt, delays.count - 1)]
        retryAttempt += 1
        retryTimer = Self.clock.schedule(after: delay) { [weak self] in
            guard let self else { return }
            self.retryTimer = nil
            guard self.editorCount == 0, !self.isClosed else { return }
            do { try self.flush() } catch { self.scheduleRetry() }
            self.closeIfIdle()
        }
    }

    private func preserveUnattendedConflict() -> Bool {
        guard editorCount == 0, conflict != nil else { return false }
        let folder = url.deletingLastPathComponent()
        let base = NoteFileNaming.sanitizedTitle(title + " (your version)")
        let target = NoteFileNaming.uniqueURL(in: folder, base: base.isEmpty ? NoteFileNaming.untitled : base,
                                              pathExtension: url.pathExtension)
        let data = NoteFileText.encode(render(page.page), format: format).data
        do { try Self.worker.sync { try data.write(to: target, options: .withoutOverwriting) } } catch { return false }
        conflict = nil
        hasUnsavedChanges = false
        forceNextSave = false
        refreshState()
        close()
        return true
    }

    private func joinSyncedBlocks() {
        reportedMissing = isMissing
        NoteSyncedBlocks.shared.useNoteFiles()
        NoteSyncedBlocks.shared.attach(page, location: { [weak self] in self?.url }, isAvailable: { [weak self] in
            guard let self else { return false }
            return !self.isClosed && !self.isMissing
        })
    }

    private func refreshState() {
        if isMissing != reportedMissing {
            reportedMissing = isMissing
            NoteSyncedBlocks.shared.availabilityChanged(page)
        }
        let next: NoteFileSaveState
        if conflict != nil { next = .conflict }
        else if let problem = lastSaveError ?? readProblem { next = .failed(problem) }
        else if !tickets.isEmpty { next = .saving }
        else if waitsForMissingFile { next = .missing }
        else if hasUnsavedChanges { next = .unsaved }
        else if diskText == nil { next = .missing }
        else { next = .saved }
        if state != next { state = next }
        stageForPresenter()
    }

    private func stageForPresenter() {
        let ready = (hasUnsavedChanges || forceNextSave) && conflict == nil && !waitsForMissingFile && !isClosed
        disk.stage(ready ? NoteFileDisk.Staged(page: page.page, kind: kind, format: format, url: url, force: forceNextSave,
                                                    customEmoji: customEmoji) : nil)
    }

    private func closeIfIdle() {
        guard !isClosed, editorCount == 0, wasAttended, !hasUnsavedChanges, !forceNextSave, conflict == nil, tickets.isEmpty
        else { return }
        close()
    }

    private func close() {
        isClosed = true
        autosaveTimer?.cancel()
        autosaveTimer = nil
        diskCheckTimer?.cancel()
        diskCheckTimer = nil
        retryTimer?.cancel()
        retryTimer = nil
        disk.stage(nil)
        watcher?.stop()
        watcher = nil
        if Self.sessions[registryKey] === self { Self.sessions[registryKey] = nil }
        Self.live[ObjectIdentifier(self)] = nil
        NoteSyncedBlocks.shared.detach(page)
    }

    private func reopen() {
        isClosed = false
        wasAttended = true
        Self.live[ObjectIdentifier(self)] = self
        if Self.sessions[registryKey] == nil { Self.sessions[registryKey] = self }
        startWatching(seen: nil)
        joinSyncedBlocks()
    }
}
