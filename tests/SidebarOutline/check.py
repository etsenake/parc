#!/usr/bin/env python3
from pathlib import Path
import re
import subprocess
import tempfile
root = Path(__file__).resolve().parents[2]
with tempfile.TemporaryDirectory(prefix="parc-sidebar-outline-") as directory:
    scratch = Path(directory)
    sidebar = (root / "Sources/ParcApp/SidebarView.swift").read_text()
    for removed in ("list.addArrangedSubview", "list.arrangedSubviews", ".selectedChildrenChanged", "SidebarOutlineEntry("):
        assert removed not in sidebar, f"SidebarView bypasses the outline: {removed}"
    hand_built = [key for key in re.findall(r"outline\.append\(\.init\(key: ([\w.]+)", sidebar) if not key.startswith("SidebarListRow.")]
    assert not hand_built, f"items reach the outline only through its checked entry helpers: {hand_built}"
    assert "outline.append(.pinnedHeader(SidebarListRow.pinnedHeader))" in sidebar, "SidebarView builds its pinned header row without the checked entry"
    assert "button?.activate?()" not in sidebar, "a folder row's AXDisclosing runs the folder click"
    def body(start, end):
        assert sidebar.count(start) == 1, f"SidebarView moved its accessibility selection: {start}"
        begin = sidebar.index(start)
        return sidebar[begin:sidebar.index(end, begin)]
    handler = body("    private func selectFromAccessibility(", "    private func applySelectionMarks(")
    refresh = body("    private func refreshItemSelection(", "    private func selectFromAccessibility(")
    marks = body("    private func applySelectionMarks(", "    private func selectItem(")
    wiring = body("        page.list.allowsAccessibilitySelection = {", "        page.view.passesThrough = true")
    toggle = body('NSAccessibilityCustomAction(name: "Add or Remove from Selection")', "        let actions = ")
    activations = ("onSelectTab", "activateSingleSelection", "Activation", "onSplitTab", "onToggleFolder", "selectTab(",
                   "onPreview", "focusSelectionList", "focusIfPresented", "makeFirstResponder", "onNewTab")
    for name, path in (("selectFromAccessibility", handler), ("refreshItemSelection", refresh), ("applySelectionMarks", marks),
                       ("the outline wiring", wiring), ("Add or Remove from Selection", toggle)):
        found = [word for word in activations if word in path]
        assert not found, f"an accessibility selection path in {name} can activate an item or move focus: {found}"
    for use in ("guard window?.isKeyWindow == true, canSelectItems?() == true else { return false }",
                "guard next.assign(items, order: selectionOrder, active: selectionActive) else { return false }",
                "itemSelection = next\n        refreshItemSelection()\n        return true"):
        assert use in handler, f"selectFromAccessibility no longer guards, assigns and refreshes the selection: {use}"
    assert "list.select(itemSelection.shown(active: selectionActive))" in refresh, \
        "refreshItemSelection reports the model's shown selection to the outline"
    assert "view.setAccessibilitySelected(itemSelection.shown(active: selectionActive).contains(item))" in marks, \
        "item views report the same selection as their rows"
    assert "page === self.shownPage && self.canSelectItems != nil" in wiring \
        and "guard let self, let page, page === self.shownPage else { return false }\n            return self.selectFromAccessibility(items)" in wiring, \
        "only the shown Space's outline offers and takes selection, through the non-activating path"
    assert "guard let self, self.selectionOrder.contains(item) else { return false }" in toggle \
        and "return self.selectFromAccessibility(shown.contains(item) ? shown.filter { $0 != item } : shown + [item])" in toggle, \
        "Add or Remove from Selection toggles the shown selection through the same non-activating path"
    assert sidebar.count("selectsFromAccessibility") == 1 and sidebar.count("allowsAccessibilitySelection") == 1 \
        and sidebar.count("selectFromAccessibility(") == 3, \
        "accessibility selection reaches SidebarView only through its outline wiring and the row action"
    rendering = body("    func render(state: BrowserState, focusedTabID: UUID?, loading: Set<UUID>,", "    private func pinnedPresentation(")
    assert rendering.count("itemSelection.clear()") == 1 and "if activeItem != selectionActive { itemSelection.clear() }" in rendering \
        and "itemSelection.reconcile(order: selectionOrder, active: selectionActive)\n        refreshItemSelection()" in rendering, \
        "background hierarchy changes trim a selection instead of clearing it; only a new current item clears it"
    assert "if dropped { clearItemSelection() }\n        return dropped" in body("    override func performDragOperation(", "\n    }\n"), \
        "any drop into the sidebar ends its selection, as the selected-rows moves do"
    setters = re.compile(r"func (setAccessibilitySelected|setAccessibilitySelectedRows|setAccessibilitySelectedChildren|"
                         r"accessibilitySetValue|setAccessibilitySelectedCells)\b")
    owners = sorted(path.name for path in list((root / "Sources/ParcApp").glob("Sidebar*.swift"))
                    + [root / "Sources/ParcApp/SplitDragView.swift"] if setters.search(path.read_text()))
    assert owners == ["SidebarOutline.swift"], f"only the outline takes accessibility selection in the sidebar: {owners}"
    store = (root / "Sources/ParcCore/BrowserStore.swift").read_text()
    reference = re.search(r"^enum SidebarItemReference\b.*?^\}\n", store, re.S | re.M)
    assert reference, "SidebarItemReference not found in BrowserStore.swift"
    selection = re.search(r"^struct SidebarItemSelection\b.*?^\}\n", store, re.S | re.M)
    assert selection, "SidebarItemSelection not found in BrowserStore.swift"
    (scratch / "SidebarItemReference.swift").write_text("import Foundation\n" + reference.group(0) + selection.group(0))
    (scratch / "ActionButton.swift").write_text(
        "import AppKit\nenum SplitOrientation: Equatable { case horizontal, vertical }\n"
        + sidebar[:sidebar.index("final class MenuAction")])
    executable = scratch / "checks"
    subprocess.run(["xcrun", "swiftc", str(root / "tests/Support/TestFailure.swift"), "-warnings-as-errors", "-parse-as-library", "-target", "arm64-apple-macos13.0",
                    str(root / "Sources/ParcCore/SidebarOutlineConfigureSkip.swift"),
                    str(root / "Sources/ParcApp/SidebarOutline.swift"),
                    str(root / "Sources/ParcApp/SidebarChromeLayout.swift"),
                    str(scratch / "SidebarItemReference.swift"),
                    str(scratch / "ActionButton.swift"),
                    str(root / "Sources/ParcApp/TranslucentButtonFace.swift"), str(root / "Sources/ParcApp/PointerCover.swift"),
                    str(root / "Sources/ParcApp/ReloadControl.swift"), str(root / "Sources/ParcApp/PointingHand.swift"),
                    str(Path(__file__).with_name("SidebarOutlineTests.swift")), "-o", str(executable)], check=True)
    subprocess.run([str(executable)], check=True)
