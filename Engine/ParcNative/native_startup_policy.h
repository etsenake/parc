#ifndef PARC_NATIVE_STARTUP_POLICY_H_
#define PARC_NATIVE_STARTUP_POLICY_H_

#include <functional>
#include <set>
#include <string>
#include <string_view>

#include "base/base_switches.h"
#include "base/command_line.h"
#include "base/feature_list.h"
#include "base/strings/string_util.h"

namespace parc {
inline constexpr const char* kExcludedFeatures[] = {
    "HistoryEmbeddings",
    "Glic",
    "GlicActorUi",
    "AutofillActorMode",
    "LensOverlay",
    "TranslateRankerQuery",
    "TranslateRankerEnforcement",
    "CentralizedInfoBarFramework",
    "TranslateTrigger",
};
inline constexpr const char* kBaselineEnabledFeatures[] = {
    "CertificateTransparencyAskBeforeEnabling",
};
inline constexpr const char* kParcEnabledFeatures[] = {
    "WebContentsDiscard",
};
inline constexpr const char* kBaselineDisabledFeatures[] = {
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
    "CredentialManagementUnifiedUi",
    "ExtensionsPinnedByDefault",
    "SkillsEnabled",
    "GoogleSearchAiModeWorkspace",
};

inline void AppendFeature(std::string& list, std::string_view feature) {
  if (!list.empty()) {
    list += ",";
  }
  list += feature;
}

inline void ApplyNativeStartupPolicy(base::CommandLine& command) {
  command.AppendSwitch("disable-field-trial-config");
  std::string enabled = command.GetSwitchValueUTF8(switches::kEnableFeatures);
  std::string disabled = command.GetSwitchValueUTF8(switches::kDisableFeatures);
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
  for (const char* feature : kBaselineDisabledFeatures) {
    if (!named.contains(feature)) {
      AppendFeature(disabled, feature);
    }
  }
  for (const char* feature : kBaselineEnabledFeatures) {
    if (!named.contains(feature)) {
      AppendFeature(enabled, feature);
    }
  }
  for (const char* feature : kParcEnabledFeatures) {
    if (!named.contains(feature)) {
      AppendFeature(enabled, feature);
    }
  }
  command.RemoveSwitch(switches::kEnableFeatures);
  command.RemoveSwitch(switches::kDisableFeatures);
  if (!enabled.empty()) {
    command.AppendSwitchUTF8(switches::kEnableFeatures, enabled);
  }
  command.AppendSwitchUTF8(switches::kDisableFeatures, disabled);
}
}
#endif
