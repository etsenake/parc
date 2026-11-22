import AppKit

@MainActor
final class DownloadLocationPicker: PointingHandPopUpButton {
    enum Choice: Int { case folder = 0, other = 1, prompt = 2 }

    struct Value: Equatable {
        let directory: URL
        let prompt: Bool
    }

    static let width: CGFloat = 180
    static let iconSize = NSSize(width: 16, height: 16)
    static let otherTitle = "Other…"
    static let promptTitle = "Ask every time"
    static let unavailableTitle = "Unavailable"

    var iconProvider: (URL) -> NSImage = { NSWorkspace.shared.icon(forFile: $0.path) }
    var onChoose: ((Choice) -> Void)?
    private(set) var value: Value?
    private(set) var panelOpen = false
    weak var rowTitle: NSView? { didSet { updateRowTitle() } }
    override var isEnabled: Bool { didSet { updateRowTitle() } }
    private func updateRowTitle() { rowTitle?.alphaValue = isEnabled ? 1 : 0.25 }

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: Self.width, height: 28), pullsDown: false)
        target = self; action = #selector(chosen)
        autoenablesItems = false
        setAccessibilityLabel("Download Location")
        update(nil, enabled: false)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    var effectiveChoice: Choice? { value.map { $0.prompt ? .prompt : .folder } }

    func update(_ value: Value?, enabled: Bool, panelOpen: Bool = false) {
        self.value = value; self.panelOpen = panelOpen
        removeAllItems()
        toolTip = nil
        isEnabled = enabled
        guard !panelOpen else { return }
        guard let value else {
            addItem(withTitle: Self.unavailableTitle)
            lastItem?.isEnabled = false
            isEnabled = false
            return
        }
        let icon = iconProvider(value.directory), size = Self.iconSize
        let folder = NSMenuItem(title: value.directory.lastPathComponent, action: nil, keyEquivalent: "")
        folder.showImage(NSImage(size: size, flipped: false) { rect in icon.draw(in: rect); return true })
        folder.tag = Choice.folder.rawValue
        folder.toolTip = value.directory.path
        menu?.addItem(folder)
        let other = NSMenuItem(title: Self.otherTitle, action: nil, keyEquivalent: "")
        other.tag = Choice.other.rawValue
        menu?.addItem(other)
        menu?.addItem(.separator())
        let prompt = NSMenuItem(title: Self.promptTitle, action: nil, keyEquivalent: "")
        prompt.tag = Choice.prompt.rawValue
        menu?.addItem(prompt)
        revert()
    }

    func revert() {
        guard let choice = effectiveChoice, !panelOpen else { return }
        selectItem(withTag: choice.rawValue)
        toolTip = choice == .folder ? value?.directory.path : nil
    }

    @objc private func chosen() {
        guard let choice = Choice(rawValue: selectedTag()), let current = effectiveChoice else { return }
        guard choice != current else { return }
        onChoose?(choice)
    }
}
