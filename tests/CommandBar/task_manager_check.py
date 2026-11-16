#!/usr/bin/env python3
from pathlib import Path
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tests/Support"))
from window_sources import browser_window_controller_source

root = Path(__file__).resolve().parents[2]
app = root / "Sources/ParcApp"
checks = 0


def flat(text):
    return " ".join(text.split())


controller = flat(browser_window_controller_source(app))
delegate = flat((app / "AppDelegate.swift").read_text())
bridge = flat((root / "Engine/ParcNative/native_appkit_bridge.h").read_text())
engine = flat((root / "Engine/ParcNative/native_appkit_page.mm").read_text())


def expect(condition, message):
    global checks
    assert condition, message
    checks += 1


def body(source, signature):
    start = source.index(signature)
    depth, i = 0, source.index("{", start)
    for j in range(i, len(source)):
        depth += {"{": 1, "}": -1}.get(source[j], 0)
        if depth == 0:
            return source[start:j + 1]
    raise AssertionError(f"unterminated {signature}")


def case(source, name):
    return source.split(f"case .{name}:", 1)[1].split(" case .", 1)[0]


listing = body(controller, "private func commandBarTypedCommands(")
expect("guard !isPopupWindow else { return [] }" in listing, "pop-up windows still list no typed commands")
expect(".init(kind: .openTaskManager)" in listing, "Task Manager is listed in the typed commands")
expect("taskmanager" not in listing.lower().replace(".opentaskmanager", ""),
       "Task Manager is always listed and filtered live, never gated when the bar opens")
available = case(body(controller, "private func typedCommandIsAvailable("), "openTaskManager")
expect("return canOpenTaskManager" in available and ".taskManager" not in available,
       "the typed command is offered whenever the window can open Task Manager")
prepared = case(body(controller, "private func prepareTypedCommand("), "openTaskManager")
expect("let browser" not in prepared.replace("let browser = currentBrowser", "") and ".taskManager" not in prepared
       and "self.currentBrowser === browser" in prepared and "self.openTaskManager()" in prepared,
       "the typed command runs without a page and keeps its original target")

route = body(controller, "private var taskManagerRoute: TaskManagerRoute?")
expect("showsNativePage: currentBrowser?.nativePage != nil" in route and "pageCanOpen: canPerformPageTool(.taskManager)" in route,
       "a showing page keeps the page route")
guard_call = "responds(to: #selector(PCNativeBrowserWindow.openTaskManager))"
expect(guard_call in route and route.index(guard_call) < route.index(".canOpenTaskManager"),
       "the window route is offered only by an engine that has it")
opener = body(controller, "func openTaskManager() -> Bool")
expect("switch taskManagerRoute" in opener and "currentBrowser?.performPageTool(.taskManager)" in case(opener, "page")
       and "nativeBinding?.openTaskManager()" in case(opener, "window"), "opening takes the route availability chose")
expect("var canOpenTaskManager: Bool { taskManagerRoute != nil }" in controller, "availability and opening share one route")

window_menu = delegate[delegate.index('let window = menu("Window")'):delegate.index('let help = menu("Help")')]
expect(delegate.count("TaskManagerMenu.add(") == 1 and "TaskManagerMenu.add(to: window, target: self, shortcuts: .shared)" in window_menu,
       "the Window menu has one Task Manager item")
expect("if item.action == TaskManagerMenu.action { return front?.canOpenTaskManager ?? false }" in delegate,
       "the menu item is enabled whenever the front window can open Task Manager")
expect("@objc private func openTaskManager(_ sender: Any?) { front?.openTaskManager() }" in delegate,
       "the menu item opens Task Manager through the front window")

declaration = bridge.split("@interface PCNativeBrowserWindow (TaskManager)", 1)[1].split("@end", 1)[0]
expect("BOOL canOpenTaskManager;" in declaration and "- (BOOL)openTaskManager;" in declaration, "the engine declares the window route")
implementation = engine.split("@implementation PCNativeBrowserWindow (TaskManager)", 1)[1].split("@end", 1)[0]
availability, opening = implementation.split("- (BOOL)openTaskManager", 1)
for condition in ("NativeProfileRemovalApplicationReady()", "window.keyWindow", "!window.attachedSheet"):
    expect(condition in availability, f"the window route requires {condition}")
expect(opening.index("self.canOpenTaskManager") < opening.index("chrome::OpenTaskManager(nullptr,"),
       "the window route validates before opening Task Manager without a page or Profile")
expect("case PCNativePageToolTaskManager: return IDC_TASK_MANAGER_MAIN_MENU;" in engine,
       "the page route still runs Chromium's main-menu command")
print(f"task_manager_check: {checks} checks passed")
