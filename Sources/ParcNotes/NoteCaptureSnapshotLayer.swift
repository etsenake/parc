import AppKit
import ParcCore

final class NoteCaptureSnapshotLayer: CATiledLayer {
    static let tilePixels: CGFloat = 512

    let snapshot: CaptureSnapshotPDF?
    let url: URL?
    private let state = NSLock()
    private var flipsDrawing = true

    init(snapshot: CaptureSnapshotPDF, url: URL) {
        self.snapshot = snapshot
        self.url = url
        super.init()
        anchorPoint = .zero
        tileSize = CGSize(width: Self.tilePixels, height: Self.tilePixels)
        levelsOfDetail = 1
        levelsOfDetailBias = 0
        needsDisplayOnBoundsChange = true
        isOpaque = false
    }

    override init(layer: Any) {
        let other = layer as? NoteCaptureSnapshotLayer
        snapshot = other?.snapshot
        url = other?.url
        super.init(layer: layer)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override class func fadeDuration() -> CFTimeInterval { 0.12 }

    override func action(forKey event: String) -> CAAction? { NSNull() }

    var drawsFlipped: Bool {
        get { state.lock(); defer { state.unlock() }; return flipsDrawing }
        set { state.lock(); flipsDrawing = newValue; state.unlock() }
    }

    func refreshOrientation() {
        drawsFlipped = contentsAreFlipped()
    }

    override func draw(in ctx: CGContext) {
        guard let snapshot else { return }
        snapshot.draw(in: ctx, rect: bounds, flipped: drawsFlipped)
    }
}
