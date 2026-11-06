// Copyright 2026 Parc contributors.
#ifndef PARC_NATIVE_STARTUP_POLICY_H_
#define PARC_NATIVE_STARTUP_POLICY_H_

#include <functional>
#include <set>
#include <string>
#include <string_view>

#include "base/feature_list.h"
#include "base/strings/string_util.h"
#include "cef/include/cef_command_line.h"

namespace parc {
// Disabled even when the command line explicitly enables them.
inline constexpr const char* kExcludedFeatures[] = {
    "HistoryEmbeddings",
    "Glic",
    "GlicActorUi",
    "AutofillActorMode",
    "LensOverlay",
    "TranslateRankerQuery",
    "TranslateRankerEnforcement",
};
// Applied only to features the command line does not already name.
inline constexpr const char* kArcEnabledFeatures[] = {
    "CertificateTransparencyAskBeforeEnabling",
};
// Parc's own defaults, applied the same way. WebContentsDiscard is the
// in-place discard -[PCNativePage discardIfIdle] uses for long-unused
// background tabs; it keeps Parc's page and WebContents, where desktop
// Chrome's discard replaces the WebContents.
inline constexpr const char* kParcEnabledFeatures[] = {
    "WebContentsDiscard",
};
inline constexpr const char* kArcDisabledFeatures[] = {
    "MacAppCodeSignClone",
    "MacAppCodeSignCloneRenameAsBundle",
    "FedCm",
    "AutofillServerCommunication",
    "PreloadMediaEngagementData",
    "BrowsingTopics",
    "NetworkTimeServiceQuerying",
    "LiveCaption",
    "MerchantTrust",
    "PageInfoAboutThisSite",
    "PageInfoAboutThisSiteMoreLangs",
    "TailoredSecurityIntegration",
};

inline void AppendFeature(std::string& list, std::string_view feature) {
  if (!list.empty()) {
    list += ",";
  }
  list += feature;
}

inline void ApplyNativeStartupPolicy(CefCommandLine& command) {
  // Chromium testing/variations/README.md prescribes this control for
  // non-developer browsers. Its bundled testing config enables experiments
  // outside pinned CEF's supported helper cohort. Keep feature defaults;
  // do not permanently exclude Aperitif. Explicit developer opt-ins retain
  // upstream precedence; the shipping GN policy must disable this config.
  command.AppendSwitch("disable-field-trial-config");
  // Page translation is excluded: Chrome's translate service needs a Google
  // API key, which Parc never ships.
  command.AppendSwitch("disable-translate-trigger");
  std::string enabled = command.GetSwitchValue("enable-features").ToString();
  std::string disabled = command.GetSwitchValue("disable-features").ToString();
  // Chromium applies any disable over an enable of the same feature, so an
  //
  std::set<std::string, std::less<>> named;
  for (const std::string* list : {&enabled, &disabled}) {
    for (std::string_view entry :
         base::FeatureList::SplitFeatureListString(*list)) {
      if (entry.starts_with('*')) {
        entry.remove_prefix(1);
      }
      named.emplace(base::TrimWhitespaceASCII(
          entry.substr(0, entry.find_first_of("<.:")), base::TRIM_ALL));
    }
  }
  for (const char* feature : kExcludedFeatures) {
    AppendFeature(disabled, feature);
  }
  for (const char* feature : kArcDisabledFeatures) {
    if (!named.contains(feature)) {
      AppendFeature(disabled, feature);
    }
  }
  for (const char* feature : kArcEnabledFeatures) {
    if (!named.contains(feature)) {
      AppendFeature(enabled, feature);
    }
  }
  for (const char* feature : kParcEnabledFeatures) {
    if (!named.contains(feature)) {
      AppendFeature(enabled, feature);
    }
  }
  if (!enabled.empty()) {
    command.AppendSwitchWithValue("enable-features", enabled);
  }
  command.AppendSwitchWithValue("disable-features", disabled);
}
}  // namespace parc
#endif  // PARC_NATIVE_STARTUP_POLICY_H_
