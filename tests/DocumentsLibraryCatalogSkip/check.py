#!/usr/bin/env python3
"""P1-F leftover: DocumentsLibraryView skips reload when the Documents-visible
catalog fingerprint already matches the last applied snapshot. NoteStore.changes
still sinks while Documents is open; true no-op duplicate admissions return
before filter/sort/rebuild. Real note/easel list, persist, membership, profile
removal pending, and search (force) changes still reload.
"""
from pathlib import Path
import re

root = Path(__file__).resolve().parents[2]
source = (root / "Sources/ParcApp/DocumentsLibraryView.swift").read_text()

assert "private var observedNotes: [NoteDocument] = []" in source, \
    "missing last-applied notes catalog snapshot"
assert "private var observedEasels: [EaselSummary] = []" in source, \
    "missing last-applied easels catalog snapshot"
assert "private var observedProfileRemovalPending = false" in source, \
    "missing last-applied profile-removal pending snapshot"
assert "private func shouldSkipCatalogReload(notes: [NoteDocument], easels: [EaselSummary], pending: Bool) -> Bool" in source, \
    "shouldSkipCatalogReload predicate missing"
assert "private func rememberAppliedCatalog(notes: [NoteDocument], easels: [EaselSummary], pending: Bool)" in source, \
    "rememberAppliedCatalog missing"

reload = re.search(
    r"func reload\(force: Bool = false\) \{(?P<body>.*?)\n    \}\n\n    /// True when this view already applied the Documents-visible",
    source, re.S)
assert reload, "reload(force:) not found"
body = reload.group("body")
assert "if !force && shouldSkipCatalogReload(notes: notes, easels: easels, pending: pending) { return }" in body, \
    "identical catalog must return before filter/sort when not forced"
assert "rememberAppliedCatalog(notes: notes, easels: easels, pending: pending)" in body, \
    "changed/forced catalog must record last apply before rebuild"
assert body.index("if !force && shouldSkipCatalogReload(notes: notes, easels: easels, pending: pending) { return }") < body.index(
    "rememberAppliedCatalog(notes: notes, easels: easels, pending: pending)"), \
    "skip gate must precede rememberAppliedCatalog"
assert body.index("rememberAppliedCatalog(notes: notes, easels: easels, pending: pending)") < body.index(
    "notes.map"), \
    "remember must precede filter/sort from listed notes"

skip = re.search(
    r"private func shouldSkipCatalogReload\(notes: \[NoteDocument\], easels: \[EaselSummary\], pending: Bool\) -> Bool \{(?P<body>.*?)\n    \}\n\n    private func rememberAppliedCatalog",
    source, re.S)
assert skip, "shouldSkipCatalogReload body not found"
skip_body = skip.group("body")
for needle in (
    "notes == observedNotes",
    "easels == observedEasels",
    "pending == observedProfileRemovalPending",
):
    assert needle in skip_body, f"Documents fingerprint no longer includes {needle}"

assert "func controlTextDidChange(_ obj: Notification) { reload(force: true) }" in source, \
    "search filter changes must force reload (not catalog-skip)"
assert 'search.stringValue = ""; reload(force: true)' in source, \
    "clearing search must force reload"
assert "reload(force: true)" in source.split("catch { empty.stringValue = error.localizedDescription }", 1)[-1][:120], \
    "initial Documents layout must force the first apply"
assert ".changes.sink { [weak self] in self?.reload() }" in source, \
    "NoteStore.changes must still sink through the unforced reload path"

# Sibling Library/Downloads fingerprint gates must remain across rebase.
library = (root / "Sources/ParcApp/LibraryView.swift").read_text()
assert "if shouldSkipCatalogReload() { return }" in library, \
    "LibraryView catalog fingerprint skip missing after rebase"
downloads = (root / "Sources/ParcApp/DownloadLibraryView.swift").read_text()
assert "if !force && shouldSkipCatalogReload() { return }" in downloads, \
    "DownloadLibraryView catalog fingerprint skip missing after rebase"

print("DocumentsLibraryCatalogSkip: ok")
