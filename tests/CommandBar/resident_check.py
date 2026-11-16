#!/usr/bin/env python3
from pathlib import Path
import re
import subprocess
import tempfile

root = Path(__file__).resolve().parents[2]
app = root / "Sources/ParcApp"
source = (app / "CommandBar.swift").read_text()


def body(name):
    match = re.search(rf"^    (?:private )?func {name}\(.*?^    }}\n", source, re.S | re.M)
    assert match, f"CommandBar.{name} is missing"
    return match.group(0)


lifetime = body("observeLifetime")
for event in ("resignedKey(ownAlert: $0.ownsAttachedSheet)", "focusMoved", "closing", "miniaturizing",
              "sheetBegan(ownAlert: $0.scopeAlert != nil)", "securityChanged", "appDeactivated", "resized", "moved"):
    assert f"respond(to: .{event})" in lifetime, f"a window event no longer asks the lifetime policy: {event}"
assert "dismiss(" not in lifetime and "position()" not in lifetime, "a window event bypasses the lifetime policy"
assert body("present").count("observeLifetime(of: parent)") == 1, "the palette no longer watches its window"
resident = body("presentResident")
assert "observeLifetime(of: parent)" in resident and "slot.addSubview(host" in resident, "the resident bar is not hosted in its slot"
assert "showsShadow = false\n        container.flatFill = true" in resident, "the resident card no longer sits flat on the page"
assert "makeFirstResponder" not in resident and "makeKey" not in resident, "presenting the resident bar takes focus"
assert "guard !resident else { return }" in body("present"), "a resident bar can be presented as an overlay"

respond = body("respond")
for case in ("case .keep: break", "case .reposition: position()", "case .retireScopeMenu: retireScopeMenu()",
             "case .leaveScope: leaveScope()", "case .reset: resetResident()", "case .resetForAction: releaseForAction()",
             "case .dismiss: dismiss(restoreFocus: false)", "case .dismissRestoringFocus: dismiss()"):
    assert case in respond, f"the lifetime responses changed: {case}"
calls = [m.start() for m in re.finditer(r"(?<![\w.])dismiss\(", source)]
assert len(calls) == 4, f"an unexpected teardown outside the lifetime policy: {len(calls)} calls"
assert source.count("else { dismiss(restoreFocus: false); return }") == 1, "only the palette's present guard may dismiss directly"
assert source.count("respond(to: .escape(scoped: isScoped || scopeInvalidated))") == 2, "Escape bypasses the lifetime policy"
submit = body("submitResult")
assert submit.count("respond(to: .submitted)") == 3 and "dismiss(" not in submit, "a submission bypasses the lifetime policy"
assert "refocusAfterAction()" in submit, "a resident submission no longer hands focus back"
assert source.count("guard isOwnerValid?() != false else { respond(to: .ownerInvalid); return }") == 2
assert "guard self.isOwnerValid?() != false else { self.respond(to: .ownerInvalid); return }" in source
assert "guard !dismissed, isOwnerValid?() != false else { respond(to: .ownerInvalid); return }" in body("submitSelection")
assert body("leaveScope").count("respond(to: .scopeExitFailed)") == 2, "a failed scope exit bypasses the lifetime policy"

refresh = body("refreshResults")
rest = "if resident, CommandBarResidentLayout.rests(query: query, scoped: isScoped, scopeInvalidated: scopeInvalidated) {"
assert refresh.index("if nativeHold.isHolding { return }") < refresh.index(rest) \
    < refresh.index("let fingerprint = openResultsFingerprint(query: query)"), "the resting bar can list empty-query results"
assert "if isScoped || scopeInvalidated || resident { position() }" in refresh, "results no longer resize the resident bar"
assert "results = []" in body("restResidentResults"), "resting no longer clears the rows"
position = body("position")
assert position.index("applyAppearance()\n        if resident {") < position.index("let available ="), "the resident bar is placed like an overlay"
for use in ("CommandBarResidentLayout.height(expanded: residentExpanded, rows: results.count, banner: banner)",
            "CommandBarResidentLayout.surfaceFrame(in: slot, height: height)"):
    assert use in position, f"the resident geometry moved: {use}"
