// Copyright 2026 Parc contributors.
#ifndef PARC_NATIVE_EXTENSION_KEYBINDING_REGISTRY_H_
#define PARC_NATIVE_EXTENSION_KEYBINDING_REGISTRY_H_

#include <set>

#include "base/functional/callback.h"
#include "base/memory/weak_ptr.h"
#include "chrome/browser/extensions/extension_keybinding_registry.h"
#include "ui/base/accelerators/accelerator.h"

class BrowserWindowInterface;
namespace input {
struct NativeWebKeyboardEvent;
}

namespace parc {

// The native BrowserWindow owns this service and destroys it before its
// Browser, Profile and TabListInterface. All calls are on Chromium's UI thread.
// This is the native registration/dispatch boundary, not an extension
// action/popup presenter.
//
//
// without FocusManager, tries action controllers first, then calls Chromium's
// shared named-command dispatcher. Keep that dispatcher responsible for real
// activeTab grants, tab serialization, user gestures and profile isolation.
class NativeExtensionKeybindingRegistry final
    : public extensions::ExtensionKeybindingRegistry {
 public:
  // Required: query this window's real extension action controllers and return
  // true only when they handled the accelerator. It must honor their enabled
  // state and correct action invocation source. A placeholder that always
  // returns false is not a complete production integration.
  using ActionDispatcher =
      base::RepeatingCallback<bool(const ui::Accelerator&)>;

  NativeExtensionKeybindingRegistry(BrowserWindowInterface& browser,
                                    ActionDispatcher dispatch_action);
  ~NativeExtensionKeybindingRegistry() override;
  NativeExtensionKeybindingRegistry(const NativeExtensionKeybindingRegistry&) =
      delete;
  NativeExtensionKeybindingRegistry& operator=(
      const NativeExtensionKeybindingRegistry&) = delete;

  // BrowserWindow calls this at the post-renderer boundary, after the native
  // menu and Chromium's DevTools forwarding. Preserve the event's real key,
  // modifiers, phase and timestamp; never derive a shortcut from text. IME
  // events marked skip_if_unhandled must not trigger either command route.
  bool DispatchKeyboardEvent(const input::NativeWebKeyboardEvent& event);

  // Preconverted accelerator entry also used by focused service tests.
  // Suspension applies to both action and named-command dispatch.
  bool DispatchAccelerator(const ui::Accelerator& accelerator);

  // Call after initial browser registration and whenever key-window/selected
  // browser ownership changes. A stale resign event must not clear a newer
  // browser's active registry, including another browser sharing an NSWindow.
  void OnHostActivationChanged(bool active);

 private:
  bool PopulateCommands(const extensions::Extension* extension,
                        ui::CommandMap* commands) override;
  bool RegisterAccelerator(const ui::Accelerator& accelerator,
                           const extensions::ExtensionId& extension_id,
                           const std::string& command_name) override;
  void UnregisterAccelerator(const ui::Accelerator& accelerator) override;

  ActionDispatcher dispatch_action_;
  // Extension IDs and command names remain solely in the upstream event-target
  // map. This native set records platform registration, not a second router.
  std::set<ui::Accelerator> accelerators_;
  base::WeakPtrFactory<NativeExtensionKeybindingRegistry> weak_factory_{this};
};

}  // namespace parc
#endif  // PARC_NATIVE_EXTENSION_KEYBINDING_REGISTRY_H_
