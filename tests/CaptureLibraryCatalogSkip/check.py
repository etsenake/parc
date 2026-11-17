#!/usr/bin/env python3
from pathlib import Path
import re

root = Path(__file__).resolve().parents[2]
source = (root / "Sources/ParcApp/CaptureLibraryView.swift").read_text()

def body(text, signature):
    begin = text.index(signature)
    finish = text.index("\n    }\n", begin)
    return text[begin:finish]


for needle in ("private var observedCaptures: [SavedCapture] = []",
               "private var observedMediaRevision: UInt64 = 0",
               "private var observedMediaFolders: [ExternalMediaFolder] = []"):
    assert needle in source, f"missing last-applied catalog field {needle}"
assert "observedMediaItems" not in source, "the view must compare the media revision, not walk the media list"

reload = body(source, "private func reload(force: Bool = false) {")
steps = ("let itemsChanged = catalogItemsChanged()",
         "if !force && !itemsChanged && !catalogStatusChanged() { return }",
         "rememberAppliedCatalog()",
         "if force { rebuildItems() } else if itemsChanged { scheduleRebuild() }",
         "refreshMessage()")
for needle in steps:
    assert needle in reload, f"reload(force:) no longer contains {needle}"
assert [reload.index(needle) for needle in steps] == sorted(reload.index(needle) for needle in steps), \
    "reload must skip identical catalogs, record them, then rebuild synchronously only when forced"
for gone in ("reloadData", ".sort", ".map", "firstIndex"):
    assert gone not in reload, f"reload(force:) must not touch the whole list on the main thread: {gone}"

schedule = body(source, "private func scheduleRebuild() {")
for needle in ("planner.start { [weak self] in",
               "let base = self.items, version = self.listVersion, ready = self.catalogReady",
               "let captures = ready ? self.store.items : [], files = ready ? self.media.items : []",
               "return (work: { try Self.plan(from: base, captures: captures, files: files, query: query) }, finish:",
               "if self.listVersion == version { self.apply(plan) } else { self.scheduleRebuild() }"):
    assert needle in schedule, f"catalog changes must be planned off the main thread by the latest-wins planner: {needle}"
assert "rebuildPending" not in source and "rebuildTask" not in source, "a newer catalog must replace the calculation in flight, not queue behind it"
assert "planner.cancel()" in body(source, "private func rebuildItems() {"), "a forced rebuild cancels the calculation in flight"
invalidate = body(source, "func invalidate() {")
assert "planner.cancel()" not in invalidate, "leaving Media must not drop a pending grid update"
context = (root / "Sources/ParcApp/MediaLibraryContext.swift").read_text()
latest = body(context, "    func start(_ request: @escaping Request) {")
for needle in ("task?.cancel(); task = nil; ticket &+= 1; queued = nil", "Task.detached(priority: .userInitiated) { try work() }",
               "if task != nil, replaced >= replacementsBeforeFinishing { queued = request; return }",
               "guard let next = request() else { return }",
               "if let waiting = self.queued { self.queued = nil; self.start(waiting) }",
               "withTaskCancellationHandler { try? await worker.value } onCancel: { worker.cancel() }", "guard let self, self.ticket == current else { return }"):
    assert needle in latest, f"a superseded grid calculation must be cancelled, not run to the end: {needle}"
assert "nonisolated private static func plan(from base: [Item]" in source, "the diff must run outside the main actor"
assert "nonisolated private static func sortedItems(" in source, "merging, filtering and sorting must run outside the main actor"
plan = body(source, "nonisolated private static func plan(from base: [Item]")
assert "sortedItems(captures: captures, files: files, query: query, check: { try Task.checkCancellation() })" in plan and "collection" not in plan, \
    "the plan sorts and diffs without touching the grid"
assert plan.count("try Task.checkCancellation()") >= 3, "the plan stops promptly once a newer catalog replaces it"
sorted_items = body(source, "nonisolated private static func sortedItems(")
assert "if offset % 512 == 511 { try check() }" in sorted_items, "a long search filter checks for cancellation as it goes"

apply = body(source, "private func apply(_ plan: ListPlan) {")
for needle in ("collection.performBatchUpdates({", "self.collection.deleteItems(at: plan.removed)", "self.collection.insertItems(at: plan.inserted)",
               "if plan.reload {", "completionHandler: { [weak self] _ in self?.resampleTiles() }"):
    assert needle in apply, f"apply must make only the minimal grid update: {needle}"
assert apply.count("reloadData()") == 1 and apply.index("if plan.reload {") < apply.index("reloadData()"), \
    "apply reloads the grid only for very large changes"
