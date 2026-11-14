import AppKit
import Combine
import UniformTypeIdentifiers
import ImageIO

@MainActor
final class CaptureLibraryView: NSView, NSCollectionViewDataSource, NSSearchFieldDelegate {
    let store: CaptureLibraryStore
    private let profileOwner: BrowserStore
    private let media: ExternalMediaLibrary
    var onClose: (() -> Void)?
    var onOpenSource: ((String) -> Void)?
    var onToast: ((PArcToastContent) -> Void)?
    var palette: ThemeChromePalette? { didSet { collection.backgroundColors = [.clear] } }
    private let search: NSTextField
    private let searchBackdrop: DownloadSearchBackdrop?
    private let collection = CaptureCollectionView()
    private let scroll = NSScrollView()
    private let message = CaptureEmptyMessage(wrappingLabelWithString: "")
    private enum Item: Equatable {
        case capture(SavedCapture), file(ExternalMediaFile)
        var id: String { switch self { case .capture(let item): return "capture:" + item.id.uuidString; case .file(let item): return "file:" + item.id } }
        var title: String { switch self { case .capture(let item): return item.title; case .file(let item): return item.title } }
        var date: Date { switch self { case .capture(let item): return item.createdAt; case .file(let item): return item.date } }
        var searchText: String { switch self { case .capture(let item): return item.title + " " + item.sourceURL + " " + item.spaceName; case .file(let item): return item.title + " " + item.detail + " " + item.folder.lastPathComponent } }
        var cacheKey: String { switch self { case .capture(let item): return item.revision.uuidString; case .file(let item): return item.id + String(describing: item.revision) } }
    }
    private var items: [Item] = []
    private let accessStatus = NSTextField(labelWithString: "")
    private var actionError: String?
    private let mediaClient = UUID()
    private var filePreview: DownloadLibraryPreview?
    private var previewedFile: ExternalMediaFile?
    private var fileAccess: ExternalMediaAccess?
    private var ownedSheet: NSWindow?
    private var windowObservers: [NSObjectProtocol] = []
    private var scrollObservers: [NSObjectProtocol] = []
    private var isScrolling = false
    private var subscriptions = Set<AnyCancellable>()
    private var observedCaptures: [SavedCapture] = []
    private var observedCaptureLoadError: String?
    private var observedCaptureLoading = false
    private var observedMediaItems: [ExternalMediaFile] = []
    private var observedMediaFolders: [ExternalMediaFolder] = []
    private var observedMediaError: String?
    private var observedMediaLoading = false
    private var thumbnails: [String: NSImage] = [:]
    private var thumbnailTasks: [String: (id: UUID, task: Task<Void, Never>)] = [:]
    private var generation: UInt64 = 0
    private var presentationGeneration: UInt64 = 0
    private var captureSharing: CaptureLibrarySharing?
    private var shareRequest: UUID?
    private var preview: CaptureLibraryPreview?
    private var focusReturn: CaptureFocusReturn?
    private var shareFocusReturn: CaptureFocusReturn?
    private let ownerValid: () -> Bool
    override var isFlipped: Bool { true }

