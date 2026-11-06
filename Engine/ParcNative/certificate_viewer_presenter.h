// Copyright 2026 Parc contributors.
#pragma once
#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN
// Real SecurityInterface certificate details, not a certificate trust decision.
// The owner retains this object; invalidate is terminal and idempotent. The
// presenter additionally retains itself until the OS sheet's didEnd callback.
@interface PCServerCertificatePresenter : NSObject
- (instancetype)initWithPage:(NSView*)page
                      window:(NSWindow*)window
                certificates:(NSArray*)certificates
                    validate:(BOOL (^)(void))validate
                    finished:(void (^)(void))finished;
@property(nonatomic, readonly, nullable) NSWindow* panel;
- (void)show;
- (void)invalidate;
@end
NS_ASSUME_NONNULL_END
