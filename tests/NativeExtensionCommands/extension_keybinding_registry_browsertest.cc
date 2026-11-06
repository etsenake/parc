// Copyright 2026 Parc contributors.
// Link this into Chromium browser_tests with the real native registry source.
#include "extension_keybinding_registry.h"

#include <memory>
#include <string>
#include <vector>

#include "base/functional/bind.h"
#include "base/test/bind.h"
#include "chrome/browser/browser_process.h"
#include "chrome/browser/extensions/commands/command_service.h"
#include "chrome/browser/extensions/extension_apitest.h"
#include "chrome/browser/extensions/extension_commands_global_registry.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/profiles/profile_manager.h"
#include "chrome/browser/profiles/profile_test_util.h"
#include "chrome/browser/ui/browser.h"
#include "chrome/browser/ui/browser_tabstrip.h"
#include "chrome/browser/ui/tabs/tab_strip_model.h"
#include "components/input/native_web_keyboard_event.h"
#include "components/sessions/content/session_tab_helper.h"
#include "content/public/test/browser_test.h"
#include "content/public/test/browser_test_utils.h"
#include "extensions/browser/event_router.h"
#include "extensions/browser/permissions/active_tab_permission_granter.h"
#include "extensions/browser/test_event_router_observer.h"
#include "extensions/common/extension.h"
#include "extensions/test/extension_test_message_listener.h"
#include "extensions/test/test_extension_dir.h"
#include "net/test/embedded_test_server/embedded_test_server.h"

namespace parc {
namespace {
constexpr char kCommand[] = "parc-test-command";
constexpr char kEvent[] = "commands.onCommand";

NativeExtensionKeybindingRegistry::ActionDispatcher NoActionForTest() {
  // Tests isolate named dispatch. Production must supply its actual action
  // controller, not this testing callback.
  return base::BindRepeating([](const ui::Accelerator&) { return false; });
}
}  // namespace

class NativeExtensionCommandsBrowserTest : public extensions::ExtensionApiTest {
 protected:
  const extensions::Extension* LoadFixture() {
    fixture_.WriteManifest(R"({
      "name":"Parc native command fixture", "version":"1.0",
      "manifest_version":3, "permissions":["activeTab"],
      "background":{"service_worker":"background.js"}, "action":{},
      "commands":{
        "parc-test-command":{"suggested_key":{"default":"Alt+Shift+Y"},
                             "description":"Native command test"},
        "_execute_action":{"suggested_key":{"default":"Alt+Shift+U"}}
      }
    })");
    fixture_.WriteFile(FILE_PATH_LITERAL("background.js"), R"(
      chrome.commands.onCommand.addListener(() => {
        chrome.test.sendMessage("command_received");
      });
      chrome.test.sendMessage("ready");
    )");
    ExtensionTestMessageListener ready("ready");
    auto* extension = LoadExtension(fixture_.UnpackedPath());
    if (extension) {
      EXPECT_TRUE(ready.WaitUntilSatisfied());
    }
    return extension;
  }

  ui::Accelerator AcceleratorFor(const extensions::Extension& extension,
                                 const std::string& name = kCommand) {
    return extensions::CommandService::Get(profile())
        ->FindCommandByName(extension.id(), name)
        .accelerator();
  }

  extensions::TestExtensionDir fixture_;
};

