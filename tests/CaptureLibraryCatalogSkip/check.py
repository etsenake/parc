#!/usr/bin/env python3
"""P1-F leftover: CaptureLibraryView skips reload when the Captures-visible
catalog fingerprint already matches the last applied snapshot. combineLatest
on store/media @Published still sinks while Captures is open; true no-op
duplicate admissions return before filter/sort/rebuild. Real capture list,
media membership, folder access, loading/error, and search (force) changes
still reload.
"""
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
assert "private func shouldSkipCatalogReload() -> Bool" in source, \
    "shouldSkipCatalogReload predicate missing"
assert "private func rememberAppliedCatalog()" in source, \
    "rememberAppliedCatalog missing"

reload = re.search(
    r"private func reload\(force: Bool = false\) \{(?P<body>.*?)\n    \}\n\n    private func shouldSkipCatalogReload\(\) -> Bool \{",
    source, re.S)
assert reload, "reload(force:) not found"
body = reload.group("body")
assert "if !force && shouldSkipCatalogReload() { return }" in body, \
    "identical catalog must return before filter/sort when not forced"
assert "rememberAppliedCatalog()" in body, \
    "changed/forced catalog must record last apply before rebuild"
assert body.index("if !force && shouldSkipCatalogReload() { return }") < body.index(
    "rememberAppliedCatalog()"), \
    "skip gate must precede rememberAppliedCatalog"
assert body.index("rememberAppliedCatalog()") < body.index("store.items.map"), \
    "remember must precede filter/sort from store.items"

skip = re.search(
    r"private func shouldSkipCatalogReload\(\) -> Bool \{(?P<body>.*?)\n    \}\n\n    private func rememberAppliedCatalog",
    source, re.S)
assert skip, "shouldSkipCatalogReload body not found"
skip_body = skip.group("body")
for needle in (
    "store.items == observedCaptures",
    "store.loadError == observedCaptureLoadError",
    "store.isLoading == observedCaptureLoading",
    "media.items == observedMediaItems",
    "media.folders == observedMediaFolders",
    "media.error == observedMediaError",
    "media.isLoading == observedMediaLoading",
):
    assert needle in skip_body, f"Captures fingerprint no longer includes {needle}"

assert "func controlTextDidChange(_ obj: Notification) { beginUserAction(); reload(force: true) }" in source, \
    "search filter changes must force reload (not catalog-skip)"
assert 'search.stringValue = ""; reload(force: true)' in source, \
    "clearing search must force reload"
assert "reload(force: true)" in source.split("collection.setAccessibilityLabel(\"Media items\")", 1)[1][:80], \
    "initial Captures layout must force the first apply"

# A preview advances work generation to retire in-flight preview work, but it
# does not retire the Library presentation. Folder-toggle recovery must
# therefore refresh whenever its owner remains valid, while error reporting
# uses the presentation lifetime that only invalidate() advances.
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

# Sibling Library/Downloads fingerprint gates must remain across rebase.
library = (root / "Sources/ParcApp/LibraryView.swift").read_text()
assert "if shouldSkipCatalogReload() { return }" in library, \
    "LibraryView catalog fingerprint skip missing after rebase"
downloads = (root / "Sources/ParcApp/DownloadLibraryView.swift").read_text()
assert "if !force && shouldSkipCatalogReload() { return }" in downloads, \
    "DownloadLibraryView catalog fingerprint skip missing after rebase"

print("CaptureLibraryCatalogSkip: ok")
