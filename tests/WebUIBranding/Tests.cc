// Copyright 2026 Parc contributors.
#include "../Support/TestFailure.h"

#include <algorithm>
#include <cstdio>
#include <fstream>
#include <iostream>
#include <iterator>
#include <sstream>
#include <string>
#include <string_view>
#include <vector>

#include "webui_branding_rules.h"

using parc::branding::ApplyResourceEdits;
using parc::branding::Edit;
using parc::branding::EditGroup;
using parc::branding::EditOutcome;
using parc::branding::FindEdit;
using parc::branding::FindResourceEdits;
using parc::branding::kAdaptiveLogoSvg;
using parc::branding::kDarkLogoSvg;
using parc::branding::kMarkPath;
using parc::branding::kPaddedLogoSvg;
using parc::branding::kProductIcon;
using parc::branding::kResourceEdits;
using parc::branding::ParsePath;
using parc::branding::ResourceEdits;

namespace {

size_t Count(std::string_view text, std::string_view needle) {
  size_t count = 0;
  for (size_t at = text.find(needle); at != std::string_view::npos;
       at = text.find(needle, at + needle.size())) {
    ++count;
  }
  return count;
}

bool Has(const std::vector<std::string_view>& names, std::string_view name) {
  for (std::string_view entry : names) {
    if (entry == name) {
      return true;
    }
  }
  return false;
}

const ResourceEdits& Rules(std::string_view name) {
  const ResourceEdits* rules = FindResourceEdits(name);
  PARC_EXPECT(rules != nullptr);
  return *rules;
}

std::string ChromiumIcon(std::string_view viewbox) {
  return std::string("      <g id=\"chrome-product\"") + std::string(viewbox) +
         ">\n        <path d=\"M9.45 14.574c.698.7 1.55 1.051 2.55 1.051Z\">"
         "\n        </path>\n      </g>\n";
}

std::string IconSet(int size, int product_icons) {
  std::string text = "<cr-iconset name=\"cr\" size=\"" + std::to_string(size) +
                     "\">\n  <svg>\n    <defs>\n      <g id=\"chevron-left\">"
                     "<path d=\"M15.41 7.41L14 6z\"></path></g>\n";
  for (int i = 0; i < product_icons; ++i) {
    text += ChromiumIcon(i % 2 ? " viewBox=\"0 -960 960 960\"" : "");
  }
  return text + "      <g id=\"close\"><path d=\"M19 6.41z\"></path></g>\n"
                "    </defs>\n  </svg>\n</cr-iconset>\n";
}

constexpr std::string_view kAboutTemplate =
    "<settings-section page-title=\"$i18n{aboutPageTitle}\">\n"
    "  <div class=\"cr-row two-line first\">\n"
    "    <img id=\"productLogo\" @click=\"${this.onProductLogoClick_}\"\n"
    "        srcset=\"chrome://theme/current-channel-logo@1x 1x,\n"
    "                chrome://theme/current-channel-logo@2x 2x\"\n"
    "        alt=\"$i18n{aboutProductLogoAlt}\"\n"
    "        role=\"presentation\">\n"
    "    <div class=\"product-title\">$i18n{aboutProductTitle}</div>\n"
    "  </div>\n";

void TestMarkPath() {
  const auto commands = ParsePath(kMarkPath);
  PARC_EXPECT(commands.has_value());
  size_t contours = 0;
  float top = 24, bottom = 0, left = 24, right = 0;
  for (const auto& command : *commands) {
    PARC_EXPECT(command.verb == 'M' || command.verb == 'C' ||
                command.verb == 'Z');
    contours += command.verb == 'M';
    const size_t arity = command.verb == 'C' ? 6 : command.verb == 'M' ? 2 : 0;
    for (size_t i = 0; i < arity; i += 2) {
      left = std::min(left, command.values[i]);
      right = std::max(right, command.values[i]);
      top = std::min(top, command.values[i + 1]);
      bottom = std::max(bottom, command.values[i + 1]);
    }
  }
  PARC_EXPECT(contours == 2);
  PARC_EXPECT(top > 1.9f && top < 2.4f);
  PARC_EXPECT(bottom > 21.6f && bottom < 22.1f);
  PARC_EXPECT(left > 5 && right < 19.2f);
  PARC_EXPECT(Count(kDarkLogoSvg, kMarkPath) == 1);
  PARC_EXPECT(kDarkLogoSvg.starts_with("<svg xmlns=\"http://www.w3.org/2000/svg\""));
  PARC_EXPECT(kDarkLogoSvg.ends_with("</svg>"));
  PARC_EXPECT(Count(kDarkLogoSvg, "fill=\"#fff\"") == 1);
  PARC_EXPECT(Count(kAdaptiveLogoSvg, kMarkPath) == 1);
  PARC_EXPECT(kAdaptiveLogoSvg.starts_with("<svg xmlns=\"http://www.w3.org/2000/svg\""));
  PARC_EXPECT(Count(kAdaptiveLogoSvg, "path{fill:#000}") == 1);
  PARC_EXPECT(Count(kAdaptiveLogoSvg,
                    "@media (prefers-color-scheme: dark){path{fill:#fff}}") == 1);
  PARC_EXPECT(Count(kPaddedLogoSvg, kMarkPath) == 1);
  PARC_EXPECT(Count(kPaddedLogoSvg, "viewBox=\"-12 -12 48 48\"") == 1);
  PARC_EXPECT(kPaddedLogoSvg.substr(kPaddedLogoSvg.find("<style>")) ==
              kAdaptiveLogoSvg.substr(kAdaptiveLogoSvg.find("<style>")));
  PARC_EXPECT(Count(kProductIcon, kMarkPath) == 1);
  PARC_EXPECT(kProductIcon.starts_with("<g id=\"chrome-product\" viewBox=\"0 0 24 24\">"));
  PARC_EXPECT(kProductIcon.ends_with("</path></g>"));
  PARC_EXPECT(Count(kProductIcon, "<g") == 1);
}

void TestPathParser() {
  PARC_EXPECT(!ParsePath("").has_value());
  PARC_EXPECT(!ParsePath("C1 2 3 4 5 6Z").has_value());
  PARC_EXPECT(!ParsePath("M1 2C1 2Z").has_value());
  PARC_EXPECT(!ParsePath("M1 2L3 4").has_value());
  PARC_EXPECT(!ParsePath("M1 2X3 4Z").has_value());
  PARC_EXPECT(!ParsePath("M1 2M3 4Z").has_value());
  PARC_EXPECT(!ParsePath("M1 2L.Z").has_value());
  const auto parsed = ParsePath("M1 2L3.5 -4Z M.25 6C1 2 3 4 5 6Z");
  PARC_EXPECT(parsed.has_value() && parsed->size() == 6);
  PARC_EXPECT((*parsed)[1].values[0] == 3.5f && (*parsed)[1].values[1] == -4);
  PARC_EXPECT((*parsed)[3].values[0] == 0.25f);
}

void TestCrIcons() {
  const ResourceEdits& rules = Rules("IDR_WEBUI_CR_ELEMENTS_ICONS_HTML_JS");
  const std::string original = IconSet(20, 0) + IconSet(24, 1) + IconSet(24, 1);
  std::string text = original;
  EditOutcome outcome = ApplyResourceEdits(text, rules);
  PARC_EXPECT(outcome.failed.empty() && Has(outcome.applied, "product icon"));
  PARC_EXPECT(Count(text, kProductIcon) == 2);
  PARC_EXPECT(Count(text, "M9.45 14.574") == 0);
  PARC_EXPECT(Count(text, "<g id=\"chevron-left\">") == 3);
  PARC_EXPECT(Count(text, "<g id=\"close\">") == 3);

  std::string one = IconSet(24, 1);
  outcome = ApplyResourceEdits(one, rules);
  PARC_EXPECT(Has(outcome.failed, "product icon") && outcome.applied.empty());
  PARC_EXPECT(one == IconSet(24, 1));

  std::string three = IconSet(24, 3);
  outcome = ApplyResourceEdits(three, rules);
  PARC_EXPECT(Has(outcome.failed, "product icon"));
  PARC_EXPECT(three == IconSet(24, 3));

  const std::string unclosed_copy =
      ChromiumIcon("") + "<g id=\"chrome-product\"><path d=\"M1 2Z\"></path>";
  std::string unclosed = unclosed_copy;
  outcome = ApplyResourceEdits(unclosed, rules);
  PARC_EXPECT(Has(outcome.failed, "product icon"));
  PARC_EXPECT(unclosed == unclosed_copy);

  const std::string nested_copy =
      ChromiumIcon("") +
      "<g id=\"chrome-product\"><g><path d=\"M1 2Z\"></path></g></g>";
  std::string nested = nested_copy;
  outcome = ApplyResourceEdits(nested, rules);
  PARC_EXPECT(Has(outcome.failed, "product icon"));
  PARC_EXPECT(nested == nested_copy);
}

void TestSettingsBundle() {
  const ResourceEdits& rules = Rules("IDR_SETTINGS_SHARED_ROLLUP_JS");
  const std::string bundle = "const a=1;" + IconSet(24, 2) + "x" +
                             IconSet(20, 2) + std::string(kAboutTemplate) +
                             "<cr-icon icon=\"cr:chrome-product\"></cr-icon>";
  std::string text = bundle;
  EditOutcome outcome = ApplyResourceEdits(text, rules);
  PARC_EXPECT(outcome.failed.empty());
  PARC_EXPECT(Has(outcome.applied, "product icon") &&
              Has(outcome.applied, "About logo"));
  PARC_EXPECT(Count(text, kProductIcon) == 4);
  PARC_EXPECT(Count(text, "<picture style=\"display: contents\">") == 1);
  PARC_EXPECT(Count(text, "srcset=\"//resources/images/chrome_logo_dark.svg\"><img "
                          "id=\"productLogo\" width=\"32\" height=\"32\" @click") == 1);
  PARC_EXPECT(Count(text, "role=\"presentation\">\n    </picture><div "
                          "class=\"product-title\">") == 1);
  PARC_EXPECT(Count(text, "<cr-icon icon=\"cr:chrome-product\"></cr-icon>") == 1);

  std::string missing_icon = "const a=1;" + IconSet(24, 2) + IconSet(20, 1) +
                             std::string(kAboutTemplate);
  const std::string missing_icon_copy = missing_icon;
  outcome = ApplyResourceEdits(missing_icon, rules);
  PARC_EXPECT(Has(outcome.failed, "product icon"));
  PARC_EXPECT(Has(outcome.applied, "About logo"));
  PARC_EXPECT(Count(missing_icon, kProductIcon) == 0);
  PARC_EXPECT(Count(missing_icon, "<picture style=\"display: contents\">") == 1);

  std::string twice = IconSet(24, 2) + IconSet(20, 2) +
                      std::string(kAboutTemplate) + std::string(kAboutTemplate);
  outcome = ApplyResourceEdits(twice, rules);
  PARC_EXPECT(Has(outcome.failed, "About logo"));
  PARC_EXPECT(Has(outcome.applied, "product icon"));
  PARC_EXPECT(Count(twice, "<picture") == 0);

  std::string half = IconSet(24, 2) + IconSet(20, 2) +
                     "<img id=\"productLogo\" srcset=\"x\">";
  outcome = ApplyResourceEdits(half, rules);
  PARC_EXPECT(Has(outcome.failed, "About logo"));
  PARC_EXPECT(Count(half, "<picture") == 0 && Count(half, "</picture>") == 0);
}

void TestVersionAndFieldTrials() {
  const ResourceEdits& version = Rules("IDR_VERSION_UI_ABOUT_VERSION_HTML");
  std::string html =
      "<img alt=\"$i18n{logo_alt_text}\" src=\"chrome://theme/IDR_PRODUCT_LOGO\">"
      "<div id=\"copyright\">$i18n{copyright}</div>"
      "<td class=\"label\">$i18n{application_label}</td>";
  EditOutcome outcome = ApplyResourceEdits(html, version);
  PARC_EXPECT(outcome.failed.empty() && outcome.applied.size() == 3);
  PARC_EXPECT(Count(html, "alt=\"Parc\"") == 1);
  PARC_EXPECT(Count(html, "<a href=\"chrome://license/\">Parc licences</a>") == 1);
  PARC_EXPECT(Count(html, "<td class=\"label\">Parc</td>") == 1);

  std::string changed = "<img alt=\"$i18n{logo_alt_text}\">"
                        "<div id=\"copyright\" class=\"x\">$i18n{copyright}</div>"
                        "$i18n{application_label}";
  outcome = ApplyResourceEdits(changed, version);
  PARC_EXPECT(outcome.failed.size() == 1 && Has(outcome.failed, "licence links"));
  PARC_EXPECT(Count(changed, "alt=\"Parc\"") == 1);

  const ResourceEdits& trials = Rules("IDR_METRICS_INTERNALS_FIELD_TRIALS_HTML_JS");
  std::string script =
      "Your changes will take effect the next time you relaunch Chromium.";
  outcome = ApplyResourceEdits(script, trials);
  PARC_EXPECT(outcome.failed.empty());
  PARC_EXPECT(script == "Your changes will take effect the next time you relaunch Parc.");
  std::string reworded = "Relaunch Chromium to apply your changes.";
  outcome = ApplyResourceEdits(reworded, trials);
  PARC_EXPECT(Has(outcome.failed, "relaunch notice"));
  PARC_EXPECT(reworded == "Relaunch Chromium to apply your changes.");
}

void TestOverlapAndLookup() {
  static constexpr Edit kFirst[] = {{"abc", {}, "1", 1}};
  static constexpr Edit kSecond[] = {{"bcd", {}, "2", 1}};
  static constexpr EditGroup kGroups[] = {{"first", kFirst}, {"second", kSecond}};
  static constexpr ResourceEdits kOverlap = {"TEST", kGroups};
  std::string text = "xabcdx";
  const EditOutcome outcome = ApplyResourceEdits(text, kOverlap);
  PARC_EXPECT(outcome.applied.empty() && outcome.failed.size() == 2);
  PARC_EXPECT(text == "xabcdx");
  PARC_EXPECT(FindResourceEdits("IDR_NOT_BRANDED") == nullptr);
  PARC_EXPECT(!FindEdit("abc", {"", {}, "x", 0}).has_value());
  PARC_EXPECT(std::size(kResourceEdits) == 4);
  const auto spans = FindEdit("<g id=\"chrome-product\">x</g>", {"<g id=\"chrome-product\"", "</g>", "y", 1});
  PARC_EXPECT(spans.has_value() && spans->size() == 1 && (*spans)[0].end == 28);
}

std::string ReadFile(const char* path) {
  std::ifstream input(path, std::ios::binary);
  PARC_EXPECT(input.good());
  std::ostringstream contents;
  contents << input.rdbuf();
  return contents.str();
}

int Apply(const char* name, const char* input, const char* output) {
  const ResourceEdits* rules = FindResourceEdits(name);
  if (!rules) {
    std::cout << "unknown resource " << name << "\n";
    return 2;
  }
  std::string text = ReadFile(input);
  const EditOutcome outcome = ApplyResourceEdits(text, *rules);
  for (std::string_view group : outcome.applied) {
    std::cout << "applied\t" << group << "\n";
  }
  for (std::string_view group : outcome.failed) {
    std::cout << "failed\t" << group << "\n";
  }
  std::ofstream(output, std::ios::binary) << text;
  return outcome.failed.empty() ? 0 : 1;
}

int Presence(const char* name, int count, char** inputs) {
  const ResourceEdits* rules = FindResourceEdits(name);
  if (!rules) {
    std::cout << "unknown resource " << name << "\n";
    return 2;
  }
  std::string text;
  for (int i = 0; i < count; ++i) {
    text += ReadFile(inputs[i]);
  }
  int status = 0;
  size_t edits = 0;
  for (const EditGroup& group : rules->groups) {
    for (const Edit& edit : group.edits) {
      const auto found = FindEdit(text, edit);
      const size_t matches = found ? found->size() : 0;
      std::cout << (matches ? "present\t" : "missing\t") << group.name << "\t"
                << matches << "\t" << edit.from << "\n";
      if (!matches) {
        status = 1;
      }
      ++edits;
    }
  }
  std::cout << "edits\t" << edits << "\n";
  return status;
}

}