IN_PROC_BROWSER_TEST_F(NativeExtensionCommandsBrowserTest,
                       DispatchUsesRealActiveTabAndUserGesture) {
  ASSERT_TRUE(embedded_test_server()->Start());
  const auto* extension = LoadFixture();
  ASSERT_TRUE(extension);
  NativeExtensionKeybindingRegistry registry(*browser(), NoActionForTest());
  const auto accelerator = AcceleratorFor(*extension);
  ASSERT_TRUE(registry.IsAcceleratorRegistered(accelerator));

  auto* tabs = browser()->tab_strip_model();
  auto* first = tabs->GetActiveWebContents();
  ASSERT_TRUE(content::NavigateToURL(
      first, embedded_test_server()->GetURL("/title1.html")));
  chrome::AddTabAt(browser(), GURL("about:blank"), -1, true);
  auto* active = tabs->GetActiveWebContents();
  ASSERT_NE(first, active);
  ASSERT_TRUE(content::NavigateToURL(
      active, embedded_test_server()->GetURL("/title2.html")));
  auto* first_granter =
      extensions::ActiveTabPermissionGranter::FromWebContents(first);
  auto* active_granter =
      extensions::ActiveTabPermissionGranter::FromWebContents(active);
  ASSERT_TRUE(first_granter);
  ASSERT_TRUE(active_granter);
  EXPECT_FALSE(first_granter->IsGranted(extension));
  EXPECT_FALSE(active_granter->IsGranted(extension));

  extensions::TestEventRouterObserver events(
      extensions::EventRouter::Get(profile()));
  ExtensionTestMessageListener received("command_received");
  EXPECT_TRUE(registry.DispatchAccelerator(accelerator));
  EXPECT_TRUE(received.WaitUntilSatisfied());
  EXPECT_TRUE(active_granter->IsGranted(extension));
  EXPECT_FALSE(first_granter->IsGranted(extension));
  ASSERT_TRUE(events.events().contains(kEvent));
  const auto& event = *events.events().at(kEvent);
  EXPECT_EQ(extensions::EventRouter::UserGestureState::kEnabled,
            event.user_gesture);
  EXPECT_EQ(profile(), event.restrict_to_browser_context);
  ASSERT_EQ(2u, event.args().size());
  EXPECT_EQ(kCommand, event.args()[0].GetString());
  EXPECT_EQ(sessions::SessionTabHelper::IdForTab(active).id(),
            event.args()[1].GetDict().FindInt("id"));
}

IN_PROC_BROWSER_TEST_F(NativeExtensionCommandsBrowserTest,
                       LoadRemapUnloadUpdatesLocalRegistration) {
  // Construct first to exercise load observation, not just Init's enumeration.
  NativeExtensionKeybindingRegistry registry(*browser(), NoActionForTest());
  const auto* extension = LoadFixture();
  ASSERT_TRUE(extension);
  const auto old_key = AcceleratorFor(*extension);
  ASSERT_TRUE(registry.IsAcceleratorRegistered(old_key));
  auto released = old_key;
  released.set_key_state(ui::Accelerator::KeyState::RELEASED);
  EXPECT_FALSE(registry.DispatchAccelerator(released));
  // Action commands remain outside the regular base event-target map.
  EXPECT_FALSE(registry.IsAcceleratorRegistered(
      AcceleratorFor(*extension, "_execute_action")));

  extensions::CommandService::Get(profile())->UpdateKeybindingPrefs(
      extension->id(), kCommand, "Alt+Shift+G");
  const auto new_key = AcceleratorFor(*extension);
  ASSERT_NE(old_key, new_key);
  EXPECT_FALSE(registry.IsAcceleratorRegistered(old_key));
  EXPECT_FALSE(registry.DispatchAccelerator(old_key));
  EXPECT_TRUE(registry.IsAcceleratorRegistered(new_key));
  ExtensionTestMessageListener received("command_received");
  EXPECT_TRUE(registry.DispatchAccelerator(new_key));
  EXPECT_TRUE(received.WaitUntilSatisfied());

  const std::string id = extension->id();
  UnloadExtension(id);
  EXPECT_FALSE(registry.IsAcceleratorRegistered(new_key));
  EXPECT_FALSE(registry.DispatchAccelerator(new_key));
}

