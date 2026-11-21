#import "ParcNativeWindows.h"

#import <dlfcn.h>
#import <objc/runtime.h>

static const void* bundleBase;
static const void* kVirtualVisible = &kVirtualVisible;

static BOOL CalledFromTestBundle(void* address) {
  Dl_info info;
  return dladdr(address, &info) && info.dli_fbase == bundleBase;
}

typedef BOOL (*VisibleIMP)(id, SEL);
typedef void (*OrderIMP)(id, SEL, id);
typedef void (*OrderRelativeIMP)(id, SEL, NSWindowOrderingMode, NSInteger);
static VisibleIMP realIsVisible;
static OrderIMP realOrderOut;

static void SetVirtualVisible(NSWindow* window, BOOL visible) {
  objc_setAssociatedObject(window, kVirtualVisible, visible ? @YES : nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static BOOL VirtualVisible(NSWindow* window) {
  if ([objc_getAssociatedObject(window, kVirtualVisible) boolValue]) return YES;
  NSWindow* parent = window.sheetParent;
  return parent && VirtualVisible(parent);
}

BOOL ParcNativeWindowOrderedForReal(NSWindow* window) {
  return realIsVisible(window, @selector(isVisible));
}

void ParcNativeMarkVisible(NSWindow* window) {
  SetVirtualVisible(window, YES);
}

NSWindow* ParcNativeOffscreenWindow(NSRect frame, NSWindowStyleMask style) {
  NSWindow* window = [[NSWindow alloc] initWithContentRect:frame
                                                 styleMask:style
                                                   backing:NSBackingStoreBuffered
                                                     defer:NO];
  window.releasedWhenClosed = NO;
  return window;
}

static void ReplaceOrdering(SEL selector) {
  Method method = class_getInstanceMethod(NSWindow.class, selector);
  IMP original = method_getImplementation(method);
  method_setImplementation(method, imp_implementationWithBlock(^(NSWindow* window, id sender) {
    if (CalledFromTestBundle(__builtin_return_address(0))) {
      SetVirtualVisible(window, YES);
      return;
    }
    ((OrderIMP)original)(window, selector, sender);
  }));
}

__attribute__((constructor)) static void InstallParcNativeWindows(void) {
  Dl_info info;
  if (dladdr((const void*)&InstallParcNativeWindows, &info)) bundleBase = info.dli_fbase;

  Method visible = class_getInstanceMethod(NSWindow.class, @selector(isVisible));
  realIsVisible = (VisibleIMP)method_getImplementation(visible);
  method_setImplementation(visible, imp_implementationWithBlock(^BOOL(NSWindow* window) {
    BOOL real = realIsVisible(window, @selector(isVisible));
    return real || (CalledFromTestBundle(__builtin_return_address(0)) && VirtualVisible(window));
  }));

  ReplaceOrdering(@selector(orderFront:));
  ReplaceOrdering(@selector(makeKeyAndOrderFront:));
  Method regardless = class_getInstanceMethod(NSWindow.class, @selector(orderFrontRegardless));
  IMP realRegardless = method_getImplementation(regardless);
  method_setImplementation(regardless, imp_implementationWithBlock(^(NSWindow* window) {
    if (CalledFromTestBundle(__builtin_return_address(0))) {
      SetVirtualVisible(window, YES);
      return;
    }
    ((void (*)(id, SEL))realRegardless)(window, @selector(orderFrontRegardless));
  }));

  Method relative = class_getInstanceMethod(NSWindow.class, @selector(orderWindow:relativeTo:));
  IMP realRelative = method_getImplementation(relative);
  method_setImplementation(relative, imp_implementationWithBlock(^(NSWindow* window, NSWindowOrderingMode mode,
                                                                   NSInteger other) {
    if (CalledFromTestBundle(__builtin_return_address(0))) {
      SetVirtualVisible(window, mode != NSWindowOut);
      if (mode != NSWindowOut) return;
    }
    ((OrderRelativeIMP)realRelative)(window, @selector(orderWindow:relativeTo:), mode, other);
  }));

  Method out = class_getInstanceMethod(NSWindow.class, @selector(orderOut:));
  realOrderOut = (OrderIMP)method_getImplementation(out);
  method_setImplementation(out, imp_implementationWithBlock(^(NSWindow* window, id sender) {
    SetVirtualVisible(window, NO);
    realOrderOut(window, @selector(orderOut:), sender);
  }));

  Method close = class_getInstanceMethod(NSWindow.class, @selector(close));
  IMP realCloseImp = method_getImplementation(close);
  method_setImplementation(close, imp_implementationWithBlock(^(NSWindow* window) {
    SetVirtualVisible(window, NO);
    ((void (*)(id, SEL))realCloseImp)(window, @selector(close));
  }));
}