    init(store: CaptureLibraryStore, profileOwner: BrowserStore, media: ExternalMediaLibrary, regularHeader: Bool = false, ownerValid: @escaping () -> Bool) {
        self.store = store; self.profileOwner = profileOwner; self.media = media; self.ownerValid = ownerValid
        search = regularHeader ? DownloadSearchField(frame: .zero) : NSSearchField()
        searchBackdrop = regularHeader ? DownloadSearchBackdrop() : nil
        super.init(frame: .zero)
        search.placeholderString = "Search Media…"; search.delegate = self
        search.setAccessibilityLabel("Search Media")
        if let searchBackdrop {
            searchBackdrop.wantsLayer = true; searchBackdrop.setAccessibilityElement(false)
            addSubview(searchBackdrop); searchBackdrop.addSubview(search)
            searchBackdrop.onFocus = { [weak self] in
                guard let self, let backdrop = self.searchBackdrop, !backdrop.isHiddenOrHasHiddenAncestor,
                      self.ownerValid(), let window = self.window else { return }
                if self.search.currentEditor() !== window.firstResponder { window.makeFirstResponder(self.search) }
            }
        } else {
            (search as? NSSearchField)?.sendsSearchStringImmediately = true
            addSubview(search)
        }
        let flow = NSCollectionViewFlowLayout()
        flow.minimumInteritemSpacing = 10; flow.minimumLineSpacing = 10
        flow.sectionInset = NSEdgeInsets(top: LibraryPageHeader.contentTop - LibraryPageHeader.top - LibraryPageHeader.height,
                                         left: 10, bottom: 10, right: 10)
        collection.collectionViewLayout = flow
        collection.register(CaptureLibraryCell.self, forItemWithIdentifier: .init("capture"))
        collection.dataSource = self; collection.isSelectable = true
        collection.allowsMultipleSelection = false; collection.backgroundColors = [.clear]
        collection.onMenu = { [weak self] index in
            guard let self, self.items.indices.contains(index), self.ownerValid() else { return nil }
            self.beginUserAction()
            let item = self.items[index]
            self.collection.selectionIndexPaths = [IndexPath(item: index, section: 0)]
            if case .file(let file) = item { return self.fileMenu(file) }
            guard case .capture(let capture) = item else { return nil }
            return self.captureMenu(capture)
        }
        collection.onEmptyMenu = { [weak self] in self?.foldersMenu() }
        message.onMenu = { [weak self] in
            guard let self, self.items.isEmpty else { return nil }
            return self.foldersMenu()
        }
        collection.onKeyboardMenu = { [weak self] foldersOnly in self?.showKeyboardMenu(foldersOnly: foldersOnly) ?? false }
        collection.setAccessibilityCustomActions([NSAccessibilityCustomAction(name: "Manage Media Folders") { [weak self] in
            self?.showKeyboardMenu(foldersOnly: true) ?? false
        }])
        collection.onActivate = { [weak self] in self?.beginUserAction(); self?.openSelected() }
        collection.onCopy = { [weak self] in self?.beginUserAction(); self?.copySelected() }
        collection.onDelete = { [weak self] in self?.beginUserAction(); self?.deleteSelected() }
        collection.onClose = { [weak self] in self?.onClose?() }
        collection.onSearch = { [weak self] in self?.focusSearch() }
        scroll.documentView = collection; scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true; scroll.drawsBackground = false; addSubview(scroll)
        message.alignment = .center; message.font = .systemFont(ofSize: 13); addSubview(message)
        store.$items.combineLatest(store.$loadError, store.$isLoading).receive(on: RunLoop.main).sink { [weak self] _ in self?.reload() }.store(in: &subscriptions)
        media.$items.combineLatest(media.$folders, media.$error, media.$isLoading).receive(on: RunLoop.main).sink { [weak self] _ in self?.reload() }.store(in: &subscriptions)
        accessStatus.font = .systemFont(ofSize: 10.5); accessStatus.textColor = .secondaryLabelColor
        accessStatus.lineBreakMode = .byTruncatingTail; accessStatus.isHidden = true; addSubview(accessStatus)
        search.nextKeyView = collection; collection.nextKeyView = search
        for (name, scrolling) in [(NSScrollView.willStartLiveScrollNotification, true), (NSScrollView.didEndLiveScrollNotification, false)] {
            scrollObservers.append(NotificationCenter.default.addObserver(forName: name, object: scroll, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.setScrolling(scrolling) }
            })
        }
        collection.setAccessibilityLabel("Media items")
        reload(force: true)
    }
    deinit { (windowObservers + scrollObservers).forEach { NotificationCenter.default.removeObserver($0) } }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    func focusSearch() { window?.makeFirstResponder(search); search.selectText(nil) }
    func activate() { if window != nil, ownerValid() { media.activate(mediaClient) } }
    func invalidate() {
        focusReturn?.cancel(); focusReturn = nil
        shareFocusReturn?.cancel(); shareFocusReturn = nil
        generation &+= 1; presentationGeneration &+= 1
        captureSharing?.detach(); captureSharing = nil; shareRequest = nil
        preview?.close(); preview = nil; closeFilePreview()
        if let ownedSheet, window?.attachedSheet === ownedSheet { window?.endSheet(ownedSheet, returnCode: .cancel) }
        ownedSheet = nil; media.deactivate(mediaClient); thumbnails = [:]
        thumbnailTasks.values.forEach { $0.task.cancel() }; thumbnailTasks = [:]
        if actionError != nil { actionError = nil; setAccessStatus(statusText()) }
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        windowObservers.forEach { NotificationCenter.default.removeObserver($0) }; windowObservers = []
        if let window {
            let center = NotificationCenter.default
            windowObservers.append(center.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.invalidate() }
            })
            for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification] {
                windowObservers.append(center.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated {
                        for tile in self?.collection.subviews.compactMap({ $0 as? CaptureLibraryTile }) ?? [] { tile.resamplePointer() }
                    }
                })
            }
        }
        activate()
    }
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil { invalidate(); setScrolling(false) }
        super.viewWillMove(toWindow: newWindow)
    }
    private func setScrolling(_ scrolling: Bool) {
        isScrolling = scrolling
        for tile in collection.subviews.compactMap({ $0 as? CaptureLibraryTile }) { tile.setScrolling(scrolling) }
    }
    func controlTextDidChange(_ obj: Notification) { beginUserAction(); reload(force: true) }
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if textView.hasMarkedText() { return false }
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            if !search.stringValue.isEmpty { search.stringValue = ""; reload(force: true) } else { onClose?() }; return true
        }
        if commandSelector == #selector(NSResponder.moveDown(_:)) || commandSelector == #selector(NSResponder.insertNewline(_:)) {
            guard !items.isEmpty else { return true }
            collection.selectionIndexPaths = [IndexPath(item: 0, section: 0)]
            if commandSelector == #selector(NSResponder.insertNewline(_:)) { openSelected() }
            else { window?.makeFirstResponder(collection) }; return true
        }
        return false
    }
    private func reload(force: Bool = false) {
        if !force && shouldSkipCatalogReload() { return }
        rememberAppliedCatalog()
        let selected = selectedItem?.id
        let query = search.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        var next = store.items.map(Item.capture)
        next.append(contentsOf: media.items.map(Item.file))
        if !query.isEmpty {
            next = next.filter { $0.searchText.localizedStandardContains(query) }
        }
        next.sort { $0.date == $1.date ? $0.id < $1.id : $0.date > $1.date }
        let nextMessage: String
        if let error = store.loadError { nextMessage = error }
        else if store.isLoading || media.isLoading { nextMessage = "Loading Media…" }
        else if query.isEmpty { nextMessage = "Saved captures and media in your folders appear here." }
        else { nextMessage = "No matching media" }
        let nextAccess = statusText()
        let itemsChanged = next != items
        if itemsChanged {
            items = next
            let keys = Set(items.map(\.cacheKey)); thumbnails = thumbnails.filter { keys.contains($0.key) }
            for (key, pending) in thumbnailTasks where !keys.contains(key) { pending.task.cancel(); thumbnailTasks[key] = nil }
            collection.reloadData()
            if let selected, let index = items.firstIndex(where: { $0.id == selected }) { collection.selectionIndexPaths = [IndexPath(item: index, section: 0)] }
        }
        if message.stringValue != nextMessage { message.stringValue = nextMessage }
        message.isHidden = !items.isEmpty && store.loadError == nil
        if accessStatus.stringValue != nextAccess { setAccessStatus(nextAccess) }
        preview?.reconcile()
        if let preview {
            let navigation = navigation(for: .capture(preview.selectedItem))
            if navigation.index == nil { preview.close() } else { preview.setNavigation(navigation) }
        }
        if let file = previewedFile {
            if !media.contains(file) || !ownerValid() || navigation(for: .file(file)).index == nil { closeFilePreview() }
            else { updateFileNavigation(file) }
        }
    }

    private func shouldSkipCatalogReload() -> Bool {
        store.items == observedCaptures
            && store.loadError == observedCaptureLoadError
            && store.isLoading == observedCaptureLoading
            && media.items == observedMediaItems
            && media.folders == observedMediaFolders
            && media.error == observedMediaError
            && media.isLoading == observedMediaLoading
    }

    private func rememberAppliedCatalog() {
        observedCaptures = store.items
        observedCaptureLoadError = store.loadError
        observedCaptureLoading = store.isLoading
        observedMediaItems = media.items
        observedMediaFolders = media.folders
        observedMediaError = media.error
        observedMediaLoading = media.isLoading
    }
    private func contains(_ item: Item) -> Bool {
        switch item { case .capture(let capture): return store.contains(capture); case .file(let file): return media.contains(file) }
    }
    func numberOfSections(in collectionView: NSCollectionView) -> Int { 1 }
    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int { items.count }
    func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        let cell = collectionView.makeItem(withIdentifier: .init("capture"), for: indexPath) as! CaptureLibraryCell
        let item = items[indexPath.item]
        let kind: CaptureLibraryTile.Kind = { if case .file(let file) = item { return file.kind == .movie ? .video : .image }; return .capture }()
        cell.configure(title: item.title, date: item.date, kind: kind, image: thumbnails[item.cacheKey], scrolling: isScrolling,
                       action: { [weak self] in self?.open(item) })
        if ownerValid(), thumbnails[item.cacheKey] == nil, thumbnailTasks[item.cacheKey] == nil {
            let generation = generation; let taskID = UUID()
            let task = Task { [weak self] in
                guard let self else { return }
                defer { if self.thumbnailTasks[item.cacheKey]?.id == taskID { self.thumbnailTasks[item.cacheKey] = nil } }
                do {
                    let data: Data
                    switch item { case .capture(let capture): data = try await self.store.thumbnail(for: capture)
                    case .file(let file): data = try await self.media.thumbnail(file) }
                    guard !Task.isCancelled, self.generation == generation, self.contains(item), let image = NSImage(data: data) else { return }
                    if self.thumbnails.count >= 128, let key = self.thumbnails.keys.first { self.thumbnails.removeValue(forKey: key) }
                    self.thumbnails[item.cacheKey] = image
                    if let index = self.items.firstIndex(of: item),
                       let cell = self.collection.item(at: IndexPath(item: index, section: 0)) as? CaptureLibraryCell {
                        cell.setImage(image)
                    }
                } catch {
                }
            }
            thumbnailTasks[item.cacheKey] = (taskID, task)
        }
        return cell
    }
    private var selectedItem: Item? {
        guard let index = collection.selectionIndexPaths.first?.item, items.indices.contains(index) else { return nil }; return items[index]
    }
    private func openSelected() { if let item = selectedItem { open(item) } }
    private func open(_ selected: Item) {
        if case .file(let file) = selected { openFilePreview(file); return }
        guard case .capture(let item) = selected, ownerValid(), store.contains(item), let window, window.attachedSheet == nil else { return }
        generation &+= 1
        if let index = items.firstIndex(of: selected) { collection.selectionIndexPaths = [IndexPath(item: index, section: 0)] }
        let controller = CaptureLibraryPreview(store: store, profileOwner: profileOwner, selected: item, parent: window,
            valid: { [weak self, weak window] in
                guard let self, let window else { return false }
                return self.window === window && !self.isHidden && self.ownerValid()
            })
        prepareFocusReturn()
        controller.sourceRect = { [weak self] in self?.previewSourceRect(selected) }
        controller.sourceImage = thumbnails[selected.cacheKey]
        controller.onOpenSource = { [weak self] url in self?.onOpenSource?(url) }
        controller.onToast = { [weak self] in self?.onToast?($0) }
        controller.onClose = { [weak self, weak controller] in
            guard let self, self.preview === controller else { return }
            self.preview = nil
            self.focusReturn?.restore()
        }
        controller.onMove = { [weak self] offset in self?.movePreview(from: .capture(item), offset: offset) }
        controller.setNavigation(navigation(for: selected))
        preview = controller; controller.show()
    }
    private func copySelected() {
        guard ownerValid(), let selection = selectedItem else { return }
        if case .file(let file) = selection { copyFile(file); return }
        guard case .capture(let item) = selection else { return }
        let token = generation
        Task { [weak self] in
            guard let self else { return }
            do {
                let data = try await self.store.data(for: item)
                guard self.ownerValid(), self.generation == token, self.selectedItem == selection, self.store.contains(item) else { return }
                NSPasteboard.general.clearContents()
                if !NSPasteboard.general.setData(data, forType: .png) { throw CocoaError(.fileWriteUnknown) }
                self.onToast?(.copiedFile([]))
            } catch {
                guard self.ownerValid(), self.generation == token else { return }
                self.message.stringValue = error.localizedDescription; self.message.isHidden = false
            }
        }
    }
    private func deleteSelected() {
        guard let item = selectedItem else { return }
        if case .file(let file) = item { hideFile(file); return }
        open(item)
        if case .capture(let capture) = item, preview?.selectedItem == capture { preview?.deleteImage() }
    }
    private func showKeyboardMenu(foldersOnly: Bool) -> Bool {
        guard let request = keyboardMenu(foldersOnly: foldersOnly) else { return false }
        request.menu.popUp(positioning: nil, at: request.point, in: collection)
        return true
    }
    func keyboardMenu(foldersOnly: Bool) -> (menu: NSMenu, point: NSPoint)? {
        guard ownerValid() else { return nil }
        let selected = foldersOnly ? nil : collection.selectionIndexPaths.first
        guard let menu = selected.flatMap({ collection.onMenu?($0.item) }) ?? foldersMenu() else { return nil }
        let visible = collection.visibleRect
        let fallback = NSPoint(x: visible.minX + 10, y: visible.minY + 10)
        guard let selectedFrame = selected.map({ collection.frameForItem(at: $0.item) }),
              visible.intersects(selectedFrame) else { return (menu, fallback) }
        let point = NSPoint(x: min(max(selectedFrame.minX, visible.minX), visible.maxX),
                            y: min(max(selectedFrame.maxY, visible.minY), visible.maxY))
        return (menu, point)
    }
    private func foldersMenu() -> NSMenu? {
        guard ownerValid() else { return nil }
        beginUserAction()
        let menu = NSMenu(); menu.autoenablesItems = false
        for folder in media.folders {
            let section = NSMenuItem(title: folder.name, action: nil, keyEquivalent: "")
            let submenu = NSMenu(); submenu.autoenablesItems = false
            let explanation: String
            switch folder.access {
            case .available: explanation = "Available"
            case .disabled: explanation = "Not shown in this Space"
            case .unavailable(let reason): explanation = reason
            }
            let status = NSMenuItem(title: explanation, action: nil, keyEquivalent: ""); status.isEnabled = false; submenu.addItem(status)
            submenu.addItem(MenuAction.item("Choose Folder to Allow Access…") { [weak self] in self?.chooseFolder(folder.url) })
            if folder.access == .disabled {
                submenu.addItem(MenuAction.item("Show This Folder") { [weak self] in self?.changeFolder(folder, enabled: true) })
            } else {
                submenu.addItem(MenuAction.item("Stop Showing This Folder") { [weak self] in self?.changeFolder(folder, enabled: false) })
            }
            section.submenu = submenu; section.toolTip = folder.url.path; menu.addItem(section)
        }
        menu.addItem(.separator())
        menu.addItem(MenuAction.item("Add Media Folder…") { [weak self] in self?.chooseFolder(nil) })
        menu.addItem(MenuAction.item("Refresh") { [weak self] in self?.media.refresh() })
        menu.addItem(MenuAction.item("Show Hidden Files Again") { [weak self] in
            guard let self, self.ownerValid() else { return }
            let presentation = self.presentationGeneration
            Task { [weak self] in
                guard let self else { return }
                do { try await self.media.restoreHidden() }
                catch {
                    guard self.ownerValid() else { return }
                    if self.presentationGeneration == presentation { self.report(error) }
                }
            }
        })
        menu.addItem(MenuAction.item("Files and Folders Privacy Settings…") {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders") { NSWorkspace.shared.open(url) }
        })
        return menu
    }
    private func changeFolder(_ folder: ExternalMediaFolder, enabled: Bool) {
        guard ownerValid() else { return }
        if previewedFile?.folder == folder.url { closeFilePreview() }
        let presentation = presentationGeneration
        Task { [weak self] in
            guard let self else { return }
            do { try await self.media.setEnabled(enabled, folder: folder.url) }
            catch {
                guard self.ownerValid() else { return }
                self.media.refresh()
                if self.presentationGeneration == presentation { self.report(error) }
            }
        }
    }
    private func chooseFolder(_ suggested: URL?) {
        guard ownerValid(), let window, window.attachedSheet == nil, ownedSheet == nil else { return }
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false
        panel.allowsMultipleSelection = false; panel.canCreateDirectories = false
        panel.title = "Allow Media Folder Access"; panel.prompt = "Allow Access"
        panel.message = "Parc shows images and videos directly in the folder you choose. Original files stay in place."
        panel.directoryURL = suggested; ownedSheet = panel
        let token = generation, presentation = presentationGeneration
        panel.beginSheetModal(for: window) { [weak self, weak panel] response in
            MainActor.assumeIsolated {
                guard let self, self.ownedSheet === panel else { return }; self.ownedSheet = nil
                guard response == .OK, self.ownerValid(), self.generation == token, let url = panel?.url else { return }
                Task { [weak self] in
                    guard let self else { return }
                    do { try await self.media.grant(url) }
                    catch {
                        guard self.ownerValid() else { return }
                        if self.presentationGeneration == presentation { self.report(error) }
                    }
                }
            }
        }
    }
    private func statusText() -> String {
        if let actionError { return actionError }
        if let error = media.error { return error }
        let unavailable = media.folders.filter { if case .unavailable = $0.access { return true }; return false }.count
        guard unavailable > 0 else { return "" }
        return "\(unavailable) folder\(unavailable == 1 ? " needs" : "s need") access. Right-click empty space to fix."
    }
    private func report(_ error: Error) {
        guard ownerValid() else { return }
        actionError = error.localizedDescription; setAccessStatus(statusText())
    }
    private func beginUserAction() {
        guard actionError != nil else { return }
        actionError = nil; setAccessStatus(statusText())
    }
    private func setAccessStatus(_ text: String) {
        accessStatus.stringValue = text; accessStatus.toolTip = text.isEmpty ? nil : text
        accessStatus.isHidden = text.isEmpty; needsLayout = true
    }
    private func runFileAction(_ file: ExternalMediaFile, action: @escaping () async throws -> Void) {
        guard ownerValid(), media.contains(file) else { return }
        let token = generation, presentation = presentationGeneration
        Task { [weak self] in
            guard let self else { return }
            do {
                let access = try await self.media.acquire(file)
                guard self.ownerValid(), self.generation == token, self.media.contains(file) else { return }
                try await action(); withExtendedLifetime(access) {}
            } catch {
                guard self.ownerValid() else { return }
                self.media.refresh()
                if self.presentationGeneration == presentation { self.report(error) }
            }
        }
    }
    private func fileMenu(_ file: ExternalMediaFile) -> NSMenu {
        let menu = NSMenu(); menu.autoenablesItems = false
        menu.addItem(MenuAction.item("Preview") { [weak self] in self?.openFilePreview(file) })
        menu.addItem(MenuAction.item("Open in Default App") { [weak self] in self?.openFile(file) })
        menu.addItem(MenuAction.item("Show in Finder") { [weak self] in
            guard let self, self.ownerValid(), self.media.contains(file) else { return }
            NSWorkspace.shared.activateFileViewerSelecting([file.url])
        })
        menu.addItem(MenuAction.item("Copy File") { [weak self] in self?.copyFile(file) })
        if file.kind == .image {
            menu.addItem(MenuAction.item("Copy Image") { [weak self] in self?.copyFileImage(file) })
        }
        menu.addItem(MenuAction.item("Save a Copy…") { [weak self] in self?.saveFile(file) })
        menu.addItem(.separator())
        menu.addItem(MenuAction.item("Hide from Media") { [weak self] in
            guard let self else { return }; self.hideFile(file)
        })
        return menu
    }
    private func hideFile(_ file: ExternalMediaFile) {
        guard ownerValid(), media.contains(file) else { return }
        let presentation = presentationGeneration
        Task { [weak self] in
            guard let self else { return }
            do { try await self.media.hide(file) }
            catch {
                guard self.ownerValid() else { return }
                self.media.refresh()
                if self.presentationGeneration == presentation { self.report(error) }
            }
        }
    }
    private func copyFile(_ file: ExternalMediaFile) {
        runFileAction(file) {
            NSPasteboard.general.clearContents()
            guard NSPasteboard.general.writeObjects([file.url as NSURL]) else { throw CocoaError(.fileWriteUnknown) }
            self.onToast?(.copiedFile([file.url]))
        }
    }
    private func copyFileImage(_ file: ExternalMediaFile) {
        let ticket = MediaLibraryActionTicket(generation: generation)
        runFileAction(file) {
            let data = try await self.media.data(file)
            guard ticket.canCommit(generation: self.generation, ownerValid: self.ownerValid(), itemCurrent: self.media.contains(file)) else { return }
            guard let type = UTType(filenameExtension: file.url.pathExtension),
                  CGImageSourceCreateWithData(data as CFData, nil) != nil else { throw CocoaError(.fileReadCorruptFile) }
            NSPasteboard.general.clearContents()
            guard NSPasteboard.general.setData(data, forType: NSPasteboard.PasteboardType(type.identifier)) else { throw CocoaError(.fileWriteUnknown) }
            self.onToast?(.copiedFile([file.url]))
        }
    }
    private func openFile(_ file: ExternalMediaFile) {
        runFileAction(file) {
            guard NSWorkspace.shared.open(file.url) else { throw CocoaError(.fileReadUnknown) }
        }
    }
    private func saveFile(_ file: ExternalMediaFile) {
        guard ownerValid(), media.contains(file), let window, window.attachedSheet == nil, ownedSheet == nil else { return }
        let panel = NSSavePanel(); panel.nameFieldStringValue = file.title; panel.canCreateDirectories = true
        if let type = UTType(filenameExtension: file.url.pathExtension) { panel.allowedContentTypes = [type] }
        let token = generation; ownedSheet = panel
        panel.beginSheetModal(for: window) { [weak self, weak panel] response in
            MainActor.assumeIsolated {
                guard let self, self.ownedSheet === panel else { return }; self.ownedSheet = nil
                guard response == .OK, self.ownerValid(), self.generation == token, self.media.contains(file), let url = panel?.url else { return }
                self.runFileAction(file) { try await self.media.export(file, to: url) }
            }
        }
    }
    private func captureMenu(_ capture: SavedCapture) -> NSMenu {
        let item = Item.capture(capture), token = generation
        func current(_ owner: CaptureLibraryView) -> Bool {
            owner.ownerValid() && owner.generation == token && owner.selectedItem == item && owner.store.contains(capture)
        }
        let menu = NSMenu(); menu.autoenablesItems = false
        menu.addItem(MenuAction.item("Preview") { [weak self] in guard let self, current(self) else { return }; self.open(item) })
        for destination in CaptureLibrarySharePayload.Destination.allCases {
            let row = MenuAction.item(destination.title) { [weak self] in
                guard let self, current(self) else { return }; self.shareCapture(capture, to: destination)
            }
            row.isEnabled = shareRequest == nil && NSSharingService(named: destination.serviceName) != nil
            menu.addItem(row)
        }
        menu.addItem(MenuAction.item("Copy Image") { [weak self] in guard let self, current(self) else { return }; self.copySelected() })
        if let url = URL(string: capture.sourceURL), ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host != nil {
            menu.addItem(.separator())
            menu.addItem(MenuAction.item("Open Source Page") { [weak self] in guard let self, current(self) else { return }; self.onOpenSource?(capture.sourceURL) })
            menu.addItem(MenuAction.item("Copy Source Address") { [weak self] in
                guard let self, current(self) else { return }
                NSPasteboard.general.clearContents()
                if NSPasteboard.general.setString(capture.sourceURL, forType: .string) { self.onToast?(.copiedCurrentURL(URL(string: capture.sourceURL))) }
                else { self.report(CocoaError(.fileWriteUnknown)) }
            })
        }
        menu.addItem(.separator())
        menu.addItem(MenuAction.item("Delete…") { [weak self] in guard let self, current(self) else { return }; self.deleteSelected() })
        return menu
    }
    private func shareCapture(_ capture: SavedCapture, to destination: CaptureLibrarySharePayload.Destination) {
        guard ownerValid(), store.contains(capture), shareRequest == nil, let window, window.attachedSheet == nil else { return }
        let request = UUID(), token = generation; shareRequest = request
        Task { [weak self, weak window] in
            guard let self, let window else { return }
            do {
                let data = try await self.store.data(for: capture)
                guard self.shareRequest == request else { return }
                guard self.ownerValid(), self.generation == token, self.window === window,
                      self.selectedItem == .capture(capture), self.store.contains(capture) else { self.shareRequest = nil; return }
                guard let payload = CaptureLibrarySharePayload(png: data, sourceAddress: capture.sourceURL, destination: destination),
                      let sharing = CaptureLibrarySharing(payload: payload, parent: window, source: self.collection, completion: { [weak self] error in
                          guard let self, self.shareRequest == request else { return }
                          self.captureSharing = nil; self.shareRequest = nil
                          guard self.ownerValid(), self.generation == token else { return }
                          if let error, !CaptureLibrarySharing.isCancellation(error) { self.report(error) }
                          self.shareFocusReturn?.restore()
                      }) else { throw CocoaError(.featureUnsupported) }
                self.shareFocusReturn?.cancel()
                self.shareFocusReturn = CaptureFocusReturn(window: window, target: self.collection, valid: { [weak self, weak window] in
                    guard let self, let window else { return false }
                    return self.ownerValid() && self.window === window && self.generation == token && self.selectedItem == .capture(capture)
                })
                self.captureSharing = sharing; sharing.present()
            } catch {
                guard self.shareRequest == request else { return }; self.shareRequest = nil
                if self.ownerValid(), self.generation == token { self.report(error) }
            }
        }
    }
    private func navigation(for item: Item) -> MediaLibraryNavigation {
        MediaLibraryNavigation(orderedIDs: items.map(\.id), selectedID: item.id)
    }
    private func movePreview(from item: Item, offset: Int) {
        guard ownerValid(), contains(item), let id = navigation(for: item).neighbor(offset),
              let next = items.first(where: { $0.id == id }) else { return }
        preview?.close(); closeFilePreview(); open(next)
    }
    private func updateFileNavigation(_ file: ExternalMediaFile) {
        let navigation = navigation(for: .file(file))
        filePreview?.update(url: file.url, title: file.title + " · " + file.date.formatted(date: .abbreviated, time: .shortened),
            ordinal: navigation.ordinal, count: items.count, canOpen: file.isLocal,
            canMovePrevious: navigation.neighbor(-1) != nil, canMoveNext: navigation.neighbor(1) != nil)
    }
    private func closeFilePreview() {
        filePreview?.close(); filePreview = nil; previewedFile = nil; fileAccess = nil
    }
    private func openFilePreview(_ file: ExternalMediaFile) {
        guard ownerValid(), media.contains(file), let parent = window, parent.attachedSheet == nil else { return }
        if let index = navigation(for: .file(file)).index { collection.selectionIndexPaths = [IndexPath(item: index, section: 0)] }
        generation &+= 1; let token = generation
        let presentation = presentationGeneration
        closeFilePreview()
        Task { [weak self, weak parent] in
            guard let self, let parent else { return }
            do {
                let access = try await self.media.acquire(file)
                guard self.ownerValid(), self.window === parent, self.generation == token, self.media.contains(file), parent.attachedSheet == nil else { return }
                self.prepareFocusReturn()
                let controller = DownloadLibraryPreview(itemName: "media file")
                controller.sourceRect = { [weak self] in self?.previewSourceRect(.file(file)) }
                controller.sourceImage = self.thumbnails[Item.file(file).cacheKey]
                self.fileAccess = access; self.filePreview = controller; self.previewedFile = file
                controller.onClosed = { [weak self, weak controller] in
                    guard let self, self.filePreview === controller else { return }
                    self.filePreview = nil; self.previewedFile = nil; self.fileAccess = nil
                    self.focusReturn?.restore()
                }
                controller.onOpen = { [weak self] in self?.openFile(file) }
                controller.onCopy = { [weak self] in self?.copyFile(file) }
                controller.onMenu = { [weak self] in self?.fileMenu(file) }
                controller.onMove = { [weak self] forward in self?.movePreview(from: .file(file), offset: forward ? 1 : -1) }
                self.updateFileNavigation(file)
                controller.present(on: parent)
            } catch {
                guard self.ownerValid() else { return }
                self.media.refresh()
                if self.presentationGeneration == presentation { self.report(error) }
            }
        }
    }
    private func prepareFocusReturn() {
        focusReturn?.cancel()
        guard let window else { focusReturn = nil; return }
        let target: NSView = search.currentEditor() === window.firstResponder ? search : collection
        focusReturn = CaptureFocusReturn(window: window, target: target, valid: { [weak self, weak window] in
            guard let self, let window else { return false }
            return self.window === window && !self.isHiddenOrHasHiddenAncestor && self.ownerValid()
        })
    }
    private func previewSourceRect(_ item: Item) -> NSRect? {
        guard ownerValid(), contains(item), let index = items.firstIndex(of: item),
              thumbnails[item.cacheKey] != nil,
              let cell = collection.item(at: IndexPath(item: index, section: 0)) as? CaptureLibraryCell,
              cell.view.window === window else { return nil }
        return cell.previewSourceRect()
    }
    override func layout() {
        super.layout()
        let listTop: CGFloat
        if let searchBackdrop {
            let inset = LibraryPageHeader.inset
            searchBackdrop.frame = NSRect(x: inset, y: LibraryPageHeader.top, width: max(0, bounds.width - 2 * inset), height: LibraryPageHeader.height)
            listTop = searchBackdrop.frame.maxY
        } else {
            search.frame = NSRect(x: 10, y: 18, width: max(0, bounds.width - 20), height: 28)
            listTop = 46
        }
        let statusHeight: CGFloat = accessStatus.isHidden ? 0 : 28
        scroll.frame = NSRect(x: 0, y: listTop, width: bounds.width, height: max(0, bounds.height - listTop - statusHeight))
        let width = max(1, (scroll.contentSize.width - 30) / 2)
        (collection.collectionViewLayout as? NSCollectionViewFlowLayout)?.itemSize = NSSize(width: width, height: width)
        message.frame = NSRect(x: 22, y: 100, width: max(0, bounds.width - 44), height: 140)
        accessStatus.frame = NSRect(x: 12, y: bounds.height - 24, width: max(0, bounds.width - 24), height: 18)
    }
}