for gone in ("sortedItems", ".sort", "store.items", "media.items", "firstIndex", "Set(items"):
    assert gone not in apply, f"apply must not walk the list on the main thread: {gone}"

changed = body(source, "private func catalogItemsChanged() -> Bool {")
assert "store.items != observedCaptures" in changed and "media.revision != observedMediaRevision" in changed and "media.items" not in changed, \
    "catalogItemsChanged compares the media revision instead of the whole list"
status = body(source, "private func catalogStatusChanged() -> Bool {")
for needle in (
    "store.loadError != observedCaptureLoadError",
    "store.isLoading != observedCaptureLoading",
    "media.folders != observedMediaFolders",
    "media.error != observedMediaError",
    "media.isLoading != observedMediaLoading",
):
    assert needle in status, f"catalogStatusChanged no longer includes {needle}"
assert "for case let cell as CaptureLibraryCell in self.collection.visibleItems() where cell.cacheKey == item.cacheKey" in source, \
    "a finished thumbnail finds its tile among the visible cells"
assert "items.map(\\.id)" not in source, "navigation must use the planned positions"

media = (root / "Sources/ParcApp/ExternalMediaLibrary.swift").read_text()
for gone in ("makeFileSystemObjectSource", "repeating: 5", "scheduleRefresh"):
    assert gone not in media, f"the five-second poll and directory watcher are gone: {gone}"
for gone in ("presentedItemDidChangeUbiquityAttributes", "cloudPaths", "isDirectory: false), queue: callbacks"):
    assert gone not in media, f"iCloud status is watched per folder, never per file: {gone}"
for needle in ("kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagWatchRoot",
               "timer.schedule(deadline: .now() + 60, repeating: 60, leeway: .seconds(10))",
               "timer.setEventHandler { [weak self] in MainActor.assumeIsolated { self?.reconcile() } }",
               "MainActor.assumeIsolated { self?.reconcile() }",
               "func update(paths: Set<String>) throws -> Change",
               "func settle() throws -> Change",
               "if recent != nil, let previous, let next, previous.isLocal == next.isLocal { settling[key] = now; continue }",
               "guard let delay = change.settle, settleTask == nil else { return }",
               "observedPresentedItemUbiquityAttributes: Set<URLResourceKey> = [.ubiquitousItemDownloadingStatusKey]",
               "func presentedSubitemDidChange(at url: URL) { changed(url) }",
               "NSFileCoordinator.removeFilePresenter(self); evicted(self); completionHandler(nil)",
               "presentedItemURL = folder; presentedItemOperationQueue = queue",
               "guard ExternalMediaDisk.isMedia(name), aliases.contains(parent) || resolved(parent).map(aliases.contains) == true else { return nil }",
               "guard !clients.isEmpty, !folders.isEmpty else { stopCloud(); return }",
               "let known = paths.filter { index[$0] != nil }",
               "publish(snapshot.catalog); observeCloud(snapshot.catalog.cloudFolders)",
               "Catalog(items: ordered, index: current, version: version, cloudFolders: synced)",
               "if cloud.isSynced(root) { syncedRoots.insert(path) }",
               "ExternalMediaPreferenceObserver($0, key: \"location\")",
               "if refreshTask == nil { reconcile() } else { rescanPending = true }",
               "guard roots == scannedRoots, !remote, readable.allSatisfy({ Self.isReadable($0.key) == $0.value }) else { return try scan(systemFolders: systemFolders) }",
               "if let appliedVersion, catalog.version <= appliedVersion { return }",
               "func contains(_ item: ExternalMediaFile) -> Bool { index[item.id] == item }",
               "case .rescan: requestRescan()",
               "if refreshTask == nil { startRefresh(announced: false) } else { rescanPending = true }",
               "func hide(_ file: ExternalMediaFile) async throws { publish(try await disk.hide(file)) }"):
    assert needle in media, f"Media change detection no longer contains {needle}"

assert "func controlTextDidChange(_ obj: Notification) { beginUserAction(); reload(force: true) }" in source, \
    "search filter changes must force reload (not catalog-skip)"
assert 'search.stringValue = ""; reload(force: true)' in source, \
    "clearing search must force reload"
assert "reload(force: true)" in source.split("collection.setAccessibilityLabel(\"Media items\")", 1)[1][:80], \
    "initial Captures layout must force the first apply"

assert "private var presentationGeneration: UInt64 = 0" in source, \
    "missing presentation lifetime distinct from operation generation"
assert source.count("presentationGeneration &+= 1") == 1, \
    "only suspend(), which invalidate() runs first, may retire the presentation lifetime"
assert "generation &+= 1; presentationGeneration &+= 1" in body(source, "func suspend() {"), \
    "leaving Media must retire both operation and presentation work"
