import AppKit
import UniformTypeIdentifiers
import Combine
import QuartzCore

@MainActor
final class DownloadLibraryView: NSView, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate {
    private enum Row: Equatable { case heading(String), item(BrowserDownload) }
    private let store: BrowserStore
    private let ownerValid: () -> Bool
    var onClose: (() -> Void)?
    var onToast: ((PArcToastContent) -> Void)?
    var onAction: ((BrowserDownload, DownloadLibraryAction) -> Bool)?
    var fileURL: ((BrowserDownload) -> URL?)?
    var onLoad: (() -> Void)?
    private var fileDrags: [DownloadFileDrag] = []
    private var contextGeneration: UInt64 = 0
    private var renderedContextGeneration: UInt64?
    private let thumbnails = DownloadThumbnailProvider()
    private var actionMessage: String?
    private var operations: [DownloadLibraryIdentity: String] = [:]
    private var loadingCount = 0
    private var loadMessage: String?
    var palette: ThemeChromePalette? { didSet { applyPalette() } }
    private let searchBackdrop = DownloadSearchBackdrop()
    private let search = DownloadSearchField(frame: .zero)
    private let filter = DownloadFilterButton("Filter", symbol: "line.3.horizontal.decrease.circle", style: .header)
    private let filterTitle = NSTextField(labelWithString: "Filter Downloads…")
    private let selectedFilter = DownloadFilterButton("")
    private var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    private var filterAnimationGeneration: UInt64 = 0
    private var animatingFilterLayout = false
    private var savedSearchSelection: NSRange?
    private let filterContent = LayoutView()
    private let filterScroll = NSScrollView()
    private let scroll = NSScrollView()
    private let table = DownloadLibraryTable()
    private let emptyContent: DownloadEmptyContentView
    private let emptyIcon = NSImageView(image: NSImage(systemSymbolName: "arrow.down.circle", accessibilityDescription: nil)!)
    private let empty = NSTextField(wrappingLabelWithString: "")
    private let footer = NSTextField(labelWithString: "")
    private let retryLoad = ActionButton("Retry", symbol: "arrow.clockwise")
    private var rows: [Row] = []
    private var displayed: [BrowserDownload] = []
    private var restoringSelection = false
    private var selectedProfile: UUID?
    private var filtersExpanded = false
    private var filterSignature: [String] = []
    private var filterControls: [NSView] = []
    private var subscription: AnyCancellable?
    private var transientSubscription: AnyCancellable?
    private var observedDownloads: [BrowserDownload] = []
    private var observedTransient: [BrowserDownload] = []
    private var observedProfiles: [BrowserProfile] = []
    private var preview: DownloadLibraryPreview?
    private var previewItem: BrowserDownload?
    private var previewURL: URL?
    private var activationGeneration: UInt64 = 0
    override var isFlipped: Bool { true }