@MainActor
private final class CaptureLibraryCell: NSCollectionViewItem {
    private let tile = CaptureLibraryTile()
    private let button = ActionButton("")
    override func loadView() {
        view = tile
        button.isBordered = false; button.imagePosition = .noImage
        button.autoresizingMask = [.width, .height]; tile.addSubview(button)
    }
    func configure(title: String, date: Date, kind: CaptureLibraryTile.Kind, image: NSImage?, scrolling: Bool, action: @escaping () -> Void) {
        _ = view
        button.frame = tile.bounds
        tile.configure(kind: kind, image: image, scrolling: scrolling)
        button.actionBlock = action; button.toolTip = title
        button.setAccessibilityLabel(title.isEmpty ? "Saved capture" : title)
        button.setAccessibilityHelp("Preview media, \(date.formatted(date: .abbreviated, time: .shortened))")
    }
    func setImage(_ image: NSImage) { tile.setImage(image) }
    func previewSourceRect() -> NSRect? {
        guard let artwork = tile.artworkRect,
              tile.visibleRect.intersection(artwork).width > 0,
              tile.visibleRect.intersection(artwork).height > 0 else { return nil }
        return tile.convert(artwork, to: nil)
    }
    override var isSelected: Bool { didSet { tile.isSelected = isSelected } }
}

