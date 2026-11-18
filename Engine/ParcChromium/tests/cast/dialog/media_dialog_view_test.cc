#include "chrome/browser/ui/views/global_media_controls/media_dialog_view.h"

#include <memory>

#include "base/functional/bind.h"
#include "base/memory/raw_ptr.h"
#include "base/test/scoped_feature_list.h"
#include "base/unguessable_token.h"
#include "chrome/browser/accessibility/live_caption/live_caption_controller_factory.h"
#include "chrome/browser/accessibility/soda_installer_impl.h"
#include "chrome/browser/media/router/chrome_media_router_factory.h"
#include "chrome/browser/ui/global_media_controls/media_notification_service.h"
#include "chrome/test/base/testing_profile.h"
#include "chrome/test/views/chrome_views_test_base.h"
#include "components/keyed_service/core/keyed_service.h"
#include "components/live_caption/pref_names.h"
#include "components/media_router/browser/media_router_factory.h"
#include "components/media_router/browser/test/mock_media_router.h"
#include "components/prefs/pref_service.h"
#include "components/soda/constants.h"
#include "components/soda/soda_installer.h"
#include "content/public/browser/web_contents.h"
#include "content/public/test/test_renderer_host.h"
#include "content/public/test/web_contents_tester.h"
#include "media/base/media_switches.h"
#include "ui/gfx/geometry/rect.h"
#include "ui/views/bubble/bubble_anchor.h"
#include "ui/views/test/widget_test.h"
#include "ui/views/widget/widget.h"

class ParcMediaDialogViewTest : public ChromeViewsTestBase {
 public:
  void SetUp() override {
    ChromeViewsTestBase::SetUp();
    web_contents_ =
        content::WebContentsTester::CreateTestWebContents(profile(), nullptr);
    media_router::ChromeMediaRouterFactory::GetInstance()->SetTestingFactory(
        profile(), base::BindRepeating(&media_router::MockMediaRouter::Create));
    media_router_ = static_cast<media_router::MockMediaRouter*>(
        media_router::MediaRouterFactory::GetApiForBrowserContext(profile()));

    notification_service_ =
        std::make_unique<MediaNotificationService>(profile(), false);
    anchor_widget_ =
        CreateTestWidget(views::Widget::InitParams::CLIENT_OWNS_WIDGET,
                         views::Widget::InitParams::TYPE_WINDOW);
    anchor_widget_->Show();
    soda_installer_impl_ = std::make_unique<speech::SodaInstallerImpl>();

    MediaDialogView::ShowDialogFromToolbar(
        views::BubbleAnchor(anchor_widget_->GetContentsView()),
        notification_service_.get(), profile());
    view_ = MediaDialogView::GetDialogViewForTesting();
  }

  void TearDown() override {
    HideDialog();
    anchor_widget_->Close();
    ChromeViewsTestBase::TearDown();
  }

 protected:
  views::Widget* anchor_widget() { return anchor_widget_.get(); }

  void HideDialog() {
    views::Widget* widget =
        MediaDialogView::IsShowing()
            ? MediaDialogView::GetDialogViewForTesting()->GetWidget()
            : nullptr;
    MediaDialogView::HideDialog();
    view_ = nullptr;
    if (widget) {
      views::test::WidgetDestroyedWaiter(widget).Wait();
    }
  }

  Profile* profile() { return &profile_; }
  content::WebContents* web_contents() { return web_contents_.get(); }
  MediaNotificationService* notification_service() {
    return notification_service_.get();
  }

 private:
  base::test::ScopedFeatureList feature_list_;
  TestingProfile profile_;
  content::RenderViewHostTestEnabler test_render_host_factories_;
  std::unique_ptr<content::WebContents> web_contents_;
  std::unique_ptr<MediaNotificationService> notification_service_;
  std::unique_ptr<views::Widget> anchor_widget_;
  raw_ptr<MediaDialogView> view_;
  raw_ptr<media_router::MockMediaRouter> media_router_;
  std::unique_ptr<speech::SodaInstallerImpl> soda_installer_impl_;
};

TEST_F(ParcMediaDialogViewTest, ParcNativePageDialogWithoutPresentation) {
  HideDialog();
  auto create = [&](base::UnguessableToken token) {
    return MediaDialogView::CreateDialogForNativePage(
        anchor_widget()->GetNativeView(), gfx::Rect(10, 10, 0, 0),
        notification_service(), profile(), web_contents(), token,
        base::BindRepeating([] { return true; }));
  };
  views::Widget* widget = create(base::UnguessableToken());
  ASSERT_TRUE(widget);
  EXPECT_TRUE(MediaDialogView::IsNativeDialogCurrent(widget));
  views::test::WidgetDestroyedWaiter destroyed(widget);
  MediaDialogView::CloseNativeDialog(widget);
  destroyed.Wait();
  EXPECT_FALSE(create(base::UnguessableToken::Create()));
}

TEST_F(ParcMediaDialogViewTest, LiveCaptionOffLeavesOutTheCaptionSection) {
  HideDialog();
  base::test::ScopedFeatureList live_caption_off;
  live_caption_off.InitAndDisableFeature(media::kLiveCaption);
  captions::LiveCaptionControllerFactory::GetInstance()->SetTestingFactory(
      profile(),
      base::BindRepeating(
          [](content::BrowserContext*) -> std::unique_ptr<KeyedService> {
            return nullptr;
          }));
  MediaDialogView::ShowDialogFromToolbar(
      views::BubbleAnchor(anchor_widget()->GetContentsView()),
      notification_service(), profile());
  MediaDialogView* view = MediaDialogView::GetDialogViewForTesting();
  ASSERT_TRUE(view);
  EXPECT_EQ(view->children().size(), 1u);

  profile()->GetPrefs()->SetBoolean(prefs::kLiveCaptionEnabled, true);
  profile()->GetPrefs()->SetBoolean(prefs::kLiveTranslateEnabled, true);
  speech::SodaInstaller* soda = speech::SodaInstaller::GetInstance();
  soda->NotifySodaProgressForTesting(50, speech::LanguageCode::kNone);
  soda->NotifySodaErrorForTesting();
  soda->NotifySodaInstalledForTesting();
  EXPECT_EQ(view->children().size(), 1u);
}