    init(store: BrowserStore, ownerValid: @escaping () -> Bool) {
        self.store = store; self.ownerValid = ownerValid
        emptyContent = DownloadEmptyContentView(ownerValid: ownerValid)
        super.init(frame: .zero)
        setAccessibilityRole(.group); setAccessibilityLabel("Downloads")
        for view in [searchBackdrop, filterTitle, filter, selectedFilter, filterScroll, scroll, emptyContent, footer, retryLoad] {
            view.wantsLayer = true; addSubview(view)
        }
        filterTitle.font = .systemFont(ofSize: 15, weight: .bold)
        filterTitle.lineBreakMode = .byTruncatingTail
        filterTitle.isHidden = true; selectedFilter.isHidden = true
        selectedFilter.symbol = "xmark.circle.fill"
        selectedFilter.actionBlock = { [weak self] in self?.selectProfile(nil) }
        retryLoad.actionBlock = { [weak self] in self?.onLoad?() }; retryLoad.isHidden = true
        searchBackdrop.addSubview(search)
        search.wantsLayer = true
        search.placeholderString = "Search Downloads…"; search.setAccessibilityLabel("Search Downloads")
        search.delegate = self
        searchBackdrop.onFocus = { [weak self] in
            guard let self, self.ownerValid(), !self.filtersExpanded,
                  !self.searchBackdrop.isHiddenOrHasHiddenAncestor,
                  let window = self.window, window.attachedSheet == nil else { return }
            if self.search.currentEditor() !== window.firstResponder { window.makeFirstResponder(self.search) }
        }
        searchBackdrop.setAccessibilityElement(false)
        filter.actionBlock = { [weak self] in
            guard let self else { return }
            self.setFiltersExpanded(!self.filtersExpanded)
        }
        filterScroll.documentView = filterContent; filterScroll.drawsBackground = false
        filterScroll.hasVerticalScroller = true; filterScroll.autohidesScrollers = true
        let column = NSTableColumn(identifier: .init("download")); column.resizingMask = .autoresizingMask
        table.addTableColumn(column); table.headerView = nil; table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        table.style = .plain; table.backgroundColor = .clear; table.intercellSpacing = .zero
        table.allowsMultipleSelection = false; table.allowsEmptySelection = true
        table.delegate = self; table.dataSource = self
        table.target = table; table.action = #selector(DownloadLibraryTable.activateOriginalClick)
        table.prepareClick = { [weak self] row in self?.prepareActivation(at: row) }
        table.setAccessibilityLabel("Downloads")
        table.setDraggingSourceOperationMask(.copy, forLocal: false)
        table.setDraggingSourceOperationMask(.copy, forLocal: true)
        table.canDrag = { [weak self] indices in
            guard let self, indices.count == 1, let row = indices.first else { return false }
            return self.dragItem(at: row) != nil
        }
        table.onMove = { [weak self] forward in self?.moveSelection(forward: forward) }
        table.canCopy = { [weak self] in self?.resolvedItems(for: .copyFile) != nil }
        table.onConfirmSelection = { [weak self] in self?.confirmSelection() }
        table.onPreview = { [weak self] in self?.togglePreview() }
        table.onClose = { [weak self] in self?.escape() }
        table.onSearch = { [weak self] in self?.focusSearch() }
        table.onCopy = { [weak self] in self?.act(.copyFile) }
        table.onDelete = { [weak self] in self?.act(.remove) }
        table.makeMenu = { [weak self] in self?.selectionMenu() }
        scroll.documentView = table; scroll.drawsBackground = false
        scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true
        emptyContent.addSubview(emptyIcon); emptyContent.addSubview(empty)
        empty.alignment = .center; empty.font = .systemFont(ofSize: 13)
        footer.font = .systemFont(ofSize: 10.5); footer.lineBreakMode = .byTruncatingTail
        footer.isHidden = true
        subscription = store.statePublisher.receive(on: RunLoop.main).sink { [weak self] _ in self?.reload() }
        transientSubscription = store.$transientDownloads.receive(on: RunLoop.main).sink { [weak self] _ in self?.reload() }
        reload(force: true); rebuildFilters(); applyPalette()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    func invalidate(settlePresentation: Bool = true) {
        contextGeneration &+= 1
        activationGeneration &+= 1; table.retireOriginalClick()
        emptyContent.settle()
        if settlePresentation { settleFilterAnimation() } else { filterAnimationGeneration &+= 1 }
        retireFileDrags()
        closePreview()
        thumbnails.invalidate()
        table.enumerateAvailableRowViews { row, _ in
            (row.view(atColumn: 0) as? DownloadLibraryCell)?.retirePresentation()
        }
    }
    private func retireFileDrags() {
        fileDrags.forEach { $0.invalidate() }; fileDrags.removeAll()
    }
    private func dragItem(at row: Int) -> BrowserDownload? {
        guard ownerValid(), window?.attachedSheet == nil, rows.indices.contains(row),
              table.selectedRowIndexes == IndexSet(integer: row),
              case let .item(original) = rows[row],
              let current = resolve([original])?.first, current.status == .completed,
              current.canCopyFile, operations[DownloadLibraryIdentity(current)] == nil else { return nil }
        return current
    }
    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
        guard tableView === table, let original = dragItem(at: row), let parent = window else { return nil }
        let generation = contextGeneration, identity = DownloadLibraryIdentity(original)
        guard let drag = DownloadFileDrag(resolve: { [weak self, weak parent] in
            guard let self, let parent, self.window === parent, self.contextGeneration == generation,
                  self.ownerValid(), parent.attachedSheet == nil,
                  self.selectedItems.map(DownloadLibraryIdentity.init) == [identity],
                  let item = self.resolve([original])?.first, item.status == .completed,
                  item.canCopyFile, self.operations[identity] == nil else { return nil }
            return self.fileURL?(item)
        }) else { return nil }
        fileDrags.append(drag); return drag.item
    }
    func tableView(_ tableView: NSTableView, draggingSession session: NSDraggingSession,
                   willBeginAt screenPoint: NSPoint, forRowIndexes rowIndexes: IndexSet) {
        table.retireOriginalClick(); activationGeneration &+= 1
    }
    func tableView(_ tableView: NSTableView, draggingSession session: NSDraggingSession,
                   endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        retireFileDrags()
    }
    private func closePreview(restoringFocus: Bool = false) {
        let controller = preview
        let ownedFocus = controller?.window?.isKeyWindow == true
        preview = nil; previewItem = nil; previewURL = nil
        controller?.onClosed = nil; controller?.close()
        if restoringFocus && ownedFocus && ownerValid(), let window, window.attachedSheet == nil {
            window.makeKey(); window.makeFirstResponder(table)
        }
    }
    func setOperation(_ item: BrowserDownload, message: String?) {
        let identity = DownloadLibraryIdentity(item)
        operations[identity] = message
        if message != nil { activationGeneration &+= 1 }
        if message != nil, previewItem.map(DownloadLibraryIdentity.init) == identity { closePreview(restoringFocus: true) }
        if let row = rowItems.firstIndex(where: { $0.map(DownloadLibraryIdentity.init) == identity }) {
            refreshCells(at: IndexSet(integer: row))
        }
    }
    func setLoading(count: Int, message: String?) {
        loadingCount = count; loadMessage = message; reload(force: true)
    }
    override func setFrameSize(_ newSize: NSSize) {
        if newSize != frame.size { settleFilterAnimation() }
        super.setFrameSize(newSize)
    }
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil { invalidate() }
        super.viewWillMove(toWindow: newWindow)
    }
    func focusSearch() {
        guard ownerValid(), window?.attachedSheet == nil else { return }
        setFiltersExpanded(false, animated: false)
        window?.makeFirstResponder(search); search.selectText(nil)
    }
    override func cancelOperation(_ sender: Any?) { escape() }
    func controlTextDidChange(_ obj: Notification) { actionMessage = nil; invalidate(); reload(force: true) }
    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        guard !textView.hasMarkedText() else { return false }
        if selector == #selector(NSResponder.cancelOperation(_:)) { escape(); return true }
        if selector == #selector(NSResponder.moveDown(_:)) || selector == #selector(NSResponder.insertNewline(_:)) {
            if confirmSelection() { window?.makeFirstResponder(table) }
            return true
        }
        return false
    }
    private func escape() {
        if preview?.window?.isVisible == true { closePreview(restoringFocus: true); window?.makeFirstResponder(table) }
        else if filtersExpanded { setFiltersExpanded(false) }
        else if !search.stringValue.isEmpty { invalidate(); search.stringValue = ""; reload(force: true) }
        else { onClose?() }
    }
    private var selectedItems: [BrowserDownload] {
        table.selectedRowIndexes.compactMap { index in
            guard rows.indices.contains(index), case let .item(item) = rows[index] else { return nil }; return item
        }
    }
    private func reload(force: Bool = false) {
        if !force && shouldSkipCatalogReload() { return }
        rememberAppliedCatalog()
        if let selectedProfile, !store.state.profiles.contains(where: { $0.id == selectedProfile }) {
            invalidate(); self.selectedProfile = nil
        }
        let liveIdentities = Set(store.downloadItems.map(DownloadLibraryIdentity.init))
        operations = operations.filter { liveIdentities.contains($0.key) }
        if let item = previewItem, !ownerValid() || resolve([item]) == nil || fileURL?(item) != previewURL { closePreview() }
        let query = search.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let next = store.downloadItems.filter { item in
            (selectedProfile == nil || item.profileID == selectedProfile) &&
            (query.isEmpty || item.name.localizedCaseInsensitiveContains(query) ||
             (item.sourceURL?.localizedCaseInsensitiveContains(query) ?? false))
        }.sorted {
            ($0.startedAt ?? .distantPast) > ($1.startedAt ?? .distantPast)
        }
        rebuildFilters()
        guard force || next != displayed else { return }
        let originals = selectedItems, origin = scroll.contentView.bounds.origin
        let previousRows = rows
        displayed = next; rows = []
        var previous: String?
        let now = Date()
        for item in next {
            let heading = item.startedAt.map { DownloadSectionHeading.title(for: $0, now: now) } ?? DownloadSectionHeading.undatedTitle
            if previous != heading { rows.append(.heading(heading)); previous = heading }
            rows.append(.item(item))
        }
        let sameLayout = renderedContextGeneration == contextGeneration && previousRows.count == rows.count && zip(previousRows, rows).allSatisfy { before, after in
            switch (before, after) {
            case let (.heading(a), .heading(b)): return a == b
            case let (.item(a), .item(b)): return DownloadLibraryIdentity(a) == DownloadLibraryIdentity(b)
            default: return false
            }
        }
        renderedContextGeneration = contextGeneration
        if sameLayout {
            let changed = IndexSet(rows.indices.filter { previousRows[$0] != rows[$0] })
            restoringSelection = true
            refreshCells(at: changed)
            restoringSelection = false
            if preview?.window?.isVisible == true { updatePreview() }
        } else { reloadRows(selecting: DownloadLibrarySelection.retainedRows(originals, in: rowItems)) }
        scroll.contentView.scroll(to: origin); scroll.reflectScrolledClipView(scroll.contentView)
        let isUnfilteredEmpty = query.isEmpty && selectedProfile == nil
        let message = loadingCount > 0 && next.isEmpty ? "Loading downloads…" : loadMessage != nil && next.isEmpty ? loadMessage! : isUnfilteredEmpty ? "Nothing here yet!\nCome back after you’ve found some cool stuff to save." : "No downloads match this search."
        let paragraph = NSMutableParagraphStyle(); paragraph.alignment = .center; paragraph.paragraphSpacing = 6
        let attributed = NSMutableAttributedString(string: message, attributes: [.font: NSFont.systemFont(ofSize: 13), .paragraphStyle: paragraph,
            .foregroundColor: palette?.foregroundSecondary ?? NSColor.secondaryLabelColor])
        if isUnfilteredEmpty && loadingCount == 0 && loadMessage == nil {
            attributed.addAttributes([.font: NSFont.systemFont(ofSize: 14, weight: .semibold),
                .foregroundColor: palette?.foregroundPrimary ?? NSColor.labelColor], range: NSRange(location: 0, length: "Nothing here yet!".utf16.count))
        }
        empty.attributedStringValue = attributed
        emptyContent.show(!next.isEmpty ? .hidden : loadingCount > 0 || loadMessage != nil ? .status : .empty)
        let status = actionMessage ?? (loadingCount > 0 ? "Loading downloads…" : loadMessage)
        footer.stringValue = status ?? ""
        footer.toolTip = status
        footer.isHidden = status == nil
        retryLoad.isHidden = loadMessage == nil || loadingCount > 0
        needsLayout = true
    }

    private func shouldSkipCatalogReload() -> Bool {
        store.state.downloads == observedDownloads
            && store.transientDownloads == observedTransient
            && store.state.profiles == observedProfiles
    }

    private func rememberAppliedCatalog() {
        observedDownloads = store.state.downloads
        observedTransient = store.transientDownloads
        observedProfiles = store.state.profiles
    }

    private func selectProfile(_ id: UUID?) {
        guard ownerValid(), let window, window.attachedSheet == nil,
              id == nil || store.state.profiles.contains(where: { $0.id == id }) else { return }
        invalidate()
        selectedProfile = selectedProfile == id ? nil : id
        reload(force: true)
        onLoad?()
    }
    private func setFiltersExpanded(_ expanded: Bool, animated: Bool = true) {
        guard ownerValid(), let window, window.attachedSheet == nil, expanded != filtersExpanded else { return }
        if expanded, let editor = search.currentEditor() as? NSTextView,
           window.firstResponder === editor {
            guard !editor.hasMarkedText() else { return }
            savedSearchSelection = editor.selectedRange()
            guard window.makeFirstResponder(filter) else { savedSearchSelection = nil; return }
        }
        let focusWasInFilters = (window.firstResponder as? NSView)?.isDescendant(of: filterContent) == true
        let restoreSearch = !expanded && savedSearchSelection != nil &&
            (window.firstResponder === filter || focusWasInFilters)
        Self.prepareFilterLayoutFlushIfNeeded(for: self)
        invalidate(settlePresentation: false)
        filtersExpanded = expanded
        reload(force: true)
        let token = filterAnimationGeneration
        let duration = animated && !reduceMotion ? 0.3 : 0
        searchBackdrop.isHidden = false; search.isHidden = false; filterTitle.isHidden = false
        filterScroll.isHidden = false; selectedFilter.isHidden = selectedProfile == nil
        search.isEnabled = !expanded
        search.setAccessibilityHidden(expanded); filterTitle.setAccessibilityHidden(!expanded)
        filterScroll.setAccessibilityHidden(!expanded); selectedFilter.setAccessibilityHidden(expanded || selectedProfile == nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.25, 0.1, 0.25, 1)
            context.allowsImplicitAnimation = duration > 0
            animatingFilterLayout = duration > 0
            searchBackdrop.animator().alphaValue = expanded ? 0 : 1
            filterTitle.animator().alphaValue = expanded ? 1 : 0
            filterScroll.animator().alphaValue = expanded ? 1 : 0
            selectedFilter.animator().alphaValue = expanded ? 0 : 1
            needsLayout = true; layoutSubtreeIfNeeded()
            animatingFilterLayout = false
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.filterAnimationGeneration == token else { return }
                self.settleFilterAnimation()
            }
        }
        if duration == 0 { settleFilterAnimation() }
        if restoreSearch, let range = savedSearchSelection {
            window.makeFirstResponder(search)
            let length = search.stringValue.utf16.count
            let location = min(range.location, length)
            (search.currentEditor() as? NSTextView)?.setSelectedRange(NSRange(location: location, length: min(range.length, length - location)))
        }
        if !expanded {
            if !restoreSearch && focusWasInFilters { window.makeFirstResponder(filter) }
            savedSearchSelection = nil
        }
    }

    static func shouldPrepareFilterLayoutFlush(of root: NSView) -> Bool {
        subtreeNeedsLayout(root) || subtreeHasUncommittedGeometry(root)
    }

    @discardableResult
    static func prepareFilterLayoutFlushIfNeeded(for root: NSView) -> Bool {
        guard shouldPrepareFilterLayoutFlush(of: root) else { return false }
        if subtreeNeedsLayout(root) {
            root.layoutSubtreeIfNeeded()
        }
        CATransaction.flush()
        return true
    }

    private static func subtreeNeedsLayout(_ root: NSView) -> Bool {
        if root.needsLayout || root.needsUpdateConstraints { return true }
        for child in root.subviews where subtreeNeedsLayout(child) { return true }
        return false
    }

    private static func subtreeHasUncommittedGeometry(_ root: NSView) -> Bool {
        if let layer = root.layer, let presentation = layer.presentation(),
           presentation.position != layer.position
            || presentation.bounds != layer.bounds
            || presentation.cornerRadius != layer.cornerRadius {
            return true
        }
        for child in root.subviews where subtreeHasUncommittedGeometry(child) { return true }
        return false
    }

    private func settleFilterAnimation() {
        filterAnimationGeneration &+= 1
        for view in [searchBackdrop, search, filterTitle, filterScroll, selectedFilter, scroll, emptyContent] {
            for key in ["position", "bounds", "opacity"] { view.layer?.removeAnimation(forKey: key) }
        }
        searchBackdrop.alphaValue = filtersExpanded ? 0 : 1; searchBackdrop.isHidden = filtersExpanded
        search.alphaValue = 1; search.isHidden = filtersExpanded
        filterTitle.alphaValue = filtersExpanded ? 1 : 0; filterTitle.isHidden = !filtersExpanded
        filterScroll.alphaValue = filtersExpanded ? 1 : 0; filterScroll.isHidden = !filtersExpanded
        selectedFilter.alphaValue = filtersExpanded ? 0 : 1
        selectedFilter.isHidden = filtersExpanded || selectedProfile == nil
        search.isEnabled = !filtersExpanded
        search.setAccessibilityHidden(filtersExpanded); filterTitle.setAccessibilityHidden(!filtersExpanded)
        filterScroll.setAccessibilityHidden(!filtersExpanded); selectedFilter.setAccessibilityHidden(selectedFilter.isHidden)
    }
    private func rebuildFilters(force: Bool = false) {
        let signature = [selectedProfile?.uuidString ?? "all", String(filtersExpanded)] + store.state.profiles.map { $0.id.uuidString + $0.name }
        guard force || signature != filterSignature else { return }
        filterSignature = signature
        let oldFocusedProfile = (window?.firstResponder as? DownloadFilterButton)?.profileID
        for view in filterControls { view.removeFromSuperview() }; filterControls = []
        filter.title = filtersExpanded ? "Done" : "Filter"
        filter.setAccessibilityLabel(filter.title)
        filter.symbol = filtersExpanded ? nil : "line.3.horizontal.decrease.circle"
        let name = selectedProfile.flatMap { id in store.state.profiles.first { $0.id == id }?.name }
        selectedFilter.title = name ?? ""
        selectedFilter.setAccessibilityLabel("Remove \(name ?? "Profile") Filter")
        LiveShortcutToolTip.set(selectedFilter, "Remove \(name ?? "Profile") Filter", behavior: .onMouseIdle(delay: 0.6))
        search.placeholderString = selectedProfile == nil ? "Search Downloads…" : "Search…"
        let label = NSTextField(labelWithString: "Profiles"); label.font = .systemFont(ofSize: 12, weight: .semibold)
        label.textColor = palette?.foregroundSecondary ?? .secondaryLabelColor
        filterControls.append(label)
        for profile in store.state.profiles {
            let id = profile.id
            let button = DownloadFilterButton(profile.name) { [weak self] in self?.selectProfile(id) }
            button.profileID = id; button.isChosen = selectedProfile == id
            button.ink = palette?.foregroundPrimary ?? .labelColor
            button.state = button.isChosen ? .on : .off
            button.setAccessibilityValue(NSNumber(value: button.isChosen))
            filterControls.append(button)
        }
        for view in filterControls { filterContent.addSubview(view) }
        if let oldFocusedProfile, let button = filterControls.compactMap({ $0 as? DownloadFilterButton }).first(where: { $0.profileID == oldFocusedProfile }) {
            window?.makeFirstResponder(button)
        }
        if !animatingFilterLayout {
            selectedFilter.isHidden = filtersExpanded || selectedProfile == nil
            filterScroll.isHidden = !filtersExpanded
        }
        needsLayout = true
    }
    private var rowItems: [BrowserDownload?] {
        rows.map { if case let .item(item) = $0 { return item }; return nil }
    }
    private var selectableRows: IndexSet { IndexSet(rows.indices.filter { if case .item = rows[$0] { return true }; return false }) }
    private func moveSelection(forward: Bool) {
        guard ownerValid(), let index = DownloadLibrarySelection.nextRow(in: selectableRows,
            selected: table.selectedRowIndexes, forward: forward) else { return }
        table.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
        table.scrollRowToVisible(index)
    }
    func tableView(_ tableView: NSTableView, selectionIndexesForProposedSelection proposed: IndexSet) -> IndexSet {
        proposed.intersection(selectableRows)
    }
    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }
    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        guard rows.indices.contains(row), case .item = rows[row] else { return false }; return true
    }
    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        if case .heading = rows[row] { return DownloadSectionHeading.height }; return 56
    }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        switch rows[row] {
        case let .heading(title):
            return DownloadSectionHeading(title)
        case let .item(item):
            let cell = DownloadLibraryCell(item: item, palette: palette, operation: operations[DownloadLibraryIdentity(item)])
            configure(cell, item: item)
            return cell
        }
    }
    private func refreshCells(at indices: IndexSet) {
        var reload = IndexSet()
        for index in indices {
            guard case let .item(item) = rows[index],
                  let cell = table.view(atColumn: 0, row: index, makeIfNecessary: false) as? DownloadLibraryCell,
                  cell.identity == DownloadLibraryIdentity(item) else { reload.insert(index); continue }
            cell.update(item: item, palette: palette, operation: operations[cell.identity])
            configure(cell, item: item)
        }
        if !reload.isEmpty { table.reloadData(forRowIndexes: reload, columnIndexes: IndexSet(integer: 0)) }
    }
    private func configure(_ cell: DownloadLibraryCell, item: BrowserDownload) {
        cell.cancelThumbnail?(cell.thumbnailToken); cell.thumbnailToken = nil
        let generation = contextGeneration
        cell.configureThumbnail = { [weak self, weak cell] in
            guard let self, let cell, self.contextGeneration == generation, self.ownerValid(),
                  let current = self.resolve([item])?.first, current.canCopyFile, let url = self.fileURL?(current) else { return }
            let key = DownloadThumbnailProvider.Key(item: DownloadLibraryIdentity(current), url: url, bytes: current.receivedBytes)
            cell.thumbnailToken = self.thumbnails.request(key, valid: { [weak self, weak cell] in
                guard let self, let cell, cell.window === self.window, cell.window != nil,
                  self.contextGeneration == generation, self.ownerValid(),
                  let live = self.resolve([item])?.first else { return false }
                return key.admits(live, url: self.fileURL?(live))
            }, completion: { [weak cell] image in cell?.setThumbnail(image) })
        }
        cell.cancelThumbnail = { [weak self] token in self?.thumbnails.cancel(token) }
        cell.makeMenu = { [weak self] in
            guard let self, self.contextGeneration == generation,
                  let row = self.rowItems.firstIndex(where: { $0.map(DownloadLibraryIdentity.init) == DownloadLibraryIdentity(item) }) else { return nil }
            if !self.table.selectedRowIndexes.contains(row) { self.table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false) }
            return self.selectionMenu()
        }
        if cell.window != nil { cell.configureThumbnail?() }
    }
    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        guard rows.indices.contains(row), case .item = rows[row] else { return nil }
        return DownloadLibraryRow()
    }
    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !restoringSelection else { return }
        activationGeneration &+= 1
        retireFileDrags()
        if preview?.window?.isVisible == true { updatePreview() }
    }
    @discardableResult private func confirmSelection() -> Bool {
        guard ownerValid(), let window, window.attachedSheet == nil,
              let row = table.selectedRowIndexes.intersection(selectableRows).first ?? selectableRows.first else { return false }
        table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        table.scrollRowToVisible(row)
        return true
    }
    private func prepareActivation(at row: Int) -> (() -> Void)? {
        activationGeneration &+= 1
        guard ownerValid(), !isHiddenOrHasHiddenAncestor, let parent = window,
              parent.attachedSheet == nil, rows.indices.contains(row),
              case let .item(original) = rows[row], resolve([original]) != nil else { return nil }
        let generation = contextGeneration, identity = DownloadLibraryIdentity(original)
        return { [weak self, weak parent] in
            guard let self, let parent, self.window === parent, parent.attachedSheet == nil,
                  self.contextGeneration == generation, self.ownerValid(), !self.isHiddenOrHasHiddenAncestor,
                  self.selectedItems.map(DownloadLibraryIdentity.init) == [identity],
                  let current = self.resolve([original])?.first,
                  self.operations[identity] == nil else { return }
            self.activate(current, in: parent)
        }
    }
    private func activate(_ original: BrowserDownload, in parent: NSWindow) {
        activationGeneration &+= 1
        let token = activationGeneration, generation = contextGeneration
        let identity = DownloadLibraryIdentity(original)
        let responder = parent.firstResponder, wasKey = parent.isKeyWindow
        guard original.status == .completed else {
            if original.canToggleOpen { act(.toggleOpen, items: [original]) }
            return
        }
        guard let url = fileURL?(original) else {
            reportActionFailure("This file is no longer available."); return
        }
        DispatchQueue.global(qos: .userInitiated).async { [weak self, weak parent, weak responder] in
            let route = DownloadFileActivation.inspect(url)
            DispatchQueue.main.async { [weak self, weak parent, weak responder] in
                guard let self, let parent, self.window === parent, parent.attachedSheet == nil,
                      parent.firstResponder === responder, parent.isKeyWindow == wasKey,
                      self.activationGeneration == token, self.contextGeneration == generation,
                      self.ownerValid(), !self.isHiddenOrHasHiddenAncestor,
                      self.selectedItems.map(DownloadLibraryIdentity.init) == [identity],
                      let current = self.resolve([original])?.first,
                      self.operations[identity] == nil, self.fileURL?(current) == url else { return }
                switch route {
                case .preview: self.updatePreview()
                case .open: self.act(.open, items: [current])
                case .unavailable: self.reportActionFailure("This file is no longer available to preview.")
                }
            }
        }
    }
    private func act(_ action: DownloadLibraryAction, items: [BrowserDownload]? = nil) {
        activationGeneration &+= 1
        guard ownerValid(), let ownerWindow = window, ownerWindow.attachedSheet == nil,
              let originals = resolvedItems(for: action, items: items) else { reportActionFailure("This download is no longer available for that action."); return }
        actionMessage = nil
        reload(force: true)
        if action == .copyFile {
            let urls = originals.compactMap { fileURL?($0) }
            guard urls.count == originals.count else { reportActionFailure("The selected files are no longer available to copy."); return }
            NSPasteboard.general.clearContents()
            if NSPasteboard.general.writeObjects(urls.map { $0 as NSURL }) { onToast?(.copiedFile(urls)) }
            else { reportActionFailure("The files couldn’t be copied.") }
            return
        }
        dispatch(action, items: originals)
    }

    private func resolve(_ originals: [BrowserDownload]) -> [BrowserDownload]? {
        DownloadLibrarySelection.resolve(originals, in: store.downloadItems, profiles: Set(store.state.profiles.map(\.id)))
    }
    private func resolvedItems(for action: DownloadLibraryAction, items: [BrowserDownload]? = nil) -> [BrowserDownload]? {
        guard ownerValid() else { return nil }
        guard let resolved = DownloadLibrarySelection.resolve(items ?? selectedItems, for: action, in: store.downloadState),
              [.copyLink, .openSource].contains(action) || resolved.allSatisfy({ operations[DownloadLibraryIdentity($0)] == nil }) else { return nil }
        return resolved
    }
    private func dispatch(_ action: DownloadLibraryAction, items: [BrowserDownload]) {
        for item in items {
            guard ownerValid(), let ownerWindow = window, ownerWindow.attachedSheet == nil,
                  let current = resolvedItems(for: action, items: [item])?.first,
                  onAction?(current, action) == true else {
                reportActionFailure("The download couldn’t be changed. It may be busy or no longer available."); return
            }
        }
    }
    private func eligible(_ item: BrowserDownload, _ action: DownloadLibraryAction) -> Bool {
        DownloadLibrarySelection.eligible(item, action, spaces: store.state.spaces)
    }
    private func selectionMenu() -> NSMenu? {
        activationGeneration &+= 1
        let items = selectedItems; guard !items.isEmpty, ownerValid() else { return nil }
        guard let originalWindow = window, originalWindow.attachedSheet == nil else { return nil }
        let generation = contextGeneration
        let menu = NSMenu(); menu.autoenablesItems = false
        func add(_ title: String, _ action: DownloadLibraryAction) {
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            let target = DownloadMenuTarget { [weak self, weak originalWindow] in
                guard let self, let originalWindow, self.window === originalWindow,
                      self.contextGeneration == generation,
                      Set(self.selectedItems.map(DownloadLibraryIdentity.init)) == Set(items.map(DownloadLibraryIdentity.init)) else { return }
                self.act(action, items: items)
            }
            item.target = target; item.action = #selector(DownloadMenuTarget.run); item.representedObject = target
            item.isEnabled = resolvedItems(for: action, items: items) != nil
            if action == .toggleOpen { item.state = items.allSatisfy(\.openWhenComplete) ? .on : .off }
            menu.addItem(item)
        }
        add("Open", .open); add("Show in Finder", .reveal); add("Copy File", .copyFile)
        add("Copy Download Link", .copyLink); add("Open Source URL", .openSource)
        menu.addItem(.separator()); add("Open When Finished", .toggleOpen)
        for (title, action) in [("Review…", DownloadLibraryAction.review), ("Pause", .pause), ("Resume", .resume), ("Cancel", .cancel), ("Retry", .retry)] where items.contains(where: { eligible($0, action) }) { add(title, action) }
        menu.addItem(.separator()); add("Hide from Parc", .remove); add("Move to Trash", .trash)
        return menu
    }
    private func reportActionFailure(_ message: String) {
        actionMessage = message; footer.stringValue = message; footer.toolTip = message; footer.isHidden = false
        needsLayout = true
        NSAccessibility.post(element: self, notification: .announcementRequested,
            userInfo: [.announcement: message, .priority: NSAccessibilityPriorityLevel.medium.rawValue])
    }
    private func togglePreview() {
        activationGeneration &+= 1
        if preview?.window?.isVisible == true { preview?.dismiss() }
        else { updatePreview() }
    }
    private func updatePreview() {
        guard ownerValid(), selectedItems.count == 1, let item = selectedItems.first,
              let current = resolve([item])?.first, operations[DownloadLibraryIdentity(current)] == nil,
              let url = fileURL?(current), let window,
              window.attachedSheet == nil else { closePreview(restoringFocus: true); return }
        let generation = contextGeneration
        let controller: DownloadLibraryPreview
        let isNew = preview == nil
        if let existing = preview { controller = existing }
        else {
            controller = DownloadLibraryPreview(); preview = controller
            controller.onMove = { [weak self, weak controller, weak window] forward in
                guard let self, let controller, self.preview === controller, self.window === window,
                      self.contextGeneration == generation, self.ownerValid() else { return }
                self.movePreviewSelection(forward: forward)
            }
            controller.onOpen = { [weak self, weak controller] in
                guard let self, self.preview === controller, self.contextGeneration == generation else { return }
                self.act(.open)
            }
            controller.onCopy = { [weak self, weak controller] in
                guard let self, self.preview === controller, self.contextGeneration == generation else { return }
                self.act(.copyFile)
            }
            controller.onMenu = { [weak self, weak controller] in
                guard let self, self.preview === controller, self.contextGeneration == generation else { return nil }
                return self.selectionMenu()
            }
            controller.sourceRect = { [weak self, weak controller, weak window] in
                guard let self, let window, self.preview === controller, self.window === window,
                      self.contextGeneration == generation, self.ownerValid(),
                      self.resolve([current]) != nil, self.fileURL?(current) == url,
                      let row = self.rows.firstIndex(where: {
                          if case .item(let item) = $0 { return DownloadLibraryIdentity(item) == DownloadLibraryIdentity(current) }
                          return false
                      }), self.table.rect(ofRow: row).intersects(self.table.visibleRect),
                      let cell = self.table.view(atColumn: 0, row: row, makeIfNecessary: false) as? DownloadLibraryCell else { return nil }
                return cell.previewSourceBounds
            }
            if let row = rows.firstIndex(where: {
                if case .item(let item) = $0 { return DownloadLibraryIdentity(item) == DownloadLibraryIdentity(current) }
                return false
            }), table.rect(ofRow: row).intersects(table.visibleRect),
                let cell = table.view(atColumn: 0, row: row, makeIfNecessary: false) as? DownloadLibraryCell {
                controller.sourceImage = cell.previewSourceImage()
            }
            controller.onClosed = { [weak self, weak controller, weak window] in
                guard let self, self.preview === controller else { return }
                let ownedFocus = controller?.window?.isKeyWindow == true
                self.preview = nil; self.previewItem = nil; self.previewURL = nil
                if ownedFocus, self.ownerValid(), self.window === window, window?.attachedSheet == nil {
                    window?.makeKey(); window?.makeFirstResponder(self.table)
                }
            }
        }
        previewItem = current; previewURL = url
        let index = displayed.firstIndex { DownloadLibraryIdentity($0) == DownloadLibraryIdentity(current) } ?? 0
        controller.update(url: url, title: current.name, ordinal: index + 1, count: displayed.count,
            canOpen: current.canOpen, canMovePrevious: previewRow(forward: false) != nil,
            canMoveNext: previewRow(forward: true) != nil)
        if isNew { controller.present(on: window) }
    }
    private func previewRow(forward: Bool) -> Int? {
        guard let selected = table.selectedRowIndexes.first else { return nil }
        let candidates = selectableRows.filter { forward ? $0 > selected : $0 < selected }
        return (forward ? candidates : Array(candidates.reversed())).first { index in
            guard case let .item(item) = rows[index], let live = resolve([item])?.first else { return false }
            return live.canCopyFile && operations[DownloadLibraryIdentity(live)] == nil
        }
    }
    private func movePreviewSelection(forward: Bool) {
        guard let row = previewRow(forward: forward) else { return }
        table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false); table.scrollRowToVisible(row)
    }
    private func reloadRows(selecting selection: IndexSet) {
        restoringSelection = true
        table.reloadData(); table.selectRowIndexes(selection, byExtendingSelection: false)
        restoringSelection = false
        if preview?.window?.isVisible == true { updatePreview() }
    }
    private func applyPalette() {
        empty.textColor = palette?.foregroundSecondary ?? .secondaryLabelColor
        footer.textColor = palette?.foregroundSecondary ?? .secondaryLabelColor
        emptyIcon.contentTintColor = palette?.foregroundSecondary ?? .secondaryLabelColor
        selectedFilter.ink = palette?.foregroundPrimary ?? .labelColor
        filterTitle.textColor = palette?.foregroundSecondary ?? .secondaryLabelColor
        searchBackdrop.ink = .labelColor
        retryLoad.contentTintColor = palette?.foregroundPrimary ?? .labelColor
        let selected = table.selectedRowIndexes
        reloadRows(selecting: selected)
        rebuildFilters(force: true)
    }
    override func layout() {
        super.layout()
        func place(_ view: NSView, _ frame: NSRect) {
            if animatingFilterLayout { view.animator().frame = frame } else { view.frame = frame }
        }
        let inset = LibraryPageHeader.inset, headerTop = LibraryPageHeader.top, headerHeight = LibraryPageHeader.height
        let width = max(0, bounds.width - 2 * inset), actionWidth = min(filter.fittingSize.width, width)
        searchBackdrop.frame = NSRect(x: inset, y: headerTop, width: max(0, width - actionWidth - LibraryPageHeader.spacing), height: headerHeight)
        filterTitle.frame = NSRect(x: inset + 4, y: 20, width: max(0, width - actionWidth - 8), height: 22)
        filter.frame = NSRect(x: max(inset, bounds.width - inset - actionWidth), y: headerTop, width: actionWidth, height: headerHeight)
        var x: CGFloat = 0, y: CGFloat = 0
        for view in filterControls {
            if view is NSTextField { view.frame = NSRect(x: 4, y: 0, width: max(0, width - 4), height: 18); y = 22; continue }
            let w = min(width, max(40, view.fittingSize.width))
            if x > 0 && x + w > width { x = 0; y += 38 }
            view.frame = NSRect(x: x, y: y, width: w, height: 32); x += w + 6
        }
        let filterHeight = min(y + 38, 180)
        filterContent.frame = NSRect(x: 0, y: 0, width: width, height: y + 38)
        place(filterScroll, NSRect(x: inset, y: 60, width: width, height: filtersExpanded ? filterHeight : 0))
        let contentTop = LibraryPageHeader.contentTop
        selectedFilter.frame = NSRect(x: inset, y: contentTop, width: min(width, selectedFilter.fittingSize.width), height: 32)
        let top: CGFloat = filtersExpanded ? 60 + filterHeight + 8 : selectedProfile == nil ? contentTop : contentTop + 40
        let statusHeight: CGFloat = footer.isHidden ? 0 : 36
        place(scroll, NSRect(x: 0, y: top, width: bounds.width, height: max(0, bounds.height - top - statusHeight)))
        footer.frame = NSRect(x: 12, y: bounds.height - 27, width: max(0, width - (retryLoad.isHidden ? 0 : 62)), height: 18)
        retryLoad.frame = NSRect(x: bounds.width - 68, y: bounds.height - 31, width: 58, height: 25)
        let emptyTop = max(top + 30, top + (bounds.height - top - statusHeight) * 0.5 - 65)
        place(emptyContent, NSRect(x: 0, y: emptyTop, width: bounds.width, height: 148))
        emptyIcon.frame = NSRect(x: bounds.midX - 24, y: 0, width: 48, height: 48)
        empty.frame = NSRect(x: 24, y: 63, width: max(0, bounds.width - 48), height: 85)
    }

}

