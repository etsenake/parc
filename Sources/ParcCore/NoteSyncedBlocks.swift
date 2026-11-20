import Combine
import Foundation

struct NoteSyncedGroup: Hashable {
    var file: String
    var anchor: String
}

struct NoteSyncedReference: Equatable {
    var path: String?
    var anchor: String

    init?(_ target: String) {
        guard let hash = target.lastIndex(of: "#") else { return nil }
        let fragment = String(target[target.index(after: hash)...])
        let anchor = fragment.removingPercentEncoding ?? fragment
        guard NoteAnchor.isValid(anchor) else { return nil }
        let path = String(target[..<hash])
        self.path = path.isEmpty ? nil : path
        self.anchor = anchor
    }

    func url(relativeTo document: URL?) -> URL? {
        guard let path else { return document }
        if path.lowercased().hasPrefix("file:"), let url = URL(string: path), url.isFileURL {
            return URL(fileURLWithPath: url.path)
        }
        let decoded = path.removingPercentEncoding ?? path
        if decoded.hasPrefix("/") { return URL(fileURLWithPath: decoded) }
        if decoded == "~" || decoded.hasPrefix("~/") { return URL(fileURLWithPath: (decoded as NSString).expandingTildeInPath) }
        guard let document else { return nil }
        return URL(fileURLWithPath: decoded, relativeTo: document.deletingLastPathComponent()).standardizedFileURL
    }

    static func target(anchor: String, original: URL?, from document: URL?) -> String {
        let fragment = "#" + NoteFilePaths.encodedSegment(anchor)
        guard let original else { return fragment }
        if let document, NoteFilePaths.key(for: document) == NoteFilePaths.key(for: original) { return fragment }
        let file = URL(fileURLWithPath: original.path)
        if let folder = document?.deletingLastPathComponent(), let relative = NoteFilePaths.relativePath(from: folder, to: file) {
            return relative + fragment
        }
        return file.absoluteString + fragment
    }
}

struct NoteSyncedInfo: Equatable {
    var isOriginal: Bool
    var isMissing: Bool
    var anchor: String?
    var originalURL: URL?
    var originalBlock: NoteBlockID?
    var notes: [URL]
}

@MainActor
final class NoteSyncedLease {
    nonisolated(unsafe) private var ending: (() -> Void)?

    init(_ ending: @escaping () -> Void) { self.ending = ending }

    func end() {
        let pending = ending
        ending = nil
        pending?()
    }

    deinit {
        guard let pending = ending else { return }
        DispatchQueue.main.async { MainActor.assumeIsolated { pending() } }
    }
}

@MainActor
final class NoteSyncedEdit {
    fileprivate weak var engine: NoteSyncedBlocks?
    fileprivate var groups: Set<NoteSyncedGroup> = []
    fileprivate var after: [NoteSyncedGroup: [NoteBlock]] = [:]
    fileprivate var leases: [NoteSyncedLease] = []
    private(set) var isApplied = true
    let name: String

    fileprivate init(engine: NoteSyncedBlocks, name: String) {
        self.engine = engine
        self.name = name
    }

    var owner: ObjectIdentifier { ObjectIdentifier(self) }

    fileprivate func mark(applied: Bool) -> Bool {
        guard isApplied != applied else { return false }
        isApplied = applied
        return true
    }

    func effect(for session: NotePageSession) -> NoteUndoEffect {
        NoteUndoEffect(undo: { [weak session] in
            guard let session else { return }
            self.engine?.reverse(self, by: session)
        }, redo: { [weak session] in
            guard let session else { return }
            self.engine?.reapply(self, by: session)
        }, owner: owner)
    }

    func reversal(for session: NotePageSession) -> NoteUndoEffect {
        NoteUndoEffect(undo: { [weak session] in
            guard let session else { return }
            self.engine?.reapply(self, by: session)
        }, redo: { [weak session] in
            guard let session else { return }
            self.engine?.reverse(self, by: session)
        }, owner: owner)
    }
}

@MainActor
final class NoteSyncedUnsync {
    fileprivate var leases: [NoteSyncedLease] = []
    fileprivate var sessions: [() -> NotePageSession?] = []
    private var isApplied = true