IN_PROC_BROWSER_TEST_F(NativeExtensionCommandsBrowserTest,
                       NativeEventsProtectIMEAndPreserveCommandIdentity) {
  const auto* extension = LoadFixture();
  ASSERT_TRUE(extension);
  NativeExtensionKeybindingRegistry registry(*browser(), NoActionForTest());
  input::NativeWebKeyboardEvent event(
      blink::WebInputEvent::Type::kRawKeyDown,
      blink::WebInputEvent::kAltKey | blink::WebInputEvent::kShiftKey,
      base::TimeTicks::Now());
  event.windows_key_code = ui::VKEY_Y;
  // Translated text may differ under a keyboard layout; command identity uses
  // the real virtual key, rather than reinterpreting the text buffer.
  event.text[0] = u'z';
  event.unmodified_text[0] = u'z';
  extensions::TestEventRouterObserver events(
      extensions::EventRouter::Get(profile()));
  event.skip_if_unhandled = true;
  EXPECT_FALSE(registry.DispatchKeyboardEvent(event));
  EXPECT_FALSE(events.events().contains(kEvent));
  event.skip_if_unhandled = false;
  event.SetType(blink::WebInputEvent::Type::kKeyUp);
  EXPECT_FALSE(registry.DispatchKeyboardEvent(event));
  EXPECT_FALSE(events.events().contains(kEvent));
  event.SetType(blink::WebInputEvent::Type::kRawKeyDown);
  ExtensionTestMessageListener received("command_received");
  EXPECT_TRUE(registry.DispatchKeyboardEvent(event));
  EXPECT_TRUE(received.WaitUntilSatisfied());
  ASSERT_TRUE(events.events().contains(kEvent));
  EXPECT_EQ(kCommand, events.events().at(kEvent)->args()[0].GetString());
}

IN_PROC_BROWSER_TEST_F(NativeExtensionCommandsBrowserTest,
                       NativeActionEventsRetainPhaseRepeatAndTime) {
  std::vector<ui::Accelerator> delivered;
  NativeExtensionKeybindingRegistry registry(
      *browser(), base::BindLambdaForTesting([&](const ui::Accelerator& value) {
        delivered.push_back(value);
        return true;
      }));
  const auto time = base::TimeTicks::Now();
  input::NativeWebKeyboardEvent event(
      blink::WebInputEvent::Type::kRawKeyDown,
      blink::WebInputEvent::kMetaKey | blink::WebInputEvent::kControlKey |
          blink::WebInputEvent::kAltKey | blink::WebInputEvent::kShiftKey |
          blink::WebInputEvent::kIsAutoRepeat,
      time);
  event.windows_key_code = ui::VKEY_G;
  event.skip_if_unhandled = true;
  EXPECT_FALSE(registry.DispatchKeyboardEvent(event));
  EXPECT_TRUE(delivered.empty());
  event.skip_if_unhandled = false;
  registry.SetShortcutHandlingSuspended(true);
  EXPECT_FALSE(registry.DispatchKeyboardEvent(event));
  EXPECT_TRUE(delivered.empty());
  registry.SetShortcutHandlingSuspended(false);
  EXPECT_TRUE(registry.DispatchKeyboardEvent(event));
  ASSERT_EQ(1u, delivered.size());
  EXPECT_EQ(ui::VKEY_G, delivered[0].key_code());
  EXPECT_EQ(ui::EF_COMMAND_DOWN | ui::EF_CONTROL_DOWN | ui::EF_ALT_DOWN |
                ui::EF_SHIFT_DOWN | ui::EF_IS_REPEAT,
            delivered[0].modifiers());
  EXPECT_EQ(ui::Accelerator::KeyState::PRESSED, delivered[0].key_state());
  EXPECT_EQ(time, delivered[0].time_stamp());
  event.SetType(blink::WebInputEvent::Type::kKeyUp);
  EXPECT_TRUE(registry.DispatchKeyboardEvent(event));
  ASSERT_EQ(2u, delivered.size());
  EXPECT_EQ(ui::Accelerator::KeyState::RELEASED, delivered[1].key_state());
  EXPECT_EQ(time, delivered[1].time_stamp());
}

