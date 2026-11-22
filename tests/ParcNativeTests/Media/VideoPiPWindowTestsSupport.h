#pragma once

#import <Cocoa/Cocoa.h>
#import "ParcNativeTest.h"
#import "ParcNativeClock.h"
#import "ParcNativePointer.h"
#include <stdio.h>

#import "VideoPiPWindow.h"
#define EXPECT(condition) PARC_CHECK(condition)
static inline void VideoPiPWindowTestsSendClick(NSControl* control) {
  if (!control.enabled) return;
  [control.cell setNextState];
  [control sendAction:control.action to:control.target];
}

static inline PCVideoPiPPresenter* VideoPiPWindowTestsOffscreen(PCVideoPiPPresenter* presenter) NS_RETURNS_RETAINED {
  presenter.presentation = ParcNativePresentation();
  presenter.scheduler = ParcNativeScheduler();
  return presenter;
}
static inline NSButton* VideoPiPWindowTestsButton(NSView* view, NSInteger tag) {
  for (NSView* child in view.subviews) {
    if ([child isKindOfClass:NSButton.class] && child.tag == tag) {
      return (NSButton*)child;
    }
    NSButton* result = VideoPiPWindowTestsButton(child, tag);
    if (result) {
      return result;
    }
  }
  return nil;
}
static inline NSSlider* VideoPiPWindowTestsSlider(NSView* view) {
  for (NSView* child in view.subviews) {
    if ([child isKindOfClass:NSSlider.class]) {
      return (NSSlider*)child;
    }
    NSSlider* nested = VideoPiPWindowTestsSlider(child);
    if (nested) {
      return nested;
    }
  }
  return nil;
}
static inline BOOL VideoPiPWindowTestsNear(NSRect a, NSRect b) {
  return fabs(NSMinX(a) - NSMinX(b)) < 0.01 && fabs(NSMinY(a) - NSMinY(b)) < 0.01 &&
         fabs(NSWidth(a) - NSWidth(b)) < 0.01 &&
         fabs(NSHeight(a) - NSHeight(b)) < 0.01;
}
static inline BOOL VideoPiPWindowTestsAspect(NSRect rect, CGFloat aspect) {
  return fabs(NSWidth(rect) / NSHeight(rect) - aspect) / aspect < 0.01;
}
static inline NSView* VideoPiPWindowTestsHost(NSButton* button) {
  if (@available(macOS 26.0, *)) {
    for (NSView* host = button; host; host = host.superview) {
      if ([host isKindOfClass:NSGlassEffectView.class]) {
        return host;
      }
    }
  }
  return button;
}
static inline void VideoPiPWindowTestsPlaceUnderCursor(NSPanel* panel, NSPoint mouse) {
  NSRect frame = panel.frame;
  frame.origin = NSMakePoint(mouse.x - frame.size.width * 0.5,
                             mouse.y - frame.size.height * 0.5);
  [panel setFrame:frame display:YES];
}
static inline void VideoPiPWindowTestsHover(PCVideoPiPPresenter* presenter, ParcNativePointerEnvironment* pointer) {
  VideoPiPWindowTestsPlaceUnderCursor(presenter.panel, pointer.location);
  [presenter.panel.contentView mouseEntered:[NSEvent new]];
  ParcNativeAdvance(0.05);
  [presenter.panel.contentView mouseMoved:[NSEvent new]];
  ParcNativeAdvance(0.02);
}
static inline NSView* VideoPiPWindowTestsCaptions(NSView* content) {
  NSView* captions = nil;
  for (NSView* child in content.subviews) {
    if ([NSStringFromClass(child.class) isEqual:@"PCVideoPiPCaptions"]) captions = child;
  }
  return captions;
}
static inline NSImage* VideoPiPWindowTestsCue(void) {
  return [NSImage imageWithSize:NSMakeSize(512, 36)
                        flipped:NO
                 drawingHandler:^BOOL(NSRect rect) {
                   return YES;
                 }];
}


@interface VideoPiPWindowTestsSupport : ParcNativeTestCase {
@protected
  NSView* _video;
  PCVideoPiPPresenter* _presenter;
  ParcNativePointerEnvironment* _pointer;
  int _actions;
  int _changes;
  PCVideoPiPAction _last;
}
- (NSView*)content;
- (void)showHovering;
- (NSButton*)hoveredPlayButton;
@end
