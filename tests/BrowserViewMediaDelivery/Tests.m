#import "ParcEngine.h"

#include "../Support/TestFailure.h"
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

int main(void) {
  @autoreleasepool {
    PCNativePage* page = [[PCNativePage alloc] initForTest];
    page.testTitle = @"Track";
    PCBrowserView* view = [[PCBrowserView alloc] initWithFrame:NSZeroRect adoptingNativePage:page];
    Delegate* delegate = [Delegate new];
    view.delegate = delegate;
    PARC_EXPECT(delegate.media == 1 && delegate.titles == 1);

    [(id<PCNativePageObserver>)view nativePageDidChange:page];
    PARC_EXPECT(delegate.media == 1 && delegate.titles == 1);

    page.testMediaRevision = 1;
    [(id<PCNativePageObserver>)view nativePageDidChange:page];
    PARC_EXPECT(delegate.media == 2 && delegate.titles == 1);
    [(id<PCNativePageObserver>)view nativePageDidChange:page];
    PARC_EXPECT(delegate.media == 2);

    page.testTitle = @"Next Track";
    [(id<PCNativePageObserver>)view nativePageDidChange:page];
    PARC_EXPECT(delegate.media == 2 && delegate.titles == 2);

    Delegate* next = [Delegate new];
    view.delegate = next;
    PARC_EXPECT(next.media == 1);
  }
  printf("Browser view media delivery: checks passed\n");
  return 0;
}
