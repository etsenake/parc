#include "location_bar.h"

#include "base/run_loop.h"
#include "base/test/scoped_feature_list.h"
#include "chrome/app/chrome_command_ids.h"
#include "chrome/browser/ui/browser.h"
#include "chrome/browser/ui/browser_command_controller.h"
#include "chrome/browser/ui/browser_tabstrip.h"
#include "chrome/browser/ui/omnibox/omnibox_controller.h"
#include "chrome/browser/ui/omnibox/omnibox_edit_model.h"
#include "chrome/browser/ui/omnibox/omnibox_view.h"
#include "chrome/browser/ui/tabs/tab_strip_model.h"
#include "chrome/test/base/in_process_browser_test.h"
#include "components/history_embeddings/core/history_embeddings_features.h"
#include "components/omnibox/browser/location_bar_model.h"
#include "content/public/test/browser_test.h"

namespace parc {
class NativeLocationBarBrowserTest : public InProcessBrowserTest {
 public:
  NativeLocationBarBrowserTest() {
    features_.InitWithFeatures({}, {history_embeddings::kHistoryEmbeddings});
  }

 private:
  base::test::ScopedFeatureList features_;
};

IN_PROC_BROWSER_TEST_F(NativeLocationBarBrowserTest,
                       UsesOwningBrowserAndActiveTab) {
  NativeLocationBar bar(*browser());
  EXPECT_EQ(bar.GetBrowser(), browser());
  EXPECT_EQ(bar.GetProfile(), browser()->GetProfile());
  EXPECT_EQ(bar.GetLocationBarModel(), LocationBarModel::From(browser()));
  EXPECT_EQ(bar.command_updater(),
            chrome::BrowserCommandController::From(browser()));
  EXPECT_TRUE(bar.GetOmniboxController()->client()->IsChromeOmniboxClient());
  EXPECT_EQ(bar.GetOmniboxController()->edit_model()->view(),
            bar.GetOmniboxView());
  EXPECT_NE(bar.GetOmniboxController()->autocomplete_controller(), nullptr);
  bool on_device_head = false;
  for (const auto& provider :
       bar.GetOmniboxController()->autocomplete_controller()->providers()) {
    on_device_head |=
        provider->type() == AutocompleteProvider::Type::kOnDeviceHead;
  }
  EXPECT_TRUE(on_device_head);
  EXPECT_FALSE(
      bar.GetOmniboxController()->client()->IsHistoryEmbeddingsEnabled());

  auto* tabs = browser()->tab_strip_model();
  auto* original = tabs->GetActiveWebContents();
  ASSERT_NE(original, nullptr);
  chrome::AddTabAt(browser(), GURL("about:blank"), -1, true);
  EXPECT_NE(tabs->GetActiveWebContents(), original);
  EXPECT_EQ(bar.GetWebContents(), tabs->GetActiveWebContents());
  tabs->ActivateTabAt(tabs->GetIndexOfWebContents(original));
  EXPECT_EQ(bar.GetWebContents(), original);
}

IN_PROC_BROWSER_TEST_F(NativeLocationBarBrowserTest,
                       UsesRealCommandEnablement) {
  NativeLocationBar bar(*browser());
  auto* commands = bar.command_updater();
  const bool previous = commands->IsCommandEnabled(IDC_OPEN_CURRENT_URL);
  commands->UpdateCommandEnabled(IDC_OPEN_CURRENT_URL, false);
  EXPECT_FALSE(bar.GetOmniboxController()->client()->IsPasteAndGoEnabled());
  commands->UpdateCommandEnabled(IDC_OPEN_CURRENT_URL, true);
  EXPECT_TRUE(bar.GetOmniboxController()->client()->IsPasteAndGoEnabled());
  commands->UpdateCommandEnabled(IDC_OPEN_CURRENT_URL, previous);
}

IN_PROC_BROWSER_TEST_F(NativeLocationBarBrowserTest,
                       PreservesRealEditModelAndLifetime) {
  auto bar = std::make_unique<NativeLocationBar>(*browser());
  auto* view = bar->GetOmniboxView();
  auto* model = bar->GetOmniboxController()->edit_model();
  view->SetUserText(u"parc local model check", false);
  EXPECT_EQ(model->user_text(), u"parc local model check");
  EXPECT_TRUE(model->user_input_in_progress());
  EXPECT_TRUE(view->GetText().empty());
  EXPECT_EQ(view->GetSelectionBounds(), gfx::Range(0));

  bar->Revert();
  EXPECT_TRUE(model->user_input_in_progress());
  view->RevertAll();
  EXPECT_FALSE(model->user_input_in_progress());
  EXPECT_FALSE(bar->GetOmniboxController()->IsPopupOpen());
  EXPECT_FALSE(bar->IsVisible());
  EXPECT_FALSE(view->AimButtonVisible());

  bar.reset();
  base::RunLoop().RunUntilIdle();
  EXPECT_NE(LocationBarModel::From(browser()), nullptr);
  EXPECT_NE(browser()->tab_strip_model()->GetActiveWebContents(), nullptr);
}
}
