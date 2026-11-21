#!/usr/bin/env python3
from pathlib import Path
import re

root = Path(__file__).resolve().parents[2]
source = (root / "Sources/ParcApp/DocumentsLibraryView.swift").read_text()

catalog = (root / "Sources/ParcApp/DocumentsLibraryCatalog.swift").read_text()
fingerprint = re.search(r"struct DocumentsLibraryInputs: Equatable \{(?P<body>.*?)\n\}", catalog, re.S)
assert fingerprint, "missing the Documents catalog fingerprint"
for field in ("let notes: [NoteReference]", "let easels: [EaselSummary]", "let pending: Bool", "let query: String",
              "let noteMatches: [URL]"):
    assert field in fingerprint.group("body"), f"Documents fingerprint no longer includes {field}"
assert "private var observedInputs: DocumentsLibraryInputs?" in source, \
    "missing last-applied catalog snapshot"

reload = re.search(r"func reload\(force: Bool = false\) \{(?P<body>.*?)\n    \}\n", source, re.S)
assert reload, "reload(force:) not found"
body = reload.group("body")
gate = "if !force && inputs == observedInputs { return }"
remember = "observedInputs = inputs"
assert gate in body, "identical catalog must return before filter/sort when not forced"
assert body.index("DocumentsLibraryCatalog.inputs(") < body.index(gate) < body.index(remember), \
    "skip gate must follow the fingerprint and precede remembering it"
assert body.index(remember) < body.index("DocumentsLibraryCatalog.visible(") < body.index("if !sameCards { rebuildCards() }"), \
    "remember must precede the catalog filter/sort and the card rebuild"
assert body.count("observedInputs = nil") == 2, "an empty or failed apply must forget the last snapshot"

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
