#include <memory>
#include <optional>
#include <string>
#include <utility>
#include <vector>

#include "base/functional/callback_helpers.h"
#include "base/memory/raw_ptr.h"
#include "base/run_loop.h"
#include "chrome/browser/chrome_content_browser_client.h"
#include "chrome/browser/ui/blocked_content/framebust_block_tab_helper.h"
#include "chrome/browser/ui/tabs/tab_strip_model.h"
#include "components/blocked_content/popup_blocker_tab_helper.h"
#include "components/tabs/public/tab_interface.h"
#include "content/public/browser/content_browser_client.h"
#include "content/public/browser/global_routing_id.h"
#include "content/public/browser/navigation_controller.h"
#include "content/public/browser/navigation_entry.h"
#include "content/public/browser/page_navigator.h"
#include "content/public/browser/render_frame_host.h"
#include "content/public/browser/site_instance.h"
#include "content/public/browser/web_contents.h"
#include "content/public/browser/web_contents_delegate.h"
#include "content/public/common/content_client.h"
#include "content/public/common/referrer.h"
#include "content/public/common/window_container_type.mojom-shared.h"
#include "content/public/test/navigation_simulator.h"
#include "content/public/test/test_renderer_host.h"
#include "native_popup_blocking.h"
#include "parc/tests/parc_native_test_support/browser_window_test.h"
#include "testing/gtest/include/gtest/gtest.h"
#include "third_party/blink/public/mojom/frame/triggering_event_info.mojom-shared.h"
#include "third_party/blink/public/mojom/window_features/window_features.mojom.h"
#include "ui/base/page_transition_types.h"
#include "ui/base/window_open_disposition.h"
#include "url/gurl.h"
#include "url/origin.h"

namespace parc {
namespace {

int g_changes = 0;
content::WebContents* g_changed = nullptr;

void CountChange(content::WebContents& contents) {
  ++g_changes;
  g_changed = &contents;
}

class SourceWindowDelegate final : public content::WebContentsDelegate {
 public:
  struct Created {
    content::GlobalRenderFrameHostId opener_id;
    std::string frame_name;
    GURL url;
    raw_ptr<content::WebContents> contents;
  };
  struct Added {
    GURL url;
    WindowOpenDisposition disposition;
    bool user_gesture;
    raw_ptr<content::WebContents> contents;
  };

  void WebContentsCreated(content::WebContents* source,
                          const content::GlobalRenderFrameHostId& opener_id,
                          const std::string& frame_name,
                          const GURL& target_url,
                          content::WebContents* new_contents) override {
    created.push_back({opener_id, frame_name, target_url, new_contents});
  }

  content::WebContents* AddNewContents(
      content::WebContents* source,
      std::unique_ptr<content::WebContents> new_contents,
      const GURL& target_url,
      WindowOpenDisposition disposition,
      const blink::mojom::WindowFeatures& window_features,
      bool user_gesture,
      bool* was_blocked) override {
    added.push_back({target_url, disposition, user_gesture, new_contents.get()});
    owned.push_back(std::move(new_contents));
    return owned.back().get();
  }

  content::WebContents* OpenURLFromTab(
      content::WebContents* source,
      const content::OpenURLParams& params,
      base::OnceCallback<void(content::NavigationHandle&)>) override {
    opened.push_back(params);
    return nullptr;
  }

  void Reset() {
    created.clear();
    added.clear();
    opened.clear();
    owned.clear();
  }

  std::vector<std::unique_ptr<content::WebContents>> owned;
  std::vector<Created> created;
  std::vector<Added> added;
  std::vector<content::OpenURLParams> opened;
};

}

class NativeBlockedPopupTest : public ParcBrowserWindowTest {
 protected:
  void SetUp() override {
    ParcBrowserWindowTest::SetUp();
    saved_factory_ =
        ChromeContentBrowserClient::GetPopupNavigationDelegateFactoryForTesting();
    InstallNativePopupBlocking(&CountChange);
    g_changes = 0;
    g_changed = nullptr;
    AddTab(browser(), GURL("https://opener.example/"));
    blocked_content::PopupBlockerTabHelper::CreateForWebContents(contents());
    original_delegate_ = contents()->GetDelegate();
    contents()->SetDelegate(&delegate_);
  }

