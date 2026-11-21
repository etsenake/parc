#import "ParcNativePointer.h"
#import <QuartzCore/QuartzCore.h>
#import <dlfcn.h>

static NSCursor* selectedCursor;
static BOOL backgroundCursor;

NSCursor* ParcNativeCursor(void) { return selectedCursor; }
BOOL ParcNativeBackgroundCursorEnabled(void) { return backgroundCursor; }
NSPoint ParcNativePointerLocation(void) { return NSMakePoint(400, 300); }

void ParcNativeResetPointer(void) {
  selectedCursor = NSCursor.arrowCursor;
  backgroundCursor = NO;
}

@implementation NSCursor (ParcNativePointer)
- (void)parcSetCursor { selectedCursor = self; }
@end

@implementation NSEvent (ParcNativePointer)
+ (NSPoint)parcPointerLocation { return ParcNativePointerLocation(); }
+ (id)parcAddLocalMonitor:(NSEventMask)mask handler:(NSEvent* (^)(NSEvent*))handler { return [handler copy]; }
+ (id)parcAddGlobalMonitor:(NSEventMask)mask handler:(void (^)(NSEvent*))handler { return [handler copy]; }
+ (void)parcRemoveMonitor:(id)monitor {}
@end

static int TestConnection(void) { return 1; }
static int SetConnectionProperty(int owner, int target, CFStringRef property, CFTypeRef value) {
  if (CFEqual(property, CFSTR("SetsCursorInBackground"))) backgroundCursor = CFEqual(value, kCFBooleanTrue);
  return 0;
}

static void* PointerSymbol(void* handle, const char* name) {
  if (!strcmp(name, "CGSMainConnectionID")) return (void*)&TestConnection;
  if (!strcmp(name, "CGSSetConnectionProperty")) return (void*)&SetConnectionProperty;
  return NULL;
}

#define set parcSetCursor
#define mouseLocation parcPointerLocation
#define dlsym PointerSymbol
#define addLocalMonitorForEventsMatchingMask parcAddLocalMonitor
#define addGlobalMonitorForEventsMatchingMask parcAddGlobalMonitor
#define removeMonitor parcRemoveMonitor
#import "../../../Sources/ParcEngine/VideoPiPWindow.m"