@MainActor final class DownloadEmptyContentView: NSView {
    enum Mode { case hidden, status, empty }
    private let ownerValid: () -> Bool
    private var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    private(set) var mode = Mode.hidden
    private var appeared = false
    private var motionObserver: NSObjectProtocol?
    private var closeObserver: NSObjectProtocol?
    private weak var retiredWindow: NSWindow?
    override var isFlipped: Bool { true }

    init(ownerValid: @escaping () -> Bool) {
        self.ownerValid = ownerValid
        super.init(frame: .zero)
        wantsLayer = true; isHidden = true
        motionObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.settle() }
            }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    deinit {
        if let motionObserver { NSWorkspace.shared.notificationCenter.removeObserver(motionObserver) }
        if let closeObserver { NotificationCenter.default.removeObserver(closeObserver) }
    }
    func show(_ mode: Mode) {
        if self.mode != mode { appeared = false }
        self.mode = mode; isHidden = mode == .hidden
        if mode == .empty { appear() } else { settle() }
    }
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if window !== newWindow { appeared = false; settle() }
        super.viewWillMove(toWindow: newWindow)
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let closeObserver { NotificationCenter.default.removeObserver(closeObserver) }
        closeObserver = nil
        if let window {
            closeObserver = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification,
                object: window, queue: .main) { [weak self, weak window] _ in
                    MainActor.assumeIsolated {
                        self?.retiredWindow = window; self?.appeared = false; self?.settle()
                    }
                }
        }
        appear()
    }
    override func viewDidHide() {
        super.viewDidHide(); appeared = false; settle()
    }
    override func viewDidUnhide() {
        super.viewDidUnhide(); appear()
    }
    override func setFrameSize(_ newSize: NSSize) {
        if frame.size != newSize { settle() }
        super.setFrameSize(newSize)
        appear()
    }
    func settle() {
        guard let layer else { return }
        layer.removeAnimation(forKey: "empty.translation")
        layer.removeAnimation(forKey: "empty.opacity")
        CATransaction.begin(); CATransaction.setDisableActions(true)
        layer.transform = CATransform3DIdentity; layer.opacity = 1
        CATransaction.commit()
    }
    private func appear() {
        guard ownerValid() else { settle(); return }
        guard mode == .empty, !appeared, !bounds.isEmpty, !isHiddenOrHasHiddenAncestor,
              let window, window !== retiredWindow, let layer else { return }
        appeared = true; settle()
        guard !reduceMotion else { return }
        let move = DownloadPreviewGeometry.spring(keyPath: "transform.translation.y", ratio: 0.6, response: 0.35)
        move.fromValue = 16; move.toValue = 0
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0; fade.toValue = 1; fade.duration = 0.125
        fade.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer.add(move, forKey: "empty.translation")
        layer.add(fade, forKey: "empty.opacity")
    }
}

