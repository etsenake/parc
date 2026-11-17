// Copyright 2026 Parc contributors.
#include "parc/parc_main_delegate.h"

#include <optional>
#include <string>
#include <string_view>
#include <utility>
#include <variant>

#include "base/check.h"
#include "base/command_line.h"
#include "base/files/file_path.h"
#include "base/memory/ref_counted_memory.h"
#include "base/no_destructor.h"
#include "base/path_service.h"
#include "base/strings/string_view_util.h"
#include "base/time/time.h"
#include "chrome/browser/chrome_browser_main_mac.h"
#include "chrome/browser/metrics/chrome_feature_list_creator.h"
#include "chrome/browser/startup_data.h"
#include "chrome/browser/ui/tabs/tab_strip_model.h"
#include "chrome/common/chrome_paths.h"
#include "chrome/common/chrome_switches.h"
#include "chrome/common/pref_names.h"
#include "chrome/common/profiler/main_thread_stack_sampling_profiler.h"
#include "components/grit/components_resources.h"
#include "components/prefs/pref_service.h"
#include "components/tabs/public/tab_interface.h"
#include "content/public/browser/browser_main_runner.h"
#include "content/public/common/content_switches.h"
#include "parc/chromium_hooks.h"
#include "parc/error_pages.h"
#include "parc/native/native_appkit_host.h"
#include "parc/native/native_background_picture_in_picture_api.h"
#include "parc/native/native_browser.h"
#include "parc/native/native_internal_urls.h"
#include "parc/native/native_profile_policy.h"
#include "parc/native/unload_transactions.h"
#include "parc/product_name_strings.h"
#include "parc/webui_branding.h"
#include "chrome/utility/chrome_content_utility_client.h"
#include "mojo/public/cpp/bindings/service_factory.h"
#include "parc/importer/import_service.h"
#include "ui/base/l10n/l10n_util.h"
#include "ui/base/resource/resource_bundle.h"
#include "ui/color/color_provider_manager.h"
#include "ui/gfx/image/image.h"
#include "ui/native_theme/native_theme.h"

