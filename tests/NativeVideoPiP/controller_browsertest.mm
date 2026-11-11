// Copyright 2026 Parc contributors.
// Actual Chrome Browser/WebContents + media/PiP controller, with only the
// content-browser-client factory overridden to select Parc's real overlay.
// This verifies the overlay contract, not the Parc native Browser factory.
#import <QuartzCore/QuartzCore.h>

#import "VideoPiPWindow.h"
#include "base/memory/raw_ptr.h"
#include "parc/native/video_overlay_window.h"
#include "chrome/browser/chrome_content_browser_client.h"
#include "chrome/browser/picture_in_picture/picture_in_picture_window_manager.h"
#include "chrome/browser/ui/browser_window/public/browser_window_interface.h"
#include "chrome/browser/ui/tabs/tab_strip_model.h"
#include "chrome/test/base/in_process_browser_test.h"
#include "chrome/test/base/ui_test_utils.h"
#include "content/public/browser/overlay_window.h"
#include "content/public/browser/video_picture_in_picture_window_controller.h"
#include "content/public/common/content_client.h"
#include "content/public/test/browser_test.h"
#include "content/public/test/browser_test_utils.h"
#include "net/test/embedded_test_server/embedded_test_server.h"

@interface PiPTestApplication : NSObject <PCNativeBrowserApplicationClient>
@property(nonatomic, strong) PCVideoPiPPresenter* presenter;
@end
@implementation PiPTestApplication
@synthesize presenter = _presenter;
- (id<PCNativeVideoPiPWindow>)
    createVideoPictureInPictureWindow:(NSView*)view
                          sourceFrame:(NSRect)frame
                               action:(void (^)(PCVideoPiPAction, double))action
                              changed:(dispatch_block_t)changed {
  self.presenter = [[PCVideoPiPPresenter alloc] initWithVideoView:view
                                                      sourceFrame:frame
                                                           action:action
                                                          changed:changed];
  return self.presenter;
}
- (void)releaseVideoPictureInPictureWindow:(id<PCNativeVideoPiPWindow>)window {
  [window invalidate];
  if (self.presenter == window) {
    self.presenter = nil;
  }
}
- (void)nativeApplicationDownloadDidUpdate:(NSDictionary*)update {
}
- (id<PCNativeBrowserWindowClient>)
    prepareNativeWindowForRequest:(PCNativeWindowRequest*)request {
  return nil;
}
- (void)nativeApplicationRelaunchedWithArguments:(NSArray*)arguments
                                currentDirectory:(NSString*)directory {
}
@end
namespace {
class BrowserClient : public ChromeContentBrowserClient {
 public:
  std::unique_ptr<content::VideoOverlayWindow>
  CreateWindowForVideoPictureInPicture(
      content::VideoPictureInPictureWindowController* controller) override {
    return parc::CreateNativeVideoOverlayWindow(controller);
  }
};
NSButton* FindAction(NSView* view, NSInteger tag) {
  for (NSView* child in view.subviews) {
    if ([child isKindOfClass:NSButton.class] && child.tag == tag) {
      return (NSButton*)child;
    }
    if (auto* button = FindAction(child, tag)) {
      return button;
    }
  }
  return nil;
}
}  // namespace
class NativeVideoControllerTest : public InProcessBrowserTest {
 public:
  void SetUpOnMainThread() override {
    InProcessBrowserTest::SetUpOnMainThread();
    application_ = [PiPTestApplication new];
    [PCNativeBrowserApplication setApplicationClient:application_];
    previous_ = content::SetBrowserClientForTesting(&client_);
    embedded_test_server()->ServeFilesFromSourceDirectory("media/test/data");
    ASSERT_TRUE(embedded_test_server()->Start());
  }
  void TearDownOnMainThread() override {
    PictureInPictureWindowManager::GetInstance()->ExitPictureInPicture();
    content::SetBrowserClientForTesting(previous_);
    [application_.presenter invalidate];
    application_ = nil;
    InProcessBrowserTest::TearDownOnMainThread();
  }
  void Open() {
    ASSERT_TRUE(ui_test_utils::NavigateToURL(
        browser(), embedded_test_server()->GetURL("/bear.webm")));
    ASSERT_TRUE(content::ExecJs(contents(), R"(
      (async () => { const v=document.querySelector('video'); v.muted=true;
        v.loop=true; await v.play(); window.pipWindow = await v.requestPictureInPicture(); })()
    )"));
    ASSERT_TRUE(application_.presenter);
    ASSERT_TRUE(controller()->GetWindowForTesting()->IsVisible());
  }
  content::WebContents* contents() {
    return browser()->tab_strip_model()->GetActiveWebContents();
  }
  content::VideoPictureInPictureWindowController* controller() {
    return content::PictureInPictureWindowController::
        GetOrCreateVideoPictureInPictureController(contents());
  }
  void Click(PCVideoPiPAction action) {
    [FindAction(application_.presenter.panel.contentView, action)
        performClick:nil];
  }

 protected:
  PiPTestApplication* __strong application_;

 private:
  BrowserClient client_;
  raw_ptr<content::ContentBrowserClient> previous_ = nullptr;
};
IN_PROC_BROWSER_TEST_F(NativeVideoControllerTest, ClosePausesRealPlayer) {
  ASSERT_NO_FATAL_FAILURE(Open());
  Click(PCVideoPiPClose);
  EXPECT_TRUE(content::EvalJs(
                  contents(),
                  "new Promise(r => { const v=document.querySelector('video'); "
                  "if(v.paused)r(true);else "
                  "v.addEventListener('pause',()=>r(true),{once:true}); })")
                  .ExtractBool());
  EXPECT_FALSE(controller()->GetWindowForTesting()->IsVisible());
}
IN_PROC_BROWSER_TEST_F(NativeVideoControllerTest,
                       HideKeepsPlaybackAndOriginalContents) {
  ASSERT_NO_FATAL_FAILURE(Open());
  auto* original = contents();
  // The real controller controls capability; the native UI doesn't fabricate
  // it.
  controller()->GetWindowForTesting()->SetHidePictureInPictureButtonVisibility(
      true);
  Click(PCVideoPiPMinimize);
  EXPECT_EQ(original, contents());
  EXPECT_FALSE(
      content::EvalJs(contents(), "document.querySelector('video').paused")
          .ExtractBool());
  EXPECT_FALSE(controller()->GetWindowForTesting()->IsVisible());
}
IN_PROC_BROWSER_TEST_F(NativeVideoControllerTest,
                       NativeCloseSynchronouslyDestroysOwnedOverlay) {
  ASSERT_NO_FATAL_FAILURE(Open());
  NSPanel* panel = application_.presenter.panel;
  [panel close];
  EXPECT_EQ(nullptr, controller()->GetWindowForTesting());
  EXPECT_FALSE(panel.visible);
  EXPECT_EQ(nil, application_.presenter);
}
IN_PROC_BROWSER_TEST_F(NativeVideoControllerTest,
                       ReentryUsesSameWindowAndVideoView) {
  ASSERT_NO_FATAL_FAILURE(Open());
  NSView* original = application_.presenter.videoView;
  auto* window = controller()->GetWindowForTesting();
  ASSERT_TRUE(content::ExecJs(contents(), "document.exitPictureInPicture()"));
  ASSERT_TRUE(content::ExecJs(
      contents(), "document.querySelector('video').requestPictureInPicture()"));
  EXPECT_EQ(window, controller()->GetWindowForTesting());
  EXPECT_EQ(original, application_.presenter.videoView);
}

IN_PROC_BROWSER_TEST_F(NativeVideoControllerTest,
                       ReturnTargetsOriginalContentsWithoutPause) {
  ASSERT_NO_FATAL_FAILURE(Open());
  auto* original = contents();
  Click(PCVideoPiPReturn);
  EXPECT_EQ(original, contents());
  EXPECT_FALSE(
      content::EvalJs(contents(), "document.querySelector('video').paused")
          .ExtractBool());
  EXPECT_FALSE(controller()->GetWindowForTesting()->IsVisible());
}

IN_PROC_BROWSER_TEST_F(NativeVideoControllerTest,
                       NativeResizeNotifiesActualSession) {
  ASSERT_NO_FATAL_FAILURE(Open());
  ASSERT_TRUE(content::ExecJs(contents(), R"(
    window.pipResize = new Promise(resolve => {
      pipWindow.addEventListener('resize', () => {
        resolve([pipWindow.width, pipWindow.height]);
      }, {once:true});
    });
  )"));
  [application_.presenter.panel setContentSize:NSMakeSize(640, 360)];
  EXPECT_EQ(
      "640,360",
      content::EvalJs(contents(), "pipResize.then(size => size.join(','))"));
}

IN_PROC_BROWSER_TEST_F(NativeVideoControllerTest,
                       ActualCompositorHostFillsVideoViewBeforeAndAfterResize) {
  ASSERT_NO_FATAL_FAILURE(Open());
  NSView* video = application_.presenter.videoView;
  ASSERT_TRUE(video.layer);
  ASSERT_EQ(1u, video.layer.sublayers.count);
  CALayer* flipped = video.layer.sublayers.firstObject;
  ASSERT_TRUE(flipped.geometryFlipped);
  ASSERT_GT(NSWidth(video.bounds), 0);
  ASSERT_GT(NSHeight(video.bounds), 0);
  // This is the real native overlay's DisplayCALayerTree container, not a
  // test-created layer tree. The old backing-layer ordering left width zero.
  EXPECT_TRUE(CGRectEqualToRect(flipped.bounds, video.layer.bounds));
  [application_.presenter.panel setContentSize:NSMakeSize(640, 360)];
  EXPECT_TRUE(CGRectEqualToRect(flipped.bounds, video.layer.bounds));
  ASSERT_TRUE(content::ExecJs(contents(), "document.exitPictureInPicture()"));
  ASSERT_TRUE(content::ExecJs(
      contents(), "document.querySelector('video').requestPictureInPicture()"));
  EXPECT_EQ(video, application_.presenter.videoView);
  EXPECT_EQ(flipped, video.layer.sublayers.firstObject);
  EXPECT_TRUE(CGRectEqualToRect(flipped.bounds, video.layer.bounds));
}
