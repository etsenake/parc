#!/usr/bin/env python3
from pathlib import Path
import re

root = Path(__file__).resolve().parents[2]
source = (root / "Sources/ParcApp/CaptureLibraryView.swift").read_text()

assert "private var observedCaptures: [SavedCapture] = []" in source, \
    "missing last-applied captures catalog snapshot"
assert "private var observedMediaItems: [ExternalMediaFile] = []" in source, \
    "missing last-applied media items snapshot"
assert "private var observedMediaFolders: [ExternalMediaFolder] = []" in source, \
    "missing last-applied media folders snapshot"
assert "private func catalogItemsChanged() -> Bool" in source, \
    "catalogItemsChanged predicate missing"
assert "private func catalogStatusChanged() -> Bool" in source, \
    "catalogStatusChanged predicate missing"
assert "private func rememberAppliedCatalog()" in source, \
    "rememberAppliedCatalog missing"

reload = re.search(
    r"private func reload\(force: Bool = false\) \{(?P<body>.*?)\n    \}\n\n    private func rebuildItems\(\) \{(?P<rebuild>.*?)\n    \}\n\n    private func catalogItemsChanged\(\) -> Bool \{(?P<items>.*?)\n    \}\n\n    private func catalogStatusChanged\(\) -> Bool \{(?P<status>.*?)\n    \}\n\n    private func rememberAppliedCatalog",
    source, re.S)
assert reload, "reload(force:), rebuildItems() and catalog predicates not found in order"
body, rebuild = reload.group("body"), reload.group("rebuild")
items, status = reload.group("items"), reload.group("status")
gate = "let rebuild = force || catalogItemsChanged()"
skip = "if !rebuild && !catalogStatusChanged() { return }"
for needle in (gate, skip, "rememberAppliedCatalog()", "if rebuild { rebuildItems() }", "guard rebuild else { return }"):
    assert needle in body, f"reload(force:) no longer contains {needle}"
assert body.index(gate) < body.index(skip) < body.index("rememberAppliedCatalog()") < body.index("if rebuild { rebuildItems() }"), \
    "identical catalogs must return before recording, and recording must precede the rebuild"
assert body.index("if rebuild { rebuildItems() }") < body.index("guard rebuild else { return }") < body.index("preview?.reconcile()"), \
    "status-only changes must update the message without reconciling previews"
assert "store.items.map" in rebuild and "next.sort" in rebuild and "store.items.map" not in body, \
    "only rebuildItems() may map, filter and sort the catalog"
assert "isLoading" not in items and "error" not in items and "folders" not in items, \
    "loading, error and folder changes must not rebuild the grid list"
for needle in ("store.items != observedCaptures", "media.items != observedMediaItems"):
    assert needle in items, f"catalogItemsChanged no longer includes {needle}"
for needle in (
    "store.loadError != observedCaptureLoadError",
    "store.isLoading != observedCaptureLoading",
    "media.folders != observedMediaFolders",
    "media.error != observedMediaError",
    "media.isLoading != observedMediaLoading",
):
    assert needle in status, f"catalogStatusChanged no longer includes {needle}"

media = (root / "Sources/ParcApp/ExternalMediaLibrary.swift").read_text()
assert "if let self, self.refreshTask == nil { self.startRefresh(announced: false) }" in media, \
    "the periodic Media rescan must stay quiet and skip while a refresh is running"
assert "MainActor.assumeIsolated { self?.startRefresh(announced: false) }" in media, \
    "app activation must rescan Media quietly"
assert "if snapshot.itemsChanged { self.items = snapshot.items }" in media, \
    "Media must publish its list only when the background scan found a change"

assert "func controlTextDidChange(_ obj: Notification) { beginUserAction(); reload(force: true) }" in source, \
    "search filter changes must force reload (not catalog-skip)"
assert 'search.stringValue = ""; reload(force: true)' in source, \
    "clearing search must force reload"
assert "reload(force: true)" in source.split("collection.setAccessibilityLabel(\"Media items\")", 1)[1][:80], \
    "initial Captures layout must force the first apply"

assert "private var presentationGeneration: UInt64 = 0" in source, \
    "missing presentation lifetime distinct from operation generation"
assert source.count("presentationGeneration &+= 1") == 1, \
    "only invalidate() may retire the presentation lifetime"
assert "generation &+= 1; presentationGeneration &+= 1" in source, \
    "invalidate() must retire both operation and presentation work"
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

print("CaptureLibraryCatalogSkip: ok")
