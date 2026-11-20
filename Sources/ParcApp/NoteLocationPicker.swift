import AppKit
import UniformTypeIdentifiers

@MainActor
final class NoteLocationPicker: PointingHandPopUpButton {
    enum Choice: Int { case folder = 0, other = 1, showInFinder = 2 }

    static let width = DownloadLocationPicker.width
    static let iconSize = DownloadLocationPicker.iconSize
    static let otherTitle = DownloadLocationPicker.otherTitle
    static let showInFinderTitle = "Show in Finder"
    static let unavailableTitle = DownloadLocationPicker.unavailableTitle
    static let helpText = "New notes land here. Notes saved anywhere else still open fine."

    static func folderIcon(_ url: URL) -> NSImage {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return NSWorkspace.shared.icon(for: .folder)
        }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    var iconProvider: (URL) -> NSImage = NoteLocationPicker.folderIcon
    var onChoose: ((Choice) -> Void)?
    private(set) var folder: URL?
    private(set) var panelOpen = false
    weak var rowTitle: NSView? { didSet { updateRowTitle() } }
    override var isEnabled: Bool { didSet { updateRowTitle() } }
    private func updateRowTitle() { rowTitle?.alphaValue = isEnabled ? 1 : 0.25 }

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: Self.width, height: 28), pullsDown: false)
        target = self; action = #selector(chosen)
        autoenablesItems = false
        setAccessibilityLabel("Notes Folder")
        update(nil, enabled: false)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func update(_ folder: URL?, enabled: Bool, panelOpen: Bool = false) {
        self.folder = folder; self.panelOpen = panelOpen
        removeAllItems()
        toolTip = nil
        isEnabled = enabled
        guard !panelOpen else { return }
        guard let folder else {
            addItem(withTitle: Self.unavailableTitle)
            lastItem?.isEnabled = false
            isEnabled = false
            return
        }
        let icon = iconProvider(folder), size = Self.iconSize
        let row = NSMenuItem(title: folder.lastPathComponent, action: nil, keyEquivalent: "")
        row.showImage(NSImage(size: size, flipped: false) { rect in icon.draw(in: rect); return true })
        row.tag = Choice.folder.rawValue
        row.toolTip = folder.path
        menu?.addItem(row)
        let other = NSMenuItem(title: Self.otherTitle, action: nil, keyEquivalent: "")
        other.tag = Choice.other.rawValue
        menu?.addItem(other)
        menu?.addItem(.separator())
        let reveal = NSMenuItem(title: Self.showInFinderTitle, action: nil, keyEquivalent: "")
        reveal.tag = Choice.showInFinder.rawValue
        menu?.addItem(reveal)
        revert()
    }

    func revert() {
        guard let folder, !panelOpen else { return }
        selectItem(withTag: Choice.folder.rawValue)
        toolTip = folder.path
    }

    @objc private func chosen() {
        guard folder != nil, let choice = Choice(rawValue: selectedTag()), choice != .folder else { return }
        if choice == .showInFinder { revert() }
        onChoose?(choice)
    }
}