enum LibraryPageHeader {
    static let inset: CGFloat = 8
    static let top: CGFloat = 10
    static let height: CGFloat = 36
    static let spacing: CGFloat = 3
    static let contentTop: CGFloat = 56
}

@MainActor enum LibraryHeaderGlyph {
    static let side: CGFloat = 15
    private static var cache: [String: NSImage] = [:]
    static func image(_ name: String, weight: NSFont.Weight = .regular) -> NSImage? {
        let key = "\(name)/\(weight.rawValue)"
        if let cached = cache[key] { return cached }
        guard let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: side, weight: weight)) else { return nil }
        guard let painted = inkBounds(of: symbol, minimumAlpha: 1.0 / 255) else { return nil }
        let image = fitted(symbol, painted: painted)
        image.isTemplate = true
        cache[key] = image
        return image
    }
    private static func fitted(_ symbol: NSImage, painted: NSRect) -> NSImage {
        let scale = side / max(painted.width, painted.height)
        let drawn = NSSize(width: painted.width * scale, height: painted.height * scale)
        let margin: CGFloat = 1
        let origin = NSPoint(x: margin + (side - drawn.width) / 2, y: margin + (side - drawn.height) / 2)
        let placement = NSRect(x: origin.x - painted.minX * scale, y: origin.y - painted.minY * scale,
                               width: symbol.size.width * scale, height: symbol.size.height * scale)
        let canvas = NSSize(width: side + margin * 2, height: side + margin * 2)
        let image = NSImage(size: canvas, flipped: false) { _ in symbol.draw(in: placement); return true }
        image.alignmentRect = NSRect(x: margin, y: margin, width: side, height: side)
        return image
    }
    static func draw(_ name: String, in rect: NSRect, color: NSColor) {
        guard let glyph = image(name), let context = NSGraphicsContext.current?.cgContext else { return }
        let alignment = glyph.alignmentRect
        let draw = NSRect(x: rect.minX - alignment.minX * rect.width / max(alignment.width, 1),
                          y: rect.minY - alignment.minY * rect.height / max(alignment.height, 1),
                          width: glyph.size.width * rect.width / max(alignment.width, 1),
                          height: glyph.size.height * rect.height / max(alignment.height, 1))
        let resolved = color.usingColorSpace(.sRGB) ?? color
        context.saveGState(); context.setAlpha(resolved.alphaComponent)
        context.beginTransparencyLayer(in: draw, auxiliaryInfo: nil)
        glyph.draw(in: draw, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        context.setBlendMode(.sourceIn); context.setFillColor(resolved.withAlphaComponent(1).cgColor); context.fill(draw)
        context.endTransparencyLayer(); context.restoreGState()
    }
    private static func inkBounds(of symbol: NSImage, minimumAlpha: CGFloat) -> NSRect? {
        let scale: CGFloat = 8
        let width = Int(ceil(symbol.size.width * scale)), height = Int(ceil(symbol.size.height * scale))
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return nil }
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = context
        symbol.draw(in: NSRect(x: 0, y: 0, width: width, height: height))
        NSGraphicsContext.restoreGraphicsState()
        var minX = width, maxX = -1, minRow = height, maxRow = -1
        for row in 0..<height { for x in 0..<width where (bitmap.colorAt(x: x, y: row)?.alphaComponent ?? 0) > minimumAlpha {
            minX = min(minX, x); maxX = max(maxX, x); minRow = min(minRow, row); maxRow = max(maxRow, row)
        } }
        guard maxX >= minX, maxRow >= minRow else { return nil }
        return NSRect(x: CGFloat(minX) / scale, y: CGFloat(height - 1 - maxRow) / scale,
                      width: CGFloat(maxX - minX + 1) / scale, height: CGFloat(maxRow - minRow + 1) / scale)
    }
}

