#!/usr/bin/env python3
from pathlib import Path
import re
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tests/Support"))
from window_sources import browser_window_controller_source

root = Path(__file__).resolve().parents[2]
controller = (root / "Sources/ParcApp/PeekController.swift").read_text()
skip = (root / "Sources/ParcCore/PeekPresentationSkip.swift").read_text()
window = browser_window_controller_source(root / "Sources/ParcApp")

assert "enum PeekPresentationSkip" in skip, "PeekPresentationSkip helper missing"
assert "static func shouldSkip(previous: String?, next: String) -> Bool" in skip, \
    "shouldSkip predicate missing"
assert "previous == next" in skip, "shouldSkip must be a true identical-fingerprint no-op"
assert "static func fingerprint(" in skip, "fingerprint helper missing"
for needle in (
    "title:",
    "url:",
    "loading:",
    "canGoBack:",
    "canGoForward:",
    "closePending:",
    "canExpand:",
    "canSplit:",
    "splitToolTip:",
    "capture:",
    "crash:",
    "favicon:",
):
    assert needle in skip, f"fingerprint no longer includes {needle}"

assert "private var lastPresentedFingerprint: String?" in controller, \
    "missing last-applied Peek presentation fingerprint"
assert "private func publishPresentationIfChanged()" in controller, \
    "missing publishPresentationIfChanged gate"
assert "private func presentationFingerprint()" in controller, \
    "missing live presentationFingerprint builder"
assert "PeekPresentationSkip.shouldSkip(previous: lastPresentedFingerprint, next: fingerprint)" in controller, \
    "refresh must gate on PeekPresentationSkip.shouldSkip"
assert "if refresh() { onUpdate?() }" in controller, \
    "publish must notify only after a changed refresh"

for selector in (
    "func browserView(_ view: PCBrowserView, didChangeTitle title: String)",
    "func browserView(_ view: PCBrowserView, didChangeURL url: URL)",
    "func browserView(_ view: PCBrowserView, didChangeLoading loading: Bool, canGoBack: Bool, canGoForward: Bool)",
    "func browserView(_ view: PCBrowserView, didChangeCaptureState state: PCNativeCaptureState?)",
    "func browserView(_ view: PCBrowserView, didChangeRendererCrash crash: PCNativeRendererCrash?)",
    "func browserViewDidChangeFavicon(_ view: PCBrowserView)",
):
    match = re.search(re.escape(selector) + r" \{(?P<body>[^}]*)\}", controller)
    assert match, f"{selector} missing"
    body = match.group("body")
    assert "publishPresentationIfChanged()" in body, \
        f"{selector} must publish through the fingerprint gate"
    assert "refresh(); onUpdate?()" not in body, \
        f"{selector} must not unconditionally refresh+onUpdate"
    assert body.count("onUpdate?()") == 0, \
        f"{selector} must not call onUpdate outside publishPresentationIfChanged"

assert "self?.view.confirmationTitle = nil\n                self?.onUpdate?()" in controller, \
    "dismissal confirmation expiry must still call onUpdate ungated"
assert re.search(
    r'view\.confirmationTitle = hangUp \? "Hang up" : "Close"\n'
    r'.*?\n\s+onUpdate\?\(\)',
    controller, re.S), \
    "dismissal confirmation request must still call onUpdate ungated"
assert "if closePending { onUpdate?() }" in controller, \
    "dismissal-start owners must still observe closePending via onUpdate"

assert "func browserView(_ view: PCBrowserView, requestFocusForRendererCrash crash: PCNativeRendererCrash) { refresh(); focus() }" in controller, \
    "renderer-crash focus must still refresh then focus"

peek_wire = re.search(
    r"peek\.onUpdate = \{ \[weak self\] in self\?\.(?P<fn>\w+)\(\) \}",
    window)
assert peek_wire, "peek.onUpdate wiring missing"
assert peek_wire.group("fn") in ("refreshLivePageChromeOrRender", "updateNavigation"), \
    "peek.onUpdate must still reach live chrome / navigation"
assert "PeekPresentationSkip" not in window, \
    "Peek skip must not move onto the BrowserWindowController onUpdate bridge"


def function_body(text, start, end="\n    }\n"):
    assert text.count(start) == 1, f"expected one {start!r}"
    begin = text.index(start)
    return text[begin:text.index(end, begin)]


assert "splitToolTip: presentedSplitToolTip," in controller and "view.splitToolTip = presentedSplitToolTip" in controller, \
    "the split reason must change the fingerprint and reach the Split button's tooltip"
assert "private var presentedSplitToolTip: String? { closePending ? nil : splitToolTip?() }" in controller, \
    "a closing Peek shows the plain Split tooltip"
assert "LiveShortcutToolTip.set(splitButton, splitToolTip ?? Self.splitTitle, anchor: .trailing)" in controller \
    and 'private static let splitTitle = "Add Peek to Split View"' in controller, \
    "without a reason the Split button keeps its usual name"

tab_wiring = function_body(window, "    private func wireTabPeek(")
tab_rule = function_body(window, "    private func tabPeekSplitRefusal(")
for blocker in ("splitCommandsAvailable", "activePeek == nil", "spaceCommandsAvailable"):
    assert blocker not in tab_wiring + tab_rule, \
        f"a tab-backed Peek's Split button must not wait for {blocker!r}, which is off while its own Peek shows"
assert "self.tabPeekSplitRefusal(controller, tabID: heldID, parentID: parent) == nil" in tab_wiring \
    and "self.tabPeekSplitRefusal(controller, tabID: heldID, parentID: parent)?.toolTip" in tab_wiring, \
    "a tab-backed Peek's Split button and its tooltip follow one rule"
for token in ("controller.canInteract?() == true", "switcherCanUse(tabID)", "visibleTabs.contains { $0.id == tabID }",
              "selectedTabIDs.contains(parentID)", "facts.panes = selectedTabIDs.count", "!isPopupWindow",
              "presentation.isReady", "nativeFullscreenTabID == nil", "libraryView == nil", "transferringTabIDs.isEmpty",
              "(selectedTabIDs.count == 1 || activeSplitLayout != nil)",
              "TabPeekSplit.refusal(facts)"):
    assert token in tab_rule, f"the tab-backed split rule lost {token!r}"

ordinary = function_body(window, "    func wirePeek(")
assert """        peek.canSplit = { [weak self, weak peek] in
            guard let self, let peek else { return false }
            return self.activePeek === peek && self.selectedTabIDs.contains(id)
                && self.selectedTabIDs.count < 4 && self.nativeFullscreenTabID == nil
        }""" in ordinary and "splitToolTip" not in ordinary, "an ordinary Peek keeps today's Split rule and tooltip"

assert "func openTabInSplitView(_ id: UUID) -> Bool { selectTab(id, extendingSplit: true) }" in window, \
    "the card's Split View action opens the tab beside the current page"
assert "            case .split: openTabInSplitView(id)\n" in function_body(window, "    private func performSidebarPreview("), \
    "the preview card's Split View uses the shared action"
assert "let selected = split ? openTabInSplitView(id) : selectTab(id)" in function_body(window, "    func promoteTabPeek(split: Bool) {"), \
    "a tab-backed Peek's Split button uses the card's Split View action"
assert "if let shown = tabPeek?.shownController { _ = shown.refresh() }" in function_body(window, "    func layoutPeeks() {"), \
    "a tab-backed Peek's buttons follow the window's layout like an ordinary Peek's"

print("PeekPresentationSkip check passed")