    var owner: ObjectIdentifier { ObjectIdentifier(self) }

    fileprivate func effect(for session: NotePageSession, retaining: Bool) -> NoteUndoEffect {
        if retaining {
            return NoteUndoEffect(undo: { [weak session] in self.retrace(undoing: true, from: session) },
                                  redo: { [weak session] in self.retrace(undoing: false, from: session) }, owner: owner)
        }
        return NoteUndoEffect(undo: { [weak self, weak session] in self?.retrace(undoing: true, from: session) },
                              redo: { [weak self, weak session] in self?.retrace(undoing: false, from: session) }, owner: owner)
    }

    private func retrace(undoing: Bool, from origin: NotePageSession?) {
        guard isApplied == undoing else { return }
        isApplied = !undoing
        for entry in sessions {
            guard let other = entry(), other !== origin else { continue }
            if undoing { other.undo(ifTopBelongsTo: owner) } else { other.redo(ifTopBelongsTo: owner) }
        }
    }
}

@MainActor
final class NoteSyncedBlocks {
    static let shared = NoteSyncedBlocks()

    static let stepName = "Synced Edit"

    @MainActor
    fileprivate final class Document {
        weak var session: NotePageSession?
        let location: () -> URL?
        let isAvailable: () -> Bool
        var subscription: AnyCancellable?
        var seen: [NoteBlockID: [NoteBlock]] = [:]
        var sites: [NoteBlockID]?
        var link: (token: Int, edit: NoteSyncedEdit)?
        private var cachedLocation: URL?
        private var cachedKey: String?
        private var targetKeys: [String: String] = [:]

        init(session: NotePageSession, location: @escaping () -> URL?, isAvailable: @escaping () -> Bool) {
            self.session = session
            self.location = location
            self.isAvailable = isAvailable
        }

        var url: URL? { location() }

        var key: String? {
            guard let url = location() else { return nil }
            if url != cachedLocation {
                cachedLocation = url
                cachedKey = NoteFilePaths.key(for: url)
                targetKeys = [:]
            }
            return cachedKey
        }

        func key(for reference: NoteSyncedReference) -> String? {
            let own = key
            guard let path = reference.path else { return own }
            if let known = targetKeys[path] { return known }
            guard let url = reference.url(relativeTo: location()) else { return nil }
            let value = NoteFilePaths.key(for: url)
            targetKeys[path] = value
            return value
        }

        func currentSites() -> [NoteBlockID] {
            if let sites { return sites }
            let found = session?.page.syncedSites().map(\.id) ?? []
            sites = found
            return found
        }
    }

    let changes = PassthroughSubject<Void, Never>()
    var opener: @MainActor (URL) -> NoteSyncedLease? = { _ in nil }
    var originalFinder: @MainActor (String, URL) -> [URL] = { _, _ in [] }
    var noteFinder: @MainActor (String, URL) -> [URL] = { _, _ in [] }
    var libraryChanges: @MainActor (URL) -> AnyPublisher<Void, Never>? = { _ in nil }
    var usesNoteFiles = false
    private var documents: [ObjectIdentifier: Document] = [:]
    private var depth = 0
    private var pendingReconcile: Set<NoteSyncedGroup> = []
    private var suppressed: Set<NoteSyncedGroup> = []
    private var pendingRewrites: [(session: NotePageSession, block: NoteBlockID, change: (inout NoteBlock) -> Void)] = []
    private var announce = false

    init() {}

    func attach(_ session: NotePageSession, location: @escaping () -> URL?, isAvailable: @escaping () -> Bool = { true }) {
        let key = ObjectIdentifier(session)
        guard documents[key] == nil else { return }
        let document = Document(session: session, location: location, isAvailable: isAvailable)
        document.subscription = session.settled.sink { [weak self, weak document] change in
            guard let self, let document else { return }
            self.settled(change, in: document)
        }
        documents[key] = document
        batch {
            pendingReconcile.formUnion(groups(in: document))
            refreshSeen(document)
            announce = true
        }
    }

    func detach(_ session: NotePageSession) {
        guard let document = documents.removeValue(forKey: ObjectIdentifier(session)) else { return }
        document.subscription = nil
        changes.send()
    }

