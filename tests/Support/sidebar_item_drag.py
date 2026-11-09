#!/usr/bin/env python3
"""sidebar_item_drag.py <scratch directory> [files the check already compiles...]

Prints SidebarItemDrag.swift and the sources it needs: its folder row builds on
the row appearance, the folder icon, the tooltips and two small SidebarView
declarations (cut by tests/Support/declarations.py)."""
import pathlib
import subprocess
import sys

root = pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0, str(root / "tests/Tooltip"))
from support import tooltip_sources

scratch = pathlib.Path(sys.argv[1])
app = root / "Sources/ParcApp"
controls = scratch / "SidebarItemDragControls.swift"
subprocess.run([sys.executable, "-B", str(root / "tests/Support/declarations.py"), str(controls), "SidebarChromeLabel", "parcInk"],
               check=True, stdout=subprocess.DEVNULL)
sources = [app / f"{name}.swift" for name in ("SidebarItemDrag", "SidebarRowAppearance", "SidebarFolderIcon", "SidebarIconCatalog",
                                              "SidebarTitleField", "SidebarRowActionButton")] + [controls]
compiled = {pathlib.Path(path).name for path in sys.argv[2:]}
sources = [path for path in sources if path.name not in compiled]
sources += tooltip_sources(root, scratch, [*sys.argv[2:], *sources])
print("\n".join(map(str, sources)))
