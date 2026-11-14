import AppKit

struct HistorySwipeOverlayRow: Equatable {
    var title: String
    var favicon: NSImage?
}

@MainActor final class HistorySwipeOverlayView: NSView {
    var palette: ThemeChromePalette? {
        didSet { if palette != oldValue { appearance = palette?.contentAppearance } }
    }
    private(set) var current = HistorySwipeOverlayRow(title: "", favicon: nil)
    private(set) var back: [HistorySwipeOverlayRow] = []
    private(set) var forward: [HistorySwipeOverlayRow] = []
    private(set) var lastOutput: HistorySwipeOutput?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = true
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func isAccessibilityElement() -> Bool { false }
    override func accessibilityChildren() -> [Any]? { [] }

    func setRows(current: HistorySwipeOverlayRow, back: [HistorySwipeOverlayRow], forward: [HistorySwipeOverlayRow]) {
        self.current = current
        self.back = back
        self.forward = forward
    }

    func handle(_ output: HistorySwipeOutput) {
        lastOutput = output
    }
}