    func isAttached(_ session: NotePageSession) -> Bool { documents[ObjectIdentifier(session)] != nil }

    func availabilityChanged(_ session: NotePageSession) {
        guard let document = documents[ObjectIdentifier(session)] else { return }
        batch {
            pendingReconcile.formUnion(groups(in: document))
            announce = true
        }
    }

    func url(of session: NotePageSession) -> URL? { documents[ObjectIdentifier(session)]?.url }

    func info(for id: NoteBlockID, in session: NotePageSession) -> NoteSyncedInfo? {
        guard let block = session.page.block(id), block.kind == .synced else { return nil }
        let document = documents[ObjectIdentifier(session)]
        let group = document.flatMap { group(of: block, in: $0) }
        let original = group.flatMap(original(of:))
        let isOriginal = block.isSyncedOriginal
        let anchor = isOriginal ? block.props.anchor : block.props.target.flatMap(NoteSyncedReference.init)?.anchor
        return NoteSyncedInfo(isOriginal: isOriginal, isMissing: !isOriginal && original == nil, anchor: anchor,
                              originalURL: original?.0.url, originalBlock: original?.1.id,
                              notes: group.map { notes(sharing: $0, besides: document) } ?? [])
    }

    private func notes(sharing group: NoteSyncedGroup, besides document: Document?) -> [URL] {
        let own = document?.key
        var found: [(url: URL, key: String)] = []
        var keys = Set<String>()
        var open = Set<String>()
        for other in documents.values {
            guard let key = other.key, let url = other.url else { continue }
            open.insert(key)
            guard key != own, other.isAvailable(), sites(in: other).contains(where: { self.group(of: $0, in: other) == group }),
                  keys.insert(key).inserted else { continue }
            found.append((url, key))
        }
        if let here = document?.url {
            for url in noteFinder(group.anchor, here) {
                let key = NoteFilePaths.key(for: url)
                guard key != own, !open.contains(key), keys.insert(key).inserted else { continue }
                found.append((url, key))
            }
        }
        found.sort { lhs, rhs in
            if (lhs.key == group.file) != (rhs.key == group.file) { return lhs.key == group.file }
            return lhs.url.deletingPathExtension().lastPathComponent.localizedStandardCompare(rhs.url.deletingPathExtension().lastPathComponent)
                == .orderedAscending
        }
        return found.map(\.url)
    }

    func originalKey(for id: NoteBlockID, in session: NotePageSession) -> String? {
        guard let document = documents[ObjectIdentifier(session)], let block = session.page.block(id) else { return nil }
        return group(of: block, in: document)?.file
    }

    func originalSession(for id: NoteBlockID, in session: NotePageSession) -> (session: NotePageSession, block: NoteBlockID)? {
        guard let document = documents[ObjectIdentifier(session)], let block = session.page.block(id),
              let group = group(of: block, in: document), let found = original(of: group), let other = found.0.session else { return nil }
        return (other, found.1.id)
    }

    func referencedOriginals(in session: NotePageSession) -> [(url: URL, anchor: String, resolved: Bool)] {
        guard let document = documents[ObjectIdentifier(session)] else { return [] }
        var result: [(url: URL, anchor: String, resolved: Bool)] = []
        var seenKeys = Set<NoteSyncedGroup>()
        for block in sites(in: document) where block.isSyncedCopy {
            guard let target = block.props.target, let reference = NoteSyncedReference(target),
                  let direct = reference.url(relativeTo: document.url) else { continue }
            let group = group(of: block, in: document)
            let found = group.flatMap(original(of:))
            let url = found?.0.url ?? direct
            let key = group ?? NoteSyncedGroup(file: NoteFilePaths.key(for: direct), anchor: reference.anchor)
            guard seenKeys.insert(key).inserted else { continue }
            result.append((url, reference.anchor, found != nil))
        }
        return result
    }

