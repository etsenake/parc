from pathlib import Path

SLICES = {
    "ThemeRenderer.swift": ("TooltipThemePalette.swift", None, "@MainActor\nenum NativeInputDiagnostics", ""),
    "KeyboardShortcuts.swift": ("TooltipKeyboardShortcut.swift", None, "@MainActor\nfinal class KeyboardShortcuts", ""),
    "ReloadControl.swift": ("TooltipFrameDriver.swift", "@MainActor final class ViewDisplayFrameDriver",
                            "@MainActor final class ReloadGlyph {", "import AppKit\n\n"),
}


def marker(text: str, name: str, value: str) -> int:
    if value not in text:
        raise SystemExit(f"tests/Tooltip/support.py: Sources/ParcApp/{name} no longer contains the slice marker {value!r}")
    return text.index(value)


def tooltip_sources(root: Path, scratch: Path, compiled) -> list:
    app = root / "Sources/ParcApp"
    names = {Path(path).name for path in compiled}
    result = [app / name for name in ("Tooltip.swift", "TooltipView.swift", "TooltipController.swift", "PointerCover.swift",
                                         "PointingHand.swift")
              if name not in names]
    if "SpaceTheme.swift" not in names:
        result.append(root / "Sources/ParcCore/SpaceTheme.swift")
    for name, (target, start, end, prefix) in SLICES.items():
        if name in names:
            continue
        text = (app / name).read_text()
        begin = marker(text, name, start) if start else 0
        path = Path(scratch) / target
        path.write_text(prefix + text[begin:marker(text, name, end)])
        result.append(path)
    return result


if __name__ == "__main__":
    import sys
    for path in tooltip_sources(Path(__file__).resolve().parents[2], Path(sys.argv[1]), sys.argv[2:]):
        print(path)