@MainActor
private final class CaptureLibraryTile: NSView {
    enum Kind { case capture, image, video }
    var isSelected = false { didSet { apply(animated: true) } }
    private(set) var artworkRect: NSRect?
    private var kind = Kind.image
    private var image: NSImage?
    private var area: NSTrackingArea?
    private var hovered = false
    private var shouldHighlight = false
    private var scrolling = false
    private var applied: Bool?
    private let plate = CALayer(), placeholder = CALayer(), paper = CALayer()
    private let border = CAShapeLayer(), artwork = CALayer(), play = CALayer()
    private static let playGlyph: NSImage? = {
        guard let symbol = NSImage(systemSymbolName: "play.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 22, weight: .bold)) else { return nil }
        let glyph = NSImage(size: symbol.size, flipped: false) { rect in
            symbol.draw(in: rect); NSColor.white.withAlphaComponent(0.95).set(); rect.fill(using: .sourceAtop); return true
        }
        let margin: CGFloat = 3
        return NSImage(size: NSSize(width: symbol.size.width + 2 * margin, height: symbol.size.height + 2 * margin), flipped: false) { rect in
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.2); shadow.shadowBlurRadius = 2; shadow.shadowOffset = NSSize(width: 0, height: -1)
            shadow.set(); glyph.draw(in: rect.insetBy(dx: margin, dy: margin)); return true
        }
    }()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        for shape in [plate, placeholder, paper] { shape.cornerCurve = .continuous }
        plate.cornerRadius = 12; placeholder.cornerRadius = 8; paper.cornerRadius = 2
        paper.backgroundColor = NSColor.white.cgColor; paper.shadowColor = NSColor.black.cgColor
        border.fillColor = nil; border.strokeColor = NSColor.white.withAlphaComponent(0.5).cgColor
        border.lineWidth = 2; border.lineCap = .round; border.lineDashPattern = [5]
        artwork.contentsGravity = .resize
        play.contents = Self.playGlyph
        for sublayer in [plate, placeholder, paper, border, artwork, play] { layer?.addSublayer(sublayer) }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func configure(kind: Kind, image: NSImage?, scrolling: Bool) {
        self.kind = kind; self.scrolling = scrolling
        CATransaction.begin(); CATransaction.setDisableActions(true)
        play.isHidden = kind != .video
        CATransaction.commit()
        setImage(image)
        resamplePointer(animated: false)
    }
    func setImage(_ image: NSImage?) {
        self.image = image
        CATransaction.begin(); CATransaction.setDisableActions(true)
        artwork.contents = image
        CATransaction.commit()
        apply(animated: false)
    }
    func setScrolling(_ scrolling: Bool) {
        guard scrolling != self.scrolling else { return }
        self.scrolling = scrolling
        if !scrolling { resamplePointer() }
    }
    func resamplePointer(animated: Bool = true) {
        hovered = window.map { window in
            let point = convert(window.mouseLocationOutsideOfEventStream, from: nil)
            return window.isKeyWindow && visibleRect.contains(point) && hitShapeContains(point)
        } ?? false
        shouldHighlight = hovered && !scrolling
        apply(animated: animated)
    }
    override func prepareForReuse() {
        super.prepareForReuse()
        hovered = false; shouldHighlight = false; applied = nil
        for sublayer in [plate, paper, border, artwork] { sublayer.removeAllAnimations() }
    }

