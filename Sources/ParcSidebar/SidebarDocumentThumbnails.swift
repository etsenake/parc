import AppKit
import Combine
import ParcCore
import ParcNotes
import ParcEasels

package struct SidebarDocumentUpdate {
    var content: SidebarDocumentContent
    var picture: NSImage?
    var settled: Bool
}

@MainActor
package final class SidebarDocumentThumbnails {
    package static let shared = SidebarDocumentThumbnails()
    static let aspect: CGFloat = 10.0 / 16.0
    static let pixelWidth: CGFloat = 560
    static let noteBlocks = 12

    private enum Revision: Hashable {
        case page(NotePage, String)
        case file(Date, Int, String)
        case easel(Date, Int)
    }

    private typealias Cache = SidebarThumbnailCache<NSImage, Revision>
    private var cache = Cache()
    private let reader = DispatchQueue(label: "org.parc.sidebar.document-thumbnails", qos: .userInitiated)

    package final class Lease {
        fileprivate var cancelled = false
        fileprivate var pending: DispatchWorkItem?
        fileprivate var subscription: AnyCancellable?
        fileprivate var content = SidebarDocumentContent()
        fileprivate var rendering = false
        fileprivate var dirty = false
        package func invalidate() {
            cancelled = true; pending?.cancel(); pending = nil; subscription = nil
        }
    }

    package func observe(_ kind: SidebarDocumentKind, title: String, appearance: NSAppearance,
                 easels: @escaping () throws -> EaselStore, noteEasels: @escaping (URL) -> NoteEaselHost?,
                 deliver: @escaping (SidebarDocumentUpdate) -> Void) -> Lease {
        let lease = Lease()
        switch kind {
        case .note(let url): observeNote(url, title: title, appearance: appearance, lease: lease, easels: noteEasels, deliver: deliver)
        case .easel(let id): observeEasel(id, appearance: appearance, lease: lease, easels: easels, deliver: deliver)
        }
        return lease
    }

    private static func appearanceName(_ appearance: NSAppearance) -> String {
        NoteTheme.isDark(appearance) ? "dark" : "light"
    }

    private func observeNote(_ url: URL, title: String, appearance: NSAppearance, lease: Lease,
                             easels: @escaping (URL) -> NoteEaselHost?, deliver: @escaping (SidebarDocumentUpdate) -> Void) {
        let key = Cache.Key(document: SidebarDocumentKind.note(url).cacheKey, appearance: Self.appearanceName(appearance))
        if let session = NoteFileSession.session(for: url) {
            let refresh = { [weak self, weak session, weak lease] in
                guard let self, let session, let lease, !lease.cancelled else { return }
                let page = Self.prefix(session.page.page)
                lease.content = SidebarDocumentContent(snippet: Self.snippet(page, kind: session.kind))
                let revision = Revision.page(page, title)
                if let image = self.cache.fresh(key, revision: revision) {
                    self.cache.touch(key)
                    deliver(SidebarDocumentUpdate(content: lease.content, picture: image, settled: true))
                    return
                }
                if let stale = self.cache.latest(key) {
                    deliver(SidebarDocumentUpdate(content: lease.content, picture: stale, settled: false))
                }
                self.schedule(lease, key: key) { [weak self, weak session] done in
                    guard let self, let session else { return done() }
                    let page = Self.prefix(session.page.page)
                    let revision = Revision.page(page, title)
                    self.renderNote(page, title: title, environment: session.environment, easels: easels(url),
                                    appearance: appearance) { image in
                        if let image { self.cache.store(image, for: key, revision: revision, now: Date()) }
                        if !lease.cancelled { deliver(SidebarDocumentUpdate(content: lease.content, picture: image ?? self.cache.latest(key), settled: true)) }
                        done()
                    }
                }
            }
            lease.subscription = session.page.changes.sink { _ in DispatchQueue.main.async { MainActor.assumeIsolated { refresh() } } }
            refresh()
            return
        }
        guard let kind = NoteFileKind(url: url) else {
            deliver(SidebarDocumentUpdate(content: SidebarDocumentContent(availability: .missing), picture: nil, settled: true))
            return
        }
        struct Probe: Sendable { var exists: Bool; var revision: (Date, Int); var snippet: String }
        offMain({ () -> Probe in
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey])
            guard let values, values.isRegularFile == true else { return Probe(exists: false, revision: (.distantPast, 0), snippet: "") }
            return Probe(exists: true, revision: (values.contentModificationDate ?? .distantPast, values.fileSize ?? 0),
                         snippet: NoteFileSummary.read(url, kind: kind).snippet)
        }) { [weak self] probe in
            guard let self, !lease.cancelled else { return }
            guard probe.exists else {
                self.cache.invalidate(document: key.document)
                deliver(SidebarDocumentUpdate(content: SidebarDocumentContent(availability: .missing), picture: nil, settled: true))
                return
            }
            let revision = Revision.file(probe.revision.0, probe.revision.1, title)
            lease.content = SidebarDocumentContent(snippet: probe.snippet)
            if let image = self.cache.fresh(key, revision: revision) {
                self.cache.touch(key)
                deliver(SidebarDocumentUpdate(content: lease.content, picture: image, settled: true))
                return
            }
            if let stale = self.cache.latest(key) {
                deliver(SidebarDocumentUpdate(content: lease.content, picture: stale, settled: false))
            }
            self.schedule(lease, key: key) { [weak self] done in
                self?.offMain({ () -> NotePage? in
                    (try? NoteFileIO.readNow(url, kind: kind)).map { contents in
                        let text = NoteFileText.editableText(contents, kind: kind)
                        return kind == .markdown ? NoteMarkdown.parse(text) : NotePlainText.parse(text)
                    }
                }) { [weak self] page in
                    guard let self, let page, !lease.cancelled else {
                        if !lease.cancelled { deliver(SidebarDocumentUpdate(content: lease.content, picture: nil, settled: true)) }
                        return done()
                    }
                    let environment = NoteFileEnvironment(documentURL: url, isPlainText: kind == .plainText)
                    self.renderNote(Self.prefix(page), title: title, environment: environment, easels: easels(url),
                                    appearance: appearance) { image in
                        if let image { self.cache.store(image, for: key, revision: revision, now: Date()) }
                        if !lease.cancelled { deliver(SidebarDocumentUpdate(content: lease.content, picture: image, settled: true)) }
                        done()
                    }
                }
            }
        }
    }

    private final class Handoff<Value>: @unchecked Sendable {
        var value: Value?
        let deliver: @MainActor (Value) -> Void
        init(_ deliver: @escaping @MainActor (Value) -> Void) { self.deliver = deliver }
    }

    private func offMain<Value>(_ work: @escaping @Sendable () -> Value, then deliver: @escaping @MainActor (Value) -> Void) {
        let handoff = Handoff(deliver)
        reader.async {
            handoff.value = work()
            DispatchQueue.main.async { MainActor.assumeIsolated { if let value = handoff.value { handoff.deliver(value) } } }
        }
    }

    private func observeEasel(_ id: UUID, appearance: NSAppearance, lease: Lease, easels: () throws -> EaselStore,
                              deliver: @escaping (SidebarDocumentUpdate) -> Void) {
        let key = Cache.Key(document: SidebarDocumentKind.easel(id).cacheKey, appearance: Self.appearanceName(appearance))
        let session: EaselSession
        do { session = try easels().load(id) } catch {
            cache.invalidate(document: key.document)
            deliver(SidebarDocumentUpdate(content: SidebarDocumentContent(availability: .missing), picture: nil, settled: true))
            return
        }
        let refresh = { [weak self, weak session, weak lease] (first: Bool) in
            guard let self, let session, let lease, !lease.cancelled else { return }
            guard !session.isDeleted, !session.isClosed || first else {
                deliver(SidebarDocumentUpdate(content: SidebarDocumentContent(availability: .missing), picture: nil, settled: true))
                return
            }
            let document = session.document
            lease.content = SidebarDocumentContent(objectCount: document.items.count)
            guard !document.items.isEmpty else {
                deliver(SidebarDocumentUpdate(content: lease.content, picture: nil, settled: true))
                return
            }
            let revision = Revision.easel(document.modifiedAt, document.items.count)
            if let image = self.cache.fresh(key, revision: revision) {
                self.cache.touch(key)
                deliver(SidebarDocumentUpdate(content: lease.content, picture: image, settled: true))
                return
            }
            if first, self.cache.renderDelay(key, now: Date()) == 0, let image = Self.renderEasel(session, appearance: appearance) {
                self.cache.store(image, for: key, revision: revision, now: Date())
                deliver(SidebarDocumentUpdate(content: lease.content, picture: image, settled: true))
                return
            }
            if let stale = self.cache.latest(key) {
                deliver(SidebarDocumentUpdate(content: lease.content, picture: stale, settled: false))
            }
            self.schedule(lease, key: key) { [weak self, weak session] done in
                guard let self, let session, !session.isDeleted else { return done() }
                let document = session.document
                let image = Self.renderEasel(session, appearance: appearance)
                if let image { self.cache.store(image, for: key, revision: .easel(document.modifiedAt, document.items.count), now: Date()) }
                if !lease.cancelled {
                    lease.content = SidebarDocumentContent(objectCount: document.items.count)
                    deliver(SidebarDocumentUpdate(content: lease.content, picture: image ?? self.cache.latest(key), settled: true))
                }
                done()
            }
        }
        lease.subscription = session.$document.dropFirst().receive(on: DispatchQueue.main).sink { _ in refresh(false) }
        refresh(true)
    }

    private func schedule(_ lease: Lease, key: Cache.Key, render: @escaping (@escaping () -> Void) -> Void) {
        guard !lease.cancelled else { return }
        if lease.rendering { lease.dirty = true; return }
        guard lease.pending == nil else { return }
        let work = DispatchWorkItem { [weak self, weak lease] in
            guard let self, let lease, !lease.cancelled else { return }
            lease.pending = nil; lease.rendering = true; lease.dirty = false
            render { [weak self, weak lease] in
                guard let lease else { return }
                lease.rendering = false
                if lease.dirty, !lease.cancelled { lease.dirty = false; self?.schedule(lease, key: key, render: render) }
            }
        }
        lease.pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + cache.renderDelay(key, now: Date()), execute: work)
    }

    private static func prefix(_ page: NotePage) -> NotePage {
        var copy = page
        if copy.blocks.count > noteBlocks { copy.blocks = Array(copy.blocks.prefix(noteBlocks)) }
        return copy
    }

    private static func snippet(_ page: NotePage, kind: NoteFileKind) -> String {
        let text = kind == .markdown ? NoteMarkdown.serialize(page) : NotePlainText.serialize(page)
        return NoteFileSummary.make(fromHead: text, kind: kind).snippet
    }

    private func renderNote(_ page: NotePage, title: String, environment: NoteEnvironment, easels: NoteEaselHost?,
                            appearance: NSAppearance, completion: @escaping (NSImage?) -> Void) {
        NotePagePrintView.prepare(page: page, title: title, environment: environment, easels: easels, appearance: appearance) { view in
            let width = NotePagePrintView.canvasWidth
            let rect = NSRect(x: 0, y: 0, width: width, height: (width * Self.aspect).rounded())
            if view.bounds.height < rect.height { view.setFrameSize(NSSize(width: width, height: rect.height)) }
            guard let rep = view.bitmapImageRepForCachingDisplay(in: rect) else { return completion(nil) }
            view.cacheDisplay(in: rect, to: rep)
            completion(Self.composite(rep: rep, size: rect.size, appearance: appearance))
        }
    }

    private static func composite(rep: NSBitmapImageRep, size: NSSize, appearance: NSAppearance) -> NSImage {
        let scale = pixelWidth / size.width
        let output = NSSize(width: pixelWidth, height: (size.height * scale).rounded())
        let image = NSImage(size: output)
        image.lockFocus()
        (NoteTheme.isDark(appearance) ? NSColor.black : NSColor.white).setFill()
        NSRect(origin: .zero, size: output).fill()
        NSGraphicsContext.current?.imageInterpolation = .high
        rep.draw(in: NSRect(origin: .zero, size: output), from: .zero, operation: .sourceOver, fraction: 1,
                 respectFlipped: true, hints: nil)
        image.unlockFocus()
        return image
    }

    private static func renderEasel(_ session: EaselSession, appearance: NSAppearance) -> NSImage? {
        guard let content = EaselPreviewRegion.content(EaselPages.view(session.document, page: nil).items) else { return nil }
        let canvas = EaselCanvasView(session: session)
        canvas.appearance = appearance
        canvas.resizeCanvas(viewport: NSSize(width: 800, height: 600))
        let area = EaselPreviewRegion.fit(content, aspect: Double(aspect), minimumWidth: 800)
        let region = NSRect(x: area.x, y: area.y, width: area.width, height: area.height), width = region.width
        let scale = min(2, pixelWidth / width)
        guard let full = canvas.exportImage(backingScale: scale) else { return nil }
        let used = canvas.bounds.width > 0 ? CGFloat(full.width) / canvas.bounds.width : scale
        let crop = CGRect(x: (region.minX * used).rounded(), y: (region.minY * used).rounded(),
                          width: (region.width * used).rounded(), height: (region.height * used).rounded())
            .intersection(CGRect(x: 0, y: 0, width: full.width, height: full.height))
        guard !crop.isEmpty, let cropped = full.cropping(to: crop) else { return nil }
        let image = NSImage(size: NSSize(width: pixelWidth, height: (pixelWidth * aspect).rounded()))
        image.lockFocus()
        (NoteTheme.isDark(appearance) ? NSColor.black : NSColor.white).setFill()
        NSRect(origin: .zero, size: image.size).fill()
        let fitted = NSSize(width: crop.width / used * (pixelWidth / width), height: crop.height / used * (pixelWidth / width))
        NSGraphicsContext.current?.imageInterpolation = .high
        NSImage(cgImage: cropped, size: .zero).draw(in: NSRect(x: 0, y: image.size.height - fitted.height,
                                                               width: fitted.width, height: fitted.height))
        image.unlockFocus()
        return image
    }
}
