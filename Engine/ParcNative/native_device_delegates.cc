// Copyright 2026 Parc contributors.
#include "parc/native/native_device_delegates.h"

#include <utility>
#include <vector>

#include "base/feature_list.h"
#include "base/functional/bind.h"
#include "base/functional/callback_helpers.h"
#include "base/memory/weak_ptr.h"
#include "chrome/browser/bluetooth/chrome_bluetooth_delegate.h"
#include "chrome/browser/bluetooth/chrome_bluetooth_delegate_impl_client.h"
#include "chrome/browser/chooser_controller/title_util.h"
#include "chrome/browser/hid/chrome_hid_delegate.h"
#include "chrome/browser/serial/chrome_serial_delegate.h"
#include "chrome/browser/ui/bluetooth/chrome_bluetooth_chooser_controller.h"
#include "chrome/browser/ui/hid/hid_chooser.h"
#include "chrome/browser/ui/hid/hid_chooser_controller.h"
#include "chrome/browser/ui/serial/serial_chooser_controller.h"
#include "chrome/browser/usb/chrome_usb_delegate.h"
#include "chrome/browser/usb/usb_chooser_controller.h"
#include "components/permissions/bluetooth_chooser_desktop.h"
#include "components/permissions/bluetooth_scanning_prompt_desktop.h"
#include "components/strings/grit/components_strings.h"
#include "content/public/browser/global_routing_id.h"
#include "content/public/browser/render_frame_host.h"
#include "extensions/browser/guest_view/web_view/web_view_guest.h"
#include "extensions/common/extension_features.h"
#include "parc/native/device_chooser.h"

namespace parc {
namespace {

template <typename Chooser>
class NativeChooserHandle final : public Chooser {
 public:
  explicit NativeChooserHandle(base::OnceClosure close)
      : close_runner_(std::move(close)) {}

 private:
  base::ScopedClosureRunner close_runner_;
};

class NativeBluetoothDelegateClient final
    : public ChromeBluetoothDelegateImplClient {
 public:
  std::unique_ptr<content::BluetoothChooser> RunBluetoothChooser(
      content::RenderFrameHost* frame,
      const content::BluetoothChooser::EventHandler& event_handler) override {
    return std::make_unique<permissions::BluetoothChooserDesktop>(
        std::make_unique<ChromeBluetoothChooserController>(frame,
                                                           event_handler),
        base::BindOnce(&ShowNativeDeviceChooser, frame));
  }

  std::unique_ptr<content::BluetoothScanningPrompt> ShowBluetoothScanningPrompt(
      content::RenderFrameHost* frame,
      const content::BluetoothScanningPrompt::EventHandler& event_handler)
      override {
    return std::make_unique<permissions::BluetoothScanningPromptDesktop>(
        frame, event_handler,
        CreateChooserTitle(frame, IDS_BLUETOOTH_SCANNING_PROMPT),
        base::BindOnce(&ShowNativeDeviceChooser, frame));
  }
};

class NativeUsbDelegate final : public ChromeUsbDelegate {
 public:
  std::unique_ptr<content::UsbChooser> RunChooser(
      content::RenderFrameHost& frame,
      blink::mojom::WebUsbRequestDeviceOptionsPtr options,
      blink::mojom::WebUsbService::GetPermissionCallback callback) override {
    return std::make_unique<NativeChooserHandle<content::UsbChooser>>(
        ShowNativeDeviceChooser(
            &frame, std::make_unique<UsbChooserController>(
                        &frame, std::move(options), std::move(callback))));
  }
};

class NativeSerialDelegate final : public ChromeSerialDelegate {
 public:
  std::unique_ptr<content::SerialChooser> RunChooser(
      content::RenderFrameHost* frame,
      std::vector<blink::mojom::SerialPortFilterPtr> filters,
      std::vector<device::BluetoothUUID> allowed_bluetooth_service_class_ids,
      content::SerialChooser::Callback callback) override {
    return std::make_unique<NativeChooserHandle<content::SerialChooser>>(
        ShowNativeDeviceChooser(
            frame, std::make_unique<SerialChooserController>(
                       frame, std::move(filters),
                       std::move(allowed_bluetooth_service_class_ids),
                       std::move(callback))));
  }
};

class NativeHidDelegate final : public ChromeHidDelegate {
 public:
  std::unique_ptr<content::HidChooser> RunChooser(
      content::RenderFrameHost* render_frame_host,
      std::vector<blink::mojom::HidDeviceFilterPtr> filters,
      std::vector<blink::mojom::HidDeviceFilterPtr> exclusion_filters,
      content::HidChooser::Callback callback) override {
    if (render_frame_host &&
        extensions::WebViewGuest::FromRenderFrameHost(render_frame_host) &&
        base::FeatureList::IsEnabled(
            extensions_features::kEnableWebHidInWebView)) {
      return ChromeHidDelegate::RunChooser(
          render_frame_host, std::move(filters), std::move(exclusion_filters),
          std::move(callback));
    }
    return std::make_unique<HidChooser>(ShowNativeDeviceChooser(
        render_frame_host,
        std::make_unique<HidChooserController>(
            render_frame_host, std::move(filters),
            std::move(exclusion_filters), std::move(callback))));
  }

 private:
  void OnWebViewHidPermissionRequestCompleted(
      base::WeakPtr<HidChooser> chooser,
      content::GlobalRenderFrameHostId embedder_rfh_id,
      std::vector<blink::mojom::HidDeviceFilterPtr> filters,
      std::vector<blink::mojom::HidDeviceFilterPtr> exclusion_filters,
      content::HidChooser::Callback callback,
      bool allow) override {
    auto* render_frame_host = content::RenderFrameHost::FromID(embedder_rfh_id);
    if (!allow || !render_frame_host || !chooser ||
        !CanRequestDevicePermission(
            render_frame_host->GetBrowserContext(),
            render_frame_host->GetMainFrame()->GetLastCommittedOrigin())) {
      std::move(callback).Run({});
      return;
    }
    base::ScopedClosureRunner close_runner(ShowNativeDeviceChooser(
        render_frame_host,
        std::make_unique<HidChooserController>(
            render_frame_host, std::move(filters),
            std::move(exclusion_filters), std::move(callback))));
    if (chooser) {
      chooser->SetCloseClosure(close_runner.Release());
    }
  }
};

}

std::unique_ptr<content::BluetoothDelegate> CreateNativeBluetoothDelegate() {
  return std::make_unique<ChromeBluetoothDelegate>(
      std::make_unique<NativeBluetoothDelegateClient>());
}

std::unique_ptr<content::UsbDelegate> CreateNativeUsbDelegate() {
  return std::make_unique<NativeUsbDelegate>();
}

std::unique_ptr<content::HidDelegate> CreateNativeHidDelegate() {
  return std::make_unique<NativeHidDelegate>();
}

std::unique_ptr<content::SerialDelegate> CreateNativeSerialDelegate() {
  return std::make_unique<NativeSerialDelegate>();
}

}
