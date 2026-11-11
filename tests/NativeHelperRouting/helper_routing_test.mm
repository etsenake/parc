// Copyright 2026 Parc contributors.
// Calls actual pinned CEF and Chromium implementations; no browser/profile is
// created, and no subprocess is launched. The paths are isolated test inputs.
#include <cstdio>
#include <cstdlib>
#include <string>

#include "base/apple/foundation_util.h"
#include "base/at_exit.h"
#include "base/base_paths.h"
#include "base/command_line.h"
#include "base/feature_list.h"
#include "base/files/file_path.h"
#include "base/files/file_util.h"
#include "base/path_service.h"
#include "base/apple/bundle_locations.h"
#include "chrome/common/chrome_paths_internal.h"
#include "parc/parc_bundle_mac.h"
#include "content/public/browser/child_process_host.h"
#include "content/public/common/content_client.h"
#include "content/public/common/content_features.h"
#include "content/public/common/content_paths.h"
#include "content/public/common/content_switches.h"
#include "native_startup_policy.h"

namespace {
int assertions = 0;
void Expect(bool value, const char* label) {
  ++assertions;
  if (!value) {
    std::fprintf(stderr, "FAIL: %s\n", label);
    std::exit(1);
  }
}
constexpr char kPolicyDisabled[] =
    "HistoryEmbeddings,Glic,GlicActorUi,AutofillActorMode,LensOverlay,"
    "TranslateRankerQuery,TranslateRankerEnforcement,"
    "MacAppCodeSignClone,MacAppCodeSignCloneRenameAsBundle,FedCm,"
    "AutofillServerCommunication,PreloadMediaEngagementData,BrowsingTopics,"
    "NetworkTimeServiceQuerying,LiveCaption,MerchantTrust,"
    "PageInfoAboutThisSite,PageInfoAboutThisSiteMoreLangs,"
    "TailoredSecurityIntegration";
constexpr char kPolicyEnabled[] =
    "CertificateTransparencyAskBeforeEnabling,WebContentsDiscard";
void CheckStartupPolicy() {
  base::CommandLine actual(base::FilePath("/fixture/Parc"));
  actual.AppendSwitchASCII("disable-features", "UserDisabledFeature");
  actual.AppendSwitchASCII("enable-features", "UserEnabledFeature");
  actual.AppendSwitchASCII("lang", "fr-CA");
  actual.AppendArg("https://example.test/kept");
  parc::ApplyNativeStartupPolicy(actual);
  Expect(actual.HasSwitch("disable-field-trial-config"),
         "default startup disables Chromium's bundled testing config");
  Expect(actual.HasSwitch("disable-translate-trigger"),
         "default startup never offers page translation");
  Expect(actual.GetSwitchValueASCII("disable-features") ==
             std::string("UserDisabledFeature,") + kPolicyDisabled,
         "explicit disable-features precede product and Parc disables");
  Expect(actual.GetSwitchValueASCII("enable-features") ==
             std::string("UserEnabledFeature,") + kPolicyEnabled,
         "explicit feature opt-in is kept ahead of the enabled default");
  Expect(actual.GetSwitchValueASCII("lang") == "fr-CA" &&
             actual.GetArgs() ==
                 base::CommandLine::StringVector{"https://example.test/kept"},
         "unrelated switches and launch arguments are preserved");
  Expect(!actual.HasSwitch("no-sandbox") && !actual.HasSwitch("disable-gpu") &&
             !actual.HasSwitch("browser-subprocess-path"),
         "sandbox, GPU and standard helper dispatch are unchanged");
  Expect(actual.GetSwitchValueASCII("disable-features").find("Aperitif") ==
             std::string::npos,
         "Aperitif is not permanently excluded");

  base::CommandLine explicit_test(base::FilePath("/fixture/Parc"));
  explicit_test.AppendSwitch("disable-field-trial-config");
  explicit_test.AppendSwitch("enable-field-trial-config");
  explicit_test.AppendSwitchASCII("enable-benchmarking",
                                  "enable-field-trial-config");
  parc::ApplyNativeStartupPolicy(explicit_test);
  Expect(explicit_test.HasSwitch("disable-field-trial-config"),
         "preexisting default-control switch is retained");
  Expect(explicit_test.HasSwitch("enable-field-trial-config") &&
             explicit_test.GetSwitchValueASCII("enable-benchmarking") ==
                 "enable-field-trial-config",
         "explicit developer test opt-ins retain upstream precedence");
  Expect(
      explicit_test.GetSwitchValueASCII("disable-features") == kPolicyDisabled,
      "empty disable list receives exactly the product and Parc disables");
  Expect(explicit_test.GetSwitchValueASCII("enable-features") == kPolicyEnabled,
         "empty enable list receives exactly the and Parc's enabled defaults");

  base::CommandLine opt_in(base::FilePath("/fixture/Parc"));
  opt_in.AppendSwitchASCII(
      "enable-features",
      "FedCm,*LiveCaption,MerchantTrust<Study.Group:p/v,HistoryEmbeddings");
  opt_in.AppendSwitchASCII("disable-features",
                           "CertificateTransparencyAskBeforeEnabling");
  parc::ApplyNativeStartupPolicy(opt_in);
  Expect(opt_in.GetSwitchValueASCII("enable-features") ==
             "FedCm,*LiveCaption,MerchantTrust<Study.Group:p/v,"
             "HistoryEmbeddings,WebContentsDiscard",
         "explicit enables are kept; an explicitly disabled Parc enable is not "
         "re-added");
  Expect(opt_in.GetSwitchValueASCII("disable-features") ==
             "CertificateTransparencyAskBeforeEnabling,HistoryEmbeddings,"
             "Glic,GlicActorUi,AutofillActorMode,LensOverlay,"
             "TranslateRankerQuery,TranslateRankerEnforcement,"
             "MacAppCodeSignClone,MacAppCodeSignCloneRenameAsBundle,"
             "AutofillServerCommunication,PreloadMediaEngagementData,"
             "BrowsingTopics,NetworkTimeServiceQuerying,"
             "PageInfoAboutThisSite,PageInfoAboutThisSiteMoreLangs,"
             "TailoredSecurityIntegration",
         "named features skip Parc disables; product exclusions remain");

  base::CommandLine spaced(base::FilePath("/fixture/Parc"));
  spaced.AppendSwitchASCII("enable-features", "FedCm :p/v");
  parc::ApplyNativeStartupPolicy(spaced);
  Expect(spaced.GetSwitchValueASCII("disable-features").find("FedCm") ==
             std::string::npos,
         "whitespace before a parameter list still names the feature");

  base::CommandLine precedence(base::FilePath("/fixture/Parc"));
  precedence.AppendSwitchASCII("enable-features", "FedCm,HistoryEmbeddings");
  parc::ApplyNativeStartupPolicy(precedence);
  base::FeatureList features;
  features.InitFromCommandLine(
      precedence.GetSwitchValueASCII("enable-features"),
      precedence.GetSwitchValueASCII("disable-features"));
  Expect(features.IsFeatureOverriddenFromCommandLine(
             "FedCm", base::FeatureList::OVERRIDE_ENABLE_FEATURE),
         "Chromium keeps an explicit enable of an Parc-disabled feature");
  Expect(features.IsFeatureOverriddenFromCommandLine(
             "HistoryEmbeddings", base::FeatureList::OVERRIDE_DISABLE_FEATURE),
         "Chromium applies a product exclusion over an explicit enable");
  Expect(features.IsFeatureOverriddenFromCommandLine(
             "CertificateTransparencyAskBeforeEnabling",
             base::FeatureList::OVERRIDE_ENABLE_FEATURE) &&
             features.IsFeatureOverriddenFromCommandLine(
                 "MacAppCodeSignClone",
                 base::FeatureList::OVERRIDE_DISABLE_FEATURE),
         "Chromium applies Parc defaults to unnamed features");
}
void CheckApplication(const std::string& name) {
  const base::FilePath executable = base::CommandLine::ForCurrentProcess()->GetProgram();
  const base::FilePath framework = executable.DirName().DirName().DirName();
  const base::FilePath bundle = framework.DirName().DirName().DirName();
  Expect(parc::InstallBundleOverrides(), "real loaded-image bundle overrides install");
  Expect(base::apple::FrameworkBundlePath() == framework, "loaded framework path");
  Expect(base::apple::OuterBundlePath() == bundle, "real outer application path");
  Expect(base::apple::BaseBundleID() == "org.parc.helper-routing-fixture", "fixture bundle identifier");
  Expect(chrome::GetFrameworkBundlePath() == framework, "Chrome honours the loaded framework override");
  auto expected = [&](const char* suffix) {
    const std::string helper = name + " Helper" + suffix;
    return bundle.Append("Contents/Frameworks").Append(helper + ".app")
        .Append("Contents/MacOS").Append(helper);
  };
  Expect(parc::HelperExecutablePath("") == expected(""), "base helper derivation");
  Expect(parc::HelperExecutablePath(" (Alerts)") == expected(" (Alerts)"), "Alerts helper derivation");
  Expect(parc::HelperExecutablePath(" (CDM)") == expected(" (CDM)"), "CDM helper derivation");
  base::FilePath child;
  Expect(base::PathService::Get(content::CHILD_PROCESS_EXE, &child) && child == expected(""),
         "startup installs correct child path");
  using Host = content::ChildProcessHost;
  Expect(Host::GetChildPath(Host::CHILD_NORMAL) == expected(""), "real default route");
  Expect(Host::GetChildPath(Host::CHILD_RENDERER) == expected(" (Renderer)"), "real renderer JIT route");
  Expect(Host::GetChildPath(Host::CHILD_GPU) == expected(" (GPU)"), "real GPU JIT route");
  Expect(base::MakeAbsoluteFilePath(base::apple::NSStringToFilePath(
             base::apple::FrameworkBundle().resourcePath)) ==
             base::MakeAbsoluteFilePath(framework.Append("Resources")),
         "real framework resource path");
  auto* command = base::CommandLine::ForCurrentProcess();
  command->AppendSwitchPath(switches::kBrowserSubprocessPath, expected(""));
  Expect(Host::GetChildPath(Host::CHILD_RENDERER) == expected(""), "explicit override reproduces wrong renderer route");
  Expect(Host::GetChildPath(Host::CHILD_GPU) == expected(""), "explicit override reproduces wrong GPU route");
  command->RemoveSwitch(switches::kBrowserSubprocessPath);
  std::printf("PASS %s: real bundle overrides, helper routes and resources\n", name.c_str());
}
}  // namespace

int main(int argc, char** argv) {
  base::AtExitManager at_exit;
  base::CommandLine::Init(argc, argv);
  base::FeatureList::InitInstance("", "");
  Expect(!base::FeatureList::IsEnabled(features::kAperitifHelpers),
         "pinned ordinary helper policy");
  base::apple::SetOverrideAmIBundled(true);
  content::ContentClient content_client;
  content::SetContentClient(&content_client);
  CheckStartupPolicy();
  Expect(argc == 2, "fixture executable name supplied");
  CheckApplication(argv[1]);
  content::SetContentClient(nullptr);
  std::printf(
      "PASS %d assertions; no browser, profile or helper process created\n",
      assertions);
  return 0;
}
