// Copyright 2026 Parc contributors.
#pragma once
#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, PCNativeStatusLinkOutcome) {
  PCNativeStatusLinkOutcomeNone,
  PCNativeStatusLinkOutcomeNewBackgroundTab,
  PCNativeStatusLinkOutcomeNewForegroundTab,
  PCNativeStatusLinkOutcomeNewWindow,
  PCNativeStatusLinkOutcomePeek,
  PCNativeStatusLinkOutcomeSplitView,
};

// One real page's click-through status overlay. The owner controls attachment
// and resets it before navigation, hiding, reparenting or page destruction.
// Does not own a window, handle renderer input, or navigate a displayed URL.
// The theme overlay comes from the window delegate when it implements
// PCNativeStatusTextThemeSource (native_appkit_bridge.h).
@interface PCNativeStatusTextController : NSObject
- (instancetype)initWithPage:(NSView*)page validate:(BOOL (^)(void))validate;
// The outcome the shell would give a click on this hovered link with these
// modifier flags (Shift/Control/Option/Command only). Only link text (a URL
// with a scheme and a host, or mailto) is asked. Nil or None keeps the plain
// text. Queried on text and modifier changes; it must be a pure state read.
@property(nonatomic, copy, nullable)
    PCNativeStatusLinkOutcome (^linkOutcome)(NSEventModifierFlags flags, NSURL* url);
- (void)setAttached:(BOOL)attached;
- (void)updateText:(NSString*)text;
- (void)reset;
- (void)invalidate;
@end

NS_ASSUME_NONNULL_END