    override func layout() {
        super.layout()
        let glyph = Self.playGlyph?.size ?? .zero
        CATransaction.begin(); CATransaction.setDisableActions(true)
        play.frame = NSRect(x: bounds.midX - glyph.width / 2, y: bounds.midY - glyph.height / 2, width: glyph.width, height: glyph.height)
        CATransaction.commit()
        apply(animated: false)
    }
    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        let scale = window?.backingScaleFactor ?? 2
        for sublayer in [artwork, play] { sublayer.contentsScale = scale }
    }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); apply(animated: false) }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); resamplePointer(animated: false) }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let area { removeTrackingArea(area) }
        let next = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .activeInKeyWindow, .inVisibleRect], owner: self)
        area = next; addTrackingArea(next)
    }
    override func mouseEntered(with event: NSEvent) { hover(hitShapeContains(convert(event.locationInWindow, from: nil))) }
    override func mouseMoved(with event: NSEvent) { hover(hitShapeContains(convert(event.locationInWindow, from: nil))) }
    override func mouseExited(with event: NSEvent) { hover(false) }
    private func hover(_ inside: Bool) {
        guard inside != hovered else { return }
        hovered = inside; shouldHighlight = inside && !scrolling; apply(animated: true)
    }
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let superview, hitShapeContains(convert(point, from: superview)) else { return nil }
        return super.hitTest(point)
    }
    private func plateFrame(_ lit: Bool) -> NSRect { bounds.insetBy(dx: lit ? 0 : 4, dy: lit ? 0 : 4) }
    private func hitShapeContains(_ point: NSPoint) -> Bool {
        NSBezierPath(roundedRect: plateFrame(shouldHighlight || isSelected), xRadius: 12, yRadius: 12).contains(point)
    }

    private var side: CGFloat { min(120, max(0, min(bounds.width, bounds.height) - 20)) }
    private func fill(_ alpha: CGFloat) -> CGColor {
        var color = NSColor.clear.cgColor
        effectiveAppearance.performAsCurrentDrawingAppearance {
            color = NSColor.labelColor.withAlphaComponent(NSColor.labelColor.alphaComponent * alpha).cgColor
        }
        return color
    }
    private func apply(animated: Bool) {
        let lit = shouldHighlight || isSelected
        let changed = applied != lit
        let animate = animated && changed && applied != nil && window != nil
            && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        applied = lit
        func set(_ layer: CALayer, _ key: String, _ value: Any) {
            let from = animate && !layer.isHidden ? (layer.presentation() ?? layer).value(forKey: key) : nil
            layer.setValue(value, forKey: key)
            if let from {
                let spring = CASpringAnimation(keyPath: key)
                spring.mass = 1; spring.stiffness = pow(2 * .pi / 0.18, 2); spring.damping = 4 * .pi * 0.8 / 0.18
                spring.fromValue = from; spring.toValue = value; spring.duration = spring.settlingDuration
                layer.add(spring, forKey: key)
            } else if changed {
                layer.removeAnimation(forKey: key)
            }
        }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        let down: CGFloat = paper.contentsAreFlipped() ? 1 : -1
        let plateRect = plateFrame(lit)
        plate.position = CGPoint(x: plateRect.midX, y: plateRect.midY)
        set(plate, "bounds", NSValue(rect: NSRect(origin: .zero, size: plateRect.size)))
        set(plate, "backgroundColor", fill(lit ? 0.15 : 0.05))
        let increaseContrast = isSelected && NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        plate.borderWidth = increaseContrast ? 1 : 0
        effectiveAppearance.performAsCurrentDrawingAppearance { plate.borderColor = NSColor.keyboardFocusIndicatorColor.cgColor }
        let size = image?.size ?? .zero
        let shown = size.width > 0 && size.height > 0
        placeholder.isHidden = shown; paper.isHidden = !shown || kind == .capture
        border.isHidden = !shown || kind != .capture; artwork.isHidden = !shown
        placeholder.frame = NSRect(x: bounds.midX - side / 2, y: bounds.midY - side / 2, width: side, height: side)
        placeholder.backgroundColor = fill(0.05)
        if shown {
            let room = max(0, side * (lit ? 1 : 0.95) - 8)
            let scale = min(room / size.width, room / size.height)
            let local = NSRect(x: 0, y: 0, width: size.width * scale + 8, height: size.height * scale + 8)
            let paperFrame = local.offsetBy(dx: bounds.midX - local.width / 2, dy: bounds.midY - local.height / 2)
            paper.position = CGPoint(x: paperFrame.midX, y: paperFrame.midY)
            set(paper, "bounds", NSValue(rect: local))
            set(paper, "shadowPath", CGPath(roundedRect: local, cornerWidth: 2, cornerHeight: 2, transform: nil))
            set(paper, "shadowOpacity", NSNumber(value: lit ? 0.2 : 0.1))
            set(paper, "shadowRadius", NSNumber(value: lit ? 5.0 : 1.0))
            set(paper, "shadowOffset", NSValue(size: NSSize(width: 0, height: down * (lit ? 3 : 1))))
            border.frame = bounds
            set(border, "path", CGPath(roundedRect: paperFrame.insetBy(dx: 1, dy: 1), cornerWidth: 1, cornerHeight: 1, transform: nil))
            set(border, "lineDashPhase", NSNumber(value: lit ? 5.0 : 0.0))
            artwork.position = paper.position
            set(artwork, "bounds", NSValue(rect: NSRect(x: 0, y: 0, width: local.width - 8, height: local.height - 8)))
            artworkRect = paperFrame.insetBy(dx: 4, dy: 4)
        } else {
            artworkRect = nil
        }
        CATransaction.commit()
    }
}