@MainActor final class DownloadSearchField: NSTextField {
    static let textFont = NSFont.systemFont(ofSize: 14, weight: .medium)
    override init(frame: NSRect) {
        super.init(frame: frame)
        isBezeled = false; drawsBackground = false; focusRingType = .none
        isEditable = true; isSelectable = true
        font = Self.textFont; textColor = .labelColor
        cell?.isScrollable = true; cell?.wraps = false
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override var placeholderString: String? {
        get { placeholderAttributedString?.string }
        set {
            placeholderAttributedString = newValue.map {
                NSAttributedString(string: $0, attributes: [.font: Self.textFont, .foregroundColor: NSColor.placeholderTextColor])
            }
        }
    }
}

@MainActor final class DownloadSearchBackdrop: NSView {
    var ink: NSColor = .labelColor { didSet { needsDisplay = true } }
    var onFocus: (() -> Void)?
    private let icon = NSImageView()
    private var tracking: NSTrackingArea?
    private var hovered = false
    private var resignationObserver: NSObjectProtocol?
    override var isFlipped: Bool { true }
    override var wantsUpdateLayer: Bool { true }
    override init(frame: NSRect) {
        super.init(frame: frame)
        icon.image = LibraryHeaderGlyph.image("magnifyingglass", weight: .semibold)
        icon.imageScaling = .scaleAxesIndependently
        icon.setAccessibilityElement(false)
        addSubview(icon)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    deinit {
        if let resignationObserver { NotificationCenter.default.removeObserver(resignationObserver) }
    }
    override func updateLayer() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = ink.withAlphaComponent(hovered ? 0.1 : 0.05).cgColor
            icon.contentTintColor = ink.withAlphaComponent(0.4)
        }
        layer?.cornerRadius = 12; layer?.cornerCurve = .continuous
    }
    override func layout() {
        super.layout()
        let optical = NSRect(x: 14.5, y: (bounds.height - LibraryHeaderGlyph.side) / 2,
                              width: LibraryHeaderGlyph.side, height: LibraryHeaderGlyph.side)
        let alignment = icon.image?.alignmentRect ?? NSRect(origin: .zero, size: optical.size)
        let imageSize = icon.image?.size ?? optical.size
        let scaleX = optical.width / max(alignment.width, 1), scaleY = optical.height / max(alignment.height, 1)
        icon.frame = NSRect(x: optical.minX - alignment.minX * scaleX, y: optical.minY - alignment.minY * scaleY,
                            width: imageSize.width * scaleX, height: imageSize.height * scaleY)
        for case let field as DownloadSearchField in subviews {
            let height = field.cell?.cellSize.height ?? 17
            field.frame = backingAlignedRect(NSRect(x: 41, y: (bounds.height - height) / 2, width: max(0, bounds.width - 51), height: height),
                                             options: .alignAllEdgesNearest)
        }
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let next = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .activeInKeyWindow, .inVisibleRect], owner: self)
        tracking = next; addTrackingArea(next)
        refreshHover()
    }
    override func mouseEntered(with event: NSEvent) {
        guard let tracking, event.trackingArea === tracking else { return }
        refreshHover()
    }
    override func mouseExited(with event: NSEvent) {
        guard let tracking, event.trackingArea === tracking else { return }
        setHovered(false)
    }
    override func mouseMoved(with event: NSEvent) {
        guard let window, event.windowNumber == window.windowNumber else { return }
        refreshHover()
    }
    private func refreshHover() {
        guard let window, window.isKeyWindow, !isHiddenOrHasHiddenAncestor,
              let content = window.contentView else { setHovered(false); return }
        let location = content.superview?.convert(window.mouseLocationOutsideOfEventStream, from: nil)
            ?? window.mouseLocationOutsideOfEventStream
        let hit = content.hitTest(location)
        setHovered(hit === self || hit?.isDescendant(of: self) == true)
    }
    private func setHovered(_ value: Bool) {
        guard value != hovered else { return }
        hovered = value; needsDisplay = true
    }
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        setHovered(false)
        if let resignationObserver { NotificationCenter.default.removeObserver(resignationObserver) }
        resignationObserver = nil
        if let newWindow {
            resignationObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didResignKeyNotification, object: newWindow, queue: .main
            ) { [weak self, weak newWindow] _ in
                MainActor.assumeIsolated {
                    guard let self, let newWindow, self.window === newWindow else { return }
                    self.setHovered(false)
                }
            }
        }
        super.viewWillMove(toWindow: newWindow)
    }
    override func viewDidHide() { super.viewDidHide(); setHovered(false) }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance(); needsDisplay = true
    }
    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        return hit === icon ? self : hit
    }
    override func mouseDown(with event: NSEvent) { onFocus?() }
}