namespace parc {
namespace {
class ParcBrowserMainPartsMac final : public ChromeBrowserMainPartsMac {
 public:
  using ChromeBrowserMainPartsMac::ChromeBrowserMainPartsMac;
  int PreCreateThreads() override {
    return ChromeBrowserMainPartsPosix::PreCreateThreads();
  }
};
std::unique_ptr<ChromeBrowserMainParts> CreateMacMainParts(
    bool is_integration_test, StartupData* startup_data) {
  return std::make_unique<ParcBrowserMainPartsMac>(is_integration_test,
                                                startup_data);
}
bool UsesNativeStartup() {
  return true;
}
ui::PageTransition NativeAddTabTransition() {
  return static_cast<ui::PageTransition>(
      ui::PAGE_TRANSITION_TYPED | ui::PAGE_TRANSITION_FROM_ADDRESS_BAR);
}
bool NativeTabUIUpdateAllowed(TabStripModel& model,
                              tabs::TabInterface& tab) {
  return model.GetIndexOfTab(&tab) != TabStripModel::kNoTab;
}
const ui::ColorProvider* NativeEmptyTabColorProvider() {
  return ui::ColorProviderManager::Get().GetColorProviderFor(
      ui::NativeTheme::GetInstanceForNativeUi()->GetColorProviderKey(
          /*custom_theme=*/nullptr));
}
class ChildProductBrandingDelegate final
    : public ui::ResourceBundle::Delegate {
 public:
  base::FilePath GetPathForResourcePack(
      const base::FilePath& pack_path,
      ui::ResourceScaleFactor scale_factor) override {
    return pack_path;
  }
  gfx::Image GetImageNamed(int resource_id) override { return gfx::Image(); }
  gfx::Image GetNativeImageNamed(int resource_id) override {
    return gfx::Image();
  }
  bool HasDataResource(int resource_id) const override { return false; }
  scoped_refptr<base::RefCountedMemory> LoadDataResourceBytes(
      int resource_id,
      ui::ResourceScaleFactor scale_factor) override {
    return LoadBrandedResource(resource_id, scale_factor);
  }
  std::optional<std::string> LoadDataResourceString(int resource_id) override {
    if (resource_id == IDR_NET_ERROR_HTML) {
      return std::string(NetErrorPageTemplate());
    }
    if (resource_id == IDR_WEBAPP_ERROR_PAGE_HTML ||
        resource_id == IDR_ENTERPRISE_PROXY_ERROR_PAGE_HTML) {
      std::string html =
          ui::ResourceBundle::GetSharedInstance()
              .LoadDataResourceStringForScale(resource_id, ui::kScaleFactorNone);
      if (resource_id == IDR_WEBAPP_ERROR_PAGE_HTML) {
        AddErrorPageSkin(html, WebAppErrorStyle(), std::string_view());
      } else {
        AddErrorPageSkin(html, InterstitialStyle(), InterstitialScript());
      }
      return html;
    }
    if (auto bytes = LoadBrandedResource(resource_id, ui::kScaleFactorNone)) {
      return std::string(base::as_string_view(*bytes));
    }
    return std::nullopt;
  }
  bool GetRawDataResource(int resource_id,
                          ui::ResourceScaleFactor scale_factor,
                          std::string_view* value) const override {
    return GetBrandedImageBytes(resource_id, scale_factor, value);
  }
  bool GetLocalizedString(int message_id,
                          std::u16string* value) const override {
    auto& resources = ui::ResourceBundle::GetSharedInstance();
    std::string locale = resources.GetLoadedLocale();
    if (locale.empty()) {
      locale = l10n_util::GetApplicationLocale(std::string(), false);
    }
    return GetProductNameString(locale, message_id, value);
  }
};
ui::ResourceBundle::Delegate* NativeResourceBundle(void* context) {
  if (context) {
    return static_cast<NativeApplication*>(context)->ResourceBundleDelegate();
  }
  static base::NoDestructor<ChildProductBrandingDelegate> delegate;
  return delegate.get();
}
class ParcContentUtilityClient final : public ChromeContentUtilityClient {
 public:
  void RegisterMainThreadServices(mojo::ServiceFactory& services) override {
    ChromeContentUtilityClient::RegisterMainThreadServices(services);
    services.Add(+[](mojo::PendingReceiver<importer::mojom::Reader> receiver) {
      return std::make_unique<importer::ImportService>(std::move(receiver));
    });
  }
};
}

ParcMainDelegate::ParcMainDelegate(NativeApplication* application)
    : ChromeMainDelegate({.exe_entry_point_ticks = base::TimeTicks::Now()}),
      application_(application) {
  parc_hooks::SetMacMainLoopEndHandler(nullptr);
  parc_hooks::SetMacMainPartsFactory(&CreateMacMainParts);
  parc_hooks::SetBrowserAdmission(&PrepareNativeBrowserWindow,
                                  &SkipNativeBrowserAdmission);
  parc_hooks::SetBrowserLifetime(&NativeBrowser::OnBrowserCreated,
                                 &NativeBrowser::OnBrowserDestroyed);
  parc_hooks::SetBrowserDelegateChange(&NativeBrowser::SetAsDelegate);
  parc_hooks::SetBrowserRegistration(&NativeBrowser::OnRegistered);
  parc_hooks::SetBrowserDeletionGate(&NativeBrowser::DeferDeletion,
                                     &NativeBrowser::DeletionReady);
  parc_hooks::SetOTRProfileDestructionDeferral(
      &DeferNativeOTRProfileDestruction);
  parc_hooks::SetNavigatorURLRewriter(&CanonicalInternalURL);
  parc_hooks::SetNavigatorContentsCreated(&NativeBrowser::OnWebContentsCreated);
  parc_hooks::SetNavigatorBrowserCreator(&CreateBrowserWindowFrom);
  parc_hooks::SetAddTabTransition(&NativeAddTabTransition);
  parc_hooks::SetTabUIUpdateGate(&NativeTabUIUpdateAllowed);
  parc_hooks::SetEmptyTabColorProvider(&NativeEmptyTabColorProvider);
  parc_hooks::SetAutoPictureInPictureVisibilitySync(
      &SynchronizeAutoPictureInPictureVisibility);
  parc_hooks::SetDevToolsBrowserCreator(&CreateBrowserWindowFrom);
  parc_hooks::SetNativeBrowserWindowFactory(&NativeBrowser::CreateWindow);
  parc_hooks::SetNativeBrowserWindowFeatures(
      &NativeBrowser::ColorProviderSource, &CreateAppKitFocusController,
      &CreateAppKitDevtoolsController,
      &NativeBrowser::CreateWebContentsDelegate);
  parc_hooks::SetNativeDevtoolsPresentation(
      &UpdateAppKitDevtools, &SetAppKitDevtoolsScrim, &TearDownAppKitDevtools);
  parc_hooks::SetNativeDevtoolsFrontend(&PrepareNativeDevtoolsContents,
                                        &HandleNativeDevtoolsKey);
  parc_hooks::SetDevToolsLinkOpener(&OpenNativeDevtoolsLink);
  parc_hooks::SetUnloadControllerLifetime(&OnUnloadControllerCreated,
                                          &OnUnloadControllerDestroyed);
  parc_hooks::SetUnloadControllerTabEvents(
      &OnUnloadControllerTabAttached, &OnUnloadControllerTabDetached,
      &OnUnloadControllerRenderProcessGone, &AbsorbsTabStripEmpty);
  parc_hooks::SetUnloadControllerCloseGates(
      &BlocksWindowClose, &HoldsClosingStatus, &BlocksShutdownBeforeUnload);
  parc_hooks::SetUnloadControllerPageGates(&HoldsContents, &UnloadEventsResult,
                                           &HasTabCloseReply,
                                           &ConsumesBeforeUnloadReply);
  parc_hooks::SetNativeProfileRemoval(
      &OnProfileManagerCreated, &OnProfileManagerDestroyed,
      &NativeProfileCreationRefused, &OwnsNativeProfileDiskCleanup,
      &RunNativeProfileDiskCleanup);
  parc_hooks::SetNativeProfileDeletion(&LoadNativeProfileForDeletion,
                                       &RunNativeProfileDiskCleanup);
  parc_hooks::SetSessionTabRestoreOmission(&IsSessionOmittedFromRestore);
  parc_hooks::SetTabRestoreOmission(&IsSessionOmittedFromRestore);
  parc_hooks::SetSessionServiceOmission(&IsSessionOmittedFromRestore);
  parc_hooks::SetGaiaAccountsPolicy(&NativeGaiaAccountsAllowed);
  parc_hooks::SetSessionRestorePolicy(&RestoreNativeSessionState);
  parc_hooks::SetRegisterProfilePrefs(&RegisterNativeProfilePrefs);
  parc_hooks::SetMainStartupPolicy(&UsesNativeStartup);
  parc_hooks::SetBrowserStartupPolicy(&UsesNativeStartup);
  parc_hooks::SetMainResourceBundleFactory(&NativeResourceBundle, application);
  parc_hooks::SetBrowserResourceBundleFactory(&NativeResourceBundle, application);
}

ParcMainDelegate::~ParcMainDelegate() {
  parc_hooks::SetMainResourceBundleFactory(nullptr, nullptr);
  parc_hooks::SetBrowserResourceBundleFactory(nullptr, nullptr);
}

void ParcMainDelegate::ShutdownBrowser() {
  if (browser_runner_) {
    browser_runner_->Shutdown();
    browser_runner_.reset();
  }
}

void ParcMainDelegate::PreSandboxStartup() {
  const auto& command_line = *base::CommandLine::ForCurrentProcess();
  const base::FilePath root =
      command_line.GetSwitchValuePath(switches::kUserDataDir);
  if (!root.empty()) {
    const bool browser =
        command_line.GetSwitchValueASCII(switches::kProcessType).empty();
    CHECK(base::PathService::OverrideAndCreateIfNeeded(
        chrome::DIR_USER_DATA, root, /*is_absolute=*/true, /*create=*/false));
    base::PathService::Override(chrome::DIR_CRASH_DUMPS, root);
    base::PathService::OverrideAndCreateIfNeeded(
        chrome::DIR_APP_DICTIONARIES, root.Append("Dictionaries"),
        /*is_absolute=*/true, /*create=*/browser);
  }
  ChromeMainDelegate::PreSandboxStartup();
}

std::optional<int> ParcMainDelegate::PreBrowserMain() {
  return content::ContentMainDelegate::PreBrowserMain();
}

std::optional<int> ParcMainDelegate::PostEarlyInitialization(
    InvokedIn invoked_in) {
  auto result = ChromeMainDelegate::PostEarlyInitialization(invoked_in);
  if (!result && std::holds_alternative<InvokedInBrowserProcess>(invoked_in)) {
    chrome_content_browser_client_->startup_data()
        ->chrome_feature_list_creator()
        ->local_state()
        ->SetBoolean(prefs::kBrowserShowProfilePickerOnStartup, false);
  }
  return result;
}

std::variant<int, content::MainFunctionParams> ParcMainDelegate::RunProcess(
    const std::string& process_type,
    content::MainFunctionParams main_function_params) {
  if (!process_type.empty()) {
    return ChromeMainDelegate::RunProcess(process_type,
                                          std::move(main_function_params));
  }
  browser_runner_ = content::BrowserMainRunner::Create();
  const int exit_code =
      browser_runner_->Initialize(std::move(main_function_params));
  return exit_code >= 0 ? exit_code : 0;
}

content::ContentClient* ParcMainDelegate::CreateContentClient() {
  return &content_client_;
}

content::ContentBrowserClient* ParcMainDelegate::CreateContentBrowserClient() {
  CHECK(application_);
  chrome_content_browser_client_ =
      std::make_unique<ParcContentBrowserClient>(*application_);
  CHECK(sampling_profiler_);
  chrome_content_browser_client_->SetSamplingProfiler(
      std::move(sampling_profiler_));
  return chrome_content_browser_client_.get();
}

content::ContentGpuClient* ParcMainDelegate::CreateContentGpuClient() {
  gpu_client_ = std::make_unique<ParcContentGpuClient>();
  return gpu_client_.get();
}

content::ContentRendererClient*
ParcMainDelegate::CreateContentRendererClient() {
  renderer_client_ = std::make_unique<ParcContentRendererClient>();
  return renderer_client_.get();
}

content::ContentUtilityClient* ParcMainDelegate::CreateContentUtilityClient() {
  chrome_content_utility_client_ = std::make_unique<ParcContentUtilityClient>();
  return chrome_content_utility_client_.get();
}

}