int main(int argc, char** argv) {
  const std::string_view mode = argc > 1 ? argv[1] : "unit";
  if (mode == "unit") {
    TestMarkPath();
    TestPathParser();
    TestCrIcons();
    TestSettingsBundle();
    TestVersionAndFieldTrials();
    TestOverlapAndLookup();
    std::cout << "webui branding rules: ok\n";
    return 0;
  }
  if (mode == "mark") {
    std::cout << kMarkPath;
    return 0;
  }
  if (mode == "svg") {
    std::cout << kDarkLogoSvg;
    return 0;
  }
  if (mode == "adaptive") {
    std::cout << kAdaptiveLogoSvg;
    return 0;
  }
  if (mode == "padded") {
    std::cout << kPaddedLogoSvg;
    return 0;
  }
  if (mode == "icon") {
    std::cout << kProductIcon;
    return 0;
  }
  if (mode == "names") {
    for (const ResourceEdits& rules : kResourceEdits) {
      std::cout << rules.resource << "\n";
    }
    return 0;
  }
  if (mode == "apply" && argc == 5) {
    return Apply(argv[2], argv[3], argv[4]);
  }
  if (mode == "presence" && argc > 3) {
    return Presence(argv[2], argc - 3, argv + 3);
  }
  std::cerr << "usage: check [unit|mark|svg|adaptive|padded|icon|names|apply NAME IN OUT|"
               "presence NAME FILE...]\n";
  return 2;
}