@MainActor final class DownloadFilterButton: PointingHandButton {
    var actionBlock: (() -> Void)?
    var profileID: UUID?
    var isChosen = false { didSet { state = isChosen ? .on : .off; needsDisplay = true } }
    var ink: NSColor = .secondaryLabelColor { didSet { needsDisplay = true } }
    var symbol: String? { didSet { needsDisplay = true } }
    private var hovered = false
    private var tracking: NSTrackingArea?
    enum Style { case header, chip }
    let style: Style
    init(_ title: String, symbol: String? = nil, style: Style = .chip, action: (() -> Void)? = nil) {
        self.symbol = symbol; self.style = style; actionBlock = action
        super.init(frame: .zero)
        self.title = title; target = self; self.action = #selector(run)
        isBordered = false; setButtonType(.momentaryPushIn)
        font = .systemFont(ofSize: 14, weight: style == .header ? .medium : .semibold)
        focusRingType = .exterior; setAccessibilityLabel(title)
        if style == .header { wantsLayer = true }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override var acceptsFirstResponder: Bool { true }
    override var fittingSize: NSSize {
        let text = ceil((title as NSString).size(withAttributes: [.font: font!]).width)
        guard style == .header else { return NSSize(width: text + (symbol == nil ? 24 : 43), height: 32) }
        return NSSize(width: headerPadding * 2 + (symbol == nil ? 0 : LibraryHeaderGlyph.side + 4) + text, height: LibraryPageHeader.height)
    }
    private var headerPadding: CGFloat { symbol == nil ? 12 : 10 }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true }
    @objc private func run() { actionBlock?() }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(area); tracking = area
    }
    override func mouseEntered(with event: NSEvent) { hovered = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hovered = false; needsDisplay = true }
    override func draw(_ dirtyRect: NSRect) {
        if style == .header { drawHeader(); return }
        let background = isChosen ? ink : ink.withAlphaComponent(isHighlighted ? 0.2 : hovered ? 0.15 : 0.1)
        background.setFill(); NSBezierPath(roundedRect: bounds, xRadius: 12, yRadius: 12).fill()
        let foreground = isChosen ? NSColor.controlBackgroundColor : ink
        let paragraph = NSMutableParagraphStyle(); paragraph.lineBreakMode = .byTruncatingTail
        let attributes: [NSAttributedString.Key: Any] = [.font: font!, .foregroundColor: foreground, .paragraphStyle: paragraph]
        let h = (title as NSString).size(withAttributes: attributes).height
        let iconWidth: CGFloat = symbol == nil ? 0 : 19
        if let symbol, let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?.withSymbolConfiguration(.init(pointSize: 14, weight: .medium)) {
            image.lockFocus(); foreground.set(); NSRect(origin: .zero, size: image.size).fill(using: .sourceAtop); image.unlockFocus()
            image.draw(in: NSRect(x: 9, y: (bounds.height - 14) / 2, width: 14, height: 14))
        }
        (title as NSString).draw(in: NSRect(x: 12 + iconWidth, y: (bounds.height - h) / 2, width: max(0, bounds.width - 24 - iconWidth), height: h), withAttributes: attributes)
    }
    private func drawHeader() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            CATransaction.begin(); CATransaction.setDisableActions(true)
            layer?.cornerRadius = 12; layer?.cornerCurve = .continuous
            layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(hovered || isHighlighted ? 0.1 : 0.05).cgColor
            CATransaction.commit()
            let foreground = DownloadAccessoryColors.foreground(hovered: false, appearance: effectiveAppearance)
            let paragraph = NSMutableParagraphStyle(); paragraph.lineBreakMode = .byTruncatingTail
            let attributes: [NSAttributedString.Key: Any] = [.font: font!, .foregroundColor: foreground, .paragraphStyle: paragraph]
            var x = headerPadding
            if let symbol {
                let side = LibraryHeaderGlyph.side
                LibraryHeaderGlyph.draw(symbol, in: NSRect(x: x, y: (bounds.height - side) / 2, width: side, height: side), color: foreground)
                x += side + 4
            }
            let height = (title as NSString).size(withAttributes: attributes).height
            (title as NSString).draw(in: NSRect(x: x, y: (bounds.height - height) / 2, width: max(0, bounds.width - x - headerPadding), height: height),
                                     withAttributes: attributes)
        }
    }
    override func drawFocusRingMask() { NSBezierPath(roundedRect: bounds, xRadius: 12, yRadius: 12).fill() }
    override var focusRingMaskBounds: NSRect { bounds }
}

@MainActor final class DownloadSectionHeading: NSView {
    static let font = NSFont.systemFont(ofSize: 12, weight: .semibold)
    static let height: CGFloat = (8 + font.ascender - font.descender + font.leading + 4).rounded()
    private static let relative: RelativeDateTimeFormatter = {
        let value = RelativeDateTimeFormatter(); value.unitsStyle = .full; return value
    }()
    static let undatedTitle = "Earlier"
    static func title(for date: Date, now: Date = Date()) -> String {
        if Calendar.current.isDateInToday(date) { return "Today" }
        if Calendar.current.isDateInYesterday(date) { return "Yesterday" }
        return relative.localizedString(for: date, relativeTo: now)
    }
    private let label: NSTextField
    override var isFlipped: Bool { true }
    init(_ title: String) {
        label = NSTextField(labelWithString: title)
        super.init(frame: .zero)
        label.font = Self.font; label.lineBreakMode = .byTruncatingTail
        addSubview(label); refreshColor()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); refreshColor() }
    private func refreshColor() {
        label.textColor = DownloadAccessoryColors.foreground(hovered: false, appearance: effectiveAppearance)
    }
    override func layout() {
        super.layout()
        label.frame = NSRect(x: 10, y: 8, width: max(0, bounds.width - 22), height: label.intrinsicContentSize.height)
    }
}