  void TearDown() override {
    base::RunLoop().RunUntilIdle();
    delegate_.Reset();
    if (content::WebContents* page = contents()) {
      page->SetDelegate(original_delegate_);
    }
    original_delegate_ = nullptr;
    g_changed = nullptr;
    InstallNativePopupBlocking(nullptr);
    ChromeContentBrowserClient::GetPopupNavigationDelegateFactoryForTesting() =
        saved_factory_;
    ParcBrowserWindowTest::TearDown();
  }

  content::WebContents* contents() {
    return browser()->GetTabStripModel()->GetActiveWebContents();
  }

  bool OpenWindow(content::RenderFrameHost* opener,
                  const GURL& url,
                  const std::string& name,
                  WindowOpenDisposition disposition) {
    const bool user_gesture = false;
    const bool opener_suppressed = false;
    bool no_javascript_access = false;
    return content::GetContentClientForTesting()->browser()->CanCreateWindow(
        opener, opener->GetLastCommittedURL(),
        contents()->GetPrimaryMainFrame()->GetLastCommittedURL(),
        opener->GetLastCommittedOrigin(),
        content::mojom::WindowContainerType::NORMAL, url, content::Referrer(),
        name, disposition, blink::mojom::WindowFeatures(), user_gesture,
        opener_suppressed, &no_javascript_access);
  }

  NativeBlockedContent Blocked() {
    base::RunLoop().RunUntilIdle();
    std::optional<NativeBlockedContent> blocked =
        GetNativeBlockedContent(*contents());
    return blocked.value_or(NativeBlockedContent());
  }

  SourceWindowDelegate delegate_;

