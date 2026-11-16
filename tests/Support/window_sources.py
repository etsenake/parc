from pathlib import Path


def browser_window_controller_paths(app):
    app = Path(app)
    return [app / "BrowserWindowController.swift", *sorted(app.glob("BrowserWindowController+*.swift")), app / "BrowserPane.swift"]


def browser_window_controller_source(app):
    return "".join(path.read_text() for path in browser_window_controller_paths(app))