@MainActor private final class DownloadMenuTarget: NSObject {
    let action: () -> Void
    init(_ action: @escaping () -> Void) { self.action = action }
    @objc func run() { action() }
}
@MainActor enum DownloadRowSubtitle {
    private static let bytes: ByteCountFormatter = {
        let value = ByteCountFormatter()
        value.allowedUnits = [.useKB, .useMB, .useGB, .useTB]
        value.includesUnit = true; value.isAdaptive = true
        value.allowsNonnumericFormatting = true; value.zeroPadsFractionDigits = true
        return value
    }()
    private static let duration: DateComponentsFormatter = {
        let value = DateComponentsFormatter()
        value.unitsStyle = .abbreviated; value.zeroFormattingBehavior = .dropAll
        value.allowedUnits = [.day, .hour, .minute, .second]
        return value
    }()
    static func text(for item: BrowserDownload) -> String {
        if item.requiresReview { return item.statusText.isEmpty ? "Review required" : item.statusText }
        if item.fileMissing && item.status == .completed { return "File deleted or moved" }
        let domain = item.sourceDomain ?? item.sourceURL.flatMap(URL.init(string:))?.host
        let source = domain.flatMap { $0.isEmpty ? nil : "from " + $0 }
        switch item.status {
        case .pending: return ""
        case .completed:
            return [kind(for: item), source].compactMap { $0 }.joined(separator: " ")
        case .paused:
            return ["Paused", source].compactMap { $0 }.joined(separator: " · ")
        case .cancelled:
            return ["Cancelled", source].compactMap { $0 }.joined(separator: " · ")
        case .failed: return "Failed to Download"
        case .downloading:
            guard item.totalBytes > 0 else { return "" }
            if item.openWhenComplete {
                let fraction = Float(max(0, item.receivedBytes)) / Float(item.totalBytes)
                let percent = Int(min(100, max(0, fraction * 100)))
                return "Opening… (\(percent)%)"
            }
            var parts: [String] = []
            if item.receivedBytes > 0 {
                let received = bytes.string(fromByteCount: item.receivedBytes)
                let total = bytes.string(fromByteCount: item.totalBytes)
                var leading = received
                let receivedParts = received.split(whereSeparator: \.isWhitespace)
                let totalParts = total.split(whereSeparator: \.isWhitespace)
                if receivedParts.count > 1, totalParts.count > 1,
                   receivedParts.last == totalParts.last,
                   let space = received.lastIndex(where: \.isWhitespace) {
                    leading = String(received[..<space])
                }
                parts.append(leading + "/" + total)
            }
            if let seconds = item.timeRemaining, seconds.isFinite, seconds >= 1 {
                let now = Date()
                if let remaining = duration.string(from: now, to: now.addingTimeInterval(seconds)),
                   !remaining.isEmpty { parts.append(remaining) }
            }
            return parts.joined(separator: " · ")
        }
    }
    static func kind(for item: BrowserDownload) -> String {
        let ext = URL(fileURLWithPath: item.path.isEmpty ? item.name : item.path).pathExtension
        let type = UTType(filenameExtension: ext) ?? item.mimeType.flatMap { UTType(mimeType: $0) }
        guard let type else { return "Download" }
        for (category, title) in [(UTType.image, "Image"), (.diskImage, "Disk Image"),
                                  (.pdf, "PDF"), (.movie, "Movie"), (.audio, "Audio"),
                                  (.zip, "Zip Archive"), (.archive, "Archive")] {
            if type.conforms(to: category) { return title }
        }
        return "Download"
    }
}

@MainActor enum DownloadRowArtwork {
    enum Kind { case file, emptyFavicon, none, security }
    static func kind(for item: BrowserDownload) -> Kind {
        if item.requiresReview { return .security }
        switch item.status {
        case .completed: return item.fileMissing ? .emptyFavicon : .file
        case .downloading, .paused: return .none
        case .pending, .failed, .cancelled: return .emptyFavicon
        }
    }
    static func title(for item: BrowserDownload) -> String {
        let path = item.path.isEmpty ? item.name : URL(fileURLWithPath: item.path).lastPathComponent
        return path.lowercased()
    }
    static func dimsTitle(_ item: BrowserDownload) -> Bool {
        item.status == .failed || item.status == .cancelled || (item.isComplete && item.fileMissing)
    }
}

@MainActor private final class DownloadArtworkView: NSImageView {
    var kind = DownloadRowArtwork.Kind.none { didSet { refreshPlaceholder() } }
    private let placeholder = CALayer()
    private let emptyFaviconMask = CALayer()
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true; placeholder.cornerCurve = .continuous
        layer?.addSublayer(placeholder)
        imageScaling = .scaleAxesIndependently
        setAccessibilityHidden(true)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override var image: NSImage? { didSet { refreshPlaceholder() } }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); refreshPlaceholder() }
    override func viewDidChangeBackingProperties() { super.viewDidChangeBackingProperties(); refreshPlaceholder() }
    override func layout() { super.layout(); refreshPlaceholder() }
    private func refreshPlaceholder() {
        let isFile = kind == .file, isEmpty = kind == .emptyFavicon
        let favicon = isEmpty ? LibraryArtwork.emptyFavicon : nil
        CATransaction.begin(); CATransaction.setDisableActions(true)
        placeholder.isHidden = image != nil || (!isFile && !isEmpty) || (isEmpty && favicon == nil)
        let size: CGFloat = isFile ? 24 : 14
        placeholder.frame = NSRect(x: (bounds.width-size)/2, y: (bounds.height-size)/2, width: size, height: size)
        placeholder.cornerRadius = isFile ? 8 : 0
        if let favicon {
            let scale = window?.backingScaleFactor ?? 2
            emptyFaviconMask.frame = placeholder.bounds
            emptyFaviconMask.contentsGravity = .resize
            emptyFaviconMask.contentsScale = scale
            emptyFaviconMask.contents = favicon.layerContents(forContentsScale: scale)
            placeholder.mask = emptyFaviconMask
        } else { placeholder.mask = nil }
        effectiveAppearance.performAsCurrentDrawingAppearance {
            placeholder.backgroundColor = NSColor.labelColor.withAlphaComponent(NSColor.labelColor.alphaComponent * (isFile ? 0.05 : 1)).cgColor
        }
        CATransaction.commit()
    }
    override func draw(_ dirtyRect: NSRect) {
        NSGraphicsContext.current?.imageInterpolation = .low
        super.draw(dirtyRect)
    }
}

@MainActor private final class DownloadLibraryCell: NSTableCellView {
    var makeMenu: (() -> NSMenu?)?
    var configureThumbnail: (() -> Void)?
    var cancelThumbnail: ((UUID?) -> Void)?
    var thumbnailToken: UUID?
    private let more = DownloadRowButton()
    var previewSourceBounds: NSRect { icon.convert(icon.bounds, to: nil) }
    func previewSourceImage() -> NSImage? {
        let size = icon.bounds.size
        guard icon.window != nil, size.width > 0, size.height > 0,
              let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(ceil(size.width * 2)),
                pixelsHigh: Int(ceil(size.height * 2)), bitsPerSample: 8, samplesPerPixel: 4,
                hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        bitmap.size = size
        icon.cacheDisplay(in: icon.bounds, to: bitmap)
        let image = NSImage(size: size); image.addRepresentation(bitmap); return image
    }
    private let name = NSTextField(labelWithString: ""), detail = NSTextField(labelWithString: ""), source = NSTextField(labelWithString: "")
    let identity: DownloadLibraryIdentity
    private var item: BrowserDownload
    private var retired = false
    private let progress = DownloadActivityBadge(frame: .zero)
    private let icon = DownloadArtworkView(frame: .zero)
    private var highlighted = false
    override var isFlipped: Bool { true }
    init(item: BrowserDownload, palette: ThemeChromePalette?, operation: String?) {
        self.identity = DownloadLibraryIdentity(item); self.item = item
        super.init(frame: .zero)
        for label in [name, detail] {
            label.lineBreakMode = .byTruncatingTail; label.setAccessibilityHidden(true); addSubview(label)
        }
        icon.setAccessibilityHidden(true)
        addSubview(icon); addSubview(progress)
        LiveShortcutToolTip.set(more, "More download actions"); more.setAccessibilityLabel("More download actions")
        more.actionBlock = { [weak self] in
            guard let self, let menu = self.makeMenu?() else { return }
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: self.more.bounds.maxY), in: self.more)
        }
        more.isHidden = true; addSubview(more)
        update(item: item, palette: palette, operation: operation)
    }
    func update(item: BrowserDownload, palette: ThemeChromePalette?, operation: String?) {
        precondition(identity == DownloadLibraryIdentity(item))
        self.item = item; retired = false
        name.stringValue = DownloadRowArtwork.title(for: item); name.font = .systemFont(ofSize: 14, weight: .regular)
        refreshTitleColor()
        detail.stringValue = operation ?? DownloadRowSubtitle.text(for: item)
        detail.font = .systemFont(ofSize: 12); detail.textColor = .secondaryLabelColor
        let host = item.sourceURL.flatMap(URL.init(string:))?.host
        source.stringValue = [host.flatMap { detail.stringValue.contains("from " + $0) ? nil : $0 },
            item.statusText == detail.stringValue ? nil : item.statusText]
            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
        icon.kind = DownloadRowArtwork.kind(for: item)
        icon.image = item.requiresReview ? NSImage(systemSymbolName: "exclamationmark.shield", accessibilityDescription: nil) : nil
        icon.contentTintColor = detail.textColor
        icon.isHidden = !item.requiresReview && (item.status == .downloading || item.status == .paused)
        progress.colors = DownloadBadgeColors(foreground: palette?.foregroundPrimary ?? .labelColor,
            maxContrast: palette?.maxContrastColor ?? .labelColor, cutout: palette?.cutoutColor ?? .windowBackgroundColor)
        refreshProgress()
        more.refreshTint()
        needsLayout = true
        toolTip = [item.name, detail.stringValue, source.stringValue].filter { !$0.isEmpty }.joined(separator: "\n")
        name.toolTip = item.name; detail.toolTip = [detail.stringValue, source.stringValue].filter { !$0.isEmpty }.joined(separator: " · ")
        setAccessibilityLabel([item.name, detail.stringValue, source.stringValue].filter { !$0.isEmpty }.joined(separator: ", "))
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func accessibilityChildren() -> [Any]? {
        more.isHidden ? [] : [more]
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        cancelThumbnail?(thumbnailToken); thumbnailToken = nil
        refreshProgress()
        if window != nil && !retired { configureThumbnail?() }
    }
    func retirePresentation() {
        retired = true; progress.reset()
        cancelThumbnail?(thumbnailToken); thumbnailToken = nil
    }
    private func refreshProgress() {
        guard !retired, item.status == .downloading, !item.requiresReview, let profile = item.profileID else {
            progress.reset(); return
        }
        progress.update([item], profiles: [profile], enabled: true)
    }
    private func returnFocus(from control: NSView) {
        guard window?.firstResponder === control else { return }
        var ancestor = superview
        while let view = ancestor {
            if view is NSTableView { window?.makeFirstResponder(view); break }
            ancestor = view.superview
        }
    }
    func setThumbnail(_ image: NSImage?) {
        guard let image else { return }; icon.image = image; icon.contentTintColor = nil
        icon.imageScaling = .scaleAxesIndependently
    }
    func setHighlighted(_ value: Bool) { highlighted = value; refreshTitleColor() }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance(); refreshTitleColor()
    }
    private func refreshTitleColor() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            name.textColor = DownloadRowArtwork.dimsTitle(item) ? .secondaryLabelColor
                : NSColor.labelColor.withAlphaComponent(NSColor.labelColor.alphaComponent * (highlighted ? 1 : 0.85))
        }
    }
    func setAccessoryVisible(_ visible: Bool) {
        guard more.isHidden == visible else { return }
        if !visible { returnFocus(from: more) }
        more.isHidden = !visible; needsLayout = true
    }
    override func layout() {
        super.layout()
        let artworkSize: CGFloat = icon.kind == .file ? 24 : 32
        icon.frame = NSRect(x: 32 - artworkSize/2, y: (bounds.height-artworkSize)/2,
                            width: artworkSize, height: artworkSize)
        let controls = more.isHidden ? [] : [more]
        let trailingWidth = controls.reduce(CGFloat.zero) { $0 + $1.targetSize } + CGFloat(max(0, controls.count - 1)) * 8
        let textX: CGFloat = 52
        let controlsX = max(textX, bounds.width - 20 - trailingWidth)
        let textWidth = max(0, controlsX - 8 - textX)
        func line(_ field: NSTextField) -> CGFloat { field.font.map { $0.ascender - $0.descender + $0.leading } ?? 16 }
        let top = (bounds.height - line(name) - 2 - line(detail)) / 2
        name.frame = backingAlignedRect(NSRect(x: textX - 2, y: top, width: textWidth, height: 18), options: .alignAllEdgesNearest)
        detail.frame = backingAlignedRect(NSRect(x: textX - 2, y: top + line(name) + 2, width: textWidth, height: 16), options: .alignAllEdgesNearest)
        progress.frame = NSRect(x: 16, y: 12, width: 28, height: 32)
        var x = controlsX
        for control in controls {
            control.frame = NSRect(x: x, y: (bounds.height - control.targetSize) / 2,
                width: control.targetSize, height: control.targetSize)
            x += control.targetSize + 8
        }
    }
}

