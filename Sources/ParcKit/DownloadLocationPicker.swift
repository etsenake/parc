import AppKit

@MainActor
package final class DownloadLocationPicker: PointingHandPopUpButton {
    package enum Choice: Int { case folder = 0, other = 1, prompt = 2 }

    package struct Value: Equatable {
        package let directory: URL
        package let prompt: Bool
        package init(directory: URL, prompt: Bool) {
            self.directory = directory
            self.prompt = prompt
        }
    }

    package static let width: CGFloat = 180
    package static let iconSize = NSSize(width: 16, height: 16)
    package static let otherTitle = "Other…"
    static let promptTitle = "Ask every time"
    package static let unavailableTitle = "Unavailable"

    var iconProvider: (URL) -> NSImage = { NSWorkspace.shared.icon(forFile: $0.path) }
    package var onChoose: ((Choice) -> Void)?
    package private(set) var value: Value?
    private(set) var panelOpen = false
    package weak var rowTitle: NSView? { didSet { updateRowTitle() } }
    package override var isEnabled: Bool { didSet { updateRowTitle() } }
    private func updateRowTitle() { rowTitle?.alphaValue = isEnabled ? 1 : 0.25 }

    package init() {
        super.init(frame: NSRect(x: 0, y: 0, width: Self.width, height: 28), pullsDown: false)
        target = self; action = #selector(chosen)
        autoenablesItems = false
        setAccessibilityLabel("Download Location")
        update(nil, enabled: false)
    }
    package required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    var effectiveChoice: Choice? { value.map { $0.prompt ? .prompt : .folder } }

    package func update(_ value: Value?, enabled: Bool, panelOpen: Bool = false) {
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

    package func revert() {
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
