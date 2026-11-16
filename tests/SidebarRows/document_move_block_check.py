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

sharing = body((root / "Sources/ParcApp/SpaceSharingConfirmation.swift").read_text(), "static func present(")
early = sharing.index("store.sharingDocumentBlock(forSpace: spaceID, to: sharing)")
expect(sharing.index("valid() else") < early < sharing.index("store.sharingWarning(") < sharing.index("ParcDialog("),
       "a data change looks for blocking entries before the sharing warning")
expect("explain(block); completion(.success(false)); return" in sharing[early:sharing.index("store.sharingWarning(")],
       "a blocked data change explains itself and asks nothing")
late = sharing.index("store.changeSharing(")
expect("if change == nil, let block = store.sharingDocumentBlock(forSpace: spaceID, to: sharing) { explain(block) }" in sharing[late:],
       "a data change refused after the warning still explains blocking entries")
expect(sharing.count("store.sharingDocumentBlock(") == 2 and "NSSound.beep()" not in sharing,
       "other refusals of a data change stay quiet, as before")
expect("if let block = store.sharingDocumentBlock(" in sharing[:early + 60]
       and "guard let warning = store.sharingWarning(forSpace: spaceID, to: sharing) else { completion(.success(false)); return }" in sharing
       and "store.changeSharing(ofSpace: spaceID, to: sharing, shouldCommit: stillWarned)" in sharing,
       "without blocking entries the warning and the change run exactly as before")

menu = body(controller, "func spaceManagementMenu(")
expect("ownerValid: ownerValid, explain: { [weak self] block in" in menu
       and menu.index("guard let self, ownerValid() else { return }") < menu.index("self.showDocumentMoveBlock(block)"),
       "Space menus explain a blocked data change with the window notice, only while the window still owns it")

settings = (root / "Sources/ParcApp/SettingsWindow.swift").read_text()
chosen = body(settings, "@objc private func shareDataChosen(")
expect(chosen.index("refusedSharing = nil; renderShareDataNote()") < chosen.index("SpaceSharingConfirmation.present("),
       "a new data choice clears the previous explanation")
expect("self.refusedSharing = (space.id, sharing)" in chosen and ".announcementRequested" in chosen,
       "Settings keeps the refused choice and announces the explanation")
note = body(settings, "private func renderShareDataNote(")
expect("editedSpace?.id == refused.spaceID ? store.sharingDocumentBlock(" in note and "block?.message" in note,
       "Settings shows the explanation only while it is still true for the edited Space")
expect("renderShareDataNote()" in body(settings, "func refresh() {"), "every Settings refresh rechecks the explanation")
watch = note[note.index("refusedSharingSubscription = store.statePublisher"):]
expect("$0.tabs == $1.tabs" in watch and "self.renderShareDataNote()" in watch,
       "a held explanation also rechecks when tabs change, which a Settings refresh does not watch")
expect("refusedSharingSubscription = nil" in note[:note.index("refusedSharingSubscription = store.statePublisher")]
       and "refusedSharing = nil; refusedSharingSubscription = nil" in body(settings, "func windowWillClose("),
       "the tab watch ends with the explanation and when Settings closes")
layout = body(settings, "private func layoutSpaceCards(")
expect(layout.index("shareDataNote") < layout.index("for (title, group) in layout.sections"),
       "the explanation sits right under the Share data with row")

print(f"document move block checks: {checks} passed")
