#!/usr/bin/env python3
from pathlib import Path

root = Path(__file__).resolve().parents[2]
tools = (root / "Sources/ParcApp/BrowserWindowController+PageTools.swift").read_text()
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


available = body(tools, "controller.canPerformCommand = {")
expect("switch self.essentialsCopyRoute" in available, "availability follows the same route as the copy itself")
expect("page.canCopyURL(fromCommandWindow: commandWindow, browser: binding)" in available
       and "let commandWindow = controller?.window" in available,
       "a page's Copy is offered only when the engine's command-window copy check admits it")
expect("isHiddenOrHasHiddenAncestor" not in available, "visibility alone no longer decides availability")
command = body(tools, "controller.onCommand = {")
copy = command[command.index('case "copyCurrentURL:":'):command.index('case "split:":')]
expect("switch self.essentialsCopyRoute" in copy
       and "page.copyURL(fromCommandWindow: commandWindow, browser: binding, completion: completion)" in copy,
       "the copy runs through the same command-window admission it was offered with")
print(f"Essentials Copy availability: {checks} checks passed")