IN_PROC_BROWSER_TEST_F(NativeExtensionCommandsBrowserTest,
                       ActionsPrecedeRegularCommandsAndSuspensionCoversBoth) {
  const auto* extension = LoadFixture();
  ASSERT_TRUE(extension);
  const auto key = AcceleratorFor(*extension);
  bool action_handles = true;
  int action_attempts = 0;
  NativeExtensionKeybindingRegistry registry(
      *browser(), base::BindLambdaForTesting([&](const ui::Accelerator& value) {
        ++action_attempts;
        EXPECT_EQ(key, value);
        return action_handles;
      }));
  extensions::TestEventRouterObserver events(
      extensions::EventRouter::Get(profile()));
  EXPECT_TRUE(registry.DispatchAccelerator(key));
  EXPECT_EQ(1, action_attempts);
  EXPECT_FALSE(events.events().contains(kEvent));

  registry.SetShortcutHandlingSuspended(true);
  EXPECT_FALSE(registry.DispatchAccelerator(key));
  EXPECT_EQ(1, action_attempts);
  action_handles = false;
  registry.SetShortcutHandlingSuspended(false);
  ExtensionTestMessageListener received("command_received");
  EXPECT_TRUE(registry.DispatchAccelerator(key));
  EXPECT_TRUE(received.WaitUntilSatisfied());
  EXPECT_EQ(2, action_attempts);
}

IN_PROC_BROWSER_TEST_F(NativeExtensionCommandsBrowserTest,
                       ActivationDoesNotClearNewerBrowserOrOtherProfile) {
  const auto* extension = LoadFixture();
  ASSERT_TRUE(extension);
  const auto key = AcceleratorFor(*extension);
  auto* second_browser = CreateBrowser(profile());
  ASSERT_TRUE(second_browser);
  NativeExtensionKeybindingRegistry first(*browser(), NoActionForTest());
  auto second = std::make_unique<NativeExtensionKeybindingRegistry>(
      *second_browser, NoActionForTest());
  auto* global = extensions::ExtensionCommandsGlobalRegistry::Get(profile());
  ASSERT_TRUE(global);
  first.OnHostActivationChanged(true);
  EXPECT_EQ(&first, global->registry_for_active_window());
  second->OnHostActivationChanged(true);
  first.OnHostActivationChanged(false);
  EXPECT_EQ(second.get(), global->registry_for_active_window());

  auto* manager = g_browser_process->profile_manager();
  Profile& other_profile = profiles::testing::CreateProfileSync(
      manager, manager->user_data_dir().AppendASCII("ParcCommandsOther"));
  auto* other_browser = CreateBrowser(&other_profile);
  ASSERT_TRUE(other_browser);
  NativeExtensionKeybindingRegistry other(*other_browser, NoActionForTest());
  EXPECT_TRUE(first.IsAcceleratorRegistered(key));
  EXPECT_FALSE(other.IsAcceleratorRegistered(key));
  EXPECT_FALSE(other.DispatchAccelerator(key));
  auto* other_global =
      extensions::ExtensionCommandsGlobalRegistry::Get(&other_profile);
  ASSERT_NE(global, other_global);
  other.OnHostActivationChanged(true);
  EXPECT_EQ(&other, other_global->registry_for_active_window());
  EXPECT_EQ(second.get(), global->registry_for_active_window());
  second.reset();
  EXPECT_EQ(nullptr, global->registry_for_active_window());
  EXPECT_EQ(&other, other_global->registry_for_active_window());
}

IN_PROC_BROWSER_TEST_F(NativeExtensionCommandsBrowserTest,
                       ActionMayDestroyRegistryWithoutNamedDispatch) {
  const auto* extension = LoadFixture();
  ASSERT_TRUE(extension);
  const auto key = AcceleratorFor(*extension);
  extensions::TestEventRouterObserver events(
      extensions::EventRouter::Get(profile()));
  for (bool handled : {false, true}) {
    std::unique_ptr<NativeExtensionKeybindingRegistry> registry;
    registry = std::make_unique<NativeExtensionKeybindingRegistry>(
        *browser(), base::BindLambdaForTesting([&](const ui::Accelerator&) {
          registry.reset();
          return handled;
        }));
    registry->OnHostActivationChanged(true);
    EXPECT_EQ(handled, registry->DispatchAccelerator(key));
    EXPECT_FALSE(registry);
    EXPECT_EQ(nullptr,
              extensions::ExtensionCommandsGlobalRegistry::Get(profile())
                  ->registry_for_active_window());
    EXPECT_FALSE(events.events().contains(kEvent));
  }
}

}  // namespace parc