    func reference(for id: NoteBlockID, in session: NotePageSession) -> NoteBlock? {
        guard let block = session.page.block(id), block.kind == .synced else { return nil }
        let document = documents[ObjectIdentifier(session)]
        let here = document?.url
        let folder = here?.deletingLastPathComponent()
        var reference = NoteBlock(.synced, children: block.children)
        if block.isSyncedOriginal {
            guard let anchor = session.ensureAnchor(for: id) else { return nil }
            reference.props.target = NoteSyncedReference.portableTarget(anchor: anchor, original: here, folder: folder)
        } else if let document, let group = group(of: block, in: document), let found = original(of: group) {
            reference.props.target = NoteSyncedReference.portableTarget(anchor: group.anchor, original: found.0.url, folder: folder)
        } else {
            reference.props.target = block.portableSyncedTargets(documentURL: here).props.target
        }
        return reference
    }

    @discardableResult
    func unsyncAll(_ id: NoteBlockID, in session: NotePageSession) -> Int {
        guard let block = session.page.block(id), block.isSyncedOriginal else { return 0 }
        guard let document = documents[ObjectIdentifier(session)], let group = group(of: block, in: document) else {
            session.unsync(id, name: "Unsync All")
            return 0
        }
        let action = NoteSyncedUnsync()
        if let here = document.url {
            let open = Set(documents.values.compactMap(\.key))
            for url in noteFinder(group.anchor, here) where !open.contains(NoteFilePaths.key(for: url)) {
                if let lease = opener(url) { action.leases.append(lease) }
            }
        }
        var copies = 0
        batch {
            for (other, site) in allSites(of: group) where !site.isSyncedOriginal {
                guard let otherSession = other.session, otherSession !== session else { continue }
                let placement = otherSession.page.syncedPlacement(of: site.id)
                let children = site.children.isEmpty ? [NoteBlock.paragraph()] : site.children
                otherSession.applyLinked("Unsync All", owner: action.owner, effect: { action.effect(for: otherSession, retaining: false) },
                                         origin: self) { page in
                    page.remove(site.id)
                    if !page.insert(children, placement) { page.insert(children, .top(page.blocks.count)) }
                }
                action.sessions.append { [weak otherSession] in otherSession }
                copies += 1
            }
            let local = sites(in: document).filter { !$0.isSyncedOriginal && self.group(of: $0, in: document) == group }.map(\.id)
            copies += local.count
            session.group("Unsync All") {
                for copy in local { session.unsync(copy, name: "Unsync All") }
                session.unsync(id, name: "Unsync All", effect: action.effect(for: session, retaining: true))
            }
            action.sessions.append { [weak session] in session }
            announce = true
        }
        return copies
    }

    func hold(_ session: NotePageSession) -> NoteSyncedHold {
        NoteSyncedHold(engine: self, session: session)
    }

    func reconcileAll() {
        batch {
            for document in documents.values { pendingReconcile.formUnion(groups(in: document)) }
        }
    }

    func batch(_ body: () -> Void) {
        depth += 1
        body()
        depth -= 1
        guard depth == 0 else { return }
        flush()
    }

    private func flush() {
        var rounds = 0
        while (!pendingReconcile.isEmpty || !pendingRewrites.isEmpty) && rounds < 8 {
            rounds += 1
            depth += 1
            let groups = pendingReconcile.subtracting(suppressed)
            pendingReconcile.subtract(groups)
            for group in groups { reconcile(group) }
            let rewrites = pendingRewrites
            pendingRewrites = []
            for rewrite in rewrites { rewrite.session.updateBlockMetadata(rewrite.block, kind: .structure, rewrite.change) }
            depth -= 1
            if pendingReconcile.isSubset(of: suppressed) { break }
        }
        if announce {
            announce = false
            changes.send()
        }
    }

    private func settled(_ change: NotePageChange, in document: Document) {
        guard document.session != nil, change.kind != .selection, change.kind != .settings else { return }
        if change.kind != .text { document.sites = nil }
        if change.origin == ObjectIdentifier(self) {
            refreshSeen(document)
            return
        }
        batch {
            if change.isUndoRedo || change.kind == .replaced {
                pendingReconcile.formUnion(groups(in: document))
                refreshSeen(document)
                announce = true
            } else {
                propagate(change, from: document)
            }
        }
    }