@MainActor
private final class CaptureEmptyMessage: NSTextField {
    var onMenu: (() -> NSMenu?)?
    override func menu(for event: NSEvent) -> NSMenu? { onMenu?() }
}

@MainActor
final class CaptureCollectionView: NSCollectionView {
    var onMenu: ((Int) -> NSMenu?)?
    var onEmptyMenu: (() -> NSMenu?)?
    private func tileIndex(at event: NSEvent) -> IndexPath? {
        let point = convert(event.locationInWindow, from: nil)
        guard let index = indexPathForItem(at: point), let tile = item(at: index)?.view, tile.hitTest(point) != nil else { return nil }
        return index
    }
    override func menu(for event: NSEvent) -> NSMenu? {
        guard let index = tileIndex(at: event) else { return onEmptyMenu?() }
        return onMenu?(index.item)
    }
    override func mouseDown(with event: NSEvent) {
        if indexPathForItem(at: convert(event.locationInWindow, from: nil)) != nil, tileIndex(at: event) == nil { return }
        super.mouseDown(with: event)
    }
    var onActivate: (() -> Void)?; var onCopy: (() -> Void)?; var onDelete: (() -> Void)?
    var onClose: (() -> Void)?; var onSearch: (() -> Void)?
    var onKeyboardMenu: ((_ foldersOnly: Bool) -> Bool)?
    @objc func copy(_ sender: Any?) { onCopy?() }
    override func accessibilityPerformShowMenu() -> Bool { onKeyboardMenu?(false) ?? false }
    override func keyDown(with event: NSEvent) {
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        if modifiers == .command, event.charactersIgnoringModifiers == "f" { onSearch?(); return }
        if modifiers == .command, event.charactersIgnoringModifiers == "c" { onCopy?(); return }
        let menuKey = (event.keyCode == 109 && modifiers.subtracting(.option) == .shift)
            || ([36, 76].contains(event.keyCode) && modifiers.subtracting(.option) == .control)
        if menuKey, onKeyboardMenu?(modifiers.contains(.option)) == true { return }
        guard modifiers.isEmpty else { super.keyDown(with: event); return }
        switch event.keyCode { case 36, 76, 49: onActivate?(); case 51, 117: onDelete?(); case 53: onClose?(); default: super.keyDown(with: event) }
    }
}