assert "|| (resident && !residentExpanded) {\n            emptyLabel.isHidden = true; scroll.isHidden = true; divider.isHidden = true" \
    in body("layoutScopeHeader"), "a collapsed resident bar shows its result area"
assert "static var residentRestHeight: CGFloat { CommandBarResidentLayout.restHeight }" in source
reset = body("resetResident")
assert "editState.edit(\"\")" in reset and "input.stringValue = \"\"" in reset and "refreshResults(requestNative: false)" in reset

host = re.search(r"^private final class CommandBarHost: NSView \{.*?^\}\n", source, re.S | re.M)
assert host, "CommandBarHost is missing"
host_source = "import AppKit\n" + host.group(0).replace("private final class", "final class", 1)
sources = [app / "CommandBarResidentLayout.swift", app / "CommandBarResidentLifetime.swift",
           root / "Sources/ParcCore/CommandBarOpenResultsSkip.swift"]


def build(directory, name, replace=None):
    files = list(sources)
    host_text = host_source
    if replace:
        target, old, new = replace
        if target == "Host":
            assert old in host_text, f"negative control no longer matches the host: {old}"
            host_text = host_text.replace(old, new)
        else:
            text = (app / target).read_text()
            assert old in text, f"negative control no longer matches {target}: {old}"
            changed = Path(directory) / f"{name}-{target}"
            changed.write_text(text.replace(old, new))
            files = [changed if path == app / target else path for path in files]
    host_file = Path(directory) / f"{name}-Host.swift"
    host_file.write_text(host_text)
    executable = Path(directory) / name
    subprocess.run(["xcrun", "swiftc", str(root / "tests/Support/TestFailure.swift"), "-warnings-as-errors", "-parse-as-library", "-target", "arm64-apple-macos13.0",
                    *map(str, files), str(host_file), str(Path(__file__).with_name("ResidentTests.swift")),
                    "-o", str(executable)], check=True)
    return executable


with tempfile.TemporaryDirectory(prefix="parc-resident-command-bar-") as directory:
    subprocess.run([str(build(directory, "check"))], check=True)
    controls = {
        "uncapped growth": (("CommandBarResidentLayout.swift", "min(max(rows, 1), visibleRows)", "max(rows, 1)"),
                            "results stay capped at five visible rows"),
        "bottom-anchored growth": (("CommandBarResidentLayout.swift", "y: slot.maxY - fitted", "y: slot.minY"),
                                   "the top edge stays at the slot's top"),
        "empty-query lists": (("CommandBarResidentLayout.swift", "return resultCount > 0", "return true"),
                              "at rest only the field shows"),
        "self-dismissal": (("CommandBarResidentLifetime.swift",
                            "case .focusMoved, .miniaturizing, .appDeactivated, .ownerInvalid: return resident ? .keep : .dismiss",
                            "case .focusMoved, .miniaturizing, .appDeactivated, .ownerInvalid: return .dismiss"),
                           "the resident bar never dismisses itself"),
        "dismissing Escape": (("CommandBarResidentLifetime.swift", "resident ? .reset : .dismissRestoringFocus\n        case .scopeExitFailed",
                               ".dismissRestoringFocus\n        case .scopeExitFailed"),
                              "Escape clears and collapses"),
        "palette regression": (("CommandBarResidentLifetime.swift", "scoped ? .leaveScope : resident ? .reset : .dismissRestoringFocus",
                                "scoped ? .leaveScope : resident ? .reset : .dismiss"),
                               "the palette still answers escape(scoped: false)"),
        "captured mouse": (("Host", "bar?.hitTest(convert(point, from: superview))",
                            "bar?.hitTest(convert(point, from: superview)) ?? self"),
                           "the slot below the card passes the mouse through"),
    }
    for name, (replace, failure) in controls.items():
        result = subprocess.run([str(build(directory, name.replace(" ", "-"), replace))], capture_output=True, text=True)
        assert result.returncode != 0 and failure in result.stderr, f"negative control did not fail: {name}\n{result.stderr[-1000:]}"
        print(f"Resident negative control fails as expected: {name}")
