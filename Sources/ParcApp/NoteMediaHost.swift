import AppKit

@MainActor
protocol NoteMediaHost: NSView {
    var kind: NoteBlockKind { get }
    var source: NoteMediaSource { get }
    var nounPhrase: String { get }
    var mediaFileName: String { get }
    var canEdit: Bool { get }
    var offersUnsplash: Bool { get }
    var offersCaption: Bool { get }
    var offersColumnLayout: Bool { get }
    var offersShowInFinder: Bool { get }
    var isBlockSelected: Bool { get }
    var isOnScreen: Bool { get }
    var embeddablePage: URL? { get }
    var mediaOverlay: NSView? { get }
    var mediaCanvas: NSView? { get }
    func invalidateMeasuredHeight()
    func contentDidFail(_ problem: NoteMediaProblem)
    func retry()
    func selectBlock(with event: NSEvent) -> Bool
    func focusHostBlock()
    func replace()
    func importFile(_ url: URL)
    func importData(_ data: Data, fileExtension: String, suggestedName: String?)
    func embed(_ url: URL)
    func embedAsPage(_ url: URL)
    func presentReplaceMenu(from anchor: NSView)
    func presentUnsplash(from anchor: NSView)
    func revealCaption()
    func setAlignment(_ alignment: NoteAlignment)
    func commitWidth(_ fraction: Double?)
    func deleteBlock()
    func download()
    func showInFinder()
    func open(_ url: URL)
    func quickLook(from rect: NSRect, in view: NSView)
    func zoom(image: NoteMediaImage, from rect: NSRect, in view: NSView, crop: NoteImageCrop?, mask: NoteImageMask?)
    func commitFraming(crop: NoteImageCrop?, mask: NoteImageMask?, name: String)
    func setAltText(_ text: String)
}

enum NoteMediaMode: Equatable {
    case empty, pending, problem(NoteMediaProblem), image, video, audio, file, pdf

    @MainActor
    static func resolve(kind: NoteBlockKind, source: NoteMediaSource, importing: Bool, failure: NoteMediaProblem?,
                        plainText: Bool = false) -> NoteMediaMode {
        if let failure { return .problem(failure) }
        switch source.readiness(for: kind, importing: importing) {
        case .empty: return .empty
        case .missing: return .problem(.missing)
        case .importing: return .pending
        case .ready: break
        }
        if case .remote(let url) = source, kind == .image, let error = NoteMediaImageLoader.shared.failure(for: url) {
            return .problem(NoteMediaBlockView.problem(for: error))
        }
        switch kind {
        case .image: return .image
        case .video: return .video
        case .audio: return .audio
        case .pdf: return plainText ? .file : .pdf
        default: return .file
        }
    }

    @MainActor
    func makeContent(host: NoteMediaHost) -> NoteMediaContentView {
        switch self {
        case .empty: return NoteMediaEmptyCard(host: host)
        case .pending: return NoteMediaPendingCard(host: host)
        case .problem(let problem): return NoteMediaProblemCard(host: host, problem: problem)
        case .image: return NoteImageContentView(host: host)
        case .video: return NoteVideoContentView(host: host)
        case .audio: return NoteAudioContentView(host: host)
        case .file: return NoteFileContentView(host: host)
        case .pdf: return NotePDFContentView(host: host)
        }
    }
}