 private:
  ChromeContentBrowserClient::PopupNavigationDelegateFactory saved_factory_ =
      nullptr;
  raw_ptr<content::WebContentsDelegate> original_delegate_ = nullptr;
};

TEST_F(NativeBlockedPopupTest, ReleaseKeepsTheOpenerWhileTheSameDocumentAsked) {
  content::RenderFrameHost* opener = contents()->GetPrimaryMainFrame();
  const GURL url("https://popup.example/sign-in");
  EXPECT_FALSE(OpenWindow(opener, url, "signin",
                          WindowOpenDisposition::NEW_FOREGROUND_TAB));
  NativeBlockedContent blocked = Blocked();
  EXPECT_EQ(1, g_changes);
  EXPECT_EQ(contents(), g_changed);
  ASSERT_EQ(1u, blocked.items.size());
  EXPECT_EQ(NativeBlockedItem::Kind::kPopup, blocked.items[0].kind);
  EXPECT_EQ(url, blocked.items[0].url);
  EXPECT_EQ(GURL("https://opener.example/"), blocked.site);
  EXPECT_FALSE(blocked.allowed);

  EXPECT_TRUE(OpenNativeBlockedItem(*contents(), NativeBlockedItem::Kind::kPopup,
                                    blocked.items[0].id, blocked.revision));
  EXPECT_TRUE(delegate_.added.empty());
  base::RunLoop().RunUntilIdle();

  ASSERT_EQ(1u, delegate_.created.size());
  EXPECT_EQ(opener->GetGlobalId(), delegate_.created[0].opener_id);
  EXPECT_EQ("signin", delegate_.created[0].frame_name);
  EXPECT_EQ(url, delegate_.created[0].url);
  ASSERT_EQ(1u, delegate_.added.size());
  content::WebContents* popup = delegate_.added[0].contents;
  EXPECT_EQ(delegate_.created[0].contents, popup);
  EXPECT_EQ(url, delegate_.added[0].url);
  EXPECT_EQ(WindowOpenDisposition::NEW_FOREGROUND_TAB,
            delegate_.added[0].disposition);
  EXPECT_TRUE(delegate_.added[0].user_gesture);
  EXPECT_EQ(opener, popup->GetOpener());
  EXPECT_TRUE(popup->GetSiteInstance()->IsRelatedSiteInstance(
      opener->GetSiteInstance()));
  ASSERT_TRUE(popup->GetController().GetPendingEntry());
  EXPECT_EQ(url, popup->GetController().GetPendingEntry()->GetURL());
  EXPECT_FALSE(GetNativeBlockedContent(*contents()));
}

TEST_F(NativeBlockedPopupTest, ReleaseDropsTheOpenerOnceItsFrameShowsAnotherDocument) {
  content::RenderFrameHost* frame =
      content::RenderFrameHostTester::For(contents()->GetPrimaryMainFrame())
          ->AppendChild("embed");
  frame = content::NavigationSimulator::NavigateAndCommitFromDocument(
      GURL("https://opener.example/embed"), frame);
  ASSERT_TRUE(frame);
  const GURL url("https://popup.example/course");
  EXPECT_FALSE(OpenWindow(frame, url, "course",
                          WindowOpenDisposition::NEW_FOREGROUND_TAB));
  NativeBlockedContent blocked = Blocked();
  ASSERT_EQ(1u, blocked.items.size());

  frame = content::NavigationSimulator::NavigateAndCommitFromDocument(
      GURL("https://opener.example/elsewhere"), frame);
  ASSERT_TRUE(frame);
  NativeBlockedContent kept = Blocked();
  ASSERT_EQ(1u, kept.items.size());
  EXPECT_EQ(blocked.revision, kept.revision);

  EXPECT_TRUE(OpenNativeBlockedItem(*contents(), NativeBlockedItem::Kind::kPopup,
                                    kept.items[0].id, kept.revision));
  base::RunLoop().RunUntilIdle();

  ASSERT_EQ(1u, delegate_.created.size());
  EXPECT_EQ(content::GlobalRenderFrameHostId(), delegate_.created[0].opener_id);
  ASSERT_EQ(1u, delegate_.added.size());
  content::WebContents* popup = delegate_.added[0].contents;
  EXPECT_EQ(url, delegate_.added[0].url);
  EXPECT_TRUE(delegate_.added[0].user_gesture);
  EXPECT_FALSE(popup->HasOpener());
  EXPECT_FALSE(popup->GetSiteInstance()->IsRelatedSiteInstance(
      contents()->GetSiteInstance()));
  ASSERT_TRUE(popup->GetController().GetPendingEntry());
  EXPECT_EQ(url, popup->GetController().GetPendingEntry()->GetURL());
}

TEST_F(NativeBlockedPopupTest, OpenAllReleasesEveryPopupThroughTheSourceWindow) {
  content::RenderFrameHost* opener = contents()->GetPrimaryMainFrame();
  const GURL first("https://popup.example/one");
  const GURL second("https://popup.example/two");
  EXPECT_FALSE(OpenWindow(opener, first, "one",
                          WindowOpenDisposition::NEW_FOREGROUND_TAB));
  EXPECT_FALSE(
      OpenWindow(opener, second, "two", WindowOpenDisposition::NEW_POPUP));
  NativeBlockedContent blocked = Blocked();
  ASSERT_EQ(2u, blocked.items.size());

  EXPECT_FALSE(OpenAllNativeBlockedPopups(*contents(), blocked.revision + 1));
  base::RunLoop().RunUntilIdle();
  EXPECT_TRUE(delegate_.added.empty());
  EXPECT_EQ(2u, Blocked().items.size());

  EXPECT_TRUE(OpenAllNativeBlockedPopups(*contents(), blocked.revision));
  base::RunLoop().RunUntilIdle();

  ASSERT_EQ(2u, delegate_.created.size());
  ASSERT_EQ(2u, delegate_.added.size());
  EXPECT_EQ(first, delegate_.added[0].url);
  EXPECT_EQ(WindowOpenDisposition::NEW_FOREGROUND_TAB,
            delegate_.added[0].disposition);
  EXPECT_EQ(second, delegate_.added[1].url);
  EXPECT_EQ(WindowOpenDisposition::NEW_POPUP, delegate_.added[1].disposition);
  for (const SourceWindowDelegate::Added& added : delegate_.added) {
    EXPECT_TRUE(added.user_gesture);
    EXPECT_EQ(opener, added.contents->GetOpener());
  }
  EXPECT_FALSE(GetNativeBlockedContent(*contents()));
}

TEST_F(NativeBlockedPopupTest, GoSendsThePageToTheBlockedRedirect) {
  FramebustBlockTabHelper* redirects = FramebustBlockTabHelper::From(
      tabs::TabInterface::GetFromContents(contents()));
  ASSERT_TRUE(redirects);
  const GURL url("https://elsewhere.example/landing");
  const url::Origin initiator =
      url::Origin::Create(GURL("https://frame.example/"));
  redirects->AddBlockedUrl(url, initiator, nullptr, base::NullCallback());
  NativeNavigationBlocked(*contents());
  NativeBlockedContent blocked = Blocked();
  EXPECT_EQ(1, g_changes);
  ASSERT_EQ(1u, blocked.items.size());
  EXPECT_EQ(NativeBlockedItem::Kind::kRedirect, blocked.items[0].kind);
  EXPECT_EQ(url, blocked.items[0].url);

  EXPECT_FALSE(OpenNativeBlockedItem(
      *contents(), NativeBlockedItem::Kind::kRedirect, 1, blocked.revision));
  EXPECT_FALSE(OpenNativeBlockedItem(*contents(),
                                     NativeBlockedItem::Kind::kRedirect, 0,
                                     blocked.revision + 1));
  EXPECT_TRUE(delegate_.opened.empty());

  EXPECT_TRUE(OpenNativeBlockedItem(
      *contents(), NativeBlockedItem::Kind::kRedirect, 0, blocked.revision));
  ASSERT_EQ(1u, delegate_.opened.size());
  EXPECT_EQ(url, delegate_.opened[0].url);
  EXPECT_EQ(WindowOpenDisposition::CURRENT_TAB, delegate_.opened[0].disposition);
  EXPECT_EQ(initiator, delegate_.opened[0].initiator_origin);
  EXPECT_TRUE(delegate_.created.empty());
  EXPECT_TRUE(delegate_.added.empty());
}

TEST_F(NativeBlockedPopupTest, BlockedLinkPopupsOpenWithATrustedGesture) {
  const GURL url("https://popup.example/link");
  content::OpenURLParams params(url, content::Referrer(),
                                WindowOpenDisposition::NEW_FOREGROUND_TAB,
                                ui::PAGE_TRANSITION_LINK, true);
  params.user_gesture = false;
  EXPECT_TRUE(BlockNativeLinkPopup(contents(), params));
  NativeBlockedContent blocked = Blocked();
  ASSERT_EQ(1u, blocked.items.size());
  EXPECT_EQ(url, blocked.items[0].url);

  EXPECT_TRUE(OpenNativeBlockedItem(*contents(), NativeBlockedItem::Kind::kPopup,
                                    blocked.items[0].id, blocked.revision));
  ASSERT_EQ(1u, delegate_.opened.size());
  EXPECT_EQ(url, delegate_.opened[0].url);
  EXPECT_EQ(WindowOpenDisposition::NEW_FOREGROUND_TAB,
            delegate_.opened[0].disposition);
  EXPECT_TRUE(delegate_.opened[0].user_gesture);
  EXPECT_EQ(blink::mojom::TriggeringEventInfo::kFromTrustedEvent,
            delegate_.opened[0].triggering_event_info);
}

TEST_F(NativeBlockedPopupTest, ANewDocumentRetiresTheBlockedList) {
  content::RenderFrameHost* opener = contents()->GetPrimaryMainFrame();
  EXPECT_FALSE(OpenWindow(opener, GURL("https://popup.example/stale"), "stale",
                          WindowOpenDisposition::NEW_FOREGROUND_TAB));
  NativeBlockedContent blocked = Blocked();
  ASSERT_EQ(1u, blocked.items.size());

  content::NavigationSimulator::NavigateAndCommitFromBrowser(
      contents(), GURL("https://next.example/"));
  base::RunLoop().RunUntilIdle();
  EXPECT_FALSE(GetNativeBlockedContent(*contents()));
  EXPECT_FALSE(OpenNativeBlockedItem(*contents(),
                                     NativeBlockedItem::Kind::kPopup,
                                     blocked.items[0].id, blocked.revision));
  EXPECT_FALSE(OpenAllNativeBlockedPopups(*contents(), blocked.revision));
  base::RunLoop().RunUntilIdle();
  EXPECT_TRUE(delegate_.created.empty());
  EXPECT_TRUE(delegate_.added.empty());
}

}
