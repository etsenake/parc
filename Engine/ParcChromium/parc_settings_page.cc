#include "parc/parc_settings_page.h"

#include <memory>
#include <utility>

#include "base/check.h"
#include "base/json/json_reader.h"
#include "base/strings/strcat.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/ui/webui/settings/settings_ui.h"
#include "chrome/common/webui_url_constants.h"
#include "content/public/browser/web_contents.h"
#include "content/public/browser/web_ui.h"
#include "content/public/browser/web_ui_controller.h"
#include "content/public/browser/web_ui_data_source.h"
#include "content/public/browser/webui_config_map.h"
#include "content/public/common/url_constants.h"
#include "url/gurl.h"
#include "url/url_constants.h"

namespace parc {
namespace {

constexpr char kPageVisibility[] = "parcPageVisibility";
constexpr char kSettingsPageValues[] = R"json({
  "parcPageVisibility": {
    "ai": false,
    "appearance": {
      "bookmarksBar": false,
      "homeButton": false,
      "hoverCard": false,
      "pageZoom": true,
      "setTheme": false,
      "sidePanel": true
    },
    "onStartup": false,
    "privacy": {
      "networkPrediction": true,
      "searchPrediction": false
    }
  },
  "autofillAiReauthOnViewingSensitiveDataEnabled": false,
  "downloadBubblePartialViewControlledByPref": false,
  "enableComposeProactiveNudge": false,
  "extendedReportingRemovePrefDependency": true,
  "hashPrefixRealTimeLookupsSamplePing": true,
  "isUserEligibleForWalletablePassDetection": false,
  "shoppingIntegrationEnabled": false,
  "shouldShowPayOverTimeSettings": false,
  "showCtrlTabMru": false,
  "showEverythingMenuEnabled": false,
  "showGlassEffectEnabled": false,
  "showOrganizerPanelEnabled": true,
  "showPrivacyGuide": false,
  "showSuggestionsFromGeminiSettings": false,
  "signinAllowed": false,
  "signinAvailable": false,
  "tabStripUnificationEnabled": false
})json";

class ParcSettingsUIConfig final : public settings::SettingsUIConfig {
 public:
  std::unique_ptr<content::WebUIController> CreateWebUIController(
      content::WebUI* web_ui,
      const GURL& url) override {
    auto controller =
        settings::SettingsUIConfig::CreateWebUIController(web_ui, url);
    base::DictValue values = SettingsPageValues();
    if (Profile::FromWebUI(web_ui)->IsGuestSession()) {
      values.Remove(kPageVisibility);
    }
    content::WebUIDataSource::Update(
        web_ui->GetWebContents()->GetBrowserContext(),
        chrome::kChromeUISettingsHost, std::move(values));
    return controller;
  }
};

}  // namespace

base::DictValue SettingsPageValues() {
  auto values =
      base::JSONReader::ReadDict(kSettingsPageValues, base::JSON_PARSE_RFC);
  CHECK(values);
  return std::move(*values);
}

void RegisterSettingsWebUI() {
  auto& configs = content::WebUIConfigMap::GetInstance();
  configs.RemoveConfig(GURL(base::StrCat({content::kChromeUIScheme,
                                          url::kStandardSchemeSeparator,
                                          chrome::kChromeUISettingsHost})));
  configs.AddWebUIConfig(std::make_unique<ParcSettingsUIConfig>());
}

}  // namespace parc
