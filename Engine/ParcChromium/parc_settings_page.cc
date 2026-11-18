#include "parc/parc_settings_page.h"

#include <memory>
#include <string>
#include <utility>

#include "base/check.h"
#include "base/json/json_reader.h"
#include "base/strings/strcat.h"
#include "chrome/browser/google/google_brand.h"
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
constexpr char kResetProfileSettings[] = "performResetProfileSettings";
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
    "people": false,
    "privacy": {
      "networkPrediction": true,
      "searchPrediction": false
    }
  },
  "parcHiddenRows": {
    "settings-a11y-page": [
      "#toastToggle",
      "[pref-key=\"settings.a11y.enable_accessibility_image_labels\"]"
    ],
    "settings-about-page": [
      ".icon-container:has(#throbber)",
      "#updateStatusMessage",
      ".separator:has(+ #buttonContainer)",
      "#buttonContainer"
    ],
    "settings-appearance-page": [
      "#toolbarRow",
      "#colorSchemeModeRow",
      ".cr-row:has(> #tabStripPosition)",
      ".cr-row:has(> #tabStripPosition) + .list-frame",
      "#showOrganizerPanelButton",
      ".cr-row:has(+ .list-frame #sidePanelPosition)",
      ".list-frame:has(#sidePanelPosition)",
      "[pref-key=\"browser.confirm_to_quit\"]",
      "#splitViewDragAndDrop"
    ],
    "settings-autofill-page": [
      "#identityManagerButton",
      "#travelManagerButton",
      "settings-section:has(> collapsible-autofill-settings-card)",
      "#googleWalletButton",
      "#googleAccountButton"
    ],
    "settings-autofill-page-index": [
      "#identityDocs",
      "#travel"
    ],
    "settings-languages-page": [
      ".target-info"
    ],
    "settings-payments-page": [
      "#cardBenefitsToggle",
      "#manageLink"
    ],
    "settings-performance-page": [
      "#performanceInterventionToggleButton",
      "#discardRingTreatmentToggleButton",
      "cr-link-row:has(+ #exceptionList)"
    ],
    "settings-reset-profile-dialog": [
      "[slot=\"footer\"]"
    ],
    "settings-safety-hub-page": [
      "#version"
    ],
    "settings-security-page": [
      "#advancedProtectionProgramLink"
    ],
    "settings-system-page": [
      "#hardwareAcceleration > cr-button"
    ],
    "settings-translate-page": [
      "settings-section"
    ]
  },
  "autofillAiReauthOnViewingSensitiveDataEnabled": false,
  "downloadBubblePartialViewControlledByPref": false,
  "enableComposeProactiveNudge": false,
  "enableLiveCaption": false,
  "enableLiveTranslate": false,
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

class ParcSettingsUI final : public settings::SettingsUI {
 public:
  using settings::SettingsUI::SettingsUI;

  bool OverrideHandleWebUIMessage(const GURL& source_url,
                                  const std::string& message,
                                  const base::ListValue& args) override {
    if (message != kResetProfileSettings || args.size() != 3 ||
        args[1] == false) {
      return false;
    }
    base::ListValue quiet = args.Clone();
    quiet[1] = base::Value(false);
    web_ui()->ProcessWebUIMessage(source_url, message, std::move(quiet));
    return true;
  }
};

class ParcSettingsUIConfig final : public settings::SettingsUIConfig {
 public:
  std::unique_ptr<content::WebUIController> CreateWebUIController(
      content::WebUI* web_ui,
      const GURL&) override {
    auto controller = std::make_unique<ParcSettingsUI>(web_ui);
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

void ReportNoBrandCode() {
  google_brand::g_brand_for_testing = "";
}

void RegisterSettingsWebUI() {
  auto& configs = content::WebUIConfigMap::GetInstance();
  configs.RemoveConfig(GURL(base::StrCat({content::kChromeUIScheme,
                                          url::kStandardSchemeSeparator,
                                          chrome::kChromeUISettingsHost})));
  configs.AddWebUIConfig(std::make_unique<ParcSettingsUIConfig>());
}

}  // namespace parc
