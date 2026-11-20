#!/usr/bin/env python3
from pathlib import Path
import re

root = Path(__file__).resolve().parents[2]
source = (root / "Sources/ParcApp/DocumentsLibraryView.swift").read_text()

assert "private var observedNotes: [NoteReference] = []" in source, \
    "missing last-applied notes catalog snapshot"
assert "private var observedEasels: [EaselSummary] = []" in source, \
    "missing last-applied easels catalog snapshot"
assert "private var observedProfileRemovalPending = false" in source, \
    "missing last-applied profile-removal pending snapshot"
assert "private func shouldSkipCatalogReload(notes: [NoteReference], easels: [EaselSummary], pending: Bool, query: String) -> Bool" in source, \
    "shouldSkipCatalogReload predicate missing"
assert "private func rememberAppliedCatalog(notes: [NoteReference], easels: [EaselSummary], pending: Bool, query: String)" in source, \
    "rememberAppliedCatalog missing"

reload = re.search(
    r"func reload\(force: Bool = false\) \{(?P<body>.*?)\n    \}\n\n    private func shouldSkipCatalogReload\(notes:",
    source, re.S)
assert reload, "reload(force:) not found"
body = reload.group("body")
gate = "if !force && shouldSkipCatalogReload(notes: notes, easels: easels, pending: pending, query: query) { return }"
remember = "rememberAppliedCatalog(notes: notes, easels: easels, pending: pending, query: query)"
assert gate in body, "identical catalog must return before search/sort when not forced"
assert remember in body, "changed/forced catalog must record last apply before rebuild"
assert body.index(gate) < body.index(remember), "skip gate must precede rememberAppliedCatalog"
assert body.index(remember) < body.index("library.search(") < body.index("DocumentsLibraryCatalog.visible("), \
    "remember must precede the note search and the catalog filter/sort"

skip = re.search(
    r"private func shouldSkipCatalogReload\(notes: \[NoteReference\], easels: \[EaselSummary\], pending: Bool, query: String\) -> Bool \{(?P<body>.*?)\n    \}\n\n    private func rememberAppliedCatalog",
    source, re.S)
assert skip, "shouldSkipCatalogReload body not found"
skip_body = skip.group("body")
for needle in (
    "notes == observedNotes",
    "easels == observedEasels",
    "pending == observedProfileRemovalPending",
    "query == observedQuery",
):
    assert needle in skip_body, f"Documents fingerprint no longer includes {needle}"

assert "func controlTextDidChange(_ obj: Notification) { reload(force: true) }" in source, \
    "search filter changes must force reload (not catalog-skip)"
assert 'search.stringValue = ""; reload(force: true)' in source, \
    "clearing search must force reload"
assert "            bindLibrary()\n        }\n        reload(force: true)\n    }" in source, \
    "initial Documents layout must force the first apply"
assert "subscription = next.changes.sink { [weak self] in self?.reload() }" in source, \
    "NoteLibrary.changes must still sink through the unforced reload path"
assert "self?.bindLibrary(); self?.reload(force: true)" in source, \
    "a new Notes folder must rebind the library and force a reload"

library = (root / "Sources/ParcApp/LibraryView.swift").read_text()
assert "if shouldSkipCatalogReload() { return }" in library, \
    "LibraryView catalog fingerprint skip missing after rebase"
downloads = (root / "Sources/ParcApp/DownloadLibraryView.swift").read_text()
assert "if !force && shouldSkipCatalogReload() { return }" in downloads, \
    "DownloadLibraryView catalog fingerprint skip missing after rebase"

print("DocumentsLibraryCatalogSkip: ok")
