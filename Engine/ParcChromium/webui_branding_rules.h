// Copyright 2026 Parc contributors.
#ifndef PARC_WEBUI_BRANDING_RULES_H_
#define PARC_WEBUI_BRANDING_RULES_H_

#include <algorithm>
#include <array>
#include <cstddef>
#include <optional>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

#define PARC_MARK_PATH \
    "M6.88 12.15C6.39 11.81 5.69 11.47 5.51 10.86" \
    "C5.29 10.14 6.02 9.59 6.88 10.12C6.93 9.8 6.9 9.45 6.9 9.13" \
    "C6.89 8.33 6.84 5.81 6.93 5.19C6.99 4.84 7.11 4.48 7.29 4.17" \
    "C8.19 2.58 10.24 2.25 11.92 2.24C13.52 2.24 15.26 2.53 16.55 3.54" \
    "C17.09 3.97 17.53 4.52 17.85 5.14C18.79 7.01 18.81 9.92 17.46 11.6" \
    "C16.84 12.38 16.06 12.92 15.14 13.31" \
    "C14.11 13.75 12.95 13.91 11.84 13.93" \
    "C11.55 13.93 11.25 13.91 10.95 13.91" \
    "C10.9 14.29 10.94 17.47 10.95 18.12C10.95 18.72 10.98 19.3 11.51 19.67" \
    "C11.98 19.99 12.73 19.86 12.96 19.31" \
    "C13.13 18.92 12.9 18.61 13.35 18.27C13.97 17.8 14.69 18.39 14.69 19.08" \
    "C14.68 20.07 13.82 20.89 12.98 21.28C11.35 22.05 8.91 21.93 7.67 20.48" \
    "C6.84 19.51 6.89 18.48 6.9 17.29C6.91 16.09 6.9 14.89 6.9 13.69" \
    "C6.89 13.24 6.94 12.57 6.88 12.15ZM10.95 5.37" \
    "C10.89 6 10.94 7.49 10.94 8.22C10.94 8.83 10.94 9.44 10.94 10.05" \
    "C10.94 10.43 10.92 10.83 10.95 11.21" \
    "C11.32 11.28 12.19 11.14 12.59 11.04C13.31 10.86 14 10.58 14.53 10.03" \
    "C15.57 8.96 15.58 6.94 14.42 5.94C13.7 5.31 12.73 5.21 11.81 5.25" \
    "C11.53 5.27 11.21 5.28 10.95 5.37Z"

