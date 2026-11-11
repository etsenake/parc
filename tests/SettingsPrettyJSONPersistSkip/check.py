#!/usr/bin/env python3
from pathlib import Path
import re

root = Path(__file__).resolve().parents[2]
skip = (root / "Sources/ParcCore/SettingsPrettyJSONPersistSkip.swift").read_text()
routing = (root / "Sources/ParcCore/LinkRouting.swift").read_text()
shortcuts = (root / "Sources/ParcApp/KeyboardShortcuts.swift").read_text()

assert "enum SettingsPrettyJSONPersistSkip" in skip, "SettingsPrettyJSONPersistSkip helper missing"
assert "static func shouldSkip(previous: Data?, next: Data) -> Bool" in skip, \
    "shouldSkip predicate missing"
assert "previous == next" in skip, "shouldSkip must be a true identical-bytes no-op"

assert "private var lastWrittenBytes: Data?" in routing, \
    "LinkRoutingStore missing lastWrittenBytes"
assert "SettingsPrettyJSONPersistSkip.shouldSkip(previous: lastWrittenBytes, next: data)" in routing, \
    "LinkRoutingStore.commit must gate on SettingsPrettyJSONPersistSkip"
assert "encoder.outputFormatting = [.prettyPrinted, .sortedKeys]" in routing, \
    "link-routing must keep pretty/sorted encode"
assert "try data.write(to: file, options: .atomic)" in routing, \
    "changed link-routing bytes must still atomically write"

commit = re.search(
    r"private func commit\(_ next: LinkRoutingState\) -> Bool \{(?P<body>.*?)\n    \}\n\}",
    routing, re.S)
assert commit, "LinkRoutingStore.commit missing"
body = commit.group("body")
assert "SettingsPrettyJSONPersistSkip.shouldSkip(" in body, \
    "commit must consult shouldSkip before write"
assert body.index("encoder.encode(next)") < body.index("SettingsPrettyJSONPersistSkip.shouldSkip("), \
    "encode must happen before the skip gate"
assert body.index("SettingsPrettyJSONPersistSkip.shouldSkip(") < body.index("data.write(to: file"), \
    "identical bytes must skip before atomic write"
assert "lastWrittenBytes = data" in body, \
    "successful write must record lastWrittenBytes"

assert "private var lastWrittenBytes: Data?" in shortcuts, \
    "KeyboardShortcuts missing lastWrittenBytes"
assert "SettingsPrettyJSONPersistSkip.shouldSkip(previous: lastWrittenBytes, next: data)" in shortcuts, \
    "KeyboardShortcuts.commit must gate on SettingsPrettyJSONPersistSkip"

shortcut_commit = re.search(
    r"private func commit\(_ next: \[String: Override\], priorities nextPriorities: \[String: Priority\]\? = nil\) throws \{(?P<body>.*?)\n    \}\n",
    shortcuts, re.S)
assert shortcut_commit, "KeyboardShortcuts.commit missing"
sbody = shortcut_commit.group("body")
assert "encoder.outputFormatting = [.prettyPrinted, .sortedKeys]" in sbody, \
    "keyboard-shortcuts must keep pretty/sorted encode"
assert sbody.index("encoder.encode(Document(") < sbody.index("SettingsPrettyJSONPersistSkip.shouldSkip("), \
    "encode must happen before the skip gate"
assert sbody.index("SettingsPrettyJSONPersistSkip.shouldSkip(") < sbody.index("data.write(to: fileURL"), \
    "identical bytes must skip before atomic write"
assert "lastWrittenBytes = data" in sbody, \
    "successful shortcut write must record lastWrittenBytes"
assert "apply(); didChange()" in sbody, \
    "real shortcut changes must still apply and publish"
assert sbody.index("SettingsPrettyJSONPersistSkip.shouldSkip(") < sbody.index("apply(); didChange()"), \
    "identical shortcut bytes must skip before apply/didChange"

print("SettingsPrettyJSONPersistSkip: identical pretty JSON bytes skip; changes still write")