    private func refreshSeen(_ document: Document) {
        guard let page = document.session?.page else { return }
        var next: [NoteBlockID: [NoteBlock]] = [:]
        for id in document.currentSites() {
            if let block = page.block(id) { next[id] = block.children }
        }
        document.seen = next
    }

    private func affectedSites(_ change: NotePageChange, in document: Document) -> [NoteBlockID] {
        guard let page = document.session?.page else { return [] }
        let all = document.currentSites()
        guard change.kind == .text, !change.blocks.isEmpty else { return all }
        let known = Set(all)
        var found = Set<NoteBlockID>()
        for id in change.blocks {
            if known.contains(id) { found.insert(id); continue }
            if let site = page.ancestors(of: id).last(where: known.contains) { found.insert(site) }
        }
        return all.filter(found.contains)
    }

    private func propagate(_ change: NotePageChange, from document: Document) {
        guard let session = document.session else { return }
        let page = session.page
        let current = Set(document.currentSites())
        if document.seen.keys.contains(where: { !current.contains($0) }) { announce = true }
        var pending: [(group: NoteSyncedGroup, content: [NoteBlock], source: NoteBlockID)] = []
        var handled = Set<NoteSyncedGroup>()
        for id in affectedSites(change, in: document) {
            guard let block = page.block(id) else { continue }
            let previous = document.seen[id]
            document.seen[id] = block.children
            guard let previous else {
                arrived(block, in: document)
                continue
            }
            guard let group = group(of: block, in: document) else { continue }
            guard previous != block.children, !handled.contains(group), let original = original(of: group) else { continue }
            handled.insert(group)
            let content = block.isSyncedOriginal ? block.children
                : Self.unmapped(block.children, key: block.id, restoringAnchorsFrom: original.1.children)
            pending.append((group, content, id))
        }
        for id in current where document.seen[id] == nil {
            if let block = page.block(id) {
                document.seen[id] = block.children
                arrived(block, in: document)
            }
        }
        for id in document.seen.keys where !current.contains(id) { document.seen[id] = nil }
        guard !pending.isEmpty else { return }
        let edit = currentEdit(for: document, session: session)
        for item in pending {
            edit.groups.insert(item.group)
            edit.after[item.group] = item.content
            spread(item.content, of: item.group, skipping: (document, item.source), edit: edit)
        }
    }

    private func arrived(_ block: NoteBlock, in document: Document) {
        announce = true
        if block.isSyncedOriginal, let anchor = block.props.anchor, let session = document.session,
           let twin = documents.values.lazy.compactMap({ other -> (Document, NoteBlock)? in
               guard other.isAvailable(), let found = self.sites(in: other).first(where: {
                   $0.id != block.id && $0.isSyncedOriginal && $0.props.anchor == anchor
               }) else { return nil }
               return (other, found)
           }).first {
            let target = NoteSyncedReference.target(anchor: anchor, original: twin.0.url, from: document.url)
            pendingRewrites.append((session, block.id, { block in
                block.props.anchor = nil
                block.props.target = target
            }))
            if let key = twin.0.key { pendingReconcile.insert(NoteSyncedGroup(file: key, anchor: anchor)) }
            return
        }
        if let group = group(of: block, in: document) { pendingReconcile.insert(group) }
    }

    private func currentEdit(for document: Document, session: NotePageSession) -> NoteSyncedEdit {
        if let link = document.link, link.edit.isApplied, let token = session.historyToken, link.token == token { return link.edit }
        let edit = NoteSyncedEdit(engine: self, name: session.undoActionName ?? Self.stepName)
        session.attachToLastStep(edit.effect(for: session))
        if let token = session.historyToken { document.link = (token, edit) } else { document.link = nil }
        return edit
    }

    private func spread(_ content: [NoteBlock], of group: NoteSyncedGroup, skipping source: (Document, NoteBlockID)?, edit: NoteSyncedEdit) {
        for (other, block) in allSites(of: group) {
            if let source, source.0 === other, source.1 == block.id { continue }
            guard let otherSession = other.session else { continue }
            let target = block.isSyncedOriginal ? content : Self.mapped(content, key: block.id)
            guard block.children != target else { continue }
            otherSession.applyLinked(Self.stepName, owner: edit.owner, effect: { edit.effect(for: otherSession) }, origin: self) { page in
                page.update(block.id) { $0.children = target }
            }
            other.seen[block.id] = otherSession.page.block(block.id)?.children
        }
    }