@MainActor private final class DownloadRowButton: PointingHandButton {
    var actionBlock: (() -> Void)?
    private var area: NSTrackingArea?
    private var hovered = false
    let targetSize: CGFloat = 32
    init() {
        super.init(frame: .zero)
        title = ""; isBordered = false; bezelStyle = .regularSquare
        font = .systemFont(ofSize: 14, weight: .medium)
        image = NSImage(systemSymbolName: "ellipsis", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 14, weight: .medium))
        imagePosition = .imageOnly; focusRingType = .default
        setAccessibilityElement(true); setAccessibilityRole(.button)
        target = self; self.action = #selector(invoke)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let area { removeTrackingArea(area) }
        let next = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
        area = next; addTrackingArea(next)
    }
    override var isHidden: Bool { didSet { if isHidden { hovered = false }; refreshTint() } }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); refreshTint() }
    override func mouseEntered(with event: NSEvent) { hovered = true; refreshTint() }
    override func mouseExited(with event: NSEvent) { hovered = false; refreshTint() }
    func refreshTint() {
        contentTintColor = DownloadAccessoryColors.foreground(hovered: hovered, appearance: effectiveAppearance)
        needsDisplay = true
    }
    override func draw(_ dirtyRect: NSRect) {
        if isEnabled && (hovered || isHighlighted) {
            let color = DownloadAccessoryColors.background(pressed: isHighlighted, appearance: effectiveAppearance)
            color.setFill()
            let radius: CGFloat = 8
            NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius).fill()
        }
        super.draw(dirtyRect)
    }
    @objc private func invoke() { actionBlock?() }
}

@MainActor enum DownloadAccessoryColors {
    static func background(pressed: Bool, appearance: NSAppearance) -> NSColor {
        let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return NSColor(white: dark ? 1 : 0, alpha: pressed ? (dark ? 0.172 : 0.141) : (dark ? 0.129 : 0.114))
    }
    static func foreground(hovered: Bool, appearance: NSAppearance) -> NSColor {
        let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return NSColor(white: dark ? 1 : 0, alpha: hovered ? (dark ? 0.923 : 0.910) : (dark ? 0.592 : 0.565))
    }
}

@MainActor final class DownloadRowBackdrop: NSView {
    var highlighted = false { didSet { needsDisplay = true } }
    var emphasized = false { didSet { needsDisplay = true } }
    private var accessibilityObserver: NSObjectProtocol?
    override var wantsUpdateLayer: Bool { true }
    override init(frame: NSRect) {
        super.init(frame: frame); wantsLayer = true
        setAccessibilityElement(false); setAccessibilityHidden(true)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    deinit { if let accessibilityObserver { NSWorkspace.shared.notificationCenter.removeObserver(accessibilityObserver) } }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let accessibilityObserver { NSWorkspace.shared.notificationCenter.removeObserver(accessibilityObserver) }
        accessibilityObserver = nil
        if let window {
            accessibilityObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main
            ) { [weak self, weak window] _ in
                MainActor.assumeIsolated {
                    guard let self, let window, self.window === window else { return }
                    self.needsDisplay = true
                }
            }
        }
        needsDisplay = true
    }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true }
    override func updateLayer() {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        layer?.cornerRadius = 12; layer?.cornerCurve = .continuous
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(NSColor.labelColor.alphaComponent * (highlighted ? 0.1 : 0)).cgColor
            layer?.borderWidth = highlighted && emphasized && NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast ? 1 : 0
            layer?.borderColor = NSColor.keyboardFocusIndicatorColor.cgColor
        }
        CATransaction.commit()
    }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func accessibilityChildren() -> [Any]? { [] }
}

@MainActor private final class DownloadLibraryRow: NSTableRowView {
    private let backdrop = DownloadRowBackdrop(frame: .zero)
    private var area: NSTrackingArea?
    private var hovered = false
    private var shouldHighlight = false
    private var scrolling = false
    init() {
        super.init(frame: .zero)
        addSubview(backdrop, positioned: .below, relativeTo: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override var isSelected: Bool { didSet { updatePresentation() } }
    override var isEmphasized: Bool { didSet { updatePresentation() } }
    override func layout() {
        super.layout()
        backdrop.frame = NSRect(x: 8, y: 0, width: max(0, bounds.width - 16), height: bounds.height)
    }
    override func didAddSubview(_ subview: NSView) { super.didAddSubview(subview); updatePresentation() }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        NotificationCenter.default.removeObserver(self)
        hovered = false; shouldHighlight = false; scrolling = false
        if let window, let scroll = enclosingScrollView {
            let center = NotificationCenter.default
            center.addObserver(self, selector: #selector(scrollBegan(_:)), name: NSScrollView.willStartLiveScrollNotification, object: scroll)
            center.addObserver(self, selector: #selector(scrollEnded(_:)), name: NSScrollView.didEndLiveScrollNotification, object: scroll)
            center.addObserver(self, selector: #selector(windowFocusChanged(_:)), name: NSWindow.didBecomeKeyNotification, object: window)
            center.addObserver(self, selector: #selector(windowFocusChanged(_:)), name: NSWindow.didResignKeyNotification, object: window)
            resamplePointer()
        }
        updatePresentation()
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let area { removeTrackingArea(area) }
        let next = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
        area = next; addTrackingArea(next)
    }
    override func mouseEntered(with event: NSEvent) { hovered = true; shouldHighlight = !scrolling; updatePresentation() }
    override func mouseExited(with event: NSEvent) { hovered = false; shouldHighlight = false; updatePresentation() }
    @objc private func scrollBegan(_ notification: Notification) {
        guard notification.object as? NSScrollView === enclosingScrollView else { return }
        scrolling = true; updatePresentation()
    }
    @objc private func scrollEnded(_ notification: Notification) {
        guard notification.object as? NSScrollView === enclosingScrollView else { return }
        scrolling = false; resamplePointer(); updatePresentation()
    }
    @objc private func windowFocusChanged(_ notification: Notification) { resamplePointer(); updatePresentation() }
    private func resamplePointer() {
        hovered = window.map { $0.isKeyWindow && visibleRect.contains(convert($0.mouseLocationOutsideOfEventStream, from: nil)) } ?? false
        shouldHighlight = hovered && !scrolling
    }
    private func updatePresentation() {
        let visible = !scrolling && (shouldHighlight || isSelected)
        for cell in subviews.compactMap({ $0 as? DownloadLibraryCell }) {
            cell.setAccessoryVisible(visible); cell.setHighlighted(shouldHighlight || isSelected)
        }
        backdrop.highlighted = shouldHighlight || (isSelected && selectionHighlightStyle != .none)
        backdrop.emphasized = isSelected && isEmphasized
        needsDisplay = true
    }
    override func drawBackground(in dirtyRect: NSRect) {}
    override func drawSelection(in dirtyRect: NSRect) {}

}

enum DownloadFileActivation {
    enum Route { case preview, open, unavailable }
    static func inspect(_ url: URL) -> Route {
        guard url.isFileURL else { return .unavailable }
        let type = (try? url.resourceValues(forKeys: [.contentTypeKey]))?.contentType
            ?? UTType(filenameExtension: url.pathExtension, conformingTo: .data)
        let media = !url.hasDirectoryPath && type.map {
            $0.conforms(to: .image) || $0.conforms(to: .movie) || $0.conforms(to: .pdf)
        } == true
        guard media else { return .open }
        return FileManager.default.isReadableFile(atPath: url.path) ? .preview : .unavailable
    }
}