namespace parc::branding {

inline constexpr std::string_view kMarkPath = PARC_MARK_PATH;

inline constexpr std::string_view kDarkLogoSvg =
    "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"24\" height=\"24\" "
    "viewBox=\"0 0 24 24\"><path fill=\"#fff\" d=\"" PARC_MARK_PATH
    "\"/></svg>";

inline constexpr std::string_view kAdaptiveLogoSvg =
    "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 24 24\"><style>"
    "path{fill:#000}@media (prefers-color-scheme: dark){path{fill:#fff}}"
    "</style><path d=\"" PARC_MARK_PATH "\"/></svg>";

inline constexpr std::string_view kPaddedLogoSvg =
    "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"-12 -12 48 48\"><style>"
    "path{fill:#000}@media (prefers-color-scheme: dark){path{fill:#fff}}"
    "</style><path d=\"" PARC_MARK_PATH "\"/></svg>";

inline constexpr std::string_view kProductIcon =
    "<g id=\"chrome-product\" viewBox=\"0 0 24 24\"><path d=\"" PARC_MARK_PATH
    "\"></path></g>";

#undef PARC_MARK_PATH

template <typename T>
struct List {
  template <size_t N>
  constexpr List(const T (&array)[N]) : items(array), size(N) {}
  constexpr const T* begin() const { return items; }
  constexpr const T* end() const { return items + size; }
  const T* items;
  size_t size;
};

struct Edit {
  std::string_view from;
  std::string_view through;
  std::string_view replacement;
  size_t count;
};

struct EditGroup {
  std::string_view name;
  List<Edit> edits;
};

struct ResourceEdits {
  std::string_view resource;
  List<EditGroup> groups;
};

inline constexpr std::string_view kProductIconStart = "<g id=\"chrome-product\"";

inline constexpr Edit kCrIconEdits[] = {
    {kProductIconStart, "</g>", kProductIcon, 2}};

inline constexpr Edit kSettingsIconEdits[] = {
    {kProductIconStart, "</g>", kProductIcon, 4}};

inline constexpr Edit kAboutLogoEdits[] = {
    {"<img id=\"productLogo\"", {},
     "<picture style=\"display: contents\"><source "
     "media=\"(prefers-color-scheme: dark)\" "
     "srcset=\"//resources/images/chrome_logo_dark.svg\"><img "
     "id=\"productLogo\" width=\"32\" height=\"32\"",
     1},
    {"<div class=\"product-title\">", {},
     "</picture><div class=\"product-title\">", 1}};

inline constexpr Edit kRelaunchEdits[] = {
    {"the next time you relaunch Chromium.", {},
     "the next time you relaunch Parc.", 1}};

inline constexpr Edit kVersionLicenceEdits[] = {
    {"<div id=\"copyright\">$i18n{copyright}</div>", {},
     "<div id=\"copyright\">$i18n{copyright}<br>"
     "<a href=\"chrome://license/\">Parc licences</a> | "
     "<a href=\"chrome://credits/\">Third-party credits</a></div>",
     1}};

inline constexpr Edit kVersionLogoEdits[] = {
    {"alt=\"$i18n{logo_alt_text}\"", {}, "alt=\"Parc\"", 1}};

inline constexpr Edit kVersionLabelEdits[] = {
    {"$i18n{application_label}", {}, "Parc", 1}};

inline constexpr EditGroup kCrIconGroups[] = {{"product icon", kCrIconEdits}};

inline constexpr EditGroup kSettingsGroups[] = {
    {"product icon", kSettingsIconEdits},
    {"About logo", kAboutLogoEdits}};

inline constexpr EditGroup kFieldTrialGroups[] = {
    {"relaunch notice", kRelaunchEdits}};

inline constexpr EditGroup kVersionGroups[] = {
    {"licence links", kVersionLicenceEdits},
    {"logo text", kVersionLogoEdits},
    {"application label", kVersionLabelEdits}};

inline constexpr ResourceEdits kResourceEdits[] = {
    {"IDR_WEBUI_CR_ELEMENTS_ICONS_HTML_JS", kCrIconGroups},
    {"IDR_SETTINGS_SHARED_ROLLUP_JS", kSettingsGroups},
    {"IDR_METRICS_INTERNALS_FIELD_TRIALS_HTML_JS", kFieldTrialGroups},
    {"IDR_VERSION_UI_ABOUT_VERSION_HTML", kVersionGroups},
};

inline const ResourceEdits* FindResourceEdits(std::string_view resource) {
  for (const ResourceEdits& edits : kResourceEdits) {
    if (edits.resource == resource) {
      return &edits;
    }
  }
  return nullptr;
}

struct Span {
  size_t begin;
  size_t end;
  std::string_view replacement;
};

inline std::optional<std::vector<Span>> FindEdit(std::string_view text,
                                                 const Edit& edit) {
  if (edit.from.empty()) {
    return std::nullopt;
  }
  std::vector<Span> spans;
  size_t position = 0;
  while ((position = text.find(edit.from, position)) != std::string_view::npos) {
    size_t end = position + edit.from.size();
    if (!edit.through.empty()) {
      const size_t close = text.find(edit.through, end);
      const std::string_view tag = edit.from.substr(0, edit.from.find(' '));
      if (close == std::string_view::npos ||
          text.substr(end, close - end).find(tag) != std::string_view::npos) {
        return std::nullopt;
      }
      end = close + edit.through.size();
    }
    spans.push_back({position, end, edit.replacement});
    position = end;
  }
  return spans;
}

inline std::optional<std::vector<Span>> FindGroup(std::string_view text,
                                                  const EditGroup& group) {
  std::vector<Span> spans;
  for (const Edit& edit : group.edits) {
    const auto found = FindEdit(text, edit);
    if (!found || found->size() != edit.count) {
      return std::nullopt;
    }
    spans.insert(spans.end(), found->begin(), found->end());
  }
  return spans;
}

struct EditOutcome {
  std::vector<std::string_view> applied;
  std::vector<std::string_view> failed;
};

inline EditOutcome ApplyResourceEdits(std::string& text,
                                      const ResourceEdits& resource) {
  EditOutcome outcome;
  std::vector<Span> spans;
  for (const EditGroup& group : resource.groups) {
    const auto found = FindGroup(text, group);
    if (!found) {
      outcome.failed.push_back(group.name);
      continue;
    }
    spans.insert(spans.end(), found->begin(), found->end());
    outcome.applied.push_back(group.name);
  }
  std::sort(spans.begin(), spans.end(),
            [](const Span& a, const Span& b) { return a.begin < b.begin; });
  size_t size = text.size();
  for (size_t i = 0; i < spans.size(); ++i) {
    if (i > 0 && spans[i].begin < spans[i - 1].end) {
      outcome.failed.insert(outcome.failed.end(), outcome.applied.begin(),
                            outcome.applied.end());
      outcome.applied.clear();
      return outcome;
    }
    size = size - (spans[i].end - spans[i].begin) + spans[i].replacement.size();
  }
  if (spans.empty()) {
    return outcome;
  }
  std::string edited;
  edited.reserve(size);
  size_t cursor = 0;
  for (const Span& span : spans) {
    edited.append(text, cursor, span.begin - cursor);
    edited.append(span.replacement);
    cursor = span.end;
  }
  edited.append(text, cursor, std::string::npos);
  text = std::move(edited);
  return outcome;
}

struct PathCommand {
  char verb;
  std::array<float, 6> values;
};

inline std::optional<std::vector<PathCommand>> ParsePath(std::string_view path) {
  std::vector<PathCommand> commands;
  size_t i = 0;
  const auto skip = [&] {
    while (i < path.size() && (path[i] == ' ' || path[i] == ',')) {
      ++i;
    }
  };
  const auto digit = [&] {
    return i < path.size() && path[i] >= '0' && path[i] <= '9';
  };
  const auto number = [&](float& value) {
    skip();
    const bool negative = i < path.size() && path[i] == '-';
    if (negative) {
      ++i;
    }
    double result = 0;
    bool digits = false;
    while (digit()) {
      result = result * 10 + (path[i++] - '0');
      digits = true;
    }
    if (i < path.size() && path[i] == '.') {
      ++i;
      double place = 0.1;
      while (digit()) {
        result += (path[i++] - '0') * place;
        place /= 10;
        digits = true;
      }
    }
    value = static_cast<float>(negative ? -result : result);
    return digits;
  };
  while (true) {
    skip();
    if (i == path.size()) {
      break;
    }
    const char verb = path[i++];
    size_t arity = 0;
    if (verb == 'M' || verb == 'L') {
      arity = 2;
    } else if (verb == 'C') {
      arity = 6;
    } else if (verb != 'Z') {
      return std::nullopt;
    }
    const bool starts_contour = commands.empty() || commands.back().verb == 'Z';
    if (starts_contour != (verb == 'M')) {
      return std::nullopt;
    }
    PathCommand command{verb, {}};
    for (size_t k = 0; k < arity; ++k) {
      if (!number(command.values[k])) {
        return std::nullopt;
      }
    }
    commands.push_back(command);
  }
  if (commands.empty() || commands.back().verb != 'Z') {
    return std::nullopt;
  }
  return commands;
}

}

#endif
