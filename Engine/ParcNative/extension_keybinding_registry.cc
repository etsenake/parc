// Copyright 2026 Parc contributors.
#include "extension_keybinding_registry.h"

#include <utility>

#include "base/check.h"
#include "chrome/browser/extensions/commands/command_service.h"
#include "chrome/browser/extensions/extension_commands_global_registry.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/tab_list/tab_list_interface.h"
#include "chrome/browser/ui/browser_window/public/browser_window_interface.h"
#include "content/public/browser/browser_thread.h"
#include "extensions/common/extension.h"
#include "ui/content_accelerators/accelerator_util.h"

namespace parc {
namespace {
TabListInterface* RequireTabList(BrowserWindowInterface& browser) {
  DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
  auto* tabs = TabListInterface::From(&browser);
  CHECK(tabs);
  return tabs;
}
}  // namespace

NativeExtensionKeybindingRegistry::NativeExtensionKeybindingRegistry(
    BrowserWindowInterface& browser,
    ActionDispatcher dispatch_action)
    : ExtensionKeybindingRegistry(browser.GetProfile(),
                                  RequireTabList(browser),
                                  ALL_EXTENSIONS),
      dispatch_action_(std::move(dispatch_action)) {
  CHECK(dispatch_action_);
  Init();
}

NativeExtensionKeybindingRegistry::~NativeExtensionKeybindingRegistry() {
  OnHostActivationChanged(false);
}

bool NativeExtensionKeybindingRegistry::PopulateCommands(
    const extensions::Extension* extension,
    ui::CommandMap* commands) {
  DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
  // Follow CommandService's real success contract. In particular, don't invert
  // successful population and discard active commands (see evidence README).
  return extensions::CommandService::Get(browser_context())
      ->GetNamedCommands(extension->id(), extensions::CommandService::ACTIVE,
                         extensions::CommandService::REGULAR, commands);
}

bool NativeExtensionKeybindingRegistry::RegisterAccelerator(
    const ui::Accelerator& accelerator,
    const extensions::ExtensionId& extension_id,
    const std::string& command_name) {
  DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
  accelerators_.insert(accelerator);
  return true;
}

void NativeExtensionKeybindingRegistry::UnregisterAccelerator(
    const ui::Accelerator& accelerator) {
  DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
  accelerators_.erase(accelerator);
}

bool NativeExtensionKeybindingRegistry::DispatchKeyboardEvent(
    const input::NativeWebKeyboardEvent& event) {
  DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
  if (event.skip_if_unhandled) {
    return false;
  }
  //
  // windows_key_code, translated modifier flags, KeyUp -> RELEASED, timestamp.
  // It preserves repeat metadata without making repeat a different shortcut.
  return DispatchAccelerator(
      ui::GetAcceleratorFromNativeWebKeyboardEvent(event));
}

bool NativeExtensionKeybindingRegistry::DispatchAccelerator(
    const ui::Accelerator& accelerator) {
  DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
  if (!browser_context() || shortcut_handling_suspended()) {
    return false;
  }

  // An action can synchronously close its window. Retain the callback state and
  // never touch this object after it is destroyed by the delegate.
  auto weak_this = weak_factory_.GetWeakPtr();
  ActionDispatcher dispatch = dispatch_action_;
  if (dispatch.Run(accelerator)) {
    return true;
  }
  if (!weak_this || !browser_context() || shortcut_handling_suspended() ||
      !accelerators_.contains(accelerator)) {
    return false;
  }
  return NotifyEventTargets(accelerator);
}

void NativeExtensionKeybindingRegistry::OnHostActivationChanged(bool active) {
  DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
  // The base shutdown notifier clears browser_context() if profile shutdown
  // precedes destruction; never recreate a service using a stale Profile.
  if (!browser_context()) {
    return;
  }
  auto* global =
      extensions::ExtensionCommandsGlobalRegistry::Get(browser_context());
  if (!global) {
    return;
  }
  //
  // conditional activation rule. A deactivation cannot erase another registry's
  // selection.
  if (active) {
    global->set_registry_for_active_window(this);
  } else if (global->registry_for_active_window() == this) {
    global->set_registry_for_active_window(nullptr);
  }
}

}  // namespace parc
