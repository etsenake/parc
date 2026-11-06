#import "content_drop_bridge.h"
#import "ui/base/cocoa/content_drop_router.h"

id<PCNativeContentDropRouting> PCCreateNativeContentDropRouter(NSView *view) {
  NSCAssert(NSThread.isMainThread, @"Native content drop routing requires the main thread");
  return [[PCNativeContentDropRouter alloc] initWithView:view];
}
