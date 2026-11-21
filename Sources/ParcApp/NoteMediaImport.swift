import AppKit
import ParcCore

@MainActor
enum NoteMediaImport {
    static let stagingThreshold = 4 * 1024 * 1024

    struct Target {
        var note: URL
        var date: Date
        var session: NotePageSession
        var imports: NoteAttachmentImports
    }

    static func imports(for environment: NoteEnvironment) -> NoteAttachmentImports {
        ((environment as? NoteFileEnvironment)?.files ?? .shared).attachmentImports
    }

    static func target(for environment: NoteEnvironment) -> Target? {
        guard let file = environment as? NoteFileEnvironment, let note = file.documentURL,
              let session = file.files.openSessions.first(where: { $0.environment === environment })?.page else { return nil }
        return Target(note: note, date: file.now(), session: session, imports: file.files.attachmentImports)
    }

    static func source(importing url: URL, environment: NoteEnvironment, scoped: Bool = false) throws -> String {
        guard url.isFileURL, let target = target(for: environment) else {
            return try withAccess(to: scoped ? url : nil) { try environment.importAsset(from: url) }
        }
        let file = NoteFilePaths.canonical(URL(fileURLWithPath: url.path))
        if NoteFilePaths.itemExists(file), let existing = NoteAttachments.existingSource(for: file, in: target.note) { return existing }
        return begin(file.absoluteString, file: file, target: target, access: scoped ? url : nil)
    }

    static func source(importing data: Data, fileExtension: String, suggestedName: String?, environment: NoteEnvironment) throws -> String {
        guard let target = target(for: environment), data.count > stagingThreshold else {
            let normalized = normalizedImage(data, fileExtension: fileExtension)
            return try environment.importAsset(data: normalized.data, fileExtension: normalized.fileExtension, suggestedName: suggestedName)
        }
        let name = suggestedName ?? NoteFileNaming.pastedBaseName(at: target.date, isImage: NoteFileNaming.imageExtensions.contains(fileExtension.lowercased()))
        let staged = try NoteAttachments.stage(data, fileExtension: fileExtension, suggestedName: name)
        return begin(staged.absoluteString, file: staged, target: target, access: nil)
    }

    static func source(importingDataURL source: String, suggestedName: String, environment: NoteEnvironment) throws -> String {
        guard let decoded = NoteClipboard.decodeDataURL(source) else { throw NoteFileError.unreadable("That pasted media came through empty.") }
        return try self.source(importing: decoded.data, fileExtension: decoded.fileExtension, suggestedName: suggestedName, environment: environment)
    }

    static func carriedSource(_ source: String, environment: NoteEnvironment) -> String? {
        guard let url = URL(string: source), url.isFileURL, imports(for: environment).mayImport(url) else { return nil }
        return try? self.source(importing: url, environment: environment)
    }

    static func replace(_ id: NoteBlockID, with url: URL, name: String, in session: NotePageSession, environment: NoteEnvironment) throws {
        let source = try source(importing: url, environment: environment, scoped: true)
        session.updateBlock(id, name: name) { block in
            block.props.source = source
            block.props.credit = nil
            block.props.crop = nil
        }
    }

    static func resume(_ source: String?, environment: NoteEnvironment) {
        guard let source, let url = URL(string: source), url.isFileURL, let target = target(for: environment) else { return }
        let imports = target.imports
        imports.adoptOrphans(of: target.note, in: target.session)
        guard NoteAttachments.isStaged(url), !imports.hasTried(source, in: target.session), NoteFilePaths.itemExists(url),
              target.session.page.documentOrder(includingCollapsed: true).contains(where: { target.session.page.block($0)?.props.source == source })
        else { return }
        _ = begin(source, file: NoteFilePaths.canonical(url), target: target, access: nil)
    }

    private static func begin(_ source: String, file: URL, target: Target, access: URL?) -> String {
        let imports = target.imports
        guard !imports.isPending(source, in: target.session) else { return source }
        let note = target.note, date = target.date
        imports.begin(source, from: file, in: target.session, note: note) {
            try withAccess(to: access) { try copy(file, into: note, date: date) }
        }
        return source
    }

    nonisolated static func copy(_ file: URL, into note: URL, date: Date) throws -> NoteAttachments.Placement {
        let pathExtension = file.pathExtension.lowercased()
        guard NoteAttachments.isStaged(file), pathExtension == "tiff" || pathExtension == "tif" else {
            return try NoteAttachments.placeFile(file, into: note)
        }
        let normalized = normalizedImage(try Data(contentsOf: file), fileExtension: "tiff")
        return try NoteAttachments.placeData(normalized.data, fileExtension: normalized.fileExtension,
                                             suggestedName: file.deletingPathExtension().lastPathComponent, into: note, date: date)
    }

    nonisolated static func normalizedImage(_ data: Data, fileExtension: String) -> (data: Data, fileExtension: String) {
        guard fileExtension == "tiff", let image = NSBitmapImageRep(data: data),
              let png = image.representation(using: .png, properties: [:]) else { return (data, fileExtension) }
        return (png, "png")
    }

    nonisolated private static func withAccess<Value>(to url: URL?, _ work: () throws -> Value) throws -> Value {
        let granted = url?.startAccessingSecurityScopedResource() == true
        defer { if granted { url?.stopAccessingSecurityScopedResource() } }
        return try work()
    }
}