@MainActor
private final class CaptureLibraryPreview: NSObject {
    let store: CaptureLibraryStore
    private let profileOwner: BrowserStore
    var onOpenSource: ((String) -> Void)?
    var onToast: ((PArcToastContent) -> Void)?
    var onClose: (() -> Void)?
    var onMove: ((Int) -> Void)?
    var sourceRect: (() -> NSRect?)?
    var sourceImage: NSImage?
    private var navigation = MediaLibraryNavigation(orderedIDs: [], selectedID: "")
    private let selected: SavedCapture
    var selectedItem: SavedCapture { selected }
    private weak var parent: NSWindow?
    private let valid: () -> Bool
    private let panel = CapturePreviewPanel(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
    private let backdropRoot = CapturePreviewBackdrop()
    private let backdrop = NSView()
    private let modal = CapturePreviewModal()
    private let transitionImage = CapturePreviewTransitionImage()
    private let root = CapturePreviewModal()
    private let image = NSImageView()
    private let title = NSTextField(labelWithString: "")
    private let status = NSTextField(wrappingLabelWithString: "")
    private let back = ActionButton("", symbol: "chevron.left")
    private let forward = ActionButton("", symbol: "chevron.right")
    private let closeButton = ActionButton("", symbol: "xmark")
    private let more = ActionButton("More", symbol: "ellipsis")
    private let export = ActionButton("Save…", symbol: "square.and.arrow.up")
    private var sharing: CaptureLibrarySharing?
    private var sharingFocusReturn: CaptureFocusReturn?
    private var data: Data?
    private var generation: UInt64 = 0
    private var finished = false
    private var outputSheet: NSWindow?
    private var removalObservers: [NSObjectProtocol] = []
    private var motionObserver: NSObjectProtocol?
    private var closing = false
    private var transition: UInt64 = 0
    init(store: CaptureLibraryStore, profileOwner: BrowserStore, selected: SavedCapture, parent: NSWindow, valid: @escaping () -> Bool) {
        self.store = store; self.profileOwner = profileOwner; self.selected = selected; self.parent = parent; self.valid = valid
        super.init()
        panel.titleVisibility = .hidden; panel.titlebarAppearsTransparent = true
        panel.isReleasedWhenClosed = false; panel.contentView = backdropRoot
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false
        backdropRoot.wantsLayer = true; backdrop.wantsLayer = true; backdrop.layer?.cornerRadius = 10
        backdrop.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.7).cgColor
        backdropRoot.addSubview(backdrop); backdropRoot.addSubview(modal)
        modal.wantsLayer = true; modal.clipsToBounds = false; modal.layer?.masksToBounds = false
        modal.layer?.cornerRadius = 10; modal.layer?.shadowRadius = 5
        modal.layer?.shadowColor = NSColor.black.cgColor; modal.layer?.shadowOpacity = 1
        modal.layer?.shadowOffset = NSSize(width: 0, height: -3)
        root.wantsLayer = true; root.layer?.cornerRadius = 10; root.layer?.masksToBounds = true
        root.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        modal.addSubview(root); modal.addSubview(transitionImage)
        transitionImage.wantsLayer = true; transitionImage.imageScaling = .scaleAxesIndependently
        transitionImage.layer?.opacity = 0; transitionImage.setAccessibilityHidden(true)
        backdropRoot.onDismiss = { [weak self] in self?.dismiss() }
        image.imageScaling = .scaleProportionallyUpOrDown
        image.setAccessibilityLabel("Saved capture preview")
        title.font = .systemFont(ofSize: 12, weight: .medium); title.lineBreakMode = .byTruncatingMiddle
        status.alignment = .center; status.textColor = .secondaryLabelColor
        status.drawsBackground = true; status.backgroundColor = .windowBackgroundColor
        for view in [image, title, status, back, forward, closeButton, more, export] { root.addSubview(view) }
        for button in [back, forward, closeButton, more, export] { button.contentTintColor = .labelColor }
        root.onAppearance = { [weak self] in self?.updateAppearance() }
        closeButton.actionBlock = { [weak self] in self?.dismiss() }; closeButton.setAccessibilityLabel("Close preview")
        back.actionBlock = { [weak self] in self?.move(-1) }; back.setAccessibilityLabel("Previous capture")
        forward.actionBlock = { [weak self] in self?.move(1) }; forward.setAccessibilityLabel("Next capture")
        more.actionBlock = { [weak self] in self?.showMore() }
        export.actionBlock = { [weak self] in self?.saveImage() }
        panel.onCancel = { [weak self] in self?.dismiss() }
        panel.onMove = { [weak self] offset in self?.move(offset) }
        panel.onCopy = { [weak self] in self?.copyImage() }
        panel.onDelete = { [weak self] in self?.deleteImage() }
        closeButton.nextKeyView = back; back.nextKeyView = forward; forward.nextKeyView = more
        more.nextKeyView = export; export.nextKeyView = closeButton
        panel.initialFirstResponder = closeButton
        status.setAccessibilityLabel("Capture preview status")
    }
    func show() {
        guard let parent, valid(), parent.attachedSheet == nil else { close(); return }
        panel.setFrame(parent.frame, display: false); panel.appearance = parent.appearance
        parent.addChildWindow(panel, ordered: .above)
        panel.makeKeyAndOrderFront(nil); panel.makeFirstResponder(closeButton)
        layoutPreview()
        let center = NotificationCenter.default
        for name in [NSWindow.willCloseNotification, NSWindow.willMiniaturizeNotification, NSWindow.willBeginSheetNotification] {
            removalObservers.append(center.addObserver(forName: name, object: parent, queue: .main) { [weak self] _ in MainActor.assumeIsolated { self?.close() } })
        }
        for name in [NSWindow.didResizeNotification, NSWindow.didMoveNotification] {
            removalObservers.append(center.addObserver(forName: name, object: parent, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, let parent = self.parent else { return }
                    if self.closing { self.close(); return }
                    self.settleTransition(); self.panel.setFrame(parent.frame, display: true); self.layoutPreview()
                }
            })
        }
        motionObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil, queue: .main) { [weak self] _ in MainActor.assumeIsolated {
                guard let self, NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
                if self.closing { self.close() } else { self.settleTransition() }
            } }
        transitionImage.image = sourceImage
        if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion, let source = localSourceRect() {
            animate(modal.layer, key: "transform", from: NSValue(caTransform3D: DownloadPreviewGeometry.transform(from: modal.frame, to: source)),
                to: NSValue(caTransform3D: CATransform3DIdentity), opening: true)
            animate(backdrop.layer, key: "opacity", from: 0, to: 1, opening: true)
            animate(modal.layer, key: "shadowOpacity", from: 0, to: 1, opening: true)
            crossfade(opening: true)
        }
        loadSelected()
    }
    private func updateAppearance() {
        root.effectiveAppearance.performAsCurrentDrawingAppearance {
            root.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        }
    }
    private func layoutPreview() {
        updateAppearance()
        backdrop.frame = backdropRoot.bounds
        modal.frame = DownloadPreviewGeometry.modalFrame(in: backdropRoot.bounds)
        modal.layer?.anchorPoint = NSPoint(x: 0.5, y: 0.5)
        modal.layer?.position = NSPoint(x: modal.frame.midX, y: modal.frame.midY)
        modal.clipsToBounds = false; modal.layer?.masksToBounds = false
        root.frame = modal.bounds
        modal.layer?.shadowPath = CGPath(roundedRect: modal.bounds, cornerWidth: 10, cornerHeight: 10, transform: nil)
        let size = root.bounds.size
        image.frame = NSRect(x: 0, y: 42, width: size.width, height: max(0, size.height - 42))
        closeButton.frame = NSRect(x: 8, y: 7, width: 28, height: 28)
        back.frame = NSRect(x: 40, y: 7, width: 28, height: 28); forward.frame = NSRect(x: 72, y: 7, width: 28, height: 28)
        back.isHidden = size.width < 260; forward.isHidden = size.width < 260
        title.frame = NSRect(x: 106, y: 12, width: max(0, size.width - 280), height: 20)
        more.frame = NSRect(x: max(40, size.width - 164), y: 7, width: 70, height: 28)
        export.frame = NSRect(x: max(40, size.width - 90), y: 7, width: 78, height: 28)
        more.isHidden = size.width < 220; export.isHidden = size.width < 140
        status.frame = NSRect(x: 12, y: max(42, size.height / 2), width: max(0, size.width - 24), height: 70)
        let aspect = sourceImage.map { $0.size.height / max(1, $0.size.width) } ?? 1
        let height = size.width * aspect
        transitionImage.frame = NSRect(x: 0, y: (size.height - height) / 2, width: size.width, height: height)
    }
    private func localSourceRect() -> NSRect? {
        guard valid(), let parent, let source = sourceRect?(), source.width > 0, source.height > 0,
              source.intersects(parent.contentView?.bounds ?? .zero) else { return nil }
        return backdropRoot.convert(panel.convertFromScreen(parent.convertToScreen(source)), from: nil)
    }
    private func animate(_ layer: CALayer?, key: String, from: Any, to: Any, opening: Bool) {
        guard let layer else { return }
        let animation = DownloadPreviewGeometry.spring(keyPath: key, ratio: opening ? 0.9 : 0.95, response: opening ? 0.25 : 0.15)
        animation.fromValue = from; animation.toValue = to; layer.add(animation, forKey: key)
    }
    private func crossfade(opening: Bool) {
        guard sourceImage != nil, let picture = transitionImage.layer, let live = root.layer else { return }
        let pictureFrom = opening ? Float(1) : picture.presentation()?.opacity ?? picture.opacity
        let liveFrom = opening ? Float(0) : live.presentation()?.opacity ?? live.opacity
        CATransaction.begin(); CATransaction.setDisableActions(true)
        picture.opacity = opening ? 0 : 1; live.opacity = opening ? 1 : 0
        CATransaction.commit()
        animate(picture, key: "opacity", from: pictureFrom, to: picture.opacity, opening: opening)
        animate(live, key: "opacity", from: liveFrom, to: live.opacity, opening: opening)
    }
    private func settleTransition() {
        transition &+= 1
        for view in [modal, backdrop, root, transitionImage] { view.layer?.removeAllAnimations() }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        modal.layer?.transform = CATransform3DIdentity; modal.layer?.shadowOpacity = 1
        backdrop.layer?.opacity = 1; root.layer?.opacity = 1; transitionImage.layer?.opacity = 0
        CATransaction.commit()
    }
    private func dismiss() {
        guard !finished, !closing, outputSheet == nil else { return }
        guard valid(), !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion, let source = localSourceRect(), let layer = modal.layer else { close(); return }
        closing = true; transition &+= 1; let token = transition
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in MainActor.assumeIsolated {
            guard let self, self.transition == token else { return }; self.close()
        } }
        let animation = DownloadPreviewGeometry.spring(keyPath: "transform", ratio: 0.95, response: 0.15)
        animation.fromValue = NSValue(caTransform3D: layer.presentation()?.transform ?? layer.transform)
        animation.toValue = NSValue(caTransform3D: DownloadPreviewGeometry.transform(from: modal.frame, to: source))
        animation.fillMode = .forwards; animation.isRemovedOnCompletion = false
        layer.add(animation, forKey: "transform")
        crossfade(opening: false)
        animate(layer, key: "shadowOpacity", from: layer.presentation()?.shadowOpacity ?? layer.shadowOpacity, to: 0, opening: false)
        animate(backdrop.layer, key: "opacity", from: backdrop.layer?.presentation()?.opacity ?? 1, to: 0, opening: false)
        CATransaction.setDisableActions(true); layer.shadowOpacity = 0; backdrop.layer?.opacity = 0
        CATransaction.commit()
    }
    func close() {
        guard !finished else { return }; finished = true; closing = true; generation &+= 1; settleTransition()
        if let outputSheet, panel.attachedSheet === outputSheet { panel.endSheet(outputSheet, returnCode: .cancel) }
        outputSheet = nil
        sharingFocusReturn?.cancel(); sharingFocusReturn = nil
        sharing?.detach(); sharing = nil
        parent?.removeChildWindow(panel)
        panel.orderOut(nil); data = nil; image.image = nil; transitionImage.image = nil; sourceImage = nil
        removalObservers.forEach { NotificationCenter.default.removeObserver($0) }; removalObservers = []
        if let motionObserver { NSWorkspace.shared.notificationCenter.removeObserver(motionObserver) }; motionObserver = nil
        let callback = onClose; onClose = nil; sourceRect = nil
        callback?()
    }
    func reconcile() {
        guard !finished else { return }
        guard valid(), store.contains(selected) else { close(); return }
        updateButtons()
    }
    private func move(_ offset: Int) {
        guard !closing, outputSheet == nil, valid(), navigation.neighbor(offset) != nil else { return }
        onMove?(offset)
    }
    private func loadSelected() {
        generation &+= 1; let token = generation; let item = selected
        data = nil; image.image = nil; status.stringValue = "Loading capture…"; status.isHidden = false
        title.stringValue = "\(item.title.isEmpty ? "Capture" : item.title) · \(item.createdAt.formatted(date: .abbreviated, time: .shortened))"
        updateButtons()
        Task { [weak self] in
            guard let self else { return }
            do {
                let bytes = try await self.store.preview(for: item)
                guard !self.finished, self.generation == token, self.valid(), self.store.contains(item) else { return }
                guard let image = NSImage(data: bytes.display) else { throw CocoaError(.fileReadCorruptFile) }
                self.data = bytes.original; self.image.image = image; self.status.isHidden = true
            } catch {
                guard !self.finished, self.generation == token else { return }
                self.status.stringValue = error.localizedDescription
            }
            self.updateButtons()
        }
    }
    func setNavigation(_ navigation: MediaLibraryNavigation) { self.navigation = navigation; updateButtons() }
    private func updateButtons() {
        back.isEnabled = navigation.neighbor(-1) != nil
        forward.isEnabled = navigation.neighbor(1) != nil
        export.isEnabled = data != nil; more.isEnabled = true
    }
    func copyImage() {
        guard !finished, !closing, valid(), store.contains(selected), let data else { return }
        NSPasteboard.general.clearContents()
        if NSPasteboard.general.setData(data, forType: .png) { onToast?(.copiedFile([])) }
        else { showError("The capture could not be copied. Try again.") }
    }
    private func saveImage() {
        guard !finished, !closing, valid(), store.contains(selected), let data, outputSheet == nil else { return }
        let item = selected
        let save = NSSavePanel(); save.allowedContentTypes = [.png]; save.canCreateDirectories = true
        save.nameFieldStringValue = (item.title.isEmpty ? "Capture" : String(item.title.components(separatedBy: CharacterSet(charactersIn: "/:\n\r")).joined(separator: " ").prefix(100))) + ".png"
        outputSheet = save
        save.beginSheetModal(for: panel) { [weak self, weak save] response in
            MainActor.assumeIsolated {
                guard let self, !self.finished, self.outputSheet === save else { return }
                self.outputSheet = nil
                guard self.valid(), self.store.contains(item), self.selected == item, response == .OK, let url = save?.url else { return }
                Task { [weak self] in
                    do { try await CaptureLibraryStore.export(data, to: url) }
                    catch { self?.showError(error.localizedDescription) }
                }
            }
        }
    }
    func deleteImage() {
        guard !finished, !closing, valid(), store.contains(selected), outputSheet == nil,
              panel.attachedSheet == nil else { return }
        let item = selected
        var content = PArcDialog.Content(title: [("Delete this capture?", false)],
            message: [("The saved image will be permanently removed from your Library. Exported files and copies in Easels are kept.", false)],
            confirm: "Delete", cancel: "Cancel")
        content.destructive = true
        let dialog = PArcDialog(content)
        let alertWindow: NSWindow = dialog.panel
        outputSheet = alertWindow
        _ = dialog.begin(for: panel) { [weak self, weak alertWindow] response in
            MainActor.assumeIsolated {
                guard let self, !self.finished, self.outputSheet === alertWindow else { return }
                self.outputSheet = nil
                guard response == .confirm, !self.closing, self.valid(), self.selected == item,
                      let reservation = self.store.reserveDeletion(owner: self.profileOwner, item: item) else { return }
                let library = self.store
                Task { [weak self] in
                    do { try await reservation.perform { try await library.delete(item) }; self?.close() }
                    catch { self?.showError(error.localizedDescription) }
                }
            }
        }
    }
    private func share(to destination: CaptureLibrarySharePayload.Destination) {
        guard !finished, !closing, valid(), store.contains(selected), outputSheet == nil, sharing == nil, let data,
              let payload = CaptureLibrarySharePayload(png: data, sourceAddress: selected.sourceURL, destination: destination),
              let owner = CaptureLibrarySharing(payload: payload, parent: panel, source: image, completion: { [weak self] error in
                  guard let self, !self.finished else { return }; self.sharing = nil
                  guard self.valid(), self.store.contains(self.selected) else { self.close(); return }
                  if let error, !CaptureLibrarySharing.isCancellation(error) { self.showError(error.localizedDescription) }
                  self.sharingFocusReturn?.restore()
              }) else { return }
        sharingFocusReturn?.cancel()
        sharingFocusReturn = CaptureFocusReturn(window: panel, target: more, valid: { [weak self] in
            guard let self else { return false }
            return !self.finished && !self.closing && self.valid() && self.store.contains(self.selected)
        })
        sharing = owner; owner.present()
    }
    private func showMore() {
        guard valid(), !finished, !closing else { return }
        let item = selected
        let menu = NSMenu(); menu.autoenablesItems = false
        for destination in CaptureLibrarySharePayload.Destination.allCases {
            let row = MenuAction.item(destination.title) { [weak self] in self?.share(to: destination) }
            row.isEnabled = sharing == nil && outputSheet == nil && data.flatMap { CaptureLibrarySharePayload(png: $0, sourceAddress: item.sourceURL, destination: destination) }?.isAvailable == true
            menu.addItem(row)
        }
        let copy = MenuAction.item("Copy Image") { [weak self] in self?.copyImage() }; copy.isEnabled = data != nil; menu.addItem(copy)
        if let url = URL(string: item.sourceURL), ["https", "http"].contains(url.scheme?.lowercased() ?? "") {
            menu.addItem(MenuAction.item("Open Source Page") { [weak self] in
                guard let self, !self.finished, self.valid(), self.store.contains(item), self.selected == item else { return }
                self.close(); self.onOpenSource?(item.sourceURL)
            })
            menu.addItem(MenuAction.item("Copy Source Address") { [weak self] in
                guard let self, !self.finished, self.valid(), self.store.contains(item), self.selected == item else { return }
                NSPasteboard.general.clearContents()
                if NSPasteboard.general.setString(item.sourceURL, forType: .string) { self.onToast?(.copiedCurrentURL(URL(string: item.sourceURL))) }
                else { self.showError("The source address could not be copied.") }
            })
        }
        menu.addItem(.separator()); menu.addItem(MenuAction.item("Delete…") { [weak self] in self?.deleteImage() })
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: more.bounds.maxY), in: more)
    }
    private func showError(_ message: String) { guard !finished else { return }; status.stringValue = message; status.isHidden = false; CaptureMotion.announce(message, from: status) }
}

