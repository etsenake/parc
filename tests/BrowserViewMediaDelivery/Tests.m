// PCBrowserView's change fan-out (Sources/ParcEngine/ParcEngine.m) over a
// stand-in page: a media-only change, such as play becoming pause, reaches the
// delegate while title, URL and loading stay the same. No engine or browser.
#import "ParcEngine.h"

#include <assert.h>
#include <stdio.h>

// The engine's classes and entry points, as far as the facade's change path
// and its link need them.
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
    assert(delegate.media == 1 && delegate.titles == 1);  // A new delegate reads the current state.

    [(id<PCNativePageObserver>)view nativePageDidChange:page];
    assert(delegate.media == 1 && delegate.titles == 1);  // Nothing changed: no callback.

    // The engine bumps the revision when it publishes a play/pause flip.
    page.testMediaRevision = 1;
    [(id<PCNativePageObserver>)view nativePageDidChange:page];
    assert(delegate.media == 2 && delegate.titles == 1);
    [(id<PCNativePageObserver>)view nativePageDidChange:page];
    assert(delegate.media == 2);

    page.testTitle = @"Next Track";
    [(id<PCNativePageObserver>)view nativePageDidChange:page];
    assert(delegate.media == 2 && delegate.titles == 2);  // A title change is not a media change.

    Delegate* next = [Delegate new];
    view.delegate = next;
    assert(next.media == 1);  // A new delegate also learns the current media state.
  }
  printf("Browser view media delivery: checks passed\n");
  return 0;
}