    fileprivate func reverse(_ edit: NoteSyncedEdit, by session: NotePageSession) {
        guard edit.mark(applied: false) else { return }
        batch {
            for group in edit.groups {
                guard let content = content(of: group, in: session) else { continue }
                settleOriginal(of: group, to: content, edit: edit, undoing: true, except: session)
            }
            retraceCopies(of: edit, undoing: true, except: session)
        }
    }

    fileprivate func reapply(_ edit: NoteSyncedEdit, by session: NotePageSession) {
        guard edit.mark(applied: true) else { return }
        let local = Set(edit.groups.filter { group in original(of: group)?.0.session === session })
        suppressed.formUnion(local)
        batch {
            for group in edit.groups {
                guard let content = edit.after[group] else { continue }
                settleOriginal(of: group, to: content, edit: edit, undoing: false, except: session)
            }
            retraceCopies(of: edit, undoing: false, except: session)
        }
        suppressed.subtract(local)
        pendingReconcile.subtract(local)
    }

    private func settleOriginal(of group: NoteSyncedGroup, to content: [NoteBlock], edit: NoteSyncedEdit, undoing: Bool,
                                except session: NotePageSession) {
        guard let found = original(of: group), let originalSession = found.0.session, originalSession !== session else { return }
        var attempts = 0
        while attempts < 4, originalSession.page.block(found.1.id)?.children != content {
            attempts += 1
            let moved = undoing ? originalSession.undo(ifTopBelongsTo: edit.owner) : originalSession.redo(ifTopBelongsTo: edit.owner)
            if !moved { break }
        }
        guard let now = original(of: group), now.0.session === originalSession, now.1.children != content else { return }
        let id = now.1.id
        originalSession.applyLinked(undoing ? "Undo " + edit.name : edit.name, owner: edit.owner,
                                    effect: { undoing ? edit.reversal(for: originalSession) : edit.effect(for: originalSession) },
                                    origin: self) { page in
            page.update(id) { $0.children = content }
        }
        found.0.seen[id] = originalSession.page.block(id)?.children
    }

    private func retraceCopies(of edit: NoteSyncedEdit, undoing: Bool, except session: NotePageSession) {
        var visited = Set<ObjectIdentifier>()
        for group in edit.groups {
            let originalSession = original(of: group)?.0.session
            for (other, _) in allSites(of: group) {
                guard let otherSession = other.session, otherSession !== session, otherSession !== originalSession,
                      visited.insert(ObjectIdentifier(otherSession)).inserted else { continue }
                if undoing { otherSession.undo(ifTopBelongsTo: edit.owner) } else { otherSession.redo(ifTopBelongsTo: edit.owner) }
            }
            pendingReconcile.insert(group)
        }
    }

    private func content(of group: NoteSyncedGroup, in session: NotePageSession) -> [NoteBlock]? {
        guard let document = documents[ObjectIdentifier(session)] else { return nil }
        let matching = sites(in: document).filter { self.group(of: $0, in: document) == group }
        if let original = matching.first(where: \.isSyncedOriginal) { return original.children }
        guard let copy = matching.first else { return nil }
        return Self.unmapped(copy.children, key: copy.id, restoringAnchorsFrom: original(of: group)?.1.children ?? [])
    }

    private func reconcile(_ group: NoteSyncedGroup) {
        guard let found = original(of: group) else { return }
        let content = found.1.children
        for (other, block) in allSites(of: group) where !block.isSyncedOriginal {
            guard let otherSession = other.session else { continue }
            let target = Self.mapped(content, key: block.id)
            guard block.children != target else { continue }
            otherSession.applyUntracked(origin: self) { page in
                page.update(block.id) { $0.children = target }
            }
            other.seen[block.id] = otherSession.page.block(block.id)?.children
        }
    }

    private func groups(in document: Document) -> Set<NoteSyncedGroup> {
        Set(sites(in: document).compactMap { group(of: $0, in: document) })
    }

