// Copyright 2026 Parc contributors.
#pragma once
#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN
@protocol PCNativePresentation, PCNativeScheduling;

typedef NS_ENUM(NSInteger, PCNativeStatusLinkOutcome) {
  PCNativeStatusLinkOutcomeNone,
  PCNativeStatusLinkOutcomeNewBackgroundTab,
  PCNativeStatusLinkOutcomeNewForegroundTab,
  PCNativeStatusLinkOutcomeNewWindow,
  PCNativeStatusLinkOutcomePeek,
  PCNativeStatusLinkOutcomeSplitView,
  PCNativeStatusLinkOutcomeThisPeek,
};

@interface PCNativeStatusTextController : NSObject
- (instancetype)initWithPage:(NSView*)page validate:(BOOL (^)(void))validate;
@property(nonatomic, strong) id<PCNativePresentation> presentation;
@property(nonatomic, strong) id<PCNativeScheduling> scheduler;
@property(nonatomic, copy, nullable)
    PCNativeStatusLinkOutcome (^linkOutcome)(NSEventModifierFlags flags, NSURL* url);
- (void)setAttached:(BOOL)attached;
- (void)updateText:(NSString*)text;
- (void)setNeedsLinkOutcomeRefresh;
- (void)reset;
- (void)invalidate;
@end

NS_ASSUME_NONNULL_END
