#import "ParcNativePointer.h"
#import "../../../Sources/ParcEngine/VideoPiPWindow.m"

static BOOL gBackgroundCursor;
static int TestConnection(void) { return 1; }
static int SetConnectionProperty(int owner, int target, CFStringRef property, CFTypeRef value) {
  if (CFEqual(property, CFSTR("SetsCursorInBackground"))) gBackgroundCursor = CFEqual(value, kCFBooleanTrue);
  return 0;
}

@implementation ParcNativePointerEnvironment {
  NSCursor* _cursor;
}
@synthesize cursor = _cursor;
@synthesize location = _location;
@synthesize liveResize = _liveResize;
- (instancetype)init {
  if (!(self = [super init])) return nil;
  _cursor = NSCursor.arrowCursor;
  _location = NSMakePoint(400, 300);
  gBackgroundCursor = NO;
  return self;
}
- (BOOL)backgroundCursorEnabled { return gBackgroundCursor; }
- (void)setCursor:(NSCursor*)cursor { _cursor = cursor; }
- (NSPoint)mouseLocation { return _location; }
- (id)addLocalMonitorForMask:(NSEventMask)mask handler:(NSEvent* (^)(NSEvent*))handler { return [handler copy]; }
- (id)addGlobalMonitorForMask:(NSEventMask)mask handler:(void (^)(NSEvent*))handler { return [handler copy]; }
- (void)removeMonitor:(id)monitor {}
- (void*)symbolNamed:(const char*)name {
  if (!strcmp(name, "CGSMainConnectionID")) return (void*)&TestConnection;
  if (!strcmp(name, "CGSSetConnectionProperty")) return (void*)&SetConnectionProperty;
  return NULL;
}
- (BOOL)isWindowInLiveResize:(NSWindow*)window { return _liveResize; }
@end