preview = re.search(
    r"private func openFilePreview\(.*?\n    \}\n    private func prepareFocusReturn",
    source, re.S)
assert preview and "generation &+= 1; let token = generation" in preview.group(), \
    "file preview must continue retiring only its operation work"
assert "presentationGeneration &+= 1" not in preview.group(), \
    "opening a preview must not retire the presentation lifetime"
toggle = re.search(
    r"private func changeFolder\(.*?\n    \}\n    private func chooseFolder",
    source, re.S)
assert toggle and "guard self.ownerValid() else { return }\n                self.media.refresh()" in toggle.group(), \
    "folder-toggle failure must refresh for any valid owner"
assert "self.presentationGeneration == presentation" in toggle.group(), \
    "folder-toggle error reporting must use presentation lifetime"

library = (root / "Sources/ParcApp/LibraryView.swift").read_text()
assert "if shouldSkipCatalogReload() { return }" in library, \
    "LibraryView catalog fingerprint skip missing after rebase"
downloads = (root / "Sources/ParcApp/DownloadLibraryView.swift").read_text()
assert "if !force && shouldSkipCatalogReload() { return }" in downloads, \
    "DownloadLibraryView catalog fingerprint skip missing after rebase"

suspend = body(source, "func suspend() {")
for gone in ("media.deactivate", "thumbnails", "thumbnailTasks"):
    assert gone not in suspend, f"switching Library sections keeps Media's files and thumbnails: {gone}"
for needle in ("suspend(); media.deactivate(mediaClient)", "thumbnails.reset()"):
    assert needle in invalidate, f"closing the Library releases Media's files and thumbnails: {needle}"
assert "refreshVisibleThumbnails()" in body(source, "func activate() {"), "showing Media again fills every visible tile still missing its thumbnail"
refresh = body(source, "private func refreshVisibleThumbnails(_ only: CacheKey? = nil) {")
assert "where cell.image == nil" in refresh and "contains(items[index])" in refresh and "fillThumbnail(cell, item: items[index])" in refresh, \
    "only visible tiles without a thumbnail, showing a current item, are filled when Media shows again"
assert "guard self.contains(item) else { self.thumbnails.abandon(key, ticket: ticket); self.refreshVisibleThumbnails(key); return }" in source, \
    "a load for a file whose record changed mid-load refills its tile from the current record"
assert "switch thumbnails.fill(item.cacheKey, live: ownerValid()) {" in source, "tiles filled while Media is hidden wait for it to show"
assert "self.generation == generation" not in source, "opening a preview must not throw away thumbnails that are still loading"
assert "let flow = MediaLibraryGridLayout()" in source and "itemSize" not in source, \
    "the grid layout sizes its own tiles from the width it lays out at"
rebuild = body(source, "private func rebuildItems() {")
assert "let ready = catalogReady" in rebuild and "captures: ready ? store.items : [], files: ready ? media.items : []" in rebuild, \
    "the grid waits for saved captures and the first folder scan so files never pop in around captures"
assert "catalogReady != observedCatalogReady" in changed, "the grid fills in once both catalogs are ready"
assert "hasCatalog = false; clear()" in media and "self.clear(); self.hasCatalog = true" in media and "        hasCatalog = true\n        publish(snapshot.catalog)" in media, \
    "Media reports when its first folder scan has landed"
for needle in ("privateMediaView?.suspend() } else { capturesView.suspend() }",
               "if self.kind == .downloads && kind != .downloads { downloadsView.suspend() }"):
    assert needle in library, f"switching Library sections suspends the page instead of closing it: {needle}"
assert "func suspend() { retireContext(); thumbnails.cancelPending(); suspended = true }" in downloads, \
    "leaving Downloads keeps its thumbnails"
assert "if suspended { resume() }" in body(downloads, "override func viewDidUnhide() {"), "showing Downloads again revives its rows"
assert "actionMessage = nil; retireContext(); thumbnails.cancelPending(); reload(force: true)" in downloads, \
    "typing a Downloads search keeps thumbnails instead of reloading every one"
escape = body(downloads, "    private func escape() {")
assert "retireContext(); thumbnails.cancelPending(); search.stringValue = \"\"" in escape and "invalidate()" not in escape, \
    "clearing a Downloads search with Escape keeps thumbnails"
assert "guard cell.finishedThumbnail != key else { return }" in downloads, "a row already showing its thumbnail never flashes back to its file icon"
assert "didSet { if palette != oldValue { applyPalette() } }" in downloads, "returning to Downloads with the same theme does not rebuild every row"

print("CaptureLibraryCatalogSkip: ok")