    private func sites(in document: Document) -> [NoteBlock] {
        guard let page = document.session?.page else { return [] }
        return document.currentSites().compactMap { page.block($0) }
    }

    private func allSites(of group: NoteSyncedGroup) -> [(Document, NoteBlock)] {
        var result: [(Document, NoteBlock)] = []
        for document in documents.values where document.isAvailable() {
            for block in sites(in: document) where self.group(of: block, in: document) == group { result.append((document, block)) }
        }
        return result
    }

    private func original(of group: NoteSyncedGroup) -> (Document, NoteBlock)? {
        for document in documents.values where document.isAvailable() && document.key == group.file {
            if let block = sites(in: document).first(where: { $0.isSyncedOriginal && $0.props.anchor == group.anchor }) {
                return (document, block)
            }
        }
        return nil
    }

    private func group(of block: NoteBlock, in document: Document) -> NoteSyncedGroup? {
        if block.isSyncedOriginal {
            guard let anchor = block.props.anchor, let key = document.key else { return nil }
            return NoteSyncedGroup(file: key, anchor: anchor)
        }
        guard let target = block.props.target, let reference = NoteSyncedReference(target) else { return nil }
        let direct = document.key(for: reference).map { NoteSyncedGroup(file: $0, anchor: reference.anchor) }
        if let direct, original(of: direct) != nil { return direct }
        let elsewhere = documents.values.filter { candidate in
            candidate.isAvailable() && sites(in: candidate).contains { $0.isSyncedOriginal && $0.props.anchor == reference.anchor }
        }
        guard elsewhere.count == 1, let home = elsewhere.first, let key = home.key, let session = document.session else { return direct }
        let fixed = NoteSyncedReference.target(anchor: reference.anchor, original: home.url, from: document.url)
        if fixed != target { pendingRewrites.append((session, block.id, { $0.props.target = fixed })) }
        return NoteSyncedGroup(file: key, anchor: reference.anchor)
    }

    static func mapped(_ blocks: [NoteBlock], key: NoteBlockID) -> [NoteBlock] {
        blocks.map { block in
            var copy = block
            copy.id = mix(block.id, key)
            if copy.props.anchor != nil { copy.props.anchor = nil }
            copy.children = mapped(block.children, key: key)
            return copy
        }
    }

    static func unmapped(_ blocks: [NoteBlock], key: NoteBlockID, restoringAnchorsFrom canonical: [NoteBlock]) -> [NoteBlock] {
        var anchors: [NoteBlockID: String] = [:]
        func collect(_ list: [NoteBlock]) {
            for block in list {
                if let anchor = block.props.anchor { anchors[block.id] = anchor }
                collect(block.children)
            }
        }
        collect(canonical)
        func walk(_ list: [NoteBlock]) -> [NoteBlock] {
            list.map { block in
                var copy = block
                copy.id = mix(block.id, key)
                let anchor = anchors[copy.id]
                if copy.props.anchor != anchor { copy.props.anchor = anchor }
                copy.children = walk(block.children)
                return copy
            }
        }
        return walk(blocks)
    }

    static func mix(_ id: NoteBlockID, _ key: NoteBlockID) -> NoteBlockID {
        let a = id.raw.uuid, b = key.raw.uuid
        return NoteBlockID(UUID(uuid: (a.0 ^ b.0, a.1 ^ b.1, a.2 ^ b.2, a.3 ^ b.3, a.4 ^ b.4, a.5 ^ b.5, a.6 ^ b.6, a.7 ^ b.7,
                                       a.8 ^ b.8, a.9 ^ b.9, a.10 ^ b.10, a.11 ^ b.11, a.12 ^ b.12, a.13 ^ b.13, a.14 ^ b.14, a.15 ^ b.15)))
    }

}

extension NotePage {
    func syncedSites() -> [NoteBlock] {
        var result: [NoteBlock] = []
        func walk(_ list: [NoteBlock]) {
            for block in list {
                if block.kind == .synced { result.append(block) } else { walk(block.children) }
            }
        }
        walk(blocks)
        return result
    }

}
