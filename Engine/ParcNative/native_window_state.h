// Copyright 2026 Parc contributors.
#ifndef CEF_LIBCEF_BROWSER_PARC_NATIVE_NATIVE_WINDOW_STATE_H_
#define CEF_LIBCEF_BROWSER_PARC_NATIVE_NATIVE_WINDOW_STATE_H_
#include <optional>
#include <string>
#include "ui/base/mojom/window_show_state.mojom-forward.h"
class BrowserWindowInterface;
namespace gfx { class Rect; }
namespace parc {
// Validates before windows.update performs any native mutation, then
// supersedes older deferred placement work. Non-native windows
// return no error and retain their existing Chromium behavior. No page/profile
// or NSWindow is retained, and the caller still owns the actual update route.
std::optional<std::string> PrepareNativeWindowStateUpdate(
    BrowserWindowInterface& browser,
    ui::mojom::WindowShowState state,
    const gfx::Rect* bounds);
}  // namespace parc
#endif
