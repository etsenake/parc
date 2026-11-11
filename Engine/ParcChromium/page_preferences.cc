// Copyright 2026 Parc contributors.
#include "parc/page_preferences.h"

#include "content/public/browser/web_contents.h"
#include "content/public/browser/web_contents_user_data.h"
#include "third_party/blink/public/common/web_preferences/web_preferences.h"

namespace parc {
namespace {
class PagePreferences final : public content::WebContentsUserData<PagePreferences> {
 public:
  bool in_window = false;
  bool power_restricted = false;
 private:
  friend class content::WebContentsUserData<PagePreferences>;
  explicit PagePreferences(content::WebContents* contents)
      : content::WebContentsUserData<PagePreferences>(*contents) {}
  WEB_CONTENTS_USER_DATA_KEY_DECL();
};
WEB_CONTENTS_USER_DATA_KEY_IMPL(PagePreferences);
PagePreferences& State(content::WebContents& contents) {
  PagePreferences::CreateForWebContents(&contents);
  return *PagePreferences::FromWebContents(&contents);
}
}

bool SetPageInWindow(content::WebContents& contents, bool in_window) {
  auto prefs = contents.GetOrCreateWebPreferences();
  State(contents).in_window = in_window;
  if (prefs.parc_page_in_window == in_window)
    return false;
  prefs.parc_page_in_window = in_window;
  contents.SetWebPreferences(prefs);
  return true;
}

void SetMediaPowerRestricted(content::WebContents& contents, bool restricted) {
  auto prefs = contents.GetOrCreateWebPreferences();
  State(contents).power_restricted = restricted;
  if (prefs.parc_media_power_restricted == restricted)
    return;
  prefs.parc_media_power_restricted = restricted;
  contents.SetWebPreferences(prefs);
}

void ApplyPagePreferences(content::WebContents& contents,
                          blink::web_pref::WebPreferences& prefs) {
  if (auto* state = PagePreferences::FromWebContents(&contents)) {
    prefs.parc_page_in_window = state->in_window;
    prefs.parc_media_power_restricted = state->power_restricted;
  }
}
}
