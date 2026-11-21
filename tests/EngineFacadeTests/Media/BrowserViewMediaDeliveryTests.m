#import "ParcEngine.h"

#import "ParcNativeTest.h"
#include <stdio.h>

@interface PCNativePage (Test)
- (instancetype)initForTest;
@property(nonatomic) uint64_t testMediaRevision;
@property(nonatomic, copy) NSString* testTitle;
@end
@implementation PCNativePage {
  uint64_t _revision;
  NSString* _title;
  __weak id<PCNativePageObserver> _observer;
}
- (instancetype)initForTest { return [super init]; }
- (uint64_t)testMediaRevision { return _revision; }
- (void)setTestMediaRevision:(uint64_t)value { _revision = value; }
- (NSString*)testTitle { return _title; }
- (void)setTestTitle:(NSString*)value { _title = [value copy]; }
- (uint64_t)mediaControlsRevision { return _revision; }
- (NSString*)title { return _title ?: @""; }
- (NSString*)profilePath { return @"/profile"; }
- (NSURL*)URL { return [NSURL URLWithString:@"https://music.example/"]; }
- (BOOL)loading { return NO; }
- (BOOL)canGoBack { return NO; }
- (BOOL)canGoForward { return NO; }
- (PCNativeCaptureState*)captureState { return nil; }
- (PCNativeRendererCrash*)rendererCrash { return nil; }
- (NSColor*)developerModeTint { return nil; }
- (id<PCNativePageObserver>)observer { return _observer; }
- (void)setObserver:(id<PCNativePageObserver>)observer { _observer = observer; }
@end
@implementation PCNativeBrowserApplication
@end
@implementation PCNativeBrowserWindow
@end
int parc_engine_initialize(int argc, char** argv, const char* a, const char* b, const char* c,
                           const char* d, int* e) { return 0; }
void parc_engine_run_message_loop(void) {}
int parc_engine_request_quit_when_idle(void (*ready)(void*), void* context) { return 0; }
int parc_engine_shutdown_if_idle(void) { return 0; }

@interface Delegate : NSObject <PCBrowserViewDelegate>
@property(nonatomic) int media, titles;
@end
@implementation Delegate
- (void)browserViewDidChangeMedia:(PCBrowserView*)view { self.media += 1; }
- (void)browserView:(PCBrowserView*)view didChangeTitle:(NSString*)title { self.titles += 1; }
@end

@interface BrowserViewMediaDeliveryTests : ParcNativeTestCase
@end

@implementation BrowserViewMediaDeliveryTests {
  PCNativePage* _page;
  PCBrowserView* _view;
  Delegate* _delegate;
}

- (void)setUp {
  [super setUp];
  _page = [[PCNativePage alloc] initForTest];
  _page.testTitle = @"Track";
  _view = [[PCBrowserView alloc] initWithFrame:NSZeroRect adoptingNativePage:_page];
  _delegate = [Delegate new];
  _view.delegate = _delegate;
}

- (void)notifyChange {
  [(id<PCNativePageObserver>)_view nativePageDidChange:_page];
}

- (void)testANewDelegateReceivesTheCurrentMediaAndTitle {
  PARC_CHECK(_delegate.media == 1 && _delegate.titles == 1);
}

- (void)testAnUnchangedPageDoesNotNotifyAgain {
  [self notifyChange];
  PARC_CHECK(_delegate.media == 1 && _delegate.titles == 1);
}

- (void)testANewMediaRevisionOnlyDeliversMedia {
  _page.testMediaRevision = 1;
  [self notifyChange];
  PARC_CHECK(_delegate.media == 2 && _delegate.titles == 1);
}

- (void)testARepeatedMediaRevisionIsDeliveredOnce {
  _page.testMediaRevision = 1;
  [self notifyChange];
  [self notifyChange];
  PARC_CHECK(_delegate.media == 2);
}

- (void)testATitleChangeOnlyDeliversTheTitle {
  _page.testTitle = @"Next Track";
  [self notifyChange];
  PARC_CHECK(_delegate.media == 1 && _delegate.titles == 2);
}

- (void)testAReplacementDelegateReceivesTheCurrentMedia {
  Delegate* next = [Delegate new];
  _view.delegate = next;
  PARC_CHECK(next.media == 1);
}

@end
