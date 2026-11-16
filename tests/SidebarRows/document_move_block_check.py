#!/usr/bin/env python3
from pathlib import Path
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tests/Support"))
from window_sources import browser_window_controller_source
root = Path(__file__).resolve().parents[2]
controller = browser_window_controller_source(root / "Sources/ParcApp")
checks = 0


def body(source, signature):
    start = source.index(signature)
    depth, i = 0, source.index("{", start)
    for j in range(i, len(source)):
        depth += {"{": 1, "}": -1}.get(source[j], 0)
        if depth == 0:
            return source[start:j + 1]
    raise AssertionError(f"unterminated {signature}")


def expect(condition, message):
    global checks
    assert condition, message
    checks += 1


confirm = body(controller, "func confirmInterProfileMove(")
expect(confirm.index("InterProfileDocumentBlock(moving: ids") < confirm.index("InterProfileMoveGate.resolve("),
       "the blocking entries are found before the gate decides whether to ask")
expect("blocked: block != nil" in confirm, "the gate learns about blocking entries")
blocked = confirm.index("case .blocked:")
expect(blocked < confirm.index("case .confirm:") < confirm.index("InterProfileMoveDialog(prompt:"),
       "a blocked move explains itself instead of showing the data warning")
expect("showDocumentMoveBlock(block)" in confirm[blocked:confirm.index("case .proceed:")]
       and "return false" in confirm[blocked:confirm.index("case .proceed:")],
       "a blocked move shows the explanation and reports that nothing moved")

notice = body(controller, "func showDocumentMoveBlock(")
expect("showToast(.standard(block.title, subLabel: block.message), at: .window)" in notice,
       "the explanation uses the window notice beside the move notice")
refused = body(controller, "func explainRefusedInterProfileMove(")
expect(refused.index("InterProfileDocumentBlock(") < refused.index("NSSound.beep()") < refused.index("showDocumentMoveBlock(block)"),
       "a late refusal explains blocking entries and keeps the beep for other refusals")

paths = {
    "window drop": "private func prepareInterProfileWindowDrop(",
    "Space icon drop": "func prepareSidebarDockDrop(",
    "Move To": "private func prepareInterProfileSpaceMove(",
    "split drop": "func beginForeignSplitDrop(",
    "Space into folder": "private func turnSpaceIntoFolder(",
}
for name, signature in paths.items():
    source = body(controller, signature)
    call = source[source.index("confirmInterProfileMove("):]
    expect("moving:" in call[:call.index("{")] and "proposal:" in call[:call.index("{")],
           f"{name} hands the move to the before-confirmation check")
    expect("case .success(false): self.explainRefusedInterProfileMove(" in source
           and "case .success(false): NSSound.beep()" not in source,
           f"{name} explains a refusal instead of only beeping")

creation = body(controller, "private func commitSpaceCreation(")
expect(creation.index("documentMoveBlock(session.draft)") < creation.index("store.createSpace("),
       "New Space checks blocking entries before it commits")
expect(creation.count("showError(block.message)") == 2, "New Space shows the explanation in its own form, before and after")

print(f"document move block checks: {checks} passed")