@MainActor
private final class CapturePreviewPanel: NSPanel {
    var onCancel: (() -> Void)?; var onMove: ((Int) -> Void)?; var onCopy: (() -> Void)?; var onDelete: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { onCancel?() }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.intersection([.command, .option, .control, .shift]) == .command,
           event.charactersIgnoringModifiers == "w" { onCancel?(); return true }
        return super.performKeyEquivalent(with: event)
    }
    @objc func copy(_ sender: Any?) { onCopy?() }
    override func keyDown(with event: NSEvent) {
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        if modifiers == .command, event.charactersIgnoringModifiers == "c" { onCopy?(); return }
        guard modifiers.isEmpty else { super.keyDown(with: event); return }
        switch event.keyCode { case 49, 53: onCancel?(); case 123: onMove?(-1); case 124: onMove?(1); case 51, 117: onDelete?(); default: super.keyDown(with: event) }
    }
}

@MainActor private final class CapturePreviewBackdrop: LayoutView {
    var onDismiss: (() -> Void)?
    override func mouseDown(with event: NSEvent) { onDismiss?() }
}
@MainActor private final class CapturePreviewTransitionImage: NSImageView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

@MainActor private final class CapturePreviewModal: LayoutView {
    var onAppearance: (() -> Void)?
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); onAppearance?() }
    override func mouseDown(with event: NSEvent) {}
}
