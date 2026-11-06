// Public engine boundary for local Note/Easel native drag receivers.
#pragma once
#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN
@protocol PCNativeContentDropRouting;

// Returns the same ui/base router used by Chromium's native content container.
// Its original view/window/gesture lifetime remains authoritative.
FOUNDATION_EXPORT __attribute__((visibility("default")))
NS_SWIFT_UI_ACTOR id<PCNativeContentDropRouting>
PCCreateNativeContentDropRouter(NSView *view);
NS_ASSUME_NONNULL_END
