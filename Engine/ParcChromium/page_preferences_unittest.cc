// Copyright 2026 Parc contributors.
#include "parc/page_preferences.h"

#include "content/public/browser/content_browser_client.h"
#include "content/public/browser/web_contents.h"
#include "content/public/common/content_client.h"
#include "content/public/test/test_renderer_host.h"
#include "testing/gtest/include/gtest/gtest.h"
#include "third_party/blink/public/common/web_preferences/web_preferences.h"

namespace parc {
namespace {
class PreferenceClient final : public content::ContentBrowserClient {
 public:
  void OverrideWebPreferences(content::WebContents* contents,
                              content::SiteInstance&,
                              blink::web_pref::WebPreferences* prefs) override {
    ApplyPagePreferences(*contents, *prefs);
  }
};
class PagePreferencesTest : public content::RenderViewHostTestHarness {
 public:
  void SetUp() override {
    RenderViewHostTestHarness::SetUp();
    previous_ = content::SetBrowserClientForTesting(&client_);
  }
  void TearDown() override {
    content::SetBrowserClientForTesting(previous_);
    RenderViewHostTestHarness::TearDown();
  }
 private:
  PreferenceClient client_;
  content::ContentBrowserClient* previous_ = nullptr;
};

TEST_F(PagePreferencesTest, PowerStateSurvivesRecomputation) {
  SetMediaPowerRestricted(*web_contents(), true);
  web_contents()->OnWebPreferencesChanged();
  EXPECT_TRUE(web_contents()->GetOrCreateWebPreferences().parc_media_power_restricted);
  SetMediaPowerRestricted(*web_contents(), false);
  web_contents()->OnWebPreferencesChanged();
  EXPECT_FALSE(web_contents()->GetOrCreateWebPreferences().parc_media_power_restricted);
}

TEST_F(PagePreferencesTest, AttachmentSurvivesRecomputationAndPowerChanges) {
  EXPECT_FALSE(web_contents()->GetOrCreateWebPreferences().parc_page_in_window);
  EXPECT_TRUE(SetPageInWindow(*web_contents(), true));
  SetMediaPowerRestricted(*web_contents(), true);
  web_contents()->OnWebPreferencesChanged();
  EXPECT_TRUE(web_contents()->GetOrCreateWebPreferences().parc_page_in_window);
  EXPECT_TRUE(SetPageInWindow(*web_contents(), false));
  web_contents()->OnWebPreferencesChanged();
  EXPECT_FALSE(web_contents()->GetOrCreateWebPreferences().parc_page_in_window);
  EXPECT_TRUE(web_contents()->GetOrCreateWebPreferences().parc_media_power_restricted);
}
}
}
